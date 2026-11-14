extends Control
## Review screen (scenes/tycoon/ui/screens/project_review.tscn, GDD 6.6): opens when a project
## launches. The project grade (counting up), the 4 quality bars, the outcome, the four
## newspapers as paper clippings taped to the panel (the only paper in the UI, GDD 22.4) with
## their scores and quotes, and the results (contract, reputation, hype, research, XP, cost).
## Reads the project's entry in state.project_history; the look is all in the scene.

const OUTCOME_COLORS := {"fail": CwPalette.DANGER, "partial": CwPalette.WARNING, "full": CwPalette.AURORA_TEAL,
	"exceptional": CwPalette.IGNITION}
const INK := Color("#1b2233")
const INK_GOOD := Color("#17735a")
const INK_BAD := Color("#b3303e")

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var entry: Dictionary = {}


func _ready() -> void:
	%Back.pressed.connect(_close)


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h


## args: {"project_id"}
func open_with(args: Dictionary) -> void:
	entry = ProjectDesk.history_entry(state, String(args.get("project_id", "")))
	if entry.is_empty():
		_close()
		return
	_fill()


func _close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


func _fill() -> void:
	var mt := state.mission_type(String(entry["type"]))
	%Caption.text = "%s · %s" % [tr("TY_PJ_REVIEW_TITLE"), String(entry["code"])]
	%Title.text = "%s · %s" % [tr(String(mt.get("name_key", ""))), tr(String(state.mission_target(String(entry["target"])).get("name_key", "")))]
	var outcome := String(entry.get("outcome", "fail"))
	var oc: Color = OUTCOME_COLORS.get(outcome, CwPalette.TEXT)
	%Outcome.text = tr("TY_PJ_OUT_" + outcome.to_upper())
	%Outcome.add_theme_color_override("font_color", oc)
	var badge := %Badge as PanelContainer
	var bs := badge.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if bs:
		bs.border_color = oc
		badge.add_theme_stylebox_override("panel", bs)
	_count_up(%Grade, float(entry.get("grade", 0.0)))
	var bars: Array = entry.get("bars", [0, 0, 0, 0])
	var rows: Array[Node] = [%BarEng, %BarSci, %BarOps, %BarRel]
	for b in 4:
		(rows[b].get_node("Bar") as CwSegmentBar).value = float(bars[b]) / 10.0
		(rows[b].get_node("Value") as Label).text = "%.1f" % float(bars[b])
	%ChanceValue.text = "%d%%" % roundi(float(entry.get("p_success", 0.0)) * 100.0)
	%DefectsValue.text = "%.1f" % float(entry.get("defects", 0.0))
	%Novelty.visible = entry.get("novelty", false)
	# the rocket that flew, and what broke (E2: the Design Review's risk that failed)
	var rk: Dictionary = entry.get("rocket", {})
	%RocketLine.visible = String(rk.get("name", "")) != ""
	%RocketLine.text = tr("TY_RK_ROCKET_LINE") % String(rk.get("name", ""))
	var ck := String(entry.get("cause_key", ""))
	%CauseLine.visible = ck != ""
	%CauseLine.text = tr("TY_RK_CAUSE_LINE") % tr(ck) if ck != "" else ""
	# the press
	var reviews: Array = entry.get("reviews", [])
	var papers: Array[Node] = [%Paper0, %Paper1, %Paper2, %Paper3]
	for i in papers.size():
		var card := papers[i]
		card.visible = i < reviews.size()
		if not card.visible:
			continue
		var r: Dictionary = reviews[i]
		var score := int(r.get("score", 0))
		(card.get_node("Masthead") as Label).text = tr(String(r.get("name_key", "")))
		(card.get_node("Kind") as Label).text = tr(String(r.get("kind_key", "")))
		var sl := card.get_node("ScoreRow/Score") as Label
		sl.text = "%d" % score
		sl.add_theme_color_override("font_color", INK_GOOD if score >= 8 else (INK_BAD if score < 5 else INK))
		(card.get_node("Quote") as Label).text = "“%s”" % tr(String(r.get("quote_key", "")))
	%Avg.text = "%.1f" % float(entry.get("review_avg", 0.0))
	# results
	var rw: Dictionary = entry.get("rewards", {})
	%RwCash.text = TycoonHUD.fmt_cr(float(rw.get("cash", 0.0))) if String(entry.get("contract_id", "")) != "" else "—"
	%RwRep.text = "%+.1f" % float(rw.get("reputation", 0.0))
	%RwRep.add_theme_color_override("font_color", CwPalette.DANGER if float(rw.get("reputation", 0.0)) < 0.0 else CwPalette.COMET_ICE)
	%RwHype.text = "%+.1f" % float(rw.get("hype", 0.0))
	%RwResearch.text = "%+.1f" % float(rw.get("research", 0.0))
	%RwXp.text = "+%d" % roundi(float(rw.get("xp", 0.0)))
	%RwCost.text = TycoonHUD.fmt_cr(float(rw.get("dev_cost", 0.0)) + float(rw.get("launch_cost", 0.0)))
	# the footer note keeps its place (it pushes Back to the right) even when empty
	%InOrbit.text = tr("TY_PJ_IN_ORBIT") if not entry.get("suborbital", true) and entry.get("success", false) else ""


## Numbers count up (GDD 22.6).
func _count_up(l: Label, target: float) -> void:
	l.text = "0.0"
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: l.text = "%.1f" % v, 0.0, target, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
