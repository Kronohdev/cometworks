extends SceneTree
## Visual test of the flight view (the hangar's test flight with Garça, the autopilot flying
## and the camera director choosing the shots): the pad on the island, liftoff from the tower
## camera, the climb with the island below, the booster and stage separations, space with the
## curve of the Earth, orbit, the map; then a break-up. Prints the FPS at the pad and in space.
## Run (windowed): godot --path . --resolution 1600x900 --script res://tests/screenshot_flight.gd -- <out_dir> [only]

var out_dir := "user://"
var only := ""
var world: FlightWorld
var _min_clearance := INF


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		only = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	FlightTips.persist = false
	if only == "" or only == "ascent":
		await _ascent()
	if only == "" or only == "crash":
		await _crash()
	print("camera above ground in every shot: %s (min %.1f m)" % [_min_clearance > 0.0, _min_clearance])
	print("SCREENSHOTS DONE")
	quit()


func _start(auto: bool) -> void:
	if world and is_instance_valid(world):
		world.queue_free()
		await process_frame
	FlightSession.clear()
	FlightSession.set_vessel(load("res://scenes/examples/garca.tscn"), ExampleVessels.display_name("garca"), 0.0)
	FlightSession.auto_ascent = auto
	world = (load(FlightSession.FLIGHT_SCENE) as PackedScene).instantiate()
	get_root().add_child(world)
	await _frames(30)


func _ascent() -> void:
	await _start(true)
	world.paused = true
	await _frames(20)
	print("fps pad: %.1f" % await _fps(60))
	await _shot("flight_01_pad")
	world.paused = false
	await _until(func() -> bool: return world.mission_time() > 2.5, 20.0)
	await _shot("flight_02_liftoff")
	await _until(func() -> bool: return world.mission_time() > 6.0, 20.0)
	await _shot("flight_03_tower")
	await _until(func() -> bool: return world.shot == "climb" and world.mission_time() > 14.0, 30.0)
	await _shot("flight_04_climb")
	world.debug_warp = 5.0
	await _until(func() -> bool: return world.sim.altitude() > 9000.0, 60.0)
	world.debug_warp = 1.0
	await _frames(40)
	await _shot("flight_05_island_below")
	world.debug_warp = 6.0
	await _until(func() -> bool: return _has_event("EV_BOOSTER_SEP"), 120.0)
	world.debug_warp = 1.0
	await _until(func() -> bool: return world.mission_time() - _event_time("EV_BOOSTER_SEP") > 1.2, 10.0)
	await _shot("flight_06_booster_sep")
	world.debug_warp = 10.0
	await _until(func() -> bool: return _has_event("EV_STAGE_SEP"), 200.0)
	world.debug_warp = 1.0
	await _until(func() -> bool: return world.mission_time() - _event_time("EV_STAGE_SEP") > 0.6, 10.0)
	await _shot("flight_07_stage_sep")
	await _until(func() -> bool: return world.mission_time() - _event_time("EV_STAGE_SEP") > 1.6, 10.0)
	await _shot("flight_07b_stage_sep")
	world.debug_warp = 12.0
	await _until(func() -> bool: return world.sim.altitude() > 130000.0, 200.0)
	world.debug_warp = 1.0
	await _frames(60)
	print("fps space: %.1f" % await _fps(60))
	await _shot("flight_08_space")
	world.change_warp(6)
	await _until(func() -> bool: return world.in_orbit() or world.ended, 120.0)
	world.warp = 1
	world.debug_warp = 1.0
	await _frames(60)
	await _shot("flight_09_orbit")
	world.set_map(true)
	await _frames(30)
	await _shot("flight_10_map")
	world.set_map(false)


func _crash() -> void:
	await _start(true)
	world.sim.fail_met = 34.0
	world.sim.fail_reason = "CRASH_AERO"
	await _until(func() -> bool: return world.sim.crashed, 60.0)
	await _frames(20)
	await _shot("flight_11_breakup")
	await _frames(120)
	await _shot("flight_12_report")


func _has_event(key: String) -> bool:
	for e: Dictionary in world._events:
		if e["key"] == key:
			return true
	return false


func _event_time(key: String) -> float:
	for e: Dictionary in world._events:
		if e["key"] == key:
			return float(e["t"])
	return 0.0


func _until(cond: Callable, timeout_s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _fps(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
	return n / ((Time.get_ticks_usec() - t0) / 1.0e6)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	var clear := world.camera_clearance()
	_min_clearance = minf(_min_clearance, clear)
	print("saved %s  (alt %.1f km, T+%.0f s, camera %.1f m above the sea, shot %s)" % [path,
		world.sim.altitude() / 1000.0, world.mission_time(), clear, world.shot])
