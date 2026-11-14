class_name FlightAutopilot
extends RefCounted
## Optional "auto-ascent" (key P): flies a gravity turn into a circular orbit, stages
## when a stage burns out, cuts the engines once the periapsis is above the target.
## Used by the screenshot script and handy for testing a design.
##   1. vertical rise to KICK_SPEED, then a pitch program that follows the prograde vector
##      closely while the dynamic pressure is high (small angle of attack = no breakup)
##   2. above ~40 km, closed-loop insertion guidance: pitch so the vertical speed goes to
##      zero as the altitude reaches the target, while the horizontal speed builds up to
##      orbital speed (works for low-TWR upper stages that burn all the way to orbit)

const KICK_SPEED := 55.0
const TURN_END_ALT := 48000.0
const GUIDANCE_ALT := 42000.0
const MAX_G := 4.5
const PITCH_RATE := 3.0
const HOLD_ALT := 125000.0
const MAX_Q := 32000.0

var target_alt := 200000.0
## orbit-plane normal (PCI): set from the pad's up and launch direction
var plane_normal := Vector3.BACK
var done := false
var _no_thrust_time := 0.0
var _stage_cooldown := 0.0
var pitch_deg := 90.0


func _init(pad_up: Vector3, launch_dir: Vector3, alt := 200000.0) -> void:
	plane_normal = pad_up.cross(launch_dir).normalized()
	target_alt = alt


## Steers `v` (sets SAS direction + throttle). Returns true when it wants the next stage.
func update(v: FlightVessel, dt: float) -> bool:
	var want_stage := false
	_stage_cooldown -= dt
	if v.current_stage < 0:
		v.throttle = 1.0
		v.set_sas(FlightVessel.Sas.DIRECTION)
		v.sas_dir = v.body.up()
		_stage_cooldown = 1.0
		return true
	if done:
		v.throttle = 0.0
		v.sas = FlightVessel.Sas.PROGRADE
		return false
	var up := v.body.up()
	var horiz := plane_normal.cross(up).normalized()
	var alt := v.body.altitude()
	var vz := v.body.vertical_speed()
	var vh := v.body.horizontal_speed()
	var speed := v.body.speed()
	var r := v.body.radius()
	var el := FlightOrbit.elements(v.body.pos(), v.body.vel())
	# --- orbit reached?
	if float(el["pe_alt"]) > target_alt - 20000.0 or (float(el["pe_alt"]) > 150000.0 and float(el["e"]) < 0.02):
		done = true
		v.throttle = 0.0
		return false
	# --- pitch program
	var theta := 90.0
	var theta_pro := rad_to_deg(asin(clampf(vz / maxf(speed, 1.0), -1.0, 1.0)))
	if speed > KICK_SPEED:
		var k := clampf((alt - 400.0) / TURN_END_ALT, 0.0, 1.0)
		theta = 90.0 - 72.0 * pow(k, 0.62)
	if alt > GUIDANCE_ALT and v.thrust_n > 0.0:
		var a_thr := v.thrust_n / v.mass
		var v_circ := sqrt(FlightOrbit.MU / r)
		var g_eff := FlightOrbit.MU / (r * r) - vh * vh / r
		var t_go := clampf((v_circ - vh) / maxf(a_thr, 0.05), 15.0, 1500.0)
		# vertical acceleration that brings the altitude to the target (on a parabola)
		# when the horizontal speed reaches orbital speed
		var az := 2.0 * (target_alt - alt - vz * t_go) / (t_go * t_go) + g_eff
		if alt > HOLD_ALT:
			# high enough: hold the vertical speed near zero (drifting slowly towards the
			# target altitude) and put everything else into horizontal speed
			var vz_des := clampf((target_alt - alt) / 200.0, -30.0, 30.0)
			az = g_eff + (vz_des - vz) / clampf(t_go / 4.0, 20.0, 120.0)
		# never plunge back into the air
		if alt < target_alt - 40000.0 and vz < 0.0:
			az = maxf(az, g_eff - vz / 15.0)
		var lo := -0.35 if alt > 90000.0 else 0.0
		var guided := rad_to_deg(asin(clampf(az / maxf(a_thr, 0.01), lo, 0.9)))
		var blend := clampf((alt - GUIDANCE_ALT) / 15000.0, 0.0, 1.0)
		theta = lerpf(theta, guided, blend)
	# keep the angle of attack small while the air is thick
	if v.q_dyn > 2000.0 and speed > KICK_SPEED * 1.5:
		var lim := lerpf(6.0, 2.0, clampf((v.q_dyn - 2000.0) / 15000.0, 0.0, 1.0))
		theta = clampf(theta, theta_pro - lim, theta_pro + lim)
	# smooth: at most PITCH_RATE degrees per second
	if pitch_deg < 89.9 or theta < 89.9:
		theta = clampf(theta, pitch_deg - PITCH_RATE * dt, pitch_deg + PITCH_RATE * dt)
	pitch_deg = theta
	var t := deg_to_rad(theta)
	v.sas = FlightVessel.Sas.DIRECTION
	v.sas_dir = (horiz * cos(t) + up * sin(t)).normalized()
	# gentle on the structure: hold the load under MAX_G and ease off near max-Q
	var thr := 1.0
	if v.thrust_n > 0.0:
		var g_now := v.thrust_n / (v.mass * PartDB.G0)
		thr = clampf(v.throttle * MAX_G / maxf(g_now, 0.01), 0.0, 1.0)
		if v.q_dyn > MAX_Q:
			thr = minf(thr, clampf(1.0 - (v.q_dyn - MAX_Q) / 10000.0, 0.0, 1.0))
	v.throttle = clampf(lerpf(v.throttle, thr, clampf(dt * 2.0, 0.0, 1.0)), 0.05, 1.0)
	# --- staging: the current stage has nothing left to burn
	if v.thrust_n <= 0.0 and not v.clamped:
		_no_thrust_time += dt
	else:
		_no_thrust_time = 0.0
	if _no_thrust_time > 0.6 and _stage_cooldown <= 0.0 and v.current_stage < v.stage_count - 1:
		want_stage = true
		_stage_cooldown = 1.5
		_no_thrust_time = 0.0
	return want_stage
