class_name FlightSolar
extends RefCounted
## The flight's solar system for patched conics: every body of data/solar_system.json with
## its gravitational parameter, radius, sphere of influence and its REAL motion around its
## parent (Ephemeris: JPL elements for the planets, ELP/Meeus for the Moon, JPL mean elements
## for the satellites, the comet's own orbit), at the campaign's date.
##
## Time: t (s) after the campaign epoch EPOCH_DAYS (2026-10-28 12:00 TT, week 0 of the tycoon
## calendar); a flight's mission time and the campaign map both use this clock.
## Frames: everything is expressed in the flight's inertial axes (PCI, see FlightOrbit:
## +Y = up at the launch pad at t = 0, the Earth does not turn in the flight). PCI is the real
## Earth-centred equatorial frame turned so that the pad (latitude PAD_LAT_DEG, the texture's
## launch site) is straight up and its east is PAD_EAST; its turn about the pole (the local
## sidereal time) puts the Sun where it is at PAD_SOLAR_HOUR local solar time on the epoch day.
## So the ecliptic is 23.44 deg off the equator, the Moon's orbit 18-29 deg off it, etc.
## Positions are doubles (PackedFloat64Array).
##
## Cache: the ephemeris is sampled per body every `step[i]` seconds (period / 512, at most half
## a day) and joined by cubic Hermite pieces (position + velocity at both ends): positions are
## within metres of the series and the velocity is exactly the
## derivative of the position, so patched-conic hand-overs stay continuous.
##
## Old fields kept for callers: sma (mean semi-major axis), rate (mean motion), phase (mean
## argument of latitude at t = 0, in the plane_p / plane_q basis of the osculating plane at
## t = 0): phase + rate * t is the body's mean angle, within ~2e of the true one.
## SOI radius: r = a (GM / GM_parent)^(2/5), never below 1.5 body radii (tiny moons).

const DATA_PATH := "res://data/solar_system.json"
## Campaign epoch in days after J2000 (JD 2461342.0 = 2026-10-28 12:00 TT).
const EPOCH_DAYS := 9797.0
const DAY := 86400.0
## the launch pad: latitude (deg, the flight texture's site, south of the equator: the
## texture's -Y pole is north), its east (== FlightWorld.EAST) and the local apparent solar
## time at the epoch (morning: the Sun ~30 deg up in the east-south-east)
const PAD_LAT_DEG := -3.0
const PAD_EAST := Vector3(0.894, 0.0, -0.447)
const PAD_SOLAR_HOUR := 8.0
## The launch-orbit normal (pad up x east): an eastward orbit from the pad.
const LAUNCH_NORMAL := Vector3(-0.447, 0.0, -0.894)
## atmosphere top (m) used for drag, rails warp and impact warnings; only Earth's is modelled
const ATMO := {"earth": FlightOrbit.ATMO_TOP}
## Sun direction (PCI) from the Earth at t = 0 (filled by build(): where the flight sky draws it)
static var SUN_DIR := Vector3(0.72, 0.45, 0.42)

static var _instance: FlightSolar = null

var eph: Ephemeris
var ids: PackedStringArray = []
var names: Array[Dictionary] = []
var kinds: PackedStringArray = []
var parent: PackedInt32Array = []
var children: Array[PackedInt32Array] = []
var mu: PackedFloat64Array = []
var radius: PackedFloat64Array = []
var soi: PackedFloat64Array = []
## mean orbit radius around the parent (m) and mean angular rate (rad/s)
var sma: PackedFloat64Array = []
var rate: PackedFloat64Array = []
## mean argument of latitude at mission time 0 (rad)
var phase: PackedFloat64Array = []
## osculating orbit-plane basis at t = 0 (PCI): P = ascending node on the parent's reference
## (the ecliptic for the planets and the Moon), Q in the plane, 90 deg ahead
var plane_p: Array[PackedFloat64Array] = []
var plane_q: Array[PackedFloat64Array] = []
var atmo_top: PackedFloat64Array = []
var colors: Array[Color] = []
var sun := 0
var earth := 0
var moon := 0
var comet := -1
var ecliptic_normal := Vector3.UP
## Earth's spin axis (north pole) in PCI
var earth_pole := Vector3.UP
## ecliptic J2000 -> PCI rotation (rows, doubles)
var ecl_to_pci := PackedFloat64Array([1, 0, 0, 0, 1, 0, 0, 0, 1])
## Hermite sample spacing (s) per body and the sampled states (key -> [6] PCI, rel. parent)
var step: PackedFloat64Array = []
var _cache: Array[Dictionary] = []


static func get_system() -> FlightSolar:
	if _instance == null:
		_instance = FlightSolar.new()
		_instance.build(SUN_DIR, LAUNCH_NORMAL)
	return _instance


func index_of(id: String) -> int:
	return ids.find(id)


func display_name(i: int) -> String:
	var d: Dictionary = names[i]
	return String(d.get("pt" if TranslationServer.get_locale().begins_with("pt") else "en", ids[i]))


## Builds the system. The arguments are kept for older callers: the frame now comes from the
## real geometry (pad latitude and east, the epoch, the pad's solar hour), not from them.
func build(_sun_dir: Vector3, _launch_normal: Vector3) -> void:
	eph = Ephemeris.shared()
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var bodies: Array = data["bodies"]
	var au_m := float(data["au_km"]) * 1000.0
	for b: Dictionary in bodies:
		ids.append(String(b["id"]))
	for b: Dictionary in bodies:
		var id: String = b["id"]
		names.append(b["name"])
		kinds.append(String(b["type"]))
		parent.append(ids.find(String(b["parent"])))
		radius.append(float(b["radius_km"]) * 1000.0)
		mu.append(eph.gm[eph.index_of(id)])
		var a := 0.0
		if float(b.get("semi_major_axis_au", 0.0)) > 0.0:
			a = float(b["semi_major_axis_au"]) * au_m
		elif b.has("semi_major_axis_km"):
			a = float(b["semi_major_axis_km"]) * 1000.0
		sma.append(a)
		var period_s := float(b["orbital_period_days"]) * DAY
		rate.append(TAU / period_s if period_s > 0.0 else 0.0)
		atmo_top.append(float(ATMO.get(id, 0.0)))
		var pal: Array = (b["visual"] as Dictionary).get("palette", ["#cccccc"])
		var c := Color.html(String(pal[mini(1, pal.size() - 1)]))
		colors.append(c.lerp(Color.WHITE, 0.25))
		children.append(PackedInt32Array())
		phase.append(0.0)
		plane_p.append(PackedFloat64Array([1.0, 0.0, 0.0]))
		plane_q.append(PackedFloat64Array([0.0, 0.0, -1.0]))
		_cache.append({})
		step.append(43200.0)
	sun = ids.find("sun")
	earth = ids.find("earth")
	moon = ids.find("moon")
	comet = ids.find("mae_gelo")
	for i in ids.size():
		if parent[i] >= 0:
			children[parent[i]].append(i)
	# the comet's mean distance / period come from its orbit (the data has no flat fields)
	if comet >= 0:
		var el := eph.elements(eph.index_of("mae_gelo"), EPOCH_DAYS)
		sma[comet] = float(el["a"])
		rate[comet] = TAU / float(el["period"])
	for i in ids.size():
		var s := INF
		if parent[i] >= 0:
			s = maxf(sma[i] * pow(mu[i] / mu[parent[i]], 0.4), radius[i] * 1.5)
		soi.append(s)
		if rate[i] > 0.0:
			step[i] = clampf(TAU / rate[i] / 512.0, 30.0, 43200.0)
	_build_frame()
	# osculating planes and mean phases at t = 0 (doubles: a 1e-7 error in these axes is metres
	# in a low orbit built on them)
	var ref_n := _unit(to_pci(PackedFloat64Array([0.0, 0.0, 1.0])))
	for i in ids.size():
		if parent[i] < 0:
			continue
		var st := state_rel_parent(i, 0.0)
		var r := PackedFloat64Array([st[0], st[1], st[2]])
		var v := PackedFloat64Array([st[3], st[4], st[5]])
		var n := _unit(Ephemeris._cross(r, v))
		var node := Ephemeris._cross(ref_n, n)
		if Ephemeris._len(node) < 1e-6:
			node = r
		var pp := _unit(node)
		var qq := _unit(Ephemeris._cross(n, pp))
		plane_p[i] = pp
		plane_q[i] = qq
		var u_true := atan2(Ephemeris._dot(r, qq), Ephemeris._dot(r, pp))
		# true -> mean anomaly offset of the osculating orbit
		var el := Ephemeris.elements_of(st, mu[parent[i]] + mu[i])
		var e := float(el["e"])
		phase[i] = u_true - (float(el["nu"]) - float(el["M"])) if e < 1.0 else u_true


static func _unit(a: PackedFloat64Array) -> PackedFloat64Array:
	var l := sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
	return PackedFloat64Array([a[0] / l, a[1] / l, a[2] / l])


static func _comb(a: PackedFloat64Array, ka: float, b: PackedFloat64Array, kb: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] * ka + b[0] * kb, a[1] * ka + b[1] * kb, a[2] * ka + b[2] * kb])


## PCI axes from the real geometry (see the class doc), in doubles.
func _build_frame() -> void:
	var up := PackedFloat64Array([0.0, 1.0, 0.0])
	var east := _unit(PackedFloat64Array([PAD_EAST.x, PAD_EAST.y, PAD_EAST.z]))
	var north := _unit(Ephemeris._cross(up, east))
	var lat := deg_to_rad(PAD_LAT_DEG)
	var pole := _unit(_comb(north, cos(lat), up, sin(lat)))
	earth_pole = Vector3(pole[0], pole[1], pole[2])
	# the pad's meridian in the equatorial plane, and east of it
	var m := _unit(_comb(up, 1.0, pole, -sin(lat)))
	var me := _unit(Ephemeris._cross(pole, m))
	# local sidereal time: the Sun's right ascension + its hour angle at PAD_SOLAR_HOUR
	var es := eph.helio(eph.index_of("earth"), EPOCH_DAYS)
	var sun_ecl := PackedFloat64Array([-es[0], -es[1], -es[2]])
	var sun_eq := eph.ecl_to_eq(sun_ecl)
	var ra := atan2(sun_eq[1], sun_eq[0])
	var theta := ra + deg_to_rad((PAD_SOLAR_HOUR - 12.0) * 15.0)
	# equatorial J2000 axes in PCI: m = cos(theta) x + sin(theta) y
	var x_eq := _comb(m, cos(theta), me, -sin(theta))
	var y_eq := _comb(m, sin(theta), me, cos(theta))
	var z_eq := pole
	# ecliptic J2000 axes: x = x_eq, y = cos(eps) y_eq + sin(eps) z_eq, z = -sin(eps) y_eq + cos(eps) z_eq
	var eps := deg_to_rad(Ephemeris.OBLIQUITY_J2000_DEG)
	var x_e := x_eq
	var y_e := _comb(y_eq, cos(eps), z_eq, sin(eps))
	var z_e := _comb(y_eq, -sin(eps), z_eq, cos(eps))
	# rows of the ecl -> PCI matrix: PCI = x_e * v.x + y_e * v.y + z_e * v.z
	ecl_to_pci = PackedFloat64Array([x_e[0], y_e[0], z_e[0], x_e[1], y_e[1], z_e[1], x_e[2], y_e[2], z_e[2]])
	ecliptic_normal = Vector3(z_e[0], z_e[1], z_e[2])
	var sp := _unit(to_pci(sun_ecl))
	SUN_DIR = Vector3(sp[0], sp[1], sp[2])


## A vector from ecliptic J2000 axes to PCI (doubles).
func to_pci(v: PackedFloat64Array) -> PackedFloat64Array:
	var m := ecl_to_pci
	return PackedFloat64Array([m[0] * v[0] + m[1] * v[1] + m[2] * v[2], m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
		m[6] * v[0] + m[7] * v[1] + m[8] * v[2]])


## A vector from PCI to ecliptic J2000 axes.
func to_ecl(v: PackedFloat64Array) -> PackedFloat64Array:
	var m := ecl_to_pci
	return PackedFloat64Array([m[0] * v[0] + m[3] * v[1] + m[6] * v[2], m[1] * v[0] + m[4] * v[1] + m[7] * v[2],
		m[2] * v[0] + m[5] * v[1] + m[8] * v[2]])


# ------------------------------------------------------------ calendar
## Days after J2000 at mission time t.
func days_at(t: float) -> float:
	return EPOCH_DAYS + t / DAY


## Julian date at mission time t.
func jd_at(t: float) -> float:
	return Ephemeris.J2000_JD + days_at(t)


## Calendar date at mission time t: {"year", "month", "day", "hour", "minute"} (TT ~ UTC).
func date_at(t: float) -> Dictionary:
	return Ephemeris.date_of_jd(jd_at(t))


## Mission time (s) of a calendar date.
static func t_of_date(year: int, month: int, day: int, hours := 0.0) -> float:
	return (Ephemeris.days_of(year, month, day, hours) - EPOCH_DAYS) * DAY


# ------------------------------------------------------------ positions (mission time t, s)
## The exact (uncached) state of body i relative to its parent, PCI.
func exact_state_rel_parent(i: int, t: float) -> PackedFloat64Array:
	var s := eph.state(eph.index_of(ids[i]), days_at(t))
	var p := to_pci(PackedFloat64Array([s[0], s[1], s[2]]))
	var v := to_pci(PackedFloat64Array([s[3], s[4], s[5]]))
	return PackedFloat64Array([p[0], p[1], p[2], v[0], v[1], v[2]])


func _node(i: int, k: int) -> PackedFloat64Array:
	var c: Dictionary = _cache[i]
	var s: Variant = c.get(k)
	if s == null:
		if c.size() > 60000:
			c.clear()
		s = exact_state_rel_parent(i, float(k) * step[i])
		c[k] = s
	return s


## Position of body i relative to its parent.
func pos_rel_parent(i: int, t: float) -> PackedFloat64Array:
	if parent[i] < 0:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var h := step[i]
	var kf := floorf(t / h)
	var k := int(kf)
	var s := t / h - kf
	var a := _node(i, k)
	var b := _node(i, k + 1)
	var s2 := s * s
	var s3 := s2 * s
	var h00 := 2.0 * s3 - 3.0 * s2 + 1.0
	var h10 := (s3 - 2.0 * s2 + s) * h
	var h01 := -2.0 * s3 + 3.0 * s2
	var h11 := (s3 - s2) * h
	return PackedFloat64Array([h00 * a[0] + h10 * a[3] + h01 * b[0] + h11 * b[3],
		h00 * a[1] + h10 * a[4] + h01 * b[1] + h11 * b[4], h00 * a[2] + h10 * a[5] + h01 * b[2] + h11 * b[5]])


## [x, y, z, vx, vy, vz] of body i relative to its parent.
func state_rel_parent(i: int, t: float) -> PackedFloat64Array:
	if parent[i] < 0:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var h := step[i]
	var kf := floorf(t / h)
	var k := int(kf)
	var s := t / h - kf
	var a := _node(i, k)
	var b := _node(i, k + 1)
	var s2 := s * s
	var s3 := s2 * s
	var h00 := 2.0 * s3 - 3.0 * s2 + 1.0
	var h10 := (s3 - 2.0 * s2 + s) * h
	var h01 := -2.0 * s3 + 3.0 * s2
	var h11 := (s3 - s2) * h
	var d00 := (6.0 * s2 - 6.0 * s) / h
	var d10 := 3.0 * s2 - 4.0 * s + 1.0
	var d01 := (-6.0 * s2 + 6.0 * s) / h
	var d11 := 3.0 * s2 - 2.0 * s
	return PackedFloat64Array([h00 * a[0] + h10 * a[3] + h01 * b[0] + h11 * b[3],
		h00 * a[1] + h10 * a[4] + h01 * b[1] + h11 * b[4], h00 * a[2] + h10 * a[5] + h01 * b[2] + h11 * b[5],
		d00 * a[0] + d10 * a[3] + d01 * b[0] + d11 * b[3], d00 * a[1] + d10 * a[4] + d01 * b[1] + d11 * b[4],
		d00 * a[2] + d10 * a[5] + d01 * b[2] + d11 * b[5]])


## State of body i relative to the Sun (root).
func state_helio(i: int, t: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var k := i
	while k >= 0 and parent[k] >= 0:
		var s := state_rel_parent(k, t)
		for j in 6:
			out[j] += s[j]
		k = parent[k]
	return out


## State (position + velocity) of body i relative to body j at time t.
func state_rel(i: int, j: int, t: float) -> PackedFloat64Array:
	if i == j:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if parent[i] == j:
		return state_rel_parent(i, t)
	if parent[j] == i:
		var s := state_rel_parent(j, t)
		for k in 6:
			s[k] = -s[k]
		return s
	var a := state_helio(i, t)
	var b := state_helio(j, t)
	for k in 6:
		a[k] -= b[k]
	return a


func pos_rel(i: int, j: int, t: float) -> PackedFloat64Array:
	var s := state_rel(i, j, t)
	return PackedFloat64Array([s[0], s[1], s[2]])


## True if `anc` is `i` or one of its ancestors.
func is_ancestor(anc: int, i: int) -> bool:
	var k := i
	while k >= 0:
		if k == anc:
			return true
		k = parent[k]
	return false


## Orbit-plane normal of body i (PCI, unit) at t = 0.
func orbit_normal(i: int) -> Vector3:
	var bp := plane_p[i]
	var bq := plane_q[i]
	return Vector3(bp[0], bp[1], bp[2]).cross(Vector3(bq[0], bq[1], bq[2])).normalized()


## Orbit-plane normal of body i (PCI, unit) at time t (the Moon's turns in 18.6 years).
func orbit_normal_at(i: int, t: float) -> Vector3:
	var s := state_rel_parent(i, t)
	return Vector3(s[0], s[1], s[2]).cross(Vector3(s[3], s[4], s[5])).normalized()


## True angle of body i at time t in its plane_p / plane_q basis (rad): where to aim a transfer
## (the old circular phase[i] + rate[i] * t is only the mean angle, ~2e off on an ellipse).
func angle_at(i: int, t: float) -> float:
	var r := pos_rel_parent(i, t)
	return atan2(Ephemeris._dot(r, plane_q[i]), Ephemeris._dot(r, plane_p[i]))


## Distance of body i from its parent at time t (m).
func distance_at(i: int, t: float) -> float:
	return Ephemeris._len(pos_rel_parent(i, t))


## Mean orbit period of body i around its parent (s).
func period(i: int) -> float:
	return TAU / rate[i] if rate[i] > 0.0 else INF


## The osculating ellipse of body i around its parent at time t, for drawing: {"a", "b", "e"
## (m), "center": PackedFloat64Array (m, PCI, relative to the parent), "p_axis" (unit, to the
## periapsis), "q_axis" (unit, 90 deg ahead in the direction of motion), "normal"}.
func orbit_shape(i: int, t: float) -> Dictionary:
	var s := state_rel_parent(i, t)
	var gm := mu[parent[i]] + mu[i]
	var r := PackedFloat64Array([s[0], s[1], s[2]])
	var v := PackedFloat64Array([s[3], s[4], s[5]])
	var el := FlightOrbit.elements(r, v, gm)
	var e := minf(float(el["e"]), 0.9999)
	var a := float(el["a"])
	var h: PackedFloat64Array = el["h"]
	var hn := FlightOrbit.length(h)
	var w := Vector3(h[0], h[1], h[2]) / hn
	var px: Vector3
	if e > 1e-6:
		var ev: PackedFloat64Array = el["ev"]
		px = Vector3(ev[0], ev[1], ev[2]).normalized()
	else:
		px = Vector3(r[0], r[1], r[2]).normalized()
	var qx := w.cross(px).normalized()
	var c := -a * e
	return {"a": a, "b": a * sqrt(1.0 - e * e), "e": e,
		"center": PackedFloat64Array([px.x * c, px.y * c, px.z * c]), "p_axis": px, "q_axis": qx, "normal": w}


## Spin axis (north pole, IAU) of body i in PCI.
func pole(i: int) -> Vector3:
	var p := to_pci(eph.pole_ecl(eph.index_of(ids[i])))
	return Vector3(p[0], p[1], p[2]).normalized()
