extends SceneTree
## Windowed screenshot of the Design Review with its CML checklist (CmlChecklist):
##   cml_01_review   a demo satellite to low orbit at its review, nothing fixed
##   cml_02_fixes    the same with the riskiest fixes chosen (the checklist climbs)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_cml_review.gd -- <out_dir> [en|pt]

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
	var s := main.state
	s.cash = 3.0e6
	await _frames(60)
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = [String(free[0]["id"]), String(free[1]["id"]), String(free[2]["id"])]
	main.hud.open_screen("rocket_designer", {"type": "demo_sat", "target": "leo", "staff": team})
	await _frames(10)
	var des := main.hud.get_node("%Screens").get_child(0)
	des.call("_pick_proposal", "balanced")
	await _frames(10)
	des.call("_start")
	await _frames(10)
	var p: MissionProject = s.mission_projects[s.mission_projects.size() - 1]
	for k in 30:
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
	await _shot("cml_01_review")
	var rev := main.hud.get_node("%Screens").get_child(0)
	for rk in DesignReview.risks(s, p, []):
		if String(rk["fix_key"]) != "" and String(rk["severity"]) != "low":
			rev.call("_toggle_fix", String(rk["id"]), true)
	await _frames(40)
	await _shot("cml_02_fixes")
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
