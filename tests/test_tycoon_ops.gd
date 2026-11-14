extends SceneTree
## Headless checks for mission operations (src/tycoon/ops/mission_ops.gd, GDD E5):
## data flow obeys the storage buffer and the downlink limit, a better antenna network brings
## down more data and science, missions end (mission_completed, archive), decisions apply
## their consequences, and the same seed gives the same campaign.
## Run: godot --headless --path . --script res://tests/test_tycoon_ops.gd

var _failures := 0


func _initialize() -> void:
	_test_buffer_and_downlink()
	_test_antenna_network()
	_test_end_and_archive()
	_test_decisions()
	_test_determinism()
	_test_save_load()
	_test_encyclopedia()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _state(p_seed := 11, antenna := 0) -> TycoonState:
	var s := TycoonState.new_campaign(p_seed)
	s.cash = 1.0e7
	if antenna > 0:
		s.buildings["antenna"] = {"kind": "antenna", "level": antenna, "target": antenna, "weeks_left": 0}
	return s


func _mission(s: TycoonState, id: String, type: String, target: String) -> Dictionary:
	var m := {"id": id, "code": id.to_upper(), "type": type, "target": target, "start_week": s.weeks,
		"weeks_total": 0, "data_stored": 0.0, "data_down": 0.0, "science": 0.0, "status": "cruise"}
	s.active_missions.append(m)
	return m


## Runs a mission to its end with no decisions taken by hand (defaults after the timeout);
## returns its archive entry.
func _run(s: TycoonState, id: String) -> Dictionary:
	for i in 80:
		if MissionOps.find(s, id).is_empty():
			break
		s.advance_week()
	for a in s.mission_archive:
		if a["id"] == id:
			return a
	return {}


func _test_buffer_and_downlink() -> void:
	var s := _state(3, 1)
	var m := _mission(s, "orb1", "orbiter", "lunar_orbit")
	s.advance_week()
	_check(m["status"] == "cruise" and float(m["data_gen"]) == 0.0, "lunar orbiter cruises first, no data yet")
	var rate := MissionOps.downlink_rate(s, m)
	var cap := float(m["storage"])
	var ok_flow := true
	var ok_cap := true
	var ok_rate := true
	var rp0 := s.research_points
	for i in 6:
		var down0 := float(m["data_down"])
		var gen0 := float(m["data_gen"])
		var lost0 := float(m["data_lost"])
		var st0 := float(m["data_stored"])
		s.advance_week()
		if m["status"] != "ops":
			continue
		var g := float(m["data_gen"]) - gen0
		var dn := float(m["data_down"]) - down0
		var ls := float(m["data_lost"]) - lost0
		# conservation: what was generated is either stored, downlinked or lost
		ok_flow = ok_flow and absf(st0 + g - (float(m["data_stored"]) + dn + ls)) < 1e-6
		ok_cap = ok_cap and float(m["data_stored"]) <= cap * float(m["buffer_mult"]) + 1e-6
		ok_rate = ok_rate and dn <= rate + 1e-6
	_check(ok_flow, "data flow: generated = stored + downlinked + lost, every week")
	_check(ok_cap, "stored data never exceeds the buffer (%.0f Gb)" % cap)
	_check(ok_rate, "weekly downlink never exceeds the network rate (%.2f Gb/week)" % rate)
	_check(float(m["data_lost"]) > 0.0, "a lunar orbiter on a 1-station network overflows its buffer (%.1f Gb lost)" % m["data_lost"])
	var expected_sci := float(m["data_down"]) * float(m["value"]) * float(m["value_mult"]) * MissionOps.scientist_bonus(s)
	_check(absf(float(m["science"]) - expected_sci) < 1e-3 or m["event"] == "storage",
		"science credited only for downlinked data (%.2f)" % m["science"])
	_check(absf((s.research_points - rp0) - float(m["science"]) * 0.5) < 1e-3,
		"research points += science * 0.5 (%.2f)" % (s.research_points - rp0))


func _test_antenna_network() -> void:
	var down: Array[float] = []
	var sci: Array[float] = []
	for lv in 4:
		var s := _state(5, lv)
		var m := _mission(s, "o", "orbiter", "lunar_orbit")
		m["event"] = ""  # same mission on every network: no decision
		MissionOps.init_mission(s, m)
		m["event"] = ""
		var a := _run(s, "o")
		down.append(float(a.get("data_down", 0.0)))
		sci.append(float(a.get("science", 0.0)))
	_check(down[0] < down[1] and down[1] < down[2] and down[2] < down[3],
		"better antenna network -> more data downlinked from the Moon (%s)" % str(down))
	_check(sci[0] < sci[1] and sci[1] < sci[2] and sci[2] < sci[3], "... and more science (%s)" % str(sci))
	var s2 := _state(5, 1)
	var leo := _mission(s2, "l", "demo_sat", "leo")
	var moon := _mission(s2, "m", "orbiter", "lunar_orbit")
	MissionOps.init_mission(s2, leo)
	MissionOps.init_mission(s2, moon)
	_check(MissionOps.downlink_rate(s2, leo) > MissionOps.downlink_rate(s2, moon) * 3.0,
		"distance matters: LEO downlink far above lunar on the same network")


func _test_end_and_archive() -> void:
	var s := _state(9, 2)
	var got: Array[Dictionary] = []
	s.mission_completed.connect(func(r: Dictionary) -> void: got.append(r))
	var m := _mission(s, "dem1", "demo_sat", "leo")
	m["grade"] = 7.5
	m["contract_id"] = "c1"
	var a := _run(s, "dem1")
	_check(not a.is_empty() and s.active_missions.is_empty(), "finished mission leaves active_missions for the archive")
	_check(got.size() == 1 and got[0]["code"] == "DEM1" and got[0].has("science") and got[0]["contract_id"] == "c1",
		"mission_completed emitted once with code, science and contract")
	_check(a.get("status", "") in ["done", "lost"] and int(a["end_week"]) > int(a["start_week"]),
		"archive entry has status and dates (%s, weeks %d..%d)" % [a.get("status"), a.get("start_week"), a.get("end_week")])
	_check(is_equal_approx(float(a["grade"]), 7.5), "archive keeps the launch grade")
	_check(String(a["lesson"]["key"]).begins_with("TY_OPS_LIM_"), "archive explains the limiting factor (%s)" % a["lesson"]["key"])
	# a failed launch is lost at once
	var f := _mission(s, "bad", "demo_sat", "leo")
	f["outcome"] = "fail"
	f["success"] = false
	s.advance_week()
	_check(MissionOps.find(s, "bad").is_empty() and s.mission_archive[-1]["status"] == "lost",
		"a failed launch goes straight to the archive as lost")
	# sample return credits its samples at the end
	var s3 := _state(4, 3)
	var smp := _mission(s3, "smp", "sample_return", "lunar_surface")
	MissionOps.init_mission(s3, smp)
	smp["event"] = ""
	var b := _run(s3, "smp")
	_check(b["status"] == "done" and float(b["science"]) > float(b["data_down"]) * float(smp["value"]),
		"sample return: samples credited when the mission comes home")


func _test_decisions() -> void:
	var s := _state(21, 1)
	var m := _mission(s, "t1", "telescope", "geo")
	MissionOps.init_mission(s, m)
	m["event"] = "storage"
	m["decision_week"] = int(m["cruise_weeks"]) + 3
	var opened := false
	for i in 8:
		s.advance_week()
		if not (m["decision"] as Dictionary).is_empty():
			opened = true
			break
	_check(opened and MissionOps.pending_decisions(s).size() == 1, "decision opens on its week")
	var choices: Array = MissionOps.event_def("storage")["choices"]
	_check(choices.size() >= 2 and choices.size() <= 3, "event has 2-3 choices")
	var cap0 := float(m["buffer_mult"])
	_check(MissionOps.decide(s, "t1", 0), "player decides")
	_check(float(m["buffer_mult"]) > cap0 and (m["decision"] as Dictionary).is_empty() and int(m["choice"]) == 0,
		"choice A (compress) grows the buffer")
	_check(not MissionOps.decide(s, "t1", 1), "a decision is taken only once")
	# unanswered decisions fall back to the default after the timeout
	var m2 := _mission(s, "t2", "telescope", "geo")
	MissionOps.init_mission(s, m2)
	m2["event"] = "wheel"
	m2["decision_week"] = int(m2["age"]) + 1
	for i in 6:
		s.advance_week()
	_check(int(m2["choice"]) == MissionOps.default_choice("wheel"), "unanswered decision resolves to its default")
	# risky choices can lose the mission (deterministic with the seed)
	var lost := 0
	for k in 40:
		var s4 := _state(100 + k, 1)
		var r := _mission(s4, "r", "telescope", "geo")
		MissionOps.init_mission(s4, r)
		r["event"] = "wheel"
		r["decision"] = {"event": "wheel", "since": 0}
		MissionOps.decide(s4, "r", 1)
		if MissionOps.find(s4, "r").is_empty():
			lost += 1
	_check(lost > 0 and lost < 40, "risky choice (25%%) loses some missions (%d of 40)" % lost)


func _campaign(p_seed: int) -> TycoonState:
	var s := _state(p_seed, 1)
	_mission(s, "a", "demo_sat", "leo")
	_mission(s, "b", "comms", "geo")
	_mission(s, "c", "orbiter", "lunar_orbit")
	_mission(s, "d", "lander", "lunar_pole")
	for i in 40:
		s.advance_week()
	return s


func _test_determinism() -> void:
	var a := _campaign(77)
	var b := _campaign(77)
	_check(JSON.stringify(a.mission_archive) == JSON.stringify(b.mission_archive)
		and is_equal_approx(a.research_points, b.research_points) and a.rng.randi() == b.rng.randi(),
		"same seed and commands -> same missions, science and rng (%.2f RP)" % a.research_points)
	_check(a.mission_archive.size() == 4, "all four missions ended within 40 weeks")


func _test_save_load() -> void:
	var s := _state(13, 2)
	_mission(s, "x", "earth_obs", "sso")
	_mission(s, "y", "rover", "lunar_surface")
	for i in 6:
		s.advance_week()
	var s2 := TycoonState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	for i in 30:
		s.advance_week()
		s2.advance_week()
	_check(JSON.stringify(s.mission_archive) == JSON.stringify(s2.mission_archive),
		"save / load mid-mission continues identically")


func _test_encyclopedia() -> void:
	var s := _state(1, 0)
	var cards := MissionOps.encyclopedia(s)
	var all_sourced := true
	for c in cards:
		all_sourced = all_sourced and String(c["url"]).begins_with("https://") and c["verified"]
	_check(cards.size() >= 12 and all_sourced, "%d encyclopedia cards, all with a checked source" % cards.size())
	var unlocked := cards.filter(func(c: Dictionary) -> bool: return c["unlocked"])
	_check(unlocked.is_empty(), "nothing unlocked before the first mission")
	_mission(s, "z", "orbiter", "lunar_orbit")
	unlocked = MissionOps.encyclopedia(s).filter(func(c: Dictionary) -> bool: return c["unlocked"])
	_check(unlocked.size() == 1 and unlocked[0]["id"] == "lro", "an orbiter unlocks the LRO card")


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
