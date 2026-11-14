class_name FlightOrbit
extends RefCounted
## Earth model and two-body orbit math, all in GDScript floats (64-bit doubles).
## Vectors are PackedFloat64Array [x, y, z] in the planet-centred inertial frame (PCI):
## origin = Earth's centre, +Y = straight up at the launch pad. Godot's Vector3 is 32-bit
## (0.5 m steps at 6.4e6 m), so it is never used for the authoritative position.

const MU := 3.986004418e14  # m^3/s^2
const R := 6371000.0  # m
const G0 := 9.80665
## Exponential atmosphere (isothermal: pressure ratio == density ratio)
const RHO0 := 1.225
const SCALE_H := 8500.0
## Above this altitude the air is ignored (and on-rails warp is allowed). Same 140 km as the
## "orbit reached" test (periapsis above the atmosphere).
const ATMO_TOP := 140000.0
const SOUND_SPEED := 330.0


static func density(alt: float) -> float:
	if alt >= ATMO_TOP:
		return 0.0
	return RHO0 * exp(-maxf(alt, -500.0) / SCALE_H)


static func pressure_ratio(alt: float) -> float:
	return density(alt) / RHO0


static func vec(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return vec(a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


static func length(a: PackedFloat64Array) -> float:
	return sqrt(dot(a, a))


static func scaled(a: PackedFloat64Array, s: float) -> PackedFloat64Array:
	return vec(a[0] * s, a[1] * s, a[2] * s)


## Orbit summary from a state vector: semi-major axis, eccentricity, apoapsis / periapsis
## radius and altitude, period, specific energy, angular momentum and the eccentricity
## vector (for drawing). Works for ellipses and hyperbolas.
static func elements(r: PackedFloat64Array, v: PackedFloat64Array) -> Dictionary:
	var rn := length(r)
	var v2 := dot(v, v)
	var energy := v2 * 0.5 - MU / rn
	var h := cross(r, v)
	var hn := length(h)
	var rv := dot(r, v)
	# e = ((v² - μ/r) r - (r·v) v) / μ
	var k := v2 - MU / rn
	var ev := vec((k * r[0] - rv * v[0]) / MU, (k * r[1] - rv * v[1]) / MU, (k * r[2] - rv * v[2]) / MU)
	var e := length(ev)
	var a := -MU / (2.0 * energy) if absf(energy) > 1e-9 else INF
	var p := hn * hn / MU
	var rp := p / (1.0 + e)
	var ra := p / (1.0 - e) if e < 1.0 else INF
	var period := TAU * sqrt(a * a * a / MU) if e < 1.0 and a > 0.0 else INF
	return {"a": a, "e": e, "p": p, "rp": rp, "ra": ra, "pe_alt": rp - R, "ap_alt": ra - R,
		"period": period, "energy": energy, "h": h, "ev": ev, "r": rn}


## Time from the current state to the next apoapsis (s); INF for open orbits.
static func time_to_apoapsis(r: PackedFloat64Array, v: PackedFloat64Array) -> float:
	var el := elements(r, v)
	var e: float = el["e"]
	if e >= 1.0 or e < 1e-6:
		return INF
	var a: float = el["a"]
	var rn: float = el["r"]
	var cos_e := clampf((1.0 - rn / a) / e, -1.0, 1.0)
	var big_e := acos(cos_e)
	if dot(r, v) < 0.0:
		big_e = TAU - big_e
	var m := big_e - e * sin(big_e)
	var n := sqrt(MU / (a * a * a))
	return (PI - m) / n if m <= PI else (PI + TAU - m) / n


# ------------------------------------------------------------ Kepler propagation
static func _stumpff_c(z: float) -> float:
	if z > 1e-6:
		return (1.0 - cos(sqrt(z))) / z
	if z < -1e-6:
		return (cosh(sqrt(-z)) - 1.0) / (-z)
	return 0.5 - z / 24.0


static func _stumpff_s(z: float) -> float:
	if z > 1e-6:
		var s := sqrt(z)
		return (s - sin(s)) / (s * s * s)
	if z < -1e-6:
		var s := sqrt(-z)
		return (sinh(s) - s) / (s * s * s)
	return 1.0 / 6.0 - z / 120.0


## Propagates (r0, v0) by dt seconds along the two-body conic (universal-variable
## formulation, Newton iteration). Returns [x, y, z, vx, vy, vz]. Exact for any dt: used
## by on-rails time warp and as the reference in the integrator tests.
static func propagate(r0: PackedFloat64Array, v0: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var r0n := length(r0)
	var v0n2 := dot(v0, v0)
	var vr0 := dot(r0, v0) / r0n
	var alpha := 2.0 / r0n - v0n2 / MU
	var smu := sqrt(MU)
	# closed orbits: only the fraction of a period matters (keeps Newton well conditioned)
	if alpha > 1e-12:
		var period := TAU / sqrt(MU * alpha * alpha * alpha)
		dt = fmod(dt, period)
	var chi := smu * absf(alpha) * dt if alpha > 1e-12 else smu * dt / r0n
	for i in 60:
		var z := alpha * chi * chi
		var c := _stumpff_c(z)
		var s := _stumpff_s(z)
		var f := r0n * vr0 / smu * chi * chi * c + (1.0 - alpha * r0n) * chi * chi * chi * s + r0n * chi - smu * dt
		var df := r0n * vr0 / smu * chi * (1.0 - z * s) + (1.0 - alpha * r0n) * chi * chi * c + r0n
		var d := f / df
		chi -= d
		if absf(d) < 1e-9:
			break
	var z2 := alpha * chi * chi
	var c2 := _stumpff_c(z2)
	var s2 := _stumpff_s(z2)
	var fl := 1.0 - chi * chi / r0n * c2
	var gl := dt - chi * chi * chi * s2 / smu
	var r := vec(fl * r0[0] + gl * v0[0], fl * r0[1] + gl * v0[1], fl * r0[2] + gl * v0[2])
	var rn := length(r)
	var fd := smu / (rn * r0n) * (alpha * chi * chi * chi * s2 - chi)
	var gd := 1.0 - chi * chi / rn * c2
	return PackedFloat64Array([r[0], r[1], r[2],
		fd * r0[0] + gd * v0[0], fd * r0[1] + gd * v0[1], fd * r0[2] + gd * v0[2]])


## Points of the osculating orbit (PCI, metres) for the map view: `n` samples of true
## anomaly. Open orbits are clipped to `max_r`.
static func orbit_points(r: PackedFloat64Array, v: PackedFloat64Array, n := 180, max_r := 6.0e7) -> Array[PackedFloat64Array]:
	var el := elements(r, v)
	var out: Array[PackedFloat64Array] = []
	var e: float = el["e"]
	var p: float = el["p"]
	var h: PackedFloat64Array = el["h"]
	var hn := length(h)
	if hn < 1e-6:
		return out
	var w := scaled(h, 1.0 / hn)
	var px: PackedFloat64Array
	if e > 1e-7:
		px = scaled(el["ev"], 1.0 / e)
	else:
		px = scaled(r, 1.0 / length(r))
	var py := cross(w, px)
	var nu_max := PI
	if e >= 1.0:
		nu_max = acos(clampf(-1.0 / e, -1.0, 1.0)) - 0.02
	for i in n + 1:
		var nu := -nu_max + 2.0 * nu_max * float(i) / float(n)
		var rr := p / (1.0 + e * cos(nu))
		if rr <= 0.0 or rr > max_r:
			continue
		var c := cos(nu) * rr
		var s := sin(nu) * rr
		out.append(vec(px[0] * c + py[0] * s, px[1] * c + py[1] * s, px[2] * c + py[2] * s))
	return out


## Apoapsis / periapsis positions (PCI) or empty arrays when undefined.
static func apsides(r: PackedFloat64Array, v: PackedFloat64Array) -> Dictionary:
	var el := elements(r, v)
	var e: float = el["e"]
	if e < 1e-5:
		return {}
	var ehat := scaled(el["ev"], 1.0 / e)
	var out := {"pe": scaled(ehat, el["rp"])}
	if e < 1.0:
		out["ap"] = scaled(ehat, -float(el["ra"]))
	return out
