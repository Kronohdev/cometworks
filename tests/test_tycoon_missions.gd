extends SceneTree
## Headless checks for the discovery-driven mission loop (src/tycoon/project/: BriefingDesk,
## PayloadRules, MissionFit, Discovery): briefings load and are well formed; matching the hidden
## ideals (target, type, instruments, power, team, levers) gives better grades; the feedback
## lines come from the right gaps; the journal records and reveals; the payload budgets block
## a bad plan; everything survives a save; and a seeded long sim where a player who reads the
## journal ends up with better grades than one who does not.
## Run: godot --headless --path . --script res://tests/test_tycoon_missions.gd

var _failures := 0


func _initialize() -> void:
	_test_briefings_load()
	_test_board()
	_test_payload_budgets()
	_test_ideals_matter()
	_test_feedback()
	_test_journal()
	_test_save_roundtrip()
	_test_long_sim()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


static func _team() -> Array[Dictionary]:
	return [
		{"id": "a", "name": "Ada", "profession": "systems_engineer", "skill": 0.7, "morale": 90.0, "level": 2, "curiosity": 0.3},
		{"id": "b", "name": "Bel", "profession": "scientist", "skill": 0.6, "morale": 90.0, "level": 2, "curiosity": 0.8},
		{"id": "c", "name": "Cid", "profession": "test_technician", "skill": 0.7, "morale": 90.0, "level": 1, "curiosity": 0.4},
		{"id": "d", "name": "Duo", "profession": "flight_controller", "skill": 0.6, "morale": 90.0, "level": 3, "curiosity": 0.4},
		{"id": "e", "name": "Eva", "profession": "pilot", "skill": 0.6, "morale": 90.0, "level": 1, "curiosity": 0.5},
		{"id": "f", "name": "Fio", "profession": "researcher", "skill": 0.6, "morale": 90.0, "level": 1, "curiosity": 0.5},
		{"id": "g", "name": "Gil", "profession": "propulsion_engineer", "skill": 0.6, "morale": 90.0, "level": 1, "curiosity": 0.4},
		{"id": "h", "name": "Hoh", "profession": "scientist", "skill": 0.5, "morale": 90.0, "level": 1, "curiosity": 0.3}]


## A campaign at the start of `era` with every tech done and plenty of cash.
static func _state(p_seed := 21, era := 3) -> TycoonState:
	var s := TycoonState.new_campaign(p_seed, _team())
	s.cash = 5.0e8
	s.weeks = (era - 1) * 5 * 52
	for t: Dictionary in TycoonResearch.techs():
		TycoonResearch.complete(s, String(t["id"]))
	return s


## Runs a project to its launch with these sliders (one split for all phases or one per phase).
static func _run(s: TycoonState, type_id: String, target_id: String, staff: Array, payload: Array, sliders: Array,
		briefing_id := "") -> Dictionary:
	var p := ProjectDesk.start_project(s, type_id, target_id, staff, "", {}, {"payload": payload, "briefing_id": briefing_id})
	if p == null:
		return {"error": ProjectDesk.start_error(s, type_id, target_id, staff, {}, {"payload": payload, "briefing_id": briefing_id})}
	var id := p.id
	var per_phase: bool = sliders.size() == 3 and sliders[0] is Array
	ProjectDesk.set_sliders(s, id, sliders[0] if per_phase else sliders)
	var guard := 0
	while ProjectDesk.find(s, id) != null and guard < 60:
		s.advance_week()
		var q := ProjectDesk.find(s, id)
		if q and q.awaiting_sliders:
			ProjectDesk.set_sliders(s, id, sliders[q.phase] if per_phase else sliders)
		guard += 1
	return ProjectDesk.history_entry(s, id)


static func _has(fb: Array, key: String, arg := "") -> bool:
	for f: Dictionary in fb:
		if String(f["key"]) == key and (arg == "" or arg in f.get("args", [])):
			return true
	return false


# ------------------------------------------------------------ briefings
func _test_briefings_load() -> void:
	print("briefings load")
	var all := BriefingDesk.briefings()
	_check(all.size() >= 20, "at least 20 briefings (%d)" % all.size())
	var eras := {}
	var kinds := {}
	var ids := {}
	var s := _state(1, 5)
	var csv := FileAccess.get_file_as_string("res://i18n/tycoon_project_strings.csv")
	var bad := 0
	for b: Dictionary in all:
		var id := String(b["id"])
		if ids.has(id):
			bad += 1
			print("    duplicate id %s" % id)
		ids[id] = true
		eras[int(b["era"])] = true
		kinds[String(b["kind"])] = true
		var ty := BriefingDesk.best_type(b)
		var tg := BriefingDesk.best_target(b)
		if ProjectRules.compat(s.mission_type(ty), tg) <= 0.0:
			bad += 1
			print("    %s: best type %s cannot fly to %s" % [id, ty, tg])
		if int(s.mission_type(ty).get("era", 1)) > int(b["era"]):
			bad += 1
			print("    %s: era %d before its type's era" % [id, int(b["era"])])
		for m in BriefingDesk.needs(b):
			if PayloadRules.module(String(m)).is_empty():
				bad += 1
				print("    %s: unknown module %s" % [id, m])
		for k in [BriefingDesk.title_key(id), BriefingDesk.story_key(id), BriefingDesk.goal_key(id)]:
			if not csv.contains("\n" + k + ","):
				bad += 1
				print("    missing text %s" % k)
		# its needed instruments are great there (the story and the journal agree)
		for m in BriefingDesk.needs(b):
			if PayloadRules.module(String(m)).get("kind", "") == "instrument" and MissionFit.instrument_fit(ty, tg, String(m)) < 2:
				bad += 1
				print("    %s: needed %s is not great on %s at %s" % [id, m, ty, tg])
	_check(bad == 0, "every briefing is well formed (solution, era, modules, pt/en texts)")
	_check(eras.size() == 5, "briefings in all 5 eras")
	_check(kinds.has("space_apps") and kinds.has("dream") and kinds.has("race") and kinds.has("contract") and kinds.has("science"),
		"all five kinds: science, contract, space apps, dream, race")
	var sa := 0
	for b: Dictionary in all:
		sa += 1 if String(b["kind"]) == "space_apps" else 0
	_check(sa >= 4, "Space Apps style challenges: %d" % sa)
	# every module has its texts and every option a tech
	var missing := 0
	for m: Dictionary in PayloadRules.modules():
		if not csv.contains("\n" + PayloadRules.name_key(String(m["id"])) + ","):
			missing += 1
		if String(m.get("option", "")) != "" and PayloadRules.tech_for(String(m["id"])) == "":
			missing += 1
			print("    module %s: no tech unlocks option %s" % [m["id"], m["option"]])
	_check(missing == 0, "every module has a name and (if locked) a tech that unlocks it")


func _test_board() -> void:
	print("briefing board")
	var s := TycoonState.new_campaign(5, _team())
	var offers := BriefingDesk.offers(s)
	_check(offers.size() >= 2, "the board offers briefings at week 0 (%d)" % offers.size())
	TycoonResearch.complete(s, "basic_instruments")
	BriefingDesk.ensure(s)
	_check(BriefingDesk.offers(s).size() >= 3, "with the basic instruments the board fills up (%d)" % BriefingDesk.offers(s).size())
	var ok := true
	for o: Dictionary in offers:
		var b := BriefingDesk.briefing(String(o["id"]))
		ok = ok and int(b["era"]) == 1 and float(o["reward"]) > 0.0 and float(o["budget"]) > 0.0
	_check(ok, "week 0 offers are era 1, priced, with a budget")
	_check(BriefingDesk.eligible(s, BriefingDesk.briefing("first_hop")), "the first dream (sounding) can be flown from the start")
	_check(not BriefingDesk.eligible(s, BriefingDesk.briefing("lunar_ice")), "an era 3 briefing waits for its era")
	_check(BriefingDesk.spawn(s, "lunar_ice") and String(BriefingDesk.offers(s)[0]["id"]) == "lunar_ice",
		"dev spawn puts any briefing at the top of the board")
	# hints: a curious scientist names the needed module, a veteran bets on the type
	var hints := Discovery.briefing_hints(s, BriefingDesk.briefing("lunar_ice"))
	var keys: Array = hints.map(func(h: Dictionary) -> String: return String(h["key"]))
	_check("TY_BF_HINT_MODULE" in keys and hints[keys.find("TY_BF_HINT_MODULE")]["args"][1] == "TY_PL_M_SPECTROMETER",
		"a curious scientist (Bel) suggests the spectrometer")
	_check("TY_BF_HINT_ENV_SUN" in keys or "TY_BF_HINT_ENV_NIGHT" in keys, "a skilled engineer warns about the pole")
	_check("TY_BF_HINT_TYPE" in keys, "the level 3 controller bets on the mission type")
	# taking and paying
	BriefingDesk.spawn(s, "first_hop")
	var reward := float(BriefingDesk.offer(s, "first_hop")["reward"])
	var e := _run(s, "sounding", "suborbital", ["a", "b"], ["sensor_pack", "beacon", "battery"], [40, 30, 30], "first_hop")
	_check(not e.has("error") and String(e.get("briefing", {}).get("id", "")) == "first_hop", "a project answers the briefing")
	_check(BriefingDesk.offer(s, "first_hop").is_empty(), "the briefing left the board")
	var br: Dictionary = e.get("briefing", {})
	var paid := float(br.get("reward", 0.0))
	print("    first_hop: grade %.2f success %s met %s paid %.0f / %.0f" % [float(e.get("grade", 0)), e.get("success"), br.get("met"), paid, reward])
	_check(String(br.get("met", "")) in ["full", "partial", "missed"] and (paid > 0.0) == (String(br["met"]) != "missed"),
		"the client pays by the result")
	if e.get("success", false) and ProjectDesk.project_grade(e) >= 6.0:
		_check(BriefingDesk.is_solved(s, "first_hop") and not BriefingDesk.eligible(s, BriefingDesk.briefing("first_hop")),
			"a solved briefing does not come back")


# ------------------------------------------------------------ payload budgets
func _test_payload_budgets() -> void:
	print("payload budgets")
	var s := _state(3, 3)
	var plan := {"type": "earth_obs", "target": "sso", "payload": ["ir_camera", "spectrometer", "radar", "lidar", "solar_wing", "omni", "battery"]}
	var g := PayloadRules.gauges(s, plan)
	_check(String(g["mass"]["state"]) == "red" and "mass" in g["blocked"], "too many instruments: mass in the red (%.0f / %.0f kg)" % [g["mass"]["have"], g["mass"]["need"]])
	_check(ProjectDesk.start_error(s, "earth_obs", "sso", ["a", "b"], {}, {"payload": plan["payload"]}) == "TY_PL_ERR_MASS",
		"a payload in the red cannot start")
	var weak := ["radar", "omni", "battery", "solar_body"]
	_check(PayloadRules.plan_error(s, {"type": "earth_obs", "target": "sso", "payload": weak}) == "TY_PL_ERR_ENERGY",
		"a radar on body panels: not enough energy")
	_check(PayloadRules.plan_error(s, {"type": "earth_obs", "target": "sso", "payload": ["battery", "solar_body", "omni"]}) == "TY_PL_ERR_NO_INSTRUMENT",
		"an observation satellite needs an instrument")
	_check(PayloadRules.plan_error(s, {"type": "earth_obs", "target": "sso", "payload": ["ir_camera", "solar_wing", "omni", "battery"]}) == "",
		"a sensible plan passes")
	var poor := s.cash
	s.cash = 1000.0
	_check(PayloadRules.plan_error(s, {"type": "earth_obs", "target": "sso", "payload": ["ir_camera", "solar_wing", "omni", "battery"],
		"dev_cost": 50000.0, "launch_cost": 100000.0}) == "TY_PL_ERR_CASH", "budget in the red blocks the plan")
	s.cash = poor
	_check(PayloadRules.toggle(["omni", "camera"], "hga") == ["camera", "hga"], "one antenna at a time")
	# the hidden lunar night: assumed away until known
	var lander := ["seismometer", "camera", "omni", "solar_wing", "battery"]
	s.unlocked.erase("rtg_power")  # the RTG research would tell the night
	var before := PayloadRules.gauges(s, {"type": "lander", "target": "lunar_surface", "payload": lander})
	_check(String(before["energy"]["state"]) != "red", "unknown lunar night: the planner does not see the problem yet")
	_check(PayloadRules.gauges(s, {"type": "lander", "target": "lunar_surface", "payload": lander, "briefing_id": "moonquakes"})["energy"]["state"] == "red",
		"the moonquakes story tells the night: now the planner sees it")
	s.discovery["env"] = {"lunar_surface": true}
	s.unlocked["rtg_power"] = true
	var after := PayloadRules.gauges(s, {"type": "lander", "target": "lunar_surface", "payload": lander})
	_check(String(after["energy"]["state"]) == "red", "known lunar night and cold: the same payload is red")
	_check(PayloadRules.plan_error(s, {"type": "lander", "target": "lunar_surface", "payload": lander}) == "",
		"but a short night only warns (the mission lives shorter): it does not block")
	var fixed := ["seismometer", "camera", "omni", "solar_wing", "battery", "battery_l", "heater"]
	var ok := PayloadRules.gauges(s, {"type": "lander", "target": "lunar_surface", "payload": fixed})
	_check(String(ok["energy"]["state"]) != "red", "heaters and a large battery get through the night (margin %.2f)" % float(ok["energy"]["margin"]))
	var rtg := ["seismometer", "camera", "omni", "rtg", "battery"]
	_check(float(PayloadRules.gauges(s, {"type": "lander", "target": "lunar_surface", "payload": rtg})["energy"]["margin"]) > float(ok["energy"]["margin"]),
		"an RTG does it with margin to spare")
	# the starter kit always passes
	var bad := 0
	for t: Dictionary in s.mdata.get("types", []):
		for tg: String in t.get("compat", {}):
			var kit := PayloadRules.default_payload(s, String(t["id"]), tg)
			var err := PayloadRules.plan_error(s, {"type": String(t["id"]), "target": tg, "payload": kit}, false)
			if err != "":
				bad += 1
				print("    starter kit %s at %s: %s %s" % [t["id"], tg, err, kit])
	_check(bad == 0, "the Cometlings' starter kit passes the gauges for every type and target")
	var s1 := TycoonState.new_campaign(9, _team())
	var kit1 := PayloadRules.default_payload(s1, "sounding", "suborbital")
	_check(PayloadRules.plan_error(s1, {"type": "sounding", "target": "suborbital", "payload": kit1}, false) == "",
		"week 0: the starter sounding kit works with nothing researched (%s)" % [kit1])


# ------------------------------------------------------------ hidden ideals
func _test_ideals_matter() -> void:
	print("hidden ideals")
	var s := _state(4, 3)
	var good_team: Array[String] = ["a", "b", "c", "d"]
	var ideal: Array = s.mission_type("orbiter").get("ratio", [])
	var good := {"type": "orbiter", "target": "lunar_orbit", "payload": ["camera", "lidar", "spectrometer", "solar_wing", "hga", "battery"],
		"staff": good_team, "ideal": ideal}
	var junk := {"type": "orbiter", "target": "lunar_orbit", "payload": ["sensor_pack", "particle", "solar_wing", "omni", "battery"],
		"staff": good_team, "ideal": ideal}
	var rg := MissionFit.evaluate(s, good)
	var rj := MissionFit.evaluate(s, junk)
	_check(float(rg["instrument"]) > float(rj["instrument"]) + 0.4, "fitting instruments score higher (%.2f vs %.2f)" % [rg["instrument"], rj["instrument"]])
	_check(float(rg["fit"]) > float(rj["fit"]), "and the plan fits better (%.2f vs %.2f)" % [rg["fit"], rj["fit"]])
	var lone := good.duplicate()
	lone["staff"] = ["g"]
	_check(float(MissionFit.evaluate(s, lone)["team"]) < float(rg["team"]), "a lone propulsion engineer is a worse team mix")
	# the objective of a briefing
	var bg := good.duplicate()
	bg["briefing_id"] = "moon_map"
	var bw := bg.duplicate()
	bw["target"] = "lunar_flyby"
	_check(float(MissionFit.evaluate(s, bg)["objective"]) > float(MissionFit.evaluate(s, bw)["objective"]),
		"the client's target scores higher than a near miss")
	# end to end: same team and rocket, matched vs mismatched plan and levers
	var ranges := Discovery.lever_ranges(ideal)
	var best: Array = []
	for k in 3:
		best.append([int(ranges[k][0][2]), int(ranges[k][1][2]), int(ranges[k][2][2])])
	var a := _state(4, 3)
	var b := _state(4, 3)
	var ea := _run(a, "orbiter", "lunar_orbit", good_team, good["payload"], best)
	var eb := _run(b, "orbiter", "lunar_orbit", good_team, junk["payload"], [[80, 10, 10], [80, 10, 10], [80, 10, 10]])
	print("    matched grade %.2f (dev %.2f, fit %.2f)  mismatched %.2f (dev %.2f, fit %.2f)" % [ProjectDesk.project_grade(ea),
		float(ea.get("grade_dev", 0)), float(ea.get("fit", {}).get("fit", 0)), ProjectDesk.project_grade(eb), float(eb.get("grade_dev", 0)),
		float(eb.get("fit", {}).get("fit", 0))])
	_check(ProjectDesk.project_grade(ea) > ProjectDesk.project_grade(eb) + 1.0, "matching the hidden ideals gives a clearly better grade")
	_check(float(ea.get("fit", {}).get("match", 0)) > 0.85, "the journal's best lever split hits the ideal balance (%.2f)" % float(ea.get("fit", {}).get("match", 0)))
	# a great combo
	var c := _state(6, 3)
	var ec := _run(c, "orbiter", "lunar_orbit", good_team, good["payload"], best)
	_check(bool(ec.get("fit", {}).get("great", false)), "orbiter at lunar orbit with camera, lidar, spectrometer and the right levers: a great combo")
	_check(ProjectDesk.project_grade(ec) > float(ec.get("grade_dev", 0)), "the great combo lifts the grade above the development grade (%.2f > %.2f)" % [ProjectDesk.project_grade(ec), float(ec.get("grade_dev", 0))])
	# early eras forgive more
	var e1 := _state(7, 1)
	var e5 := _state(7, 5)
	var r1 := MissionFit.evaluate(e1, junk)
	var r5 := MissionFit.evaluate(e5, junk)
	_check(float(r1["mult"]) > float(r5["mult"]), "the same poor plan costs less in era 1 than in era 5 (x%.2f vs x%.2f)" % [r1["mult"], r5["mult"]])


# ------------------------------------------------------------ feedback
func _test_feedback() -> void:
	print("feedback")
	var s := _state(8, 3)
	var team: Array[String] = ["a", "c", "g"]  # no scientist
	var ctx := {"type": "lander", "target": "lunar_surface", "payload": ["camera", "particle", "omni", "solar_wing", "battery"],
		"staff": team, "ideal": s.mission_type("lander")["ratio"], "briefing_id": "moonquakes", "pts": [10.0, 60.0, 10.0, 20.0]}
	var r := MissionFit.evaluate(s, ctx)
	var fb := MissionFit.feedback(s, r, "lander", "lunar_surface")
	var all := MissionFit.feedback(s, r, "lander", "lunar_surface")
	BriefingDesk.disc()["feedback_max"] = 20
	all = MissionFit.feedback(s, r, "lander", "lunar_surface")
	BriefingDesk.disc()["feedback_max"] = 5
	_check(fb.size() <= 5, "at most 5 lines on the review (%d)" % fb.size())
	_check(_has(all, "TY_FB_MISSING", "TY_PL_M_SEISMOMETER"), "the scientists missed the seismometer")
	_check(_has(all, "TY_FB_NIGHT_MOON"), "the battery did not last the lunar night")
	_check(_has(all, "TY_FB_COLD"), "the cold froze the instruments")
	_check(_has(all, "TY_FB_INSTR_USELESS", "TY_PL_M_PARTICLE"), "the particle detector was dead weight on the surface")
	_check(_has(all, "TY_FB_BAR_HIGH", "TY_BAR_SCI") or _has(all, "TY_FB_BAR_LOW", "TY_BAR_ENG"), "the lever balance is named")
	_check(not _has(all, "TY_FB_TEAM_MISSING_SCI"), "science (20%) is not a bar the lander leans on")
	var ctx2 := {"type": "earth_obs", "target": "sso", "payload": ["ir_camera", "spectrometer", "omni", "solar_wing", "battery"],
		"staff": ["a", "c"], "ideal": s.mission_type("earth_obs")["ratio"]}
	var fb2 := MissionFit.feedback(s, MissionFit.evaluate(s, ctx2), "earth_obs", "sso")
	_check(_has(fb2, "TY_FB_TEAM_MISSING_SCI"), "an observation satellite without a scientist: Science was orphaned")
	_check(_has(fb2, "TY_FB_OPS_OVERLOAD"), "8 Gb a week and nobody in operations: overloaded")
	var ctx3 := ctx2.duplicate()
	ctx3["staff"] = ["a", "b", "c", "d"]
	ctx3["payload"] = ["ir_camera", "spectrometer", "hga", "solar_wing", "battery"]
	var r3 := MissionFit.evaluate(s, ctx3)
	_check(not _has(MissionFit.feedback(s, r3, "earth_obs", "sso"), "TY_FB_OPS_OVERLOAD") and float(r3["team"]) >= 1.0,
		"with a controller and a scientist the team is right")
	_check(_has(MissionFit.feedback(s, r3, "earth_obs", "sso"), "TY_FB_INSTR_STAR"), "a great instrument is praised")
	# feedback texts exist
	var csv := FileAccess.get_file_as_string("res://i18n/tycoon_project_strings.csv")
	var missing := 0
	for f: Dictionary in all + fb2:
		if not csv.contains("\n" + String(f["key"]) + ","):
			missing += 1
			print("    missing text %s" % f["key"])
	_check(missing == 0, "every feedback line has its text")


# ------------------------------------------------------------ journal
func _test_journal() -> void:
	print("journal")
	var s := _state(9, 3)
	_check(Discovery.instr_rating(s, "orbiter", "lunar_orbit", "lidar") == "" and Discovery.combo(s, "orbiter", "lunar_orbit").is_empty(),
		"a fresh journal has no ratings nor combos")
	_check(Discovery.ratio_known(s, "orbiter"), "the lab complex research reveals the orbiter's balance")
	# lab_complex is done (every tech): it reveals the orbiter's balance; check a type it does not
	_check(not Discovery.ratio_known(s, "rover"), "the rover's balance is hidden")
	var payload := ["camera", "spectrometer", "sensor_pack", "solar_wing", "rtg", "hga", "battery"]
	var e := _run(s, "rover", "lunar_pole", ["a", "b", "c", "d"], payload + ["battery_l", "heater"], [34, 33, 33])
	_check(not e.has("error"), "rover project flew (%s)" % e.get("error", ""))
	_check(Discovery.attempts(s, "rover") == 1 and not Discovery.ratio_known(s, "rover"), "one attempt: the balance is still hidden")
	_check(Discovery.instr_rating(s, "rover", "lunar_pole", "spectrometer") == "great", "the spectrometer is rated great at the pole")
	_check(Discovery.instr_rating(s, "rover", "lunar_pole", "sensor_pack") == "useless", "the sensor pack is rated useless there")
	_check(not Discovery.combo(s, "rover", "lunar_pole").is_empty(), "the combo is in the journal")
	_check(int(e.get("learned", []).size()) >= 3, "the review lists what was learned (%d)" % int(e.get("learned", []).size()))
	if e.get("success", false):
		_check(Discovery.env_known(s, "lunar_pole"), "a spacecraft at the pole reveals its environment")
	_run(s, "rover", "lunar_pole", ["a", "b", "c", "d"], payload + ["battery_l", "heater"], [34, 33, 33])
	_check(Discovery.ratio_known(s, "rover"), "two attempts: the rover's ideal balance is revealed")
	_check(Discovery.notes(s).size() >= 3 and Discovery.count(s) > 0, "the journal feed has notes")
	# lever ranges: the best split for a sounding (40/20/15/25) in the concept phase
	var lr := Discovery.lever_ranges([0.4, 0.2, 0.15, 0.25])
	_check(lr.size() == 3 and (lr[0] as Array).size() == 3, "lever ranges: 3 phases x 3 levers")
	var bs := [int(lr[0][0][2]) / 100.0, int(lr[0][1][2]) / 100.0, int(lr[0][2][2]) / 100.0]
	var m := MissionProject.ratio_match(MissionProject.fractions_of(ProjectRules.focus(0, bs)), [0.4, 0.2, 0.15, 0.25])
	_check(m > 0.85 and int(lr[0][0][0]) <= int(lr[0][0][2]) and int(lr[0][0][2]) <= int(lr[0][0][1]),
		"the best split sits inside its range and matches well (%.2f)" % m)
	# research reveals
	var r := TycoonState.new_campaign(2, _team())
	_check(not Discovery.env_known(r, "lunar_surface"), "the lunar night is unknown at the start")
	TycoonResearch.complete(r, "rtg_power")
	_check(Discovery.env_known(r, "lunar_surface"), "the RTG research reveals the lunar night")
	_check(Discovery.env_known(r, "leo"), "low orbit hides nothing")
	Discovery.reveal_all(r)
	_check(Discovery.ratio_known(r, "comet_mission") and Discovery.instr_rating(r, "comet_mission", "comet", "drill") == "great"
		and Discovery.env_known(r, "comet"), "dev: reveal all")


# ------------------------------------------------------------ save
func _test_save_roundtrip() -> void:
	print("save / load")
	var s := _state(10, 3)
	BriefingDesk.spawn(s, "lunar_ice")
	_run(s, "orbiter", "lunar_orbit", ["a", "b", "c", "d"], ["camera", "lidar", "solar_wing", "hga", "battery"], [40, 40, 20])
	var p := ProjectDesk.start_project(s, "impactor", "lunar_pole", ["a", "b"], "", {},
		{"payload": ["spectrometer", "camera", "omni", "battery", "battery_l"], "briefing_id": "lunar_ice"})
	_check(p != null and p.briefing_id == "lunar_ice" and p.payload.size() == 5, "a briefing project with its payload (%s)" % (
		"ok" if p else ProjectDesk.start_error(s, "impactor", "lunar_pole", ["a", "b"], {}, {"payload": ["spectrometer", "camera", "omni", "battery", "battery_l"]})))
	var d := s.to_dict()
	var l := TycoonState.from_dict(JSON.parse_string(JSON.stringify(TycoonSave.encode(d))))
	var lp := ProjectDesk.find(l, p.id) if p else null
	_check(lp != null and lp.briefing_id == "lunar_ice" and lp.payload == p.payload and float(lp.briefing_terms.get("reward", 0)) > 0.0,
		"the project keeps its briefing, terms and payload")
	_check(JSON.stringify(Discovery.combo(l, "orbiter", "lunar_orbit")) == JSON.stringify(JSON.parse_string(JSON.stringify(Discovery.combo(s, "orbiter", "lunar_orbit"))))
		and Discovery.instr_rating(l, "orbiter", "lunar_orbit", "lidar") != "", "the journal survives")
	_check((Discovery.d(l)["taken"] as Dictionary).has("lunar_ice"), "the taken briefing survives")
	_check(TycoonSave.save(s, "test_missions") == OK, "save to a slot")
	var ls := TycoonSave.load_state("test_missions")
	_check(ls != null and _canon(ls.to_dict()) == _canon(s.to_dict()), "slot save -> load gives the same state")
	for i in 20:
		s.advance_week()
		ls.advance_week()
	_check(_canon(ls.to_dict()) == _canon(s.to_dict()), "20 weeks later both campaigns (and the board) are the same")
	TycoonSave.delete("test_missions")


static func _canon(d: Dictionary) -> String:
	var j: Variant = JSON.parse_string(JSON.stringify(TycoonSave.encode(d), "", true, true))
	return JSON.stringify(j, "", true, true)


# ------------------------------------------------------------ long sim: knowledge pays
const COMBOS := [["earth_obs", "sso"], ["orbiter", "lunar_orbit"], ["lander", "lunar_surface"], ["space_weather", "geo"],
	["telescope", "geo"], ["rover", "lunar_pole"]]
const ROUNDS := 4


## Two players fly the same 6 type x target combos 4 times on the same seed. The naive one never
## reads the journal: random instruments, even levers, a random team. The learner starts the
## same but uses what the journal knows: rated instruments, the revealed balance's lever split,
## a team that covers the bars, and the environment (heaters, batteries).
func _test_long_sim() -> void:
	print("long sim: knowledge improves the grades")
	var seeds := [101, 202]
	var naive_late := 0.0
	var learn_late := 0.0
	var learn_early := 0.0
	var naive_early := 0.0
	var n_late := 0
	var n_early := 0
	for sd: int in seeds:
		var rn := _sim(sd, false)
		var rl := _sim(sd, true)
		for r in ROUNDS:
			print("    seed %d round %d: naive %.2f  learner %.2f" % [sd, r + 1, rn[r], rl[r]])
		naive_early += rn[0]
		learn_early += rl[0]
		n_early += 1
		for r in range(2, ROUNDS):
			naive_late += rn[r]
			learn_late += rl[r]
			n_late += 1
	naive_late /= n_late
	learn_late /= n_late
	naive_early /= n_early
	learn_early /= n_early
	print("    first round: naive %.2f learner %.2f   rounds 3-4: naive %.2f learner %.2f" % [naive_early, learn_early, naive_late, learn_late])
	_check(learn_late > naive_late + 1.0, "with the journal, later grades are clearly better (%.2f vs %.2f)" % [learn_late, naive_late])
	_check(learn_late - learn_early > naive_late - naive_early + 0.5, "the learner improves more than the naive player")


## Average final grade per round.
func _sim(p_seed: int, learner: bool) -> Array[float]:
	var s := _state(p_seed, 3)
	var dice := RandomNumberGenerator.new()
	dice.seed = p_seed * 7 + 3
	var out: Array[float] = []
	for r in ROUNDS:
		var tot := 0.0
		for c: Array in COMBOS:
			var ty := String(c[0])
			var tg := String(c[1])
			var payload := _plan(s, ty, tg, dice, learner)
			var team := _pick_team(s, ty, tg, dice, learner)
			var sl: Array = [[34, 33, 33], [34, 33, 33], [34, 33, 33]]
			if learner and Discovery.ratio_known(s, ty):
				var lr := Discovery.lever_ranges(s.mission_type(ty)["ratio"])
				sl = []
				for k in 3:
					sl.append([int(lr[k][0][2]), int(lr[k][1][2]), int(lr[k][2][2])])
			var e := _run(s, ty, tg, team, payload, sl)
			if e.has("error"):
				print("    could not start %s at %s: %s %s" % [ty, tg, e["error"], payload])
			tot += ProjectDesk.project_grade(e)
			if OS.get_environment("SIM_DEBUG") != "":
				var f: Dictionary = e.get("fit", {})
				print("      %s r%d %-13s %-13s g %.2f dev %.2f fit %.2f ins %.2f pow %.2f dat %.2f team %.2f match %.2f %s" % ["L" if learner else "N", r + 1, ty, tg,
					float(e.get("grade", 0)), float(e.get("grade_dev", 0)), float(f.get("fit", 0)), float(f.get("instrument", 0)), float(f.get("power", 0)),
					float(f.get("data", 0)), float(f.get("team", 0)), float(f.get("match", 0)), e.get("payload", [])])
			# the same people rest a little between projects
			for m in s.staff:
				m["morale"] = 90.0
		out.append(tot / COMBOS.size())
	return out


static func _instruments(s: TycoonState) -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in PayloadRules.modules_of("instrument"):
		if PayloadRules.is_available(s, String(m["id"])):
			out.append(String(m["id"]))
	return out


## A payload: the starter kit's power and comms plus instruments, made to pass the gauges.
func _plan(s: TycoonState, ty: String, tg: String, dice: RandomNumberGenerator, learner: bool) -> Array:
	var pool := _instruments(s)
	var picks: Array[String] = []
	if learner:
		var rank := {"great": 3, "good": 2, "": 1, "useless": -1, "bad": -2}
		pool.sort_custom(func(x: String, y: String) -> bool:
			var rx: int = rank[Discovery.instr_rating(s, ty, tg, x)]
			var ry: int = rank[Discovery.instr_rating(s, ty, tg, y)]
			return rx > ry if rx != ry else x < y)
		var cap := int(PayloadRules.type_rules(ty).get("instr_cap", 3))
		var known := 0
		for x in pool:
			var rt := Discovery.instr_rating(s, ty, tg, x)
			if rt in ["great", "good"] and known < cap:
				picks.append(x)
				known += 1 if rt == "good" else 2
		# explore unknown instruments while the journal is thin: first the ones that shone at
		# this target on other mission types (the journal's other pages), then any
		var unknown := pool.filter(func(x: String) -> bool: return Discovery.instr_rating(s, ty, tg, x) == "")
		unknown.sort_custom(func(x: String, y: String) -> bool: return _elsewhere(s, tg, x) > _elsewhere(s, tg, y))
		var tries := 0
		while known < cap and not unknown.is_empty() and tries < 2:
			var pick: String = unknown.pop_front() if _elsewhere(s, tg, unknown[0]) > 0 else unknown.pop_at(dice.randi_range(0, unknown.size() - 1))
			picks.append(pick)
			known += 1
			tries += 1
	else:
		for i in 2:
			var x := pool[dice.randi_range(0, pool.size() - 1)]
			if not x in picks:
				picks.append(x)
	var base := PayloadRules.default_payload(s, ty, tg)
	var payload: Array = []
	for m in base:
		if PayloadRules.module(m).get("kind", "") != "instrument":
			payload.append(m)
	for x in picks:
		payload.append(x)
	# make it fly: strongest power the agency has, the night and the cold when it knows them
	for extra in ["solar_wing", "battery_l", "rtg", "hga"]:
		if PayloadRules.plan_error(s, {"type": ty, "target": tg, "payload": payload}, false) == "":
			break
		if not extra in payload:
			payload = PayloadRules.toggle(payload, extra)
	if learner:
		# the planner shows the comms gauge: take the antenna that brings the most data down
		var best_ant := PayloadRules.antenna(payload)
		var best_down := -1.0
		for ant in ["omni", "hga", "reflector"]:
			var trial: Array = PayloadRules.toggle(payload, ant) if PayloadRules.antenna(payload) != ant else payload
			if PayloadRules.plan_error(s, {"type": ty, "target": tg, "payload": trial}, false) == "":
				var dn := PayloadRules.downlink(s, ty, tg, trial)
				if dn > best_down * 1.2:
					best_down = dn
					best_ant = ant
		if best_ant != "" and PayloadRules.antenna(payload) != best_ant:
			payload = PayloadRules.toggle(payload, best_ant)
		var en := PayloadRules.energy(s, ty, payload, PayloadRules.env(s, tg))
		if not en["cold_ok"] and not "heater" in payload:
			payload.append("heater")
		if float(en["night_margin"]) < 0.2 and not "battery_l" in payload:
			payload.append("battery_l")
	while PayloadRules.plan_error(s, {"type": ty, "target": tg, "payload": payload}, false) != "" and not picks.is_empty():
		payload.erase(picks.pop_back())
	if PayloadRules.plan_error(s, {"type": ty, "target": tg, "payload": payload}, false) != "":
		return base
	return payload


## How well an instrument did at this target on any mission type the journal knows (0 unknown).
static func _elsewhere(s: TycoonState, tg: String, m: String) -> int:
	var best := 0
	for t: Dictionary in s.mdata.get("types", []):
		var r := Discovery.instr_rating(s, String(t["id"]), tg, m)
		if r == "great":
			best = maxi(best, 2)
		elif r == "good":
			best = maxi(best, 1)
	return best


func _pick_team(s: TycoonState, ty: String, tg: String, dice: RandomNumberGenerator, learner: bool) -> Array[String]:
	var probe := MissionProject.new()
	probe.type_id = ty
	var n := probe.ideal_team(s)
	var free := ProjectDesk.free_staff(s)
	var out: Array[String] = []
	if learner and Discovery.ratio_known(s, ty):
		var ratio: Array = s.mission_type(ty)["ratio"]
		for bi in 4:
			if float(ratio[bi]) >= 0.25 or (bi == ProjectRules.OPS and float(ratio[bi]) >= 0.15):
				for m in free:
					if String(s.profession(String(m["profession"])).get("primary", "")) == ProjectRules.BARS[bi] and not String(m["id"]) in out:
						out.append(String(m["id"]))
						break
	var rest := free.duplicate()
	while out.size() < n and not rest.is_empty():
		var m: Dictionary = rest.pop_at(dice.randi_range(0, rest.size() - 1))
		if not String(m["id"]) in out and String(m.get("profession", "")) != "pilot":
			out.append(String(m["id"]))
	return out


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
