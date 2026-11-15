class_name FlightGuide
extends RefCounted
## The autopilot of a flight (node free, deterministic): FlightSim calls update() before every
## physics step and next_event() to know where rails warp must stop.
##   ascent     ignition, a vertical rise, then a pitch program that keeps the angle of attack
##              small while the air is thick; above GUIDANCE_ALT a closed loop that brings the
##              vertical speed to zero at the target altitude while the horizontal speed grows to
##              orbital speed (works for low-thrust upper stages that burn all the way). Stages
##              when a stage burns out, holds the load under MAX_G. Cuts when the orbit is good.
##   suborbital `apo_only`: cuts once the apoapsis is above `target_alt` and coasts (no orbit).
##   burns      `burns`: [{"t": centre time, "dv": Vector3 (PCI), "snap": Callable() or null}]
##              flown with the real engines along the Δv, half before and half after `t`; when the
##              Δv is done the engines stop and `snap` (if any) puts the craft exactly on its
##              planned path (a career track's leg).
## `phase`: "pad", "ascent", "coast", "orbit", "burn", "done".

const KICK_SPEED := 45.0
const TURN_END_ALT := 40000.0
const GUIDANCE_ALT := 42000.0
const HOLD_ALT := 125000.0
const MAX_G := 4.5
const MAX_Q := 32000.0
const PITCH_RATE := 3.0

var target_alt := 200000.0
## orbit-plane normal (PCI); the launch heads along normal x up
var plane_normal := Vector3(-0.447, 0.0, -0.894)
var apo_only := false
var phase := "pad"
var burns: Array = []
var pitch_deg := 90.0
## the rocket could not make it by itself (out of stages before the orbit)
var short := false
var _no_thrust := 0.0
var _cooldown := 0.0
var _burned := 0.0


func _init(alt := 200000.0, normal := Vector3(-0.447, 0.0, -0.894)) -> void:
	target_alt = alt
	plane_normal = normal.normalized()


## Rails stop here: the start of the next burn (minus a lead for turning).
func next_event(sim: FlightSim) -> float:
	if phase in ["pad", "ascent"]:
		return sim.t
	if phase == "burn":
		return sim.t
	if burns.is_empty():
		return INF
	var b: Dictionary = burns[0]
	var bt := sim.craft.burn_time((b["dv"] as Vector3).length())
	if bt == INF:
		bt = 0.0
	return float(b["t"]) - bt * 0.5 - 30.0


func update(sim: FlightSim, dt: float) -> void:
	var c := sim.craft
	_cooldown -= dt
	match phase:
		"pad":
			if dt <= 0.0:
				return
			c.throttle = 1.0
			c.sas = FlightCraft.Sas.DIRECTION
			sim.command = sim.up()
			if c.current_stage < 0:
				sim.stage()
				_cooldown = 1.0
			phase = "ascent"
		"ascent":
			if dt > 0.0:
				_ascent(sim, dt)
		"coast", "orbit":
			c.throttle = 0.0
			if phase == "coast" and not apo_only and not sim.in_orbit and burns.is_empty() and sim.altitude() > 100000.0 					and dt > 0.0 and not short:
				_plan_circularize(sim)
			c.sas = FlightCraft.Sas.PROGRADE
			if phase == "coast" and sim.in_orbit:
				phase = "orbit"
			if not burns.is_empty():
				var b: Dictionary = burns[0]
				var dv: Vector3 = b["dv"]
				c.sas = FlightCraft.Sas.DIRECTION
				sim.command = dv.normalized()
				var bt := c.burn_time(dv.length())
				if bt == INF:
					burns.pop_front()
					return
				if sim.t >= float(b["t"]) - bt * 0.5:
					phase = "burn"
					_burned = 0.0
		"burn":
			if dt > 0.0:
				_burn(sim, dt)


func _ascent(sim: FlightSim, dt: float) -> void:
	var c := sim.craft
	var up := sim.up()
	var horiz := plane_normal.cross(up).normalized()
	var alt := sim.altitude()
	var vz := sim.vertical_speed()
	var vh := sim.horizontal_speed()
	var speed := sim.speed()
	var r := sim.radius()
	var mu := sim.mu()
	var el := sim.elements()
	if apo_only:
		if float(el["ap_alt"]) > target_alt and alt > 20000.0:
			c.throttle = 0.0
			phase = "coast"
			return
	elif float(el["pe_alt"]) > minf(target_alt - 20000.0, FlightSim.ORBIT_PE + 12000.0) 			and float(el["ap_alt"]) > minf(target_alt * 0.85, float(el["pe_alt"]) + 1000.0):
		c.throttle = 0.0
		phase = "coast"
		return
	elif alt > 110000.0 and vz > 20.0 and float(el["ap_alt"]) > target_alt * 0.95 and float(el["pe_alt"]) > -sim.sys.radius[sim.body] * 0.5 and _circ_fits(sim):
		# high and fast enough: coast up to the apoapsis and round the orbit off there (only while
		# still climbing, and when the engines can round it off around the apoapsis: else a short
		# orbit falls back before the burn is done, keep burning)
		c.throttle = 0.0
		phase = "coast"
		_plan_circularize(sim)
		return
	var theta := 90.0
	var theta_pro := rad_to_deg(asin(clampf(vz / maxf(speed, 1.0), -1.0, 1.0)))
	if speed > KICK_SPEED:
		var k := clampf((alt - 400.0) / TURN_END_ALT, 0.0, 1.0)
		theta = 90.0 - 72.0 * pow(k, 0.5)
	if apo_only:
		theta = maxf(theta, 70.0)
	elif alt > GUIDANCE_ALT and sim.thrust_n > 0.0:
		var a_thr := sim.thrust_n / c.mass()
		var v_circ := sqrt(mu / r)
		var g_eff := mu / (r * r) - vh * vh / r
		var t_go := clampf((v_circ - vh) / maxf(a_thr, 0.05), 15.0, 1500.0)
		var az := 2.0 * (target_alt - alt - vz * t_go) / (t_go * t_go) + g_eff
		if alt > HOLD_ALT:
			var vz_des := clampf((target_alt - alt) / 200.0, -30.0, 30.0)
			az = g_eff + (vz_des - vz) / clampf(t_go / 4.0, 20.0, 120.0)
		if alt < 105000.0 and vz < 0.0:
			az = maxf(az, g_eff - vz / 15.0)
		var lo := -0.35 if alt > 90000.0 else 0.0
		# a weak upper stage that cannot hold its height sinks a little while it gathers speed
		# (holding it up would spend everything against gravity)
		var hi := lerpf(0.9, 0.42, clampf((alt - 110000.0) / 30000.0, 0.0, 1.0))
		var guided := rad_to_deg(asin(clampf(az / maxf(a_thr, 0.01), lo, hi)))
		theta = lerpf(theta, guided, clampf((alt - GUIDANCE_ALT) / 15000.0, 0.0, 1.0))
	if sim.q_dyn > 2000.0 and speed > KICK_SPEED * 1.5:
		var lim := lerpf(12.0, 5.0, clampf((sim.q_dyn - 2000.0) / 20000.0, 0.0, 1.0))
		theta = clampf(theta, theta_pro - lim, theta_pro + lim)
	if pitch_deg < 89.9 or theta < 89.9:
		theta = clampf(theta, pitch_deg - PITCH_RATE * dt, pitch_deg + PITCH_RATE * dt)
	pitch_deg = theta
	var tr := deg_to_rad(theta)
	c.sas = FlightCraft.Sas.DIRECTION
	sim.command = (horiz * cos(tr) + up * sin(tr)).normalized()
	var thr := 1.0
	if sim.thrust_n > 0.0:
		var g_now := sim.thrust_n / (c.mass() * PartDB.G0)
		thr = clampf(c.throttle * MAX_G / maxf(g_now, 0.01), 0.0, 1.0)
		if sim.q_dyn > MAX_Q:
			thr = minf(thr, clampf(1.0 - (sim.q_dyn - MAX_Q) / 10000.0, 0.0, 1.0))
	c.throttle = clampf(lerpf(c.throttle, thr, clampf(dt * 2.0, 0.0, 1.0)), 0.05, 1.0)
	_auto_stage(sim, dt)
	if c.spent() and not sim.clamped and sim.thrust_n <= 0.0:
		short = true
		c.throttle = 0.0
		phase = "coast"


func _auto_stage(sim: FlightSim, dt: float) -> void:
	var c := sim.craft
	if sim.thrust_n <= 0.0 and not sim.clamped:
		_no_thrust += dt
	else:
		_no_thrust = 0.0
	if _no_thrust > 0.6 and _cooldown <= 0.0 and c.current_stage < c.stage_count - 1:
		sim.stage()
		_cooldown = 1.5
		_no_thrust = 0.0


## Can the burning engines give the circularization at the apoapsis within the time left to it
## (the burn is flown half before, half after the apoapsis)?
func _circ_fits(sim: FlightSim) -> bool:
	var tta := sim.time_to_apoapsis()
	if tta == INF or float(sim.elements()["e"]) >= 1.0:
		return false
	var s := FlightOrbit.propagate(sim.pos(), sim.vel(), tta, sim.mu())
	var r := Vector3(s[0], s[1], s[2])
	var v := Vector3(s[3], s[4], s[5])
	var dv := sqrt(sim.mu() / r.length()) - v.length()
	var a_max := float(sim.craft.burn_engines()["thrust"]) / sim.craft.mass()
	return dv <= 0.0 or (a_max > 0.0 and dv / a_max < 2.0 * tta)


## A burn at the apoapsis that lifts the periapsis out of the air (the end of the ascent).
func _plan_circularize(sim: FlightSim) -> void:
	var el := sim.elements()
	if float(el["e"]) >= 1.0:
		return
	var tta := sim.time_to_apoapsis()
	if tta == INF:
		return
	var s := FlightOrbit.propagate(sim.pos(), sim.vel(), tta, sim.mu())
	var r := Vector3(s[0], s[1], s[2])
	var v := Vector3(s[3], s[4], s[5])
	var up := r.normalized()
	var h := (v - up * v.dot(up)).normalized()
	var dv := sqrt(sim.mu() / r.length()) - v.length()
	if dv <= 1.0:
		return
	burns.append({"t": sim.t + tta, "dv": h * dv, "circ": true})


func _burn(sim: FlightSim, dt: float) -> void:
	var c := sim.craft
	var b: Dictionary = burns[0]
	var dv: Vector3 = b["dv"]
	var need := dv.length()
	c.sas = FlightCraft.Sas.DIRECTION
	sim.command = dv.normalized()
	var aligned := sim.nose().angle_to(dv.normalized()) < deg_to_rad(4.0)
	if aligned:
		var a_max := float(c.burn_engines()["thrust"]) / c.mass()
		c.throttle = clampf((need - _burned) / maxf(a_max * 1.5, 1e-3), 0.05, 1.0)
	else:
		c.throttle = 0.0
	if sim.thrust_n > 0.0:
		_burned += sim.thrust_n / c.mass() * dt
	_auto_stage(sim, dt)
	var dry := c.spent()
	var done := _burned >= need
	if b.get("circ", false):
		var el := sim.elements()
		var want := minf(target_alt - 20000.0, float(el["ap_alt"]) - 8000.0)
		done = float(el["pe_alt"]) >= maxf(want, FlightSim.ORBIT_PE + 5000.0) or _burned >= need * 1.6
		# keep the burn level: along the horizon in the orbit plane
		var up := sim.up()
		var vv := sim.velocity_v3()
		sim.command = (vv - up * vv.dot(up)).normalized()
	if done or dry:
		c.throttle = 0.0
		var snap: Variant = b.get("snap")
		if snap is Callable and (snap as Callable).is_valid():
			(snap as Callable).call()
		burns.pop_front()
		phase = "orbit" if sim.body == sim.sys.earth and sim.in_orbit else "coast"
