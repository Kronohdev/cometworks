extends SceneTree
## Windowed screenshots of the research tree and of the money endgame:
##   rt_01_early        year 1: two techs done, one being researched, the rest misty
##   rt_02_late         year 17: most of the tree grown, a tech under way, hovering a tech
##                      (its path of prerequisites lit)
##   rt_03_grow         an animation frame: a tech just finished, its branches growing
##   rt_04_studies      the mission studies tab (unchanged)
##   rt_05_loan         the emergency loan screen (Bankruptcy)
##   rt_06_gameover     the bankruptcy game-over screen
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_research_tree.gd -- <out_dir> [en|pt_BR]

var out_dir := "user://"
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
	var s := main.state
	s.cash = 2.0e6
	TycoonCrew.ensure(s)
	# early: year 1
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	TycoonResearch.fund(s, "radio_tracking")
	TycoonResearch.fund(s, "basic_instruments")
	TycoonResearch.rs(s)["progress"]["radio_tracking"] = 30.0
	main.hud.open_screen("research")
	await _wait(1.6)
	await _shot("rt_01_early")
	main.hud.close_screen()
	await _wait(0.4)
	# late: year 17, most of the tree done
	s.weeks = 16 * 52 + 10
	for t: Dictionary in TycoonResearch.techs():
		if int(t["era"]) <= 3 or String(t["id"]) in ["hydrolox_engines", "lab_complex", "life_support", "rtg_power"]:
			TycoonResearch.complete(s, String(t["id"]))
	TycoonResearch.rs(s)["active"] = ""
	TycoonResearch.rs(s)["queue"].clear()
	TycoonResearch.fund(s, "crewed_lander")
	TycoonResearch.rs(s)["progress"]["crewed_lander"] = 400.0
	TycoonResearch.fund(s, "sample_return_capsule")
	s.changed.emit()
	main.hud.open_screen("research")
	await _wait(1.6)
	var scr: Node = main.hud.get_node("%Screens").get_child(0)
	if scr.has_method("hover_tech"):
		scr.call("hover_tech", "comet_rendezvous")
		await _wait(0.4)
	await _shot("rt_02_late")
	if scr.has_method("hover_tech"):
		scr.call("hover_tech", "")
	# a frame of the growing animation
	TycoonResearch.complete(s, "crewed_lander")
	s.changed.emit()
	await _wait(0.18)
	await _shot("rt_03_grow")
	main.hud.close_screen()
	await _wait(0.4)
	main.hud.open_screen("research", {"study": ""})
	await _wait(1.0)
	await _shot("rt_04_studies")
	main.hud.close_screen()
	await _wait(0.4)
	# the money endgame (Bankruptcy), when it is there
	if ResourceLoader.exists("res://scenes/tycoon/ui/screens/emergency_loan.tscn"):
		main.bankruptcy_flow.save_records = false
		s.cash = -Bankruptcy.threshold(s) - 1000.0
		Bankruptcy.month_end(s)
		s.changed.emit()
		main.hud.open_screen("emergency_loan")
		await _wait(1.2)
		await _shot("rt_05_loan")
		main.hud.close_screen()
		await _wait(0.4)
		s.cash = -Bankruptcy.threshold(s) * 2.0
		Bankruptcy.month_end(s)
		s.changed.emit()
		main.hud.open_screen("bankrupt")
		await _wait(2.4)
		await _shot("rt_06_gameover")
	print("RESEARCH TREE SCREENSHOTS DONE")
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
