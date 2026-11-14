extends Control
## Review screen (scenes/tycoon/ui/screens/project_review.tscn, GDD 6.6): opens when a project
## launches. The mission grade (counting up; the project's own grade under it when the flight
## cut it), the 4 quality bars, the outcome, the four
## newspapers as paper clippings taped to the panel (the only paper in the UI, GDD 22.4) with
## their scores and quotes, what the flight taught (MissionFit feedback lines, the briefing's
## result, the journal's new entries, a key to open the journal) and the results (contract,
## reputation, hype, research, XP, cost).
## Reads the project's entry in state.project_history; the look is all in the scene (the
## middle, body and debrief, scrolls inside %Scroll so the header, results and Back stay on screen).

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
	%OpenJournal.pressed.connect(_open_journal)
	%Watch.pressed.connect(_watch)


## "Acompanhar o lançamento": the launch in the 3D flight, as it went (TycoonModes.open_watch); this
## screen stays underneath and is here again after.
func _watch() -> void:
	var m := _modes()
	if m and not entry.is_empty():
		m.open_watch(String(entry.get("id", "")))


func _modes() -> TycoonModes:
	var main := hud.owner as TycoonMain if hud else null
	return main.modes if main else null


func _open_journal() -> void:
	if hud:
		hud.open_screen("journal", {"type": String(entry.get("type", "")), "target": String(entry.get("target", ""))})


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
	%Watch.visible = _modes() != null
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
	_fill_grade(outcome, oc)
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
	if entry.get("piloted", false):  # flown by the player in the flight mode (HangarRocket)
		var reached := String((entry.get("flight", {}) as Dictionary).get("reached", "none"))
		%RocketLine.text += "  ·  " + tr("TY_HG_REVIEW_PILOTED") % tr("TY_HG_REACHED_" + reached.to_upper())
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
	_fill_debrief()
	# the footer note keeps its place (it pushes Back to the right) even when empty
	%InOrbit.text = tr("TY_PJ_IN_ORBIT") if not entry.get("suborbital", true) and entry.get("success", false) else ""


## The big number is the mission's grade (the project's grade cut by the flight's outcome,
## ProjectDesk.outcome_grade); under it the project's own grade when the two differ. A failed
## or partial flight tints the number with the outcome's colour.
func _fill_grade(outcome: String, oc: Color) -> void:
	var g := float(entry.get("grade", 0.0))
	var gp := ProjectDesk.project_grade(entry)
	_count_up(%Grade, g)
	if outcome in ["fail", "partial"]:
		%Grade.add_theme_color_override("font_color", oc)
	else:
		%Grade.remove_theme_color_override("font_color")
	var differs := absf(gp - g) >= 0.05
	%GradeProject.visible = differs
	if differs:
		var pct := roundi(g / gp * 100.0) if gp > 0.0 else 0
		var k := "TY_PJ_GRADE_PROJECT"
		if outcome in ["fail", "partial"]:
			k += "_" + outcome.to_upper()
		%GradeProject.text = tr(k) % (["%.1f" % gp, pct] if k != "TY_PJ_GRADE_PROJECT" else ["%.1f" % gp])
		if outcome == "fail":
			%GradeProject.add_theme_color_override("font_color", oc)
		else:
			%GradeProject.remove_theme_color_override("font_color")


## Numbers count up (GDD 22.6).
func _count_up(l: Label, target: float) -> void:
	l.text = "0.0"
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: l.text = "%.1f" % v, 0.0, target, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## What this flight taught: the feedback lines (gaps in red, what went well in teal, a great
## combo in gold), the briefing's result and pay, and the journal's new entries.
func _fill_debrief() -> void:
	var fb: Array = entry.get("feedback", [])
	var rows := TycoonHUD._copies(%FeedbackTemplate, fb.size())
	var tone_colors := {"bad": CwPalette.DANGER, "good": CwPalette.AURORA_TEAL, "star": CwPalette.IGNITION}
	for i in fb.size():
		var f: Dictionary = fb[i]
		(rows[i].get_node("Dot") as ColorRect).color = tone_colors.get(String(f.get("tone", "bad")), CwPalette.TEXT_DIM)
		(rows[i].get_node("Text") as Label).text = TycoonHUD.news_text(f)
	%Debrief.visible = not fb.is_empty() or not (entry.get("briefing", {}) as Dictionary).is_empty()
	var br: Dictionary = entry.get("briefing", {})
	%BriefLine.visible = not br.is_empty()
	%BriefPay.visible = not br.is_empty()
	if not br.is_empty():
		var met := String(br.get("met", "missed"))
		%BriefLine.text = tr("TY_PJ_BRIEF_" + met.to_upper()) % tr(BriefingDesk.title_key(String(br.get("id", ""))))
		%BriefLine.add_theme_color_override("font_color", {"full": CwPalette.AURORA_TEAL, "partial": CwPalette.WARNING}.get(met, CwPalette.DANGER))
		var extra: Array[String] = []
		if br.get("late", false):
			extra.append(tr("TY_PJ_BRIEF_LATE"))
		if br.get("over_budget", false):
			extra.append(tr("TY_PJ_BRIEF_OVER"))
		%BriefPay.text = TycoonHUD.fmt_cr(float(br.get("reward", 0.0))) + ("  (%s)" % ", ".join(extra) if not extra.is_empty() else "")
	var learned: Array = entry.get("learned", [])
	%JournalLine.text = tr("TY_PJ_JOURNAL_NEW") % learned.size() if not learned.is_empty() else tr("TY_PJ_JOURNAL_NONE")
