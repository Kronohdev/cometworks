extends SceneTree
## Headless checks for the patched-conic core (src/flight/flight_conic.gd, flight_solar.gd,
## flight_trajectory.gd, flight_maneuvers.gd):
##   1. FlightConic agrees with the universal-variable propagator (ellipse, hyperbola, Sun)
##   2. energy and angular momentum are constant along every predicted conic
##   3. solar system: SOI radii from the data, Sun direction at t = 0 == the flight sky's
##   4. a Hohmann transfer from LEO aimed at the Moon gives a Moon encounter (SOI entry,
##      segment around the Moon with a periapsis), and leaves / impacts consistently
##   5. a hyperbolic escape from LEO ends in an ESCAPE and continues around the Sun with a
##      continuous heliocentric state
##   6. maneuver node: a prograde burn at periapsis raises the apoapsis exactly as vis-viva
##      predicts; a radial / normal burn changes the plane / shape as expected
##   7. node time dragging: clamping (past, neighbours), the burn moved to apoapsis raises
##      the periapsis instead, picking a sample point returns its time
##   8. timing: prediction cost for LEO, the Moon transfer and an interplanetary plan
## Run: godot --headless --path . --script res://tests/test_flight_conics.gd

const R := FlightOrbit.R
const MU := FlightOrbit.MU

var _failures := 0
var sys: FlightSolar


func _initialize() -> void:
	sys = FlightSolar.get_system()
	var t0 := Time.get_ticks_msec()
	_test_conic_vs_universal()
	_test_energy_along_conics()
	_test_system()
	_test_moon_encounter()
	_test_escape()
	_test_prograde_burn()
	_test_node_drag()
	_test_timing()
	print("time %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1


static func sci(x: float) -> String:
	return String.num_scientific(x)


static func v3(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func dist(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2]))


## Circular LEO state in the Moon's plane at angle th (rad) from the plane's P axis.
func leo_state(alt: float, th: float, speed_k := 1.0) -> Array[PackedFloat64Array]:
	var r := R + alt
	var p := sys.plane_p[sys.moon]
	var q := sys.plane_q[sys.moon]
	var vc := sqrt(MU / r) * speed_k
	var pos := PackedFloat64Array([r * (cos(th) * p[0] + sin(th) * q[0]), r * (cos(th) * p[1] + sin(th) * q[1]),
		r * (cos(th) * p[2] + sin(th) * q[2])])
	var vel := PackedFloat64Array([vc * (-sin(th) * p[0] + cos(th) * q[0]), vc * (-sin(th) * p[1] + cos(th) * q[1]),
		vc * (-sin(th) * p[2] + cos(th) * q[2])])
	return [pos, vel]


# ------------------------------------------------------------ 1
func _test_conic_vs_universal() -> void:
	print("conic vs universal-variable propagation")
	var cases := [
		["LEO ellipse 200 x 3000 km", PackedFloat64Array([R + 200000.0, 0, 0]), PackedFloat64Array([0, 0, -8300.0]), MU],
		["hyperbola e~1.6", PackedFloat64Array([R + 300000.0, 0, 0]), PackedFloat64Array([0, 1000.0, -13500.0]), MU],
		["heliocentric 1 AU x 1.5 AU", PackedFloat64Array([1.496e11, 0, 0]), PackedFloat64Array([0, 0, -32700.0]), sys.mu[sys.sun]],
	]
	for cs in cases:
		var r0: PackedFloat64Array = cs[1]
		var v0: PackedFloat64Array = cs[2]
		var gm: float = cs[3]
		var c := FlightConic.from_state(r0, v0, gm, 100.0)
		var worst := 0.0
		var worst_v := 0.0
		for dt in [0.0, 60.0, 1234.5, 20000.0, 3.0e5, 4.0e6]:
			var a := c.state_at(100.0 + dt)
			var b := FlightOrbit.propagate(r0, v0, dt, gm)
			worst = maxf(worst, dist(a, b) / maxf(FlightOrbit.length(PackedFloat64Array([b[0], b[1], b[2]])), 1.0))
			worst_v = maxf(worst_v, Vector3(a[3] - b[3], a[4] - b[4], a[5] - b[5]).length())
		print("  %s e=%.4f  max rel. position diff %s, max velocity diff %s m/s" % [cs[0], c.e, sci(worst), sci(worst_v)])
		_check(worst < 1e-8 and worst_v < 1e-3, "%s matches" % cs[0])


# ------------------------------------------------------------ 2
func _test_energy_along_conics() -> void:
	print("energy / angular momentum along predicted conics")
	var s := leo_state(200000.0, 0.3, 1.38)
	var tr := FlightTrajectory.predict(sys, sys.earth, s[0], s[1], 0.0)
	var worst_e := 0.0
	var worst_h := 0.0
	var n := 0
	for seg in tr.segments:
		var c := seg.conic
		for i in range(0, seg.count(), 7):
			var st := c.state_at(seg.times[i])
			var r := Vector3(st[0], st[1], st[2])
			var rn := sqrt(st[0] * st[0] + st[1] * st[1] + st[2] * st[2])
			var en := (st[3] * st[3] + st[4] * st[4] + st[5] * st[5]) * 0.5 - c.mu / rn
			var h := r.cross(Vector3(st[3], st[4], st[5])).length()
			worst_e = maxf(worst_e, absf(en - c.energy) / absf(c.energy))
			worst_h = maxf(worst_h, absf(h - sqrt(c.p * c.mu)) / sqrt(c.p * c.mu))
			n += 1
	print("  %d segments, %d states: energy err %s, h err %s" % [tr.segments.size(), n, sci(worst_e), sci(worst_h)])
	_check(worst_e < 1e-9 and worst_h < 1e-6, "energy and angular momentum conserved along every conic")


# ------------------------------------------------------------ 3
func _test_system() -> void:
	print("solar system data")
	var soi_e := sys.soi[sys.earth]
	var soi_m := sys.soi[sys.moon]
	print("  SOI Earth %.0f km (expected ~924 000), Moon %.0f km (~66 100), Mars %.0f km, Jupiter %.0f km" % [
		soi_e / 1000.0, soi_m / 1000.0, sys.soi[sys.index_of("mars")] / 1000.0, sys.soi[sys.index_of("jupiter")] / 1000.0])
	_check(absf(soi_e - 9.24e8) / 9.24e8 < 0.01 and absf(soi_m - 6.61e7) / 6.61e7 < 0.01, "SOI radii from a (m/M)^(2/5)")
	var sun := sys.pos_rel(sys.sun, sys.earth, 0.0)
	var dir := v3(sun).normalized()
	var want := FlightSolar.SUN_DIR.normalized()
	print("  Sun direction at t=0 %s vs sky %s (%.4f deg), distance %.4f AU" % [dir, want,
		rad_to_deg(dir.angle_to(want)), FlightOrbit.length(sun) / 1.495978707e11])
	_check(dir.angle_to(want) < 1e-4, "Sun where the flight sky draws it at t = 0")
	var mars := sys.index_of("mars")
	var lead := rad_to_deg(v3(sys.pos_rel_parent(sys.earth, 0.0)).normalized().signed_angle_to(
		v3(sys.pos_rel_parent(mars, 0.0)).normalized(), sys.ecliptic_normal))
	var pe := sys.pos_rel_parent(sys.earth, 0.0)
	var pm := sys.pos_rel_parent(mars, 0.0)
	print("  Mars leads Earth by %.1f deg at the epoch (Hohmann window at 44.3 deg); |E| %.4f AU |M| %.4f AU" % [lead,
		FlightOrbit.length(pe) / 1.495978707e11, FlightOrbit.length(pm) / 1.495978707e11])
	var st := sys.state_rel_parent(sys.moon, 1000.0)
	var dp := sys.pos_rel_parent(sys.moon, 1000.5)
	var dm := sys.pos_rel_parent(sys.moon, 999.5)
	var vnum := Vector3(dp[0] - dm[0], dp[1] - dm[1], dp[2] - dm[2])
	_check(vnum.distance_to(Vector3(st[3], st[4], st[5])) < 1e-3, "body velocity == d(position)/dt")


# ------------------------------------------------------------ 4
func _test_moon_encounter() -> void:
	print("Moon encounter (Hohmann from 200 km LEO)")
	var r1 := R + 200000.0
	var r2 := sys.sma[sys.moon]
	var at := (r1 + r2) * 0.5
	var t_tr := PI * sqrt(at * at * at / MU)
	# the vessel starts opposite the Moon's position at arrival
	var th_moon := sys.phase[sys.moon] + sys.rate[sys.moon] * t_tr
	var vp := sqrt(MU * (2.0 / r1 - 1.0 / at))
	var s := leo_state(200000.0, th_moon - PI, vp / sqrt(MU / r1))
	var tr := FlightTrajectory.predict(sys, sys.earth, s[0], s[1], 0.0)
	var desc := ""
	for seg in tr.segments:
		desc += "[%s %s %.1f h]" % [sys.ids[seg.body], FlightTrajectory.End.keys()[seg.end], (seg.t1 - seg.t0) / 3600.0]
	print("  transfer %.1f h, segments %s, %.1f ms" % [t_tr / 3600.0, desc, tr.compute_ms])
	var enc := tr.encounter_summary(sys)
	_check(not enc.is_empty() and int(enc.get("body", -1)) == sys.moon, "Moon encounter found")
	if enc.is_empty():
		return
	var seg0 := tr.segments[0]
	var entry := seg0.conic.position_at(seg0.t1)
	var moon_at := sys.pos_rel_parent(sys.moon, seg0.t1)
	var d_entry := dist(entry, moon_at)
	print("  SOI entry at T+%.1f h, distance to the Moon %.1f km (SOI %.1f km), periapsis %.1f km at T+%.1f h" % [
		seg0.t1 / 3600.0, d_entry / 1000.0, sys.soi[sys.moon] / 1000.0, float(enc["pe_alt"]) / 1000.0,
		float(enc["t_pe"]) / 3600.0])
	_check(absf(d_entry - sys.soi[sys.moon]) < 50.0, "entry point on the SOI sphere (bisection < 50 m)")
	_check(seg0.t1 < t_tr and seg0.t1 > t_tr * 0.7, "entry before the nominal arrival")
	# the state at entry: Moon-relative state + Moon state == Earth-relative state
	var s1 := tr.segments[1]
	var st_m := s1.conic.state_at(s1.t0)
	var mo := sys.state_rel_parent(sys.moon, s1.t0)
	var st_e := seg0.conic.state_at(seg0.t1)
	var dv := Vector3(st_m[3] + mo[3] - st_e[3], st_m[4] + mo[4] - st_e[4], st_m[5] + mo[5] - st_e[5]).length()
	_check(dv < 1e-6 and s1.body == sys.moon, "frame change at the SOI boundary is continuous (dv %s m/s)" % sci(dv))
	# closest approach to the target before the encounter
	var tr2 := FlightTrajectory.predict(sys, sys.earth, s[0], s[1], 0.0, [], sys.moon)
	_check(not tr2.closest.is_empty() and float(tr2.closest["d"]) < sys.soi[sys.moon],
		"closest approach to the target Moon recorded (%.0f km)" % (float(tr2.closest.get("d", INF)) / 1000.0))
	# a miss: aim 60 degrees late -> no encounter, Earth orbit only
	var s_miss := leo_state(200000.0, th_moon - PI + 1.0, vp / sqrt(MU / r1))
	var tr3 := FlightTrajectory.predict(sys, sys.earth, s_miss[0], s_miss[1], 0.0)
	_check(tr3.encounter_summary(sys).is_empty(), "a mistimed transfer misses the Moon")


# ------------------------------------------------------------ 5
func _test_escape() -> void:
	print("Earth escape -> Sun-centric segment")
	var r1 := R + 200000.0
	var s := leo_state(200000.0, 1.0, 1.2 * sqrt(2.0))
	var tr := FlightTrajectory.predict(sys, sys.earth, s[0], s[1], 0.0)
	var desc := ""
	for seg in tr.segments:
		desc += "[%s %s %.1f d]" % [sys.ids[seg.body], FlightTrajectory.End.keys()[seg.end], (seg.t1 - seg.t0) / 86400.0]
	print("  v = 1.2 v_esc at %.0f km: %s (%.1f ms)" % [(r1 - R) / 1000.0, desc, tr.compute_ms])
	_check(tr.segments.size() >= 2 and tr.segments[0].end == FlightTrajectory.End.ESCAPE, "first segment escapes")
	if tr.segments.size() < 2:
		return
	var s0 := tr.segments[0]
	var s1 := tr.segments[1]
	_check(s1.body == sys.sun, "continues around the Sun")
	var a := s0.conic.state_at(s0.t1)
	var e := sys.state_rel(sys.earth, sys.sun, s0.t1)
	var b := s1.conic.state_at(s1.t0)
	var dp := Vector3(a[0] + e[0] - b[0], a[1] + e[1] - b[1], a[2] + e[2] - b[2]).length()
	var dv := Vector3(a[3] + e[3] - b[3], a[4] + e[4] - b[4], a[5] + e[5] - b[5]).length()
	print("  escape after %.2f d at %.0f km; heliocentric state jump %.3f m, %s m/s; helio a = %.3f AU, e = %.3f" % [
		s0.t1 / 86400.0, FlightOrbit.length(PackedFloat64Array([a[0], a[1], a[2]])) / 1000.0, dp, sci(dv),
		s1.conic.a / 1.495978707e11, s1.conic.e])
	_check(dp < 1.0 and dv < 1e-6, "heliocentric state continuous at the SOI exit")
	_check(absf(FlightOrbit.length(PackedFloat64Array([a[0], a[1], a[2]])) - sys.soi[sys.earth]) < 1.0, "exit exactly on the SOI sphere")


# ------------------------------------------------------------ 6
func _test_prograde_burn() -> void:
	print("maneuver node: prograde burn at periapsis (vis-viva)")
	var rp := R + 200000.0
	var ra := R + 1000000.0
	var a := (rp + ra) * 0.5
	var vp := sqrt(MU * (2.0 / rp - 1.0 / a))
	var p := sys.plane_p[sys.moon]
	var q := sys.plane_q[sys.moon]
	var r0 := PackedFloat64Array([rp * p[0], rp * p[1], rp * p[2]])
	var v0 := PackedFloat64Array([vp * q[0], vp * q[1], vp * q[2]])
	var c := FlightConic.from_state(r0, v0, MU, 0.0)
	var plan := FlightManeuvers.new()
	var dvp := 250.0
	plan.add(c.period, Vector3(dvp, 0, 0))  # one revolution later = at periapsis again
	var tr := FlightTrajectory.predict(sys, sys.earth, r0, v0, 0.0, plan.nodes)
	var after: FlightTrajectory.Segment = null
	for seg in tr.segments:
		if seg.plan == 1:
			after = seg
			break
	_check(after != null, "planned segment after the node")
	if after == null:
		return
	var v_new := vp + dvp
	var a_new := 1.0 / (2.0 / rp - v_new * v_new / MU)
	var ra_new := 2.0 * a_new - rp
	print("  Ap %.3f km -> predicted %.3f km, vis-viva %.3f km (diff %.3f m); Pe %.3f km" % [
		(ra - R) / 1000.0, (after.conic.ra - R) / 1000.0, (ra_new - R) / 1000.0, after.conic.ra - ra_new,
		(after.conic.rp - R) / 1000.0])
	_check(absf(after.conic.ra - ra_new) < 5.0 and absf(after.conic.rp - rp) < 1.0, "Ap raised as vis-viva predicts (< 5 m of 2 067 km), Pe unchanged")
	var nd := plan.first()
	_check(nd.valid and nd.body == sys.earth and absf(FlightOrbit.length(nd.dv_world) - dvp) < 1e-6, "node filled by the predictor")
	# normal burn: plane change of atan(dv / v) at the node
	plan.set_dv(nd, Vector3(0, 300.0, 0))
	tr = FlightTrajectory.predict(sys, sys.earth, r0, v0, 0.0, plan.nodes)
	var seg1: FlightTrajectory.Segment = null
	for seg in tr.segments:
		if seg.plan == 1:
			seg1 = seg
	var w0 := Vector3(c.wx, c.wy, c.wz)
	var w1 := Vector3(seg1.conic.wx, seg1.conic.wy, seg1.conic.wz)
	var inc := rad_to_deg(w0.angle_to(w1))
	var want := rad_to_deg(atan(300.0 / vp))
	print("  normal 300 m/s: inclination change %.4f deg (expected %.4f)" % [inc, want])
	_check(absf(inc - want) < 1e-3, "normal burn tilts the plane by atan(dv / v)")
	# radial out burn at periapsis: rotates the apsides, energy up by dv²/2
	plan.set_dv(nd, Vector3(0, 0, 200.0))
	tr = FlightTrajectory.predict(sys, sys.earth, r0, v0, 0.0, plan.nodes)
	for seg in tr.segments:
		if seg.plan == 1:
			seg1 = seg
	var de := seg1.conic.energy - c.energy
	_check(absf(de - 200.0 * 200.0 * 0.5) < 1e-3, "radial burn adds dv^2/2 of energy (%.3f J/kg)" % de)


# ------------------------------------------------------------ 7
func _test_node_drag() -> void:
	print("maneuver node time dragging")
	var rp := R + 200000.0
	var ra := R + 1000000.0
	var a := (rp + ra) * 0.5
	var vp := sqrt(MU * (2.0 / rp - 1.0 / a))
	var p := sys.plane_p[sys.moon]
	var q := sys.plane_q[sys.moon]
	var r0 := PackedFloat64Array([rp * p[0], rp * p[1], rp * p[2]])
	var v0 := PackedFloat64Array([vp * q[0], vp * q[1], vp * q[2]])
	var c := FlightConic.from_state(r0, v0, MU, 0.0)
	var plan := FlightManeuvers.new()
	var n1 := plan.add(c.period, Vector3(100.0, 0, 0))
	var n2 := plan.add(c.period * 3.0, Vector3(50.0, 0, 0))
	var now := 100.0
	plan.set_time(n1, -500.0, now)
	_check(absf(n1.time - (now + FlightManeuvers.MIN_LEAD)) < 1e-6, "cannot drag into the past (%.1f s)" % n1.time)
	plan.set_time(n1, c.period * 10.0, now)
	_check(n1.time < n2.time and absf(n1.time - (n2.time - 1.0)) < 1e-6, "cannot jump over the next node")
	# from periapsis to apoapsis: the same prograde burn now raises the periapsis
	plan.remove(n2)
	plan.set_time(n1, c.period, now)
	var tr := FlightTrajectory.predict(sys, sys.earth, r0, v0, 0.0, plan.nodes)
	var at_pe := _after(tr)
	plan.set_time(n1, c.period * 1.5, now)
	tr = FlightTrajectory.predict(sys, sys.earth, r0, v0, 0.0, plan.nodes)
	var at_ap := _after(tr)
	print("  burn at Pe: Ap %.1f km Pe %.1f km;  dragged to Ap: Ap %.1f km Pe %.1f km" % [
		(at_pe.ra - R) / 1000.0, (at_pe.rp - R) / 1000.0, (at_ap.ra - R) / 1000.0, (at_ap.rp - R) / 1000.0])
	_check(at_ap.rp > rp + 100000.0 and absf(at_ap.ra - ra) < 2.0, "after the drag the burn raises Pe, Ap stays")
	# picking: a stored sample maps back to its own time
	var seg := tr.segments[0]
	var k := seg.count() / 3
	var hit := FlightManeuvers.nearest_on_segment(seg, seg.point(k))
	var t_pick := FlightManeuvers.time_on_segment(seg, int(hit["i"]), float(hit["f"]))
	_check(absf(t_pick - seg.times[k]) < 1e-3, "picking a trajectory point returns its time (%.3f s off)" % (t_pick - seg.times[k]))
	var mono := true
	for i in seg.count() - 1:
		if seg.times[i + 1] < seg.times[i]:
			mono = false
	_check(mono, "sample times increase along the segment")


func _after(tr: FlightTrajectory) -> FlightConic:
	for seg in tr.segments:
		if seg.plan == 1:
			return seg.conic
	return tr.segments[0].conic


# ------------------------------------------------------------ 8
func _test_timing() -> void:
	print("prediction cost")
	var s := leo_state(200000.0, 0.0)
	var t0 := Time.get_ticks_usec()
	for i in 10:
		FlightTrajectory.predict(sys, sys.earth, s[0], s[1], 0.0)
	var leo_ms := (Time.get_ticks_usec() - t0) / 10000.0
	var r1 := R + 200000.0
	var r2 := sys.sma[sys.moon]
	var at := (r1 + r2) * 0.5
	var t_tr := PI * sqrt(at * at * at / MU)
	var vp := sqrt(MU * (2.0 / r1 - 1.0 / at))
	var sm := leo_state(200000.0, sys.phase[sys.moon] + sys.rate[sys.moon] * t_tr - PI, vp / sqrt(MU / r1))
	t0 = Time.get_ticks_usec()
	for i in 10:
		FlightTrajectory.predict(sys, sys.earth, sm[0], sm[1], 0.0)
	var moon_ms := (Time.get_ticks_usec() - t0) / 10000.0
	var se := leo_state(200000.0, 1.0, 1.2 * sqrt(2.0))
	t0 = Time.get_ticks_usec()
	for i in 5:
		FlightTrajectory.predict(sys, sys.earth, se[0], se[1], 0.0)
	var esc_ms := (Time.get_ticks_usec() - t0) / 5000.0
	t0 = Time.get_ticks_usec()
	for i in 5:
		FlightTrajectory.predict(sys, sys.earth, se[0], se[1], 0.0, [], -1, 0.4)
	var drag_ms := (Time.get_ticks_usec() - t0) / 5000.0
	print("  LEO %.2f ms, Moon transfer %.2f ms, escape + heliocentric year %.2f ms (drag quality %.2f ms)" % [
		leo_ms, moon_ms, esc_ms, drag_ms])
	_check(leo_ms < 20.0 and moon_ms < 60.0, "predictions are cheap enough to cache and refresh on edits")
