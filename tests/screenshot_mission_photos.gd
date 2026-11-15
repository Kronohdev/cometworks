extends SceneTree
## Windowed check of the photos missions send home (MissionPhotoStudio, the album, the mural):
##   photo_<shot>.png   every shot of data/tycoon/mission_photos.json rendered by the studio
##                      (photo_ir_comet.png: the infrared camera's false colours)
##   album.png          the album screen after three missions (Earth, Moon, comet) sent photos
##   mural.png          the campus mural by the headquarters with the best three
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_mission_photos.gd -- <out_dir> [en|pt]

var out_dir := "user://photo_shots"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		TranslationServer.set_locale(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	main.camera.tour_enabled = false
	var s := main.state
	s.weeks = 1 * 52 + 13   # year 2: no conference invitation in the way
	var studio := main.photo_studio
	print("can render: %s" % MissionPhotoStudio.can_render())
	# every shot, straight to the output folder
	var k := 0
	for shot_id: String in MissionPhotos.data()["shots"]:
		k += 1
		var ph := {"id": "gallery_%d" % k, "project_id": "gallery", "code": "TST-%02d" % k, "type": "orbiter",
			"target": "leo", "shot": shot_id, "filter": "", "outcome": "full", "week": s.weeks, "seed": 1000 + k * 37,
			"file": out_dir.path_join("photo_%s.png" % shot_id)}
		var ok: bool = await studio.render(ph, s)
		print("%s %s" % ["saved" if ok else "FAILED", ph["file"]])
	var irph := {"id": "gallery_ir", "project_id": "gallery", "code": "IR-01", "type": "comet_mission", "target": "comet",
		"shot": "comet", "filter": "ir", "outcome": "full", "week": s.weeks, "seed": 4242,
		"file": out_dir.path_join("photo_ir_comet.png")}
	await studio.render(irph, s)
	print("saved %s" % irph["file"])
	# three missions send photos home through the state; the studio renders them on its own
	for m in [["DEM-01", "demo_sat", "leo", "full"], ["ORB-02", "orbiter", "lunar_orbit", "exceptional"],
			["CMT-03", "comet_mission", "comet", "exceptional"]]:
		s.weeks += 3
		MissionPhotos.on_launch(s, {"project_id": "shot_" + String(m[0]), "code": m[0], "type": m[1], "target": m[2],
			"success": true, "outcome": m[3], "payload": ["camera", "battery"]})
	s.changed.emit()
	for i in 600:
		await process_frame
		if MissionPhotos.missing(s).is_empty():
			break
	print("missing after the studio ran: %d of %d" % [MissionPhotos.missing(s).size(), s.photos.size()])
	await _frames(20)
	main.hud.open_screen("album", {"project_id": "shot_CMT-03"})
	await _frames(40)
	await _shot("album")
	main.hud.close_screen()
	await _frames(20)
	main.camera.frame_area(main.photo_mural.global_position, Vector2(7, 7))
	await _frames(150)
	await _shot("mural")
	# straight in front of the board
	var cam := Camera3D.new()
	main.add_child(cam)
	var mt := main.photo_mural.global_transform
	cam.look_at_from_position(mt * Vector3(-2.2, 2.2, 6.5), mt * Vector3(0, 1.4, 0), Vector3.UP)
	cam.fov = 45.0
	cam.make_current()
	await _frames(30)
	await _shot("mural_close")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
