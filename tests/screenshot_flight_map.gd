extends SceneTree
## Windowed screenshots of the solar-system map and the maneuver nodes (Garça in a 200 km
## parking orbit, placed directly - the ascent has its own script):
##   map_01_vessel        the vessel's orbit (scale 1)
##   map_02_earth_moon    Earth-Moon system (scale 2)
##   map_03_node_moon     a trans-lunar node selected (gizmo), dashed post-burn path,
##                        Moon encounter with periapsis, Moon targeted (closest / AN-DN)
##   map_04_node_close    the same node seen up close (handles, info tag, panel)
##   map_05_solar         whole solar system (scale 3)
##   map_06_escape        an escape node: Earth escape -> heliocentric segment (dashed)
##   map_07_moon          after executing the node and warping on rails into the Moon's SOI
##   flight_11_navball_node  flight view: maneuver marker on the navball + burn countdown
## Also prints GPU time of the map viewport, prediction cost, the executed burn and the
## SOI change. Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_flight_map.gd -- <out_dir> [only]

var out_dir := "user://"
var only := ""
var world: FlightWorld
var sys: FlightSolar


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		only = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	FlightSession.set_vessel(load("res://scenes/examples/garca.tscn"), ExampleVessels.display_name("garca"), 0.0)
	world = (load(FlightSession.FLIGHT_SCENE) as PackedScene).instantiate()
	get_root().add_child(world)
	await _frames(20)
	sys = world.sys
	_to_parking_orbit()
	await _frames(10)
	world.set_map(true)
	await _frames(40)
	await _measure("map vessel")
	await _shot("map_01_vessel")
	world.map.set_scale_mode(1)
	await _frames(60)
	await _measure("map earth-moon")
	await _shot("map_02_earth_moon")
	# trans-lunar injection node, aimed for a ~300 km flyby
	var n := _plan_tli()
	world.target_body = sys.moon
	world._traj_dirty = true
	world.map.select_node(n)
	world.map._refresh_names()
	await _frames(40)
	var enc := world.traj.encounter_summary(sys, 1)
	print("TLI node: T+%.0f s, Δv %.1f m/s, encounter %s, prediction %.2f ms" % [n.time - world.time, n.dv.x,
		str(enc), world.traj.compute_ms])
	world.map.yaw = 0.35
	world.map.pitch = 0.95
	world.map.dist = 9.5e5
	await _frames(60)
	await _shot("map_03_node_moon")
	# up close, looking at the node from its side of the Earth
	world.map.set_focus(sys.earth)
	world.map.dist = 20000.0
	world.map.pitch = 0.1
	world.map.face_direction(Vector3(n.state[0], n.state[1], n.state[2]).normalized().rotated(sys.orbit_normal(sys.moon), 0.3))
	await _frames(70)
	await _shot("map_04_node_close")
	world.map.set_scale_mode(2)
	await _frames(70)
	await _measure("map solar")
	await _shot("map_05_solar")
	# escape plan (a second plan on a copy: remove the TLI, add an escape burn)
	var keep := n.dv
	world.plan.set_dv(n, Vector3(3900.0, 0.0, 0.0))
	world.map.set_focus(sys.earth)
	world.map.dist = 2.4e7
	world.map.pitch = 1.1
	await _frames(70)
	var desc := ""
	for s in world.traj.segments:
		desc += "[%s %s]" % [sys.ids[s.body], FlightTrajectory.End.keys()[s.end]]
	print("escape plan: %s" % desc)
	await _shot("map_06_escape")
	world.plan.set_dv(n, keep)
	await _frames(5)
	# flight view: point at the node, the navball shows the maneuver marker
	world.set_map(false)
	world.active.set_sas(FlightVessel.Sas.DIRECTION)
	var rem := n.remaining_world()
	# a little off the node, so the navball shows the maneuver marker next to the centre
	world.active.sas_dir = rem.normalized().rotated(world.active.body.up(), 0.22).rotated(rem.normalized().cross(world.active.body.up()).normalized(), 0.12)
	world.cam.set_view(-2.4, 0.2, 40.0, true)
	world.debug_warp = 4.0
	await _frames(400)
	world.debug_warp = 1.0
	await _frames(20)
	await _shot("flight_11_navball_node")
	# execute: warp to the node, burn, then warp on rails into the Moon's SOI
	if only != "fast":
		await _execute_and_coast()
	print("MAP SCREENSHOTS DONE")
	quit()


## 200 km circular orbit in the launch plane (= the Moon's plane), eastward.
func _to_parking_orbit() -> void:
	var r := FlightOrbit.R + 200000.0
	var v := sqrt(FlightOrbit.MU / r)
	var up := Vector3.UP
	var east := FlightWorld.EAST.normalized()
	world.set_orbit_state(sys.earth, PackedFloat64Array([up.x * r, up.y * r, up.z * r]),
		PackedFloat64Array([east.x * v, east.y * v, east.z * v]))
	world.active.body.q = Quaternion(Vector3.UP, east)
	world.active.prev.copy_from(world.active.body)
	world.active.throttle = 0.0
	# only the upper stage made it to orbit
	while world.active.current_stage < world.active.stage_count - 1:
		for d in world.active.activate_next_stage():
			d.queue_free()
	world.active.throttle = 0.0
	world.active.set_sas(FlightVessel.Sas.PROGRADE)
	# the auto-end after orbit would show the report: keep flying
	world._orbit_announced = true


## Hohmann departure towards the Moon from the current circular orbit, refined so the
## predicted lunar periapsis is a few hundred km.
func _plan_tli() -> FlightManeuverNode:
	var b := world.active.body
	var r1 := b.radius()
	var r2 := sys.sma[sys.moon]
	var at := (r1 + r2) * 0.5
	var t_tr := PI * sqrt(at * at * at / FlightOrbit.MU)
	var n_v := sqrt(FlightOrbit.MU / (r1 * r1 * r1))
	var p := sys.plane_p[sys.moon]
	var q := sys.plane_q[sys.moon]
	var th_v := atan2(b.px * q[0] + b.py * q[1] + b.pz * q[2], b.px * p[0] + b.py * p[1] + b.pz * p[2])
	var th_m := sys.phase[sys.moon] + sys.rate[sys.moon] * (world.time + t_tr)
	var dth := fposmod(th_m - PI - th_v - sys.rate[sys.moon] * 0.0, TAU)
	var dt := dth / (n_v - sys.rate[sys.moon])
	if dt < 600.0:
		dt += TAU / (n_v - sys.rate[sys.moon])
	var dv := sqrt(FlightOrbit.MU * (2.0 / r1 - 1.0 / at)) - sqrt(FlightOrbit.MU / r1)
	var n := world.plan.add(world.time + dt, Vector3(dv, 0, 0))
	# refine: aim the flyby periapsis at ~300 km by nudging the node time
	var best := 1e18
	var best_t := n.time
	for k in range(-40, 41):
		var tt := world.time + dt + k * 12.0
		world.plan.set_time(n, tt, world.time)
		var tr := FlightTrajectory.predict(sys, world.soi, b.pos(), b.vel(), world.time, world.plan.nodes, -1, 0.6)
		var e := tr.encounter_summary(sys, 1)
		if e.is_empty():
			continue
		var pe: float = e["pe_alt"]
		var score := absf(pe - 300000.0)
		if pe > 50000.0 and score < best:
			best = score
			best_t = tt
	world.plan.set_time(n, best_t, world.time)
	return n


func _execute_and_coast() -> void:
	var n := world.plan.first()
	var t_node := n.time
	world.set_executor(true)
	# physics warp 4x during the long upper-stage burn (players can do the same with , .)
	await _until(func() -> bool: return world.time > t_node - world.node_burn_time(n) * 0.5 - 2.0, 60.0)
	world.debug_warp = 4.0
	var t0 := Time.get_ticks_msec()
	while world.plan.nodes.has(n) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
		if world.time > t_node + 4000.0:
			break
	world.debug_warp = 1.0
	print("executor: node done %s at T%+.0f s, Δv used %.1f m/s, soi %s" % [not world.plan.nodes.has(n),
		world.time - t_node, world.active.dv_used, sys.ids[world.soi]])
	await _frames(10)
	var el := world._elements()
	var enc := world.traj.encounter_summary(sys) if world.traj else {}
	print("after the burn: Ap %.0f km Pe %.0f km, encounter %s" % [float(el["ap_alt"]) / 1000.0, float(el["pe_alt"]) / 1000.0, str(enc)])
	if enc.is_empty() or float(enc["pe_alt"]) < 50000.0:
		# a 7-minute burn is not impulsive: plan a mid-course correction one hour out
		var best := {}
		var best_score := 1e18
		var b := world.active.body
		var cn := world.plan.add(world.time + 3600.0)
		for pro in [-12.0, -8.0, -5.0, -3.0, -1.5, 0.0, 1.5, 3.0, 5.0, 8.0, 12.0]:
			for rad in [-20.0, -10.0, -4.0, 0.0, 4.0, 10.0, 20.0]:
				world.plan.set_dv(cn, Vector3(pro, 0.0, rad))
				var tr := FlightTrajectory.predict(sys, world.soi, b.pos(), b.vel(), world.time, world.plan.nodes, -1, 0.5)
				var e := tr.encounter_summary(sys, 1)
				if e.is_empty():
					continue
				var score := absf(float(e["pe_alt"]) - 400000.0) + Vector2(pro, rad).length() * 2000.0
				if float(e["pe_alt"]) > 60000.0 and score < best_score:
					best_score = score
					best = {"dv": Vector3(pro, 0.0, rad), "e": e}
		if best.is_empty():
			print("no correction found")
			world.plan.remove(cn)
			return
		world.plan.set_dv(cn, best["dv"])
		print("mid-course correction: %s m/s -> %s" % [str(best["dv"]), str(best["e"])])
		world.set_map(true)
		world.map.set_focus(sys.earth)
		world.map.select_node(cn)
		world.map.dist = 8.0e5
		world.map.pitch = 1.0
		await _frames(60)
		await _shot("map_07a_correction")
		world.set_map(false)
		world.set_executor(true)
		t0 = Time.get_ticks_msec()
		while world.plan.nodes.has(cn) and Time.get_ticks_msec() - t0 < 120000:
			await process_frame
		await _frames(10)
		enc = world.traj.encounter_summary(sys) if world.traj else {}
		print("after the correction: encounter %s" % str(enc))
		if enc.is_empty():
			return
	# rails warp until inside the Moon's SOI
	world.warp_to(float(enc["t_enter"]) + 3600.0)
	t0 = Time.get_ticks_msec()
	while world.soi != sys.moon and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await _frames(30)
	world._set_warp_value(1)
	print("SOI now %s at T+%.0f s; Moon altitude %.0f km" % [sys.ids[world.soi], world.time, world.active.body.altitude() / 1000.0])
	world.set_map(true)
	world.map.set_focus(sys.moon)
	world.map.dist = 2.2e5
	world.map.pitch = 0.7
	await _frames(80)
	await _shot("map_07_moon")
	# down to the lunar periapsis on rails, then the flight view looking down at the Moon
	var pe := world.traj.segments[0].conic.time_at_true_anomaly(0.0, world.time) if world.traj else INF
	if pe < INF:
		world.warp_to(pe - 900.0)
		var t1 := Time.get_ticks_msec()
		while world._warp_to > 0.0 and Time.get_ticks_msec() - t1 < 60000:
			await process_frame
	world.set_map(false)
	world.active.set_sas(FlightVessel.Sas.PROGRADE)
	world.cam.set_view(-2.0, 0.55, 60.0, true)
	await _frames(90)
	print("near the Moon: altitude %.0f km, speed %.0f m/s" % [world.active.body.altitude() / 1000.0, world.active.body.speed()])
	await _shot("flight_12_near_moon")


func _until(cond: Callable, timeout_s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
		await process_frame


func _measure(tag: String) -> void:
	var vp := (world.map.get_node("%MapViewport") as SubViewport).get_viewport_rid()
	var main := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	RenderingServer.viewport_set_measure_render_time(main, true)
	await _frames(10)
	var gpu := 0.0
	var proc := 0.0
	var n := 60
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp) + RenderingServer.viewport_get_measured_render_time_gpu(main)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("%s: gpu %.2f ms, fps %.1f, draws %d, prims %d" % [tag, gpu / n, n / ((Time.get_ticks_usec() - t0) / 1e6),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved %s" % path)
