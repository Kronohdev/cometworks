extends SceneTree
## Headless checks for the flight simulation (src/flight/):
##   1. integrator: a circular 200 km orbit stays circular for one full revolution and
##      ends where the analytic Kepler propagation says
##   2. Kepler propagation: energy and angular momentum conserved over 10 orbits
##   3. staging: FlightStaging puts every Garça part in the same stage as the hangar's
##      Vessel.compute_stages(); the flight drops 2 boosters, then 1 stage, in that order
##   4. rocket equation: burns in vacuum without gravity reproduce the hangar's per-stage
##      vacuum Δv (VesselMath) within 2 %, and mass bookkeeping balances to the kilogram
##   5. full ascent: the auto-ascent flies Garça from the pad to orbit (Pe > 140 km)
## Run: godot --headless --path . --script res://tests/test_flight.gd

const DT := 0.02
const GARCA := "res://scenes/examples/garca.tscn"

var _failures := 0
var _world: Node3D


func _initialize() -> void:
	await process_frame
	_world = Node3D.new()
	get_root().add_child(_world)
	var t0 := Time.get_ticks_msec()
	_test_orbit()
	_test_kepler()
	_test_staging()
	_test_rocket_equation()
	_test_ascent()
	print("time %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1


func _garca() -> FlightVessel:
	var fv := FlightVessel.new()
	_world.add_child(fv)
	fv.setup_from_scene(load(GARCA))
	return fv


# ------------------------------------------------------------ 1. integrator
func _test_orbit() -> void:
	print("orbit integrator (circular 200 km, dt %.3f s)" % DT)
	var r := FlightOrbit.R + 200000.0
	var vc := sqrt(FlightOrbit.MU / r)
	var b := FlightBody.new()
	b.set_state(FlightOrbit.vec(0, r, 0), FlightOrbit.vec(vc, 0, 0))
	var period := TAU * sqrt(r * r * r / FlightOrbit.MU)
	var n := int(round(period / DT))
	var rmin := INF
	var rmax := -INF
	for i in n:
		b.step(DT, 0.0, 0.0, 0.0)
		var rr := b.radius()
		rmin = minf(rmin, rr)
		rmax = maxf(rmax, rr)
	var ref := FlightOrbit.propagate(FlightOrbit.vec(0, r, 0), FlightOrbit.vec(vc, 0, 0), n * DT)
	var err := Vector3(b.px - ref[0], b.py - ref[1], b.pz - ref[2]).length()
	print("  period %.1f s, %d steps; radius %.2f .. %.2f m from nominal; end vs Kepler %.2f m" % [
		period, n, rmin - r, rmax - r, err])
	_check(rmax - r < 5.0 and r - rmin < 5.0, "radius within 5 m over one orbit")
	_check(err < 50.0, "final position within 50 m of the analytic orbit")
	var el := FlightOrbit.elements(b.pos(), b.vel())
	_check(absf(float(el["ap_alt"]) - 200000.0) < 20.0 and absf(float(el["pe_alt"]) - 200000.0) < 20.0,
		"Ap/Pe still 200 km (%.1f / %.1f m off)" % [float(el["ap_alt"]) - 200000.0, float(el["pe_alt"]) - 200000.0])


# ------------------------------------------------------------ 2. Kepler
func _test_kepler() -> void:
	print("kepler propagation (elliptic 200 x 2000 km)")
	var rp := FlightOrbit.R + 200000.0
	var ra := FlightOrbit.R + 2000000.0
	var a := (rp + ra) * 0.5
	var vp := sqrt(FlightOrbit.MU * (2.0 / rp - 1.0 / a))
	var r0 := FlightOrbit.vec(rp, 0, 0)
	var v0 := FlightOrbit.vec(0, 0, -vp)
	var el0 := FlightOrbit.elements(r0, v0)
	var period: float = el0["period"]
	var s := FlightOrbit.propagate(r0, v0, period * 10.0 + 1234.5)
	var r1 := FlightOrbit.vec(s[0], s[1], s[2])
	var v1 := FlightOrbit.vec(s[3], s[4], s[5])
	var el1 := FlightOrbit.elements(r1, v1)
	var de := absf(float(el1["energy"]) - float(el0["energy"])) / absf(float(el0["energy"]))
	var dh := absf(FlightOrbit.length(el1["h"]) - FlightOrbit.length(el0["h"])) / FlightOrbit.length(el0["h"])
	var back := FlightOrbit.propagate(r0, v0, period)
	var dp := Vector3(back[0] - r0[0], back[1] - r0[1], back[2] - r0[2]).length()
	print("  energy err %.3f ppb, h err %.3f ppb, one-period return %.3f m, Ap %.1f km Pe %.1f km" % [
		de * 1e9, dh * 1e9, dp, float(el0["ap_alt"]) / 1000.0, float(el0["pe_alt"]) / 1000.0])
	_check(de < 1e-9 and dh < 1e-9 and dp < 1.0, "Kepler propagation conserves the orbit")


# ------------------------------------------------------------ 3. staging
func _test_staging() -> void:
	print("staging (Garça)")
	var v := Vessel.new()
	_world.add_child(v)
	v.load_scene(load(GARCA))
	var st := v.compute_stages()
	var gs := FlightStaging.groups(v)
	var mismatch := 0
	var counted := 0
	for si in st["stage_parts"].size():
		for p: PartInstance in st["stage_parts"][si]:
			counted += 1
			var found := -1
			for g in gs:
				if (g["parts"] as Array).has(p):
					found = g["stage"]
			if found != si:
				mismatch += 1
	var boosters := 0
	for g in gs:
		if g["kind"] == "booster":
			boosters += 1
	print("  hangar stages %d, flight stages %d, parts %d, mismatches %d, booster groups %d" % [
		st["stage_parts"].size(), FlightStaging.stage_count(gs), counted, mismatch, boosters])
	_check(mismatch == 0 and FlightStaging.stage_count(gs) == st["stage_parts"].size(), "flight stages == hangar stages")
	_check(boosters == 2, "two booster groups")
	v.queue_free()


# ------------------------------------------------------------ 4. rocket equation + mass
func _test_rocket_equation() -> void:
	print("rocket equation (vacuum, no gravity)")
	var fv := _garca()
	var hv := Vessel.new()
	_world.add_child(hv)
	hv.load_scene(load(GARCA))
	var an := hv.analyze()
	hv.queue_free()
	var m0_hangar: float = an["stages"][0]["m0_kg"]
	_check(absf(fv.mass - m0_hangar) < 1.0, "liftoff mass %.1f kg == hangar %.1f kg" % [fv.mass, m0_hangar])
	var prop_total := 0.0
	for p in fv.prop0:
		prop_total += float(fv.prop0[p])
	var m_start := fv.mass
	fv.body.set_state(FlightOrbit.vec(0, FlightOrbit.R + 3.0e6, 0), FlightOrbit.vec(0, 0, 0))
	fv.body.gravity_on = false
	fv.place_on_pad(3.0e6, Vector3.UP, Vector3.BACK)
	fv.body.gravity_on = false
	fv.clamped = false
	fv.landed = false
	fv.set_sas(FlightVessel.Sas.HOLD)
	var debris: Array[FlightVessel] = []
	var events: Array[String] = []
	fv.flight_event.connect(func(k: String, _d: Dictionary) -> void: events.append(k))
	fv.activate_next_stage()
	var dvs: Array[float] = []
	for s in fv.stage_count:
		var v_start := fv.body.velocity_v3()
		var burning := false
		var t := 0.0
		while t < 3000.0:
			debris.append_array(fv.physics_step(DT))
			t += DT
			if fv.thrust_n > 0.0:
				burning = true
			elif burning:
				break
		dvs.append((fv.body.velocity_v3() - v_start).length())
		if s < fv.stage_count - 1:
			debris.append_array(fv.activate_next_stage())
	for i in dvs.size():
		var exp_dv: float = an["stages"][i]["dv_vac"]
		var err := absf(dvs[i] - exp_dv) / exp_dv
		print("  stage %d: sim %.1f m/s, hangar vac %.1f m/s (%.2f %%)" % [i + 1, dvs[i], exp_dv, err * 100.0])
		_check(err < 0.02, "stage %d Δv matches the rocket equation" % (i + 1))
	# mass bookkeeping: everything that is not burned propellant is still somewhere
	var burned := 0.0
	var all: Array[FlightVessel] = [fv]
	all.append_array(debris)
	var m_all := 0.0
	for b in all:
		m_all += b.mass
		for p in b.prop0:
			if b.vessel.is_ancestor_of(p):
				burned += float(b.prop0[p]) - float(b.prop[p])
	print("  start %.1f kg = now %.1f kg (%d bodies) + burned %.1f kg (diff %.3f kg); prop loaded %.0f kg" % [
		m_start, m_all, all.size(), burned, m_start - m_all - burned, prop_total])
	_check(absf(m_start - m_all - burned) < 1.0, "mass balance")
	var order := ",".join(events.filter(func(e: String) -> bool: return e in ["EV_BOOSTER_SEP", "EV_STAGE_SEP"]))
	print("  events: " + order)
	_check(order == "EV_BOOSTER_SEP,EV_BOOSTER_SEP,EV_STAGE_SEP", "boosters drop first, then the stage")
	var dry := 0.0
	for p in fv.parts:
		dry += p.dry_mass()
	_check(absf(fv.mass - dry) < 1.0, "upper stage burned dry: %.1f kg == dry %.1f kg" % [fv.mass, dry])
	for b in all:
		b.queue_free()


# ------------------------------------------------------------ 5. ascent
func _test_ascent() -> void:
	print("auto-ascent (Garça, pad -> orbit)")
	var fv := _garca()
	var hv := Vessel.new()
	_world.add_child(hv)
	hv.load_scene(load(GARCA))
	var predicted: float = hv.analyze()["ascent_dv"]
	hv.queue_free()
	var east := Vector3(0.894, 0, -0.447).normalized()
	fv.place_on_pad(12.7, Vector3.UP, -east)
	var ap := FlightAutopilot.new(Vector3.UP, east, 200000.0)
	var t := 0.0
	var max_q := 0.0
	var max_g := 0.0
	var events: Array[String] = []
	var clock := [0.0]
	fv.flight_event.connect(func(k: String, _d: Dictionary) -> void: events.append("%s@%.0f" % [k, clock[0]]))
	while t < 2500.0 and not fv.crashed and not ap.done:
		clock[0] = t
		if ap.update(fv, DT):
			for d in fv.activate_next_stage():
				d.queue_free()
		for d in fv.physics_step(DT):
			d.queue_free()
		t += DT
		max_q = maxf(max_q, fv.q_dyn)
		if t > 2.0:
			max_g = maxf(max_g, fv.g_load)
		if int(t / DT) % 2500 == 0:
			var e := FlightOrbit.elements(fv.body.pos(), fv.body.vel())
			print("    t=%4.0f alt=%6.1f km v=%5.0f m/s pitch=%5.1f q=%5.0f Pa thr=%4.0f kN m=%6.1f t Ap=%6.1f Pe=%7.1f km" % [
				t, fv.body.altitude() / 1000.0, fv.body.speed(), ap.pitch_deg, fv.q_dyn, fv.thrust_n / 1000.0,
				fv.mass / 1000.0, float(e["ap_alt"]) / 1000.0, float(e["pe_alt"]) / 1000.0])
	var el := FlightOrbit.elements(fv.body.pos(), fv.body.vel())
	print("  t=%.0f s crashed=%s (%s) Ap %.1f km Pe %.1f km  maxQ %.1f kPa  maxG %.2f  Δv used %.0f / predicted %.0f m/s" % [
		t, fv.crashed, fv.crash_reason, float(el["ap_alt"]) / 1000.0, float(el["pe_alt"]) / 1000.0, max_q / 1000.0,
		max_g, fv.dv_used, predicted])
	print("  events: " + ", ".join(events))
	_check(not fv.crashed and float(el["pe_alt"]) > 140000.0, "orbit reached (Pe > 140 km)")
	fv.queue_free()
