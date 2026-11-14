extends SceneTree
## Finds what costs frame time in the empty hangar: baseline (camera only), full hangar,
## then the hangar with groups hidden one at a time (outside site, interior lights,
## building structure, UI). Windowed, vsync off.
## Run: godot --path . --resolution 1600x900 --script res://tests/bench_scene_parts.gd

const FRAMES := 120


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var base := Node3D.new()
	var cam := Camera3D.new()
	base.add_child(cam)
	get_root().add_child(base)
	await _frames(20)
	await _measure("baseline (camera only)")
	base.queue_free()
	var hangar: Node = (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(30)
	await _measure("hangar empty")
	var vab := hangar.get_node("VAB")
	for child in vab.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
			await _frames(8)
			await _measure("  -" + String(child.name))
			(child as Node3D).visible = true
	var lights := hangar.find_children("*", "OmniLight3D", true, false) + hangar.find_children("*", "SpotLight3D", true, false)
	for l in lights:
		(l as Light3D).visible = false
	await _frames(8)
	await _measure("  -all omni/spot lights (%d)" % lights.size())
	for l in lights:
		(l as Light3D).visible = true
	hangar.get_node("UI").visible = false
	await _frames(8)
	await _measure("  -UI")
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
	var med := times[times.size() / 2]
	print("%-36s median %6.2f ms (%5.1f fps)  draws %5d  prims %8d  objs %5d" % [label, med, 1000.0 / med,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])


func _frames(n: int) -> void:
	for i in n:
		await process_frame
