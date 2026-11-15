extends SceneTree
## Windowed screenshots of Cometlings with memory (CrewMemory) on the crew sheet:
##   memory_01_sheet     a veteran's sheet: milestone chips, totals and the missions they flew
##   memory_02_sheet_en  the same in English
##   memory_03_new       a Cometling with no missions yet (the empty milestones line)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_crew_memory.gd -- <out_dir>

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
	s.cash = 5.0e6
	var vet := String(s.staff[0]["id"])
	# a few real launches (they also fill the sheet's mission list), then a long career on paper;
	# the review and pad gates stay off for them (no screens open in between)
	var gates := [s.review_gate, s.pilot_gate]
	s.review_gate = false
	s.pilot_gate = false
	for o in ["success", "fail", "partial", "success"]:
		var p := ProjectDesk.start_project(s, "sounding", "suborbital", [vet])
		if p:
			ProjectDesk.dev_force_outcome = o
			ProjectDesk.dev_finish_development(s, p.id)
	ProjectDesk.dev_force_outcome = ""
	s.review_gate = gates[0]
	s.pilot_gate = gates[1]
	var fake := [["DEM-01", "demo_sat", "leo", true, "full"], ["ORB-01", "orbiter", "lunar_orbit", true, "exceptional"],
		["LND-01", "lander", "lunar_surface", false, "fail"], ["LND-02", "lander", "lunar_surface", false, "fail"],
		["LND-03", "lander", "lunar_surface", true, "full"], ["COM-01", "comms", "geo", true, "full"]]
	for f: Array in fake:
		CrewMemory.record(s, [vet], {"code": f[0], "type": f[1], "target": f[2], "success": f[3], "outcome": f[4],
			"novelty": false, "week": s.weeks})
	s.changed.emit()
	main.hud.open_screen("crew")
	var scr := main.hud.get_node("%Screens").get_child(0) as CrewScreen
	await _frames(30)
	scr.select_member(vet)
	await _frames(20)
	# scroll the sheet's right column down to the milestones
	var scroll := scr.get_node("Layout/Pages/Sheet/Right/Scroll") as ScrollContainer
	var ms := scr.get_node("%Milestones") as Control
	await _frames(20)
	if scroll and ms:
		scroll.scroll_vertical = int(ms.position.y) - 40
	await _frames(30)
	await _shot("memory_01_sheet")
	TranslationServer.set_locale("en")
	scr.refresh()
	await _frames(30)
	await _shot("memory_02_sheet_en")
	TranslationServer.set_locale("pt_BR")
	scr.go_back()
	scr.select_member(String(s.staff[s.staff.size() - 1]["id"]))
	await _frames(30)
	if scroll and ms:
		scroll.scroll_vertical = int(ms.position.y) - 40
	await _frames(20)
	await _shot("memory_03_new")
	print("CREW MEMORY SCREENSHOTS DONE")
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
