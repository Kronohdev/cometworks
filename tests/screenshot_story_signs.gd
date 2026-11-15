extends SceneTree
## Screenshots of the story signs on the campus island (CampusSigns, the "sign" card):
##   signs_world_plaza     the plaza signs at eye level, the welcome sign hovered (label)
##   signs_world_covered   a covered sign (tarp) next to an open one
##   signs_world_beach     the beach sign by the pier
##   signs_face_<id>       a lore, a space-history and a joke sign up close (their painted pictures)
##   signs_card_<id>_<pt|en>  the card of a lore sign, two space-history signs (fact box; halley is the longest text) and a joke
##   signs_journal         the journal with the count of signs read
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_story_signs.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(8)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	if main.tutorial:
		main.tutorial.set_process(false)
		main.tutorial.visible = false
	var cam := main.camera
	cam.tour_enabled = false
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.set_process_unhandled_input(false)
	var s := main.state
	s.race.claim("first_satellite", RaceDirector.PLAYER)
	main.campus.signs.refresh()
	await _frames(4)
	while main.hud.current_screen() != "":   # the newspaper of the milestone
		main.hud.close_screen()
		await _frames(4)
	var signs := main.campus.signs
	await _look(Vector3(-2.5, 3.2, 14.0), Vector3(-6.0, 1.4, 3.0), 50.0)
	signs._hover("welcome")
	await _frames(20)
	await _shot("signs_world_plaza")
	signs._hover("")
	await _look(Vector3(-11.0, 3.0, 33.5), Vector3(-20.0, 1.2, 24.0), 50.0)
	signs._hover("giotto")
	await _frames(20)
	await _shot("signs_world_covered")
	signs._hover("")
	await _look(Vector3(14.0, -5.5, 68.0), Vector3(6.0, -7.6, 58.0), 50.0)
	await _shot("signs_world_beach")
	# each kind's painted face up close (a comet, a rocket, a smiley), the tag on the open ones
	for id in ["welcome", "sputnik", "no_feeding"]:
		var sn := signs.sign_node(id)
		var front := sn.global_transform.basis.z.normalized()
		var at := sn.pick_point()
		await _look(at + front * 4.2 + Vector3.UP * 0.9 + sn.global_transform.basis.x.normalized() * 0.8, at, 45.0)
		signs._hover(id)
		await _frames(20)
		await _shot("signs_face_%s" % id)
		signs._hover("")
	for loc in ["pt_BR", "en"]:
		TranslationServer.set_locale(loc)
		for id in ["mae_gelo", "sputnik", "halley", "no_feeding"]:
			main.open_sign(id)
			await _frames(30)
			await _shot("signs_card_%s_%s" % [id, loc.substr(0, 2)])
			main.hud.close_screen()
			await _frames(4)
	TranslationServer.set_locale("pt_BR")
	main.hud.open_screen("journal")
	await _frames(30)
	await _shot("signs_journal")
	print("STORY SIGN SCREENSHOTS DONE")
	quit()


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	main.camera.fov = fov
	main.camera.global_transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	await _frames(20)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
