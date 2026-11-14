class_name TycoonHUD
extends Control
## Main-screen HUD of Cometworks (scenes/tycoon/ui/tycoon_hud.tscn), "Aurora de
## observatório" (GDD section 22): top instrument strip, left rail, race board with the
## Tail Radio, project / construction strips along the bottom, the one primary button and
## the lot panel. Everything visual is in the scene: lists are filled by duplicating the
## hidden templates there (RaceRowTemplate, NewsTemplate, StripTemplate), so their look is
## edited in the editor. This script only fills data.

signal build_requested(lot_id: String)
signal screen_opened(screen_name: String)
signal screen_closed(screen_name: String)

const ICONS := "res://ui/cometworks/icons/%s.svg"
const SCREENS := "res://scenes/tycoon/ui/screens/%s.tscn"

var state: TycoonState
var clock: TycoonClock
var lot_id := ""
var _hint_default := ""
var _hint_timer := 0.0


func _ready() -> void:
	%Pause.pressed.connect(func() -> void: _set_speed(0))
	%S1.pressed.connect(func() -> void: _set_speed(1))
	%S2.pressed.connect(func() -> void: _set_speed(2))
	%S3.pressed.connect(func() -> void: _set_speed(3))
	%Close.pressed.connect(close_lot)
	%BuildButton.pressed.connect(func() -> void:
		if lot_id != "":
			build_requested.emit(lot_id))
	%NewProject.pressed.connect(func() -> void:
		if not open_screen("new_project"):
			flash_hint(tr("TY_SOON_PROJECT")))
	for b in %VBox.get_children():
		if b is Button and b.name != "Build":
			var btn := b as Button
			var screen := String(btn.name).to_snake_case()
			btn.pressed.connect(func() -> void:
				if not open_screen(screen):
					_mark_rail(current_screen())
					flash_hint(tr("TY_SOON") % tr(btn.tooltip_text)))
	%Build.toggled.connect(func(on: bool) -> void:
		flash_hint(tr("TY_BUILD_HINT") if on else _hint_default, 6.0 if on else 0.1))
	_hint_default = tr("TY_CAMPUS_HINT")
	%Hint.text = _hint_default


func bind(s: TycoonState, c: TycoonClock) -> void:
	state = s
	clock = c
	state.changed.connect(refresh)
	clock.speed_changed.connect(_press_speed)
	_press_speed(clock.speed)
	refresh()


func _process(delta: float) -> void:
	if clock:
		(%WeekBar as CwSegmentBar).value = clock.week_fraction()
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			%Hint.text = _hint_default


func _set_speed(s: int) -> void:
	if clock:
		clock.set_speed(s)


func _press_speed(s: int) -> void:
	var btns: Array[Button] = [%Pause, %S1, %S2, %S3]
	for i in btns.size():
		btns[i].set_pressed_no_signal(i == clampi(s, 0, 3))


func flash_hint(text: String, seconds := 2.5) -> void:
	if %Hint.text != text:
		CwMotion.poke(%Hint)
	%Hint.text = text
	_hint_timer = seconds


# ------------------------------------------------------------ refresh
func refresh() -> void:
	if state == null:
		return
	%Name.text = state.agency_name
	var emblem := TycoonLeader.agency_emblem(state)   # the leader's emblem in the agency colour
	if emblem:
		%Mark.texture = emblem
		%Mark.self_modulate = TycoonLeader.agency_color(state, CwPalette.IGNITION)
	%DateValue.text = "%02d · %02d" % [state.year(), state.week()]
	%EraValue.text = tr("TY_ERA_%d" % state.era())
	# number labels count to their new value when they carry a CwNumberTicker (scene)
	CwNumberTicker.show(%CashValue, state.cash, fmt_cr)
	%CashValue.add_theme_color_override("font_color", CwPalette.MONEY_NEG if state.cash < 0.0 else CwPalette.MONEY_POS)
	CwNumberTicker.show(%RepValue, state.reputation, fmt_int)
	CwNumberTicker.show(%HypeValue, state.hype, fmt_int)
	var left := state.comet_weeks_left()
	var comet_was: String = %CometValue.text
	%CometValue.text = "T− %02da %02ds" % [left / state.weeks_per_year(), left % state.weeks_per_year()]
	if %CometValue.text != comet_was:
		CwMotion.poke(%CometValue)
	_fill_race()
	_fill_news()
	_fill_strips()
	if lot_id != "":
		show_lot(lot_id)


## Keeps `count` visible copies of `template` (a hidden node in the scene) in its parent.
static func _copies(template: Control, count: int) -> Array[Control]:
	var parent := template.get_parent()
	var out: Array[Control] = []
	for c in parent.get_children():
		if c != template and c.has_meta("from_template"):
			out.append(c)
	while out.size() < count:
		var c := template.duplicate() as Control
		c.set_meta("from_template", true)
		c.visible = true
		parent.add_child(c)
		out.append(c)
	while out.size() > count:
		out.pop_back().queue_free()
	return out


func _fill_race() -> void:
	var board := state.race_board()
	var rows := _copies(%RaceRowTemplate, board.size())
	for i in board.size():
		var r: Dictionary = board[i]
		var col: Color = r["color"]
		var name_l := rows[i].get_node("Head/Name") as Label
		name_l.text = String(r["name"]) if r.has("name") else tr(String(r["name_key"]))
		name_l.add_theme_color_override("font_color", CwPalette.TEXT if r["player"] else CwPalette.TEXT_DIM)
		(rows[i].get_node("Head/Dot") as Control).self_modulate = col
		# the player's row wears the agency emblem instead of the dot
		var emblem := TycoonLeader.agency_emblem(state) if r["player"] else null
		var emblem_r := rows[i].get_node_or_null("Head/Emblem") as TextureRect
		if emblem_r:
			emblem_r.visible = emblem != null
			emblem_r.texture = emblem
			emblem_r.self_modulate = col
			(rows[i].get_node("Head/Dot") as Control).visible = emblem == null
		var count_l := rows[i].get_node("Head/Count") as Label
		count_l.text = "%d/%d" % [roundi(float(r["progress"]) * state.milestones_total()), state.milestones_total()]
		count_l.add_theme_color_override("font_color", CwPalette.ink(col.lerp(CwPalette.TEXT, 0.35)))
		var bar := rows[i].get_node("Bar") as CwSegmentBar
		bar.segments = state.milestones_total()
		bar.color = col
		bar.value = float(r["progress"])


func _fill_news() -> void:
	var n := mini(state.news.size(), 3)
	var lines := _copies(%NewsTemplate, n)
	for i in n:
		var l := lines[i] as Label
		var t := news_text(state.news[i])
		if l.text != t:
			l.text = t
			CwMotion.poke(l)   # the line's CwAppear slides it in
		l.add_theme_color_override("font_color", CwPalette.TEXT if i == 0 else CwPalette.TEXT_DIM)


static func news_text(n: Dictionary) -> String:
	var args: Array = []
	for a in n.get("args", []):
		args.append(TranslationServer.translate(String(a)) if a is String and String(a).begins_with("TY_") else a)
	var t := TranslationServer.translate(String(n.get("key", "")))
	return t % args if not args.is_empty() else t


## Bottom strips: buildings under construction, then mission projects (E1).
func _fill_strips() -> void:
	var items: Array[Dictionary] = []
	for lid: String in state.buildings:
		var b: Dictionary = state.buildings[lid]
		var wl := int(b.get("weeks_left", 0))
		if wl <= 0:
			continue
		var name_key := String(state.building_type(b["kind"]).get("name_key", ""))
		var total := maxi(int(b.get("total_weeks", wl)), wl)
		items.append({"title": tr("TY_STRIP_BUILD") % [tr(name_key), int(b["target"])],
			"sub": tr("TY_WEEKS_LEFT") % wl, "progress": 1.0 - float(wl) / total, "color": CwPalette.AURORA_VIOLET})
	for p in state.projects:
		items.append({"title": String(p.get("code", "")), "sub": String(p.get("phase", "")),
			"progress": float(p.get("progress", 0.0)), "color": p.get("color", CwPalette.AURORA_TEAL)})
	if items.is_empty():
		items.append({"title": tr("TY_NO_PROJECTS"), "sub": tr("TY_NO_PROJECTS_HINT"), "progress": -1.0,
			"color": CwPalette.LINE})
	var strips := _copies(%StripTemplate, items.size())
	for i in items.size():
		var it := items[i]
		var pc := strips[i] as PanelContainer
		# a few strips get room for their whole title; a full row shares the bar
		pc.custom_minimum_size.x = 300.0 if items.size() <= 3 else (%StripTemplate as Control).custom_minimum_size.x
		# the strip's style comes from the theme (CwStrip); only the tab colour changes per strip
		var st := pc.get_theme_stylebox("panel").duplicate() as CwPanelStyle
		if st:
			st.tab_color = it["color"]
			pc.add_theme_stylebox_override("panel", st)
		(pc.get_node("VBox/Title") as Label).text = it["title"]
		(pc.get_node("VBox/Sub") as Label).text = it["sub"]
		var bar := pc.get_node("VBox/Bar") as CwSegmentBar
		bar.visible = float(it["progress"]) >= 0.0
		bar.color = it["color"]
		bar.value = maxf(float(it["progress"]), 0.0)


# ------------------------------------------------------------ lot panel
func show_lot(id: String) -> void:
	if state == null or id == "":
		close_lot()
		return
	lot_id = id
	var kind := state.lot_kind(id)
	var bt := state.building_type(kind)
	var b := state.building(id)
	var lv := int(b.get("level", 0))
	var wl := int(b.get("weeks_left", 0))
	%LotPanel.visible = true
	%Icon.texture = load(ICONS % String(bt.get("icon", "hq")))
	%LotName.text = tr(String(bt.get("name_key", "")))
	%LotLevel.text = tr("TY_LOT_FOR_SALE") if lv == 0 and wl == 0 else tr("TY_LEVEL") % lv
	(%LevelBar as CwSegmentBar).value = lv / 3.0
	%Desc.text = tr(String(bt.get("desc_key", "")))
	var nx := state.next_level(id)
	var btn: Button = %BuildButton
	btn.tooltip_text = ""
	if wl > 0:
		%CostValue.text = tr("TY_WEEKS_LEFT") % wl
		btn.text = tr("TY_UNDER_CONSTRUCTION")
		btn.disabled = true
	elif nx.is_empty():
		%CostValue.text = "—"
		btn.text = tr("TY_MAX_LEVEL")
		btn.disabled = true
	else:
		%CostValue.text = "%s · %s" % [fmt_cr(nx["cost"]), tr("TY_WEEKS") % int(nx["weeks"])]
		btn.text = tr("TY_BUILD") if lv == 0 else tr("TY_UPGRADE") % int(nx["level"])
		btn.disabled = not state.can_build(id)
		if btn.disabled:
			btn.tooltip_text = tr("TY_NO_CASH")


func close_lot() -> void:
	lot_id = ""
	%LotPanel.visible = false


# ------------------------------------------------------------ screens
## Opens a full screen (crew, research, contracts, map, race, book, finance, settings,
## new_project, ...): the scene res://scenes/tycoon/ui/screens/<name>.tscn, shown in the
## Screens layer, one at a time. A rail button opens the screen named after it in
## snake_case, so adding a screen is only adding its scene. The screen's root gets
## `bind(state, clock, hud)` when it has that method and closes itself with `close_screen()`
## on the HUD (or by freeing itself). Returns false when the scene does not exist yet.
func open_screen(screen_name: String, args := {}) -> bool:
	var path := SCREENS % screen_name
	if not ResourceLoader.exists(path):
		return false
	close_screen()
	var scr := (load(path) as PackedScene).instantiate()
	scr.set_meta("screen_name", screen_name)
	%Screens.add_child(scr)
	if scr.has_method("bind"):
		scr.call("bind", state, clock, self)
	if not args.is_empty() and scr.has_method("open_with"):
		scr.call("open_with", args)
	_mark_rail(screen_name)
	screen_opened.emit(screen_name)
	return true


func close_screen() -> void:
	for c in %Screens.get_children():
		# a screen with a CwScreenTransition leaves the layer now (the next screen and the
		# game carry on) and plays its exit below the Screens layer before it is freed
		if not CwScreenTransition.leave(c as Control, self, %Screens.get_index()):
			c.queue_free()
			%Screens.remove_child(c)
		screen_closed.emit(String(c.get_meta("screen_name", "")))
	_mark_rail("")


## Lights the rail key of the screen on show (the rail keys are toggles; only one is lit).
func _mark_rail(screen_name: String) -> void:
	for b in %VBox.get_children():
		if b is Button and b.name != "Build":
			(b as Button).set_pressed_no_signal(String(b.name).to_snake_case() == screen_name)


## The name of the screen on show, "" when the campus is.
func current_screen() -> String:
	for c in %Screens.get_children():
		return String(c.get_meta("screen_name", ""))
	return ""


# ------------------------------------------------------------ camera tag
## Shows what the camera is on (the followed Cometling, the idle tour) in the FollowTag panel.
func show_camera_tag(caption: String, title: String, hint := "") -> void:
	var tag: Control = %FollowTag
	%TagCaption.text = caption
	%TagTitle.text = title
	%TagHint.text = hint
	%TagHint.visible = hint != ""
	if not tag.visible:
		tag.modulate.a = 0.0
		tag.visible = true
		create_tween().tween_property(tag, "modulate:a", 1.0, 0.35)


func hide_camera_tag() -> void:
	%FollowTag.visible = false


# ------------------------------------------------------------ formatting
static func fmt_int(v: float) -> String:
	return "%d" % roundi(v)


## 1284000 -> "1 284 000 cr" (thin spaces between groups).
static func fmt_cr(v: float) -> String:
	var neg := v < 0.0
	var s := str(roundi(absf(v)))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("−" if neg else "") + s + out + " cr"
