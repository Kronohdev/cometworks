extends SceneTree
## Headless checks of rover missions in the career (src/rover/rover_missions.gd):
##   - a rover project starts with a workshop rover in its payload (the planner accepts it) and
##     flies; once it reaches the surface it can be driven, with the rover the player built
##   - a drive's objectives and science go back into the mission (capped, objectives done stay
##     done), survive save / load, and the mission's archive entry gets its surface summary with
##     what the rover then did alone
##   - the automatic mode: deterministic, it needs the tools, air for the drone, the climb, an
##     RTG for the polar night; it never touches the campaign RNG
##   - the rover briefings and objective sets exist, with texts
## Run: godot --headless --path . --script res://tests/test_rover_missions.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	_check(RoverMissions != null and not RoverMissions.data().is_empty(), "RoverMissions loaded")
	_test_data()
	_test_auto()
	_test_career()
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL: " + msg)


func _test_data() -> void:
	var sets: Dictionary = RoverMissions.data()["sets"]
	for k: String in sets:
		var list := RoverMissions.objective_set(k)
		_check(list.size() == (sets[k] as Array).size(), "set %s: every objective exists" % k)
		for o in list:
			_check(TranslationServer.translate(String(o["label_key"])) != String(o["label_key"]), "%s has a label" % o["id"])
			_check(StringName(o["kind"]) in SurfaceSession.ACTIONS, "%s kind %s is an action" % [o["id"], o["kind"]])
	for bid in ["crater_rim", "landing_scout", "sample_cache"]:
		var b := BriefingDesk.briefing(bid)
		_check(not b.is_empty(), "briefing %s exists" % bid)
		_check(TranslationServer.translate("TY_BF_%s_TITLE" % bid.to_upper()) != "TY_BF_%s_TITLE" % bid.to_upper(), "briefing %s has a title" % bid)
		_check(sets.has("briefing:" + bid), "briefing %s has surface objectives" % bid)
		_check((b["solution"]["types"] as Dictionary).has("rover"), "briefing %s wants a rover" % bid)
	for body in ["moon", "mars", "earth", "mercury", "europa", "titan"]:
		_check(RoverDesign.is_valid(RoverMissions.sandbox_design(StringName(body))), "sandbox rover of %s is valid" % body)


func _test_auto() -> void:
	var objs := RoverMissions.objective_set("sandbox:mars")
	var basic := RoverDesign.make("t", "wheels4", ["solar", "battery", "camera", "beacon"])
	var r := RoverMissions.auto_result(basic, objs, "mars")
	_check("land_photo" in r["done"] and not "rock_scan" in r["done"], "auto: a camera rover photographs, cannot scan")
	var whys := {}
	for f in r["failed"]:
		whys[f["id"]] = f["why"]
	_check(whys.get("rock_scan", "") == "RV_AUTO_NO_TOOL", "auto says why: no tool")
	var drone := RoverDesign.make("t", "wheels6", ["rtg", "camera", "drone", "spectrometer", "weather", "hga"])
	var rm := RoverMissions.auto_result(drone, objs, "mars")
	_check("drone_scout" in rm["done"], "auto: the drone flies on Mars")
	var moon := RoverMissions.auto_result(drone, [RoverMissions.objective_def("drone_scout")], "moon")
	_check(moon["done"].is_empty() and moon["failed"][0]["why"] == "RV_AUTO_NO_AIR", "auto: no drone flight on the Moon")
	var rim := RoverMissions.auto_result(RoverDesign.make("h", "hopper", ["rtg", "camera", "hga"]), [RoverMissions.objective_def("rim")], "moon")
	_check(rim["failed"][0]["why"] == "RV_AUTO_TOO_STEEP", "auto: the hopper's chassis cannot climb to the rim")
	var ice := [RoverMissions.objective_def("ice_drill")]
	var sunny := RoverDesign.make("s", "wheels6", ["solar_wing", "battery", "drill", "omni"])
	_check(RoverMissions.auto_result(sunny, ice, "moon", true)["failed"][0]["why"] == "RV_AUTO_COLD", "auto: no RTG, the polar night stops it")
	var nuke := RoverDesign.toggle(sunny, "rtg")
	nuke = RoverDesign.toggle(nuke, "solar_wing")
	_check("ice_drill" in RoverMissions.auto_result(nuke, ice, "moon", true)["done"], "auto: with an RTG it drills the polar ice")
	_check(JSON.stringify(RoverMissions.auto_result(drone, objs, "mars")) == JSON.stringify(rm), "auto is deterministic")
	_check(float(rm["science"]) < RoverMissions.objectives_science(objs), "auto earns less than everything")


func _campaign(p_seed: int) -> TycoonState:
	var team: Array[Dictionary] = [
		{"id": "a", "name": "Ada", "profession": "systems_engineer", "skill": 0.6, "morale": 80.0, "level": 2},
		{"id": "b", "name": "Bel", "profession": "scientist", "skill": 0.5, "morale": 70.0, "level": 2},
		{"id": "c", "name": "Cid", "profession": "test_technician", "skill": 0.5, "morale": 70.0, "level": 1},
		{"id": "d", "name": "Duo", "profession": "flight_controller", "skill": 0.4, "morale": 60.0, "level": 1}]
	var s := TycoonState.new_campaign(p_seed, team)
	for t: Dictionary in TycoonResearch.techs():
		if not TycoonResearch.is_done(s, String(t["id"])):
			TycoonResearch.complete(s, String(t["id"]))
	s.cash = 9.0e7
	return s


func _launch_rover(s: TycoonState, design: Dictionary) -> String:
	var team: Array[String] = []
	for m in ProjectDesk.free_staff(s):
		if team.size() < 4:
			team.append(String(m["id"]))
	var payload := RoverDesign.apply_to_payload(PayloadRules.default_payload(s, "rover", "lunar_surface"), design)
	var err := ProjectDesk.start_error(s, "rover", "lunar_surface", team, {}, {"payload": payload})
	_check(err == "", "a rover project with a workshop rover can start (%s)" % err)
	var p := ProjectDesk.start_project(s, "rover", "lunar_surface", team, "", {}, {"payload": payload})
	if p == null:
		return ""
	_check(RoverDesign.from_payload(p.payload)["name"] == design["name"], "the project carries the rover")
	ProjectDesk.dev_force_outcome = "success"
	var entry := ProjectDesk.launch(s, p)
	_check(bool(entry.get("success", false)), "the rover launches")
	return p.id


func _until(s: TycoonState, id: String, status: String, max_weeks := 60) -> Dictionary:
	for i in max_weeks:
		var m := MissionOps.find(s, id)
		if m.is_empty() or String(m.get("status", "")) == status:
			return m
		# keep the decisions out of the way
		if not (m.get("decision", {}) as Dictionary).is_empty():
			MissionOps.decide(s, id, MissionOps.default_choice(String(m["event"])), true)
		s.advance_week()
	return MissionOps.find(s, id)


func _test_career() -> void:
	var s := _campaign(31337)
	var design := RoverDesign.make("Tatu Teste", "wheels6", ["solar_wing", "battery", "camera", "spectrometer", "arm", "omni"])
	var id := _launch_rover(s, design)
	if id == "":
		return
	var m := MissionOps.find(s, id)
	_check(not m.is_empty() and RoverMissions.is_rover_mission(s, m), "a rover mission in operation")
	_check(not RoverMissions.can_drive(s, m), "not drivable during the cruise")
	m = _until(s, id, "ops")
	_check(String(m.get("status", "")) == "ops", "it reaches the surface (status %s)" % m.get("status", "?"))
	if String(m.get("status", "")) != "ops":
		return
	_check(RoverMissions.can_drive(s, m), "arrived: Controlar o rover")
	_check(s.news.any(func(n: Dictionary) -> bool: return String(n.get("key", "")) == "RV_NEWS_ARRIVED"), "the news says it arrived")
	var rng0 := s.rng.state
	var session := RoverMissions.start_drive(s, id)
	_check(session != null and session.rover["name"] == "Tatu Teste", "the drive uses the player's rover")
	_check(session.body == &"moon" and session.objectives.size() == 3, "lunar surface objectives (%d)" % session.objectives.size())
	session.report_objective(&"land_photo")
	session.report_objective(&"rock_scan")
	session.add_science(5.0, &"ground")
	session.distance = 120.0
	var res := session.finish()
	var sci0 := float(m["science"])
	var rp0 := s.research_points
	var add := RoverMissions.apply_result(s, id, res)
	_check(add > 20.0 and is_equal_approx(float(m["science"]), sci0 + add), "the drive's science goes into the mission (+%.1f)" % add)
	_check(s.research_points > rp0, "and into the research points")
	var again := RoverMissions.start_drive(s, id)
	_check(again.objective(&"land_photo")["done"] and not again.objective(&"drive_100")["done"], "objectives done stay done")
	again.add_science(9999.0, &"farm")
	var add2 := RoverMissions.apply_result(s, id, again.finish())
	var cap := RoverMissions.objectives_science(again.objectives) * 1.6 + 12.0
	_check(float(RoverGarage.drive_of(s, id)["science"]) <= cap + 0.01, "drive science is capped (%.1f <= %.1f, +%.1f)" % [
		float(RoverGarage.drive_of(s, id)["science"]), cap, add2])
	_check(s.rng.state == rng0, "drives never touch the campaign RNG")
	# save / load in the middle of the operation
	var s2 := TycoonState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var m2 := MissionOps.find(s2, id)
	_check(RoverMissions.can_drive(s2, m2) and RoverMissions.rover_of(s2, m2)["name"] == "Tatu Teste", "after loading: still drivable, same rover")
	_check(RoverGarage.drive_of(s2, id)["done"].size() == 2, "after loading: the drive's objectives")
	# the end of the mission: the archive tells the surface story
	var end := _until(s2, id, "__never__", 80)
	_check(end.is_empty(), "the mission ends")
	var entry := {}
	for a in s2.mission_archive:
		if String(a.get("id", "")) == id:
			entry = a
	_check(not entry.is_empty() and entry.has("surface"), "the archive entry has a surface summary")
	if entry.has("surface"):
		var sf: Dictionary = entry["surface"]
		_check(bool(sf["driven"]) and int(sf["total"]) == 3, "driven, 3 objectives")
		if String(entry.get("status", "")) == "done":
			_check("drive_100" in sf["done"] and "drive_100" in sf["auto_done"], "the rover drove the 100 m alone at the end")
		_check(RoverMissions.summary_text(sf).contains("3"), "summary text: %s" % RoverMissions.summary_text(sf))
	# a rover type launched without a workshop rover drives a basic one, automatic only
	var s3 := _campaign(4040)
	var team: Array[String] = []
	for f in ProjectDesk.free_staff(s3):
		if team.size() < 4:
			team.append(String(f["id"]))
	var p := ProjectDesk.start_project(s3, "rover", "lunar_surface", team)
	ProjectDesk.dev_force_outcome = "success"
	ProjectDesk.launch(s3, p)
	var m3 := MissionOps.find(s3, p.id)
	var basic := RoverMissions.rover_of(s3, m3)
	_check(RoverDesign.is_valid(basic) and "camera" in basic["parts"], "no workshop rover: a basic one with the payload's camera (%s)" % [basic["parts"]])
	var rng3 := s3.rng.state
	var arch0 := s3.mission_archive.size()
	_until(s3, p.id, "__never__", 80)
	if s3.mission_archive.size() > arch0:
		var a3: Dictionary = s3.mission_archive[-1]
		_check(a3.has("surface") and not bool(a3["surface"]["driven"]), "automatic mission: surface summary, not driven")
		if String(a3.get("status", "")) == "done":
			_check(not (a3["surface"]["auto_done"] as Array).is_empty(), "the rover did something alone")
	_check(s3.rng.state != rng3, "(the weeks themselves use the RNG as before)")
