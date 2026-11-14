extends SceneTree
## Windowed screenshots of the main menu (scenes/menu/main_menu.tscn):
##   menu_<lang>_<NN>_<shot>   the menu over each background shot of the attract loop
##   menu_<lang>_options       the options panel
##   menu_<lang>_hover         "New campaign" hovered (the Cometling peeks in and waves)
## for lang in pt and en. With "shots" after the output folder it renders only the shots
## (no UI) at a few moments each, for look development; with "fair" it presses Fair mode and
## checks that the campus opens with TycoonMain.fair_mode on (menu_fair_switch.png).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_menu.gd -- <out_dir> [shots|fair]

const MENU := "res://scenes/menu/main_menu.tscn"

var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	if args.size() > 1 and args[1] == "shots":
		await _shots_only(args.slice(2))
	elif args.size() > 1 and args[1] == "fair":
		await _fair()
	else:
		await _menu()
	print("MENU SCREENSHOTS DONE")
	quit()


func _shots_only(only: Array) -> void:
	var ps := load(MENU) as PackedScene
	var probe := ps.instantiate()
	var director := probe.get_node("Background") as MenuDirector
	var shots := director.shots.duplicate()
	probe.free()
	for path: String in shots:
		var shot_name := path.get_file().get_basename()
		if not only.is_empty() and not only.has(shot_name):
			continue
		var shot := (load(path) as PackedScene).instantiate() as MenuShot
		get_root().add_child(shot)
		await process_frame
		shot.begin()
		var t0 := Time.get_ticks_msec()
		await _frames(3)
		print("%s ready in %d ms" % [shot_name, Time.get_ticks_msec() - t0])
		for frac in [0.15, 0.5, 0.85]:
			await _run_until(shot, shot.duration * frac)
			await _shot("%s_%02d" % [shot_name, int(frac * 100)])
		shot.queue_free()
		await _frames(2)


func _fair() -> void:
	var t0 := Time.get_ticks_msec()
	var menu := (load(MENU) as PackedScene).instantiate()
	get_root().add_child(menu)
	current_scene = menu
	await _frames(2)
	print("menu loaded and first frame in %d ms" % (Time.get_ticks_msec() - t0))
	await _frames(60)
	(menu.get_node("%Fair") as Button).pressed.emit()
	var guard := 0
	while current_scene == menu and guard < 1200:
		await process_frame
		guard += 1
	await _frames(90)
	var scene := current_scene
	print("switched to %s, fair_mode = %s" % [scene.scene_file_path if scene else "<none>",
		str(scene.get("fair_mode")) if scene else "-"])
	await _shot("menu_fair_switch")


func _menu() -> void:
	var menu := (load(MENU) as PackedScene).instantiate()
	get_root().add_child(menu)
	var director := menu.get_node("Background") as MenuDirector
	for lang in ["pt", "en"]:
		TranslationServer.set_locale(lang)
		director.show_shot(0, false)
		await _frames(30)
		if lang == "pt":
			# frame timing: average over 2 s of the first shot
			var t0 := Time.get_ticks_usec()
			await _frames(120)
			print("avg frame %.2f ms" % ((Time.get_ticks_usec() - t0) / 120000.0))
		for i in director.shots.size():
			director.show_shot(i, false)
			await _frames(4)
			await _run_until(director.current, director.current.duration * 0.45)
			await _shot("menu_%s_%02d_%s" % [lang, i + 1, director.shots[i].get_file().get_basename().trim_prefix("shot_")])
			if i == 0:
				menu.call("debug_hover_new_campaign")
				await _frames(70)
				await _shot("menu_%s_hover" % lang)
				menu.call("debug_unhover")
		menu.call("open_options")
		await _frames(30)
		await _shot("menu_%s_options" % lang)
		menu.call("close_options")
		await _frames(20)


## Lets the shot run in real time until its clock reaches t seconds.
func _run_until(shot: MenuShot, t: float) -> void:
	var guard := 0
	Engine.time_scale = 3.0
	while shot.time < t and guard < 2000:
		await process_frame
		guard += 1
	Engine.time_scale = 1.0


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
