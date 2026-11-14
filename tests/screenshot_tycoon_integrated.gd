extends SceneTree
## Windowed screenshots of the hangar and the flight inside the main mode (TycoonModes):
##   integrated_01_designer        the rocket designer with "Montar no hangar" (quick design)
##   integrated_02_hangar_mission  the embedded hangar building for the mission (the HUD goal card with Voltar / Usar na missão)
##   integrated_03_designer_hangar the designer with the hangar rocket on the bench
##   integrated_04_launch_choice   the pad: pilot the launch or automatic simulation
##   integrated_05_flight_pad      the piloted mission flight, on the pad
##   integrated_06_flight_pause    its pause menu (End and back to the campus)
##   integrated_07_review          the review after a piloted flight
##   integrated_08_workshop_lot    the workshop's lot panel with "Abrir o hangar"
##   integrated_09_free_workshop   the free workshop (no mission)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_integrated.gd -- <out_dir> [en|pt]

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
	s.cash = 3.0e6
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	await _frames(40)
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = [String(free[0]["id"]), String(free[1]["id"]), String(free[2]["id"])]
	main.hud.open_screen("rocket_designer", {"type": "demo_sat", "target": "leo", "staff": team})
	await _frames(40)
	await _shot("integrated_01_designer")
	var des := _screen()
	des.call("open_hangar")
	await _frames(20)
	main.modes.mode_node.call("load_example", "garca")
	await _frames(60)
	main.modes.refresh_card()
	await _frames(5)
	await _shot("integrated_02_hangar_mission")
	main.modes.accept_vessel()
	await _frames(40)
	await _shot("integrated_03_designer_hangar")
	des.call("_start")
	await _frames(10)
	var p: MissionProject = null
	for q: MissionProject in s.mission_projects:
		if HangarRocket.is_hangar(q.rocket["parts"]):
			p = q
	var flow: ProjectFlow = null
	for c in main.get_children():
		if c is ProjectFlow:
			flow = c
	flow.dev_drop_phases(p.id)
	ProjectDesk.dev_finish_development(s, p.id)
	flow.dev_drop_phases(p.id)
	await _frames(10)
	ProjectDesk.confirm_review(s, p.id, [])
	main.hud.close_screen()
	await _frames(40)
	await _shot("integrated_04_launch_choice")
	var choice := _screen()
	choice.call("pilot")
	await _frames(90)
	await _shot("integrated_05_flight_pad")
	var fw := main.modes.mode_node as FlightWorld
	fw.toggle_pause()
	await _frames(10)
	await _shot("integrated_06_flight_pause")
	fw.toggle_pause()
	# a good flight (the report a real orbit would give)
	main.modes._on_flight_exit("done", {"result": "orbit", "orbit": true, "max_alt": 215000.0, "ap": 260000.0,
		"pe": 180000.0, "dv_left": 900.0, "time": 540.0, "launched": true})
	await _frames(60)
	await _shot("integrated_07_review")
	for i in 4:
		if main.hud.current_screen() != "":
			main.hud.close_screen()
		await _frames(10)
	var lot := ""
	for l: String in s.lot_ids():
		if s.lot_kind(l) == "workshop":
			lot = l
	main.hud.show_lot(lot)
	main.camera.frame_area(main.campus.lot_position(lot), Vector2(16, 16))
	await _frames(90)
	await _shot("integrated_08_workshop_lot")
	main.hud.close_lot()
	main.modes.open_project_hangar()
	await _frames(60)
	await _shot("integrated_09_free_workshop")
	main.modes.close_mode()
	await _frames(5)
	quit()


func _screen() -> Node:
	var layer := main.hud.get_node("%Screens")
	return layer.get_child(layer.get_child_count() - 1) if layer.get_child_count() > 0 else null


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
