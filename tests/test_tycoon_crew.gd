extends SceneTree
## Headless checks for the Cometworks crew (src/tycoon/crew/tycoon_crew.gd, GDD section 9):
## hiring market, hidden traits, hiring fee and limits, adaptation, firing, XP and levels,
## specialisations, morale (overwork, naps, late salaries, launches), salaries, determinism
## and save / load.
## Run: godot --headless --path . --script res://tests/test_tycoon_crew.gd

var _failures := 0


func _staff() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": "a", "name": "Ana", "profession": "systems_engineer", "level": 1},
		{"id": "b", "name": "Bia", "profession": "scientist", "level": 1},
		{"id": "c", "name": "Caio", "profession": "pilot", "level": 2, "xp": 100.0},
		{"id": "d", "name": "Duda", "profession": "flight_controller", "level": 1}]
	return out


func _initialize() -> void:
	var s := TycoonState.new_campaign(42, _staff())
	TycoonCrew.ensure(s)
	# ---- market
	var cands := TycoonCrew.candidates(s)
	_check(cands.size() == 3, "3 candidates on the market (got %d)" % cands.size())
	var profs := {}
	var hidden_ok := true
	for c: Dictionary in cands:
		profs[c["profession"]] = true
		hidden_ok = hidden_ok and (c["hidden"] as Array).size() == 2
	_check(profs.size() == 3, "candidates have 3 different professions")
	_check(hidden_ok, "each candidate starts with 2 hidden traits")
	s.advance_week()
	var revealed := true
	for c: Dictionary in TycoonCrew.candidates(s):
		revealed = revealed and (c["hidden"] as Array).size() == 1
	_check(revealed, "one hidden trait is revealed per week")
	var first_ids := _ids(TycoonCrew.candidates(s))
	_advance_to_month_change(s)
	_check(_ids(TycoonCrew.candidates(s)) != first_ids and TycoonCrew.candidates(s).size() == 3,
		"a new month brings 3 new candidates")

	# ---- determinism by seed
	var a := TycoonState.new_campaign(7, _staff())
	var b := TycoonState.new_campaign(7, _staff())
	var c7 := TycoonState.new_campaign(8, _staff())
	for i in 30:
		a.advance_week()
		b.advance_week()
		c7.advance_week()
	_check(JSON.stringify(TycoonCrew.candidates(a)) == JSON.stringify(TycoonCrew.candidates(b)),
		"same seed, same candidates after 30 weeks")
	_check(JSON.stringify(TycoonCrew.candidates(a)) != JSON.stringify(TycoonCrew.candidates(c7)),
		"another seed, other candidates")

	# ---- salaries
	var pilot := TycoonCrew.find(s, "c")
	_check(absf(TycoonCrew.salary(s, pilot) - 6500.0) < 0.01, "pilot level 2 salary 4000 x 1.25 x 1.3 = 6500")
	var tot := 0.0
	for m in s.staff:
		tot += TycoonCrew.salary(s, m)
	_check(absf(tot - s.monthly_salaries()) < 0.01, "salaries per member add up to the monthly bill")

	# ---- hiring
	s = TycoonState.new_campaign(42, _staff())
	var cand: Dictionary = TycoonCrew.candidates(s)[0]
	var fee := TycoonCrew.hire_fee(s, cand)
	_check(absf(fee - 2.0 * TycoonCrew.salary(s, cand)) < 0.01, "hiring fee is 2 salaries (%.0f)" % fee)
	var cash0 := s.cash
	var cand_name := String(cand["name"])
	_check(TycoonCrew.hire(s, String(cand["id"])) == "", "hire a candidate")
	_check(absf(s.cash - (cash0 - fee)) < 0.01, "fee paid")
	_check(s.staff.size() == 5 and TycoonCrew.candidates(s).size() == 2, "joins the staff, leaves the market")
	var hired: Dictionary = s.staff[4]
	_check(hired["name"] == cand_name and int(hired["adapt_weeks"]) == 2, "2 weeks of adaptation")
	_check(not TycoonCrew.is_working(hired) and TycoonCrew.status(hired) == "adapting", "does not work while settling in")
	_check((hired["hidden"] as Array).size() == 2, "hidden traits stay hidden until settled")
	s.advance_week()
	s.advance_week()
	_check(TycoonCrew.is_working(hired) and (hired["hidden"] as Array).is_empty(), "settled after 2 weeks, traits known")
	# staff limit from the HQ level
	_check(TycoonCrew.staff_limit(s) == 8, "HQ level 1 holds 8 staff")
	s.cash = 1.0e7
	var hires := 0
	for k in 10:
		var cs := TycoonCrew.candidates(s)
		if cs.is_empty():
			_advance_to_month_change(s)
			cs = TycoonCrew.candidates(s)
		if TycoonCrew.hire(s, String(cs[0]["id"])) == "":
			hires += 1
		if s.staff.size() >= 8:
			break
	_check(s.staff.size() == 8, "hired up to the limit (%d staff)" % s.staff.size())
	if TycoonCrew.candidates(s).is_empty():
		_advance_to_month_change(s)
	var cid := String(TycoonCrew.candidates(s)[0]["id"])
	_check(TycoonCrew.hire(s, cid) == "TY_CREW_ERR_LIMIT", "cannot hire past the HQ limit")
	s.buildings["hq"]["level"] = 2
	_check(TycoonCrew.staff_limit(s) == 12 and TycoonCrew.hire(s, cid) == "", "HQ level 2: 12 staff, hire works")
	s.cash = 10.0
	cid = String(TycoonCrew.candidates(s)[0]["id"]) if not TycoonCrew.candidates(s).is_empty() else ""
	_check(cid == "" or TycoonCrew.hire(s, cid) == "TY_CREW_ERR_CASH", "cannot hire without the fee")
	# firing
	s.cash = 1.0e6
	var n0 := s.staff.size()
	var mor := float(TycoonCrew.find(s, "b")["morale"])
	TycoonCrew.find(s, "a")["assigned"] = "p1"
	_check(TycoonCrew.fire(s, "a") == "TY_CREW_ERR_ASSIGNED", "cannot fire someone on a project")
	TycoonCrew.find(s, "a")["assigned"] = ""
	_check(TycoonCrew.fire(s, "a") == "" and s.staff.size() == n0 - 1 and TycoonCrew.find(s, "a").is_empty(), "fire")
	_check(float(TycoonCrew.find(s, "b")["morale"]) < mor, "the others feel a firing")

	# ---- XP, levels and specialisations
	s = TycoonState.new_campaign(42, _staff())
	_check(TycoonCrew.add_xp(s, "a", 250.0) == 2 and int(TycoonCrew.find(s, "a")["level"]) == 3,
		"250 XP: level 1 -> 3 (100 XP per level)")
	TycoonCrew.add_xp(s, "a", 5000.0)
	_check(int(TycoonCrew.find(s, "a")["level"]) == 6, "level caps at 6")
	var m3 := TycoonCrew.find(s, "b")
	TycoonCrew.add_xp(s, "b", 200.0)
	var slots := TycoonCrew.spec_slots(s, m3)
	_check(slots[0]["unlocked"] and not slots[1]["unlocked"], "level 3 unlocks the first specialisation")
	_check(slots[0]["reason"] == "TY_CREW_SPEC_NEED_TRAINING", "it needs the training centre")
	_check(TycoonCrew.choose_spec(s, "b", "data_miner") == "TY_CREW_SPEC_NEED_TRAINING", "no centre, no spec")
	s.buildings["training"] = {"kind": "training", "level": 1, "target": 1, "weeks_left": 0}
	_check(TycoonCrew.choose_spec(s, "b", "mass_trimmer") != "", "a spec of another profession is refused")
	_check(TycoonCrew.choose_spec(s, "b", "data_miner") == "", "scientist learns Data miner")
	_check(TycoonCrew.status(m3) == "training" and not TycoonCrew.is_working(m3), "away training for a while")
	_check(absf(TycoonCrew.spec_effect(m3, "science") - 0.15) < 0.001, "spec effect readable by other systems")
	var xp0 := float(TycoonCrew.find(s, "d")["xp"])
	TycoonCrew.add_xp(s, "d", 100.0)
	_check(absf(float(TycoonCrew.find(s, "d")["xp"]) - xp0 - 115.0) < 0.01, "training centre level 1: +15% XP")
	_check(TycoonCrew.points_mult(TycoonCrew.find(s, "d"), "ops") == 1.0, "no spec, no bar bonus")

	# ---- morale
	s = TycoonState.new_campaign(42, _staff())
	var w := TycoonCrew.find(s, "a")
	var idle := TycoonCrew.find(s, "b")
	w["assigned"] = "p1"
	w["morale"] = 60.0
	idle["morale"] = 60.0
	for i in 8:
		s.advance_week()
	_check(absf(float(w["morale"]) - 60.0) < 0.01, "8 weeks on a project: still fine (%.0f)" % float(w["morale"]))
	_check(float(idle["morale"]) > 60.0, "resting raises morale (%.0f)" % float(idle["morale"]))
	for i in 4:
		s.advance_week()
	_check(float(w["morale"]) < 60.0, "overwork lowers morale (%.0f)" % float(w["morale"]))
	w["morale"] = 31.0
	var napped := false
	for i in 6:
		s.advance_week()
		if bool(w["napping"]):
			napped = true
			break
	_check(napped and not TycoonCrew.is_working(w) and TycoonCrew.status(w) == "nap", "below 30 morale: a nap")
	var before := float(w["morale"])
	s.advance_week()
	_check(float(w["morale"]) > before, "a nap restores some morale")
	# late salaries
	s.cash = -1000.0
	idle["morale"] = 90.0  # above the rest cap: only the late pay moves it
	_advance_to_month_change(s)
	_check(absf(float(idle["morale"]) - 80.0) < 0.01, "late salaries: -10 morale (%.0f)" % float(idle["morale"]))
	# launches
	s = TycoonState.new_campaign(42, _staff())
	TycoonCrew.ensure(s)
	TycoonCrew.find(s, "a")["assigned"] = "p9"
	TycoonCrew.find(s, "a")["morale"] = 50.0
	TycoonCrew.find(s, "b")["morale"] = 50.0
	s.mission_launched.emit({"project_id": "p9", "success": true, "outcome": "full"})
	_check(float(TycoonCrew.find(s, "a")["morale"]) == 58.0, "success: +8 for the project crew")
	_check(absf(float(TycoonCrew.find(s, "b")["morale"]) - 52.8) < 0.01, "success: a share for the others")
	s.mission_launched.emit({"project_id": "p9", "success": false, "outcome": "fail"})
	_check(float(TycoonCrew.find(s, "a")["morale"]) < 58.0, "failure lowers morale")

	# ---- save / load
	s = TycoonState.new_campaign(5, _staff())
	for i in 3:
		s.advance_week()
	s.cash = 1.0e6
	TycoonCrew.hire(s, String(TycoonCrew.candidates(s)[0]["id"]))
	var d := s.to_dict()
	var s2 := TycoonState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_check(s2.staff.size() == 5 and int(s2.staff[4]["adapt_weeks"]) == 2, "hired Cometling survives save / load")
	for i in 12:
		s.advance_week()
		s2.advance_week()
	_check(JSON.stringify(TycoonCrew.candidates(s)) == JSON.stringify(TycoonCrew.candidates(s2)),
		"after load the market goes on exactly the same")
	_research_specs()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


## The five specialisations research opens (flight surgeon, moonwalker, comet navigator, ice
## miner, mission director): gated by their tech, learnable in either slot, and each one moves
## the system it promises; plus the older effects that used to be only text.
func _research_specs() -> void:
	print("research specialisations")
	var s := TycoonState.new_campaign(42, _staff())
	s.cash = 1.0e7
	s.buildings["training"] = {"kind": "training", "level": 2, "target": 2, "weeks_left": 0}
	var sci := TycoonCrew.find(s, "b")
	TycoonCrew.add_xp(s, "b", 200.0)   # level 3: the first slot
	var ids := _ids(TycoonCrew.spec_options(sci, 1, s))
	_check(not ("flight_surgeon" in ids) and "data_miner" in ids, "before Life support the flight surgeon is not on offer")
	_check(TycoonCrew.choose_spec(s, "b", "flight_surgeon") != "", "and cannot be learned")
	var later := _ids(TycoonCrew.spec_locked(sci, 1, s))
	_check("flight_surgeon" in later and "ice_miner" in later, "the crew sheet can name the ones research will open")
	for tech in ["life_support", "crewed_lander", "comet_rendezvous", "ice_extraction", "mission_automation"]:
		TycoonResearch.complete(s, tech)
	_check("flight_surgeon" in _ids(TycoonCrew.spec_options(sci, 1, s)), "Life support opens the flight surgeon")
	_check(TycoonCrew.choose_spec(s, "b", "flight_surgeon") == "", "a scientist learns it in the first slot")
	sci["train_weeks"] = 0
	TycoonCrew.add_xp(s, "b", 200.0)   # level 5: the second slot
	var t2 := _ids(TycoonCrew.spec_options(sci, 2, s))
	_check("ice_miner" in t2 and "mission_director" in t2 and not ("flight_surgeon" in t2),
		"the second slot offers the research specs too, not the one it already has")
	for id in ["flight_surgeon", "moonwalker", "comet_navigator", "ice_miner", "mission_director"]:
		_check(not (TycoonCrew.spec(id).get("effects", {}) as Dictionary).is_empty()
			and tr("TY_CREW_SPEC_" + id.to_upper() + "_DESC") != "TY_CREW_SPEC_" + id.to_upper() + "_DESC",
			"%s has an effect and a description for the crew sheet" % id)
	# crew risk: a flight surgeon on a crewed flight
	var p := MissionProject.new()
	p.type_id = "crewed_flight"
	p.target_id = "leo"
	p.staff_ids.assign(["c", "d"])
	var base := 1.0 - DesignReview.crew_factor(s, p)
	TycoonCrew.find(s, "d")["specs"] = ["flight_surgeon"]
	var with_doc := 1.0 - DesignReview.crew_factor(s, p)
	_check(base > 0.0 and absf(with_doc - base * 0.6) < 1e-6, "a flight surgeon cuts the crew risk by 40%% (%.3f -> %.3f)" % [base, with_doc])
	# moonwalker: points on crewed landings only
	var pilot := TycoonCrew.find(s, "c")
	pilot["specs"] = ["moonwalker"]
	var vals := [40, 30, 30]
	var land := MissionProject.member_points(s, pilot, 0, vals, "crewed_landing", "lunar_surface")
	var fly := MissionProject.member_points(s, pilot, 0, vals, "crewed_flight", "leo")
	_check(absf(land[2] / fly[2] - 1.25) < 1e-6, "a moonwalker makes 25% more points on a crewed landing")
	# comet navigator and ice miner: their targets and types
	pilot["specs"] = ["comet_navigator"]
	var comet := MissionProject.member_points(s, pilot, 0, vals, "comet_mission", "comet")
	var moon := MissionProject.member_points(s, pilot, 0, vals, "lander", "lunar_surface")
	_check(absf(comet[2] / moon[2] - 1.25) < 1e-6, "a comet navigator makes 25% more points on the comet")
	var eng := TycoonCrew.find(s, "a")
	eng["specs"] = ["ice_miner"]
	var isru := MissionProject.member_points(s, eng, 0, vals, "isru", "lunar_surface")
	var pole := MissionProject.member_points(s, eng, 0, vals, "lander", "lunar_pole")
	var plain := MissionProject.member_points(s, eng, 0, vals, "lander", "lunar_surface")
	_check(absf(isru[0] / plain[0] - 1.25) < 1e-6 and absf(pole[0] / plain[0] - 1.15) < 1e-6,
		"an ice miner: +25% on ISRU, +15% at the lunar pole")
	# mission director: everyone on the project
	p.type_id = "demo_sat"
	p.staff_ids.assign(["a", "c", "d"])
	eng["specs"] = []
	var m0 := p.team_mult(s)
	eng["specs"] = ["mission_director"]
	_check(absf(m0 - 1.0) < 1e-6 and absf(p.team_mult(s) - 1.1) < 1e-6, "a mission director: +10% points for the whole team")
	# the older effects that were only text before
	pilot["specs"] = ["steady_hands"]
	TycoonCrew.find(s, "d")["specs"] = []
	p.type_id = "crewed_flight"
	p.staff_ids.assign(["c", "d"])
	_check(absf((1.0 - DesignReview.crew_factor(s, p)) - base * 0.8) < 1e-6, "steady hands: 20% less crew risk")
	var mo := {"target": "leo", "type": "demo_sat", "antenna_gain": 1.0}
	var d0 := MissionOps.downlink_rate_at(mo, 1)
	mo["spec_downlink"] = 0.2
	_check(absf(MissionOps.downlink_rate_at(mo, 1) / d0 - 1.2) < 1e-6, "an antenna master's downlink bonus reaches mission ops")
	pilot["specs"] = []
	var sc := TycoonCrew.find(s, "b")
	sc["specs"] = ["lunar_specialist"]
	var sl := MissionProject.member_points(s, sc, 0, [0, 100, 0], "orbiter", "lunar_orbit")
	var sg := MissionProject.member_points(s, sc, 0, [0, 100, 0], "telescope", "geo")
	_check(absf(sl[1] / sg[1] - 1.2) < 1e-6, "a lunar specialist: +20% Science on Moon targets")


func _ids(cs: Array) -> Array:
	var out: Array = []
	for c: Dictionary in cs:
		out.append(c["id"])
	return out


func _advance_to_month_change(s: TycoonState) -> void:
	var m0 := s._month_of(s.weeks)
	while s._month_of(s.weeks) == m0:
		s.advance_week()


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
