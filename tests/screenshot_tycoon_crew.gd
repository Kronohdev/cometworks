extends SceneTree
## Windowed screenshots of the Cometworks crew (scenes/tycoon/ui/screens/crew.tscn + campus):
##   crew_01_campus_nap   the camera on a napping Cometling (antenna in the profession colour)
##   crew_02_walk_in      a new hire walking in from the gate
##   crew_03_roster       the crew screen: roster + card of a Cometling on a project
##   crew_04_spec         card of a level-3 Cometling choosing a specialisation
##   crew_05_nap_card     card of a napping Cometling
##   crew_06_hire         the hiring market with hidden traits
##   crew_07_roster_en    the roster in English
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_crew.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt_BR")
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	var s := main.state
	TycoonCrew.ensure(s)
	s.cash = 2.0e6
	s.buildings["training"] = {"kind": "training", "level": 1, "target": 1, "weeks_left": 0}
	s.projects.append({"id": "p1", "code": "SAT-07", "kind": "probe", "phase": "2/3", "progress": 0.4,
		"color": CwPalette.AURORA_TEAL})
	var staff := s.staff
	if staff.size() >= 4:
		staff[0]["assigned"] = "p1"
		staff[0]["busy_weeks"] = 5
		staff[1]["morale"] = 22.0
		staff[1]["napping"] = true
		TycoonCrew.add_xp(s, String(staff[2]["id"]), 230.0)
		staff[3]["assigned"] = "p1"
		staff[3]["busy_weeks"] = 11
		staff[3]["morale"] = 41.0
	s.changed.emit()
	await _frames(90)
	var napper := _walker_of(String(staff[1]["id"]))
	if napper:
		main.camera.follow(napper)
	await _frames(150)
	await _shot("crew_01_campus_nap")
	# a new hire walks in from the gate
	TycoonCrew.hire(s, String(TycoonCrew.candidates(s)[0]["id"]))
	await _frames(5)
	var newbie := _walker_of(String(s.staff[s.staff.size() - 1]["id"]))
	if newbie:
		main.camera.follow(newbie)
	await _frames(160)
	await _shot("crew_02_walk_in")
	main.camera.release()
	main.hud.open_screen("crew")
	var scr := main.hud.get_node("%Screens").get_child(0) as CrewScreen
	scr.select_member(String(staff[0]["id"]))
	await _frames(40)
	await _shot("crew_03_roster")
	scr.select_member(String(staff[2]["id"]))
	await _frames(40)
	await _shot("crew_04_spec")
	scr.select_member(String(staff[1]["id"]))
	await _frames(40)
	await _shot("crew_05_nap_card")
	scr.show_tab("hire")
	await _frames(40)
	await _shot("crew_06_hire")
	TranslationServer.set_locale("en")
	scr.show_tab("roster")
	scr.select_member(String(s.staff[s.staff.size() - 1]["id"]))
	await _frames(40)
	await _shot("crew_07_roster_en")
	print("CREW SCREENSHOTS DONE")
	quit()


func _walker_of(id: String) -> Node3D:
	for w in main.campus.cometlings():
		if String(w.get("member_id")) == id:
			return w
	return null


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
