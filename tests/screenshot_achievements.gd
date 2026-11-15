extends SceneTree
## Windowed screenshots of the Conquistas and the Estatísticas (Achievements):
##   ach_01_book      the badge book on a campaign (the era 3 demonstration save): earned badges in
##                    colour, locked ones greyed, secret ones as "?", a badge with progress chosen
##   ach_02_toast     the unlock toast under the HUD's top bar
##   ach_03_stats     the campaign's Estatísticas page
##   ach_04_book_en   the badge book in English, an earned badge chosen
##   ach_05_menu      the badge book over the main menu (the profile, no campaign)
## The profile stays in memory (a test script). Run:
##   godot --path . --resolution 1600x900 --script res://tests/screenshot_achievements.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt_BR")
	Achievements.reset_profile()
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.load_slot = "demo_era3"
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	var s := main.state
	# a few more months on the books for the chart, then some events no state remembers
	for i in 40:
		s.advance_week()
		main.hud.close_screen()
	Achievements.note(s, "sim_to_end")
	var toast := main.get_node("ToastLayer/AchievementToast") as AchievementToast
	# let the notes of the badges the save already earned go by first
	while toast.is_showing():
		await _wait(0.3)
	main.hud.close_screen()
	main.hud.open_screen("achievements", {"id": "photos_10"})
	await _wait(1.2)
	await _shot("ach_01_book")
	main.hud.close_screen()
	await _wait(0.8)
	# the toast: wait for the load's notes to go, then a fresh one
	while toast.is_showing():
		await _wait(0.3)
	toast.show_achievement("moon_landing")
	await _wait(0.7)
	await _shot("ach_02_toast")
	main.hud.open_screen("stats")
	await _wait(1.2)
	await _shot("ach_03_stats")
	TranslationServer.set_locale("en")
	main.hud.open_screen("achievements", {"id": "first_orbit"})
	await _wait(1.2)
	await _shot("ach_04_book_en")
	TranslationServer.set_locale("pt_BR")
	main.queue_free()
	await _frames(4)
	var menu := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	get_root().add_child(menu)
	await _wait(1.5)
	menu.open_achievements()
	await _wait(1.2)
	await _shot("ach_05_menu")
	print("ACHIEVEMENT SCREENSHOTS DONE")
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
