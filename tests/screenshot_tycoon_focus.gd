extends SceneTree
## Windowed screenshots of the mission studies (FocusStudy) where the player uses them:
##   focus_00_phase_t0     a phase screen when nothing is known ("?" and how to find out)
##   focus_01_phase_t1     tier 1: the bar that matters most / least, the lever to focus on
##   focus_02_phase_t2     tier 2: the levels, the lever arrows, the study's suggestion button
##   focus_03_phase_t3     tier 3: the ideal ticks, the green bands on the levers, the match
##   focus_04_phase_t3_suggested  the suggestion applied
##   focus_05_new_project  New project: what the agency knows about the type, the study button
##   focus_06_team         the team step with what the mission leans on (tier 2)
##   focus_07_studies      the lab's mission studies page (one under way)
##   focus_08_journal      the journal page of a studied type
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_focus.gd -- <out_dir> [en|pt]

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
	var s := main.state
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	await _frames(60)
	# a demo satellite with a small team (no scientist: Science runs low)
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = []
	for m in free:
		if String(m.get("profession", "")) != "scientist" and team.size() < 3:
			team.append(String(m["id"]))
	var p := ProjectDesk.start_project(s, "demo_sat", "leo", team)
	await _frames(10)
	main.hud.close_screen()
	await _frames(5)
	for t in 4:
		if t > 0:
			FocusStudy.complete_tier(s, "demo_sat")
		main.hud.open_screen("project_phase", {"project_id": p.id})
		await _frames(30)
		await _shot("focus_0%d_phase_t%d" % [t, t])
		if t == 3:
			main.hud.get_node("%Screens").get_child(0).call("apply_suggestion")
			await _frames(15)
			await _shot("focus_04_phase_t3_suggested")
		main.hud.close_screen()
		await _frames(8)
	# New project on a type the lab has started on (tier 1 of the orbiter... the earth obs)
	TycoonResearch.complete(s, "basic_instruments")
	TycoonResearch.complete(s, "radio_tracking")
	TycoonResearch.complete(s, "multispectral_imaging")
	TycoonResearch.complete(s, "sun_sync_orbits")
	FocusStudy.complete_tier(s, "earth_obs")
	main.hud.open_screen("new_project", {"target": "sso", "type": "earth_obs"})
	await _frames(30)
	await _shot("focus_05_new_project")
	main.hud.close_screen()
	await _frames(8)
	FocusStudy.complete_tier(s, "earth_obs")
	main.hud.open_screen("project_team", {"type": "earth_obs", "target": "sso", "payload": ["camera", "omni", "battery"]})
	await _frames(30)
	await _shot("focus_06_team")
	main.hud.close_screen()
	await _frames(8)
	FocusStudy.start(s, "sounding")
	s.research_points += 3.0
	main.hud.open_screen("research", {"study": "sounding"})
	await _frames(40)
	await _shot("focus_07_studies")
	main.hud.close_screen()
	await _frames(8)
	main.hud.open_screen("journal", {"type": "earth_obs", "target": "sso"})
	await _frames(30)
	await _shot("focus_08_journal")
	print("FOCUS SCREENSHOTS DONE")
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
