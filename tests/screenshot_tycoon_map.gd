extends SceneTree
## Windowed screenshots of the mission map and the mission archive (step E5), opened from the
## real HUD of scenes/tycoon/tycoon_main.tscn with synthetic missions in LEO, SSO, GEO, on the
## way to the Moon, in lunar orbit and on the lunar surface:
##   tycoon_map_00_empty      year 1, English: no mission yet, only the campus dish
##   tycoon_map_01_overview   the Earth–Moon system, cards, network, a pending decision
##   tycoon_map_01b_selected  a GEO telescope selected (card lit, camera follows it)
##   tycoon_map_02_earth      the Earth view: LEO / SSO / GEO rings, stations, coverage arcs
##   tycoon_map_03_moon       the Moon view: lunar orbiter, lander, translunar trajectory
##   tycoon_map_04_net3       same overview with the deep-space network (level 3)
##   tycoon_map_05_comet      year 24: the comet Mother-Ice on approach and a comet mission
##   tycoon_book_01_archive   the mission archive
##   tycoon_book_02_cards     the encyclopedia cards
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_map.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	var s := main.state
	TranslationServer.set_locale("en")
	main.hud.open_screen("map")
	await _frames(60)
	await _shot("tycoon_map_00_empty")
	main.hud.close_screen()
	TranslationServer.set_locale("pt")
	s.weeks = 10 * 52 + 6
	s.cash = 4.0e6
	s.buildings["antenna"] = {"kind": "antenna", "level": 2, "target": 2, "weeks_left": 0}
	_add(s, "DEM-04", "demo_sat", "leo")
	_add(s, "EOB-02", "earth_obs", "sso")
	_add(s, "COM-01", "comms", "geo")
	_add(s, "TEL-01", "telescope", "geo")
	for i in 4:
		s.advance_week()
	_add(s, "ORB-01", "orbiter", "lunar_orbit")
	_add(s, "LND-01", "lander", "lunar_surface")
	for i in 3:
		s.advance_week()
	_add(s, "ROV-01", "rover", "lunar_pole")
	_add(s, "SWX-01", "space_weather", "geo")
	var orb := MissionOps.find(s, "ORB-01")
	orb["event"] = "storage"
	orb["decision"] = {"event": "storage", "since": int(orb["age"])}
	# a few finished missions for the archive
	_archive(s)
	s.changed.emit()
	main.hud.open_screen("map")
	var map := main.hud.get_node("%Screens").get_child(0) as OpsMapScreen
	await _frames(90)
	await _shot("tycoon_map_01_overview")
	map.select_mission("TEL-01")
	await _frames(90)
	await _shot("tycoon_map_01b_selected")
	map.set_view("earth", true)
	await _frames(40)
	await _shot("tycoon_map_02_earth")
	map.set_view("moon", true)
	await _frames(40)
	await _shot("tycoon_map_03_moon")
	s.buildings["antenna"]["level"] = 3
	map.set_view("all", true)
	s.changed.emit()
	await _frames(40)
	await _shot("tycoon_map_04_net3")
	# late campaign: the comet comes
	s.weeks = 23 * 52 + 30
	_add(s, "CMT-01", "comet_mission", "comet")
	s.advance_week()
	s.advance_week()
	map.set_view("comet", true)
	await _frames(60)
	await _shot("tycoon_map_05_comet")
	main.hud.open_screen("book")
	await _frames(30)
	await _shot("tycoon_book_01_archive")
	var book := main.hud.get_node("%Screens").get_child(-1)
	if book.has_method("show_page"):
		book.call("show_page", "cards")
	await _frames(20)
	await _shot("tycoon_book_02_cards")
	print("TYCOON MAP SCREENSHOTS DONE")
	quit()


func _add(s: TycoonState, code: String, type: String, target: String) -> void:
	s.active_missions.append({"id": code, "code": code, "type": type, "target": target, "start_week": s.weeks,
		"weeks_total": 0, "data_stored": 0.0, "data_down": 0.0, "science": 0.0, "status": "cruise",
		"grade": 7.0, "outcome": "full"})


## Runs a few short missions to the end on a copy, so the archive has real entries.
func _archive(s: TycoonState) -> void:
	var t := TycoonState.new_campaign(99)
	t.weeks = 2 * 52
	var plan := [["SND-01", "sounding", "suborbital", 0], ["SND-02", "sounding", "suborbital", 0],
		["DEM-01", "demo_sat", "leo", 0], ["DEM-02", "demo_sat", "leo", 1], ["EOB-01", "earth_obs", "sso", 1],
		["IMP-01", "impactor", "lunar_pole", 2], ["DEM-03", "demo_sat", "leo", 2]]
	for p in plan:
		t.buildings["antenna"] = {"kind": "antenna", "level": p[3], "target": p[3], "weeks_left": 0}
		_add(t, p[0], p[1], p[2])
		for i in 6:
			t.advance_week()
	for i in 30:
		t.advance_week()
	s.mission_archive.assign(t.mission_archive)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved %s" % path)
