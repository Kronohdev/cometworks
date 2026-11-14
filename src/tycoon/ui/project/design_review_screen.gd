extends CwScreen
## Design Review (scenes/tycoon/ui/screens/design_review.tscn, E2 / GDD section 7): opens when
## a project ends its development (ProjectFlow, on project_review_ready). Big on the right, the
## chance of success counting as fixes are toggled, and its breakdown (rocket x payload x crew);
## the advisor Cometling names the riskiest factor. On the left one row per risk (DesignReview):
## its chance to end the flight, a coloured severity, and Accept / Fix (+weeks, cr). Footer:
## scrub (two clicks), change rocket (the rocket designer), decide later, and Launch (or Fix,
## then launch). A design that does not reach blocks the launch.
## The look is all in the scene; risk rows are copies of its hidden RiskTemplate.

const SEV_COLORS := {"low": CwPalette.AURORA_TEAL, "mid": CwPalette.WARNING, "high": CwPalette.DANGER}

var project_id := ""
var project: MissionProject
## the risks the player chose to fix
var fixes: Array[String] = []
var _scrub_armed := false


func _ready() -> void:
	super._ready()
	%Launch.pressed.connect(_launch)
	%Change.pressed.connect(_change)
	%Scrub.pressed.connect(_scrub)
	%Later.pressed.connect(close_screen)


## args: {"project_id"}
func open_with(args: Dictionary) -> void:
	project_id = String(args.get("project_id", ""))
	project = ProjectDesk.find(state, project_id)
	if project == null or project.review_state != "waiting":
		close_screen()
		return
	fixes.clear()
	for f in project.review_fixes:
		fixes.append(f)
	refresh()


func _toggle_fix(id: String, on: bool) -> void:
	if on and id not in fixes:
		fixes.append(id)
	elif not on:
		fixes.erase(id)
	_scrub_armed = false
	refresh()


func _launch() -> void:
	# confirm_review launches now (no fixes) or after the fixes' weeks; ProjectFlow opens the
	# launch sequence when this screen closes
	if ProjectDesk.confirm_review(state, project_id, fixes):
		close_screen()


func _change() -> void:
	if hud:
		hud.open_screen("rocket_designer", {"project_id": project_id})


func _scrub() -> void:
	if not _scrub_armed:
		_scrub_armed = true
		%Scrub.text = tr("TY_RK_SCRUB_SURE")
		return
	ProjectDesk.scrub(state, project_id)
	close_screen()


# ------------------------------------------------------------ fill
func refresh() -> void:
	if state == null or project == null:
		return
	if ProjectDesk.find(state, project_id) == null:
		return
	var mt := project.mission_type(state)
	var info := ProjectDesk.rocket_info(state, project)
	%Caption.text = "%s · %s → %s · %s" % [project.code, tr(String(mt.get("name_key", ""))),
		tr(String(state.mission_target(project.target_id).get("name_key", ""))), tr("TY_RK_ROCKET_LINE") % String(info["name"])]
	var o := DesignReview.odds(state, project, fixes)
	var o0 := DesignReview.odds(state, project, [])
	var list: Array = o["risks"]
	_fill_risks(list)
	# the odds and their breakdown
	var total := float(o["total"])
	CwNumberTicker.show(%OddsValue, total * 100.0, func(v: float) -> String: return "%d%%" % roundi(v))
	%OddsValue.add_theme_color_override("font_color", _odds_color(total))
	%OddsBefore.visible = not fixes.is_empty()
	%OddsBefore.text = tr("TY_RK_ODDS_BEFORE") % roundi(float(o0["total"]) * 100.0)
	_part(%PartRocket, float(o["rocket"]))
	_part(%PartPayload, float(o["payload"]))
	_part(%PartCrew, float(o["crew"]))
	%PartCrew.visible = ProjectRules.is_crewed(project.type_id)
	var terms: Array[String] = ["%d%%" % roundi(float(o["rocket"]) * 100.0), "%d%%" % roundi(float(o["payload"]) * 100.0)]
	if ProjectRules.is_crewed(project.type_id):
		terms.append("%d%%" % roundi(float(o["crew"]) * 100.0))
	%Equation.text = "%s = %d%%" % [" × ".join(terms), roundi(total * 100.0)]
	_fill_advisor(list)
	# the rocket: its family, heritage and cost per flight
	var fam := RocketFamilies.find(state, String(info["family"]))
	var fl := RocketFamilies.flights(fam)
	%RocketName.text = String(info["name"])
	%RocketMeta.text = tr("TY_RK_ROCKET_META") % [
		tr("TY_RK_HERITAGE_N") % [fl, int(fam.get("successes", 0))] if fl > 0 else tr("TY_RK_HERITAGE_NEW"),
		cr(RocketDesigner.unit_cost(state, info["parts"], fl))]
	# the plan and the footer
	var blocked := not DesignReview.blockers(state, project).is_empty()
	var plan := DesignReview.fix_plan(state, project, fixes)
	%Plan.text = tr("TY_RK_PLAN") % [int(plan["weeks"]), cr(float(plan["cost"]))] if not fixes.is_empty() else tr("TY_RK_PLAN_NONE")
	%Blocked.visible = blocked
	var err := ProjectDesk.review_error(state, project, fixes)
	%Error.text = tr(err) if err != "" and not blocked else ""
	%Launch.disabled = err != ""
	%Launch.text = tr("TY_RK_FIX_AND_LAUNCH") if not fixes.is_empty() else tr("TY_RK_LAUNCH")
	if not _scrub_armed:
		%Scrub.text = tr("TY_RK_SCRUB")


func _fill_risks(list: Array) -> void:
	var rows := copies(%RiskTemplate, list.size())
	for i in list.size():
		var rk: Dictionary = list[i]
		var row := rows[i]
		var sev := String(rk["severity"])
		var c: Color = SEV_COLORS.get(sev, CwPalette.TEXT_DIM)
		if rk.get("blocking", false):
			c = CwPalette.DANGER
		(row.get_node("HBox/Dot") as Control).self_modulate = c
		var name_l := row.get_node("HBox/Names/Name") as Label
		name_l.text = tr(String(rk["name_key"]))
		(row.get_node("HBox/Names/Detail") as Label).text = _detail(rk)
		var pl := row.get_node("HBox/Chance/P") as Label
		pl.text = tr("TY_RK_P_FAIL") % ("%.1f" % (float(rk["p"]) * 100.0)) if not rk.get("blocking", false) else tr("TY_RK_NOT_REACH")
		pl.add_theme_color_override("font_color", CwPalette.ink(c))
		var bar := row.get_node("HBox/Chance/Bar") as CwSegmentBar
		bar.value = clampf(float(rk["p"]) / 0.15, 0.0, 1.0)
		bar.color = c
		var fixable := String(rk["fix_key"]) != ""
		var choice := row.get_node("HBox/Choice") as Control
		choice.visible = fixable
		(row.get_node("HBox/NoFix") as Control).visible = not fixable
		if not fixable:
			continue
		var acc := row.get_node("HBox/Choice/Seg/Accept") as Button
		var fix := row.get_node("HBox/Choice/Seg/Fix") as Button
		var id := String(rk["id"])
		acc.set_meta("id", id)
		fix.set_meta("id", id)
		if not fix.has_meta("wired"):
			fix.set_meta("wired", true)
			fix.pressed.connect(func() -> void: _toggle_fix(String(fix.get_meta("id")), true))
			acc.pressed.connect(func() -> void: _toggle_fix(String(acc.get_meta("id")), false))
		var on := id in fixes
		fix.set_pressed_no_signal(on)
		acc.set_pressed_no_signal(not on)
		var cost := float(rk["fix_cost"])
		fix.text = "%s  %s" % [tr("TY_RK_FIX"), tr("TY_RK_FIX_COST") % [int(rk["fix_weeks"]), cr(cost)] if cost > 0.0
			else tr("TY_RK_FIX_WEEKS") % int(rk["fix_weeks"])]
		fix.tooltip_text = tr(String(rk["fix_key"]))
		(row.get_node("HBox/Choice/FixName") as Label).text = tr(String(rk["fix_key"]))


func _detail(rk: Dictionary) -> String:
	var d: Variant = rk.get("detail", "")
	match String(rk["kind"]):
		"component":
			return tr(String(RocketDesigner.component(String(d)).get("name_key", "")))
		"debut":
			var fam := RocketFamilies.find(state, String(project.rocket.get("family", "")))
			var n := RocketFamilies.flights(fam)
			return tr("TY_RK_DETAIL_DEBUT") % [String(d), n] if n > 0 else tr("TY_RK_DETAIL_DEBUT_NEW") % String(d)
		"margin":
			if d is Array and (d as Array).size() >= 2:
				return tr("TY_RK_DETAIL_MARGIN") % [float(d[0]), float(d[1])]
		"payload":
			if d is Array and (d as Array).size() >= 2:
				return tr("TY_RK_DETAIL_PAYLOAD") % [float(d[0]), int(d[1])]
		"crew":
			return tr("TY_RK_DETAIL_CREW")
	return ""


func _part(row: Control, v: float) -> void:
	var bar := row.get_node("Bar") as CwSegmentBar
	bar.value = v
	bar.color = _odds_color(v)
	(row.get_node("Value") as Label).text = "%d%%" % roundi(v * 100.0)


static func _odds_color(v: float) -> Color:
	return CwPalette.AURORA_TEAL if v >= 0.85 else (CwPalette.WARNING if v >= 0.7 else CwPalette.DANGER)


## The advisor: the team's test technician (else the first Cometling) names the riskiest factor.
func _fill_advisor(list: Array) -> void:
	var team := project.team(state)
	var who: Dictionary = team[0] if not team.is_empty() else {}
	for m in team:
		if String(m.get("profession", "")) == "test_technician":
			who = m
			break
	var prof := state.profession(String(who.get("profession", "")))
	%AdvisorBy.text = tr("TY_RK_ADVISOR_BY") % [String(who.get("name", "")), tr(String(prof.get("name_key", "")))]
	var top := DesignReview.riskiest(list)
	if top.is_empty():
		%AdvisorLine.text = ""
		return
	var advice := "TY_RK_ADVICE_ACCEPT"
	if top.get("blocking", false):
		advice = "TY_RK_ADVICE_BLOCK"
	elif String(top["id"]) in fixes:
		advice = "TY_RK_ADVICE_FIXED"
	elif String(top["fix_key"]) != "" and String(top["severity"]) != "low":
		advice = "TY_RK_ADVICE_FIX"
	%AdvisorLine.text = tr("TY_RK_ADVISOR") % [_lower_first(tr(String(top["name_key"]))), tr(advice)]


## "Estágio principal" -> "estágio principal" in a sentence; symbols (Δv) stay as they are.
static func _lower_first(t: String) -> String:
	if t.is_empty() or not "ABCDEFGHIJKLMNOPQRSTUVWXYZÁÉÍÓÚÂÊÔÃÕÇ".contains(t[0]):
		return t
	return t[0].to_lower() + t.substr(1)
