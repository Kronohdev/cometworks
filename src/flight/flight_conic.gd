class_name FlightConic
extends RefCounted
## One two-body conic (ellipse or hyperbola) in double precision, built from a state
## vector at an absolute time. Positions are relative to the attracting body, in the
## inertial PCI axes (see FlightOrbit). Used by the patched-conic predictor
## (FlightTrajectory), on-rails time warp and the map.
##
## Perifocal basis: P -> periapsis, Q -> 90 deg ahead along the motion, W = orbit normal.
## Time is tied to the anomalies through the time of periapsis passage `t_peri`:
##   ellipse   M = n (t - t_peri) = E - e sin E
##   hyperbola M = n (t - t_peri) = e sinh H - H
## Radial (h ~ 0) and near-parabolic orbits fall back to universal-variable propagation
## from the stored epoch state (FlightOrbit.propagate).

var mu := FlightOrbit.MU
var e := 0.0
## semi-major axis (m); negative for hyperbolas
var a := 0.0
## semi-latus rectum (m)
var p := 0.0
var rp := 0.0
var ra := INF
## mean motion (rad/s)
var n := 0.0
var period := INF
var t_peri := 0.0
var energy := 0.0
var px := 1.0
var py := 0.0
var pz := 0.0
var qx := 0.0
var qy := 1.0
var qz := 0.0
var wx := 0.0
var wy := 0.0
var wz := 1.0
## epoch state (fallback propagation and debugging)
var t0 := 0.0
var r0 := PackedFloat64Array([0.0, 0.0, 0.0])
var v0 := PackedFloat64Array([0.0, 0.0, 0.0])
var degenerate := false


static func from_state(r: PackedFloat64Array, v: PackedFloat64Array, gm: float, t: float) -> FlightConic:
	var c := FlightConic.new()
	c.mu = gm
	c.t0 = t
	c.r0 = r.duplicate()
	c.v0 = v.duplicate()
	var rn := FlightOrbit.length(r)
	var v2 := FlightOrbit.dot(v, v)
	var hx := r[1] * v[2] - r[2] * v[1]
	var hy := r[2] * v[0] - r[0] * v[2]
	var hz := r[0] * v[1] - r[1] * v[0]
	var hn := sqrt(hx * hx + hy * hy + hz * hz)
	c.energy = v2 * 0.5 - gm / rn
	var k := v2 - gm / rn
	var rv := FlightOrbit.dot(r, v)
	var ex := (k * r[0] - rv * v[0]) / gm
	var ey := (k * r[1] - rv * v[1]) / gm
	var ez := (k * r[2] - rv * v[2]) / gm
	c.e = sqrt(ex * ex + ey * ey + ez * ez)
	c.p = hn * hn / gm
	c.rp = c.p / (1.0 + c.e)
	c.a = -gm / (2.0 * c.energy) if absf(c.energy) > 1e-12 else INF
	if hn < 1e-3 * rn or absf(c.e - 1.0) < 1e-7:
		c.degenerate = true
		c.ra = INF if c.energy >= 0.0 else -gm / c.energy
		if c.energy < 0.0:
			c.period = TAU * sqrt(c.a * c.a * c.a / gm)
		return c
	c.wx = hx / hn
	c.wy = hy / hn
	c.wz = hz / hn
	if c.e > 1e-9:
		c.px = ex / c.e
		c.py = ey / c.e
		c.pz = ez / c.e
	else:
		c.e = 0.0
		c.px = r[0] / rn
		c.py = r[1] / rn
		c.pz = r[2] / rn
	# Q = W x P
	c.qx = c.wy * c.pz - c.wz * c.py
	c.qy = c.wz * c.px - c.wx * c.pz
	c.qz = c.wx * c.py - c.wy * c.px
	var nu := atan2(r[0] * c.qx + r[1] * c.qy + r[2] * c.qz, r[0] * c.px + r[1] * c.py + r[2] * c.pz)
	if c.e < 1.0:
		c.ra = c.p / (1.0 - c.e)
		c.n = sqrt(gm / (c.a * c.a * c.a))
		c.period = TAU / c.n
		var big_e := atan2(sqrt(1.0 - c.e * c.e) * sin(nu), c.e + cos(nu))
		c.t_peri = t - (big_e - c.e * sin(big_e)) / c.n
	else:
		c.ra = INF
		c.n = sqrt(gm / (-c.a * -c.a * -c.a))
		var sh := sqrt(c.e * c.e - 1.0) * sin(nu) / (1.0 + c.e * cos(nu))
		var big_h := asinh(sh)
		c.t_peri = t - (c.e * sinh(big_h) - big_h) / c.n
	return c


func is_closed() -> bool:
	return e < 1.0 and energy < 0.0


## Eccentric (ellipse) or hyperbolic anomaly at absolute time t.
func anomaly_at(t: float) -> float:
	var m := n * (t - t_peri)
	if e < 1.0:
		m = fposmod(m + PI, TAU) - PI
		var big_e := m + e * sin(m)
		if e >= 0.8:
			big_e = PI * signf(m)
		for i in 40:
			var f := big_e - e * sin(big_e) - m
			var d := f / (1.0 - e * cos(big_e))
			big_e -= d
			if absf(d) < 1e-13:
				break
		return big_e
	var h := asinh(m / e)
	for i in 60:
		var f := e * sinh(h) - h - m
		var d := f / (e * cosh(h) - 1.0)
		h -= d
		if absf(d) < 1e-13 * maxf(1.0, absf(h)):
			break
	return h


## Absolute time at a given eccentric / hyperbolic anomaly, on the revolution that starts
## at periapsis passage t_peri (ellipses: add k * period for other revolutions).
func time_at_anomaly(x: float) -> float:
	if e < 1.0:
		return t_peri + (x - e * sin(x)) / n
	return t_peri + (e * sinh(x) - x) / n


## Position (relative to the body, PCI axes) at anomaly x.
func position_at_anomaly(x: float) -> PackedFloat64Array:
	var u: float
	var w: float
	if e < 1.0:
		u = a * (cos(x) - e)
		w = a * sqrt(1.0 - e * e) * sin(x)
	else:
		var aa := -a
		u = aa * (e - cosh(x))
		w = aa * sqrt(e * e - 1.0) * sinh(x)
	return PackedFloat64Array([px * u + qx * w, py * u + qy * w, pz * u + qz * w])


func position_at(t: float) -> PackedFloat64Array:
	if degenerate:
		var s := FlightOrbit.propagate(r0, v0, t - t0, mu)
		return PackedFloat64Array([s[0], s[1], s[2]])
	return position_at_anomaly(anomaly_at(t))


## [x, y, z, vx, vy, vz] at absolute time t.
func state_at(t: float) -> PackedFloat64Array:
	if degenerate:
		return FlightOrbit.propagate(r0, v0, t - t0, mu)
	var x := anomaly_at(t)
	var u: float
	var w: float
	var du: float
	var dw: float
	if e < 1.0:
		var sq := sqrt(1.0 - e * e)
		var xd := n / (1.0 - e * cos(x))
		u = a * (cos(x) - e)
		w = a * sq * sin(x)
		du = -a * sin(x) * xd
		dw = a * sq * cos(x) * xd
	else:
		var aa := -a
		var sq := sqrt(e * e - 1.0)
		var xd := n / (e * cosh(x) - 1.0)
		u = aa * (e - cosh(x))
		w = aa * sq * sinh(x)
		du = -aa * sinh(x) * xd
		dw = aa * sq * cosh(x) * xd
	return PackedFloat64Array([px * u + qx * w, py * u + qy * w, pz * u + qz * w,
		px * du + qx * dw, py * du + qy * dw, pz * du + qz * dw])


## Distance from the body at true anomaly nu.
func radius_at_true_anomaly(nu: float) -> float:
	return p / (1.0 + e * cos(nu))


## Next absolute time >= after_t at which the orbit passes true anomaly nu (INF if never).
func time_at_true_anomaly(nu: float, after_t: float) -> float:
	if degenerate:
		return INF
	if e < 1.0:
		var x := atan2(sqrt(1.0 - e * e) * sin(nu), e + cos(nu))
		var te := time_at_anomaly(x)
		return te + ceilf((after_t - te) / period) * period
	var lim := acos(-1.0 / e)
	if absf(nu) >= lim:
		return INF
	var sh := sqrt(e * e - 1.0) * sin(nu) / (1.0 + e * cos(nu))
	var th := time_at_anomaly(asinh(sh))
	return th if th >= after_t else INF


## Next time >= after_t at which the distance equals r_target, moving outwards
## (outgoing = true) or inwards. INF if the orbit never reaches that radius.
func time_to_radius(r_target: float, after_t: float, outgoing: bool) -> float:
	if degenerate:
		return _time_to_radius_scan(r_target, after_t, outgoing)
	if r_target < rp or (e < 1.0 and r_target > ra) or e < 1e-9:
		return INF
	var c := clampf((p / r_target - 1.0) / e, -1.0, 1.0)
	var nu := acos(c)
	return time_at_true_anomaly(nu if outgoing else -nu, after_t)


## Radial / near-parabolic fallback: march with the universal propagator and bisect.
func _time_to_radius_scan(r_target: float, after_t: float, outgoing: bool) -> float:
	var horizon := period if period < INF else 3.0e7
	var steps := 400
	var dt := horizon / steps
	var prev := FlightOrbit.length(position_at(after_t)) - r_target
	for i in range(1, steps + 1):
		var t := after_t + dt * i
		var cur := FlightOrbit.length(position_at(t)) - r_target
		if (outgoing and prev < 0.0 and cur >= 0.0) or (not outgoing and prev > 0.0 and cur <= 0.0):
			var lo := t - dt
			var hi := t
			for k in 50:
				var mid := (lo + hi) * 0.5
				var f := FlightOrbit.length(position_at(mid)) - r_target
				if (f >= 0.0) == outgoing:
					hi = mid
				else:
					lo = mid
			return hi
		prev = cur
	return INF


## True anomaly (rad) of a position on this orbit.
func true_anomaly_of(r: PackedFloat64Array) -> float:
	return atan2(r[0] * qx + r[1] * qy + r[2] * qz, r[0] * px + r[1] * py + r[2] * pz)


func periapsis_position() -> PackedFloat64Array:
	return PackedFloat64Array([px * rp, py * rp, pz * rp])


func apoapsis_position() -> PackedFloat64Array:
	if e >= 1.0:
		return PackedFloat64Array()
	return PackedFloat64Array([-px * ra, -py * ra, -pz * ra])


## Ascending-node direction relative to a reference plane normal (unit); empty if the
## planes coincide.
func node_line(ref_normal: Vector3) -> PackedFloat64Array:
	# N = ref x W
	var nx := ref_normal.y * wz - ref_normal.z * wy
	var ny := ref_normal.z * wx - ref_normal.x * wz
	var nz := ref_normal.x * wy - ref_normal.y * wx
	var nl := sqrt(nx * nx + ny * ny + nz * nz)
	if nl < 1e-6:
		return PackedFloat64Array()
	return PackedFloat64Array([nx / nl, ny / nl, nz / nl])
