extends SceneTree
## Windowed screenshots of the rocket designer and the Design Review (E2) on the Cometworks
## main screen:
##   rocket_01_designer_sounding  the designer after New project: a sounding rocket
##   rocket_02_designer_leo       a demo satellite to low orbit, a proposal with boosters
##   rocket_03_designer_short     the same with no upper stage: "não chega"
##   rocket_04_review             the Design Review of the demo satellite, nothing fixed
##   rocket_05_review_fixes       the same with fixes chosen (the odds count up)
##   rocket_06_launch_climb       the launch sequence flying the designed rocket (boosters)
##   rocket_07_fail_card          the failure card naming the cause
##   rocket_08_paper              the newspaper's front page on the failure
##   rocket_09_pad                the campus pad with the designed rocket rolling out
##   rocket_10_research           the research screen listing a tech's rocket parts
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_rocket.gd -- <out_dir> [en|pt]

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
	main.race_flow.autosave = false
	var flow: ProjectFlow = null
	for c in main.get_children():
		if c is ProjectFlow:
			flow = c
	var s := main.state
	s.cash = 3.0e6
	await _frames(60)
	# 1. a sounding rocket from New project
	main.hud.open_screen("new_project")
	await _frames(10)
	main.hud.get_node("%Screens").get_child(0).call("_start")
	await _frames(40)
	await _shot("rocket_01_designer_sounding")
	main.hud.close_screen()
	await _frames(10)
	# 2. low orbit: a demo satellite
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = [String(free[0]["id"]), String(free[1]["id"]), String(free[2]["id"])]
	main.hud.open_screen("rocket_designer", {"type": "demo_sat", "target": "leo", "staff": team})
	await _frames(10)
	var des := main.hud.get_node("%Screens").get_child(0)
	des.call("_pick_proposal", "robust")
	await _frames(40)
	await _shot("rocket_02_designer_leo")
	des.call("_pick_part", "upper", "upper_none")
	await _frames(30)
	await _shot("rocket_03_designer_short")
	des.call("_pick_proposal", "balanced")
	await _frames(10)
	des.call("_start")
	await _frames(10)
	# run the project to its review
	var p: MissionProject = s.mission_projects[s.mission_projects.size() - 1]
	for k in 20:
		if p.review_state == "waiting":
			break
		if main.hud.current_screen() == "project_phase":
			main.hud.close_screen()
			await _frames(2)
		ProjectDesk.set_sliders(s, p.id, [40, 25, 35])
		s.advance_week()
		await _frames(2)
	await _frames(40)
	if main.hud.current_screen() != "design_review":
		main.hud.open_screen("design_review", {"project_id": p.id})
		await _frames(40)
	await _shot("rocket_04_review")
	var rev := main.hud.get_node("%Screens").get_child(0)
	rev.call("_toggle_fix", "debut", true)
	rev.call("_toggle_fix", "stage1", true)
	rev.call("_toggle_fix", "payload", true)
	await _frames(40)
	await _shot("rocket_05_review_fixes")
	main.hud.close_screen()
	await _frames(10)
	# 3. the launch flying the designed rocket, then failing
	if flow:
		flow.launch_cinematic = true
	LaunchSequence.set_enabled(true)
	var parts := {"core": "core_falcao", "upper": "upper_kestrel_v", "tank": "tank_m", "boosters": "boost_srb2",
		"fairing": "fairing_s", "avionics": "avionics_basic", "recovery": "recovery_none"}
	var r := {"project_id": p.id, "code": p.code, "type": "demo_sat", "target": "leo", "grade": 6.4, "success": false,
		"outcome": "fail", "p_success": 0.82, "pad": "pad", "cause": "stage2", "cause_key": "TY_RK_CAUSE_STAGE2",
		"rocket": {"family": "", "name": "Bem-te-vi", "parts": parts, "class": "light"}}
	main.hud.open_screen("launch", {"result": r})
	await _frames(5)
	var seq := main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	await _until(seq, "countdown", 5.6)
	await _shot("rocket_06_launch_pad")
	await _until(seq, "flight_fail", 1.5)
	await _shot("rocket_06_launch_climb")
	await _until(seq, "result", 2.0)
	await _shot("rocket_07_fail_card")
	seq.skip()
	await create_timer(1.5).timeout
	await _close_all()
	# 4. the paper
	s.race.report_launch_failure({"code": p.code, "type": "demo_sat", "target": "leo", "cause_key": "TY_RK_CAUSE_STAGE2",
		"p_success": 0.82, "rocket": {"name": "Bem-te-vi"}})
	s.news.push_front({"key": "TY_RK_NEWS_FAIL_CAUSE", "args": [p.code, "TY_RK_CAUSE_STAGE2", "3.1"]})
	main.race_flow._next_page()
	await _frames(60)
	await _shot("rocket_08_paper")
	await _close_all()
	# 5. the pad: the designed rocket rolling out
	s.buildings["pad"]["last_rocket"] = parts
	s.buildings["pad"]["rocket_weeks"] = 3
	s.buildings["pad"]["rocket_total"] = 6
	s.changed.emit()
	await _frames(30)
	var pad := main.campus.building_node("pad")
	if pad:
		main.camera.frame_area(pad.global_position + Vector3(0, 3, 0), Vector2(26, 18))
	await _frames(60)
	await _shot("rocket_09_pad")
	# 6. research lists rocket parts
	main.hud.open_screen("research")
	await _frames(10)
	var rs := main.hud.get_node("%Screens").get_child(0)
	rs.call("select", "upper_stage")
	await _frames(30)
	await _shot("rocket_10_research")
	print("ROCKET SCREENSHOTS DONE")
	quit()


## Waits (in real time: the camera blends) until the sequence plays `anim_name` past `at` s.
func _until(seq: LaunchSequence, anim_name: String, at: float) -> void:
	var guard := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < guard:
		if seq.anim.current_animation == anim_name and seq.anim.current_animation_position >= at:
			return
		await process_frame


func _close_all() -> void:
	for i in 8:
		if main.hud.current_screen() == "":
			break
		main.hud.close_screen()
		await _frames(4)
	await _frames(10)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
