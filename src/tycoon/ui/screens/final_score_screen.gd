class_name FinalScoreScreen
extends Control
## Campaign report (scenes/tycoon/ui/screens/final_score.tscn, GDD section 16.2), two pages:
##   Summary  the final score counted up from zero, the rank, the standings of the four
##            agencies and the player's milestones
##   Details  its breakdown (milestones, science, reputation, cash, Cometlings, firsts and the
##            Mother-Ice bonus) as LED meters that fill as the page opens
## Back to the menu or to the race. Data from RaceDirector.score(); rows are copies of the
## hidden templates in the scene.

const MENU := "res://scenes/menu/main_menu.tscn"
const ROW_COLORS := {"race": CwPalette.IGNITION, "science": CwPalette.COMET_ICE, "reputation": CwPalette.AURORA_VIOLET,
	"cash": CwPalette.WARNING, "cometlings": CwPalette.AURORA_TEAL, "firsts": CwPalette.TEXT}

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var result: Dictionary = {}


func _ready() -> void:
	%MenuButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU))
	%RaceButton.pressed.connect(func() -> void:
		if hud:
			hud.open_screen("race"))
	%DetailsButton.pressed.connect(open_detail)
	(%Pages as CwPageStack).page_changed.connect(func(p: StringName, _d: int) -> void:
		if p == &"Details":
			_grow_bars())


## The breakdown page.
func open_detail() -> void:
	(%Pages as CwPageStack).push(&"Details")


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	result = state.race.score()
	fill()


func fill() -> void:
	var r := state.race
	(%Pages as CwPageStack).set_title(state.agency_name)
	var st: Array = result.get("standings", [])
	%Rank.text = tr("TY_SCORE_RANK") % [int(result.get("rank", 1)), st.size()]
	%Of.text = tr("TY_SCORE_OF") % int(result.get("max", 1000))
	var bonus := int(result.get("comet_bonus", 0))
	%BonusRow.visible = bonus > 0
	%BonusPoints.text = "+%d" % bonus
	var rows: Array = result.get("rows", [])
	var nodes := TycoonHUD._copies(%RowTemplate, rows.size())
	var tw := create_tween().set_parallel()
	for i in rows.size():
		var row: Dictionary = rows[i]
		var n := nodes[i]
		(n.get_node("Top/Label") as Label).text = tr(String(row["key"]))
		var detail := String(row["detail"])
		if row["id"] == "cash":
			detail = TycoonHUD.fmt_cr(float(detail))
		(n.get_node("Top/Detail") as Label).text = detail
		(n.get_node("Top/Points") as Label).text = "%d / %d" % [int(row["points"]), int(row["max"])]
		var bar := n.get_node("Bar") as CwSegmentBar
		bar.color = ROW_COLORS.get(row["id"], CwPalette.TEXT)
		bar.value = 0.0
		bar.set_meta("ratio", float(row["ratio"]))
	if (%Pages as CwPageStack).current() == &"Details":
		_grow_bars()
	var total := int(result.get("total", 0))
	tw.tween_method(func(v: float) -> void: %Total.text = "%d" % roundi(v), 0.0, float(total), 1.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# standings
	var stands := TycoonHUD._copies(%StandTemplate, st.size())
	for k in st.size():
		var a: Dictionary = st[k]
		var s := stands[k]
		var col: Color = a["color"]
		var style := s.get_theme_stylebox("panel").duplicate() as CwPanelStyle
		if style:
			style.tab_color = col
			s.add_theme_stylebox_override("panel", style)
		(s.get_node("HBox/Rank") as Label).text = "%d" % (k + 1)
		var mk := s.get_node("HBox/Marker") as CwMarker
		mk.fill = col
		mk.outline = col
		mk.star = bool(a["comet"])
		var nl := s.get_node("HBox/Name") as Label
		nl.text = String(a["name"]) if a["player"] else tr(String(a["name"]))
		nl.add_theme_color_override("font_color", CwPalette.TEXT if a["player"] else CwPalette.TEXT_DIM)
		(s.get_node("HBox/Count") as Label).text = "%d/%d · %d★" % [int(a["count"]), r.milestones.size(), int(a["firsts"])]
		(s.get_node("HBox/Points") as Label).text = "%.1f" % float(a["points"])
	# the player's milestones, in order
	var ms := TycoonHUD._copies(%MsTemplate, r.milestones.size())
	for i in r.milestones.size():
		var m: Dictionary = r.milestones[i]
		var mk := ms[i] as CwMarker
		var first := r.first_of(m["id"])
		mk.star = bool(m.get("victory", false))
		mk.tooltip_text = tr(String(m["name_key"]))
		if r.has_claimed(m["id"], RaceDirector.PLAYER):
			var is_first := String(first.get("by", "")) == RaceDirector.PLAYER
			mk.fill = CwPalette.IGNITION if is_first else Color(CwPalette.IGNITION, 0.35)
			mk.outline = CwPalette.IGNITION
		else:
			mk.fill = Color(0, 0, 0, 0)
			mk.outline = CwPalette.LINE


## The breakdown meters fill from empty, one after another (when the Details page opens).
func _grow_bars() -> void:
	var tw := create_tween().set_parallel()
	var i := 0
	for n in (%RowTemplate as Control).get_parent().get_children():
		if n == %RowTemplate or not n.has_meta("from_template"):
			continue
		var bar := n.get_node("Bar") as CwSegmentBar
		bar.value = 0.0
		tw.tween_property(bar, "value", float(bar.get_meta("ratio", 0.0)), 0.6).set_delay(0.15 + 0.1 * i) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1
