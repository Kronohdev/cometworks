extends SceneTree
## One continuous career launch (CareerFlight, TycoonModes, LaunchSequence's handoff):
##   1. liftoff: start_launch flies the project's rocket from the campus pad at the track's time
##   2. the 3D view: open_launch_flight shows that same run, the live campus lent as the island
##      under the pad, the camera starting on the campus shot; leaving gives the campus back
##   3. leaving anytime: the run goes on with the calendar in the background; at orbit the track
##      takes the flight's own state (rebase) and the map's path is the flight's path
##   4. re-entering: the map's "Acompanhar" opens the same run while it flies
##   5. the career outcome decides: a failure breaks up at the track's second with its cause,
##      a partial orbit is lower, a lunar orbiter burns for the Moon and arrives on its track,
##      a lander's landing is known (status "arrived")
##   6. determinism: the same launch flown twice ends in the same state
##   7. LaunchVessels: a designer rocket becomes a hangar vessel with its stages and boosters
## Run: godot --headless --path . --script res://tests/test_launch_flight.gd

var _failures := 0
var main: TycoonMain


func _initialize() -> void:
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(5)
	main.race_flow.autosave = false
	main.clock.set_speed(0)
	main.state.weeks = 30
	_check(load("res://src/tycoon/tracking/career_flight.gd") != null, "CareerFlight script loaded")
	await _test_live()
	_test_outcomes()
	_test_determinism()
	_test_vessels()
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _result(pid: String, code: String, type_id: String, target: String, outcome: String) -> Dictionary:
	var e := {"id": pid, "project_id": pid, "code": code, "type": type_id, "target": target, "outcome": outcome,
		"success": outcome != "fail", "week": main.state.weeks, "grade": 6.0, "grade_project": 6.0,
		"bars": [5.0, 5.0, 5.0, 5.0], "reviews": [], "rewards": {}, "rocket": {}, "pad": "pad",
		"cause_key": "TY_RK_CAUSE_STAGE1" if outcome == "fail" else ""}
	main.state.project_history.append(e)
	SpaceTracking.sync(main.state)
	return e


# ------------------------------------------------------------ 1-4
func _test_live() -> void:
	print("live launch: liftoff, the 3D view, leaving and coming back")
	var modes := main.modes
	var r := _result("L1", "LUA-07", "orbiter", "lunar_orbit", "full")
	var run := modes.start_launch(r)
	_check(run != null and run.track_id == "p:L1", "the launch has its career flight")
	if run == null:
		return
	var tr := SpaceTracking.find(main.state, "p:L1")
	_check(is_equal_approx(run.sim.t, float(tr["launch_t"])), "it starts at the track's launch time")
	modes.launch_hold += 1
	for i in 150:
		run.advance(0.02)
	modes.launch_hold -= 1
	var keys := run.log.map(func(e: Array) -> String: return String(e[0]))
	_check(run.sim.launched and keys.has("EV_LIFTOFF"), "it lifts off from the pad (%s)" % ", ".join(keys))
	var h0 := run.sim.altitude()
	# the handoff
	_check(modes.open_launch_flight(Vector3(14.0, 6.0, 9.0)), "the 3D view opens on it")
	await _frames(4)
	var fw := modes.mode_node as FlightWorld
	_check(fw != null and fw.run == run and fw.spectator, "...showing the same run")
	if fw == null:
		return
	_check(main.campus.get_parent() != main and fw.island != null and fw.island.lent, "the live campus is the island under the pad")
	_check(fw.shot == "climb", "the camera carries on from the campus shot (%s)" % fw.shot)
	_check(modes.overlay is LaunchWatch and (modes.overlay as LaunchWatch).mode == "live", "the live watch card")
	await _frames(30)
	_check(run.sim.altitude() > h0, "it keeps climbing in the view (%.0f m)" % run.sim.altitude())
	fw.revert_to_hangar()
	await _frames(4)
	_check(not modes.is_open(), "Voltar ao campus leaves the view")
	_check(main.campus.get_parent() == main and main.campus.visible, "the campus is back home")
	_check(modes.launch_run == run, "the flight goes on without the view")
	# re-entering while it flies
	_check(modes.open_follow("p:L1"), "the map's Acompanhar opens the live flight")
	await _frames(4)
	fw = modes.mode_node as FlightWorld
	_check(fw != null and fw.run == run, "...the very same run")
	if fw:
		fw.revert_to_hangar()
	await _frames(4)
	if modes.kind == "map":
		modes.close_mode()
		await _frames(3)
	# the background: the calendar flies it to orbit and on
	var t_orbit := float(tr["launch_t"]) + 3600.0
	run.advance_to(t_orbit, 20000.0)
	_check(run.sim.in_orbit and tr.has("ins_t"), "in orbit, the track rebased on the flight (status %s)" % run.status())
	var st := SpaceTracking.state_at(tr, run.sim.t)
	var d := Vector3(st["pos"][0] - run.sim.px, st["pos"][1] - run.sim.py, st["pos"][2] - run.sim.pz).length()
	_check(int(st["body"]) == run.sim.body and d < 1000.0, "the map's place is the flight's place (%.1f m)" % d)
	var legs: Array = tr["legs"]
	var t_dep := float(legs[1]["t0"]) if legs.size() > 1 else INF
	run.advance_to(t_dep + 3600.0, 60000.0)
	_check(run.phase == "transfer", "the departure burn sends it to the Moon (%s)" % run.phase)
	st = SpaceTracking.state_at(tr, run.sim.t)
	d = Vector3(st["pos"][0] - run.sim.px, st["pos"][1] - run.sim.py, st["pos"][2] - run.sim.pz).length()
	_check(d < 1000.0, "after the burn it rides the track's transfer (%.1f m)" % d)
	run.advance_to(float(legs[-1]["t0"]) + 7200.0, 20000.0)
	_check(run.sim.body == FlightSolar.get_system().moon and run.status() == "orbit", "it arrives in lunar orbit (%s)" % run.status())
	_check(run.settled(), "then it just rides its track")


# ------------------------------------------------------------ 5
func _fly(r: Dictionary, seconds: float) -> CareerFlight:
	var tr := SpaceTracking.find(main.state, "p:" + String(r["id"]))
	var ps := TycoonModes.watch_vessel(main.state, {}, String(r["target"]))
	var run := CareerFlight.for_track(main.state, tr, ps, 0.0, "", String(r.get("cause_key", "")))
	run.advance_to(float(tr["launch_t"]) + seconds, 60000.0)
	return run


func _test_outcomes() -> void:
	print("the career outcome decides the flight")
	var rf := _result("F1", "ORB-09", "demo_sat", "leo", "fail")
	var trf := SpaceTracking.find(main.state, "p:F1")
	var fail_at := float(trf["lost_t"]) - float(trf["launch_t"])
	var run := _fly(rf, fail_at + 30.0)
	var crash := -1.0
	for e: Array in run.log:
		if e[0] == "EV_CRASH":
			crash = float(e[2])
	_check(run.sim.crashed and absf(crash - fail_at) < 0.05, "a failure breaks up at the track's second (%.2f / %.2f s)" % [crash, fail_at])
	_check(run.sim.crash_reason == "TY_TRK_CRASH_ENGINE" or run.sim.crash_reason == "TY_TRK_CRASH_STAGE"
		or run.sim.crash_reason == "CRASH_Q", "...naming what broke (%s)" % run.sim.crash_reason)
	_check(run.status() == "lost", "...and is lost")
	var rp := _result("P1", "ORB-10", "demo_sat", "leo", "partial")
	var runp := _fly(rp, 4000.0)
	var rs := _result("S1", "ORB-11", "demo_sat", "leo", "full")
	var runs := _fly(rs, 4000.0)
	var pe_p := float(runp.sim.elements()["pe_alt"])
	var pe_s := float(runs.sim.elements()["pe_alt"])
	_check(runp.sim.in_orbit and runs.sim.in_orbit and pe_p < pe_s, "a partial orbit is lower (%.0f km vs %.0f km)" % [
		pe_p / 1000.0, pe_s / 1000.0])
	var rl := _result("M1", "LUN-03", "lander", "lunar_surface", "full")
	var trl := SpaceTracking.find(main.state, "p:M1")
	var runl := _fly(rl, 3600.0)
	var legs: Array = trl["legs"]
	runl.advance_to(float(legs[-1]["t0"]) + 3600.0, 60000.0)
	_check(runl.status() == "arrived" and runl.result == "arrived", "a lander's landing is known: arrived (%s)" % runl.status())
	var rh := _result("H1", "SND-04", "sounding", "suborbital", "full")
	var runh := _fly(rh, 1200.0)
	_check(runh.result == "arrived" or runh.result == "landed", "a sounding rocket goes up and splashes down (%s, %.0f km)" % [
		runh.result, float(runh.sim.stats["max_alt"]) / 1000.0])


# ------------------------------------------------------------ 6
func _test_determinism() -> void:
	print("determinism")
	var r := _result("D1", "ORB-12", "demo_sat", "leo", "full")
	var a := _fly(r, 900.0)
	var b := _fly(r, 900.0)
	_check(a.sim.px == b.sim.px and a.sim.vz == b.sim.vz and a.sim.craft.mass() == b.sim.craft.mass(),
		"the same launch flown twice ends in the same state")


# ------------------------------------------------------------ 7
func _test_vessels() -> void:
	print("designer rockets as hangar vessels")
	var parts := {"core": "core_harpia", "upper": "upper_falcao_v", "boosters": "boost_srb4", "fairing": "fairing_m"}
	var ps := LaunchVessels.for_design(parts, "leo")
	_check(ps != null, "a designer rocket gets a hangar vessel")
	if ps == null:
		return
	var c := FlightCraft.from_scene(ps, 1000.0)
	var boosters := c.groups.filter(func(g: Dictionary) -> bool: return g["kind"] == "booster").size()
	_check(c.stage_count == 2 and boosters == 4, "two stages and four boosters (%d, %d)" % [c.stage_count, boosters])
	_check(not c.fairings.is_empty(), "...under a fairing")
	_check(LaunchVessels.for_design(parts, "leo") == ps, "cached per design")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
