class_name OpsBookScreen
extends Control
## Mission archive and encyclopedia (GDD sections 15.1 and 15.3): scenes/tycoon/ui/screens/book.tscn,
## as pages (CwPageStack): categories, then a list, then one entry.
##   Shelf     two big tiles: the mission archive and the encyclopedia, with their counts
##   Missions  the archive totals and every finished mission (code, type, result, grade)
##   Mission   one mission: dates, result, grade, science, data return and the factor that
##             limited it
##   Cards     the encyclopedia cards unlocked by the mission types flown (locked ones say how
##             to unlock them)
##   Card      one card: year, mission type, title, fact and its NASA source (cards without a
##             checked source never appear)
## Visuals live in the scene; rows and cards are copies of its hidden templates.

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
## the page last asked for with show_page() ("missions" | "cards")
var page := "missions"
var _mission := {}
var _card := {}

@onready var pages: CwPageStack = %Pages


func _ready() -> void:
	%Back.pressed.connect(close)
	%MissionsTile.pressed.connect(func() -> void: show_page("missions"))
	%CardsTile.pressed.connect(func() -> void: show_page("cards"))
	pages.page_changed.connect(func(_p: StringName, _d: int) -> void: refresh())


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD = null) -> void:
	state = s
	clock = c
	hud = h
	state.changed.connect(refresh)
	refresh()


func close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


## Opens a category's list: "missions" (the archive) or "cards" (the encyclopedia).
func show_page(p: String) -> void:
	page = p
	if pages.depth() > 0:
		pages.back_to(0)
	pages.push(&"Cards" if p == "cards" else &"Missions")
	refresh()


## The newest mission's page (tests, dev menu).
func open_detail() -> void:
	if state and not state.mission_archive.is_empty():
		show_page("missions")
		open_mission(state.mission_archive[state.mission_archive.size() - 1])


## The first unlocked encyclopedia card's page (tests, dev menu).
func open_first_card() -> void:
	if state == null:
		return
	for c in MissionOps.encyclopedia(state):
		if c["unlocked"]:
			show_page("cards")
			open_card(c)
			return


func open_mission(a: Dictionary) -> void:
	_mission = a
	pages.push(&"Mission", String(a.get("code", "")))
	refresh()


func open_card(c: Dictionary) -> void:
	_card = c
	pages.push(&"Card", tr("TY_ENC_%s_TITLE" % String(c["id"]).to_upper()))
	refresh()


func refresh() -> void:
	if state == null or not is_inside_tree():
		return
	_fill_shelf()
	match pages.current():
		&"Missions":
			_fill_missions()
		&"Mission":
			_fill_mission(_mission)
		&"Cards":
			_fill_cards()
		&"Card":
			_fill_card_page(_card)


# ------------------------------------------------------------ shelf
func _archive_totals() -> Dictionary:
	var arc := state.mission_archive
	var done := 0
	var sci := 0.0
	var down := 0.0
	for a in arc:
		if a.get("status", "") == "done":
			done += 1
		sci += float(a.get("science", 0.0))
		down += float(a.get("data_down", 0.0))
	return {"n": arc.size(), "done": done, "science": sci, "down": down}


func _fill_shelf() -> void:
	var t := _archive_totals()
	%Count.text = tr("TY_BOOK_SHELF_MISSIONS") % [int(t["n"]), "%d%%" % roundi(100.0 * int(t["done"]) / int(t["n"]))] \
		if int(t["n"]) > 0 else tr("TY_BOOK_EMPTY")
	var cards := MissionOps.encyclopedia(state)
	var on := 0
	for c in cards:
		on += 1 if c["unlocked"] else 0
	%CardsCount.text = tr("TY_BOOK_CARDS_COUNT") % [on, cards.size()]


# ------------------------------------------------------------ archive
func _fill_missions() -> void:
	var arc := state.mission_archive
	var t := _archive_totals()
	%StatFlown.text = "%d" % int(t["n"])
	%StatSuccess.text = "%d%%" % roundi(100.0 * int(t["done"]) / arc.size()) if arc.size() > 0 else "—"
	%StatScience.text = "%.0f" % float(t["science"])
	%StatData.text = "%s Gb" % TycoonOpsFmt.int_str(roundi(float(t["down"])))
	%Empty.visible = arc.is_empty()
	var rows := TycoonHUD._copies(%RowTemplate, arc.size())
	for i in arc.size():
		_fill_row(rows[i] as PanelContainer, arc[arc.size() - 1 - i])


## [result text, colour] of an archived mission.
func _result(a: Dictionary) -> Array:
	var lost: bool = a.get("status", "") != "done"
	var outcome := String(a.get("outcome", "full"))
	var col := CwPalette.SUCCESS
	if lost:
		col = CwPalette.DANGER
	elif outcome == "partial":
		col = CwPalette.WARNING
	elif outcome == "exceptional":
		col = CwPalette.AURORA_TEAL
	return [tr("TY_BOOK_OUT_FAIL") if lost else tr("TY_BOOK_OUT_%s" % outcome.to_upper()), col]


func _type_line(a: Dictionary) -> String:
	var ty := state.mission_type(String(a.get("type", "")))
	var tg := state.mission_target(String(a.get("target", "")))
	return "%s · %s" % [tr(String(ty.get("name_key", ""))), tr(String(tg.get("name_key", "")))]


static func _tint(p: PanelContainer, col: Color, type_name: StringName) -> void:
	var st := p.get_theme_stylebox("panel", type_name) as CwPanelStyle
	if st:
		var s2 := st.duplicate() as CwPanelStyle
		s2.tab_color = col
		p.add_theme_stylebox_override("panel", s2)


func _fill_row(row: PanelContainer, a: Dictionary) -> void:
	var h := row.get_node("HBox")
	(h.get_node("Mission/Code") as Label).text = String(a.get("code", ""))
	(h.get_node("Mission/Type") as Label).text = _type_line(a)
	var r := _result(a)
	var res := h.get_node("Result") as Label
	res.text = r[0]
	res.add_theme_color_override("font_color", CwPalette.ink(r[1]))
	(h.get_node("Grade/Value") as Label).text = "%.1f" % float(a.get("grade", 0.0))
	_tint(row, r[1], &"CwStrip")
	row.set_meta("mission", a)
	if not row.has_meta("wired"):
		row.set_meta("wired", true)
		h.get_node("Open").pressed.connect(func() -> void: open_mission(row.get_meta("mission")))
		row.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				open_mission(row.get_meta("mission")))


func _fill_mission(a: Dictionary) -> void:
	if a.is_empty():
		return
	var r := _result(a)
	%MResult.text = r[0]
	%MResult.add_theme_color_override("font_color", CwPalette.ink(r[1]))
	_tint(%MCard, r[1], &"CwCard")
	%MCode.text = String(a.get("code", ""))
	%MType.text = _type_line(a)
	var y0: Array = TycoonOpsFmt.year_week(state, int(a.get("start_week", 0)))
	var y1: Array = TycoonOpsFmt.year_week(state, int(a.get("end_week", 0)))
	%MDates.text = tr("TY_BOOK_DATES") % [y0[0], y0[1], y1[0], y1[1]]
	%MLesson.text = lesson_text(a.get("lesson", {}))
	%MGrade.text = "%.1f" % float(a.get("grade", 0.0))
	%MScience.text = "%.1f" % float(a.get("science", 0.0))
	var ret := clampf(float(a.get("return", 0.0)), 0.0, 1.0)
	var bar := %MReturnBar as CwSegmentBar
	bar.value = ret
	bar.color = CwPalette.AURORA_TEAL if ret >= 0.8 else (CwPalette.WARNING if ret >= 0.4 else CwPalette.DANGER)
	%MReturn.text = "%d%%" % roundi(ret * 100.0)


static func lesson_text(l: Dictionary) -> String:
	var args: Array = []
	for x in l.get("args", []):
		args.append(TranslationServer.translate(String(x)) if x is String and String(x).begins_with("TY_") else x)
	var t := TranslationServer.translate(String(l.get("key", "")))
	return t % args if not args.is_empty() else t


# ------------------------------------------------------------ encyclopedia
func _fill_cards() -> void:
	var cards := MissionOps.encyclopedia(state)
	var on := 0
	for c in cards:
		if c["unlocked"]:
			on += 1
	%CardCount.text = tr("TY_BOOK_CARDS_COUNT") % [on, cards.size()]
	# unlocked first, then by year
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["unlocked"] != b["unlocked"]:
			return a["unlocked"]
		return int(a.get("year", 0)) < int(b.get("year", 0)))
	var nodes := TycoonHUD._copies(%CardTemplate, cards.size())
	for i in cards.size():
		_fill_card(nodes[i] as Button, cards[i])


func _type_name(c: Dictionary) -> String:
	var types: Array = c.get("types", [])
	return tr(String(state.mission_type(String(types[0])).get("name_key", ""))) if not types.is_empty() \
		else tr("TY_OPS_NETWORK")


func _locked_hint(c: Dictionary) -> String:
	if c.has("antenna_level"):
		return tr("TY_BOOK_LOCKED_ANTENNA") % int(c["antenna_level"])
	var names: Array = []
	for t in c.get("types", []):
		names.append(tr(String(state.mission_type(String(t)).get("name_key", ""))))
	return tr("TY_BOOK_LOCKED_HINT") % ", ".join(names)


func _fill_card(n: Button, c: Dictionary) -> void:
	var v := n.get_node("VBox")
	var id := String(c["id"]).to_upper()
	var on: bool = c["unlocked"]
	var year := int(c.get("year", 0))
	(v.get_node("Top/Year") as Label).text = ("%d" % year if year > 0 else "—") if on else "····"
	(v.get_node("Top/Tag") as Label).text = _type_name(c)
	(v.get_node("Title") as Label).text = tr("TY_ENC_%s_TITLE" % id) if on else tr("TY_BOOK_LOCKED")
	var hint := v.get_node("Hint") as Label
	hint.visible = not on
	hint.text = _locked_hint(c) if not on else ""
	n.disabled = not on
	n.tooltip_text = tr("TY_BOOK_OPEN_CARD_TIP") if on else _locked_hint(c)
	n.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)
	n.set_meta("card", c)
	if not n.has_meta("wired"):
		n.set_meta("wired", true)
		n.pressed.connect(func() -> void: open_card(n.get_meta("card")))


func _fill_card_page(c: Dictionary) -> void:
	if c.is_empty():
		return
	var id := String(c["id"]).to_upper()
	var year := int(c.get("year", 0))
	%CYear.text = "%d" % year if year > 0 else "—"
	%CTag.text = _type_name(c)
	%CTitle.text = tr("TY_ENC_%s_TITLE" % id)
	%CFact.text = tr("TY_ENC_%s_FACT" % id)
	var url := String(c.get("url", ""))
	%CSource.text = tr("TY_BOOK_SOURCE") % url.get_slice("//", 1).get_slice("/", 0)
	%CSource.uri = url
	%CSource.tooltip_text = url
	%CSource.visible = url != ""
