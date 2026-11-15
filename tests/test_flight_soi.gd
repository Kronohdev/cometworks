extends SceneTree
## Headless checks of the patched conics, warp and maneuver nodes in the running flight view
## (scenes/flight/flight.tscn, FlightWorld on a FlightRun):
##   1. physics steps: a craft falling into the Moon's SOI switches its central body to the
##      Moon with a continuous Earth-relative state
##   2. on-rails warp (1000x) along the predicted conics: leaving the Moon's SOI hands the
##      craft back to the Earth where the prediction said
##   3. maneuver node + executor: a 60 m/s prograde node in LEO is burned by the autopilot and
##      the resulting apoapsis matches the planned one
##   4. warp-to-node stops just before the burn
## Run: godot --headless --path . --script res://tests/test_flight_soi.gd

const DT := 0.02

var _failures := 0
var world: FlightWorld
var sys: FlightSolar


func _initialize() -> void:
	FlightSession.clear()
	FlightSession.set_vessel(load("res://scenes/examples/garca.tscn"), ExampleVessels.display_name("garca"), 0.0)
	world = (load(FlightSession.FLIGHT_SCENE) as PackedScene).instantiate()
	get_root().add_child(world)
	await process_frame
	await process_frame
	sys = world.sys
	world.set_process(false)
	var c := world.sim.craft
	var evs: Array = []
	while c.current_stage < c.stage_count - 1:
		c.next_stage(evs)
	c.throttle = 0.0
	world.sim.limits = false
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
	var s := world.sim
	var o := sys.state_rel(s.body, sys.earth, s.t)
	return PackedFloat64Array([s.px + o[0], s.py + o[1], s.pz + o[2], s.vx + o[3], s.vy + o[4], s.vz + o[5]])


func _test_physics_soi() -> void:
	print("physics: falling into the Moon's SOI")
	var s := world.sim
	var t := s.t
	var m := sys.state_rel_parent(sys.moon, t)
	var dir := Vector3(m[0], m[1], m[2]).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var start := Vector3(m[0], m[1], m[2]) - dir * (sys.soi[sys.moon] + 1500000.0) + side * 8000000.0
	var vel := Vector3(m[3], m[4], m[5]) + dir * 900.0
	s.set_orbit_state(sys.earth, PackedFloat64Array([start.x, start.y, start.z]), PackedFloat64Array([vel.x, vel.y, vel.z]))
	var before := _earth_state()
	var steps := 0
	var jump := 0.0
	while s.body == sys.earth and steps < 200000:
		var a := _earth_state()
		s.step(1.0)
		var b := _earth_state()
		jump = Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]).length()
		steps += 1
	print("  %d s to the Moon's SOI, last step %.1f m (Earth frame)" % [steps, jump])
	_check(s.body == sys.moon, "the Moon holds the craft now")
	_check(jump < 3000.0, "continuous across the switch")
	_check(before.size() == 6, "state readable")


func _test_rails_escape() -> void:
	print("rails: leaving the Moon's SOI at 1000x")
	world.time = world.sim.t
	world._traj_dirty = true
	world._update_trajectory(0.0)
	var ev := world.traj.next_event(world.time)
	var escape := not ev.is_empty() and int(ev["kind"]) == FlightTrajectory.End.ESCAPE
	_check(escape, "prediction: the craft leaves the Moon's SOI")
	if not escape:
		return
	var t_exit: float = ev["t"]
	var seg: FlightTrajectory.Segment = world.traj.segments[int(ev["seg"])]
	var exit_state := seg.conic.state_at(t_exit)
	var o := sys.state_rel(sys.moon, sys.earth, t_exit)
	world.warp = 1000
	_check(world.rails_allowed(), "rails allowed above the surface with the engines off")
	var frames := 0
	while world.sim.body == sys.moon and frames < 20000:
		world._advance(1.0 / 60.0)
		frames += 1
	_check(world.sim.on_rails, "it coasted on rails")
	var st := _earth_state()
	var c := FlightConic.from_state(PackedFloat64Array([exit_state[0] + o[0], exit_state[1] + o[1], exit_state[2] + o[2]]),
		PackedFloat64Array([exit_state[3] + o[3], exit_state[4] + o[4], exit_state[5] + o[5]]), sys.mu[sys.earth], t_exit)
	var now := c.state_at(world.sim.t)
	var err := Vector3(st[0] - now[0], st[1] - now[1], st[2] - now[2]).length()
	print("  %d frames, now around %s; position vs prediction %.3f m" % [frames, sys.ids[world.sim.body], err])
	_check(world.sim.body == sys.earth, "back in the Earth's SOI")
	_check(err < 50.0, "rails follow the predicted patched conics (< 50 m)")
	world.warp = 1


func _test_executor() -> void:
	print("maneuver node executed by the autopilot (LEO, 60 m/s prograde)")
	var r := FlightOrbit.R + 200000.0
	var vc := sqrt(FlightOrbit.MU / r)
	var east := FlightWorld.EAST.normalized()
	var s := world.sim
	s.set_orbit_state(sys.earth, PackedFloat64Array([0.0, r, 0.0]), PackedFloat64Array([east.x * vc, 0.0, east.z * vc]))
	s.craft.throttle = 0.0
	world.time = s.t
	world.plan.clear()
	var n := world.plan.add(s.t + 120.0, Vector3(60.0, 0.0, 0.0))
	world._traj_dirty = true
	world._update_trajectory(0.0)
	var planned := 0.0
	for seg in world.traj.segments:
		if seg.plan == 1:
			planned = seg.conic.ra - FlightOrbit.R
			break
	world.set_executor(true)
	world._warp_to = -1.0
	var frames := 0
	var dv0 := s.craft.dv_used
	while world.plan.nodes.has(n) and frames < 20000:
		world._advance(1.0 / 60.0)
		world._update_nodes()
		frames += 1
	var el := s.elements()
	var ap: float = el["ap_alt"]
	print("  burn done after %d frames: Δv used %.2f m/s, Ap %.1f km (planned %.1f km), Pe %.1f km" % [frames,
		s.craft.dv_used - dv0, ap / 1000.0, planned / 1000.0, float(el["pe_alt"]) / 1000.0])
	_check(not world.plan.nodes.has(n), "node completed and removed")
	_check(planned > 0.0 and absf(ap - planned) / planned < 0.02, "apoapsis within 2 % of the plan")
	_check(world.executor == null and world.run.guide == null, "the executor let go")
	await process_frame


func _test_warp_to() -> void:
	print("warp to node")
	world.sim.craft.throttle = 0.0
	world.plan.clear()
	var n := world.plan.add(world.time + 2000.0, Vector3(20.0, 0.0, 0.0))
	world._traj_dirty = true
	world._update_trajectory(0.0)
	world.warp_to_next_node()
	var target := world._warp_to
	var frames := 0
	while world._warp_to > 0.0 and frames < 20000:
		world._update_warp_to(1.0 / 60.0)
		world._advance(1.0 / 60.0)
		frames += 1
	var left := n.time - world.time
	print("  %d frames, stopped %.1f s before the node (target %.1f s before), warp now %dx" % [frames, left,
		n.time - target, world.current_warp()])
	_check(absf(world.time - target) < 1.0 and world.current_warp() == 1, "stopped at the warp-to target, 1x")
