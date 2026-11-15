extends SceneTree
## Guards of the campus render-cost work (headless):
##   * a wide CampusScatter is drawn in chunks at run time: same instances, the graphics level's
##     foliage share passed on exactly (the first N instances), the scatter itself draws nothing
##   * the campus sky animates on the cw_sky_time global, not TIME (a TIME sky re-renders its
##     radiance cubemap every frame)
##   * the ink outline blends its ink without a screen texture (no full-screen copy)
##   * the photo studio's 3D world stays switched off while no photo is being taken
## Run: godot --headless --path . --script res://tests/test_render_cost.gd

var _fails := 0


func _initialize() -> void:
	var saved := GraphicsQuality.current()
	GraphicsQuality.watch()
	await _chunks()
	_shaders()
	await _photo_studio()
	GraphicsQuality.set_level(saved)
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _chunks() -> void:
	print("scatter chunks")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sc := CampusScatter.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 300
	# through the buffer (12 floats of transform + 4 of colour each): headless, the instance
	# setters are no-ops, the buffer is kept
	var buf := PackedFloat32Array()
	for i in mm.instance_count:
		buf.append_array([1, 0, 0, rng.randf_range(-100, 100), 0, 1, 0, 0, 0, 0, 1, rng.randf_range(-70, 70), rng.randf(), 1, 1, 1])
	mm.buffer = buf
	sc.multimesh = mm
	var placed_before := sc.placed()
	GraphicsQuality.set_level(GraphicsQuality.Level.MEDIUM)
	root.add_child(sc)
	await process_frame
	_check(sc.is_chunked(), "a scatter 200 m wide is drawn in chunks")
	var chunks := sc.get_children(true).filter(func(c: Node) -> bool: return c is MultiMeshInstance3D)
	_check(chunks.size() > 1, "%d chunks" % chunks.size())
	_check(sc.layers == 0 and sc.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the scatter itself draws nothing")
	_check(sc.placed() == placed_before and sc.multimesh.instance_count == 300, "the scatter keeps its MultiMesh (walk grid, placed())")
	var total := 0
	var shown := 0
	for c: MultiMeshInstance3D in chunks:
		total += c.multimesh.instance_count
		shown += c.multimesh.instance_count if c.multimesh.visible_instance_count < 0 else c.multimesh.visible_instance_count
	_check(total == 300, "the chunks hold every instance (%d)" % total)
	_check(sc.multimesh.visible_instance_count == 210 and shown == 210, "Médio: 70 %% shown in the chunks too (%d)" % shown)
	# exactly the first 210 instances: every shown chunk instance is one of them
	var first := {}
	for i in 210:
		first[placed_before[i].origin] = true
	var same := true
	for c: MultiMeshInstance3D in chunks:
		var n := c.multimesh.visible_instance_count
		var cs := CampusScatter.new()
		cs.multimesh = c.multimesh
		var xf := cs.placed()
		cs.free()
		for j in (xf.size() if n < 0 else n):
			same = same and first.has(xf[j].origin)
	_check(same, "the chunks show the same instances as the whole scatter would")
	GraphicsQuality.set_level(GraphicsQuality.Level.HIGH)
	var all_shown := chunks.all(func(c: MultiMeshInstance3D) -> bool: return c.multimesh.visible_instance_count == -1)
	_check(all_shown, "Alto: every instance in every chunk")
	sc.queue_free()
	await process_frame
	var narrow := CampusScatter.new()
	var nm := MultiMesh.new()
	nm.transform_format = MultiMesh.TRANSFORM_3D
	nm.mesh = BoxMesh.new()
	nm.instance_count = 20
	narrow.multimesh = nm
	root.add_child(narrow)
	await process_frame
	_check(not narrow.is_chunked() and narrow.layers != 0, "a small scatter stays whole")
	narrow.queue_free()
	await process_frame


func _shaders() -> void:
	print("shaders")
	var sky := FileAccess.get_file_as_string("res://shaders/campus_sky.gdshader")
	var code := ""
	for line in sky.split("\n"):
		code += line.get_slice("//", 0) + "\n"
	_check(not RegEx.create_from_string("\\bTIME\\b").search(code), "the campus sky does not read TIME")
	_check(code.contains("cw_sky_time"), "the campus sky animates on cw_sky_time")
	_check(ProjectSettings.has_setting("shader_globals/cw_sky_time"), "cw_sky_time is a project shader global")
	var outline := FileAccess.get_file_as_string("res://shaders/cw_outline.gdshader")
	_check(not outline.contains("hint_screen_texture"), "the outline reads no screen texture")
	_check(outline.contains("blend_premul_alpha"), "the outline blends its ink premultiplied")


func _photo_studio() -> void:
	print("photo studio")
	var ps := (load("res://scenes/tycoon/photos/photo_studio.tscn") as PackedScene).instantiate() as MissionPhotoStudio
	root.add_child(ps)
	await process_frame
	_check(ps.world.render_target_update_mode == SubViewport.UPDATE_DISABLED, "the studio's 3D world is off while idle")
	_check(ps.frame.render_target_update_mode == SubViewport.UPDATE_DISABLED, "the studio's print is off while idle")
	ps.queue_free()
	await process_frame
