extends SceneTree
## Headless checks of the patched conics inside the running flight scene
## (scenes/flight/flight.tscn, FlightWorld):
##   1. physics steps: a vessel falling into the Moon's SOI switches its central body to the
##      Moon, with a continuous Earth-relative state, and the gravity / altitude follow
##   2. on-rails warp (1000x) along the predicted conics: leaving the Moon's SOI hands the
##      vessel back to the Earth exactly where the prediction said
##   3. maneuver node + executor: a 60 m/s prograde node in LEO is burned by the autopilot
##      and the resulting apoapsis matches the planned one
##   4. warp-to-node stops just before the burn
## Run: godot --headless --path . --script res://tests/test_flight_soi.gd

const DT := 0.02

var _failures := 0
var world: FlightWorld
var sys: FlightSolar


func _initialize() -> void:
	FlightSession.set_vessel(load("res://scenes/examples/garca.tscn"), ExampleVessels.display_name("garca"), 0.0)
	world = (load(FlightSession.FLIGHT_SCENE) as PackedScene).instantiate()
	get_root().add_child(world)
	await process_frame
	await process_frame
	sys = world.sys
	world.set_process(false)
	while world.active.current_stage < world.active.stage_count - 1:
		for d in world.active.activate_next_stage():
			d.queue_free()
	world.active.throttle = 0.0
	world._orbit_announced = true
	var t0 := Time.get_ticks_msec()
	_test_physics_soi()
	_test_rails_escape()
	await _test_executor()
	_test_warp_to()
	print("time %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1


func _earth_state() -> PackedFloat64Array:
	var b := world.active.body
	var o := sys.state_rel(world.soi, sys.earth, world.time)
	return PackedFloat64Array([b.px + o[0], b.py + o[1], b.pz + o[2], b.vx + o[3], b.vy + o[4], b.vz + o[5]])


func _test_physics_soi() -> void:
	print("physics: falling into the Moon's SOI")
	var t := world.time
	var m := sys.state_rel_parent(sys.moon, t)
	var dir := Vector3(m[0], m[1], m[2]).normalized()
	# 1 500 km outside the SOI on the Earth side, closing at 900 m/s, aimed 8 000 km off the
	# centre (a flyby with a periapsis ~3 000 km above the surface)
	var d := sys.soi[sys.moon] + 1.5e6
	var side := dir.cross(sys.orbit_normal(sys.moon)).normalized() * 8.0e6
	var r := PackedFloat64Array([m[0] - dir.x * d + side.x, m[1] - dir.y * d + side.y, m[2] - dir.z * d + side.z])
	var v := PackedFloat64Array([m[3] + dir.x * 900.0, m[4] + dir.y * 900.0, m[5] + dir.z * 900.0])
	world.set_orbit_state(sys.earth, r, v)
	var before := PackedFloat64Array()
	var after := PackedFloat64Array()
	var steps := 0
	while world.soi == sys.earth and steps < 200000:
		before = _earth_state()
		world._step(DT)
		steps += 1
	after = _earth_state()
	print("  switched after %.0f s of physics: soi %s, |r| %.0f km (SOI %.0f km), body mu %s" % [steps * DT,
		sys.ids[world.soi], world.active.body.radius() / 1000.0, sys.soi[sys.moon] / 1000.0, String.num_scientific(world.active.body.mu)])
	_check(world.soi == sys.moon, "central body is the Moon")
	_check(absf(world.active.body.radius() - sys.soi[sys.moon]) < 2000.0, "switch happened at the SOI boundary")
	_check(world.active.body.mu == sys.mu[sys.moon] and not world.active.body.atmosphere, "gravity and air follow the Moon")
	var dv := Vector3(after[3] - before[3], after[4] - before[4], after[5] - before[5]).length()
	_check(dv < 1.0, "Earth-relative velocity continuous across the switch (%.3f m/s in one step)" % dv)


func _test_rails_escape() -> void:
	print("rails: leaving the Moon's SOI at 1000x")
	world._traj_dirty = true
	world._update_trajectory(0.0)
	var ev := world.traj.next_event(world.time)
	_check(not ev.is_empty() and int(ev["kind"]) == FlightTrajectory.End.ESCAPE, "prediction: the vessel leaves the Moon's SOI")
	if ev.is_empty():
		return
	var t_exit: float = ev["t"]
	var seg: FlightTrajectory.Segment = world.traj.segments[int(ev["seg"])]
	var exit_state := seg.conic.state_at(t_exit)
	var o := sys.state_rel(sys.moon, sys.earth, t_exit)
	world._set_warp_value(1000)
	_check(world.on_rails, "on rails above the surface with the engines off")
	var frames := 0
	while world.soi == sys.moon and frames < 20000:
		world._simulate(1.0 / 60.0)
		frames += 1
	var st := _earth_state()
	var expect := PackedFloat64Array([exit_state[0] + o[0], exit_state[1] + o[1], exit_state[2] + o[2]])
	# the exit happened inside the last frame: propagate the expectation to now
	var c := FlightConic.from_state(PackedFloat64Array([expect[0], expect[1], expect[2]]),
		PackedFloat64Array([exit_state[3] + o[3], exit_state[4] + o[4], exit_state[5] + o[5]]), sys.mu[sys.earth], t_exit)
	var now := c.state_at(world.time)
	var err := Vector3(st[0] - now[0], st[1] - now[1], st[2] - now[2]).length()
	print("  %d frames, now around %s at T+%.0f s (exit predicted at T+%.0f s); position vs prediction %.3f m" % [
		frames, sys.ids[world.soi], world.time, t_exit, err])
	_check(world.soi == sys.earth, "back in the Earth's SOI")
	_check(err < 50.0, "rails follow the predicted patched conics (< 50 m)")
	world._set_warp_value(1)


func _test_executor() -> void:
	print("maneuver node executed by the autopilot (LEO, 60 m/s prograde)")
	var r := FlightOrbit.R + 200000.0
	var vc := sqrt(FlightOrbit.MU / r)
	var east := FlightWorld.EAST.normalized()
	world.set_orbit_state(sys.earth, PackedFloat64Array([0.0, r, 0.0]), PackedFloat64Array([east.x * vc, 0.0, east.z * vc]))
	world.active.body.q = Quaternion(Vector3.UP, east)
	world.active.prev.copy_from(world.active.body)
	world.active.throttle = 0.0
	world.plan.clear()
	var n := world.plan.add(world.time + 120.0, Vector3(60.0, 0.0, 0.0))
	world._traj_dirty = true
	world._update_trajectory(0.0)
	var planned := 0.0
	for s in world.traj.segments:
		if s.plan == 1:
			planned = s.conic.ra - FlightOrbit.R
			break
	world.set_executor(true)
	world._warp_to = -1.0
	var steps := 0
	while world.plan.nodes.has(n) and steps < 60000:
		world._step(DT)
		world._update_nodes()
		steps += 1
	var el := world._elements()
	var ap: float = el["ap_alt"]
	print("  burn done after %.0f s: Δv used %.2f m/s, Ap %.1f km (planned %.1f km), Pe %.1f km" % [steps * DT,
		world.active.dv_used, ap / 1000.0, planned / 1000.0, float(el["pe_alt"]) / 1000.0])
	_check(not world.plan.nodes.has(n), "node completed and removed")
	_check(absf(ap - planned) / planned < 0.02, "apoapsis within 2 % of the plan")
	await process_frame


func _test_warp_to() -> void:
	print("warp to node")
	world.active.throttle = 0.0
	world.plan.clear()
	var n := world.plan.add(world.time + 2000.0, Vector3(20.0, 0.0, 0.0))
	world._traj_dirty = true
	world._update_trajectory(0.0)
	world.warp_to_next_node()
	var target := world._warp_to
	var frames := 0
	while world._warp_to > 0.0 and frames < 20000:
		world._update_warp_to(1.0 / 60.0)
		world._simulate(1.0 / 60.0)
		frames += 1
	var left := n.time - world.time
	print("  %d frames, stopped %.1f s before the node (target %.1f s before), warp now %dx" % [frames, left,
		n.time - target, world.current_warp()])
	_check(absf(world.time - target) < 1.0 and world.current_warp() == 1, "stopped at the warp-to target, 1x")
