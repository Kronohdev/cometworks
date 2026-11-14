extends SceneTree
## Windowed screenshots of the mission project loop (E1) on the Cometworks main screen:
##   project_01_new        New project: target, type, ideal balance, contract, team, estimate
##   project_02_phase1     phase 1 levers right after Start
##   project_03_phase1_mix the levers moved (live preview of the bars)
##   project_04_phase2     phase 2 (tests remove defects)
##   project_05_phase3     phase 3
##   project_06_review     the review: grade, 4 newspapers, results
##   project_07_strips     the campus with two projects in the bottom strips
##   project_08_review_success  a 2-Cometling sounding that flies (the roll is forced)
##   project_01b_rocket    the rocket designer after New project (E2)
##   project_05b_design_review  the Design Review when development ends (E2)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_project.gd -- <out_dir> [en|pt]

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
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	for c in main.get_children():
		if c is ProjectFlow:
			(c as ProjectFlow).launch_cinematic = false  # the launch has its own screenshots (screenshot_launch.gd)
	var s := main.state
	s.contracts.append({"id": "C-104", "type": "sounding", "target": "suborbital", "sponsor_key": "Instituto do Vento",
		"reward": 60000, "bonus": 15000, "penalty": 20000, "deadline_week": 30, "min_bars": {"sci": 5.0},
		"status": "accepted"})
	await _frames(90)
	main.hud.open_screen("new_project")
	await _frames(20)
	await _shot("project_01_new")
	var np := main.hud.get_node("%Screens").get_child(0)
	np.call("_start")
	await _frames(30)
	await _shot("project_01b_rocket")
	main.hud.get_node("%Screens").get_child(0).call("_start")
	await _frames(20)
	await _shot("project_02_phase1")
	var ph := main.hud.get_node("%Screens").get_child(0)
	(ph.get_node("%Lever0/Slider") as VSlider).value = 55
	(ph.get_node("%Lever2/Slider") as VSlider).value = 25
	await _frames(10)
	await _shot("project_03_phase1_mix")
	ph.call("_confirm")
	await _frames(5)
	s.advance_week()
	await _frames(20)
	ph = main.hud.get_node("%Screens").get_child(0)
	(ph.get_node("%Lever2/Slider") as VSlider).value = 35
	await _frames(10)
	await _shot("project_04_phase2")
	ph.call("_confirm")
	await _frames(5)
	s.advance_week()
	await _frames(20)
	ph = main.hud.get_node("%Screens").get_child(0)
	(ph.get_node("%Lever2/Slider") as VSlider).value = 45
	await _frames(10)
	await _shot("project_05_phase3")
	ph.call("_confirm")
	await _frames(5)
	s.advance_week()
	await _frames(40)
	await _shot("project_05b_design_review")
	var dr := main.hud.get_node("%Screens").get_child(0)
	if dr.has_method("_launch"):
		dr.call("_launch")
	await _frames(90)
	await _shot("project_06_review")
	main.hud.close_screen()
	await _frames(5)
	# a second sounding with a small team, launched on a roll that flies
	var free0 := ProjectDesk.free_staff(s)
	var team2: Array[String] = [String(free0[0]["id"]), String(free0[1]["id"])]
	var p2 := ProjectDesk.start_project(s, "sounding", "suborbital", team2)
	await _frames(5)
	var plan := [[45, 25, 30], [40, 20, 40], [25, 15, 60]]
	for k in 3:
		ProjectDesk.set_sliders(s, p2.id, plan[k])
		main.hud.close_screen()
		await _frames(3)
		if k == 2:
			_force_success(s, p2)
		s.advance_week()
		await _frames(5)
		if p2.review_state == "waiting":
			main.hud.close_screen()
			await _frames(3)
			ProjectDesk.confirm_review(s, p2.id, [])
			await _frames(5)
	await _frames(90)
	await _shot("project_08_review_success")
	main.hud.close_screen()
	await _frames(5)
	# two projects in development for the strips
	var free := ProjectDesk.free_staff(s)
	var a: Array[String] = [String(free[0]["id"]), String(free[1]["id"])]
	var b: Array[String] = [String(free[2]["id"])]
	ProjectDesk.start_project(s, "sounding", "suborbital", a)
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	ProjectDesk.start_project(s, "demo_sat", "leo", b)
	main.hud.close_screen()
	await _frames(5)
	main.hud.close_screen()
	s.advance_week()
	main.hud.close_screen()
	await _frames(5)
	main.hud.close_screen()
	await _frames(60)
	await _shot("project_07_strips")
	print("PROJECT SCREENSHOTS DONE")
	quit()


## Reseeds the campaign rng so the next launch roll succeeds (screenshots only).
func _force_success(s: TycoonState, p: MissionProject) -> void:
	var chance := float(ProjectDesk.success_chance(s, p)["total"])
	for k in range(1, 1000):
		var r := RandomNumberGenerator.new()
		r.seed = k
		if r.randf() < chance * 0.8:
			s.rng.seed = k
			return


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
