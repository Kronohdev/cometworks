extends SceneTree
## Windowed screenshots of the Cometworks flight HUD (the Garça, flown by hand with scripted
## steering, so the first-flight tips and the "do this now" coach show up):
##   hud_01_pad           on the pad: goal card, gauges, stage stickers, the engine-lever tip
##   hud_02_ignite        the ignition tip pointing at the staging key
##   hud_03_turn          climbing: the turn-east tip on the navball (also checks D turns east)
##   hud_04_stage         stage 1 burned out: the "drop the empty stage" tip and coach
##   hud_05_space         upper stage near space with "More data" open
##   hud_06_map           the map in a parking orbit with a trans-lunar node (markers, labels)
##   hud_07_report        a mission flight's end-of-flight card (hands back to the campus)
##   hud_08_report_lost   the card after a breakup
## Also checks that every HUD block stays inside the window and that the blocks do not overlap.
## Tips are forced on and nothing is written to the settings.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_flight_hud.gd -- <out_dir> [suffix]

var out_dir := "user://"
var suffix := ""
var world: FlightWorld
var fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		suffix = "_" + args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	FlightTips.force = true
	FlightTips.persist = false
	TranslationServer.set_locale("pt")
	await _manual()
	await _map()
	await _report_mission()
	await _report_lost()
	print("FLIGHT HUD SHOTS DONE (%d layout problems)" % fails)
	quit()


func _start(mission := {}, mission_mode := false) -> void:
	if world and is_instance_valid(world):
		world.queue_free()
		await process_frame
	FlightSession.clear()
	FlightSession.mission = mission
	FlightSession.set_vessel(load("res://scenes/examples/garca.tscn"), ExampleVessels.display_name("garca"), 0.0)
	world = (load(FlightSession.FLIGHT_SCENE) as PackedScene).instantiate()
	world.embedded = mission_mode
	world.mission_mode = mission_mode
	get_root().add_child(world)
	await _frames(2)
	world.hud.get_node("%Tip").call("restart")
	await _frames(28)


func _manual() -> void:
	await _start()
	world.cam.set_view(2.6, 0.04, 72.0, true)
	await _frames(30)
	_check_layout("pad")
	await _shot("hud_01_pad")
	var tips: FlightTips = world.hud.get_node("%Tip")
	print("tip on the pad: %s" % tips.current)
	tips.complete(tips.current)
	await _frames(10)
	print("then: %s" % tips.current)
	await _shot("hud_02_ignite")
	world.stage()
	world.sim.craft.sas = FlightCraft.Sas.HOLD
	world.cam.set_view(2.3, 0.05, 110.0, true)
	await _until(func() -> bool: return world.sim.altitude() > 700.0, 40.0)
	await _frames(12)
	print("tip climbing: %s, coach %s" % [tips.current, world.hud.get("_now_key")])
	await _shot("hud_03_turn")
	# W tips the nose east (pitch input -1 = W)
	var h0 := _heading()
	world.scripted_input = Vector3(-1, 0, 0)
	await _until(func() -> bool: return world.hud.get("_pitch") < 77.0, 8.0)
	world.scripted_input = Vector3.ZERO
	world.sim.craft.sas = FlightCraft.Sas.HOLD
	await _frames(10)
	print("tilted: coach %s" % world.hud.get("_now_key"))
	var b := world.sim
	await _until(func() -> bool: return rad_to_deg(asin(b.vertical_speed() / maxf(b.speed(), 1.0))) < world.hud.get("_pitch") + 1.5, 30.0)
	await _frames(4)
	print("caught up: coach %s" % world.hud.get("_now_key"))
	world.sim.craft.sas = FlightCraft.Sas.PROGRADE
	await _frames(10)
	print("W: heading %.0f -> %.0f, pitch %.0f (east = 90)" % [h0, _heading(), world.hud.get("_pitch")])
	# burn the first stage dry (prograde hold), boosters drop by themselves
	world.debug_warp = 6.0
	await _until(func() -> bool: return FlightTips.stage_empty(world._telemetry()) or world.sim.crashed, 120.0)
	world.debug_warp = 1.0
	world.cam.set_view(-2.2, 0.2, 90.0, true)
	await _frames(20)
	print("stage empty: tip %s, coach %s, alt %.1f km" % [tips.current, world.hud.get("_now_key"), world.sim.altitude() / 1000.0])
	_check_layout("stage")
	await _shot("hud_04_stage")
	world.stage()
	world.set_autopilot(true)
	world.debug_warp = 10.0
	await _until(func() -> bool: return world.sim.altitude() > 95000.0 or world.sim.crashed, 160.0)
	world.debug_warp = 1.0
	world.hud.set_tele_collapsed(false)
	world.cam.set_view(-2.5, 0.24, 40.0, true)
	await _frames(30)
	_check_layout("space")
	await _shot("hud_05_space")
	world.hud.set_tele_collapsed(true)


func _map() -> void:
	await _start()
	var sys := world.sys
	var r := FlightOrbit.R + 200000.0
	var v := sqrt(FlightOrbit.MU / r)
	var up := Vector3.UP
	var east := FlightWorld.EAST.normalized()
	world.sim.set_orbit_state(sys.earth, PackedFloat64Array([up.x * r, up.y * r, up.z * r]),
		PackedFloat64Array([east.x * v, east.y * v, east.z * v]))
	world.sim.q = Quaternion(Vector3.UP, east)
	pass
	while world.sim.craft.current_stage < world.sim.craft.stage_count - 1:
		world.sim.stage()
	world.sim.craft.throttle = 0.0
	world.sim.craft.sas = FlightCraft.Sas.PROGRADE
	world.sim.in_orbit = true
	await _frames(10)
	var n := world.plan.add(world.time + 1500.0, Vector3(3120.0, 0, 0))
	world.target_body = sys.moon
	world._traj_dirty = true
	world.set_map(true)
	await _frames(60)
	_check_layout("map")
	await _shot("hud_06_map")
	world.map.set_scale_mode(1)
	world.map.select_node(n)
	world.map._refresh_names()
	world.map.pitch = 0.9
	await _frames(90)
	await _shot("hud_06b_map_moon")
	world.set_map(false)


func _report_mission() -> void:
	var m := {"title": "SAT-1 · Satélite de demonstração", "target": "Órbita baixa", "target_id": "leo",
		"dv_needed": 9400.0, "payload_kg": 300.0, "goal": "entrar numa órbita estável", "type_id": "demo_sat"}
	await _start(m, true)
	world.stage()
	world.set_autopilot(true)
	world.debug_warp = 20.0
	await _until(func() -> bool: return world.ended or world.sim.crashed, 300.0)
	world.debug_warp = 1.0
	await _until(func() -> bool: return world.ended, 20.0)
	await _frames(30)
	_check_inside(world.hud.get_node("%Report").get_node("Center/Panel"), "report")
	await _shot("hud_07_report")


func _report_lost() -> void:
	await _start()
	world.stage()
	world.sim.craft.sas = FlightCraft.Sas.OFF
	await _until(func() -> bool: return world.mission_time() > 8.0, 30.0)
	world.debug_warp = 2.0
	world.scripted_input = Vector3(-1, 0, 0.3)
	await _until(func() -> bool: return world.sim.crashed or world.mission_time() > 90.0, 90.0)
	world.scripted_input = Vector3.ZERO
	world.debug_warp = 1.0
	await _until(func() -> bool: return world.ended, 10.0)
	await _frames(30)
	_check_inside(world.hud.get_node("%Report").get_node("Center/Panel"), "lost report")
	await _shot("hud_08_report_lost")


func _heading() -> float:
	var t := world._telemetry()
	var up: Vector3 = t["up"]
	var e: Vector3 = t["east"]
	var north := up.cross(e).normalized()
	e = north.cross(up).normalized()
	var nose: Vector3 = t["nose"]
	return fposmod(rad_to_deg(atan2(nose.dot(e), nose.dot(north))), 360.0)


## Every visible HUD block inside the window, and the blocks clear of each other.
func _check_layout(tag: String) -> void:
	var hud := world.hud
	var names := ["LeftColumn", "TopStrip", "StagesPanel", "NavCluster"]
	if hud.get_node("%Tip").visible:
		names.append("Tip")
	if hud.get_node("%Maneuver").visible:
		names.append("Maneuver")
	var rects := {}
	for n in names:
		var c := hud.get_node("Root/" + n) as Control
		if c == null or not c.is_visible_in_tree():
			continue
		_check_inside(c, "%s %s" % [tag, n])
		if n != "Tip":
			rects[n] = c.get_global_rect().grow(-2.0)
	var keys := rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				fails += 1
				print("  LAYOUT %s: %s overlaps %s" % [tag, keys[i], keys[j]])
	var bar := world.map.get_node("%MapBar") as Control
	if bar.is_visible_in_tree():
		_check_inside(bar, tag + " MapBar")
		for n in rects:
			if bar.get_global_rect().grow(-2.0).intersects(rects[n]):
				fails += 1
				print("  LAYOUT %s: MapBar overlaps %s" % [tag, n])


func _check_inside(c: Control, tag: String) -> void:
	var root := world.hud.get_node("Root") as Control
	var view := Rect2(Vector2.ZERO, root.size).grow(1.0)
	var r := c.get_global_rect()
	if not view.encloses(r):
		fails += 1
		print("  LAYOUT %s outside the window: %s (view %s)" % [tag, r, view])


func _until(cond: Callable, timeout_s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + suffix + ".png")
	img.save_png(path)
	print("saved %s" % path)
