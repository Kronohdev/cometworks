extends SceneTree
## Visual smoke test for the solar-system map: saves screenshots (overview EN/PT and
## close-ups) and prints render statistics (FPS, primitives, draw calls, objects) for
## the default view.
## Run (windowed): godot --path . --resolution 1600x900 --script res://tests/screenshot_solar_system.gd -- <out_dir>

var out_dir := "user://"
var sys: SolarSystem


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var only := args.slice(1)
	sys = (load("res://scenes/solar_system/solar_system.tscn") as PackedScene).instantiate() as SolarSystem
	get_root().add_child(sys)
	await _frames(10)
	TranslationServer.set_locale("en")
	sys.refresh_texts()
	sys._on_pause_toggled(true)
	await _frames(20)
	if only.is_empty() or "overview" in only:
		_shot("ss_overview_en")
		await _stats("default view")
		TranslationServer.set_locale("pt")
		sys.show_info("saturn")
		sys.refresh_texts()
		await _frames(4)
		_shot("ss_overview_pt")
		TranslationServer.set_locale("en")
		sys.refresh_texts()
	var views := [
		["inner", "sun", 210.0, 34.0, -60.0],
		["sun", "sun", 70.0, 12.0, -20.0],
		["earth", "earth", 15.0, 14.0, 40.0],
		["earth_moon", "earth", 26.0, 20.0, -150.0],
		["moon", "moon", 6.5, 10.0, -90.0],
		["mars", "mars", 9.5, 16.0, 30.0],
		["venus", "venus", 12.0, 10.0, 60.0],
		["mercury", "mercury", 7.5, 10.0, 60.0],
		["jupiter", "jupiter", 48.0, 10.0, 25.0],
		["europa", "europa", 6.0, 8.0, 100.0],
		["saturn", "saturn", 62.0, 24.0, -30.0],
		["uranus", "uranus", 24.0, 12.0, 20.0],
		["neptune", "neptune", 24.0, 12.0, 40.0],
		["pluto", "pluto", 6.0, 12.0, 40.0],
		["outer", "jupiter", 260.0, 30.0, -10.0],
		# right at the lod0 -> lod1 switch of the Earth (14 r = 44.7 u, 12% fade margin)
		["earth_lod_fade", "earth", 46.0, 14.0, 40.0],
	]
	for v in views:
		if not only.is_empty() and not v[0] in only:
			continue
		await _view(v[1], v[2], v[3], v[4])
		_shot("ss_" + String(v[0]))
	print("SHOTS DONE")
	quit()


## Focus a body and place the camera at (distance, pitch, yaw) around it, then let it settle.
func _view(id: String, dist: float, pitch_deg: float, yaw_rel_deg: float) -> void:
	sys.focus_body(id)
	var cam := sys.cam
	var b: SolarBody = sys.bodies[id]
	# yaw relative to the Sun direction, so close-ups are lit from the side
	var p := b.body_position()
	var sun_yaw := atan2(-p.x, -p.z) if p.length() > 0.1 else 0.0
	cam.target_distance = dist
	cam.target_yaw = sun_yaw + deg_to_rad(yaw_rel_deg)
	cam.target_pitch = deg_to_rad(pitch_deg)
	cam.distance = dist
	cam.yaw = cam.target_yaw
	cam.pitch = cam.target_pitch
	cam._glide = Vector3.ZERO
	await _frames(14)


func _stats(what: String) -> void:
	# let FPS settle for ~1.5 s of frames
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
		frames += 1
	var fps := frames / ((Time.get_ticks_msec() - t0) / 1000.0)
	print("[%s] fps=%.1f  primitives=%d  draw_calls=%d  objects=%d  video_mem=%.1f MB" % [what, fps,
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	get_root().get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])
