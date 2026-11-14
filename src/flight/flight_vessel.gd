class_name FlightVessel
extends Node3D
## One flying rigid body: the active rocket or a separated piece (spent stage, booster,
## fairing). Visuals are the hangar's own PartInstance tree inside a `Vessel` child
## (so joint collars / engine shrouds come from JointDecor, exactly as in the hangar).
##
## Physics per fixed step (FlightBody integrates):
##   gravity (inverse square, in FlightBody), thrust of the lit engines of the current stage
##   with Isp interpolated sea level -> vacuum by ambient pressure and constant mass flow,
##   propellant drained from the group's pools (same pool rules as VesselMath), axial drag
##   from the frontal area with a transonic drag rise, normal force applied at the centre
##   of pressure (the hangar's centre-of-lift estimate) -> restoring / destabilizing torque,
##   aerodynamic pitch damping, control torque (gimbal + reaction wheels) and ground contact.
## Mass, centre of mass and inertia follow the propellant as it burns.

signal flight_event(key: String, data: Dictionary)

const PLUME_SCENE := preload("res://scenes/flight/engine_plume.tscn")
## Reaction-wheel torque (N·m) of parts that carry attitude control.
const WHEEL_TORQUE := {"avionics_core_s": 8000.0, "avionics_core_m": 40000.0, "crew_capsule": 30000.0,
	"reaction_wheels": 30000.0, "bus_small": 4000.0, "bus_medium": 8000.0, "bus_large": 15000.0}
const MIN_WHEEL_TORQUE := 1500.0
## Separation: radial boosters are pushed out at this speed (m/s)
const BOOSTER_PUSH := 2.5
const FAIRING_PUSH := 4.0
const IMPACT_SPEED := 8.0
## Structural limits (active vessel): q·sin(AoA) (Pa), dynamic pressure (Pa), load (g)
const LIMIT_Q_AOA := 9000.0
const LIMIT_Q := 90000.0
const LIMIT_G := 16.0

enum Sas { OFF, HOLD, PROGRADE, RETROGRADE, DIRECTION }

var vessel: Vessel
var decor: JointDecor
var body := FlightBody.new()
## state at the previous fixed step (render interpolation)
var prev := FlightBody.new()
var is_debris := false
var age := 0.0
var crashed := false
var crash_reason := ""

# mass properties (local frame = the hangar's vessel frame, +Y = nose)
var mass := 1.0
var com := Vector3.ZERO
var inertia := Vector3.ONE
var parts: Array[PartInstance] = []
## PartInstance -> {"c": centre, "r": radius, "h": height, "dry": kg, "lift": weight}
var info := {}
## PartInstance -> remaining propellant (tanks and solid motors), kg
var prop := {}
var prop0 := {}

# staging
var groups: Array = []
var stage_count := 0
## -1 = on the pad, nothing ignited yet
var current_stage := -1
var engines: Array = []
var pools: Array = []
var fairings: Array[PartInstance] = []

# aerodynamics
var a_front := 1.0
var a_side := 1.0
var length := 1.0
var cop := Vector3.ZERO
var cd := 0.4
var bounds_local := AABB()

# control
var throttle := 1.0
## player input: pitch (x), roll (y), yaw (z) in [-1, 1]
var input := Vector3.ZERO
var sas := Sas.OFF
var sas_hold := Quaternion.IDENTITY
var sas_dir := Vector3.UP
var authority := Vector3.ONE
var clamped := true
var landed := true
var ground_alt := 0.0
## pad position for ground contact (PCI)
var pad_up := Vector3.UP
var pad_alt := 0.0
var pad_radius := 30.0

# telemetry of the last step
var thrust_n := 0.0
var accel_ng := Vector3.ZERO
var g_load := 1.0
var q_dyn := 0.0
var aoa := 0.0
var mach := 0.0
var dv_used := 0.0
var pressure := 1.0


# ------------------------------------------------------------ setup
## Builds the active vessel from a saved hangar scene.
func setup_from_scene(ps: PackedScene) -> void:
	vessel = Vessel.new()
	vessel.name = "Vessel"
	add_child(vessel)
	vessel.load_scene(ps)
	_add_decor()
	groups = FlightStaging.groups(vessel)
	stage_count = FlightStaging.stage_count(groups)
	for p in vessel.all_parts():
		if PartDB.is_fairing(p.data):
			fairings.append(p)
		prop[p] = PartDB.prop_mass(p.data)
		prop0[p] = prop[p]
	_build_engines()
	_rebuild()


func _add_decor() -> void:
	decor = JointDecor.new()
	decor.name = "JointDecor"
	decor.vessel = vessel
	vessel.add_child(decor)
	decor.rebuild()


func _build_engines() -> void:
	engines.clear()
	pools.clear()
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		for pl in FlightStaging.pools(g["parts"]):
			var pool := {"propellant": pl["propellant"], "tanks": pl["tanks"], "engines": [], "solid": pl["solid"],
				"stage": g["stage"], "group": gi}
			for p: PartInstance in pl["engines"]:
				var d := p.data
				var f_vac := float(d.get("thrust_vac_kn", 0.0)) * 1000.0
				var isp_vac := float(d.get("isp_vac_s", 0.0))
				if f_vac <= 0.0 or isp_vac <= 0.0:
					continue
				var isp_sl := float(d.get("isp_sl_s", 0.0))
				var e := {"part": p, "pool": pool, "stage": g["stage"], "group": gi,
					"mdot": f_vac / (isp_vac * PartDB.G0), "isp_vac": isp_vac,
					# vacuum-only nozzles (no sea-level rating) separate badly at low altitude
					"isp_sl": isp_sl if isp_sl > 0.0 else isp_vac * 0.3,
					"tmin": float(d.get("throttle_min", 0.0)), "solid": pl["solid"],
					"gimbal": deg_to_rad(float(d.get("gimbal_deg", 0.0))),
					"restarts": int(d.get("restarts", 0)), "lit": false, "running": false,
					"thrust": 0.0, "plume": null, "pos": Vector3.ZERO, "dir": Vector3.UP}
				pool["engines"].append(e)
				engines.append(e)
				var plume: Node3D = PLUME_SCENE.instantiate()
				p.add_child(plume)
				plume.position = Vector3(0, p.aabb.position.y, 0)
				if plume.has_method("setup"):
					plume.call("setup", p.radius(), String(d.get("propellant", "")), f_vac)
				e["plume"] = plume
			pools.append(pool)


func _xf_of(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Recomputes per-part geometry and the aerodynamic summary after the tree changed.
func _rebuild() -> void:
	parts = vessel.all_parts() if vessel.root else ([] as Array[PartInstance])
	info.clear()
	var first := true
	var lw := 0.0
	var colv := Vector3.ZERO
	a_side = 0.0
	for p in parts:
		var xf := _xf_of(p)
		var c := xf * p.aabb.get_center()
		var b := xf * p.aabb
		bounds_local = b if first else bounds_local.merge(b)
		first = false
		var r := maxf(p.radius(), 0.05)
		var h := maxf(p.aabb.size.y, 0.05)
		info[p] = {"c": c, "r": r, "h": h, "dry": p.dry_mass(), "xz": Vector2(c.x, c.z)}
		if not prop.has(p):
			prop[p] = PartDB.prop_mass(p.data)
			prop0[p] = prop[p]
		if not PartDB.is_engine(p.data) or p.data.get("propellant", "") == "solid":
			colv += c * p.lift_weight()
			lw += p.lift_weight()
		a_side += h * 2.0 * r
	cop = colv / lw if lw > 0.0 else bounds_local.get_center()
	length = maxf(bounds_local.size.y, 1.0)
	a_front = _frontal_area()
	var top := _top_part()
	cd = 0.3 if top and (top.data.get("category", "") == "aero" or top.part_id == "crew_capsule") else 0.42
	for e in engines:
		var p: PartInstance = e["part"]
		if parts.has(p):
			var xf := _xf_of(p)
			e["pos"] = xf * Vector3(0, p.aabb.position.y, 0)
			e["dir"] = xf.basis.y.normalized()
	_update_mass(true, false)
	_update_inertia()


func _top_part() -> PartInstance:
	var best: PartInstance = null
	var y := -INF
	for p in parts:
		var top: float = (info[p]["c"] as Vector3).y + float(info[p]["h"]) * 0.5
		if top > y:
			y = top
			best = p
	return best


## Frontal area: union of the part discs projected along the axis, on a 32x32 grid.
func _frontal_area() -> float:
	var n := 32
	var x0 := bounds_local.position.x
	var z0 := bounds_local.position.z
	var sx := maxf(bounds_local.size.x, 0.1) / n
	var sz := maxf(bounds_local.size.z, 0.1) / n
	var hits := 0
	for i in n:
		for j in n:
			var pt := Vector2(x0 + (i + 0.5) * sx, z0 + (j + 0.5) * sz)
			for p in parts:
				var r: float = info[p]["r"]
				if pt.distance_squared_to(info[p]["xz"]) <= r * r:
					hits += 1
					break
	return maxf(hits * sx * sz, 0.05)


## Mass and centre of mass. When `shift` the body position follows the CoM so the parts
## stay where they are while the CoM moves inside the vessel.
func _update_mass(first := false, shift := true) -> void:
	var m := 0.0
	var c := Vector3.ZERO
	for p in parts:
		var pm: float = float(info[p]["dry"]) + float(prop.get(p, 0.0))
		m += pm
		c += (info[p]["c"] as Vector3) * pm
	m = maxf(m, 1.0)
	var new_com := c / m
	if shift and not first:
		var d := Basis(body.q) * (new_com - com)
		body.px += d.x
		body.py += d.y
		body.pz += d.z
		prev.px += d.x
		prev.py += d.y
		prev.pz += d.z
	mass = m
	com = new_com


func _update_inertia() -> void:
	var ix := 0.0
	var iy := 0.0
	var iz := 0.0
	for p in parts:
		var pm: float = float(info[p]["dry"]) + float(prop.get(p, 0.0))
		var r: float = info[p]["r"]
		var h: float = info[p]["h"]
		var d: Vector3 = (info[p]["c"] as Vector3) - com
		var it := pm * (3.0 * r * r + h * h) / 12.0
		ix += it + pm * (d.y * d.y + d.z * d.z)
		iy += pm * 0.5 * r * r + pm * (d.x * d.x + d.z * d.z)
		iz += it + pm * (d.x * d.x + d.y * d.y)
	inertia = Vector3(maxf(ix, 1.0), maxf(iy, 1.0), maxf(iz, 1.0))


# ------------------------------------------------------------ placement
## World (PCI) position of a local point, as doubles.
func local_to_pci(lp: Vector3) -> PackedFloat64Array:
	var d := Basis(body.q) * (lp - com)
	return PackedFloat64Array([body.px + d.x, body.py + d.y, body.pz + d.z])


## Places the node for rendering: body state interpolated between the last two steps,
## minus the floating origin (doubles), so the vessel renders near (0, 0, 0).
func update_render(alpha: float, ox: float, oy: float, oz: float) -> void:
	var x := prev.px + (body.px - prev.px) * alpha - ox
	var y := prev.py + (body.py - prev.py) * alpha - oy
	var z := prev.pz + (body.pz - prev.pz) * alpha - oz
	var qr := prev.q.slerp(body.q, alpha) if alpha < 1.0 else body.q
	var b := Basis(qr)
	transform = Transform3D(b, Vector3(x, y, z) - b * com)


func render_pci(alpha: float) -> PackedFloat64Array:
	return PackedFloat64Array([prev.px + (body.px - prev.px) * alpha, prev.py + (body.py - prev.py) * alpha,
		prev.pz + (body.pz - prev.pz) * alpha])


## Puts the vessel on the pad: lowest point on the launcher deck, nose up, still.
func place_on_pad(pad_top_alt: float, up_axis: Vector3, top_axis: Vector3) -> void:
	pad_up = up_axis
	pad_alt = pad_top_alt
	var right := up_axis.cross(top_axis).normalized()
	# local +X = right, +Y = nose (up), +Z = top
	var b := Basis(right, up_axis, top_axis).orthonormalized()
	body.q = b.get_rotation_quaternion()
	var lowest := bounds_local.position.y - com.y
	var r := FlightOrbit.R + pad_top_alt - lowest
	body.px = up_axis.x * r
	body.py = up_axis.y * r
	body.pz = up_axis.z * r
	body.vx = 0.0
	body.vy = 0.0
	body.vz = 0.0
	body.w = Vector3.ZERO
	prev.copy_from(body)
	clamped = true
	landed = true


# ------------------------------------------------------------ staging
func ignite(stage: int) -> void:
	for e in engines:
		if e["stage"] == stage and parts.has(e["part"]):
			e["lit"] = true
			e["running"] = e["solid"] or throttle > 0.001


## Space bar. Returns the separated pieces (new FlightVessels, already in the tree).
func activate_next_stage() -> Array[FlightVessel]:
	var out: Array[FlightVessel] = []
	if current_stage < 0:
		current_stage = 0
		ignite(0)
		clamped = false
		flight_event.emit("EV_IGNITION", {"stage": 1})
		return out
	if current_stage >= stage_count - 1:
		return out
	var max_level := 0
	for g in groups:
		max_level = maxi(max_level, g["level"])
	var level := max_level - current_stage
	for g in groups:
		if g["kind"] == "stack" and g["level"] == level and g["root"] != vessel.root and _attached(g["root"]):
			var push: float = float((g["root"] as PartInstance).data.get("ejection_impulse_kns", 1.0)) * 1000.0
			out.append(_detach(g["root"], Vector3.ZERO, push))
	current_stage += 1
	flight_event.emit("EV_STAGE_SEP", {"stage": current_stage})
	if current_stage == 1:
		out.append_array(jettison_fairings())
	ignite(current_stage)
	flight_event.emit("EV_IGNITION", {"stage": current_stage + 1})
	return out


func jettison_fairings() -> Array[FlightVessel]:
	var out: Array[FlightVessel] = []
	for f in fairings:
		if _attached(f):
			var side := Vector3((info[f]["c"] as Vector3).x, 0, (info[f]["c"] as Vector3).z)
			out.append(_detach(f, side.normalized() if side.length() > 0.01 else Vector3.RIGHT, 0.0, FAIRING_PUSH))
			flight_event.emit("EV_FAIRING", {})
	return out


func _attached(p: Variant) -> bool:
	return is_instance_valid(p) and vessel.is_ancestor_of(p)


## Detaches the subtree at `p` into a new debris body. `impulse` (N·s) pushes the two
## apart along the vessel axis; `push_dir`/`push_speed` add a sideways push (boosters).
func _detach(p: PartInstance, push_dir: Vector3, impulse: float, push_speed := 0.0) -> FlightVessel:
	var xf := _xf_of(p)
	var deb := FlightVessel.new()
	deb.name = "Debris_" + p.part_id
	deb.is_debris = true
	deb.vessel = Vessel.new()
	deb.vessel.name = "Vessel"
	deb.add_child(deb.vessel)
	p.get_parent().remove_child(p)
	for q in p.subtree():
		q.sym_group = []
	deb.vessel.set_root(p)
	deb.vessel.transform = xf
	deb.throttle = 0.0
	deb.clamped = false
	deb.landed = false
	deb.pad_up = pad_up
	deb.pad_alt = pad_alt
	for q in p.subtree():
		deb.prop[q] = prop.get(q, 0.0)
		deb.prop0[q] = prop0.get(q, 0.0)
	# engines, pools and propellant records that left with the piece belong to it now
	for e in engines:
		if not _attached(e["part"]):
			e["lit"] = false
			e["running"] = false
			e["thrust"] = 0.0
			if is_instance_valid(e["plume"]):
				e["plume"].call("set_state", 0.0, 1.0)
	engines = engines.filter(func(e: Dictionary) -> bool: return _attached(e["part"]))
	for pool in pools:
		pool["tanks"] = (pool["tanks"] as Array).filter(func(t: Variant) -> bool: return _attached(t))
		pool["engines"] = (pool["engines"] as Array).filter(func(e: Dictionary) -> bool: return _attached(e["part"]))
	pools = pools.filter(func(pool: Dictionary) -> bool: return not (pool["engines"] as Array).is_empty())
	for q in p.subtree():
		prop.erase(q)
		prop0.erase(q)
	fairings = fairings.filter(func(f: Variant) -> bool: return _attached(f))
	get_parent().add_child(deb)
	deb.transform = transform
	deb._add_decor()
	deb._rebuild()
	var old_com := com
	_rebuild()
	if decor:
		decor.rebuild()
	# the parts did not move: shift both CoMs in PCI
	var b := Basis(body.q)
	var d_self := b * (com - old_com)
	var d_deb := b * (deb.com - old_com)
	deb.body.copy_from(body)
	deb.body.px += d_deb.x
	deb.body.py += d_deb.y
	deb.body.pz += d_deb.z
	body.px += d_self.x
	body.py += d_self.y
	body.pz += d_self.z
	# rigid rotation: v_piece = v + ω × r
	var wv := b * body.w
	var rv := wv.cross(d_deb)
	deb.body.vx += rv.x
	deb.body.vy += rv.y
	deb.body.vz += rv.z
	var axis := b * Vector3.UP
	if impulse > 0.0:
		var dv_d := -axis * (impulse / deb.mass)
		var dv_s := axis * (impulse / mass)
		deb.body.vx += dv_d.x
		deb.body.vy += dv_d.y
		deb.body.vz += dv_d.z
		body.vx += dv_s.x
		body.vy += dv_s.y
		body.vz += dv_s.z
	if push_speed > 0.0:
		var out_w := b * push_dir.normalized()
		deb.body.vx += out_w.x * push_speed
		deb.body.vy += out_w.y * push_speed
		deb.body.vz += out_w.z * push_speed
		# tip the nose outward
		deb.body.w += push_dir.normalized().cross(Vector3.UP) * -0.25
	prev.copy_from(body)
	deb.prev.copy_from(deb.body)
	return deb


## Drops boosters whose propellant is gone (like VesselMath: as soon as they are empty).
func _check_boosters() -> Array[FlightVessel]:
	var out: Array[FlightVessel] = []
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		if g["kind"] != "booster" or g["stage"] != current_stage or not _attached(g["root"]):
			continue
		var has_engine := false
		var empty := true
		for pool in pools:
			if pool["group"] == gi and not pool["engines"].is_empty():
				has_engine = true
				if pool_prop(pool) > 1e-3:
					empty = false
		if has_engine and empty:
			var root: PartInstance = g["root"]
			var c := _subtree_center(root)
			var side := Vector3(c.x - com.x, 0, c.z - com.z)
			out.append(_detach(root, side.normalized() if side.length() > 0.01 else Vector3.RIGHT, 0.0, BOOSTER_PUSH))
			flight_event.emit("EV_BOOSTER_SEP", {})
	return out


func _subtree_center(p: PartInstance) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for q in p.subtree():
		c += info[q]["c"]
		n += 1
	return c / maxf(n, 1)


func pool_prop(pool: Dictionary) -> float:
	var s := 0.0
	for t in pool["tanks"]:
		if _attached(t):
			s += float(prop.get(t, 0.0))
	return s


func _drain(pool: Dictionary, amount: float) -> void:
	var total := pool_prop(pool)
	if total <= 0.0:
		return
	var k := clampf(amount / total, 0.0, 1.0)
	for t in pool["tanks"]:
		if _attached(t):
			prop[t] = float(prop[t]) * (1.0 - k)


# ------------------------------------------------------------ physics
## One fixed step. Returns pieces dropped this step (empty boosters).
func physics_step(dt: float) -> Array[FlightVessel]:
	prev.copy_from(body)
	age += dt
	var dropped: Array[FlightVessel] = []
	if crashed:
		return dropped
	var alt := body.altitude()
	var rho := FlightOrbit.density(alt)
	pressure = rho / FlightOrbit.RHO0
	var b := Basis(body.q)
	var f := Vector3.ZERO
	var tq := Vector3.ZERO
	# --- thrust
	thrust_n = 0.0
	var gimbal_auth := 0.0
	var roll_auth := 0.0
	for pool in pools:
		var demand := 0.0
		for e in pool["engines"]:
			e["thrust"] = 0.0
			var thr := _engine_throttle(e)
			e["thr"] = thr
			demand += float(e["mdot"]) * thr * dt
		if demand <= 0.0:
			continue
		var avail := pool_prop(pool)
		var frac := clampf(avail / demand, 0.0, 1.0) if demand > 0.0 else 0.0
		if frac <= 0.0:
			for e in pool["engines"]:
				if e["running"]:
					e["running"] = false
					flight_event.emit("EV_FLAMEOUT", {"stage": int(e["stage"]) + 1})
			continue
		_drain(pool, demand * frac)
		for e in pool["engines"]:
			var thr: float = e["thr"]
			if thr <= 0.0:
				continue
			var isp: float = float(e["isp_vac"]) + (float(e["isp_sl"]) - float(e["isp_vac"])) * pressure
			var fe: float = float(e["mdot"]) * thr * frac * PartDB.G0 * isp
			e["thrust"] = fe
			thrust_n += fe
			var dir: Vector3 = e["dir"]
			var arm: Vector3 = (e["pos"] as Vector3) - com
			f += dir * fe
			tq += arm.cross(dir * fe)
			var s := sin(float(e["gimbal"])) * fe
			gimbal_auth += s * absf(arm.dot(dir))
			roll_auth += s * Vector2(arm.x, arm.z).length() * 0.5
	if clamped:
		_hold_clamps()
		_update_engines_visual()
		g_load = 1.0
		return dropped
	# --- aerodynamics (air at rest in PCI: the Earth model does not rotate)
	var v := body.velocity_v3()
	var vl := b.transposed() * v
	var speed := vl.length()
	q_dyn = 0.5 * rho * speed * speed
	mach = speed / FlightOrbit.SOUND_SPEED
	aoa = 0.0
	if rho > 0.0 and speed > 0.5:
		var vh := vl / speed
		var cosa := vh.y
		var vn := Vector3(vh.x, 0, vh.z)
		var sina := vn.length()
		aoa = atan2(sina, cosa)
		var cdm := cd * (1.0 + 1.1 * exp(-pow((mach - 1.1) / 0.4, 2.0)))
		f += Vector3(0, -q_dyn * cdm * a_front * cosa * absf(cosa), 0)
		f += -vh * q_dyn * cd * 0.15 * a_front  # skin friction
		if sina > 1e-5:
			var nmag := q_dyn * (2.0 * a_front * sina * absf(cosa) + 0.9 * a_side * sina * sina)
			var fn := -vn / sina * nmag
			f += fn
			tq += (cop - com).cross(fn)
		var damp := q_dyn * a_side * length * length * 0.12 / maxf(speed, 20.0)
		tq -= Vector3(body.w.x, 0, body.w.z) * damp
		tq.y -= body.w.y * q_dyn * a_front * 0.5 * length / maxf(speed, 20.0)
	# --- control: gimbal + reaction wheels
	var wheels := _wheel_torque()
	authority = Vector3(wheels + gimbal_auth, wheels + roll_auth, wheels + gimbal_auth)
	if not is_debris:
		var u := _control_input()
		tq += Vector3(u.x * authority.x, u.y * authority.y, u.z * authority.z)
	# --- integrate
	var fw := b * f
	accel_ng = fw / mass
	body.step(dt, accel_ng.x, accel_ng.y, accel_ng.z, tq, inertia)
	_ground_contact(dt)
	g_load = accel_ng.length() / PartDB.G0
	if landed:
		g_load = maxf(g_load, 1.0)
	dv_used += thrust_n / mass * dt
	_update_mass()
	if int(age / dt) % 10 == 0:
		_update_inertia()
	if not is_debris:
		_check_limits()
		dropped = _check_boosters()
	_update_engines_visual()
	return dropped


func _engine_throttle(e: Dictionary) -> float:
	if not e["lit"] or not parts.has(e["part"]):
		return 0.0
	if e["solid"]:
		return 1.0 if e["running"] else 0.0
	if throttle <= 0.001:
		if e["running"]:
			e["running"] = false
		return 0.0
	if not e["running"]:
		if int(e["restarts"]) <= 0:
			return 0.0
		e["restarts"] = int(e["restarts"]) - 1
		e["running"] = true
	return maxf(throttle, float(e["tmin"]))


func _wheel_torque() -> float:
	var t := 0.0
	for p in parts:
		t += float(WHEEL_TORQUE.get(p.part_id, 0.0))
	return maxf(t, MIN_WHEEL_TORQUE) if not is_debris else 0.0


func _hold_clamps() -> void:
	body.vx = 0.0
	body.vy = 0.0
	body.vz = 0.0
	body.w = Vector3.ZERO
	q_dyn = 0.0
	accel_ng = Vector3.ZERO


func _ground_contact(dt: float) -> void:
	var up := body.up()
	var b := Basis(body.q)
	var lowest := INF
	var corners := 8
	for i in corners:
		var c := Vector3(bounds_local.position.x if i & 1 == 0 else bounds_local.end.x,
			bounds_local.position.y if i & 2 == 0 else bounds_local.end.y,
			bounds_local.position.z if i & 4 == 0 else bounds_local.end.z)
		lowest = minf(lowest, (b * (c - com)).dot(up))
	var alt := body.altitude()
	var horiz := (up - pad_up).length() * FlightOrbit.R
	ground_alt = pad_alt if horiz < pad_radius else 0.0
	var pen := ground_alt - (alt + lowest)
	if pen <= 0.0:
		landed = false
		return
	var vs := body.vertical_speed()
	if vs < -IMPACT_SPEED or (not landed and body.speed() > IMPACT_SPEED * 2.0):
		_crash("CRASH_IMPACT")
		return
	landed = true
	body.px += up.x * pen
	body.py += up.y * pen
	body.pz += up.z * pen
	if vs < 0.0:
		body.vx -= up.x * vs
		body.vy -= up.y * vs
		body.vz -= up.z * vs
	var k := exp(-dt * 4.0)
	var vsn := body.vertical_speed()
	body.vx = (body.vx - up.x * vsn) * k + up.x * vsn
	body.vy = (body.vy - up.y * vsn) * k + up.y * vsn
	body.vz = (body.vz - up.z * vsn) * k + up.z * vsn
	body.w *= k


func _check_limits() -> void:
	if q_dyn * sin(minf(aoa, PI * 0.5)) > LIMIT_Q_AOA and aoa > deg_to_rad(4.0):
		_crash("CRASH_AERO")
	elif q_dyn > LIMIT_Q:
		_crash("CRASH_Q")
	elif g_load > LIMIT_G:
		_crash("CRASH_G")


func _crash(reason: String) -> void:
	if crashed:
		return
	crashed = true
	crash_reason = reason
	for e in engines:
		e["running"] = false
		e["thrust"] = 0.0
	flight_event.emit("EV_CRASH", {"reason": reason})


func _update_engines_visual() -> void:
	for e in engines:
		var pl: Variant = e["plume"]
		if not is_instance_valid(pl):
			continue
		var thr: float = float(e.get("thr", 0.0)) if float(e["thrust"]) > 0.0 else 0.0
		pl.call("set_state", thr, pressure)


# ------------------------------------------------------------ attitude control
func _control_input() -> Vector3:
	var u := input
	if u.length_squared() > 1e-4:
		# the pilot is steering: SAS lets go and re-captures the attitude afterwards
		sas_hold = body.q
		return u.clamp(-Vector3.ONE, Vector3.ONE)
	if sas == Sas.OFF:
		return Vector3.ZERO
	var target := sas_hold
	var nose := Basis(body.q) * Vector3.UP
	var want := Vector3.ZERO
	match sas:
		Sas.PROGRADE:
			if body.speed() > 1.0:
				want = body.velocity_v3().normalized()
		Sas.RETROGRADE:
			if body.speed() > 1.0:
				want = -body.velocity_v3().normalized()
		Sas.DIRECTION:
			want = sas_dir.normalized()
	if want != Vector3.ZERO:
		if nose.dot(want) < -0.9999:
			want = (want + Basis(body.q) * Vector3.RIGHT * 0.01).normalized()
		target = Quaternion(nose, want) * body.q
	return attitude_command(target)


## PD attitude controller limited by the available angular acceleration. Returns the
## control input (pitch, roll, yaw) in [-1, 1].
func attitude_command(target: Quaternion) -> Vector3:
	var err := body.q.inverse() * target
	if err.w < 0.0:
		err = -err
	var ang := 2.0 * acos(clampf(err.w, -1.0, 1.0))
	var e := Vector3.ZERO
	if ang > 1e-6:
		e = Vector3(err.x, err.y, err.z).normalized() * ang
	var u := Vector3.ZERO
	for i in 3:
		var alpha: float = maxf(authority[i] / inertia[i], 1e-4)
		var ei: float = e[i]
		var wmax := minf(0.5, sqrt(2.0 * 0.4 * alpha * absf(ei)))
		var wd: float = signf(ei) * minf(1.2 * absf(ei), wmax)
		var tq_req: float = (wd - body.w[i]) * inertia[i] / 0.35
		u[i] = clampf(tq_req / maxf(authority[i], 1.0), -1.0, 1.0)
	return u


func set_sas(mode: int) -> void:
	sas = mode as Sas
	sas_hold = body.q


# ------------------------------------------------------------ queries for the HUD
func nose_world() -> Vector3:
	return Basis(body.q) * Vector3.UP


func stage_engines(stage: int) -> Array:
	var out: Array = []
	for e in engines:
		if e["stage"] == stage and _attached(e["part"]):
			out.append(e)
	return out


## Propellant fraction left in stage `stage`: [core remaining, core initial, booster remaining, booster initial]
func stage_fuel(stage: int) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for pool in pools:
		if pool["stage"] != stage:
			continue
		var booster: bool = groups[pool["group"]]["kind"] == "booster"
		for t in pool["tanks"]:
			var k := 2 if booster else 0
			out[k + 1] += float(prop0.get(t, 0.0))
			if _attached(t):
				out[k] += float(prop.get(t, 0.0))
	return out


## Δv left per stage from VesselMath with the propellant that is actually left, so it
## uses exactly the hangar's math. Returns [{stage, dv (at current pressure), dv_vac}].
func remaining_dv() -> Array:
	var out: Array = []
	var first := maxi(current_stage, 0)
	var specs: Array = []
	for s in range(first, stage_count):
		var spec := {"core": [], "boosters": []}
		for gi in groups.size():
			var g: Dictionary = groups[gi]
			if g["stage"] != s:
				continue
			var datas: Array = []
			for pv in g["parts"]:
				if not _attached(pv):
					continue
				var p: PartInstance = pv
				if PartDB.is_fairing(p.data):
					continue
				var d := p.data.duplicate()
				if PartDB.prop_mass(d) > 0.0:
					d["prop_mass_kg"] = prop.get(p, 0.0)
				datas.append(d)
			if g["kind"] == "booster":
				if not datas.is_empty():
					spec["boosters"].append(datas)
			else:
				spec["core"].append_array(datas)
		specs.append(spec)
	if specs.is_empty():
		return out
	var fairing_kg := 0.0
	for fp in fairings:
		if _attached(fp):
			fairing_kg += fp.dry_mass()
	var drop := 2 if current_stage <= 0 else 1
	var res := VesselMath.analyze(specs, 0.0, fairing_kg, drop)
	for st in res["stages"]:
		var i: int = int(st["stage"]) - 1
		var dv: float = st["dv_vac"]
		if i == 0:
			dv = lerpf(float(st["dv_vac"]), float(st["dv_sl"]), pressure)
		out.append({"stage": first + i, "dv": dv, "dv_vac": st["dv_vac"], "twr": st["twr_vac"]})
	return out
