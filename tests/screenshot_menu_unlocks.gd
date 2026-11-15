extends SceneTree
## Screenshots of the HUD menus a new career unlocks (MenuUnlocks, HudUnlocker):
##   unlocks_hud_all        the HUD with every menu (an old save, "Já sei jogar", gradual off)
##   unlocks_hud_fresh      a new career: only the essentials
##   unlocks_pop_crew       the crew key popping in under its badge
##   unlocks_lesson_crew_<pt|en>  Vovô's lesson pointing at the new key
##   unlocks_pop_race       the race board and its rail key popping in
##   unlocks_library        the library with "Já sei jogar" and "Menus aos poucos"
## Run: godot --path . --resolution 1280x720 --script res://tests/screenshot_menu_unlocks.gd -- <out_dir>

var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt_BR")
	# every menu (what a test script, an old save or "Já sei jogar" shows)
	var all := await _main()
	await _frames(20)
	await _shot("unlocks_hud_all")
	all.queue_free()
	await _frames(4)
	# a new career
	HudUnlocker.allow_in_scripts = true
	TycoonTutorial.allow_in_scripts = true
	var main := await _main()
	main.tutorial.auto_start = false
	await _frames(20)
	await _shot("unlocks_hud_fresh")
	TutorialBook.mark_seen(main.state, "campus")
	main.tutorial.auto_start = true
	main.state.mission_projects.append(MissionProject.new())
	main.state.changed.emit()
	await _frames(2)
	await _wait(0.32)
	await _shot("unlocks_pop_crew")
	await _wait(main.unlocks.lesson_delay + 0.9)
	if main.tutorial._typing:
		main.tutorial.next()
	await _frames(6)
	await _shot("unlocks_lesson_crew_pt")
	TranslationServer.set_locale("en")
	main.tutorial.start("unlock_crew", true)
	await _frames(2)
	main.tutorial.next()
	await _frames(6)
	await _shot("unlocks_lesson_crew_en")
	TranslationServer.set_locale("pt_BR")
	main.tutorial.skip()
	await _frames(2)
	# the race: let the other items go by quietly, then catch the race popping in
	main.tutorial.auto_start = false
	for id in ["hangar", "map", "journal", "research", "contracts"]:
		MenuUnlocks.open(main.state, id)
		MenuUnlocks.mark_shown(main.state, id)
	main.hud.close_lot()
	main.unlocks.apply()
	await _wait(main.unlocks.reveal_gap + main.unlocks.lesson_delay + 0.2)
	main.hud.close_lot()
	main.state.rivals[0]["milestones"] = 1
	main.state.changed.emit()
	await _frames(2)
	await _wait(0.34)
	await _shot("unlocks_pop_race")
	await _wait(2.0)
	TutorialBook.mark_seen(main.state, "library")
	main.hud.open_screen("library")
	await _frames(30)
	await _shot("unlocks_library")
	print("MENU UNLOCK SCREENSHOTS DONE")
	quit()


func _main() -> TycoonMain:
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(8)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	var cam := main.camera
	cam.tour_enabled = false
	return main


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
