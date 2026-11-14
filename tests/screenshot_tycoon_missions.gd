extends SceneTree
## Windowed screenshots of the discovery-driven mission loop in era 3 (a campaign with the lunar
## techs, a few flights already in the journal):
##   missions_01_board          the mission board on "A Lua treme?" (moonquakes), with staff hints
##   missions_02_objective      New project for it: lander at the lunar surface, the goal on the right
##   missions_03_payload_night  the payload planner: the story told the lunar night, energy is short
##   missions_04_payload_fixed  heaters and a large battery: the plan closes
##   missions_05_team           the team step: what a lander leans on, the journal's best team
##   missions_06_review         a review with the debrief: what the flight taught, the client, the journal
##   missions_07_journal        the discovery journal on the orbiter page
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_missions.gd -- <out_dir> [en|pt]

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		TranslationServer.set_locale(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	CwMotion.set_reduced(true)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.set("cutscenes", false)
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	var flow: ProjectFlow = null
	for c in main.get_children():
		if c is ProjectFlow:
			flow = c
			flow.launch_cinematic = false
	var s := main.state
	s.cash = 6.0e7
	s.weeks = 10 * 52
	TycoonCrew.ensure(s)
	for t: Dictionary in TycoonResearch.techs():
		if int(t.get("era", 1)) <= 3:
			TycoonResearch.complete(s, String(t["id"]))
	s.buildings["antenna"] = {"kind": "antenna", "level": 2, "target": 2, "weeks_left": 0}
	# a few flights already in the journal (the Design Review waits off screen)
	s.review_gate = false
	_fly(s, "orbiter", "lunar_orbit", ["camera", "lidar", "spectrometer", "solar_wing", "hga", "battery"], [40, 40, 20])
	_fly(s, "orbiter", "lunar_orbit", ["camera", "particle", "solar_wing", "omni", "battery"], [34, 33, 33])
	_fly(s, "earth_obs", "sso", ["ir_camera", "spectrometer", "solar_wing", "hga", "battery"], [30, 40, 30])
	var review_id := _fly(s, "lander", "lunar_surface", ["camera", "particle", "omni", "solar_wing", "battery"], [50, 20, 30])
	s.review_gate = true
	if flow:
		flow._queue.clear()
	main.hud.close_screen()
	await _frames(30)
	BriefingDesk.spawn(s, "moonquakes")
	main.hud.open_screen("briefings", {"briefing_id": "moonquakes"})
	await _frames(30)
	await _shot("missions_01_board")
	main.hud.open_screen("new_project", {"briefing_id": "moonquakes", "type": "lander", "target": "lunar_surface"})
	await _frames(25)
	await _shot("missions_02_objective")
	var plan := {"briefing_id": "moonquakes", "type": "lander", "target": "lunar_surface",
		"payload": ["seismometer", "camera", "omni", "solar_wing", "battery"]}
	main.hud.open_screen("payload_planner", plan)
	await _frames(25)
	var pl := main.hud.get_node("%Screens").get_child(0)
	pl.call("_hover", "seismometer")
	await _frames(5)
	await _shot("missions_03_payload_night")
	pl.call("_toggle", "battery_l")
	pl.call("_toggle", "heater")
	await _frames(10)
	await _shot("missions_04_payload_fixed")
	pl.call("_next")
	await _frames(25)
	await _shot("missions_05_team")
	main.hud.open_screen("project_review", {"project_id": review_id})
	await _frames(60)
	await _shot("missions_06_review")
	main.hud.open_screen("journal", {"type": "orbiter", "target": "lunar_orbit"})
	await _frames(30)
	await _shot("missions_07_journal")
	print("MISSION SCREENSHOTS DONE")
	quit()


## Runs a project to its launch (forced to fly) and returns its id.
func _fly(s: TycoonState, type_id: String, target_id: String, payload: Array, sliders: Array) -> String:
	var team: Array[String] = []
	for m in ProjectDesk.free_staff(s):
		if team.size() < 4:
			team.append(String(m["id"]))
	var p := ProjectDesk.start_project(s, type_id, target_id, team, "", {}, {"payload": payload})
	if p == null:
		push_warning("could not start %s: %s" % [type_id, ProjectDesk.start_error(s, type_id, target_id, team, {}, {"payload": payload})])
		return ""
	var id := p.id
	ProjectDesk.set_sliders(s, id, sliders)
	var guard := 0
	while ProjectDesk.find(s, id) != null and guard < 40:
		if ProjectDesk.find(s, id).weeks_done >= ProjectDesk.find(s, id).weeks_total - 1:
			ProjectDesk.dev_force_outcome = "success"
		s.advance_week()
		var q := ProjectDesk.find(s, id)
		if q and q.awaiting_sliders:
			ProjectDesk.set_sliders(s, id, sliders)
		guard += 1
	return id


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
