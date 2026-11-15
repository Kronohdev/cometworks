extends SceneTree
## Headless checks for the flight simulation (FlightCraft, FlightSim, FlightGuide):
##   1. integrator: a circular 200 km orbit stays circular for one revolution of physics steps
##      and ends where Kepler says
##   2. Kepler propagation: energy and angular momentum conserved over 10 orbits
##   3. staging: FlightStaging puts every Garça part in the hangar's stage; the craft drops
##      2 boosters, then 1 stage, in that order
##   4. rocket equation: burns in vacuum without gravity give the hangar's per-stage vacuum Δv
##      (VesselMath) within 2 %, and the liftoff mass is the hangar's
##   5. ascent: the guide flies Garça from the pad to orbit (Pe > 140 km), Andorinha too
##   6. warp: rails coasting matches the physics steps on the same orbit
##   7. determinism: the same flight twice gives the same state, bit for bit
##   8. failure: a career failure breaks the craft up at its second; a suborbital hop splashes down
## Run: godot --headless --path . --script res://tests/test_flight.gd

const DT := 0.02
const GARCA := "res://scenes/examples/garca.tscn"
const ANDORINHA := "res://scenes/examples/andorinha.tscn"

var _failures := 0


func _initialize() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	_test_orbit()
	_test_kepler()
	_test_staging()
	_test_rocket_equation()
	_test_ascent(GARCA, 0.0, 200000.0)
	_test_ascent(ANDORINHA, 0.0, 150000.0)
	_test_rails()
	_test_determinism()
	_test_failure()
	print("time %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1


func _craft(path: String, payload := 0.0) -> FlightCraft:
	return FlightCraft.from_scene(load(path), payload)


# ------------------------------------------------------------ 1. integrator
func _test_orbit() -> void:
	print("orbit integrator (circular 200 km, dt %.3f s)" % DT)
	var sim := FlightSim.new(_craft(GARCA))
	var r := FlightOrbit.R + 200000.0
	var vc := sqrt(FlightOrbit.MU / r)
	sim.set_orbit_state(sim.sys.earth, FlightOrbit.vec(0, r, 0), FlightOrbit.vec(vc, 0, 0))
	sim.craft.throttle = 0.0
	var period := TAU * sqrt(r * r * r / FlightOrbit.MU)
	var n := int(round(period / DT))
	var rmin := INF
	var rmax := -INF
	for i in n:
		sim.step(DT)
		var rr := sim.radius()
		rmin = minf(rmin, rr)
		rmax = maxf(rmax, rr)
	var s := FlightOrbit.propagate(FlightOrbit.vec(0, r, 0), FlightOrbit.vec(vc, 0, 0), n * DT)
	var d := Vector3(sim.px - s[0], sim.py - s[1], sim.pz - s[2]).length()
	print("  radius %.1f .. %.1f m, end vs Kepler %.1f m" % [rmin - FlightOrbit.R, rmax - FlightOrbit.R, d])
	_check(rmax - rmin < 50.0 and d < 200.0, "one revolution of physics steps stays on the orbit")


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
	var el1 := FlightOrbit.elements(FlightOrbit.vec(s[0], s[1], s[2]), FlightOrbit.vec(s[3], s[4], s[5]))
	var de := absf(float(el1["energy"]) - float(el0["energy"])) / absf(float(el0["energy"]))
	var dh := absf(FlightOrbit.length(el1["h"]) - FlightOrbit.length(el0["h"])) / FlightOrbit.length(el0["h"])
	_check(de < 1e-9 and dh < 1e-9, "Kepler propagation conserves the orbit")


# ------------------------------------------------------------ 3. staging
func _test_staging() -> void:
	print("staging (Garça)")
	var v := Vessel.new()
	v.load_scene(load(GARCA))
	var st := v.compute_stages()
	var gs := FlightStaging.groups(v)
	var mismatch := 0
	for si in st["stage_parts"].size():
		for p: PartInstance in st["stage_parts"][si]:
			var found := -1
			for g in gs:
				if (g["parts"] as Array).has(p):
					found = g["stage"]
			if found != si:
				mismatch += 1
	_check(mismatch == 0 and FlightStaging.stage_count(gs) == st["stage_parts"].size(), "flight stages == hangar stages")
	v.free()
	var c := _craft(GARCA)
	var boosters := 0
	for g: Dictionary in c.groups:
		if g["kind"] == "booster":
			boosters += 1
	_check(boosters == 2 and c.stage_count == 2, "two booster groups, two stages (%d, %d)" % [boosters, c.stage_count])


# ------------------------------------------------------------ 4. rocket equation
func _test_rocket_equation() -> void:
	print("rocket equation (vacuum, no gravity)")
	var hv := Vessel.new()
	hv.load_scene(load(GARCA))
	var an := hv.analyze()
	hv.free()
	var c := _craft(GARCA)
	var m0: float = an["stages"][0]["m0_kg"]
	_check(absf(c.mass() - m0) < 1.0, "liftoff mass %.1f kg == hangar %.1f kg" % [c.mass(), m0])
	var events: Array = []
	c.next_stage(events)
	var dvs: Array[float] = []
	for s in c.stage_count:
		var v := 0.0
		var burning := false
		var t := 0.0
		while t < 3000.0:
			var f := c.burn(DT, 0.0, events)
			v += f / c.mass() * DT
			var ev2: Array = []
			c.spent_boosters(ev2)
			events.append_array(ev2)
			t += DT
			if f > 0.0:
				burning = true
			elif burning:
				break
		dvs.append(v)
		if s < c.stage_count - 1:
			c.next_stage(events)
	for i in dvs.size():
		var exp_dv: float = an["stages"][i]["dv_vac"]
		var err := absf(dvs[i] - exp_dv) / exp_dv
		print("  stage %d: sim %.1f m/s, hangar vac %.1f m/s (%.2f %%)" % [i + 1, dvs[i], exp_dv, err * 100.0])
		_check(err < 0.02, "stage %d Δv matches the rocket equation" % (i + 1))
	var order := []
	for e: Array in events:
		if e[0] in ["EV_BOOSTER_SEP", "EV_STAGE_SEP"]:
			order.append(e[0])
	_check(",".join(order) == "EV_BOOSTER_SEP,EV_BOOSTER_SEP,EV_STAGE_SEP", "boosters drop first, then the stage (%s)" % ",".join(order))


# ------------------------------------------------------------ 5. ascent
func _fly_to_orbit(path: String, payload: float) -> FlightSim:
	var sim := FlightSim.new(_craft(path, payload))
	sim.place_on_pad(12.0)
	var g := FlightGuide.new(200000.0)
	while sim.met() < 2500.0 and not sim.crashed and g.phase in ["pad", "ascent"]:
		sim.advance(DT, g)
	return sim


func _test_ascent(path: String, payload: float, alt: float) -> void:
	print("auto-ascent (%s, pad -> %.0f km orbit)" % [path.get_file(), alt / 1000.0])
	var sim := FlightSim.new(_craft(path, payload))
	sim.place_on_pad(12.0)
	var g := FlightGuide.new(alt)
	var keys: Array[String] = []
	var dropped := 0
	while sim.met() < 2500.0 and not sim.crashed and g.phase in ["pad", "ascent"]:
		sim.advance(DT, g)
		for e: Array in sim.take_events():
			keys.append("%s@%.0f" % [e[0], e[2]])
		dropped += sim.dropped.size()
		sim.dropped.clear()
	# coast to the apoapsis region and let the orbit settle
	for i in 300:
		sim.advance(20.0, g)
	for e: Array in sim.take_events():
		keys.append("%s@%.0f" % [e[0], e[2]])
	var el := sim.elements()
	print("  met %.0f s crashed=%s (%s) Ap %.1f km Pe %.1f km maxQ %.1f kPa maxG %.2f dropped %d, short %s" % [
		sim.met(), sim.crashed, sim.crash_reason, float(el["ap_alt"]) / 1000.0, float(el["pe_alt"]) / 1000.0,
		sim.max_q / 1000.0, float(sim.stats["max_g"]), dropped, g.short])
	print("  events: " + ", ".join(keys))
	_check(not sim.crashed and sim.in_orbit and float(el["pe_alt"]) > 140000.0, "orbit reached (Pe > 140 km)")
	_check(keys.any(func(k: String) -> bool: return k.begins_with("EV_LIFTOFF")), "liftoff event")
	_check(keys.any(func(k: String) -> bool: return k.begins_with("EV_ORBIT")), "orbit event")


# ------------------------------------------------------------ 6. rails
func _test_rails() -> void:
	print("rails vs physics")
	var r := FlightOrbit.R + 300000.0
	var vc := sqrt(FlightOrbit.MU / r) * 1.05
	var a := FlightSim.new(_craft(GARCA))
	var b := FlightSim.new(_craft(GARCA))
	for s: FlightSim in [a, b]:
		s.set_orbit_state(s.sys.earth, FlightOrbit.vec(0, r, 0), FlightOrbit.vec(vc, 0, 0))
		s.craft.throttle = 0.0
	for i in int(1200.0 / DT):
		a.step(DT)
	b.advance(1200.0)
	var d := Vector3(a.px - b.px, a.py - b.py, a.pz - b.pz).length()
	print("  after 1200 s: %.1f m apart, rails %s" % [d, b.on_rails])
	_check(b.on_rails and d < 500.0, "rails follow the same orbit")
	# a long warp keeps the clock exact
	var t0 := b.t
	b.advance(86400.0 * 3.0)
	_check(absf(b.t - t0 - 86400.0 * 3.0) < 1e-3, "three days of warp in one call")


# ------------------------------------------------------------ 7. determinism
func _test_determinism() -> void:
	print("determinism")
	var a := _fly_to_orbit(ANDORINHA, 300.0)
	var b := _fly_to_orbit(ANDORINHA, 300.0)
	_check(a.px == b.px and a.vy == b.vy and a.t == b.t and a.craft.mass() == b.craft.mass(),
		"two flights of the same rocket end in the same state")


# ------------------------------------------------------------ 8. failure / suborbital
func _test_failure() -> void:
	print("career failure and suborbital hop")
	var sim := FlightSim.new(_craft(GARCA, 9000.0))
	sim.place_on_pad(12.0)
	sim.fail_met = 61.0
	sim.fail_reason = "TY_TRK_CRASH_ENGINE"
	var g := FlightGuide.new(200000.0)
	var crash_at := -1.0
	while sim.t < 400.0:
		sim.advance(0.1, g)
		for e: Array in sim.take_events():
			if e[0] == "EV_CRASH":
				crash_at = float(e[2])
	print("  crash at %.2f s (%s)" % [crash_at, sim.crash_reason])
	_check(absf(crash_at - 61.0) < 0.05 and sim.crash_reason == "TY_TRK_CRASH_ENGINE", "breaks up at its second")
	var hop := FlightSim.new(_craft(ANDORINHA, 300.0))
	hop.place_on_pad(12.0)
	hop.soft_landing = true
	hop.limits = false
	var gh := FlightGuide.new(120000.0)
	gh.apo_only = true
	var landed := false
	while hop.met() < 3000.0 and not landed and not hop.crashed:
		hop.advance(1.0, gh)
		for e: Array in hop.take_events():
			landed = landed or e[0] == "EV_LANDED"
	print("  hop: max alt %.1f km, landed %s, crashed %s" % [float(hop.stats["max_alt"]) / 1000.0, landed, hop.crashed])
	_check(landed and float(hop.stats["max_alt"]) > 100000.0, "a suborbital hop goes to space and splashes down")
