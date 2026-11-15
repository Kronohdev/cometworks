extends SceneTree
## Windowed screenshots of one continuous career launch: the countdown and liftoff on the campus
## (LaunchSequence), the cloud punch into the 3D flight on the same shot, the climb with the
## island falling away, staging, space and orbit; then "Voltar ao campus" (the result card), the
## Solar System map with the mission still flying, and "Acompanhar" back into the same flight.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_launch_flight.gd -- <out_dir> [target] [outcome]

var out_dir := "user://"
var main: TycoonMain
var prefix := "lf"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var target := "leo"
	var outcome := "full"
	if args.size() > 1:
		target = args[1]
	if args.size() > 2:
		outcome = args[2]
	await process_frame
	var size := DisplayServer.window_get_size()
	prefix = "lf_%dx%d_%s_%s" % [size.x, size.y, target, outcome]
	DirAccess.make_dir_recursive_absolute(out_dir)
	FlightTips.persist = false
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.race_flow.autosave = false
	main.clock.set_speed(0)
	var s := main.state
	var cycle := main.get_node_or_null("DayCycle") as CampusDayCycle
	if cycle:
		cycle.force_phase = 0.12
	s.weeks = 3 * 52 + 10
	for lot: String in s.lot_ids():
		s.buildings[lot] = {"kind": s.lot_kind(lot), "level": 2, "target": 2, "weeks_left": 0}
	s.changed.emit()
	await _frames(30)
	var r := {"id": "LF1", "project_id": "LF1", "code": "ORB-21", "type": "demo_sat" if target in ["leo", "sso"] else "orbiter",
		"target": target, "grade": 7.4 if outcome != "fail" else 4.1, "success": outcome != "fail", "outcome": outcome,
		"p_success": 0.82, "week": s.weeks, "rocket": {"parts": {"core": "core_harpia", "upper": "upper_falcao_v",
		"boosters": "boost_srb2", "fairing": "fairing_m"}, "name": "Harpia"}, "pad": "pad", "grade_project": 7.0,
		"bars": [5.0, 5.0, 5.0, 5.0], "reviews": [], "rewards": {}}
	s.project_history.append(r)
	SpaceTracking.sync(s)
	main.hud.open_screen("launch", {"result": r})
	var seq := main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	await _until(func() -> bool: return seq.anim.current_animation == "countdown" and seq.anim.current_animation_position > 3.6, 30.0)
	await _shot("01_countdown")
	await _until(func() -> bool: return seq.anim.current_animation == "flight_success" and seq.anim.current_animation_position > 1.2, 30.0)
	await _shot("02_liftoff_campus")
	await _until(func() -> bool: return seq.flight_phase == "punch" or seq.flight_phase == "back", 30.0)
	await _frames(6)
	await _shot("03_punch")
	await _until(func() -> bool: return main.modes.kind == "flight", 10.0)
	var fw := main.modes.mode_node as FlightWorld
	await _frames(12)
	await _shot("04_flight_handoff")
	await _until(func() -> bool: return fw.sim.altitude() > fw.sim.pad_alt + 900.0, 40.0)
	await _shot("05_climb_island")
	fw.debug_warp = 4.0
	await _until(func() -> bool: return fw.sim.altitude() > 12000.0, 60.0)
	fw.debug_warp = 1.0
	await _frames(50)
	await _shot("06_high_climb")
	fw.debug_warp = 6.0
	await _until(func() -> bool: return _has(fw, "EV_STAGE_SEP") or fw.sim.crashed, 200.0)
	fw.debug_warp = 1.0
	await _frames(40)
	await _shot("07_staging")
	fw.debug_warp = 10.0
	await _until(func() -> bool: return fw.sim.altitude() > 120000.0 or fw.sim.crashed, 200.0)
	fw.debug_warp = 1.0
	await _frames(60)
	await _shot("08_space")
	fw.warp = 1000
	await _until(func() -> bool: return fw.in_orbit() or fw.sim.crashed, 60.0)
	fw.warp = 1
	await _frames(90)
	await _shot("09_orbit")
	var run := main.modes.launch_run
	if run and not target in ["leo", "sso", "suborbital"]:
		# the departure burn for the target, with the real engines
		fw.warp = 10000
		await _until(func() -> bool: return run.autopilot() != null and run.autopilot().phase == "burn", 60.0)
		fw.warp = 1
		await _frames(90)
		await _shot("09b_departure_burn")
		fw.warp = 100
		await _until(func() -> bool: return run.phase == "transfer", 60.0)
		fw.warp = 1
		await _frames(60)
		await _shot("09c_transfer")
	# Voltar ao campus
	(main.modes.overlay as LaunchWatch).go_back()
	await _until(func() -> bool: return not main.modes.is_open(), 10.0)
	await _frames(70)
	await _shot("10_back_campus_card")
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(1.6).timeout
	for i in 4:
		if main.hud.current_screen() != "":
			main.hud.close_screen()
			await _frames(10)
	await _frames(20)
	# a little campus time: the calendar catches up with the flight, which flies on meanwhile
	main.clock.set_speed(3)
	var trk := SpaceTracking.find(s, "p:LF1")
	await _until(func() -> bool: return SpaceTracking.status_at(trk, SpaceTracking.now(s, main.clock.week_fraction())) != "flight", 15.0)
	main.clock.set_speed(0)
	print("on the map now: %s" % SpaceTracking.status_at(trk, SpaceTracking.now(s, main.clock.week_fraction())))
	# the map: the mission flies on
	main.modes.open_space_map("p:LF1")
	await _frames(40)
	await _shot("11_map")
	var ov := main.modes.overlay as SpaceMapOverlay
	if ov:
		ov.watch_selected()
	await _frames(30)
	await _shot("12_follow_again")
	print("LAUNCH FLIGHT SCREENSHOTS DONE (run in view: %s)" % [main.modes.mode_node is FlightWorld
		and (main.modes.mode_node as FlightWorld).run == main.modes.launch_run])
	quit()


func _has(fw: FlightWorld, key: String) -> bool:
	for e: Dictionary in fw._events:
		if e["key"] == key:
			return true
	return false


func _until(cond: Callable, timeout_s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join("%s_%s.png" % [prefix, name])
	img.save_png(path)
	print("saved ", path)
