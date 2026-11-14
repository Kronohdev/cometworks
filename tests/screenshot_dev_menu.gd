extends SceneTree
## Windowed screenshots of the dev menu (autoload CwDev, scenes/dev/dev_menu.tscn) open over:
##   dev_campus_<tab>   the campus (scenes/tycoon/tycoon_main.tscn) on each tab
##   dev_menu           the main menu (Geral)
##   dev_hangar         the hangar (Geral)
##   dev_collapsed      the campus with the menu collapsed to its header
## The player's user://dev.cfg and user://settings.cfg are put back afterwards (the main menu
## would otherwise apply a saved fullscreen and ignore --resolution).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_dev_menu.gd -- <out_dir>

var out_dir := "user://"
var dev: CwDevMenu
var _kept := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	for p in [CwDevMenu.CFG_PATH, MenuSettings.PATH]:
		_kept[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null
	var cfg := ConfigFile.new()
	cfg.load(MenuSettings.PATH)
	cfg.set_value(MenuSettings.SECTION, "fullscreen", false)
	cfg.save(MenuSettings.PATH)
	await _frames(2)
	dev = root.get_node("CwDev") as CwDevMenu
	dev.panel.position = Vector2(104, 100)
	dev.set_collapsed(false)

	change_scene_to_file("res://scenes/tycoon/tycoon_main.tscn")
	await _frames(4)
	var main := current_scene as TycoonMain
	main.race_flow.autosave = false
	await _wait(1.5)
	dev.set_open(true)
	for tab in ["Geral", "Campanha", "Projetos", "Cenas", "Telas", "Cometinhos", "Log"]:
		dev.tabs.current_tab = dev.tabs.get_tab_idx_from_control(dev.tabs.get_node(tab))
		await _wait(0.4)
		await _shot("dev_campus_" + tab.to_lower())
	dev.tabs.current_tab = 1
	dev.set_collapsed(true)
	await _wait(0.3)
	await _shot("dev_collapsed")
	dev.set_collapsed(false)

	dev.tabs.current_tab = 0
	change_scene_to_file("res://scenes/menu/main_menu.tscn")
	await _wait(2.0)
	await _shot("dev_menu")

	change_scene_to_file("res://scenes/hangar.tscn")
	await _wait(2.0)
	await _shot("dev_hangar")

	for p: String in _kept:
		if _kept[p] == null:
			DirAccess.remove_absolute(p)
		else:
			FileAccess.open(p, FileAccess.WRITE).store_buffer(_kept[p])
	print("DEV MENU SCREENSHOTS DONE")
	quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join("%s_%dx%d.png" % [shot_name, img.get_width(), img.get_height()])
	img.save_png(path)
	print("saved ", path)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout
