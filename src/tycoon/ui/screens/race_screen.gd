class_name RaceScreen
extends Control
## The race to the Moon (scenes/tycoon/ui/screens/race.tscn, GDD section 13): the 15
## milestones as stations on a rail from the home world to the Mother-Ice (names alternate
## above and below the line, so each has two stations of room), one row per agency with
## what it took when, a plain-words legend, the rival cards in a scrolling row and the detail
## of the milestone under the cursor. All the look is in the scene; this script fills data,
## places the station / lane templates on the track (CwRaceTrack.station_pos) and follows
## the hover.

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var selected := -1

@onready var track: CwRaceTrack = %Track


func _ready() -> void:
	%Close.pressed.connect(close)
	track.resized.connect(refresh)


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	state.changed.connect(refresh)
	refresh.call_deferred()


func close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if hud == null and event.is_action_pressed("ui_cancel"):
		close()


func refresh() -> void:
	if state == null or not is_inside_tree():
		return
	var r := state.race
	var left := state.comet_weeks_left()
	%CometValue.text = "T− %02da %02ds" % [left / state.weeks_per_year(), left % state.weeks_per_year()]
	track.count = r.milestones.size()
	track.reached = r.frontier()
	track.current_era = state.era()
	_fill_eras()
	_fill_stations()
	_fill_lanes()
	_fill_cards()
	if selected < 0:
		selected = mini(r.next_of(RaceDirector.PLAYER), r.milestones.size() - 1)
	_fill_detail(selected)


static func initials(name: String) -> String:
	var words := name.split(" ", false)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	return (name.left(1) + name.substr(name.length() / 2, 1)).to_upper()


func _agency_initials(id: String) -> String:
	if id == RaceDirector.PLAYER:
		return initials(state.agency_name)
	return String(state.race.rival(id).get("initials", id.left(2).to_upper()))


func _agency_label(id: String) -> String:
	var n := state.race.agency_name(id)
	return n if id == RaceDirector.PLAYER else tr(n)


func _when(week_index: int) -> String:
	return tr("TY_RACE_WHEN") % [week_index / state.weeks_per_year() + 1, week_index % state.weeks_per_year() + 1]


# ------------------------------------------------------------ track
func _fill_eras() -> void:
	var labels := TycoonHUD._copies(%EraTemplate, track.era_breaks.size() + 1)
	for k in labels.size():
		var l := labels[k] as Label
		var span := track.era_span(k)
		l.text = tr("TY_RACE_ERA") % [k + 1, tr("TY_ERA_%d" % (k + 1))]
		l.position = Vector2(span.x, 4.0)
		l.size = Vector2(span.y - span.x, l.size.y)
		l.add_theme_color_override("font_color", CwPalette.TEXT if state.era() == k + 1 else CwPalette.TEXT_DIM)


func _fill_stations() -> void:
	var r := state.race
	var nodes := TycoonHUD._copies(%StationTemplate, r.milestones.size())
	var player_next := r.next_of(RaceDirector.PLAYER)
	for i in nodes.size():
		var m: Dictionary = r.milestones[i]
		var st := nodes[i]
		st.position = track.station_pos(i)
		var first := r.first_of(m["id"])
		var mk := st.get_node("Marker") as CwMarker
		mk.star = bool(m.get("victory", false))
		mk.fill = r.agency_color(String(first["by"])) if not first.is_empty() else Color(0, 0, 0, 0)
		mk.outline = CwPalette.TEXT if not first.is_empty() else CwPalette.HAIRLINE
		mk.ring = i == player_next or i == selected
		mk.ring_color = CwPalette.TEXT if i == selected else CwPalette.AURORA_TEAL
		var info := st.get_node("Info") as VBoxContainer
		var above := i % 2 == 1
		# names alternate above / below the line: each one has two stations of room
		var lw := minf(track.station_gap() * 2.0 - 8.0, 200.0)
		info.alignment = BoxContainer.ALIGNMENT_END if above else BoxContainer.ALIGNMENT_BEGIN
		info.size = Vector2(lw, info.size.y)
		info.position = Vector2(-lw * 0.5, -info.size.y - 16.0 if above else 16.0)
		# above the line the claim sits next to the marker, below it the number does
		info.move_child(info.get_node("Num"), info.get_child_count() - 1 if above else 0)
		(info.get_node("Num") as Label).text = "%02d" % (i + 1)
		var name_l := info.get_node("Name") as Label
		name_l.text = tr(String(m.get("short_key", m["name_key"])))
		name_l.add_theme_color_override("font_color", CwPalette.TEXT if not first.is_empty() or i == player_next else CwPalette.TEXT_DIM)
		var first_l := info.get_node("First") as Label
		if first.is_empty():
			first_l.text = "—"
			first_l.add_theme_color_override("font_color", CwPalette.HAIRLINE)
		else:
			var w := int(first["week"])
			first_l.text = "%s · %s" % [_agency_initials(String(first["by"])), tr("TY_RACE_YEAR_SHORT") % (w / state.weeks_per_year() + 1)]
			first_l.add_theme_color_override("font_color", CwPalette.ink(r.agency_color(String(first["by"]))))
		var hit := st.get_node("Hit") as Button
		if not hit.has_meta("wired"):
			hit.set_meta("wired", true)
			hit.mouse_entered.connect(func() -> void: select(int(st.get_meta("index"))))
		st.set_meta("index", i)


func select(i: int) -> void:
	if i == selected:
		return
	selected = i
	_fill_stations()
	_fill_detail(i)


# ------------------------------------------------------------ lanes
func _fill_lanes() -> void:
	var r := state.race
	var ids := r.agencies()
	var lanes := TycoonHUD._copies(%LaneTemplate, ids.size())
	for k in ids.size():
		var id := ids[k]
		var lane := lanes[k]
		var col := r.agency_color(id)
		var head := lane.get_node("Head") as PanelContainer
		var st := head.get_theme_stylebox("panel").duplicate() as CwPanelStyle
		if st:
			st.tab_color = col
			head.add_theme_stylebox_override("panel", st)
		var emblem := TycoonLeader.agency_emblem(state) if id == RaceDirector.PLAYER else null
		var emblem_r := head.get_node_or_null("HBox/Emblem") as TextureRect
		if emblem_r:   # the player's lane wears the agency emblem
			emblem_r.visible = emblem != null
			emblem_r.texture = emblem
			emblem_r.self_modulate = col
		var name_l := head.get_node("HBox/Name") as Label
		name_l.text = _agency_label(id) + ("  ·  " + tr("TY_RACE_YOU") if id == RaceDirector.PLAYER else "")
		name_l.add_theme_color_override("font_color", CwPalette.TEXT if id == RaceDirector.PLAYER else CwPalette.TEXT_DIM.lerp(CwPalette.TEXT, 0.5))
		(head.get_node("HBox/Count") as Label).text = "%d/%d · %d★" % [r.claims_of(id).size(), r.milestones.size(), r.firsts_of(id)]
		# the lane and the track share the left edge; the cells start after the head column
		var dx := -(head.custom_minimum_size.x + float(lane.get_theme_constant("separation")))
		_fill_cells(lane.get_node("Cells") as Control, id, col, dx, lane.custom_minimum_size.y)


func _fill_cells(cells: Control, id: String, col: Color, dx: float, height: float) -> void:
	var r := state.race
	var n := r.milestones.size()
	var y := height * 0.5 - 4.0
	var nodes := TycoonHUD._copies(cells.get_node("CellTemplate") as Control, n)
	var next := r.next_of(id)
	var last_x := track.station_pos(0).x + dx
	for i in n:
		var m: Dictionary = r.milestones[i]
		var c := nodes[i]
		var x := track.station_pos(i).x + dx
		c.position = Vector2(x, y)
		var mk := c.get_node("Marker") as CwMarker
		var year_l := c.get_node("Year") as Label
		var mine: Dictionary = {}
		for cl in r.claims_of(id):
			if cl["milestone"] == m["id"]:
				mine = cl
		mk.star = bool(m.get("victory", false))
		mk.ring = i == next and next < n
		mk.ring_color = col
		if mine.is_empty():
			var dropped: Array = r.rival_state(id).get("dropped", [])
			mk.fill = Color(0, 0, 0, 0)
			mk.outline = CwPalette.DANGER.darkened(0.3) if dropped.has(m["id"]) else CwPalette.LINE
			mk.radius = 3.0
			year_l.text = ""
		else:
			var first := int(mine["order"]) == 0
			mk.fill = col if first else Color(col, 0.35)
			mk.outline = col if first else Color(col, 0.7)
			mk.radius = 6.0 if first else 4.5
			year_l.text = "%02d" % (int(mine["week"]) / state.weeks_per_year() + 1)
			year_l.add_theme_color_override("font_color", CwPalette.ink(Color(col, 0.9) if first else CwPalette.TEXT_DIM))
			last_x = x
	var rail := cells.get_node("Rail") as ColorRect
	rail.position = Vector2(track.station_pos(0).x + dx, y - 1.5)
	rail.size = Vector2(track.station_pos(n - 1).x - track.station_pos(0).x, 3.0)
	var prog := cells.get_node("Progress") as ColorRect
	var target_x := track.station_pos(mini(next, n - 1)).x + dx if next < n else last_x
	prog.color = Color(col, 0.75)
	prog.position = Vector2(track.station_pos(0).x + dx, y - 2.0)
	prog.size = Vector2(maxf(target_x - prog.position.x, 0.0), 4.0)


# ------------------------------------------------------------ rival cards
func _fill_cards() -> void:
	var r := state.race
	var cards := TycoonHUD._copies(%CardTemplate, state.rivals.size())
	for k in state.rivals.size():
		var id := String(state.rivals[k]["id"])
		var p := r.rival(id)
		var card := cards[k] as PanelContainer
		var col := r.agency_color(id)
		var st := card.get_theme_stylebox("panel").duplicate() as CwPanelStyle
		if st:
			st.tab_color = col
			card.add_theme_stylebox_override("panel", st)
		var v := card.get_node("VBox")
		var name_l := v.get_node("Head/Name") as Label
		name_l.text = tr(String(p.get("name_key", id)))
		name_l.add_theme_color_override("font_color", CwPalette.ink(col))
		(v.get_node("Head/Initials") as Label).text = String(p.get("initials", ""))
		(v.get_node("Pers") as Label).text = tr(String(p.get("personality_key", "")))
		(v.get_node("Grid/Str") as Label).text = tr(String(p.get("strength_key", "")))
		(v.get_node("Grid/Weak") as Label).text = tr(String(p.get("weakness_key", "")))
		var next := r.next_of(id)
		(v.get_node("Now/Value") as Label).text = tr(String(r.milestones[next].get("short_key", ""))) if next < r.milestones.size() else tr("TY_RACE_ALL_DONE")
		(v.get_node("Foot/Motto") as Label).text = tr(String(p.get("motto_key", "")))
		(v.get_node("Foot/Setbacks") as Label).text = "%s: %d" % [tr("TY_RACE_SETBACKS"), int(r.rival_state(id).get("fails", 0))]


# ------------------------------------------------------------ detail
func _fill_detail(i: int) -> void:
	var r := state.race
	if i < 0 or i >= r.milestones.size():
		return
	var m: Dictionary = r.milestones[i]
	%DNum.text = "%02d" % (i + 1)
	%DEra.text = tr("TY_RACE_ERA") % [int(m.get("era", 1)), tr("TY_ERA_%d" % int(m.get("era", 1)))]
	%DName.text = tr(String(m["name_key"]))
	if bool(m.get("victory", false)):
		%DReward.text = tr("TY_RACE_VICTORY") % int(r.mdata.get("score", {}).get("comet_bonus", 200))
	else:
		%DReward.text = tr("TY_RACE_REWARD") % [TycoonHUD.fmt_cr(float(m.get("prize", 0))), int(m.get("rep", 0)), int(m.get("hype", 0))]
	%DHow.text = how_text(state, m)
	var yrs: Array = m.get("years", [1, 25])
	%DExpect.text = tr("TY_RACE_EXPECT") % [int(yrs[0]), int(yrs[1])]
	var list: Array = r.claims.get(m["id"], [])
	var rows := TycoonHUD._copies(%ClaimTemplate, list.size())
	for k in list.size():
		var c: Dictionary = list[k]
		var by := String(c["by"])
		var row := rows[k]
		var mk := row.get_node("Marker") as CwMarker
		mk.fill = r.agency_color(by) if k == 0 else Color(r.agency_color(by), 0.35)
		mk.outline = r.agency_color(by)
		(row.get_node("Order") as Label).text = tr("TY_RACE_ORD_%d" % mini(k + 1, 4))
		var nl := row.get_node("Name") as Label
		nl.text = _agency_label(by)
		nl.add_theme_color_override("font_color", CwPalette.TEXT if k == 0 else CwPalette.TEXT_DIM)
		(row.get_node("When") as Label).text = _when(int(c["week"]))
	%DNobody.visible = list.is_empty()


## "Launch: Sounding rocket → Suborbital (partial success or better)", one line per condition.
static func how_text(s: TycoonState, m: Dictionary) -> String:
	var lines: PackedStringArray = []
	for c: Dictionary in m.get("conditions", []):
		var types: PackedStringArray = []
		for t: String in c.get("types", []):
			types.append(TranslationServer.translate(String(s.mission_type(t).get("name_key", t))))
		var targets: PackedStringArray = []
		for t: String in c.get("targets", []):
			targets.append(TranslationServer.translate(String(s.mission_target(t).get("name_key", t))))
		var verb := TranslationServer.translate("TY_RACE_LAUNCH" if String(c.get("on", "")) == "launched" else "TY_RACE_COMPLETE")
		lines.append("%s: %s → %s (%s)" % [verb,
			" / ".join(types) if not types.is_empty() else TranslationServer.translate("TY_RACE_ANY_TYPE"),
			" / ".join(targets) if not targets.is_empty() else TranslationServer.translate("TY_RACE_ANY_TARGET"),
			TranslationServer.translate("TY_RACE_OUT_" + String(c.get("min_outcome", "partial")).to_upper())])
	var req: PackedStringArray = []
	for id: String in m.get("requires", []):
		for mm: Dictionary in s.race.milestones:
			if mm["id"] == id:
				req.append(TranslationServer.translate(String(mm.get("short_key", mm["name_key"]))))
	if not req.is_empty():
		lines.append(TranslationServer.translate("TY_RACE_REQUIRES") % ", ".join(req))
	return "\n".join(lines)
