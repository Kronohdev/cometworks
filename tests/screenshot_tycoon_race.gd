extends SceneTree
## Windowed screenshots of the race and ending screens on the Cometworks main scene:
##   race_01_board        the race screen in year 13 (rivals and player spread on the track)
##   race_02_paper_player the newspaper front page for a player first
##   race_03_paper_rival  the newspaper front page for a rival first
##   race_04_paper_fail   the newspaper front page for a rival's spectacular miss
##   race_05_settings     the settings screen (save slots, options)
##   race_06_finale       the Mother-Ice passing (end of year 25)
##   race_07_score        the final score
##   race_08_race_end     the race screen at the end of the campaign
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_race.gd -- <out_dir> [pt|en]

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false   # the finale screen right away (the ending cutscene: screenshot_cutscenes.gd)
	get_root().add_child(main)
	await _frames(5)
	if args.size() > 1:
		TranslationServer.set_locale(args[1])
	main.race_flow.autosave = false
	main.clock.set_speed(0)
	var s := main.state
	var r := s.race
	# twelve and a half years: the rivals spread along the track
	for i in 12 * 52 + 30:
		s.advance_week()
	s.mission_launched.emit({"type": "sounding", "target": "suborbital", "success": true, "outcome": "full"})
	s.mission_launched.emit({"type": "demo_sat", "target": "leo", "success": true, "outcome": "full"})
	s.mission_completed.emit({"type": "comms", "target": "geo", "success": true, "outcome": "full", "science": 80.0})
	s.mission_launched.emit({"type": "orbiter", "target": "lunar_orbit", "success": true, "outcome": "full"})
	_clear_popups()
	await _frames(30)
	await _open("race")
	await _shot("race_01_board")
	# a player first on the front page
	var page := {}
	for p: Dictionary in r.pages:
		if p["by"] == "player" and p["kind"] == "first":
			page = p
	if page.is_empty():
		r.claim("crewed_flyby", "player")
		page = r.pages[0]
	await _open("newspaper", {"page": page})
	await _shot("race_02_paper_player")
	var rival_page := {}
	for p: Dictionary in r.pages:
		if p["by"] != "player" and p["kind"] == "first" and rival_page.is_empty():
			rival_page = p
	if rival_page.is_empty():
		rival_page = {"kind": "first", "milestone": "robotic_landing", "by": "aurora", "week": s.weeks, "issue": 9}
	await _open("newspaper", {"page": rival_page})
	await _shot("race_03_paper_rival")
	await _open("newspaper", {"page": {"kind": "fail", "milestone": "crewed_flyby", "by": "aurora", "months": 5,
		"week": s.weeks, "issue": r.pages.size() + 1}})
	await _shot("race_04_paper_fail")
	await _open("settings")
	await _shot("race_05_settings")
	main.hud.close_screen()
	# to the end: the comet passes
	for i in s.campaign_weeks() - s.weeks - 30:
		s.advance_week()
	s.mission_completed.emit({"type": "comet_mission", "target": "comet", "success": true, "outcome": "full", "science": 900.0})
	_clear_popups()
	for i in 30:
		s.advance_week()
	await _frames(20)
	if main.hud.current_screen() == "finale":
		await _frames(260)   # let the finale sequence play
		await _shot("race_06_finale")
	await _open("final_score")
	await _frames(90)
	await _shot("race_07_score")
	await _open("race")
	await _shot("race_08_race_end")
	print("RACE SCREENSHOTS DONE")
	quit()


func _clear_popups() -> void:
	main.state.race.pending_pages.clear()
	main.hud.close_screen()


func _open(screen: String, args := {}) -> void:
	if not main.hud.open_screen(screen, args):
		print("no screen %s yet" % screen)
	await _frames(30)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
