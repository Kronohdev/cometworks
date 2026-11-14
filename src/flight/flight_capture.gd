class_name FlightCapture
extends RefCounted
## Automatic orbit insertion planner: from the current plan (nodes already placed, e.g. a
## trans-lunar injection) to a chosen orbit around the body the trajectory encounters.
## It adds up to two maneuver nodes:
##   1. a mid-course correction (if there is time before the encounter) that aims the
##      arrival: periapsis altitude and, optionally, the orbit inclination;
##   2. the capture burn at the periapsis: retrograde, down to the chosen apoapsis
##      (apoapsis = periapsis -> circular orbit).
##
## Aiming uses the B-plane of the arrival: the plane through the body perpendicular to the
## arrival velocity S at the SOI entry. The vector B (S x h / v) is the miss distance of
## the arrival line; its length sets the periapsis radius, its direction the orbit plane
## (h = B x S). The correction's normal / radial Δv is found by Newton iterations on the
## 2-D B error, each evaluation a full patched-conic prediction (FlightTrajectory.predict).
## Pure math on RefCounted data: no scene access.

## reference for the inclination: the body's own orbit plane around its parent (0° =
## orbiting the same way the body goes round its parent, 90° = polar, 180° = retrograde)
const MAX_ITER := 14
const FD_STEP := 0.1
const MAX_STEP_DV := 400.0
## correction placed this far into the coast (fraction of the time to the encounter)
const CORR_FRACTION := 0.15
const MIN_COAST := 600.0

var sys: FlightSolar
var soi := 0
var r := PackedFloat64Array()
var v := PackedFloat64Array()
var now := 0.0
## existing plan (FlightManeuverNode, sorted); not modified (copies are predicted)
var base: Array[FlightManeuverNode] = []
## burn time estimate of the last existing node (s)
var last_burn := 0.0


func _init(s: FlightSolar, soi_body: int, pos: PackedFloat64Array, vel: PackedFloat64Array, t: float,
		nodes: Array[FlightManeuverNode], last_node_burn := 0.0) -> void:
	sys = s
	soi = soi_body
	r = pos
	v = vel
	now = t
	for n in nodes:
		base.append(_copy(n))
	last_burn = last_node_burn


## Body the current plan arrives at (encounter after the last node), or the current SOI
## body when the vessel is passing through it unbound; -1 if none.
## -> {"body", "t_enter"}
func target() -> Dictionary:
	var tr := _predict(base)
	var k := base.size()
	for i in tr.segments.size():
		var s := tr.segments[i]
		if s.plan != k:
			continue
		if i > 0 and tr.segments[i - 1].end == FlightTrajectory.End.ENCOUNTER:
			return {"body": s.body, "t_enter": s.t0}
		if i == 0 and sys.parent[s.body] >= 0 and (s.end == FlightTrajectory.End.ESCAPE or not s.conic.is_closed()):
			return {"body": s.body, "t_enter": s.t0}
	return {}


## Lowest periapsis altitude allowed around body b (above the air / the surface margin).
func min_altitude(b: int) -> float:
	if sys.atmo_top[b] > 0.0:
		return sys.atmo_top[b] + 10000.0
	return maxf(10000.0, sys.radius[b] * 0.01)


## Plans the insertion. inc_deg = NAN keeps the arrival's orbit plane.
## -> {"ok", "msg" (translation key), "nodes": [{"t", "dv"}], "pe", "ap", "inc", "dv_corr",
##     "dv_capt", "body"}
func plan(pe_alt: float, ap_alt: float, inc_deg: float) -> Dictionary:
	var tg := target()
	if tg.is_empty():
		return {"ok": false, "msg": "FL_CAPT_NO_ENCOUNTER"}
	var b: int = tg["body"]
	var t_enter: float = tg["t_enter"]
	for n in base:
		if n.time >= t_enter:
			return {"ok": false, "msg": "FL_CAPT_NODES_AFTER"}
	pe_alt = maxf(pe_alt, min_altitude(b))
	var rp_des := sys.radius[b] + pe_alt
	var out := {"ok": true, "msg": "", "body": b, "nodes": [], "dv_corr": 0.0, "dv_capt": 0.0}
	var nodes: Array[FlightManeuverNode] = base.duplicate()
	var k := base.size()
	# --- 1. mid-course correction
	var t_prev := now + 60.0
	if not base.is_empty():
		t_prev = maxf(t_prev, base[-1].time + last_burn * 0.5 + 60.0)
	if t_enter - t_prev > MIN_COAST:
		var c := FlightManeuverNode.new(t_prev + (t_enter - t_prev) * CORR_FRACTION)
		nodes.append(c)
		var res := _aim(nodes, k + 1, b, rp_des, inc_deg, c)
		if res.is_empty():
			return {"ok": false, "msg": "FL_CAPT_AIM_FAILED"}
		if c.dv.length() > 0.05:
			out["nodes"].append({"t": c.time, "dv": c.dv})
			out["dv_corr"] = c.dv.length()
			k += 1
		else:
			nodes.pop_back()
	# --- 2. capture at the periapsis
	var tr := _predict(nodes)
	var seg := _segment(tr, b, k)
	if seg == null:
		return {"ok": false, "msg": "FL_CAPT_NO_ENCOUNTER"}
	var cn := seg.conic
	var t_pe := cn.time_at_true_anomaly(0.0, seg.t0) if not cn.degenerate else INF
	if t_pe > seg.t1 or cn.rp < sys.radius[b]:
		return {"ok": false, "msg": "FL_CAPT_IMPACT"}
	var rp := cn.rp
	var ra := clampf(sys.radius[b] + ap_alt, rp, sys.soi[b] * 0.9 if sys.soi[b] < INF else 1.0e13)
	var v_p := sqrt(maxf(2.0 * (cn.energy + cn.mu / rp), 0.0))
	var v_t := sqrt(cn.mu * (2.0 / rp - 2.0 / (rp + ra)))
	var dv := Vector3(v_t - v_p, 0.0, 0.0)
	out["nodes"].append({"t": t_pe, "dv": dv})
	out["dv_capt"] = absf(dv.x)
	# --- check: the orbit after the capture
	nodes.append(FlightManeuverNode.new(t_pe, dv))
	tr = _predict(nodes)
	var fin := _segment(tr, b, k + 1)
	if fin != null:
		out["pe"] = fin.conic.rp - sys.radius[b]
		out["ap"] = fin.conic.ra - sys.radius[b] if fin.conic.is_closed() else INF
		out["inc"] = _inclination(fin.conic, b)
	else:
		out["pe"] = rp - sys.radius[b]
		out["ap"] = ra - sys.radius[b]
		out["inc"] = _inclination(cn, b)
	if absf(float(out["pe"]) - pe_alt) > maxf(0.05 * pe_alt, 5000.0):
		out["msg"] = "FL_CAPT_APPROX"
	return out


# ------------------------------------------------------------ aiming (B-plane Newton)
## Adjusts node c (normal, radial Δv) so the arrival at body b (plan index `pl`) has
## periapsis radius rp_des and inclination inc_deg (NAN: keep the plane). {} on failure.
func _aim(nodes: Array[FlightManeuverNode], pl: int, b: int, rp_des: float, inc_deg: float,
		c: FlightManeuverNode) -> Dictionary:
	var err := _b_error(nodes, pl, b, rp_des, inc_deg)
	if err.is_empty():
		return {}
	for it in MAX_ITER:
		var e0: Vector2 = err["e"]
		if e0.length() < maxf(float(err["b"]) * 2.0e-4, 300.0):
			break
		# Jacobian by finite differences (normal = dv.y, radial = dv.z)
		var u := c.dv
		c.dv = u + Vector3(0.0, FD_STEP, 0.0)
		var en := _b_error(nodes, pl, b, rp_des, inc_deg, err["frame"])
		c.dv = u + Vector3(0.0, 0.0, FD_STEP)
		var er := _b_error(nodes, pl, b, rp_des, inc_deg, err["frame"])
		c.dv = u
		if en.is_empty() or er.is_empty():
			break
		var j1: Vector2 = (en["e"] - e0) / FD_STEP
		var j2: Vector2 = (er["e"] - e0) / FD_STEP
		var det := j1.x * j2.y - j2.x * j1.y
		if absf(det) < 1e-12:
			break
		# solve J * d = -e0
		var d := Vector2((-e0.x * j2.y + j2.x * e0.y) / det, (-j1.x * e0.y + e0.x * j1.y) / det)
		if d.length() > MAX_STEP_DV:
			d = d.normalized() * MAX_STEP_DV
		# line search: accept the first step that reduces the error
		var accepted := false
		var f := 1.0
		for ls in 6:
			c.dv = u + Vector3(0.0, d.x * f, d.y * f)
			var e1 := _b_error(nodes, pl, b, rp_des, inc_deg)
			if not e1.is_empty() and (e1["e"] as Vector2).length() < e0.length():
				err = e1
				accepted = true
				break
			f *= 0.5
		if not accepted:
			c.dv = u
			break
	return err


## B-plane error of the arrival at b: {"e": Vector2 (m), "b": |B desired|, "frame": [S, e1, e2]}.
## `frame`: evaluate in a given frame (Jacobian columns), else the arrival's own.
func _b_error(nodes: Array[FlightManeuverNode], pl: int, b: int, rp_des: float, inc_deg: float,
		frame: Array = []) -> Dictionary:
	var tr := _predict(nodes)
	var seg := _segment(tr, b, pl)
	if seg == null:
		return {}
	var st := seg.conic.state_at(seg.t0)
	var re := Vector3(st[0], st[1], st[2])
	var ve := Vector3(st[3], st[4], st[5])
	var vn := ve.length()
	if vn < 1e-3:
		return {}
	var s := ve / vn
	var h := re.cross(ve)
	var b_act := s.cross(h) / vn
	var n_ref := sys.orbit_normal(b)
	var e1: Vector3
	var e2: Vector3
	if frame.is_empty():
		e1 = n_ref - s * n_ref.dot(s)
		if e1.length_squared() < 1e-8:
			e1 = s.cross(Vector3.RIGHT if absf(s.x) < 0.9 else Vector3.UP)
		e1 = e1.normalized()
		e2 = s.cross(e1)
		frame = [s, e1, e2]
	else:
		s = frame[0]
		e1 = frame[1]
		e2 = frame[2]
	# |B| for the wanted periapsis (energy / momentum conservation from the SOI entry)
	var mu_b := sys.mu[b]
	var k := 1.0 + 2.0 * mu_b / (rp_des * vn * vn) - 2.0 * mu_b / (re.length() * vn * vn)
	var b_len := rp_des * sqrt(maxf(k, 0.0))
	# wanted orbit normal: perpendicular to S, at the wanted inclination to n_ref, the one
	# closest to the arrival's own plane (cheapest); NAN: keep the plane
	var h_now := h - s * h.dot(s)
	var h_hat := h_now.normalized() if h_now.length_squared() > 1e-6 else e2
	if not is_nan(inc_deg):
		var c_n := n_ref.dot(e1)  # = |n_ref projected on the B plane|
		var ci := clampf(cos(deg_to_rad(inc_deg)) / maxf(c_n, 1e-6), -1.0, 1.0)
		var phi := acos(ci)
		var ha := (e1 * cos(phi) + e2 * sin(phi)).normalized()
		var hb := (e1 * cos(phi) - e2 * sin(phi)).normalized()
		h_hat = ha if ha.dot(h_hat) >= hb.dot(h_hat) else hb
	var b_des := s.cross(h_hat) * b_len
	var d := b_act - b_des
	return {"e": Vector2(d.dot(e1), d.dot(e2)), "b": b_len, "frame": frame}


# ------------------------------------------------------------ helpers
func _predict(nodes: Array[FlightManeuverNode]) -> FlightTrajectory:
	return FlightTrajectory.predict(sys, soi, r, v, now, nodes)


## First segment around body b on plan index pl.
static func _segment(tr: FlightTrajectory, b: int, pl: int) -> FlightTrajectory.Segment:
	for s in tr.segments:
		if s.plan == pl and s.body == b:
			return s
	return null


func _inclination(c: FlightConic, b: int) -> float:
	return rad_to_deg(Vector3(c.wx, c.wy, c.wz).angle_to(sys.orbit_normal(b)))


static func _copy(n: FlightManeuverNode) -> FlightManeuverNode:
	var o := FlightManeuverNode.new(n.time, n.dv)
	o.burned = n.burned
	o.locked = n.locked
	o.dv_world = n.dv_world.duplicate()
	return o
