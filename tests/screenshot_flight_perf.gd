extends SceneTree
## GPU / CPU timing of the flight scene (windowed, same views every run) for the
## performance pass: the pad (default camera), a low camera looking along the coast, low
## orbit looking at the limb, low orbit looking down, and the map view at three scales.
## Optional variants switch single features off to see what they cost.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_flight_perf.gd -- <out_dir> [variant ...]
##   variants: noglow nossao noshadow nosite novessel nohud empty nosky freeze_sky scale50
##             mapnomsaa mapnoglow mapscale lowq highq

var out_dir := "user://"
var variants: PackedStringArray = []
var world: FlightWorld
var results := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	for i in range(1, args.size()):
		variants.append(args[i])
	DirAccess.make_dir_recursive_absolute(out_dir)
	if "lowq" in variants:
		GraphicsQuality.level = GraphicsQuality.Level.LOW
	elif "highq" in variants:
		GraphicsQuality.level = GraphicsQuality.Level.HIGH
	else:
		GraphicsQuality.level = GraphicsQuality.Level.MEDIUM
	FlightSession.set_vessel(load("res://scenes/examples/garca.tscn"), ExampleVessels.display_name("garca"), 0.0)
	world = (load(FlightSession.FLIGHT_SCENE) as PackedScene).instantiate()
	get_root().add_child(world)
	await _frames(30)
	_apply_variants()
	print("variants: %s  quality %s  adapter %s" % [str(variants), GraphicsQuality.NAMES[GraphicsQuality.current()],
		RenderingServer.get_video_adapter_name()])
	world.cam.set_view(2.6, 0.04, 72.0, true)
	await _measure("pad")
	world.cam.set_view(0.9, 0.02, 160.0, true)
	await _measure("pad_coast")
	# low orbit, 200 km circular (state set directly: the timing is about rendering)
	world.launched = true
	world.liftoff_time = 0.0
	world.active.clamped = false
	world.active.landed = false
	var r := FlightOrbit.R + 200000.0
	var up := Vector3.UP
	var east := FlightWorld.EAST.normalized()
	var v := sqrt(FlightOrbit.MU / r)
	world.active.body.set_state(FlightOrbit.vec(0, r, 0), FlightOrbit.vec(east.x * v, 0.0, east.z * v))
	world.active.body.q = Quaternion(Vector3.UP, east)
	world.active.prev.copy_from(world.active.body)
	world.active.throttle = 0.0
	world.active.set_sas(FlightVessel.Sas.HOLD)
	await _frames(20)
	world.cam.set_view(-2.5, 0.24, 36.0, true)
	await _measure("orbit_limb")
	world.cam.set_view(0.2, 0.55, 30.0, true)
	await _measure("orbit_down")
	world.set_map(true)
	var mvp := world.map.get_node("%MapViewport") as SubViewport
	var menv: Environment = (world.map.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	if "mapnomsaa" in variants:
		mvp.msaa_3d = Viewport.MSAA_DISABLED
	if "mapnoglow" in variants:
		menv.glow_enabled = false
	if "mapscale" in variants:
		mvp.scaling_3d_scale = 0.77
	await _frames(10)
	await _measure("map")
	if world.map.has_method("set_scale_mode"):
		world.map.call("set_scale_mode", 1)
		await _frames(40)
		await _measure("map_system")
		world.map.call("set_scale_mode", 2)
		await _frames(40)
		await _measure("map_solar")
	world.set_map(false)
	var line := ""
	for k in results:
		line += "%s %.2f ms  " % [k, results[k]]
	print("SUMMARY gpu: " + line)
	print("PERF DONE")
	quit()


func _apply_variants() -> void:
	var env: Environment = world.sky.environment
	if "noglow" in variants:
		env.glow_enabled = false
	if "nossao" in variants:
		env.ssao_enabled = false
	if "noshadow" in variants:
		world.sun.shadow_enabled = false
	if "nosite" in variants:
		for c in world.site.get_children():
			if c is Node3D:
				(c as Node3D).visible = false
	if "novessel" in variants:
		world.vessels.visible = false
	if "nohud" in variants:
		world.hud.get_node("Root").visible = false
	if "empty" in variants:
		world.hud.get_node("Root").visible = false
		world.vessels.visible = false
		env.background_mode = Environment.BG_COLOR
		for c in world.site.get_children():
			if c is Node3D:
				(c as Node3D).visible = false
	if "scale50" in variants:
		get_root().scaling_3d_scale = 0.5
	if "nosky" in variants:
		env.background_mode = Environment.BG_COLOR
	if "freeze_sky" in variants:
		world.sky.set_meta("frozen", true)


func _measure(tag: String) -> void:
	await _frames(30)
	var vp := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var n := 120
	var gpu := 0.0
	var cpu := 0.0
	var proc := 0.0
	var t0 := Time.get_ticks_usec()
	var map_vp := RID()
	if world.map_view:
		map_vp = world.map.get_node("%MapViewport").get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(map_vp, true)
	for i in n:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		if map_vp.is_valid():
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(map_vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var fps := n / ((Time.get_ticks_usec() - t0) / 1.0e6)
	var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var prim := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var obj := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	results[tag] = gpu / n
	print("%-11s gpu %6.2f ms  render-cpu %5.2f ms  process %5.2f ms  fps %5.1f  draws %4d  prims %7d  objects %4d" % [
		tag, gpu / n, cpu / n, proc / n, fps, dc, prim, obj])
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out_dir.path_join("perf_%s.png" % tag))


func _frames(k: int) -> void:
	for i in k:
		await process_frame
