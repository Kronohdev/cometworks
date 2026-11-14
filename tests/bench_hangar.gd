extends SceneTree
## Hangar performance benchmark (windowed, vsync off). For each scenario prints the
## average / 1%-low frame time, FPS, draw calls, primitives and objects, then measures
## the cost of each expensive environment feature by toggling it off.
## Run: godot --path . --resolution 1600x900 --script res://tests/bench_hangar.gd

const FRAMES := 150

var hangar: Node


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	hangar = (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(30)
	await _measure("empty")
	for id in ["andorinha", "garca", "condor"]:
		hangar.load_example(id)
		await _frames(20)
		var c: HangarCamera = hangar.cam
		c.snap_to(c.target_focus, c.target_yaw, c.target_pitch, c.target_distance)
		await _frames(20)
		await _measure(id)
	# quality presets on the heaviest scene (condor)
	for l in [GraphicsQuality.Level.LOW, GraphicsQuality.Level.HIGH, GraphicsQuality.Level.MEDIUM]:
		GraphicsQuality.set_level(l)
		GraphicsQuality.apply(hangar)
		await _frames(10)
		await _measure("condor @" + GraphicsQuality.NAMES[l])
	# feature costs on the heaviest scene (condor)
	var env: Environment = (hangar.get_node("WorldEnvironment") as WorldEnvironment).environment
	for f in ["ssil_enabled", "ssao_enabled", "glow_enabled", "fog_enabled"]:
		if env.get(f):
			env.set(f, false)
			await _frames(10)
			await _measure("condor -" + f)
			env.set(f, true)
	var lights := hangar.find_children("*", "Light3D", true, false)
	var shadowed: Array = []
	for l in lights:
		if (l as Light3D).shadow_enabled:
			shadowed.append(l)
			(l as Light3D).shadow_enabled = false
	await _frames(10)
	await _measure("condor -shadows(%d lights)" % shadowed.size())
	for l in shadowed:
		(l as Light3D).shadow_enabled = true
	hangar.get_node("UI").visible = false
	await _frames(10)
	await _measure("condor -HUD")
	print("BENCH DONE")
	quit()


func _measure(label: String) -> void:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	var low := times[int(times.size() * 0.99) - 1]
	print("%-32s avg %6.2f ms (%5.1f fps)  1%%low %6.2f ms  draws %5d  prims %8d  objs %5d  process %.2f ms" % [
		label, avg, 1000.0 / avg, low,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])


func _frames(n: int) -> void:
	for i in n:
		await process_frame
