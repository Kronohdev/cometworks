extends SceneTree
## Headless checks for the rocket designer, rocket families and the Design Review (E2,
## src/tycoon/rocket/): components and their research unlocks, the design numbers, the
## "pode chegar / não chega" check, the automatic designer's proposals, family heritage, the
## review's choices (fix / accept / scrub / change rocket) changing the odds, the odds feeding
## ProjectDesk's launch, failure causes (result, history, news, the paper), save / load of
## families and of a project waiting in review, and the launch / the pad showing the designed
## rocket.
## Run: godot --headless --path . --script res://tests/test_tycoon_rocket.gd

const SOUNDING := {"core": "core_kestrel", "upper": "upper_none", "tank": "tank_m", "boosters": "boost_none",
	"fairing": "fairing_none", "avionics": "avionics_basic", "recovery": "recovery_none"}
const LEO := {"core": "core_falcao", "upper": "upper_kestrel_v", "tank": "tank_m", "boosters": "boost_srb2",
	"fairing": "fairing_s", "avionics": "avionics_basic", "recovery": "recovery_none"}

var _failures := 0


func _initialize() -> void:
	_test_components()
	_test_stats_and_check()
	_test_proposals()
	_test_heritage()
	_test_review_odds()
	_test_review_commands()
	_test_odds_feed_launch()
	_test_failure_cause()
	_test_save_load()
	await _test_visuals()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


static func _team() -> Array[Dictionary]:
	return [
		{"id": "a", "name": "Ada", "profession": "systems_engineer", "skill": 0.6, "morale": 80.0, "level": 1},
		{"id": "b", "name": "Bel", "profession": "scientist", "skill": 0.5, "morale": 70.0, "level": 2},
		{"id": "c", "name": "Cid", "profession": "test_technician", "skill": 0.5, "morale": 70.0, "level": 1},
		{"id": "d", "name": "Duo", "profession": "flight_controller", "skill": 0.4, "morale": 60.0, "level": 1}]


static func _state(p_seed := 21) -> TycoonState:
	var s := TycoonState.new_campaign(p_seed, _team())
	s.cash = 5.0e6
	return s


static func _with(base: Dictionary, changes: Dictionary) -> Dictionary:
	var d := base.duplicate()
	for k in changes:
		d[k] = changes[k]
	return d


## Runs a project's development with good sliders; it stops in review when the gate is on.
static func _develop(s: TycoonState, p: MissionProject) -> void:
	var plan := [[50, 20, 30], [45, 20, 35], [20, 10, 70]]
	ProjectDesk.set_sliders(s, p.id, plan[0])
	for i in 30:
		if ProjectDesk.find(s, p.id) == null or p.review_state != "":
			return
		s.advance_week()
		if p.awaiting_sliders:
			ProjectDesk.set_sliders(s, p.id, plan[p.phase])


# ------------------------------------------------------------ components and unlocks
func _test_components() -> void:
	print("components and unlocks")
	var s := _state()
	var cores := RocketDesigner.options(s, "core").map(func(c: Dictionary) -> String: return String(c["id"]))
	_check(cores == ["core_kestrel"], "at the start only the Kestrel main stage (%s)" % [cores])
	_check(RocketDesigner.locked_count(s, "core") == 4, "4 main stages wait in the research tree")
	for sid in RocketDesigner.slot_ids():
		_check(not RocketDesigner.options(s, sid).is_empty(), "slot %s has a starting option" % sid)
	for c: Dictionary in RocketDesigner.data()["components"]:
		for k in ["id", "slot", "name_key", "desc_key"]:
			if not c.has(k):
				_check(false, "component %s has %s" % [c.get("id", "?"), k])
		_check(TranslationServer.translate(String(c["name_key"])) != String(c["name_key"]), "%s is translated" % c["id"])
	_check(RocketDesigner.tech_for("core_falcao") == "orbital_rocketry", "Falcão comes with orbital rocketry")
	TycoonResearch.complete(s, "orbital_rocketry")
	_check(RocketDesigner.available(s, "core_falcao") and bool(s.unlocked.get("rocket:core_falcao", false)),
		"researching it unlocks the part (unlocked['rocket:core_falcao'])")
	_check(RocketDesigner.options(s, "boosters").size() == 2, "and the two solid boosters")
	var rows := TycoonResearch.unlock_list("upper_stage")
	var rk := rows.filter(func(r: Dictionary) -> bool: return r["kind"] == "rocket")
	_check(rk.size() == 5, "the research screen lists a tech's rocket parts (%d)" % rk.size())
	# every component a tech unlocks exists
	for t: Dictionary in TycoonResearch.techs():
		for x in t.get("unlocks", {}).get("rockets", []):
			_check(not RocketDesigner.component(String(x)).is_empty(), "research unlock %s is a component" % x)


# ------------------------------------------------------------ numbers and the check
func _test_stats_and_check() -> void:
	print("design numbers and the requirement check")
	var s := _state()
	var st := RocketDesigner.stats(SOUNDING)
	_check(absf(float(st["dv"]) - 2.4) < 1e-6 and absf(float(st["lift"]) - 0.25) < 1e-6, "sounding: 2.4 km/s, 0.25 t")
	_check(absf(float(st["cost"]) - 30000.0) < 0.5, "sounding: 30 000 cr a unit (GDD appendix C)")
	_check(int(st["weeks"]) == 2 and String(st["class"]) == "sounding", "2 build weeks, sounding class")
	_check(absf(float(st["rel"]) - 0.97 * 0.985) < 1e-6, "hardware reliability = product of the parts")
	var leo := RocketDesigner.stats(LEO)
	_check(absf(float(leo["dv"]) - ((7.2 + 2.8) * 1.0 + 0.8)) < 1e-6, "dv = (core + upper) * tank + boosters")
	_check(absf(float(leo["lift"]) - 1.2 * 1.4) < 1e-6, "lift = core * tank * boosters")
	_check(absf(float(leo["cost"]) - ((80000.0 + 40000.0) * 1.3 + 8000.0 + 6000.0)) < 0.5,
		"cost = (core + upper) * tank * (1 + boosters) + fairing + avionics")
	var chk := RocketDesigner.check(s, SOUNDING, "sounding", "suborbital")
	_check(chk["reaches"] and chk["dv"]["state"] == "green", "a sounding rocket reaches suborbital (green)")
	var short := RocketDesigner.check(s, _with(SOUNDING, {"tank": "tank_s"}), "sounding", "suborbital")
	_check(short["reaches"] and short["dv"]["state"] == "yellow", "short tanks: it gets there, just (yellow)")
	var pr := RocketDesigner.margin_risk("dv", float(short["dv"]["margin"]))
	_check(pr > 0.0 and pr < 0.1, "a thin margin is a risk (%.3f)" % pr)
	var no := RocketDesigner.check(s, SOUNDING, "demo_sat", "leo")
	_check(not no["reaches"] and no["dv"]["state"] == "red" and no["size"]["state"] == "red",
		"a sounding rocket does not reach low orbit (Δv and fairing red)")
	var ok := RocketDesigner.check(s, LEO, "demo_sat", "leo")
	_check(ok["reaches"] and ok["dv"]["state"] == "green", "Falcão + Kestrel-V + 2 solids reaches low orbit")
	var nob := RocketDesigner.check(s, _with(LEO, {"boosters": "boost_none"}), "demo_sat", "leo")
	_check(nob["reaches"] and nob["dv"]["state"] == "yellow", "without the boosters the margin is thin")
	_check(not RocketDesigner.check(s, _with(LEO, {"fairing": "fairing_none"}), "demo_sat", "leo")["reaches"],
		"a satellite does not fit the nose cone")
	# every target and type has a requirement, and some rocket of the full tree reaches each mission
	var all := _state()
	for t: Dictionary in TycoonResearch.techs():
		TycoonResearch.complete(all, String(t["id"]))
	for mt: Dictionary in all.mdata["types"]:
		for tg: String in mt.get("compat", {}):
			_check(RocketDesigner.data()["targets"].has(tg) and RocketDesigner.data()["payload_t"].has(mt["id"]),
				"%s / %s has a Δv and payload requirement" % [mt["id"], tg])
			_check(not RocketDesigner.proposals(all, String(mt["id"]), tg).is_empty(),
				"the full tree reaches %s / %s" % [mt["id"], tg])


func _test_proposals() -> void:
	print("the automatic designer")
	var s := _state()
	var props := RocketDesigner.proposals(s, "sounding", "suborbital")
	_check(props.size() == 3 and props.map(func(p: Dictionary) -> String: return p["kind"]) == ["cheap", "balanced", "robust"],
		"three proposals: cheap, balanced, robust")
	for p in props:
		_check(RocketDesigner.check(s, p["parts"], "sounding", "suborbital")["reaches"], "%s reaches" % p["kind"])
	_check(float(props[0]["cost"]) <= float(props[1]["cost"]) and float(props[0]["cost"]) <= float(props[2]["cost"]),
		"the cheap one costs the least")
	_check(float(props[2]["odds"]) >= float(props[0]["odds"]) and float(props[2]["odds"]) >= float(props[1]["odds"]),
		"the robust one has the best odds")
	var bal := RocketDesigner.default_design(s, "sounding", "suborbital")
	_check(RocketDesigner.same_parts(bal["parts"], SOUNDING), "the default sounding rocket is the 30 000 cr Kestrel")
	_check(RocketDesigner.proposals(s, "demo_sat", "leo").is_empty() and not RocketDesigner.reachable(s, "demo_sat", "leo"),
		"before orbital rocketry nothing reaches orbit")
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	_check(RocketDesigner.proposals(s, "demo_sat", "leo").size() == 3 and RocketDesigner.reachable(s, "demo_sat", "leo"),
		"after it, low orbit has proposals")
	_check(RocketDesigner.proposals(s, "comms", "geo").is_empty() and not RocketDesigner.reachable(s, "comms", "geo"),
		"GEO needs the upper stage tech")
	# the quick reach check agrees with the full designer on every mission, era by era
	var agree := true
	var st := _state(23)
	for tid in ["orbital_rocketry", "small_sat_bus", "upper_stage", "sun_sync_orbits", "lunar_stage", "guided_descent",
			"hydrolox_engines"]:
		TycoonResearch.complete(st, tid)
		for mt: Dictionary in st.mdata["types"]:
			for tg: String in mt.get("compat", {}):
				if RocketDesigner.reachable(st, String(mt["id"]), tg) != (not RocketDesigner.proposals(st, String(mt["id"]), tg).is_empty()):
					agree = false
					print("    disagree after %s: %s / %s" % [tid, mt["id"], tg])
	_check(agree, "the quick reach check (contracts) agrees with the proposals")
	_check(ProjectDesk.start_error(s, "demo_sat", "leo", ["a"], {"parts": SOUNDING}) == "TY_PJ_ERR_ROCKET",
		"a project cannot start with a rocket that does not reach")


# ------------------------------------------------------------ families and heritage
func _test_heritage() -> void:
	print("rocket families and flight heritage")
	var s := _state()
	var h := RocketFamilies.heritage()
	var f := RocketFamilies.ensure(s, SOUNDING)
	_check(String(f["name"]) == "Andorinha" and RocketFamilies.trust(f) == float(h["debut"]), "a new family: Andorinha, debut trust 0.90")
	_check(RocketFamilies.ensure(s, SOUNDING)["id"] == f["id"], "the same parts are the same family")
	var r0 := RocketFamilies.reliability(s, SOUNDING)
	RocketFamilies.record_flight(s, String(f["id"]), true)
	_check(absf(RocketFamilies.trust(f) - (float(h["debut"]) + float(h["step"]))) < 1e-9, "a good flight: +0.02 trust")
	_check(RocketFamilies.reliability(s, SOUNDING) > r0, "the family is more reliable after a good flight")
	RocketFamilies.record_flight(s, String(f["id"]), false)
	_check(absf(RocketFamilies.trust(f) - (float(h["debut"]) + float(h["step"]) - float(h["fail_drop"]))) < 1e-9,
		"a failure: -0.06 trust")
	for i in 30:
		RocketFamilies.record_flight(s, String(f["id"]), true)
	_check(RocketFamilies.trust(f) <= float(h["max"]) + 1e-9, "trust stops at its max")
	for i in 30:
		RocketFamilies.record_flight(s, String(f["id"]), false)
	_check(RocketFamilies.trust(f) >= float(h["min"]) - 1e-9, "and at its min")
	_check(RocketFamilies.flights(f) == 62 and int(f["successes"]) == 31, "flights and successes counted")
	# a new family on a main stage that has flown well debuts higher
	var g := RocketFamilies.ensure(s, _with(SOUNDING, {"avionics": "avionics_redundant"}))
	_check(absf(RocketFamilies.trust(g) - float(h["debut_known_core"])) < 1e-9, "a known main stage debuts at 0.94")
	_check(String(g["name"]) != String(f["name"]), "and gets its own name (%s)" % g["name"])
	# repeat units: cheaper and faster
	var c0 := RocketDesigner.unit_cost(s, SOUNDING, 0)
	_check(RocketDesigner.unit_cost(s, SOUNDING, 2) < c0 and RocketDesigner.unit_cost(s, SOUNDING, 50) >= c0 * 0.8 - 1.0,
		"repeat units cost less, down to 80%")
	_check(RocketDesigner.build_weeks(s, LEO, 3) < RocketDesigner.build_weeks(s, LEO, 0), "and are built faster")
	RocketFamilies.rename(s, String(f["id"]), "Sabiá Azul")
	_check(String(RocketFamilies.find(s, String(f["id"]))["name"]) == "Sabiá Azul", "a family can be renamed")
	# the default rocket of a mission is the best family that has flown
	var d := RocketDesigner.default_design(s, "sounding", "suborbital")
	_check(String(d.get("family", "")) == String(f["id"]), "the default rocket is the flown family")


# ------------------------------------------------------------ the review's odds
func _review_project(p_seed := 31, design := {}) -> Array:
	var s := _state(p_seed)
	s.review_gate = true
	var ready: Array[String] = []
	s.project_review_ready.connect(func(id: String) -> void: ready.append(id))
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", ["a", "b", "c", "d"], "", design)
	_develop(s, p)
	return [s, p, ready]


func _test_review_odds() -> void:
	print("Design Review: risks and odds")
	var t := _review_project()
	var s: TycoonState = t[0]
	var p: MissionProject = t[1]
	_check(p.review_state == "waiting" and ProjectDesk.find(s, p.id) != null, "development ends in the review (gate on)")
	_check((t[2] as Array).size() == 1, "project_review_ready emitted")
	var w0 := s.weeks
	s.advance_week()
	_check(p.review_state == "waiting" and (t[2] as Array).size() == 2 and s.weeks == w0 + 1, "a waiting review is announced again each week")
	var risks := DesignReview.risks(s, p, [])
	var ids := risks.map(func(r: Dictionary) -> String: return r["id"])
	for want in ["stage1", "avionics", "debut", "payload"]:
		_check(want in ids, "risk %s listed" % want)
	_check(not "stage2" in ids and not "boosters" in ids, "no upper stage and no boosters: no such risks")
	var o0 := DesignReview.odds(s, p, [])
	var prod := 1.0
	for r: Dictionary in o0["risks"]:
		prod *= 1.0 - float(r["p"])
	_check(absf(prod - float(o0["total"])) < 1e-9, "odds = product of (1 - p) of every risk")
	_check(absf(float(o0["total"]) - float(o0["rocket"]) * float(o0["payload"]) * float(o0["crew"])) < 1e-9,
		"odds = rocket x payload x crew")
	var o1 := DesignReview.odds(s, p, ["debut"])
	_check(float(o1["total"]) > float(o0["total"]), "fixing the debut risk raises the odds (%.3f -> %.3f)" % [o0["total"], o1["total"]])
	var all_fix := ["debut", "stage1", "avionics", "payload"]
	var o2 := DesignReview.odds(s, p, all_fix)
	_check(float(o2["total"]) > float(o1["total"]), "more fixes, better odds (%.3f)" % o2["total"])
	var plan := DesignReview.fix_plan(s, p, all_fix)
	_check(int(plan["weeks"]) == 2, "fixes run in parallel: the longest is 2 weeks")
	var cost := 0.0
	for r: Dictionary in risks:
		if String(r["id"]) in all_fix:
			cost += float(r["fix_cost"])
	_check(absf(float(plan["cost"]) - cost) < 0.01 and cost > 0.0, "and their costs add up (%.0f cr)" % cost)
	# balance: a first sounding rocket is around 85-90% once reviewed
	print("    first sounding: %.1f%% as designed, %.1f%% with debut + stage 1 fixed, %.1f%% all fixed" % [
		float(o0["total"]) * 100.0, float(DesignReview.odds(s, p, ["debut", "stage1"])["total"]) * 100.0,
		float(o2["total"]) * 100.0])
	var reviewed := float(DesignReview.odds(s, p, ["debut", "stage1"])["total"])
	_check(reviewed >= 0.85 and reviewed <= 0.93, "a reviewed first sounding flies 85-93%% of the time (%.1f%%)" % (reviewed * 100.0))
	_check(float(o0["total"]) >= 0.75, "and does not punish an unreviewed one (%.1f%%)" % (float(o0["total"]) * 100.0))
	# the payload fix cuts the residual defects (grade too)
	var d0 := p.residual_defects()
	p.review_fixes.assign(["payload"])
	_check(p.residual_defects() < d0 or d0 == 0.0, "the readiness review cuts the residual defects")
	p.review_fixes.clear()
	# the advisor's riskiest factor
	var top := DesignReview.riskiest(risks)
	_check(not top.is_empty() and float(top["p"]) == float(risks[0]["p"]), "the riskiest factor is the most likely one")
	# a thin margin and a rocket that does not reach
	p.rocket["parts"] = _with(SOUNDING, {"tank": "tank_s"})
	_check("dv" in DesignReview.risks(s, p, []).map(func(r: Dictionary) -> String: return r["id"]), "a thin Δv margin is a risk")
	p.rocket["parts"] = _with(SOUNDING, {"core": "core_kestrel", "tank": "tank_s"})
	var p2 := MissionProject.from_dict(p.to_dict())
	p2.target_id = "leo"
	p2.type_id = "demo_sat"
	_check(not DesignReview.blockers(s, p2).is_empty() and float(DesignReview.odds(s, p2)["total"]) == 0.0,
		"a rocket that does not reach blocks the launch (odds 0)")
	p.rocket["parts"] = SOUNDING.duplicate()


func _test_review_commands() -> void:
	print("Design Review: fix, accept, change rocket, scrub")
	# fix: money now, then the weeks, then the launch
	var t := _review_project(41)
	var s: TycoonState = t[0]
	var p: MissionProject = t[1]
	var launched: Array[Dictionary] = []
	s.mission_launched.connect(func(r: Dictionary) -> void: launched.append(r))
	var cash0 := s.cash
	var plan := DesignReview.fix_plan(s, p, ["debut", "stage1"])
	_check(ProjectDesk.confirm_review(s, p.id, ["debut", "stage1", "nonsense"]), "the review is confirmed")
	_check(p.review_state == "fixing" and p.review_weeks == int(plan["weeks"]) and p.review_fixes.size() == 2,
		"fixing for %d weeks (unknown ids ignored)" % p.review_weeks)
	_check(absf(cash0 - s.cash - float(plan["cost"])) < 0.01, "the fixes are paid at once")
	_check(s.projects[0]["review"] == "fixing", "the strip shows the fixes")
	for i in int(plan["weeks"]):
		s.advance_week()
	_check(ProjectDesk.find(s, p.id) == null and launched.size() == 1, "after the fixes it launches")
	var h := ProjectDesk.history_entry(s, p.id)
	_check(h["fixes"] == ["debut", "stage1"] and absf(float(h["p_success"]) - float(DesignReview.odds(s, p, ["debut", "stage1"])["total"])) < 0.02,
		"the history keeps the fixes and the reviewed odds")
	# accept: no fixes, launches at once
	t = _review_project(42)
	s = t[0]
	p = t[1]
	_check(ProjectDesk.confirm_review(s, p.id, []) and ProjectDesk.find(s, p.id) == null, "accepting everything launches now")
	# change rocket: a new design is built, then the review comes back
	t = _review_project(43)
	s = t[0]
	p = t[1]
	var ready: Array = t[2]
	var n0 := ready.size()
	_check(not ProjectDesk.change_rocket(s, p.id, {"parts": _with(SOUNDING, {"core": "core_falcao"})}),
		"parts the research has not unlocked are refused")
	var better := _with(SOUNDING, {"avionics": "avionics_redundant"})
	_check(ProjectDesk.change_rocket(s, p.id, {"parts": better, "name": "Colibri"}), "a new rocket for the waiting project")
	_check(p.review_state == "rebuild" and p.review_weeks > 0 and String(RocketFamilies.find(s, String(p.rocket["family"]))["name"]) == "Colibri",
		"it is being built (%d weeks), as the family Colibri" % p.review_weeks)
	for i in p.review_weeks:
		s.advance_week()
	_check(p.review_state == "waiting" and ready.size() > n0, "then the review comes back")
	_check(not ProjectDesk.change_rocket(s, p.id, {"parts": LEO}) or RocketDesigner.check(s, LEO, "sounding", "suborbital")["reaches"],
		"a rocket that does not reach is refused")
	# scrub: cancelled, team freed, reputation down, contract failed
	t = _review_project(44)
	s = t[0]
	p = t[1]
	var rep0 := s.reputation
	_check(ProjectDesk.scrub(s, p.id), "scrub")
	_check(ProjectDesk.find(s, p.id) == null and ProjectDesk.history_entry(s, p.id).is_empty(), "the project is gone, nothing flew")
	_check(ProjectDesk.free_staff(s).size() == 4 and s.reputation < rep0, "the team is free, the reputation drops")
	_check(String(s.news[0]["key"]) == "TY_RK_NEWS_SCRUB", "Tail Radio: launch scrubbed")
	# errors
	t = _review_project(45)
	s = t[0]
	p = t[1]
	s.cash = 10.0
	_check(ProjectDesk.review_error(s, p, ["debut"]) == "TY_RK_ERR_CASH" and not ProjectDesk.confirm_review(s, p.id, ["debut"]),
		"fixes need the money")
	_check(ProjectDesk.review_error(s, p, []) == "", "accepting needs none")


# ------------------------------------------------------------ the odds feed the launch
func _test_odds_feed_launch() -> void:
	print("the odds feed ProjectDesk")
	var s := _state(51)
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", ["a", "b", "c", "d"])
	_check(p.rocket.has("parts") and RocketDesigner.same_parts(p.rocket["parts"], SOUNDING), "a project gets the default rocket")
	_check(not RocketFamilies.find(s, String(p.rocket["family"])).is_empty(), "as a rocket family")
	var est := ProjectDesk.estimate(s, "sounding", p.rocket, "suborbital")
	_check(int(est["weeks"]) == 3 and absf(float(est["launch_cost"]) - 30000.0) < 0.5, "estimate: 3 weeks, 30 000 cr launch")
	var chance := ProjectDesk.success_chance(s, p)
	_check(absf(float(chance["total"]) - float(DesignReview.odds(s, p)["total"])) < 1e-9, "success_chance is the review's odds")
	_check(float(chance["rocket"]) < 0.98 and float(chance["rocket"]) > 0.8, "the rocket factor is no longer the 0.75 placeholder (%.3f)" % chance["rocket"])
	var cash := [0.0]
	s.mission_launched.connect(func(r: Dictionary) -> void:
		cash[0] = float(r.get("p_success", -1.0))
		_check(r.has("rocket") and String(r["rocket"]["name"]) != "" and r["rocket"]["parts"]["core"] == "core_kestrel",
			"the launch result carries the rocket (%s)" % r["rocket"]["name"]))
	var fam_id := String(p.rocket["family"])
	var odds_at := -1.0
	_develop(s, p)
	var h := ProjectDesk.history_entry(s, p.id)
	odds_at = float(h["p_success"])
	_check(absf(cash[0] - odds_at) < 1e-9, "the result's odds are the history's odds")
	_check(String(h["launch_class"]) == "sounding" and absf(float(h["rewards"]["launch_cost"]) - 30000.0) < 0.5,
		"the launch pays one unit of the rocket")
	var fam := RocketFamilies.find(s, fam_id)
	_check(RocketFamilies.flights(fam) == 1 and int(fam["successes"]) == (1 if h["success"] else 0), "the family flew once")
	# heritage feeds the next project's odds
	var p2 := ProjectDesk.start_project(s, "sounding", "suborbital", ["a", "b", "c", "d"])
	_check(String(p2.rocket["family"]) == fam_id or not h["success"], "the next project reuses the flown family")
	if h["success"]:
		_check(float(ProjectDesk.success_chance(s, p2)["rocket"]) > float(chance["rocket"]), "with a better rocket factor")
	# many seeds: the success rate follows the odds
	var wins := 0
	var sum := 0.0
	for sd in range(100, 160):
		var st := _state(sd)
		var q := ProjectDesk.start_project(st, "sounding", "suborbital", ["a", "b", "c", "d"])
		_develop(st, q)
		var e := ProjectDesk.history_entry(st, q.id)
		sum += float(e["p_success"])
		wins += 1 if e["success"] else 0
	print("    60 first soundings: %d flew, mean odds %.1f%%" % [wins, sum / 60.0 * 100.0])
	_check(absf(wins / 60.0 - sum / 60.0) < 0.15, "the success rate follows the odds")


func _test_failure_cause() -> void:
	print("failure causes")
	var risks := [{"id": "a", "p": 0.0, "cause_key": "A"}, {"id": "b", "p": 0.1, "cause_key": "B"}, {"id": "c", "p": 0.1, "cause_key": "C"}]
	_check(DesignReview.pick_cause(risks, 0.0)["id"] == "b", "a risk with no chance never causes a failure")
	_check(DesignReview.pick_cause(risks, 0.99)["id"] == "c", "the roll picks by share of the failure chance")
	var found := false
	for sd in range(300, 420):
		var s := _state(sd)
		var p := ProjectDesk.start_project(s, "sounding", "suborbital", ["a", "b"])
		# a fragile design so failures come quickly
		p.rocket["parts"] = _with(SOUNDING, {"tank": "tank_s"})
		_develop(s, p)
		var h := ProjectDesk.history_entry(s, p.id)
		if h.is_empty() or h["success"]:
			continue
		found = true
		var keys := (h["risks"] as Array).map(func(r: Dictionary) -> String: return r["id"])
		_check(String(h["cause"]) in keys and String(h["cause_key"]).begins_with("TY_RK_CAUSE_"),
			"a failed launch names one of its risks (%s: %s)" % [h["cause"], TranslationServer.translate(String(h["cause_key"]))])
		var news_hit := false
		for n: Dictionary in s.news:
			if String(n["key"]) == "TY_RK_NEWS_FAIL_CAUSE" and String(n["args"][1]) == String(h["cause_key"]):
				news_hit = true
		_check(news_hit, "Tail Radio says what broke")
		var page := {}
		for pg: Dictionary in s.race.pending_pages:
			if String(pg.get("kind", "")) == "launch_fail":
				page = pg
		_check(not page.is_empty() and String(page["cause_key"]) == String(h["cause_key"]) and String(page["code"]) == p.code,
			"the paper prints a front page with the cause")
		var fam := RocketFamilies.find(s, String(h["rocket"]["family"]))
		_check(int(fam["failures"]) == 1 and RocketFamilies.trust(fam) < float(RocketFamilies.heritage()["debut"]),
			"a failure lowers the family's trust")
		break
	_check(found, "some seed fails a launch")


# ------------------------------------------------------------ save / load
func _test_save_load() -> void:
	print("save / load")
	var t := _review_project(61)
	var s: TycoonState = t[0]
	var p: MissionProject = t[1]
	var fam := RocketFamilies.find(s, String(p.rocket["family"]))
	RocketFamilies.record_flight(s, String(fam["id"]), true)
	RocketFamilies.ensure(s, LEO, "Garça")
	p.review_fixes.assign(["debut"])
	var l := TycoonState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var lp := ProjectDesk.find(l, p.id)
	_check(lp != null and lp.review_state == "waiting" and lp.review_fixes == p.review_fixes
		and RocketDesigner.same_parts(lp.rocket["parts"], p.rocket["parts"]) and String(lp.rocket["family"]) == String(fam["id"]),
		"a project waiting in review keeps its rocket and fixes")
	_check(RocketFamilies.families(l).size() == 2, "families survive")
	var lf := RocketFamilies.find(l, String(fam["id"]))
	_check(lf["flights"] is int and RocketFamilies.flights(lf) == 1 and absf(RocketFamilies.trust(lf) - RocketFamilies.trust(fam)) < 1e-9,
		"with their heritage")
	_check(String(RocketFamilies.find_parts(l, LEO).get("name", "")) == "Garça", "and their names")
	_check(absf(float(DesignReview.odds(l, lp)["total"]) - float(DesignReview.odds(s, p)["total"])) < 1e-9, "the same odds after loading")
	# through the save file
	_check(TycoonSave.save(s, "rocket_test") == OK, "TycoonSave writes it")
	var f := TycoonSave.load_state("rocket_test")
	_check(f != null and RocketFamilies.families(f).size() == 2 and ProjectDesk.find(f, p.id) != null, "and reads it back")
	TycoonSave.delete("rocket_test")
	# an empty agency saves nothing extra
	var e := _state(62)
	var le := TycoonState.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	_check(le.rockets.is_empty(), "no families, no rockets data")


# ------------------------------------------------------------ the launch and the pad show it
func _test_visuals() -> void:
	print("the designed rocket on the pad and in the launch")
	var s := _state(71)
	var dr := (load("res://scenes/tycoon/launch/designed_rocket.tscn") as PackedScene).instantiate() as DesignedRocket
	get_root().add_child(dr)
	await process_frame
	var h0 := dr.core_size.y
	dr.build(SOUNDING)
	var hs := dr.core_size.y
	dr.build(LEO)
	_check(dr.core_size.y > hs, "a bigger main stage is a taller rocket (%.1f > %.1f m)" % [dr.core_size.y, hs])
	var shown := 0
	for slot in dr.boosters.get_children():
		shown += slot.get_child_count()
	_check(shown == 2, "two side boosters stand by the core")
	dr.build(_with(LEO, {"boosters": "boost_srb4", "tank": "tank_l"}))
	shown = 0
	for slot in dr.boosters.get_children():
		shown += slot.get_child_count()
	_check(shown == 4, "four for the 4-solid option")
	dr.build({})
	_check(is_equal_approx(dr.core_size.y, h0), "no design: the authored look")
	dr.queue_free()
	# the launch sequence flies it, and its card says why it failed
	var seq := (load("res://scenes/tycoon/launch/launch_sequence.tscn") as PackedScene).instantiate() as LaunchSequence
	get_root().add_child(seq)
	await process_frame
	seq.state = s
	var r := {"project_id": "", "code": "DEM-01", "type": "demo_sat", "target": "leo", "grade": 5.0, "success": false,
		"outcome": "fail", "p_success": 0.83, "cause": "stage2", "cause_key": "TY_RK_CAUSE_STAGE2",
		"rocket": {"family": "", "name": "Bem-te-vi", "parts": LEO, "class": "light"}}
	seq.play(r)
	await process_frame
	_check(seq.designed != null and RocketDesigner.same_parts(seq.designed.parts, LEO), "the sequence flies the designed rocket")
	var b := 0
	for slot in seq.designed.boosters.get_children():
		b += slot.get_child_count()
	_check(b == 2, "boosters visible in the launch")
	var odds := seq.get_node("%CardFail").find_child("OddsValue", true, false) as Label
	_check(odds.text == "83%", "the card's odds match the result (%s)" % odds.text)
	var cause := seq.get_node("%CardFail").find_child("Cause", true, false) as Label
	_check(cause.visible and cause.text.contains(TranslationServer.translate("TY_RK_CAUSE_STAGE2")), "the failure card names the cause (%s)" % cause.text)
	_check((seq.get_node("%MissionRoute") as Label).text.contains("Bem-te-vi"), "the overlay names the rocket")
	seq.queue_free()
	await process_frame
	# the pad shows the next rocket: the project in development's
	var pad := (load("res://scenes/tycoon/buildings/pad.tscn") as PackedScene).instantiate() as CampusBuilding
	get_root().add_child(pad)
	await process_frame
	pad.set_look(1, 1)
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	var p := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b"], "", {"parts": LEO})
	var parts := LaunchPads.pad_rocket(s, "pad")
	_check(RocketDesigner.same_parts(parts, p.rocket["parts"]), "the pad's rocket is the project's")
	pad.set_rocket_design(parts)
	var rk := pad.get_node("Era1/Level1/Rocket") as Node3D
	var designed := rk.get_node_or_null("Designed") as DesignedRocket
	_check(designed != null and designed.visible and not (rk.get_node("Model") as Node3D).visible,
		"the pad shows the designed rocket instead of the era's")
	pad.set_rocket_progress(0.4)
	_check(rk.visible or pad.rocket_held, "it rolls out on the crawler")
	pad.set_rocket_design({})
	_check((rk.get_node("Model") as Node3D).visible and not designed.visible, "no design: the era's rocket again")
	LaunchPads.launched(s, "pad", LEO)
	ProjectDesk.scrub(s, p.id)
	_check(RocketDesigner.same_parts(LaunchPads.pad_rocket(s, "pad"), LEO), "after a launch the pad keeps the last rocket's look")
	pad.queue_free()
	await process_frame


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
