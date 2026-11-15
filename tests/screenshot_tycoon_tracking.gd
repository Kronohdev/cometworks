extends SceneTree
## Windowed screenshots of the missions in space (SpaceTracking, TycoonModes):
##   tracking_01_campus        the campus with the Solar System map key
##   tracking_02_map_system    the Solar System map: the Earth–Moon system, several missions
##                             (ours and the rivals'), their paths and the list
##   tracking_03_map_selected  a lunar mission selected (followed, its whole path, its card)
##   tracking_04_map_leo       a craft in low orbit selected, zoomed in
##   tracking_05_follow        "Acompanhar": that craft up close in the 3D flight
##   tracking_05b_follow_moon  a craft in lunar orbit up close
##   tracking_06_watch_pad     the launch watch on the pad (countdown)
##   tracking_07_watch_ascent  the watched launch climbing
##   tracking_08_watch_orbit   the watched launch in orbit (result card)
##   tracking_09_watch_fail    a watched failed launch breaking up
##   tracking_10_watch_lost    its result card (Lançamento perdido)
##   tracking_11_review        the review with "Acompanhar o lançamento"
##   tracking_12_watch_wait    a lunar launch in its parking orbit, waiting for the departure burn
##   tracking_13_watch_transfer  after the burn: on the way to the Moon (result card)
##   tracking_14_watch_transfer_map  the flight's map: the transfer meeting the Moon
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_tracking.gd -- <out_dir> [en|pt]

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
	await _frames(60)
	await _shot("tracking_01_campus")
	_seed_missions(s)
	main.modes.open_space_map()
	await _frames(90)
	await _shot("tracking_02_map_system")
	var ov := main.modes.overlay as SpaceMapOverlay
	ov.select("p:LUA1")
	await _frames(70)
	await _shot("tracking_03_map_selected")
	ov.select("p:SAT1")
	await _frames(70)
	await _shot("tracking_04_map_leo")
	ov.watch_selected()
	await _frames(90)
	await _shot("tracking_05_follow")
	(main.modes.mode_node as FlightWorld).revert_to_hangar()   # back to the map
	await _frames(20)
	ov = main.modes.overlay as SpaceMapOverlay
	ov.select("p:LUA0")
	await _frames(30)
	ov.watch_selected()
	await _frames(90)
	await _shot("tracking_05b_follow_moon")
	(main.modes.mode_node as FlightWorld).revert_to_hangar()   # back to the map
	await _frames(20)
	if main.modes.kind == "map":
		(main.modes.mode_node as FlightWorld).revert_to_hangar()   # back to the campus
	await _frames(20)
	# the launch watch of a good launch
	main.hud.open_screen("project_review", {"project_id": "SAT2"})
	await _frames(40)
	await _shot("tracking_11_review")
	main.modes.open_watch("SAT2")
	await _frames(30)
	await _shot("tracking_06_watch_pad")
	var w := main.modes.mode_node as FlightWorld
	await _frames(240)
	w.debug_warp = 1.0
	await _until(func() -> bool: return w.mission_time() > 40.0, 1200)
	await _shot("tracking_07_watch_ascent")
	w.warp = 50
	await _until(func() -> bool: return (main.modes.overlay as LaunchWatch).get_node("%Result").visible, 4000)
	w.warp = 1
	await _frames(20)
	await _shot("tracking_08_watch_orbit")
	w.revert_to_hangar()
	await _frames(20)
	main.hud.close_screen()
	await _frames(10)
	# a failed one
	main.modes.open_watch("ORB9")
	await _frames(10)
	var w2 := main.modes.mode_node as FlightWorld
	var lw := main.modes.overlay as LaunchWatch
	await _until(func() -> bool: return lw.phase == "ascent", 600)
	w2.warp = 4
	await _until(func() -> bool: return w2.sim.crashed, 3000)
	w2.warp = 1
	await _frames(14)
	await _shot("tracking_09_watch_fail")
	await _until(func() -> bool: return lw.get_node("%Result").visible, 900)
	await _frames(20)
	await _shot("tracking_10_watch_lost")
	w2.revert_to_hangar()
	await _frames(20)
	# to the Moon: the departure burn, then the transfer on the flight's own map
	main.modes.open_watch("LUA1")
	await _frames(10)
	var w3 := main.modes.mode_node as FlightWorld
	var lw3 := main.modes.overlay as LaunchWatch
	await _until(func() -> bool: return lw3.phase == "ascent", 600)
	w3.warp = 50
	await _until(func() -> bool: return lw3.phase == "wait", 6000)
	await _frames(30)
	await _shot("tracking_12_watch_wait")
	await _until(func() -> bool: return lw3.phase == "transfer", 6000)
	w3.warp = 1
	await _until(func() -> bool: return lw3.get_node("%Result").visible, 900)
	await _frames(10)
	await _shot("tracking_13_watch_transfer")
	lw3.get_node("%Result").visible = false
	w3.set_map(true)
	w3.map.set_scale_mode(1, true)
	await _frames(60)
	await _shot("tracking_14_watch_transfer_map")
	quit()


## A campaign a year in: our missions to every kind of place (one lunar craft on its way, one
## lander down, one launch lost) and the rivals' milestones.
func _seed_missions(s: TycoonState) -> void:
	s.weeks = 60
	var now := SpaceTracking.now(s)
	var add := func(pid: String, code: String, type_id: String, target: String, outcome: String, t0: float) -> void:
		var trk := SpaceTracking.build(SpaceTracking.PLAYER, "p:" + pid, code, type_id, target, outcome, t0)
		trk["project_id"] = pid
		SpaceTracking.missions(s).append(trk)
		s.project_history.append({"id": pid, "code": code, "type": type_id, "target": target, "outcome": outcome,
			"success": outcome != "fail", "week": int(t0 / SpaceTracking.WEEK), "grade": 7.5, "grade_project": 7.5,
			"bars": [6.0, 7.0, 6.5, 7.0], "reviews": [], "rewards": {}, "rocket": {},
			"cause_key": "TY_RK_RISK_STAGE2" if outcome == "fail" else ""})
	add.call("SAT1", "ORB-01", "demo_sat", "leo", "full", now - 30.0 * SpaceTracking.WEEK)
	add.call("SAT2", "ORB-02", "earth_obs", "sso", "full", now - 12.0 * SpaceTracking.WEEK)
	add.call("COM1", "COM-01", "comms", "geo", "full", now - 8.0 * SpaceTracking.WEEK)
	add.call("LUA1", "LUA-01", "orbiter", "lunar_orbit", "full", now - 2.6 * 86400.0)
	add.call("LUA0", "LUA-00", "orbiter", "lunar_orbit", "full", now - 3.0 * SpaceTracking.WEEK)
	add.call("POU1", "POU-01", "lander", "lunar_surface", "full", now - 5.0 * SpaceTracking.WEEK)
	add.call("ORB9", "ORB-03", "demo_sat", "leo", "fail", now - 3.0 * SpaceTracking.WEEK)
	s.race.claim("first_satellite", "aurora")
	s.race.claim("first_satellite", "nimbo")
	s.race.claim("probe_moon", "quietude")
	SpaceTracking.sync(s)
	for trk: Dictionary in SpaceTracking.missions(s):
		if String(trk["owner"]) != SpaceTracking.PLAYER:
			# their launches happened over the last months
			var back := (3.0 + SpaceTracking.hash01(String(trk["id"])) * 20.0) * SpaceTracking.WEEK
			var rebuilt := SpaceTracking.build(String(trk["owner"]), String(trk["id"]), String(trk["code"]),
				String(trk["type"]), String(trk["target"]), String(trk["outcome"]), now - back)
			trk.merge(rebuilt, true)


func _until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
