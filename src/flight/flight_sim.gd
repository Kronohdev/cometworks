class_name FlightSim
extends RefCounted
## The flight simulation, node free (it runs headless: tests, the campus' background flight
## after the player leaves the 3D view, the launch watch). One craft (FlightCraft) as a point
## mass with an attitude:
##   state      position / velocity in doubles, relative to the body whose sphere of influence
##              holds it (`body`, a FlightSolar index), in the flight's inertial axes (PCI:
##              +Y = up at the launch pad, Earth not rotating), at time `t` (FlightSolar's clock:
##              campaign seconds, so the Moon and the planets are where the campus map has them)
##   attitude   `q` (local +Y = nose); it slews towards the commanded direction at `turn_rate`
##              (SAS / autopilot), or turns with the pilot's input
##   physics    fixed steps of DT: gravity of `body` (kick-drift-kick leapfrog), thrust of the lit
##              engines along the nose (Isp between sea level and vacuum by the air pressure),
##              axial drag with a transonic rise, pad clamps until the thrust lifts the weight,
##              ground contact (a gentle touchdown off the Earth is a landing, else an impact),
##              structural limits (q·sin AoA, q, g), staging and empty boosters dropping
##   on rails   no thrust and above the air: exact conics (FlightTrajectory, patched conics), SOI
##              changes at their computed times; or `rails_source` (a career track's own legs)
##   warp       advance(dt, warp) picks rails or physics; physics warp is capped by the caller
## Events (`take_events()`): [key, data, met] in order: EV_IGNITION, EV_LIFTOFF, EV_MAXQ,
## EV_BOOSTER_SEP, EV_STAGE_SEP, EV_FAIRING, EV_FLAMEOUT, EV_SPACE, EV_ORBIT, EV_SOI, EV_CRASH,
## EV_LANDED. Detached groups and fairings go to `dropped` for the view (FlightModel).
## Deterministic: the same craft, guide and start give the same flight, bit for bit.

const DT := 0.02
const ORBIT_PE := 140000.0
const IMPACT_SPEED := 8.0
const DEFAULT_TURN_RATE := 9.0   # deg/s

var sys: FlightSolar
var craft: FlightCraft
var body := 0
var px := 0.0
var py := 0.0
var pz := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var t := 0.0
## FlightSolar time of the liftoff (-1 = still on the pad)
var t_liftoff := -1.0
var launched := false
var clamped := true
var landed := true
var crashed := false
var crash_reason := ""
var in_orbit := false
## attitude: local -> PCI (local +Y = nose)
var q := Quaternion.IDENTITY
## SAS / autopilot target direction (PCI) used in FlightCraft.Sas.DIRECTION
var command := Vector3.UP
var turn_rate := DEFAULT_TURN_RATE
## pilot's steering input: pitch (x), roll (y), yaw (z) in [-1, 1]
var input := Vector3.ZERO
var pad_up := Vector3.UP
var pad_alt := 12.0
## the craft breaks up at this mission time (s after liftoff; -1 = never): a career failure
var fail_met := -1.0
var fail_reason := "CRASH_AERO"
## structural limits on (the pilot can break a rocket; the autopilot never asks that much)
var limits := true
## an impact on the Earth is a splashdown (a capsule under its parachutes), not a crash
var soft_landing := false
## when valid, coasting follows it: Callable(t) -> {"body": int, "pos", "vel"} (a career
## track's legs, so the 3D view and the campus map share one path)
var rails_source := Callable()
var on_rails := false

# telemetry of the last step
var thrust_n := 0.0
var q_dyn := 0.0
var mach := 0.0
var aoa := 0.0
var pressure := 1.0
var g_load := 1.0
var accel := Vector3.ZERO
var max_q := 0.0
var stats := {}
var visited := {}

var _events: Array = []
## groups / fairings that left the craft since the view last looked: [{"groups", "fairings", "t"}]
var dropped: Array = []
var _maxq_done := false
var _space_done := false
var _traj: FlightTrajectory = null
var _traj_key := PackedFloat64Array()


func _init(c: FlightCraft = null, solar: FlightSolar = null) -> void:
	craft = c if c else FlightCraft.new()
	sys = solar if solar else FlightSolar.get_system()
	body = sys.earth
	visited[body] = true
	stats = {"max_alt": 0.0, "max_speed": 0.0, "max_q": 0.0, "max_q_t": 0.0, "max_q_alt": 0.0, "max_g": 0.0}


# ------------------------------------------------------------ state
func pos() -> PackedFloat64Array:
	return PackedFloat64Array([px, py, pz])


func vel() -> PackedFloat64Array:
	return PackedFloat64Array([vx, vy, vz])


func set_state(r: PackedFloat64Array, v: PackedFloat64Array) -> void:
	px = r[0]
	py = r[1]
	pz = r[2]
	vx = v[0]
	vy = v[1]
	vz = v[2]
	_traj = null


func radius() -> float:
	return sqrt(px * px + py * py + pz * pz)


func altitude() -> float:
	return radius() - sys.radius[body]


func speed() -> float:
	return sqrt(vx * vx + vy * vy + vz * vz)


func up() -> Vector3:
	var r := maxf(radius(), 1.0)
	return Vector3(px / r, py / r, pz / r)


func velocity_v3() -> Vector3:
	return Vector3(vx, vy, vz)


func vertical_speed() -> float:
	return (px * vx + py * vy + pz * vz) / maxf(radius(), 1.0)


func horizontal_speed() -> float:
	var vs := vertical_speed()
	return sqrt(maxf(vx * vx + vy * vy + vz * vz - vs * vs, 0.0))


func nose() -> Vector3:
	return Basis(q) * Vector3.UP


func mu() -> float:
	return sys.mu[body]


## Mission time (s since liftoff; 0 on the pad).
func met() -> float:
	return t - t_liftoff if t_liftoff >= 0.0 else 0.0


func elements() -> Dictionary:
	return FlightOrbit.elements(pos(), vel(), sys.mu[body], sys.radius[body])


func has_air() -> bool:
	return sys.atmo_top[body] > 0.0


## Lowest altitude for rails: the top of the air, or a margin above an airless surface.
func rails_floor() -> float:
	return sys.atmo_top[body] if has_air() else maxf(5000.0, sys.radius[body] * 0.005)


# ------------------------------------------------------------ setup
## Stands the craft on the launch pad: base on the pad (`alt` m above the sea), nose up, still;
## `downrange` is the horizontal direction the rocket's top side faces (its pitch-over side).
func place_on_pad(alt: float, up_axis := Vector3.UP, downrange := Vector3(0.894, 0, -0.447)) -> void:
	pad_up = up_axis.normalized()
	pad_alt = alt
	body = sys.earth
	var right := pad_up.cross(downrange.normalized()).normalized()
	q = Basis(right, pad_up, right.cross(pad_up).normalized()).orthonormalized().get_rotation_quaternion()
	var r := sys.radius[body] + alt
	set_state(PackedFloat64Array([pad_up.x * r, pad_up.y * r, pad_up.z * r]), PackedFloat64Array([0.0, 0.0, 0.0]))
	command = pad_up
	clamped = true
	landed = true
	launched = false


## Puts the craft on a state around a body (a craft already in space: following a track).
func set_orbit_state(b: int, r: PackedFloat64Array, v: PackedFloat64Array) -> void:
	body = b
	visited[b] = true
	set_state(r, v)
	launched = true
	clamped = false
	landed = false
	if t_liftoff < 0.0:
		t_liftoff = t
	var vv := velocity_v3()
	if vv.length() > 1.0:
		q = Quaternion(Vector3.UP, vv.normalized())


func take_events() -> Array:
	var e := _events
	_events = []
	return e


func _emit(key: String, data := {}) -> void:
	_events.append([key, data, met()])


func _emit_craft(list: Array) -> void:
	for e: Array in list:
		_emit(String(e[0]), e[1])


# ------------------------------------------------------------ actions
## The space bar: ignition on the pad, else the next stage.
func stage() -> void:
	if crashed:
		return
	var evs: Array = []
	var out := craft.next_stage(evs)
	_emit_craft(evs)
	if not (out["groups"] as Array).is_empty() or not (out["fairings"] as Array).is_empty():
		dropped.append({"groups": out["groups"], "fairings": out["fairings"], "t": t})
	if craft.current_stage == 0 and not launched:
		launched = true


func jettison_fairings() -> void:
	var evs: Array = []
	var f := craft.jettison(evs)
	_emit_craft(evs)
	if not f.is_empty():
		dropped.append({"groups": [], "fairings": f, "t": t})


## Breaks the craft up now (a career failure, the structure giving way).
func fail(reason: String) -> void:
	if crashed:
		return
	crashed = true
	craft.crashed = true
	crash_reason = reason
	for e: Dictionary in craft.engines:
		e["running"] = false
		e["thrust"] = 0.0
		e["thr"] = 0.0
	thrust_n = 0.0
	craft.thrust_n = 0.0
	_emit("EV_CRASH", {"reason": reason})


## An impulsive change of velocity (m/s, PCI): the track snaps a finished burn onto its leg.
func kick(dv: Vector3) -> void:
	vx += dv.x
	vy += dv.y
	vz += dv.z
	_traj = null


# ------------------------------------------------------------ physics step
func step(dt := DT) -> void:
	if crashed:
		t += dt
		return
	t += dt
	if fail_met >= 0.0 and t_liftoff >= 0.0 and met() >= fail_met:
		fail(fail_reason)
		return
	var alt := altitude()
	var rho := FlightOrbit.density(alt) if body == sys.earth else 0.0
	pressure = rho / FlightOrbit.RHO0
	_steer(dt)
	var evs: Array = []
	thrust_n = craft.burn(dt, pressure, evs)
	_emit_craft(evs)
	var m := craft.mass()
	var n := nose()
	var ax := n.x * thrust_n / m
	var ay := n.y * thrust_n / m
	var az := n.z * thrust_n / m
	if clamped:
		# held down until the engines lift the weight
		var g := sys.mu[body] / (radius() * radius())
		if thrust_n > m * g * 1.02 and craft.current_stage >= 0:
			clamped = false
			landed = false
			if t_liftoff < 0.0:
				t_liftoff = t
				_emit("EV_LIFTOFF")
		else:
			q_dyn = 0.0
			g_load = 1.0
			accel = Vector3.ZERO
			return
	# aerodynamics (air at rest in the inertial frame)
	var v := velocity_v3()
	var sp := v.length()
	q_dyn = 0.5 * rho * sp * sp
	mach = sp / FlightOrbit.SOUND_SPEED
	aoa = 0.0
	if rho > 0.0 and sp > 0.5:
		var vh := v / sp
		aoa = n.angle_to(vh)
		var cdm := craft.cd * (1.0 + 1.1 * exp(-pow((mach - 1.1) / 0.4, 2.0)))
		var side := absf(sin(aoa))
		var drag := q_dyn * craft.a_front * (cdm * (1.0 + 3.0 * side)) / m
		ax -= vh.x * drag
		ay -= vh.y * drag
		az -= vh.z * drag
	accel = Vector3(ax, ay, az)
	_integrate(dt, ax, ay, az)
	g_load = accel.length() / PartDB.G0
	craft.dv_used += thrust_n / m * dt
	_ground()
	if crashed:
		return
	if limits and t_liftoff >= 0.0:
		if q_dyn * sin(minf(aoa, PI * 0.5)) > FlightCraft.LIMIT_Q_AOA and aoa > deg_to_rad(4.0):
			fail("CRASH_AERO")
		elif q_dyn > FlightCraft.LIMIT_Q:
			fail("CRASH_Q")
		elif g_load > FlightCraft.LIMIT_G:
			fail("CRASH_G")
	if crashed:
		return
	var b_evs: Array = []
	var gone := craft.spent_boosters(b_evs)
	_emit_craft(b_evs)
	if not gone.is_empty():
		dropped.append({"groups": gone, "fairings": [], "t": t})
	_check_soi()
	_track()


func _integrate(dt: float, ax: float, ay: float, az: float) -> void:
	_traj = null
	var h := dt * 0.5
	var k := -sys.mu[body] / pow(px * px + py * py + pz * pz, 1.5)
	vx += h * px * k + dt * ax
	vy += h * py * k + dt * ay
	vz += h * pz * k + dt * az
	px += dt * vx
	py += dt * vy
	pz += dt * vz
	k = -sys.mu[body] / pow(px * px + py * py + pz * pz, 1.5)
	vx += h * px * k
	vy += h * py * k
	vz += h * pz * k


## Attitude: the pilot's input turns the nose; else SAS / the autopilot slews it to its target.
func _steer(dt: float) -> void:
	var rate := deg_to_rad(turn_rate) * dt
	if input.length_squared() > 1e-4:
		var b := Basis(q)
		var rot := Quaternion(b.x, input.x * rate) * Quaternion(b.z, -input.z * rate) * Quaternion(b.y, input.y * rate * 2.0)
		q = (rot * q).normalized()
		if craft.sas == FlightCraft.Sas.HOLD:
			command = nose()
		return
	var want := Vector3.ZERO
	match craft.sas:
		FlightCraft.Sas.PROGRADE:
			if speed() > 1.0:
				want = velocity_v3().normalized()
		FlightCraft.Sas.RETROGRADE:
			if speed() > 1.0:
				want = -velocity_v3().normalized()
		FlightCraft.Sas.DIRECTION:
			want = command.normalized()
		FlightCraft.Sas.HOLD:
			want = command.normalized()
	if want == Vector3.ZERO or clamped:
		return
	var n := nose()
	var ang := n.angle_to(want)
	if ang < 1e-6:
		return
	var axis := n.cross(want)
	if axis.length_squared() < 1e-12:
		axis = Basis(q).x
	q = (Quaternion(axis.normalized(), minf(ang, rate)) * q).normalized()


func _ground() -> void:
	var alt := altitude()
	var ground := 0.0
	if body == sys.earth and (up() - pad_up).length() * sys.radius[body] < 60.0:
		ground = pad_alt
	if alt > ground:
		landed = false
		return
	var vs := vertical_speed()
	var r := sys.radius[body] + ground
	var u := up()
	var hard := vs < -IMPACT_SPEED or speed() > IMPACT_SPEED * 2.0 or (body == sys.earth and t_liftoff >= 0.0 and met() > 5.0)
	if hard and soft_landing and body == sys.earth and t_liftoff >= 0.0:
		set_state(PackedFloat64Array([u.x * r, u.y * r, u.z * r]), PackedFloat64Array([0.0, 0.0, 0.0]))
		if not landed:
			_emit("EV_LANDED", {"body": sys.display_name(body)})
		landed = true
		return
	if hard:
		set_state(PackedFloat64Array([u.x * r, u.y * r, u.z * r]), PackedFloat64Array([0.0, 0.0, 0.0]))
		fail("CRASH_IMPACT")
		return
	set_state(PackedFloat64Array([u.x * r, u.y * r, u.z * r]), PackedFloat64Array([0.0, 0.0, 0.0]))
	if not landed and t_liftoff >= 0.0:
		_emit("EV_LANDED", {"body": sys.display_name(body)})
	landed = true


func _track() -> void:
	var alt := altitude()
	stats["max_alt"] = maxf(stats["max_alt"], alt)
	stats["max_speed"] = maxf(stats["max_speed"], speed())
	if q_dyn > float(stats["max_q"]):
		stats["max_q"] = q_dyn
		stats["max_q_t"] = met()
		stats["max_q_alt"] = alt
	if met() > 1.0:
		stats["max_g"] = maxf(stats["max_g"], g_load)
	max_q = maxf(max_q, q_dyn)
	if not _maxq_done and max_q > 4000.0 and q_dyn < max_q * 0.97:
		_maxq_done = true
		_emit("EV_MAXQ", {"q": max_q})
	if not _space_done and body == sys.earth and alt > 100000.0:
		_space_done = true
		_emit("EV_SPACE")
	_check_orbit()


func _check_orbit() -> void:
	if in_orbit or body != sys.earth or thrust_n > 0.0 or altitude() < FlightOrbit.ATMO_TOP:
		return
	var el := elements()
	if float(el["pe_alt"]) > ORBIT_PE:
		in_orbit = true
		_emit("EV_ORBIT", {"ap": el["ap_alt"], "pe": el["pe_alt"]})


## Physics steps: crossing a sphere of influence?
func _check_soi() -> void:
	var r2 := px * px + py * py + pz * pz
	if sys.parent[body] >= 0 and r2 > sys.soi[body] * sys.soi[body]:
		_switch_soi(sys.parent[body])
		return
	for k in sys.children[body]:
		var c := sys.pos_rel_parent(k, t)
		var dx := px - c[0]
		var dy := py - c[1]
		var dz := pz - c[2]
		if dx * dx + dy * dy + dz * dz < sys.soi[k] * sys.soi[k]:
			_switch_soi(k)
			return


func _switch_soi(nb: int) -> void:
	if nb == body:
		return
	var off := sys.state_rel(body, nb, t)
	var entering := sys.parent[nb] == body
	px += off[0]
	py += off[1]
	pz += off[2]
	vx += off[3]
	vy += off[4]
	vz += off[5]
	body = nb
	visited[nb] = true
	_traj = null
	_emit("EV_SOI", {"body": sys.display_name(nb), "enter": entering})


# ------------------------------------------------------------ rails
## Can it coast on exact conics now (no thrust, above the air, flying)?
func rails_ok() -> bool:
	if not launched or clamped or landed or crashed:
		return false
	if thrust_n > 0.0 or _engines_lit():
		return false
	return altitude() > rails_floor()


func _engines_lit() -> bool:
	if craft.throttle <= 0.0 or craft.current_stage < 0:
		return false
	for e: Dictionary in craft.stage_engines(craft.current_stage):
		if e["lit"] and craft.pool_prop(int(e["pool"])) > 0.0 and (e["running"] or int(e["restarts"]) > 0 or e["solid"]):
			return true
	return false


## Coasts on rails to `t_end` (or earlier: `stop`), crossing SOI boundaries at their computed
## times. Stops above the air / surface (returns the time reached).
func coast_to(t_end: float) -> float:
	if crashed:
		t = t_end
		return t
	if rails_source.is_valid():
		var st: Dictionary = rails_source.call(t_end)
		var nb := int(st["body"])
		if nb != body:
			_emit("EV_SOI", {"body": sys.display_name(nb), "enter": sys.parent[nb] == body})
			body = nb
			visited[nb] = true
		set_state(st["pos"], st["vel"])
		t = t_end
		thrust_n = 0.0
		_point_along_velocity()
		_track()
		return t
	for guard in 8:
		if _traj == null or _traj.current_segment_at(t) < 0 or _traj.start_body != body:
			_traj = FlightTrajectory.predict(sys, body, pos(), vel(), t, [], -1, 0.6)
		var si := _traj.current_segment_at(t)
		if si < 0:
			break
		var seg: FlightTrajectory.Segment = _traj.segments[si]
		var c := seg.conic
		var stop := t_end
		var floor_r := sys.radius[body] + rails_floor()
		if c.rp < floor_r:
			var tf := c.time_to_radius(floor_r, t, false)
			if tf < INF and tf > t:
				stop = minf(stop, tf)
		if (seg.end == FlightTrajectory.End.ESCAPE or seg.end == FlightTrajectory.End.ENCOUNTER) and stop >= seg.t1:
			var s := c.state_at(seg.t1)
			px = s[0]
			py = s[1]
			pz = s[2]
			vx = s[3]
			vy = s[4]
			vz = s[5]
			t = seg.t1
			_switch_soi(seg.next_body)
			continue
		var s2 := c.state_at(stop)
		px = s2[0]
		py = s2[1]
		pz = s2[2]
		vx = s2[3]
		vy = s2[4]
		vz = s2[5]
		t = stop
		if seg.end == FlightTrajectory.End.HORIZON and t >= seg.t1:
			_traj = null
		break
	_track()
	return t


func _point_along_velocity() -> void:
	if craft.sas == FlightCraft.Sas.PROGRADE and speed() > 1.0:
		q = Quaternion(Vector3.UP, velocity_v3().normalized())


## Advances `dt` seconds of flight time: on rails when it may coast, else physics steps (at most
## `max_steps`; returns the flight time actually reached). `guide` (FlightGuide or null) steers
## before every physics step and may ask rails to stop at its next event.
func advance(dt: float, guide: RefCounted = null, max_steps := 400) -> float:
	var t_end := t + dt
	var steps := 0
	while t < t_end - 1e-9 and not crashed:
		var stop := t_end
		if guide:
			guide.call("update", self, 0.0)
			stop = minf(stop, maxf(float(guide.call("next_event", self)), t))
		if rails_ok() and stop - t > DT * 2.0:
			on_rails = true
			coast_to(stop)
			continue
		on_rails = false
		if steps >= max_steps:
			break
		if guide:
			guide.call("update", self, DT)
		step(DT)
		steps += 1
	if crashed and t < t_end:
		t = t_end
	return t


# ------------------------------------------------------------ queries for the HUD / report
## Seconds to the apoapsis (INF when none).
func time_to_apoapsis() -> float:
	return FlightOrbit.time_to_apoapsis(pos(), vel(), sys.mu[body])


func report(result: String) -> Dictionary:
	var el := elements()
	var r := stats.duplicate()
	r["result"] = result
	r["reason"] = crash_reason
	r["time"] = met()
	r["ap"] = el["ap_alt"]
	r["pe"] = el["pe_alt"]
	r["orbit"] = float(el["pe_alt"]) > ORBIT_PE and not crashed and body == sys.earth
	r["dv_used"] = craft.dv_used
	r["launched"] = launched
	r["dv_left"] = 0.0 if crashed else craft.total_dv()
	r["reached_moon"] = visited.has(sys.moon)
	r["landed"] = landed and t_liftoff >= 0.0 and not crashed
	r["body"] = sys.ids[body]
	return r
