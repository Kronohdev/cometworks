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

## Dev menu only (src/dev/cw_dev.gd): the outcome the next launch() takes, whatever the roll:
## "success" (at least "full"), "partial" or "fail"; "" rolls as usual. Used once, then cleared.
static var dev_force_outcome := ""


# ------------------------------------------------------------ queries
static func find(state: TycoonState, project_id: String) -> MissionProject:
	for p: MissionProject in state.mission_projects:
		if p.id == project_id:
			return p
	return null


## The mission grade's share of the project grade for a launch outcome
## (projects.json launch.outcome_grade: a failed flight keeps 0.35 of it, a partial one 0.8).
static func outcome_grade(outcome: String) -> float:
	return float((ProjectRules.section("launch").get("outcome_grade", {}) as Dictionary).get(outcome, 1.0))


## A history entry's project grade (development x MissionFit, before the flight's outcome);
## entries from saves older than grade_project only have "grade".
static func project_grade(entry: Dictionary) -> float:
	return float(entry.get("grade_project", entry.get("grade", 0.0)))


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


## The payload of a plan ({"payload": [...]}), or the Cometlings' starter kit when it has none.
static func plan_payload(state: TycoonState, type_id: String, target_id: String, plan: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for m in plan.get("payload", []):
		out.append(String(m))
	return out if not out.is_empty() else PayloadRules.default_payload(state, type_id, target_id)


## Why a project cannot start ("" when it can): a translation key.
## `design` as in estimate(); a rocket that does not reach the target cannot start.
## `plan` {"payload": module ids, "briefing_id"}: a payload in the red (mass, energy) cannot
## start, and its cost counts with the money.
static func start_error(state: TycoonState, type_id: String, target_id: String, staff_ids: Array, design := {},
		plan := {}) -> String:
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
	var payload := plan_payload(state, type_id, target_id, plan)
	var est := estimate(state, type_id, d, target_id)
	var perr := PayloadRules.plan_error(state, {"type": type_id, "target": target_id, "payload": payload,
		"weeks": est["weeks"], "dev_cost": est["dev_cost"], "launch_cost": est["launch_cost"],
		"briefing_id": String(plan.get("briefing_id", ""))}, false)
	if perr != "":
		return perr
	if state.cash < float(est["total"]) + PayloadRules.cost(payload):
		return "TY_PJ_ERR_CASH"
	return ""


# ------------------------------------------------------------ commands
## Starts a project (the team gets `assigned`); null when start_error() says no. The phase
## screen should then ask for the first phase's sliders (project_phase_started is emitted).
## `design` {"parts", "family", "name"}: the rocket (RocketDesigner); empty takes the default
## one. A new design becomes a rocket family (RocketFamilies.ensure, named "name" if given).
## `plan` {"payload": module ids (empty: the starter kit), "briefing_id": the briefing it answers
## (its offer leaves the board, BriefingDesk.take)}. The payload is paid now.
static func start_project(state: TycoonState, type_id: String, target_id: String, staff_ids: Array,
		contract_id := "", design := {}, plan := {}) -> MissionProject:
	var d := design if not design.is_empty() else RocketDesigner.default_design(state, type_id, target_id)
	if start_error(state, type_id, target_id, staff_ids, d, plan) != "":
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
	p.payload = plan_payload(state, type_id, target_id, plan)
	var pc := PayloadRules.cost(p.payload)
	state.cash -= pc
	p.cost_spent += pc
	var bid := String(plan.get("briefing_id", ""))
	if not BriefingDesk.briefing(bid).is_empty():
		p.briefing_id = bid
		p.briefing_terms = BriefingDesk.take(state, bid, p.id).duplicate()
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
	BriefingDesk.week(state)
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
		"pad":
			if not state.pilot_gate:
				launch(state, p, {"auto": true})
			else:
				state.launch_pad_ready.emit(p.id)  # still on the pad: remind the player


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


## A new rocket for a project still in development (the campus workshop's hangar): it is built
## during the development (the project lasts at least the rocket's build weeks). Returns false
## if the design does not reach the target or the project is past its development.
static func swap_rocket(state: TycoonState, project_id: String, design: Dictionary) -> bool:
	var p := find(state, project_id)
	if p == null or p.review_state != "":
		return false
	var parts: Dictionary = design.get("parts", {})
	if not RocketDesigner.buildable(state, parts) or not RocketDesigner.check(state, parts, p.type_id, p.target_id)["reaches"]:
		return false
	var fam := RocketFamilies.ensure(state, parts, String(design.get("name", "")))
	p.rocket = {"family": String(fam["id"]), "parts": RocketDesigner.normalize(fam["parts"])}
	p.weeks_total = maxi(p.weeks_total, RocketDesigner.build_weeks(state, parts, RocketFamilies.flights(fam)))
	sync_strips(state)
	state.changed.emit()
	return true


## Projects on the pad waiting for the player's launch choice (a rocket built in the hangar).
static func waiting_pad(state: TycoonState) -> Array[MissionProject]:
	var out: Array[MissionProject] = []
	for p: MissionProject in state.mission_projects:
		if p.review_state == "pad":
			out.append(p)
	return out


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
	if p.briefing_id != "":
		BriefingDesk.release(state, p.briefing_id)
	state.reputation = maxf(state.reputation - float(DesignReview.cfg().get("scrub_reputation", 1.0)), 0.0)
	state.news.push_front({"key": "TY_RK_NEWS_SCRUB", "args": [p.code]})
	sync_strips(state)
	state.changed.emit()
	return true


# ------------------------------------------------------------ dev menu (src/dev/cw_dev.gd)
## Dev only: works the project's current phase to its end at once (no week passes, nothing is
## paid). Then, as a week would: the next phase asks for its sliders (project_phase_started)
## or development ends (the Design Review waits, or it launches with the gate off). A project
## in its review's fixes or rebuild counts them down to the end. False if there is nothing to do.
static func dev_finish_phase(state: TycoonState, project_id: String) -> bool:
	var p := find(state, project_id)
	if p == null or p.review_state == "waiting":
		return false
	if p.review_state != "":
		p.review_weeks = 1
		_review_week(state, p)
		sync_strips(state)
		state.changed.emit()
		return true
	var new_phase := false
	while not p.is_done() and not new_phase:
		new_phase = p.work_week(state)
	if p.is_done():
		_development_done(state, p)
	else:
		sync_strips(state)
		state.project_phase_started.emit(p.id, p.phase)
	sync_strips(state)
	state.changed.emit()
	return true


## Dev only: dev_finish_phase() until the project leaves development (its Design Review).
static func dev_finish_development(state: TycoonState, project_id: String) -> bool:
	var any := false
	for i in 4:
		var p := find(state, project_id)
		if p == null or p.review_state == "waiting":
			break
		any = dev_finish_phase(state, project_id) or any
	return any


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
## A rocket built in the hangar first stops on the pad when state.pilot_gate is on (review_state
## "pad", launch_pad_ready; returns {}): the player flies it (TycoonModes) or lets it be
## simulated. `flight` is that choice: {"auto": true} rolls as usual; a piloted flight's verdict
## (HangarRocket.flight_verdict: "outcome" "success" | "partial" | "fail", "cause_key",
## "flight") replaces the roll: a success is graded as usual, "partial" stays partial, a failure
## names the flight's cause.
static func launch(state: TycoonState, p: MissionProject, flight := {}) -> Dictionary:
	if flight.is_empty() and state.pilot_gate and p.review_state != "pad" and HangarRocket.is_hangar(p.rocket.get("parts", {})):
		p.review_state = "pad"
		p.review_weeks = 0
		state.news.push_front({"key": "TY_HG_NEWS_PAD", "args": [p.code]})
		sync_strips(state)
		state.launch_pad_ready.emit(p.id)
		state.changed.emit()
		return {}
	var piloted := flight.has("outcome")
	var l := ProjectRules.section("launch")
	var rw := ProjectRules.section("rewards")
	var history := state.project_history
	# the development grade, then how well the plan fit its hidden ideals (MissionFit)
	var grade_dev := p.grade(state, history)
	var report := MissionFit.evaluate(state, MissionFit.ctx_of(state, p))
	var grade := MissionFit.apply(grade_dev, report)
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
	var forced := dev_force_outcome
	dev_force_outcome = ""
	if forced != "":
		success = forced != "fail"
	if piloted:
		forced = ""
		success = String(flight["outcome"]) != "fail"
	var cause := {}
	if not success and piloted:
		cause = {"id": "flight", "cause_key": String(flight.get("cause_key", "TY_HG_CAUSE_LOST"))}
	elif not success:
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
		if forced == "partial" or (piloted and String(flight["outcome"]) == "partial"):
			outcome = "partial"
		elif forced == "success" and outcome == "partial":
			outcome = "full"
	# the mission's grade counts the flight too: a blown launch can't score 10 however well it was
	# built (projects.json launch.outcome_grade). The project's own grade (development x fit) stays
	# as grade_project: the outcome above, the press (it shifts by the outcome itself), the client,
	# the journal and the crew's XP read that one, so a failure is not counted twice
	var grade_project := grade
	grade = grade_project * outcome_grade(outcome)
	# the family's heritage, and the recovered stage's refund after a good flight
	RocketFamilies.record_flight(state, String(rocket["family"]), success)
	var refund := float(RocketDesigner.stats(rocket["parts"])["refund"]) if success else 0.0
	state.cash += refund
	var reviews := ReviewBoard.review(state.rng, {"grade": grade_project, "outcome": outcome, "novelty": novelty,
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
	if report.get("great", false) and success:
		hype += float((BriefingDesk.disc().get("great", {}) as Dictionary).get("hype", 6.0))
	state.hype += hype
	# the briefing's client pays by the result; the journal writes down what this flight taught
	var brief := {}
	if p.briefing_id != "":
		brief = BriefingDesk.complete(state, p, grade_project, success)
		brief["id"] = p.briefing_id
	var learned := Discovery.record(state, p, report, grade_project, success)
	var feedback := MissionFit.feedback(state, report, p.type_id, p.target_id)
	if not success:
		# the rocket failed: say so first; a great plan is no great combo without a flight
		var kept: Array[Dictionary] = [{"key": "TY_FB_LAUNCH_FAIL", "args": [], "tone": "bad", "topic": "launch"}]
		for f in feedback:
			if String(f["tone"]) != "star" and kept.size() < int(BriefingDesk.disc().get("feedback_max", 5)):
				kept.append(f)
		feedback = kept
	var research := 0.0
	if suborbital:
		research = science * float(rw.get("research_per_science", 0.5))
		state.research_points += research
	var xp := float(rw.get("xp_per_week", 12.0)) * p.weeks_total * (float(rw.get("xp_grade_floor", 0.5)) + grade_project / 10.0) \
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
		"cause_key": cause_key, "grade_dev": grade_dev, "grade_project": grade_project, "payload": p.payload_or_default(state).duplicate(),
		"fit": {"fit": report["fit"], "mult": report["mult"], "great": report["great"], "instrument": report["instrument"],
			"power": report["power"], "data": report["data"], "team": report["team"], "objective": report["objective"],
			"match": report["match"]},
		"feedback": feedback, "learned": learned, "briefing": brief, "piloted": piloted,
		"flight": (flight.get("flight", {}) as Dictionary).duplicate() if piloted else {},
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
		"grade_project": grade_project, "success": success, "outcome": outcome, "contract_id": p.contract_id, "review_avg": avg,
		"p_success": chance["total"], "pad": pad, "rocket": rocket, "cause": String(cause.get("id", "")),
		"cause_key": cause_key, "piloted": piloted}
	if success and not suborbital:
		var am := {"id": p.id, "code": p.code, "type": p.type_id, "target": p.target_id,
			"start_week": state.weeks, "weeks_total": ProjectRules.ops_weeks(p.type_id), "data_stored": 0.0,
			"data_down": 0.0, "science": 0.0, "status": "cruise", "science_goal": science, "grade": grade,
			"contract_id": p.contract_id, "outcome": outcome, "success": success, "project_id": p.id}
		# the payload drives the operations: its data, storage, antenna, science value, night and cold
		am.merge(MissionFit.ops_fields(state, p.type_id, p.payload_or_default(state), report), true)
		state.active_missions.append(am)
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
			"pad":
				line = TranslationServer.translate("TY_HG_STRIP_PAD")
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
	# saves from before the mission grade: their "grade" was the project grade
	for h: Dictionary in state.project_history:
		if not h.has("grade_project"):
			h["grade_project"] = float(h.get("grade", 0.0))
			h["grade"] = float(h["grade_project"]) * outcome_grade(String(h.get("outcome", "full")))
	sync_strips(state)
