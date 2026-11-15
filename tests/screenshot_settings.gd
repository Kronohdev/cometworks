extends SceneTree
## Windowed screenshots of the settings (the in-game settings screen and the main menu's
## options): their Accessibility and Image tabs, and the race screen in colour-blind mode
## (shape cues on the agency markers).
##   set_01_access        in-game settings, Access tab (colour-blind, keys)
##   set_02_image         in-game settings, Image tab (graphics Baixo / Médio / Alto)
##   set_04_race_cb       the race screen with colour-blind colours and cues
##   set_05_menu_access   the main menu's options, Access page
## user://settings.cfg is put back at the end.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_settings.gd -- <out_dir> [pt|en]

const SETTINGS := "user://settings.cfg"

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var kept: Variant = FileAccess.get_file_as_bytes(SETTINGS) if FileAccess.file_exists(SETTINGS) else null
	TranslationServer.set_locale("en" if args.size() > 1 and args[1] == "en" else "pt_BR")
	CwMotion.set_reduced(true)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.race_flow.autosave = false
	main.camera.tour_enabled = false
	main.clock.set_speed(0)
	if main.tutorial:
		main.tutorial.visible = false
	while main.hud.current_screen() != "":
		main.hud.close_screen()
		await _frames(2)
	main.hud.open_screen("settings", {"tab": "Access"})
	await _wait(1.0)
	await _shot("set_01_access")
	main.hud.close_screen()
	await _frames(4)
	main.hud.open_screen("settings", {"tab": "Image"})
	await _wait(1.0)
	await _shot("set_02_image")
	main.hud.close_screen()
	await _frames(4)
	# a few claims on the track so the markers carry colours
	for rid in ["aurora", "nimbo", "quietude"]:
		main.state.race.claim("suborbital" if rid == "aurora" else ("first_satellite" if rid == "nimbo" else "long_signal"), rid)
	main.state.race.pending_pages.clear()
	CwAccess.set_colorblind(true)
	main.hud.open_screen("race")
	await _wait(1.0)
	await _shot("set_04_race_cb")
	main.hud.close_screen()
	CwAccess.set_colorblind(false)
	main.queue_free()
	await _frames(4)
	var menu := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	await _wait(1.0)
	menu.call("open_options")
	await _wait(0.6)
	(menu.get("options") as MenuOptionsPanel).show_page("access")
	await _wait(0.6)
	await _shot("set_05_menu_access")
	menu.queue_free()
	if kept == null:
		DirAccess.remove_absolute(SETTINGS)
	else:
		FileAccess.open(SETTINGS, FileAccess.WRITE).store_buffer(kept)
	print("SETTINGS SCREENSHOTS DONE")
	quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout
