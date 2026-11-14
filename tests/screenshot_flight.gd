extends SceneTree
## Visual test of the flight scene with the Garça example: flies the auto-ascent (with
## extra physics warp between the shots) and saves screenshots of the pad, liftoff with
## plumes, Max-Q, booster separation, the upper stage in space with the Earth's limb, the
## map view and the flight report; then a second, deliberately bad flight for the crash.
## Prints the average FPS at the pad and in space.
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
	# the first-flight tips may show, but a scripted run never marks them as seen
	FlightTips.persist = false
	if only == "" or only == "ascent":
		await _ascent()
	if only == "" or only == "crash":
		await _crash()
	await _camera_ground_check()
	print("camera above ground in every shot: %s (min %.1f m)" % [_min_clearance > 0.0, _min_clearance])
	print("SCREENSHOTS DONE")
	quit()


func _start() -> void:
	if world and is_instance_valid(world):
		world.queue_free()
		await process_frame
	FlightSession.set_vessel(load("res://scenes/examples/garca.tscn"), ExampleVessels.display_name("garca"), 0.0)
	world = (load(FlightSession.FLIGHT_SCENE) as PackedScene).instantiate()
	get_root().add_child(world)
	await _frames(30)


func _ascent() -> void:
	await _start()
	world.cam.set_view(2.6, 0.04, 72.0, true)
	await _frames(20)
	print("fps pad: %.1f" % await _fps(90))
	await _shot("flight_01_pad")
	world.set_autopilot(true)
	await _frames(2)
	world.cam.set_view(2.45, 0.0, 85.0, true)
	await _until(func() -> bool: return world.mission_time() > 3.2, 20.0)
	await _shot("flight_02_liftoff")
	world.cam.set_view(2.2, -0.06, 120.0)
	await _until(func() -> bool: return world.mission_time() > 9.0, 30.0)
	await _shot("flight_02b_climb")
	print("   smoke puffs: %d" % world.smoke.multimesh.visible_instance_count)
	world.debug_warp = 6.0
	await _until(func() -> bool: return world._maxq_announced, 120.0)
	world.debug_warp = 1.0
	world.cam.set_view(-2.4, 0.15, 80.0, true)
	await _frames(40)
	await _shot("flight_03_maxq")
	world.debug_warp = 4.0
	await _until(func() -> bool: return _has_event("EV_BOOSTER_SEP"), 120.0)
	world.debug_warp = 1.0
	world.cam.set_view(-2.0, 0.3, 80.0, true)
	await _until(func() -> bool: return world.time - _event_time("EV_BOOSTER_SEP") > 1.3, 10.0)
	await _shot("flight_04_booster_sep")
	world.debug_warp = 12.0
	await _until(func() -> bool: return _has_event("EV_STAGE_SEP"), 200.0)
	world.debug_warp = 1.0
	world.cam.set_view(-2.2, 0.25, 45.0, true)
	await _until(func() -> bool: return world.time - _event_time("EV_STAGE_SEP") > 2.5, 10.0)
	await _shot("flight_05_stage_sep")
	world.debug_warp = 16.0
	await _until(func() -> bool: return world.active.body.altitude() > 158000.0 or world._orbit_announced, 300.0)
	world.debug_warp = 1.0
	world.cam.set_view(-2.5, 0.24, 36.0, true)
	await _frames(40)
	print("fps space: %.1f" % await _fps(90))
	await _shot("flight_06_space_limb")
	world.cam.set_view(0.2, 0.55, 30.0, true)
	await _frames(30)
	await _shot("flight_06b_space_down")
	world.set_map(true)
	await _frames(40)
	await _shot("flight_07_map")
	world.set_map(false)
	world.debug_warp = 20.0
	await _until(func() -> bool: return world.ended or world._orbit_announced, 600.0)
	world.debug_warp = 1.0
	await _until(func() -> bool: return world.ended, 15.0)
	await _frames(20)
	await _shot("flight_08_report")
	print("report: %s" % str(world.stats))


func _crash() -> void:
	await _start()
	world.stage()
	world.active.set_sas(FlightVessel.Sas.OFF)
	world.cam.set_view(2.4, 0.1, 75.0, true)
	await _until(func() -> bool: return world.mission_time() > 8.0, 30.0)
	# hard pitch over at low altitude: the aerodynamic loads tear it apart
	world.debug_warp = 2.0
	world.scripted_input = Vector3(-1, 0, 0.3)
	await _until(func() -> bool: return world.active.crashed or world.mission_time() > 90.0, 90.0)
	world.scripted_input = Vector3.ZERO
	world.debug_warp = 1.0
	await _frames(25)
	await _shot("flight_09_breakup")
	await _until(func() -> bool: return world.ended, 10.0)
	await _frames(20)
	await _shot("flight_10_crash_report")
	print("crash: %s  reason %s" % [world.active.crashed, world.active.crash_reason])


## Tries to drive the camera under the pad (low pitch, zoom in/out) and checks it stays up.
func _camera_ground_check() -> void:
	await _start()
	var worst := INF
	for d in [12.0, 40.0, 150.0, 600.0]:
		world.cam.set_view(1.0, -1.4, d, true)
		for i in 20:
			await process_frame
			worst = minf(worst, world.camera_clearance())
	_min_clearance = minf(_min_clearance, worst)
	await _shot("flight_00_camera_low")
	print("camera ground check (pitch -80°, pad): min clearance %.1f m -> %s" % [worst, "OK" if worst > 0.0 else "BELOW GROUND"])


func _has_event(key: String) -> bool:
	for e in world.events:
		if e["key"] == key:
			return true
	return false


func _event_time(key: String) -> float:
	for e in world.events:
		if e["key"] == key:
			return float(e["t"]) + world.liftoff_time
	return world.time


func _until(cond: Callable, timeout_s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _fps(n: int) -> float:
	var vp := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var t0 := Time.get_ticks_usec()
	var gpu := 0.0
	var cpu := 0.0
	for i in n:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("   gpu %.1f ms/frame, process %.1f ms/frame" % [gpu / n, cpu / n])
	return n / ((Time.get_ticks_usec() - t0) / 1.0e6)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	var clear := world.camera_clearance()
	_min_clearance = minf(_min_clearance, clear)
	print("saved %s  (alt %.1f km, T+%.0f s, camera %.1f m above ground)" % [path, world.active.body.altitude() / 1000.0,
		world.mission_time(), clear])
