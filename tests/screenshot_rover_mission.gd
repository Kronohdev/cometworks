extends SceneTree
## Windowed screenshots of a rover mission in the career (opens a window):
##   rover_mission_01_planner   the payload planner of a rover mission with its Rover card
##   rover_mission_02_builder   the workshop opened from it ("Montar o rover")
##   rover_mission_03_planner_rover  back in the planner with the rover in the payload
##   rover_mission_04_map       the rover landed: the Solar System map with "Controlar o rover"
##   rover_mission_05_drive     driving it on the Moon inside the campus
##   rover_mission_06_archive   the mission's archive page with its surface summary
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_rover_mission.gd -- <out_dir> [en|pt]

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	TranslationServer.set_locale(args[1] if args.size() > 1 else "pt")
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	var s := main.state
	for t: Dictionary in TycoonResearch.techs():
		if int(t.get("era", 1)) <= 4 and not TycoonResearch.is_done(s, String(t["id"])):
			TycoonResearch.complete(s, String(t["id"]))
	s.cash = maxf(s.cash, 5.0e6)
	await _frames(30)
	var plan := {"type": "rover", "target": "lunar_surface", "briefing_id": "", "payload": PayloadRules.default_payload(s, "rover", "lunar_surface")}
	main.hud.open_screen("payload_planner", plan)
	await _frames(40)
	await _shot("rover_mission_01_planner")
	var planner := _screen()
	planner.get_node("%RoverBuild").emit_signal("pressed")
	await _frames(40)
	var builder := _screen()
	builder.call("toggle_part", "spectrometer")
	builder.call("set_tab", "instrument")
	await _frames(30)
	await _shot("rover_mission_02_builder")
	builder.call("use_design")
	await _frames(40)
	await _shot("rover_mission_03_planner_rover")
	main.hud.close_screen()
	await _frames(10)
	var dev := root.get_node_or_null("CwDev")
	dev.call("run", "rover_test_mission")
	await _frames(10)
	# the launch's cinematic and review are queued: let them go, then two weeks pass (it lands)
	for i in 6:
		main.hud.close_screen()
		await _frames(6)
	for i in 2:
		s.advance_week()
	for i in 4:
		main.hud.close_screen()
		await _frames(4)
	var am: Dictionary = dev.call("_rover_mission", s)
	main.modes.open_space_map("p:" + String(am.get("id", "")))
	await _frames(100)
	await _shot("rover_mission_04_map")
	var ov := main.modes.overlay
	ov.call("drive_selected")
	await _frames(20)
	var drive := main.modes.mode_node as RoverDrive
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and not drive.planet.terrain.is_idle():
		await process_frame
	drive.rover.player_input = false
	drive.rover.throttle = 1.0
	await _frames(120)
	drive.rover.throttle = 0.0
	drive.hud.use_tool("photo")
	await _frames(200)
	await _shot("rover_mission_05_drive")
	drive.hud.set_paused(true)
	drive.leave()
	await _frames(30)
	main.modes.close_mode()
	await _frames(10)
	dev.call("run", "rover_end_mission")
	await _frames(60)
	await _shot("rover_mission_06_archive")
	print("SHOTS DONE")
	quit()


func _screen() -> Node:
	var scr := main.hud.get_node("%Screens")
	return scr.get_child(scr.get_child_count() - 1) if scr.get_child_count() > 0 else null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)
