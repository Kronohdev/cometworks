extends SceneTree
## Close-up screenshots of the campus buildings (tools/build_campus_buildings.py) on the
## Cometworks main screen, with the HUD hidden and a fixed camera of its own (the campus
## camera is paused so its easing does not move the shots):
##   bld_overview_e<era>_closed / _open   whole campus, every lot at level 3
##   bld_<lot>_e<era>                     one building close up (cutaway open)
##   bld_<lot>_e<era>_ext                 the same building from further away, roof on
## and prints the frame time / draw calls of the full campus at era 5 (vsync off).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_campus_buildings.gd -- <out_dir> [eras] [lots]
##   eras: comma list (default 1,3,5), lots: comma list (default all)

var out_dir := "user://"
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var eras := [1, 3, 5]
	if args.size() > 1:
		eras = Array(args[1].split(",")).map(func(s: String) -> int: return int(s))
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(5)
	main.clock.set_speed(0)
	var ui := main.get_node_or_null("UI") as CanvasLayer
	if ui:
		ui.visible = false
	var main_cam := main.get_node("Camera") as Camera3D
	main_cam.set_process(false)
	main_cam.set_process_input(false)
	main_cam.set_process_unhandled_input(false)
	cam = Camera3D.new()
	cam.fov = 34.0
	cam.far = 1600.0
	main.add_child(cam)
	cam.current = true
	var s: TycoonState = main.state
	s.cash = 9.0e7
	var lots: Array = s.lot_ids()
	if args.size() > 2:
		lots = Array(args[2].split(","))
	for era: int in eras:
		_set_campus(s, era, 3)
		await _frames(30)
		_place(Vector3(4, 0, 2), 38.0, 40.0, 105.0)
		_cutaway(false)
		await _frames(20)
		await _shot("bld_overview_e%d_closed" % era)
		_cutaway(true)
		_place(Vector3(4, 0, 2), 38.0, 38.0, 70.0)
		await _frames(60)
		await _shot("bld_overview_e%d_open" % era)
		for lot: String in lots:
			var b: CampusBuilding = main.campus._buildings.get(lot)
			if b == null:
				continue
			var c := b.global_position
			var yaw := 38.0 + (180.0 if absf(b.rotation.y) > 1.0 else 0.0)
			var size: Vector2 = main.campus.lots.get_node(lot).get_meta("size", Vector2(16, 12))
			var d := maxf(size.x, size.y) * 1.55 + 6.0
			_place(c, yaw, 42.0, d)
			await _frames(45)
			await _shot("bld_%s_e%d" % [lot, era])
			if era == eras[-1]:
				_cutaway(false)
				_place(c, yaw, 30.0, d * 1.25)
				await _frames(20)
				await _shot("bld_%s_e%d_ext" % [lot, era])
				_cutaway(true)
	# performance: full campus, era 5, all lots level 3, default-ish view, vsync off
	_set_campus(s, 5, 3)
	_place(Vector3(4, 0, 2), 38.0, 40.0, 100.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for open: bool in [false, true]:
		_cutaway(true)
		if open:
			_place(Vector3(4, 0, 2), 38.0, 38.0, 60.0)
		await _frames(90)
		var t0 := Time.get_ticks_usec()
		await _frames(120)
		var ms := (Time.get_ticks_usec() - t0) / 120000.0
		print("PERF %s: %.2f ms/frame (%.0f fps), draw calls %d, primitives %d, objects %d" % [
			"close" if open else "overview", ms, 1000.0 / ms,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	print("CAMPUS BUILDING SCREENSHOTS DONE")
	quit()


func _set_campus(s: TycoonState, era: int, level: int) -> void:
	s.weeks = (era - 1) * 5 * 52 + 10
	for lot: String in s.lot_ids():
		s.buildings[lot] = {"kind": s.lot_kind(lot), "level": level, "target": level, "weeks_left": 0}
	s.changed.emit()


func _place(focus: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> void:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	cam.global_position = focus + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.look_at(focus + Vector3(0, 1.5, 0), Vector3.UP)
	cam.near = maxf(dist * 0.02, 0.2)


func _cutaway(on: bool) -> void:
	for b: CampusBuilding in main.campus._buildings.values():
		b.cutaway_enabled = on


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved %s" % path)
