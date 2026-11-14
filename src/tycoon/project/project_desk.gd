class_name ProjectDesk
extends RefCounted
## The agency's project desk (GDD sections 6.2-6.6, E2): starts mission projects (each with a
## rocket from the designer, RocketDesigner / RocketFamilies), runs their weeks, holds them for
## the Design Review when development ends (DesignReview: fix, accept or scrub), launches them,
## has the 4 newspapers review them and pays the rewards. Static functions over a TycoonState
## (no scene access); the state keeps the data:
##   state.mission_projects  MissionProject objects in development
##   state.project_history   one entry per launched project (grade, reviews, rewards...),
##                           newest last; drives expectations, novelty and compat discovery
##   state.projects          the bottom-strip view the HUD draws (code, phase, progress, colour)
## TycoonState.advance_week() calls ProjectDesk.advance_week(self) once per week.


# ------------------------------------------------------------ queries
static func find(state: TycoonState, project_id: String) -> MissionProject:
	for p: MissionProject in state.mission_projects:
		if p.id == project_id:
			return p
	return null


## The history entry (review data) of a launched project, {} if none.
static func history_entry(state: TycoonState, project_id: String) -> Dictionary:
	for i in range(state.project_history.size() - 1, -1, -1):
		if String(state.project_history[i].get("id", "")) == project_id:
			return state.project_history[i]
	return {}


static func free_staff(state: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in state.staff:
		if String(m.get("assigned", "")) == "":
			out.append(m)
	return out


## Accepted contracts no project is working on yet (quick picks of the new project screen).
static func open_contracts(state: TycoonState) -> Array[Dictionary]:
	var busy := {}
	for p: MissionProject in state.mission_projects:
		if p.contract_id != "":
			busy[p.contract_id] = true
	var out: Array[Dictionary] = []
	for c in state.contracts:
		if String(c.get("status", "")) == "accepted" and not busy.has(String(c.get("id", ""))):
			out.append(c)
	return out


static func contract(state: TycoonState, contract_id: String) -> Dictionary:
	for c in state.contracts:
		if String(c.get("id", "")) == contract_id:
			return c
	return {}


## Has the agency already flown this type on this target? (The compat matrix is discovered
## by playing, GDD 6.2.)
static func compat_known(state: TycoonState, type_id: String, target_id: String) -> bool:
	for h in state.project_history:
		if String(h.get("type", "")) == type_id and String(h.get("target", "")) == target_id:
			return true
	return false


static func is_novel(state: TycoonState, type_id: String, target_id: String) -> bool:
	for h in state.project_history:
		if String(h.get("type", "")) == type_id or String(h.get("target", "")) == target_id:
			return false
	return true


static func next_code(state: TycoonState, type_id: String) -> String:
	var n := 1
	for h in state.project_history:
		if String(h.get("type", "")) == type_id:
			n += 1
	for p: MissionProject in state.mission_projects:
		if p.type_id == type_id:
			n += 1
	return "%s-%02d" % [String(state.mission_type(type_id).get("code", "MSN")), n]


## {"weeks", "week_cost", "dev_cost", "launch_cost", "total", "rocket_weeks"} for a new project of
## this type with this rocket (`design` {"parts", "family"}; empty: the default rocket for the
## target, RocketDesigner.default_design). The project lasts the type's weeks, or the rocket's
## build weeks when they are longer; the launch costs one unit of the rocket.
static func estimate(state: TycoonState, type_id: String, design := {}, target_id := "") -> Dictionary:
	var mt := state.mission_type(type_id)
	var wk := maxi(int(mt.get("weeks", 3)), 3)
	var wc := ProjectRules.week_cost(mt, state.era())
	var d := design
	if d.is_empty():
		d = RocketDesigner.default_design(state, type_id, target_id if target_id != "" else default_target(state, type_id))
	var lc := ProjectRules.launch_cost(type_id)
	var rw := 0
	if not d.is_empty():
		var fl := RocketFamilies.flights(_family_of(state, d))
		lc = RocketDesigner.unit_cost(state, d.get("parts", {}), fl)
		rw = RocketDesigner.build_weeks(state, d.get("parts", {}), fl)
		wk = maxi(wk, rw)
	return {"weeks": wk, "week_cost": wc, "dev_cost": wc * wk, "launch_cost": lc, "total": wc * wk + lc, "rocket_weeks": rw}


## The family of a design: its "family" id, else the family with the same parts ({} if new).
static func _family_of(state: TycoonState, design: Dictionary) -> Dictionary:
	var f := RocketFamilies.find(state, String(design.get("family", "")))
	if f.is_empty() or not RocketDesigner.same_parts(f.get("parts", {}), design.get("parts", {})):
		f = RocketFamilies.find_parts(state, design.get("parts", {}))
	return f


## The best target for a type the agency can fly now (the highest compatibility), "" if none.
static func default_target(state: TycoonState, type_id: String) -> String:
	var best := ""
	var best_c := 0.0
	var cmp: Dictionary = state.mission_type(type_id).get("compat", {})
	for t: String in cmp:
		if state.mission_target_available(t) and float(cmp[t]) > best_c:
			best_c = float(cmp[t])
			best = t
	return best


## Why a project cannot start ("" when it can): a translation key.
## `design` as in estimate(); a rocket that does not reach the target cannot start.
static func start_error(state: TycoonState, type_id: String, target_id: String, staff_ids: Array, design := {}) -> String:
	if not state.mission_target_available(target_id):
		return "TY_PJ_ERR_TARGET"
	if not state.mission_type_available(type_id):
		return "TY_PJ_ERR_TYPE"
	if ProjectRules.compat(state.mission_type(type_id), target_id) <= 0.0:
		return "TY_PJ_ERR_IMPOSSIBLE"
	if staff_ids.is_empty():
		return "TY_PJ_ERR_TEAM"
	for sid in staff_ids:
		var ok := false
		for m in free_staff(state):
			if String(m["id"]) == String(sid):
				ok = true
		if not ok:
			return "TY_PJ_ERR_BUSY"
	if ProjectRules.is_crewed(type_id):
		var pilot := false
		for m in state.staff:
			if String(m["id"]) in staff_ids and String(m.get("profession", "")) == "pilot":
				pilot = true
		if not pilot:
			return "TY_PJ_ERR_PILOT"
	var d := design if not design.is_empty() else RocketDesigner.default_design(state, type_id, target_id)
	if d.is_empty():
		return "TY_PJ_ERR_NO_ROCKET"
	var dp: Dictionary = d.get("parts", {})
	if not RocketDesigner.buildable(state, dp) or not RocketDesigner.check(state, dp, type_id, target_id)["reaches"]:
		return "TY_PJ_ERR_ROCKET"
	if state.cash < float(estimate(state, type_id, d, target_id)["total"]):
		return "TY_PJ_ERR_CASH"
	return ""


# ------------------------------------------------------------ commands
## Starts a project (the team gets `assigned`); null when start_error() says no. The phase
## screen should then ask for the first phase's sliders (project_phase_started is emitted).
## `design` {"parts", "family", "name"}: the rocket (RocketDesigner); empty takes the default
## one. A new design becomes a rocket family (RocketFamilies.ensure, named "name" if given).
static func start_project(state: TycoonState, type_id: String, target_id: String, staff_ids: Array,
		contract_id := "", design := {}) -> MissionProject:
	var d := design if not design.is_empty() else RocketDesigner.default_design(state, type_id, target_id)
	if start_error(state, type_id, target_id, staff_ids, d) != "":
		return null
	var fam := _family_of(state, d)
	if fam.is_empty():
		fam = RocketFamilies.ensure(state, d.get("parts", {}), String(d.get("name", "")))
	elif String(d.get("name", "")).strip_edges() != "":
		fam["name"] = String(d["name"]).strip_edges()
	var p := MissionProject.new()
	p.code = next_code(state, type_id)
	p.id = p.code
	p.type_id = type_id
	p.target_id = target_id
	p.contract_id = contract_id
	for sid in staff_ids:
		p.staff_ids.append(String(sid))
	p.start_week = state.weeks
	p.rocket = {"family": String(fam["id"]), "parts": RocketDesigner.normalize(fam["parts"])}
	p.weeks_total = int(estimate(state, type_id, p.rocket, target_id)["weeks"])
	p.awaiting_sliders = true
	for m in state.staff:
		if String(m["id"]) in p.staff_ids:
			m["assigned"] = p.id
	state.mission_projects.append(p)
	state.news.push_front({"key": "TY_PJ_NEWS_STARTED", "args": [p.code, String(state.mission_type(type_id).get("name_key", ""))]})
	sync_strips(state)
	state.project_phase_started.emit(p.id, 0)
	state.changed.emit()
	return p


## Sets the slider percents of the project's current phase (3 ints summing to 100).
static func set_sliders(state: TycoonState, project_id: String, values: Array) -> void:
	var p := find(state, project_id)
	if p == null or values.size() != 3:
		return
	var v: Array = [int(values[0]), int(values[1]), int(values[2])]
	var s: int = v[0] + v[1] + v[2]
	if s != 100:  # keep the invariant even if a caller is sloppy
		v[2] = maxi(100 - v[0] - v[1], 0)
	p.sliders[p.phase] = v
	p.awaiting_sliders = false
	state.changed.emit()


# ------------------------------------------------------------ the week
## One week for every project on the desk: pay the week, then work (maybe a new phase:
## project_phase_started), or count down the Design Review's fixes / rebuild. A project whose
## development ends goes to its Design Review (review_gate on: it waits for the player,
## project_review_ready) or straight to the launch with the review's defaults (gate off).
static func advance_week(state: TycoonState) -> void:
	for p: MissionProject in state.mission_projects.duplicate():
		var wc := ProjectRules.week_cost(p.mission_type(state), state.era())
		state.cash -= wc
		p.cost_spent += wc
		if p.review_state != "":
			_review_week(state, p)
			continue
		var new_phase := p.work_week(state)
		if p.is_done():
			_development_done(state, p)
		elif new_phase:
			sync_strips(state)
			state.project_phase_started.emit(p.id, p.phase)
	sync_strips(state)


static func _development_done(state: TycoonState, p: MissionProject) -> void:
	if not state.review_gate:
		launch(state, p)
		return
	p.review_state = "waiting"
	p.review_weeks = 0
	state.news.push_front({"key": "TY_RK_NEWS_REVIEW", "args": [p.code]})
	sync_strips(state)
	state.project_review_ready.emit(p.id)


static func _review_week(state: TycoonState, p: MissionProject) -> void:
	match p.review_state:
		"waiting":
			if not state.review_gate:
				launch(state, p)
			else:
				state.project_review_ready.emit(p.id)  # the launch is ready: remind the player
		"fixing":
			p.review_weeks -= 1
			if p.review_weeks <= 0:
				launch(state, p)
		"rebuild":
			p.review_weeks -= 1
			if p.review_weeks <= 0:
				p.review_state = ""
				_development_done(state, p)


# ------------------------------------------------------------ the Design Review (E2)
## Projects waiting for the player's Design Review.
static func waiting_review(state: TycoonState) -> Array[MissionProject]:
	var out: Array[MissionProject] = []
	for p: MissionProject in state.mission_projects:
		if p.review_state == "waiting":
			out.append(p)
	return out


## Why the review cannot send the rocket up ("" when it can): a translation key.
static func review_error(state: TycoonState, p: MissionProject, fixes: Array) -> String:
	if p == null or p.review_state != "waiting":
		return "TY_RK_ERR_NOT_READY"
	if not DesignReview.blockers(state, p).is_empty():
		return "TY_RK_ERR_BLOCKED"
	if state.cash < float(DesignReview.fix_plan(state, p, fixes)["cost"]):
		return "TY_RK_ERR_CASH"
	return ""


## The player's decision on a waiting project: the risks in `fixes` are fixed (their money now,
## their weeks in parallel, then the launch), the others accepted. No fixes: it launches now.
## Returns false when review_error() says no.
static func confirm_review(state: TycoonState, project_id: String, fixes: Array = []) -> bool:
	var p := find(state, project_id)
	if review_error(state, p, fixes) != "":
		return false
	var fixable := {}
	for rk in DesignReview.risks(state, p, []):
		if String(rk["fix_key"]) != "":
			fixable[String(rk["id"])] = true
	p.review_fixes.clear()
	for f in fixes:
		if fixable.has(String(f)) and String(f) not in p.review_fixes:
			p.review_fixes.append(String(f))
	var plan := DesignReview.fix_plan(state, p, p.review_fixes)
	state.cash -= float(plan["cost"])
	p.cost_spent += float(plan["cost"])
	if int(plan["weeks"]) > 0:
		p.review_state = "fixing"
		p.review_weeks = int(plan["weeks"])
		state.news.push_front({"key": "TY_RK_NEWS_FIXING", "args": [p.code, int(plan["weeks"])]})
		sync_strips(state)
		state.changed.emit()
	else:
		launch(state, p)
	return true


## A new rocket for a waiting project (the review's "change rocket"): it is built (its weeks),
## then the review comes back. Returns false if the design does not reach the target.
static func change_rocket(state: TycoonState, project_id: String, design: Dictionary) -> bool:
	var p := find(state, project_id)
	if p == null or p.review_state != "waiting":
		return false
	var parts: Dictionary = design.get("parts", {})
	if not RocketDesigner.buildable(state, parts) or not RocketDesigner.check(state, parts, p.type_id, p.target_id)["reaches"]:
		return false
	if RocketDesigner.same_parts(parts, p.rocket.get("parts", {})):
		var keep := RocketFamilies.find(state, String(p.rocket.get("family", "")))
		if String(design.get("name", "")).strip_edges() != "" and not keep.is_empty():
			keep["name"] = String(design["name"]).strip_edges()
		state.changed.emit()
		return true
	var fam := RocketFamilies.ensure(state, parts, String(design.get("name", "")))
	p.rocket = {"family": String(fam["id"]), "parts": RocketDesigner.normalize(fam["parts"])}
	p.review_fixes.clear()
	p.review_state = "rebuild"
	p.review_weeks = RocketDesigner.build_weeks(state, parts, RocketFamilies.flights(fam))
	state.news.push_front({"key": "TY_RK_NEWS_REBUILD", "args": [p.code, String(fam["name"]), p.review_weeks]})
	sync_strips(state)
	state.changed.emit()
	return true


## Scrubs the launch: the project is cancelled before it flies (the team is freed, a contract
## fails, the reputation drops by rockets.json review.scrub_reputation). The rocket stays home.
static func scrub(state: TycoonState, project_id: String) -> bool:
	var p := find(state, project_id)
	if p == null:
		return false
	state.mission_projects.erase(p)
	for m in state.staff:
		if String(m.get("assigned", "")) == p.id:
			m["assigned"] = ""
	if p.contract_id != "":
		state.complete_contract(p.contract_id, 0.0, false)
	state.reputation = maxf(state.reputation - float(DesignReview.cfg().get("scrub_reputation", 1.0)), 0.0)
	state.news.push_front({"key": "TY_RK_NEWS_SCRUB", "args": [p.code]})
	sync_strips(state)
	state.changed.emit()
	return true


# ------------------------------------------------------------ launch and review (GDD 6.6)
## Chance of success (DesignReview.odds with the project's review fixes):
##   rocket  = the product of (1 - p) of the rocket's risks: components, the family's flight
##             heritage, thin delta-v / lift margins
##   payload = clamp(0.55 + 0.45 * normalised reliability fraction - 0.03 * defects, 0.30, 0.99)
##   crew    = lerp(0.85, 1, the crew's courage) on crewed flights
##   total   = rocket * payload * crew
static func success_chance(state: TycoonState, p: MissionProject) -> Dictionary:
	if p.rocket.is_empty():
		var d := RocketDesigner.default_design(state, p.type_id, p.target_id)
		var fam := _family_of(state, d) if not d.is_empty() else {}
		if not d.is_empty():
			p.rocket = {"family": String(fam.get("id", "")), "parts": d["parts"]}
	var o := DesignReview.odds(state, p)
	return {"payload": o["payload"], "rocket": o["rocket"], "crew": o["crew"], "total": o["total"], "risks": o["risks"]}


## A short look of the project's rocket for the launch, the pad and the papers:
## {"family", "name", "parts", "class", "flights"}.
static func rocket_info(state: TycoonState, p: MissionProject) -> Dictionary:
	var parts := RocketDesigner.normalize(p.rocket.get("parts", {}))
	var fam := RocketFamilies.find(state, String(p.rocket.get("family", "")))
	return {"family": String(fam.get("id", "")), "name": String(fam.get("name", "")), "parts": parts,
		"class": String(RocketDesigner.stats(parts)["class"]), "flights": RocketFamilies.flights(fam)}


## Development is over: grade, launch roll, reviews, rewards; the project leaves the desk.
## Returns the history entry it wrote.
static func launch(state: TycoonState, p: MissionProject) -> Dictionary:
	var l := ProjectRules.section("launch")
	var rw := ProjectRules.section("rewards")
	var history := state.project_history
	var grade := p.grade(state, history)
	var bars := p.bar_scores(state, history)
	var expected := MissionProject.expected_points(state, p.type_id, history)
	var chance := success_chance(state, p)
	var novelty := is_novel(state, p.type_id, p.target_id)
	var rocket := rocket_info(state, p)
	var fam := RocketFamilies.find(state, String(rocket["family"]))
	var launch_cost := RocketDesigner.unit_cost(state, rocket["parts"], RocketFamilies.flights(fam)) \
		if not p.rocket.is_empty() else ProjectRules.launch_cost(p.type_id)
	state.cash -= launch_cost
	# the pad it leaves from (LaunchPads: the class's pad, else the one with a rocket ready, alternating)
	var cls := String(rocket["class"])
	var pad := LaunchPads.pick(state, cls)
	LaunchPads.launched(state, pad, rocket["parts"])
	var roll := state.rng.randf()
	var success := roll < float(chance["total"])
	var cause := {}
	if not success:
		cause = DesignReview.pick_cause(chance["risks"], state.rng.randf())
	var outcome := "fail"
	if success:
		outcome = "partial"
		if grade >= float(l.get("exceptional_grade", 8.5)):
			outcome = "exceptional"
		elif grade >= float(l.get("full_grade", 5.5)):
			outcome = "full"
		var c := contract(state, p.contract_id)
		for bar: String in c.get("min_bars", {}):
			var bi := ProjectRules.BARS.find(bar)
			if bi >= 0 and bars[bi] < float(c["min_bars"][bar]):
				outcome = "partial"
	# the family's heritage, and the recovered stage's refund after a good flight
	RocketFamilies.record_flight(state, String(rocket["family"]), success)
	var refund := float(RocketDesigner.stats(rocket["parts"])["refund"]) if success else 0.0
	state.cash += refund
	var reviews := ReviewBoard.review(state.rng, {"grade": grade, "outcome": outcome, "novelty": novelty,
		"crewed": ProjectRules.is_crewed(p.type_id), "hype": state.hype, "bar_scores": bars, "defects": p.residual_defects(),
		"q": p.total_points() / maxf(expected, 0.001), "contract": p.contract_id != ""})
	var avg := ReviewBoard.average(reviews)
	var compat := p.compat(state)
	var science := p.pts[ProjectRules.SCI] * float(rw.get("science_per_point", 1.0)) \
		* float(l.get("science_mult", {}).get(outcome, 0.0)) * compat
	var suborbital := p.target_id == "suborbital" or ProjectRules.ops_weeks(p.type_id) <= 0
	# rewards
	var cash0 := state.cash
	if p.contract_id != "":
		state.complete_contract(p.contract_id, avg, success)
	var rep := clampf(avg - float(rw.get("reputation_pivot", 5.0)), -float(rw.get("reputation_cap", 5.0)),
		float(rw.get("reputation_cap", 5.0)))
	state.reputation = maxf(state.reputation + rep, 0.0)
	var hype := avg * avg / float(rw.get("hype_div", 5.0))
	state.hype += hype
	var research := 0.0
	if suborbital:
		research = science * float(rw.get("research_per_science", 0.5))
		state.research_points += research
	var xp := float(rw.get("xp_per_week", 12.0)) * p.weeks_total * (float(rw.get("xp_grade_floor", 0.5)) + grade / 10.0) \
		+ p.training_xp
	# levels, the training centre and mentors live in the crew rules; launch morale too
	# (TycoonCrew.mission_result reacts to mission_launched, while the team is still assigned)
	for sid in p.staff_ids:
		TycoonCrew.add_xp(state, String(sid), xp)
	var risk_rows: Array = []
	for rk: Dictionary in chance["risks"]:
		risk_rows.append({"id": rk["id"], "kind": rk["kind"], "name_key": rk["name_key"], "p": rk["p"], "fixed": rk["fixed"]})
	var cause_key := String(cause.get("cause_key", ""))
	var entry := {"id": p.id, "code": p.code, "type": p.type_id, "target": p.target_id, "contract_id": p.contract_id,
		"week": state.weeks, "start_week": p.start_week, "weeks": p.weeks_total, "staff": p.staff_ids.duplicate(),
		"grade": grade, "bars": bars, "pts": p.pts.duplicate(), "defects": p.residual_defects(), "expected": expected,
		"compat": compat, "novelty": novelty, "p_success": chance["total"], "p_payload": chance["payload"],
		"p_rocket": chance["rocket"], "p_crew": chance["crew"], "launch_class": cls, "pad": pad, "success": success,
		"outcome": outcome, "reviews": reviews, "review_avg": avg, "science": science, "suborbital": suborbital,
		"rocket": rocket, "risks": risk_rows, "fixes": p.review_fixes.duplicate(), "cause": String(cause.get("id", "")),
		"cause_key": cause_key,
		"rewards": {"cash": state.cash - cash0, "reputation": rep, "hype": hype, "research": research, "xp": xp,
			"dev_cost": p.cost_spent, "launch_cost": launch_cost, "refund": refund}}
	state.project_history.append(entry)
	state.mission_projects.erase(p)
	if success:
		state.news.push_front({"key": "TY_PJ_NEWS_SUCCESS", "args": [p.code, "%.1f" % avg]})
	elif cause_key != "":
		state.news.push_front({"key": "TY_RK_NEWS_FAIL_CAUSE", "args": [p.code, cause_key, "%.1f" % avg]})
	else:
		state.news.push_front({"key": "TY_PJ_NEWS_FAIL", "args": [p.code, "%.1f" % avg]})
	sync_strips(state)
	var result := {"project_id": p.id, "code": p.code, "type": p.type_id, "target": p.target_id, "grade": grade,
		"success": success, "outcome": outcome, "contract_id": p.contract_id, "review_avg": avg,
		"p_success": chance["total"], "pad": pad, "rocket": rocket, "cause": String(cause.get("id", "")),
		"cause_key": cause_key}
	if success and not suborbital:
		state.active_missions.append({"id": p.id, "code": p.code, "type": p.type_id, "target": p.target_id,
			"start_week": state.weeks, "weeks_total": ProjectRules.ops_weeks(p.type_id), "data_stored": 0.0,
			"data_down": 0.0, "science": 0.0, "status": "cruise", "science_goal": science, "grade": grade,
			"contract_id": p.contract_id, "outcome": outcome, "success": success, "project_id": p.id})
	state.mission_launching.emit(result)
	state.mission_launched.emit(result)
	for m in state.staff:
		if String(m.get("assigned", "")) == p.id:
			m["assigned"] = ""
	if suborbital or not success:
		var done := result.duplicate()
		done["science"] = science
		state.mission_completed.emit(done)
	if not success and state.race:
		state.race.report_launch_failure(entry)  # the paper's front page names what broke
	state.changed.emit()
	return entry


# ------------------------------------------------------------ HUD strips, save / load
## Rebuilds state.projects (the bottom strips) from the projects in development.
static func sync_strips(state: TycoonState) -> void:
	state.projects.clear()
	for p: MissionProject in state.mission_projects:
		var mt := p.mission_type(state)
		var ideal := p.ideal(state)
		var top := 0
		for b in 4:
			if ideal[b] > ideal[top]:
				top = b
		var ph := ProjectRules.phase(p.phase)
		var line := TranslationServer.translate("TY_PJ_STRIP_PHASE") % [
				TranslationServer.translate(String(ph.get("name_key", ""))), p.phase + 1]
		match p.review_state:
			"waiting":
				line = TranslationServer.translate("TY_RK_STRIP_REVIEW")
			"fixing":
				line = TranslationServer.translate("TY_RK_STRIP_FIXING") % p.review_weeks
			"rebuild":
				line = TranslationServer.translate("TY_RK_STRIP_REBUILD") % p.review_weeks
		state.projects.append({"id": p.id, "code": "%s · %s" % [p.code, TranslationServer.translate(String(mt.get("name_key", "")))],
			"kind": p.type_id, "phase": line, "review": p.review_state,
			"progress": p.progress(), "color": CwPalette.BARS[ProjectRules.BARS[top]]})


static func save(state: TycoonState) -> Array:
	var out: Array = []
	for p: MissionProject in state.mission_projects:
		out.append(p.to_dict())
	return out


## from_dict() hook: projects and history back from a save, strips rebuilt.
static func restore(state: TycoonState, d: Dictionary) -> void:
	state.mission_projects.clear()
	for pd: Dictionary in d.get("mission_projects", []):
		state.mission_projects.append(MissionProject.from_dict(pd))
	state.project_history.assign(d.get("project_history", []))
	sync_strips(state)
