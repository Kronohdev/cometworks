class_name OpsBookScreen
extends Control
## Mission archive and encyclopedia (GDD sections 15.1 and 15.3): scenes/tycoon/ui/screens/book.tscn.
## Page "missions": every finished mission with dates, result, grade, science, data return
## and the factor that limited it. Page "cards": encyclopedia cards unlocked by the mission
## types flown, each with its NASA source (cards without a checked source never appear).
## Visuals live in the scene; rows and cards are copies of its hidden templates.

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var page := "missions"


func _ready() -> void:
	%Back.pressed.connect(close)
	%TabMissions.pressed.connect(func() -> void: show_page("missions"))
	%TabCards.pressed.connect(func() -> void: show_page("cards"))
	show_page("missions")


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


func show_page(p: String) -> void:
	page = p
	%MissionsPage.visible = p == "missions"
	%CardsPage.visible = p == "cards"
	%TabMissions.set_pressed_no_signal(p == "missions")
	%TabCards.set_pressed_no_signal(p == "cards")
	refresh()


func refresh() -> void:
	if state == null:
		return
	if page == "missions":
		_fill_missions()
	else:
		_fill_cards()


# ------------------------------------------------------------ archive
func _fill_missions() -> void:
	var arc := state.mission_archive
	var done := 0
	var sci := 0.0
	var down := 0.0
	for a in arc:
		if a.get("status", "") == "done":
			done += 1
		sci += float(a.get("science", 0.0))
		down += float(a.get("data_down", 0.0))
	%StatFlown.text = "%d" % arc.size()
	%StatSuccess.text = "%d%%" % roundi(100.0 * done / arc.size()) if arc.size() > 0 else "—"
	%StatScience.text = "%.0f" % sci
	%StatData.text = "%s Gb" % TycoonOpsFmt.int_str(roundi(down))
	%Empty.visible = arc.is_empty()
	%ColumnHead.visible = not arc.is_empty()
	var rows := TycoonHUD._copies(%RowTemplate, arc.size())
	for i in arc.size():
		_fill_row(rows[i] as PanelContainer, arc[arc.size() - 1 - i])


func _fill_row(row: PanelContainer, a: Dictionary) -> void:
	var lost: bool = a.get("status", "") != "done"
	var ty := state.mission_type(String(a.get("type", "")))
	var tg := state.mission_target(String(a.get("target", "")))
	var h := row.get_node("HBox")
	(h.get_node("Mission/Code") as Label).text = String(a.get("code", ""))
	(h.get_node("Mission/Type") as Label).text = "%s · %s" % [tr(String(ty.get("name_key", ""))), tr(String(tg.get("name_key", "")))]
	var y0: Array = TycoonOpsFmt.year_week(state, int(a.get("start_week", 0)))
	var y1: Array = TycoonOpsFmt.year_week(state, int(a.get("end_week", 0)))
	(h.get_node("Dates") as Label).text = tr("TY_BOOK_DATES") % [y0[0], y0[1], y1[0], y1[1]]
	var res := h.get_node("Result") as Label
	var outcome := String(a.get("outcome", "full"))
	res.text = tr("TY_BOOK_OUT_FAIL") if lost else tr("TY_BOOK_OUT_%s" % outcome.to_upper())
	var col := CwPalette.SUCCESS
	if lost:
		col = CwPalette.DANGER
	elif outcome == "partial":
		col = CwPalette.WARNING
	elif outcome == "exceptional":
		col = CwPalette.AURORA_TEAL
	res.add_theme_color_override("font_color", CwPalette.ink(col))
	(h.get_node("Grade") as Label).text = "%.1f" % float(a.get("grade", 0.0))
	(h.get_node("Science") as Label).text = "%.1f" % float(a.get("science", 0.0))
	var ret := clampf(float(a.get("return", 0.0)), 0.0, 1.0)
	var bar := h.get_node("Return/Bar") as CwSegmentBar
	bar.value = ret
	bar.color = CwPalette.AURORA_TEAL if ret >= 0.8 else (CwPalette.WARNING if ret >= 0.4 else CwPalette.DANGER)
	(h.get_node("Return/Pct") as Label).text = "%d%%" % roundi(ret * 100.0)
	(h.get_node("Lesson") as Label).text = lesson_text(a.get("lesson", {}))
	var st := row.get_theme_stylebox("panel", "CwStrip") as CwPanelStyle
	if st:
		var s2 := st.duplicate() as CwPanelStyle
		s2.tab_color = col
		row.add_theme_stylebox_override("panel", s2)


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
		_fill_card(nodes[i] as PanelContainer, cards[i])


func _fill_card(n: PanelContainer, c: Dictionary) -> void:
	var v := n.get_node("VBox")
	var id := String(c["id"]).to_upper()
	var on: bool = c["unlocked"]
	var year := int(c.get("year", 0))
	(v.get_node("Top/Year") as Label).text = ("%d" % year if year > 0 else "—") if on else "····"
	var types: Array = c.get("types", [])
	var tag := v.get_node("Top/Tag") as Label
	tag.text = (tr(String(state.mission_type(String(types[0])).get("name_key", ""))) if not types.is_empty() 		else tr("TY_OPS_NETWORK"))
	(v.get_node("Title") as Label).text = tr("TY_ENC_%s_TITLE" % id) if on else tr("TY_BOOK_LOCKED")
	var fact := v.get_node("Fact") as Label
	if on:
		fact.text = tr("TY_ENC_%s_FACT" % id)
	elif c.has("antenna_level"):
		fact.text = tr("TY_BOOK_LOCKED_ANTENNA") % int(c["antenna_level"])
	else:
		var names: Array = []
		for t in types:
			names.append(tr(String(state.mission_type(String(t)).get("name_key", ""))))
		fact.text = tr("TY_BOOK_LOCKED_HINT") % ", ".join(names)
	fact.add_theme_color_override("font_color", CwPalette.TEXT if on else CwPalette.TEXT_DIM)
	var src := v.get_node("Source") as LinkButton
	src.visible = on
	var url := String(c.get("url", ""))
	src.text = tr("TY_BOOK_SOURCE") % url.get_slice("//", 1).get_slice("/", 0)
	src.uri = url
	src.tooltip_text = url
	n.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)
