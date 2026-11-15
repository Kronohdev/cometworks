class_name TycoonHUD
extends Control
## Main-screen HUD of Cometworks (scenes/tycoon/ui/tycoon_hud.tscn), "Aurora de
## observatório" (GDD section 22): top instrument strip, left rail, race board with the
## Tail Radio, project / construction strips along the bottom, the one primary button and
## the lot panel. Everything visual is in the scene: lists are filled by duplicating the
## hidden templates there (RaceRowTemplate, NewsTemplate, StripTemplate), so their look is
## edited in the editor. This script only fills data.

signal build_requested(lot_id: String)
## the lot panel's "Abrir o hangar" (the workshop): TycoonMain opens the hangar (TycoonModes)
signal hangar_requested(lot_id: String)
## the bottom row's planet key: TycoonMain opens the Solar System map (TycoonModes.open_space_map)
signal solar_map_requested
## the follow tag's "Conversar": TycoonMain's dialogue box talks to the followed Cometling
signal talk_requested
## a screen asks to talk with a Lenda that is not on the campus (a mentor on a briefing, a rival
## leader on the race board): CometlingDialogue.open_legend
signal legend_talk_requested(legend_id: String, where: String)
signal screen_opened(screen_name: String)
signal screen_closed(screen_name: String)

const ICONS := "res://ui/cometworks/icons/%s.svg"
const SCREENS := "res://scenes/tycoon/ui/screens/%s.tscn"

var state: TycoonState
var clock: TycoonClock
var lot_id := ""
var _hint_default := ""
var _hint_timer := 0.0
## the translation key of the follow tag's hint when it names keys (CwKeys.hint), else ""
var _tag_hint_key := ""
## HUD nodes hidden until a new career unlocks them (HudUnlocker, MenuUnlocks): {ref: true}
var _locked := {}
## True while the camera is focused on something (following a Cometling): the race panel steps
## aside, as it does while a lot panel is open.
var _focus := false
var _cash_tween: Tween


func _ready() -> void:
	%Pause.pressed.connect(func() -> void: _set_speed(0))
	%S1.pressed.connect(func() -> void: _set_speed(1))
	%S2.pressed.connect(func() -> void: _set_speed(2))
	%S3.pressed.connect(func() -> void: _set_speed(3))
	%Close.pressed.connect(close_lot)
	%BuildButton.pressed.connect(func() -> void:
		if lot_id != "":
			build_requested.emit(lot_id))
	%HangarButton.pressed.connect(func() -> void:
		if lot_id != "":
			hangar_requested.emit(lot_id))
	%SolarMap.pressed.connect(func() -> void: solar_map_requested.emit())
	# the photo album (MissionPhotos): its key shows once a mission has sent a photo home
	var album := get_node_or_null("%Album") as Button
	if album:
		album.pressed.connect(func() -> void: open_screen("album"))
	%TagTalk.pressed.connect(func() -> void: talk_requested.emit())
	%NewProject.pressed.connect(func() -> void:
		if not open_screen("briefings"):  # the mission board, then New project
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
	_hint_default = CwKeys.hint("TY_CAMPUS_HINT")   # names the keys bound now (CwKeys)
	%Hint.text = _hint_default
	add_to_group(CwKeys.GROUP)


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


## The key bindings changed (CwKeys): the campus hint and the follow tag's hint name the new keys.
func refresh_keys() -> void:
	var was := _hint_default
	_hint_default = CwKeys.hint("TY_CAMPUS_HINT")
	if %Hint.text == was:
		%Hint.text = _hint_default
	if _tag_hint_key != "":
		%TagHint.text = CwKeys.hint(_tag_hint_key)


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
	_cash_warning()
	CwNumberTicker.show(%RepValue, state.reputation, fmt_int)
	CwNumberTicker.show(%HypeValue, state.hype, fmt_int)
	var left := state.comet_weeks_left()
	var comet_was: String = %CometValue.text
	%CometValue.text = tr("TY_COMET_COUNTDOWN") % [left / state.weeks_per_year(), left % state.weeks_per_year()]
	if %CometValue.text != comet_was:
		CwMotion.poke(%CometValue)
	_fill_race()
	_fill_news()
	_fill_strips()
	var album := get_node_or_null("%Album") as Control
	if album:
		album.visible = not state.photos.is_empty()
	if lot_id != "":
		show_lot(lot_id)


## Near bankruptcy (Bankruptcy.DANGER and past it) the cash caption says so in red and the coin
## throbs; in the red the cash's tooltip tells where the bankruptcy line is.
func _cash_warning() -> void:
	var lvl := Bankruptcy.danger_level(state)
	var text_box := %CashValue.get_parent() as Control
	var cap := text_box.get_node_or_null("Caption") as Label
	var icon := text_box.get_parent().get_node_or_null("Icon") as Control
	var danger := lvl >= Bankruptcy.DANGER
	(text_box.get_parent() as Control).tooltip_text = "" if lvl == Bankruptcy.SAFE else 		tr("BK_HUD_TIP") % fmt_cr(-Bankruptcy.threshold(state))
	if cap:
		cap.text = tr("BK_HUD_DANGER") if danger else "TY_CASH"
		if danger:
			cap.add_theme_color_override("font_color", CwPalette.DANGER)
		else:
			cap.remove_theme_color_override("font_color")
	if icon == null:
		return
	if danger and (_cash_tween == null or not _cash_tween.is_valid()):
		_cash_tween = create_tween().set_loops()
		_cash_tween.tween_property(icon, "modulate", Color(1.0, 0.55, 0.6), 0.45).set_trans(Tween.TRANS_SINE)
		_cash_tween.tween_property(icon, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)
	elif not danger and _cash_tween != null:
		_cash_tween.kill()
		_cash_tween = null
		icon.modulate = Color.WHITE


## Keeps `count` visible copies of `template` (a hidden node in the scene) in its parent.
static func _copies(template: Control, count: int) -> Array[Control]:
	var parent := template.get_parent()
	var out: Array[Control] = []
	# a parent may hold several templates (a golden card next to the usual one): each keeps its own
	for c in parent.get_children():
		if c != template and c.has_meta("from_template") and c.get_meta("template_of", template.name) == template.name:
			out.append(c)
	while out.size() < count:
		var c := template.duplicate() as Control
		c.set_meta("from_template", true)
		c.set_meta("template_of", template.name)
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
	_apply_race_visibility()
	%Icon.texture = load(ICONS % String(bt.get("icon", "hq")))
	%LotName.text = tr(String(bt.get("name_key", "")))
	%LotLevel.text = tr("TY_LOT_FOR_SALE") if lv == 0 and wl == 0 else tr("TY_LEVEL") % lv
	(%LevelBar as CwSegmentBar).value = lv / 3.0
	%Desc.text = tr(String(bt.get("desc_key", "")))
	# the workshop, once built, opens the hangar
	%HangarButton.visible = kind == "workshop" and lv > 0 and not is_locked("%HangarButton")
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
	_apply_race_visibility()


## Focus mode (the camera follows a Cometling): the "Corrida à Lua" panel hides until it ends.
func set_focus(on: bool) -> void:
	if _focus == on:
		return
	_focus = on
	_apply_race_visibility()


## The race panel shows when the career unlocked it and nothing has the focus (no Cometling
## followed, no lot panel open).
func _apply_race_visibility() -> void:
	var race := get_node_or_null("Side/Race") as Control
	if race:
		race.visible = not is_locked("Side/Race") and not _focus and lot_id == ""


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


## Esc (or a back key) on the open screen: a screen with pages goes up one page (its own
## go_back() first, else its deepest CwPageStack showing a sub page); at its top level the
## screen closes.
func screen_back() -> void:
	for c in %Screens.get_children():
		if c.has_method("go_back") and bool(c.call("go_back")):
			return
		if CwPageStack.back_in(c):
			return
	close_screen()


## Lights the rail key of the screen on show (the rail keys are toggles; only one is lit).
func _mark_rail(screen_name: String) -> void:
	for b in %VBox.get_children():
		if b is Button and b.name != "Build":
			(b as Button).set_pressed_no_signal(String(b.name).to_snake_case() == screen_name)


## The name of the screen on show, "" when the campus is.
## Talk with Lenda `id` from a screen ("briefing", "race"): the dialogue box opens over it.
func talk_to_legend(id: String, where: String) -> void:
	if id != "":
		legend_talk_requested.emit(id, where)


func current_screen() -> String:
	for c in %Screens.get_children():
		return String(c.get_meta("screen_name", ""))
	return ""


# ------------------------------------------------------------ menus a career unlocks
## A HUD node by the reference the unlock table uses (data/tycoon/menu_unlocks.json):
## "%Name" a unique name, "Crew" a rail button (a child of %VBox), "Side/Race" a path from the
## HUD root. null when there is no such node (a button another feature has not added yet).
func hud_node(ref: String) -> Control:
	if ref == "":
		return null
	if ref.begins_with("%"):
		return get_node_or_null(NodePath(ref)) as Control
	var rail := (%VBox as Node).get_node_or_null(NodePath(ref)) as Control
	if rail:
		return rail
	return get_node_or_null(NodePath(ref)) as Control


## Hides (locked) or shows a HUD node a new career has not unlocked yet (HudUnlocker).
func lock_node(ref: String, locked: bool) -> void:
	var n := hud_node(ref)
	if locked:
		_locked[ref.trim_prefix("%")] = true
	else:
		_locked.erase(ref.trim_prefix("%"))
	if n == null:
		return
	if n.get_parent() == %VBox:
		_tidy_rail.call_deferred()
	if not locked and not n.visible:
		# hidden while the rail cascaded in: drop the entrance it never got to play
		CwMotion.clear_channel(n, &"stagger")
	if n == %HangarButton:
		n.visible = not locked and lot_id != "" and state != null and state.lot_kind(lot_id) == "workshop" \
			and int(state.building(lot_id).get("level", 0)) > 0
	elif ref == "Side/Race":
		_apply_race_visibility()
	else:
		n.visible = not locked


## The rail's separators show only between groups that have a key on show (the rail grows
## from its top as keys appear).
func _tidy_rail() -> void:
	var any_before := false
	var group_has := false
	for c in %VBox.get_children():
		if c is Separator:
			(c as Control).visible = any_before and group_has
			group_has = false
		elif c is Control and (c as Control).visible:
			any_before = true
			group_has = true


## True while a new career has not unlocked that node ("%SolarMap", "Crew"...).
func is_locked(ref: String) -> bool:
	return _locked.has(ref.trim_prefix("%"))


## A key for a locked menu (M for the map...): a hint instead of the screen.
func locked_hint() -> void:
	flash_hint(tr("TY_UNL_LOCKED_HINT"), 3.0)


# ------------------------------------------------------------ camera tag
## Shows what the camera is on (the followed Cometling, the idle tour) in the FollowTag panel;
## `can_talk` shows its "Conversar" button (talk_requested).
func show_camera_tag(caption: String, title: String, hint := "", can_talk := false) -> void:
	var tag: Control = %FollowTag
	%TagCaption.text = caption
	%TagTitle.text = title
	%TagHint.text = hint
	_tag_hint_key = ""
	for k in ["TY_CAM_FOLLOW_HINT"]:
		if hint == CwKeys.hint(k):
			_tag_hint_key = k
	%TagHint.visible = hint != ""
	%TagTalk.visible = can_talk
	if not tag.visible:
		tag.modulate.a = 0.0
		tag.visible = true
		create_tween().tween_property(tag, "modulate:a", 1.0, 0.35)


## While a conversation is up (CometlingDialogue) the follow tag's Conversar button and the
## bottom hint step aside for the dialogue box; `can_talk` puts the button back after.
func set_talking(on: bool, can_talk := true) -> void:
	$HintBox.visible = not on
	%TagTalk.visible = not on and can_talk


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
