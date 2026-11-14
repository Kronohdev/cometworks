extends "res://tests/test_ui_fit.gd"
## Windowed screenshots of the HUD and every full screen on the state of test_ui_fit.gd
## (year 13, rivals spread on the race track, projects in each state), for checking the fit at
## a window size: fit_00_hud, fit_01_hud_lot, fit_<screen>.
## Run: godot --path . --resolution 1280x720 --script res://tests/screenshot_ui_fit.gd -- <out_dir> [pt|en] [screen,...]

var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only: PackedStringArray = []
	if args.size() > 2:
		only = args[2].split(",")
	CwMotion.set_reduced(true)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(3)
	hud = main.hud
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	await _prepare_state()
	TranslationServer.set_locale("en" if args.size() > 1 and args[1] == "en" else "pt_BR")
	await _frames(60)
	if only.is_empty() or "hud" in only:
		await _shot("fit_00_hud")
		hud.show_lot("lab")
		await _frames(10)
		await _shot("fit_01_hud_lot")
		hud.close_lot()
	for c: Dictionary in cases():
		var n := String(c["key"])
		if not only.is_empty() and n not in only:
			continue
		if not await open_case(c):
			print("no screen %s" % n)
			continue
		await _wait(0.9 if c["screen"] == "finale" else 0.1)
		await _frames(20)
		await _shot("fit_" + n.replace("@", "_"))
		hud.close_screen()
		await _frames(4)
	print("FIT SCREENSHOTS DONE")
	main.queue_free()
	await _frames(2)
	quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
