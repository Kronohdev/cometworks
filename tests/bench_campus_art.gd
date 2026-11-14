extends SceneTree
## Frame cost of the campus art layers (scenes/tycoon/tycoon_main.tscn, era 5, every lot at
## level 3, the default game camera): everything, then without Nature, Dressing and Life, then
## with the plain environment effects off (SSIL, SSAO, glow, fog), to see what each one costs.
## Run windowed: godot --path . --resolution 1600x900 --script res://tests/bench_campus_art.gd

var main: TycoonMain


func _initialize() -> void:
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(5)
	main.clock.set_speed(0)
	var cam := main.camera
	cam.set_process(false)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(4, 0, 2) - Vector3(70, 70, 95), Vector3.UP),
		Vector3(70, 70, 95))
	var s := main.state
	s.weeks = 4 * 5 * 52 + 10
	for lot: String in s.lot_ids():
		s.buildings[lot] = {"kind": s.lot_kind(lot), "level": 3, "target": 3, "weeks_left": 0}
	s.changed.emit()
	await _frames(30)
	var campus := main.campus
	await _measure("all layers")
	for layer in ["Nature", "Dressing", "Life"]:
		(campus.get_node(layer) as Node3D).visible = false
		await _measure("without %s" % layer)
		(campus.get_node(layer) as Node3D).visible = true
	for layer in ["Nature", "Dressing", "Life"]:
		(campus.get_node(layer) as Node3D).visible = false
	await _measure("no art layers")
	for layer in ["Nature", "Dressing", "Life"]:
		(campus.get_node(layer) as Node3D).visible = true
	var env := (campus.get_node("WorldEnvironment") as WorldEnvironment).environment
	env.ssil_enabled = false
	await _measure("all, SSIL off")
	env.ssao_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	await _measure("all, SSIL / SSAO / glow / fog off")
	print("BENCH DONE")
	quit()


func _measure(label: String) -> void:
	var vp := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _frames(20)
	var cpu := 0.0
	var gpu := 0.0
	var n := 120
	for i in n:
		await process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	print("%-36s render cpu %.2f ms  gpu %.2f ms  draw calls %d  primitives %d" % [label, cpu / n, gpu / n,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])


func _frames(k: int) -> void:
	for i in k:
		await process_frame
