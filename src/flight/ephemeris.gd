class_name Ephemeris
extends RefCounted
## Real positions of the Sun's planets, the Moon, the planetary satellites and the comet
## Mãe-Gelo from the 'orbit' blocks of data/solar_system.json. Pure maths, no scene access;
## FlightSolar is the facade the game uses (it turns these into the flight's PCI frame and
## caches them), this class is the truth it is built on.
##
## Frame: heliocentric (planets, comet) or parent-centred (moons) ECLIPTIC J2000 (x to the
## vernal equinox, z to the north ecliptic pole), metres and m/s. Time: days after J2000.0
## (JD 2451545.0, TT; TT - UTC is ~70 s, ignored by the game's calendar).
## Models (sources in the data file and docs/solar_system.md):
##   standish        Keplerian elements + secular rates, E. M. Standish & J. G. Williams (JPL):
##                   Table 1 (1800-2050), Table 2a + 2b (3000 BC - 3000 AD) outside it, blended
##                   linearly over 2049-2051 so nothing jumps. "earth" is the Earth-Moon
##                   barycentre of the table minus the Moon's share (1 / 82.3006).
##   meeus47         geocentric Moon, the truncated ELP-2000/82 series of Meeus ch. 47
##   kepler_laplace  JPL mean elements of a satellite on its Laplace plane, with apsidal and
##                   nodal precession
##   kepler_helio    a fixed heliocentric ellipse (the comet: perihelion distance and time)
## Accuracy: planets ~arcminute or better over 1800-2050 (Earth ~20", Mars ~40", Jupiter/Saturn
## ~a few arcminutes); the Moon ~10" in longitude and ~20 km in distance; satellites ~1-2 deg
## of orbital phase after decades (enough for a map, not for a probe's flyby).

const DATA_PATH := "res://data/solar_system.json"
const J2000_JD := 2451545.0
const DAY := 86400.0
const AU_M := 149597870700.0
const OBLIQUITY_J2000_DEG := 23.4392911
## Moon mass / (Earth + Moon mass) (DE440: Earth/Moon mass ratio 81.30057)
const MOON_SHARE := 1.0 / 82.30057
## general precession in longitude (deg per Julian century): brings the Moon's longitude of
## date back to the J2000 equinox
const PRECESSION_DEG_CY := 1.396971
## Table 1 is valid from 1800-01-01 to 2050-01-01 (days after J2000); blend to Table 2 over 2049-2051
const T1_FROM := -73048.5
const BLEND_FROM := 17897.5
const BLEND_TO := 18627.5
## half-width (s) of the central difference giving the velocities
const FD_S := 20.0

enum Model { NONE, STANDISH, MEEUS47, KEPLER_LAPLACE, KEPLER_HELIO }

static var _shared: Ephemeris = null

var ids: PackedStringArray = []
var parent_ids: PackedStringArray = []
var data: Array[Dictionary] = []
## GM (m^3/s^2) and mean radius (m)
var gm: PackedFloat64Array = []
var radius: PackedFloat64Array = []
var model: PackedInt32Array = []
var gm_sun := 1.32712440018e20
var _moon := -1
## per body: the prepared orbit (Dictionary of doubles)
var _orb: Array[Dictionary] = []
var _cos_eps := cos(deg_to_rad(OBLIQUITY_J2000_DEG))
var _sin_eps := sin(deg_to_rad(OBLIQUITY_J2000_DEG))


static func shared() -> Ephemeris:
	if _shared == null:
		_shared = Ephemeris.new()
		_shared.load_data(DATA_PATH)
	return _shared


func index_of(id: String) -> int:
	return ids.find(id)


func load_data(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var bodies: Array = (parsed as Dictionary)["bodies"]
	for b: Dictionary in bodies:
		var id := String(b["id"])
		ids.append(id)
		parent_ids.append(String(b.get("parent", "")))
		data.append(b)
		var r_m := float(b["radius_km"]) * 1000.0
		radius.append(r_m)
		var g := float(b.get("gm_km3_s2", 0.0)) * 1.0e9
		if g <= 0.0:
			g = float(b.get("surface_gravity_ms2", 0.0)) * r_m * r_m
		gm.append(g)
		var o: Dictionary = b.get("orbit", {})
		var m := Model.NONE
		match String(o.get("model", "")):
			"standish":
				m = Model.STANDISH
			"meeus47":
				m = Model.MEEUS47
			"kepler_laplace":
				m = Model.KEPLER_LAPLACE
			"kepler_helio":
				m = Model.KEPLER_HELIO
		model.append(m)
		_orb.append(_prepare(m, o))
		if id == "sun":
			gm_sun = g
		if m == Model.MEEUS47:
			_moon = ids.size() - 1


func _prepare(m: Model, o: Dictionary) -> Dictionary:
	var p := {}
	match m:
		Model.STANDISH:
			p["t1"] = PackedFloat64Array(o["t1"])
			p["r1"] = PackedFloat64Array(o["t1_rate_cy"])
			if o.has("t2"):
				p["t2"] = PackedFloat64Array(o["t2"])
				p["r2"] = PackedFloat64Array(o["t2_rate_cy"])
			p["bcsf"] = PackedFloat64Array(o.get("t2_extra_bcsf", [0.0, 0.0, 0.0, 0.0]))
			p["bary"] = bool(o.get("barycenter", false))
		Model.MEEUS47:
			var lr := PackedFloat64Array()
			for row: Array in o["terms_lr"]:
				for v in row:
					lr.append(float(v))
			var tb := PackedFloat64Array()
			for row: Array in o["terms_b"]:
				for v in row:
					tb.append(float(v))
			p["lr"] = lr
			p["b"] = tb
		Model.KEPLER_LAPLACE:
			p["epoch"] = float(o.get("epoch_jd", J2000_JD)) - J2000_JD
			p["a"] = float(o["a_km"]) * 1000.0
			p["e"] = float(o["e"])
			p["i"] = deg_to_rad(float(o["i_deg"]))
			p["w0"] = deg_to_rad(float(o["w_deg"]))
			p["M0"] = deg_to_rad(float(o["M_deg"]))
			p["node0"] = deg_to_rad(float(o["node_deg"]))
			var pa := float(o.get("p_apsis_yr", 0.0))
			var pn := float(o.get("p_node_yr", 0.0))
			var w_rate := TAU / (pa * 365.25) if pa > 0.0 else 0.0           # rad/day
			var node_rate := -TAU / (pn * 365.25) if pn > 0.0 else 0.0       # regression
			p["w_rate"] = w_rate
			p["node_rate"] = node_rate
			# mean anomaly rate = mean longitude rate - longitude of periapsis rate
			p["n"] = deg_to_rad(float(o["lon_rate_deg_day"])) - (w_rate + node_rate)
			# Laplace-plane basis in ecliptic J2000: x = its ascending node on the ICRF equator
			var pole := _eq_to_ecl(radec(float(o["laplace_ra_deg"]), float(o["laplace_dec_deg"])))
			var zeq := _eq_to_ecl(PackedFloat64Array([0.0, 0.0, 1.0]))
			var x := _unit(_cross(zeq, pole))
			p["lx"] = x
			p["ly"] = _cross(pole, x)
			p["lz"] = pole
		Model.KEPLER_HELIO:
			var q := float(o["q_au"]) * AU_M
			var e := float(o["e"])
			p["a"] = q / (1.0 - e)
			p["e"] = e
			p["i"] = deg_to_rad(float(o["i_deg"]))
			p["node"] = deg_to_rad(float(o["node_deg"]))
			p["w"] = deg_to_rad(float(o["w_deg"]))
			p["tp"] = float(o["tp_jd"]) - J2000_JD
	return p


# ------------------------------------------------------------ public
## [x, y, z, vx, vy, vz] of body i relative to its parent, ecliptic J2000, at `days` after J2000.
## The velocity is the model's own time derivative (central difference over +-FD_S seconds), so
## the slow turning of the elements (apsides, nodes) is in it too.
func state(i: int, days: float) -> PackedFloat64Array:
	if model[i] == Model.MEEUS47 or model[i] == Model.NONE:
		return _raw(i, days)
	var h := FD_S / DAY
	var p0 := _raw(i, days)
	var pa := _raw(i, days + h)
	var pb := _raw(i, days - h)
	for k in 3:
		p0[3 + k] = (pa[k] - pb[k]) / (2.0 * FD_S)
	return p0


func _raw(i: int, days: float) -> PackedFloat64Array:
	match model[i]:
		Model.STANDISH:
			return _standish(i, days)
		Model.MEEUS47:
			return _moon_state(days)
		Model.KEPLER_LAPLACE:
			return _laplace(i, days)
		Model.KEPLER_HELIO:
			return _helio(i, days)
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


## Heliocentric ecliptic state of body i (sums the parents' states).
func helio(i: int, days: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var k := i
	while k >= 0 and parent_ids[k] != "":
		var s := state(k, days)
		for j in 6:
			out[j] += s[j]
		k = ids.find(parent_ids[k])
	return out


## Osculating Keplerian elements of body i around its parent: {"a" (m), "e", "i" (rad, to the
## ecliptic), "node", "w", "M" (rad), "period" (s)}.
func elements(i: int, days: float) -> Dictionary:
	var s := state(i, days)
	var p := ids.find(parent_ids[i])
	var mu := (gm[p] if p >= 0 else gm_sun) + gm[i]
	return elements_of(s, mu)


static func elements_of(s: PackedFloat64Array, mu: float) -> Dictionary:
	var r := PackedFloat64Array([s[0], s[1], s[2]])
	var v := PackedFloat64Array([s[3], s[4], s[5]])
	var rn := _len(r)
	var h := _cross(r, v)
	var hn := _len(h)
	var v2 := _dot(v, v)
	var k := v2 - mu / rn
	var rv := _dot(r, v)
	var ev := PackedFloat64Array([(k * r[0] - rv * v[0]) / mu, (k * r[1] - rv * v[1]) / mu, (k * r[2] - rv * v[2]) / mu])
	var e := _len(ev)
	var a := 1.0 / (2.0 / rn - v2 / mu)
	var inc := acos(clampf(h[2] / hn, -1.0, 1.0))
	var node := atan2(h[0], -h[1])
	var nvec := PackedFloat64Array([cos(node), sin(node), 0.0])
	var w := 0.0
	var nu := 0.0
	if e > 1e-9:
		w = atan2(_dot(_cross(nvec, ev), h) / hn, _dot(nvec, ev))
		nu = atan2(_dot(_cross(ev, r), h) / hn, _dot(ev, r))
	else:
		nu = atan2(_dot(_cross(nvec, r), h) / hn, _dot(nvec, r))
	var big_m := nu
	if e < 1.0:
		var big_e := 2.0 * atan(sqrt((1.0 - e) / (1.0 + e)) * tan(nu * 0.5))
		big_m = big_e - e * sin(big_e)
	var period := TAU * sqrt(a * a * a / mu) if a > 0.0 else INF
	return {"a": a, "e": e, "i": inc, "node": node, "w": w, "M": big_m, "nu": nu, "period": period}


# ------------------------------------------------------------ planets
func _standish(i: int, days: float) -> PackedFloat64Array:
	var p: Dictionary = _orb[i]
	var s: PackedFloat64Array
	if not p.has("t2") or (days >= T1_FROM and days <= BLEND_FROM):
		s = _standish_table(p["t1"], p["r1"], PackedFloat64Array(), days)
	elif days >= BLEND_TO or days < T1_FROM:
		s = _standish_table(p["t2"], p["r2"], p["bcsf"], days)
	else:
		var w := (days - BLEND_FROM) / (BLEND_TO - BLEND_FROM)
		var s1 := _standish_table(p["t1"], p["r1"], PackedFloat64Array(), days)
		var s2 := _standish_table(p["t2"], p["r2"], p["bcsf"], days)
		s = PackedFloat64Array()
		for k in 6:
			s.append(s1[k] * (1.0 - w) + s2[k] * w)
	if p["bary"] and _moon >= 0:
		var m := _moon_state(days)
		for k in 6:
			s[k] -= m[k] * MOON_SHARE
	return s


func _standish_table(el: PackedFloat64Array, rt: PackedFloat64Array, bcsf: PackedFloat64Array, days: float) -> PackedFloat64Array:
	var t := days / 36525.0
	var a := (el[0] + rt[0] * t) * AU_M
	var e := el[1] + rt[1] * t
	var inc := deg_to_rad(el[2] + rt[2] * t)
	var big_l := el[3] + rt[3] * t
	var peri := el[4] + rt[4] * t
	var node := deg_to_rad(el[5] + rt[5] * t)
	var m_deg := big_l - peri
	if not bcsf.is_empty():
		var f := deg_to_rad(bcsf[3] * t)
		m_deg += bcsf[0] * t * t + bcsf[1] * cos(f) + bcsf[2] * sin(f)
	var w := deg_to_rad(peri) - node
	var n := deg_to_rad(rt[3] - rt[4]) / (36525.0 * DAY)
	return kepler_state(a, e, inc, node, w, deg_to_rad(fposmod(m_deg, 360.0)), n)


## State on a Kepler ellipse (elements in the target frame), n = mean motion (rad/s).
static func kepler_state(a: float, e: float, inc: float, node: float, w: float, mean_anom: float, n: float) -> PackedFloat64Array:
	var big_e := mean_anom + e * sin(mean_anom) if e < 0.8 else (PI if mean_anom > 0.0 else -PI)
	if e >= 0.8 and absf(mean_anom) < 1e-12:
		big_e = 0.0
	for _k in 40:
		var d := (big_e - e * sin(big_e) - mean_anom) / (1.0 - e * cos(big_e))
		big_e -= d
		if absf(d) < 1e-14:
			break
	var ce := cos(big_e)
	var se := sin(big_e)
	var sq := sqrt(1.0 - e * e)
	var fac := 1.0 - e * ce
	var xp := a * (ce - e)
	var yp := a * sq * se
	var vxp := -a * n * se / fac
	var vyp := a * n * sq * ce / fac
	var cw := cos(w)
	var sw := sin(w)
	var co := cos(node)
	var so := sin(node)
	var ci := cos(inc)
	var si := sin(inc)
	var px := cw * co - sw * so * ci
	var py := cw * so + sw * co * ci
	var pz := sw * si
	var qx := -sw * co - cw * so * ci
	var qy := -sw * so + cw * co * ci
	var qz := cw * si
	return PackedFloat64Array([px * xp + qx * yp, py * xp + qy * yp, pz * xp + qz * yp,
		px * vxp + qx * vyp, py * vxp + qy * vyp, pz * vxp + qz * vyp])


# ------------------------------------------------------------ the Moon
func _moon_state(days: float) -> PackedFloat64Array:
	var h := 60.0 / DAY
	var p0 := moon_position(days)
	var pa := moon_position(days + h)
	var pb := moon_position(days - h)
	return PackedFloat64Array([p0[0], p0[1], p0[2], (pa[0] - pb[0]) / 120.0, (pa[1] - pb[1]) / 120.0,
		(pa[2] - pb[2]) / 120.0])


## Geocentric Moon (m, ecliptic J2000): Meeus ch. 47.
func moon_position(days: float) -> PackedFloat64Array:
	var lbr := moon_lbr(days)
	var lon := deg_to_rad(lbr[0])
	var lat := deg_to_rad(lbr[1])
	var r := lbr[2] * 1000.0
	return PackedFloat64Array([r * cos(lat) * cos(lon), r * cos(lat) * sin(lon), r * sin(lat)])


## [ecliptic longitude (deg, J2000 equinox), latitude (deg), distance (km)] of the Moon.
func moon_lbr(days: float) -> PackedFloat64Array:
	var p: Dictionary = _orb[_moon]
	var t := days / 36525.0
	var t2 := t * t
	var t3 := t2 * t
	var t4 := t3 * t
	var lp := 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538841.0 - t4 / 65194000.0
	var dd := 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545868.0 - t4 / 113065000.0
	var mm := 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000.0
	var mp := 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69699.0 - t4 / 14712000.0
	var ff := 93.2720950 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3526000.0 + t4 / 863310000.0
	var a1 := deg_to_rad(119.75 + 131.849 * t)
	var a2 := deg_to_rad(53.09 + 479264.290 * t)
	var a3 := deg_to_rad(313.45 + 481266.484 * t)
	var ecc := 1.0 - 0.002516 * t - 0.0000074 * t2
	var d := deg_to_rad(dd)
	var m := deg_to_rad(mm)
	var mpr := deg_to_rad(mp)
	var f := deg_to_rad(ff)
	var lpr := deg_to_rad(lp)
	var sl := 0.0
	var sr := 0.0
	var lr: PackedFloat64Array = p["lr"]
	var k := 0
	while k < lr.size():
		var arg := lr[k] * d + lr[k + 1] * m + lr[k + 2] * mpr + lr[k + 3] * f
		var em := 1.0
		var am := absf(lr[k + 1])
		if am == 1.0:
			em = ecc
		elif am == 2.0:
			em = ecc * ecc
		sl += lr[k + 4] * em * sin(arg)
		sr += lr[k + 5] * em * cos(arg)
		k += 6
	var sb := 0.0
	var tb: PackedFloat64Array = p["b"]
	k = 0
	while k < tb.size():
		var arg := tb[k] * d + tb[k + 1] * m + tb[k + 2] * mpr + tb[k + 3] * f
		var em := 1.0
		var am := absf(tb[k + 1])
		if am == 1.0:
			em = ecc
		elif am == 2.0:
			em = ecc * ecc
		sb += tb[k + 4] * em * sin(arg)
		k += 5
	sl += 3958.0 * sin(a1) + 1962.0 * sin(lpr - f) + 318.0 * sin(a2)
	sb += -2235.0 * sin(lpr) + 382.0 * sin(a3) + 175.0 * sin(a1 - f) + 175.0 * sin(a1 + f) \
		+ 127.0 * sin(lpr - mpr) - 115.0 * sin(lpr + mpr)
	var lon := lp + sl / 1.0e6 - PRECESSION_DEG_CY * t
	return PackedFloat64Array([fposmod(lon, 360.0), sb / 1.0e6, 385000.56 + sr / 1000.0])


# ------------------------------------------------------------ satellites, comet
func _laplace(i: int, days: float) -> PackedFloat64Array:
	var p: Dictionary = _orb[i]
	var dt := days - float(p["epoch"])
	var w := float(p["w0"]) + float(p["w_rate"]) * dt
	var node := float(p["node0"]) + float(p["node_rate"]) * dt
	var mean_anom := fposmod(float(p["M0"]) + float(p["n"]) * dt, TAU)
	var s := kepler_state(p["a"], p["e"], p["i"], node, w, mean_anom, float(p["n"]) / DAY)
	var lx: PackedFloat64Array = p["lx"]
	var ly: PackedFloat64Array = p["ly"]
	var lz: PackedFloat64Array = p["lz"]
	var out := PackedFloat64Array()
	out.resize(6)
	for k in 2:
		var o := k * 3
		for j in 3:
			out[o + j] = lx[j] * s[o] + ly[j] * s[o + 1] + lz[j] * s[o + 2]
	return out


func _helio(i: int, days: float) -> PackedFloat64Array:
	var p: Dictionary = _orb[i]
	var a: float = p["a"]
	var n := sqrt(gm_sun / (a * a * a))
	var mean_anom := fposmod(n * (days - float(p["tp"])) * DAY + PI, TAU) - PI
	return kepler_state(a, p["e"], p["i"], p["node"], p["w"], mean_anom, n)


# ------------------------------------------------------------ frames
## Unit vector of a right ascension / declination (deg), equatorial J2000.
static func radec(ra_deg: float, dec_deg: float) -> PackedFloat64Array:
	var ra := deg_to_rad(ra_deg)
	var dec := deg_to_rad(dec_deg)
	return PackedFloat64Array([cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)])


## Equatorial J2000 -> ecliptic J2000 (rotation by the obliquity about x).
func _eq_to_ecl(v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([v[0], _cos_eps * v[1] + _sin_eps * v[2], -_sin_eps * v[1] + _cos_eps * v[2]])


func eq_to_ecl(v: PackedFloat64Array) -> PackedFloat64Array:
	return _eq_to_ecl(v)


func ecl_to_eq(v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([v[0], _cos_eps * v[1] - _sin_eps * v[2], _sin_eps * v[1] + _cos_eps * v[2]])


## Spin axis of body i (unit, ecliptic J2000) from its IAU pole.
func pole_ecl(i: int) -> PackedFloat64Array:
	var b := data[i]
	return _eq_to_ecl(radec(float(b.get("pole_ra_deg", 0.0)), float(b.get("pole_dec_deg", 90.0))))


# ------------------------------------------------------------ calendar
## Julian date of a Gregorian calendar date (hours as a fraction of the day).
static func jd_of(year: int, month: int, day: int, hours := 0.0) -> float:
	var y := year
	var m := month
	if m <= 2:
		y -= 1
		m += 12
	var a := floorf(y / 100.0)
	var b := 2.0 - a + floorf(a / 4.0)
	return floorf(365.25 * (y + 4716)) + floorf(30.6001 * (m + 1)) + day + b - 1524.5 + hours / 24.0


## Days after J2000 of a calendar date.
static func days_of(year: int, month: int, day: int, hours := 0.0) -> float:
	return jd_of(year, month, day, hours) - J2000_JD


## {"year", "month", "day", "hour", "minute"} of a Julian date (Meeus ch. 7).
static func date_of_jd(jd: float) -> Dictionary:
	var z := floorf(jd + 0.5)
	var f := jd + 0.5 - z
	var a := z
	if z >= 2299161.0:
		var alpha := floorf((z - 1867216.25) / 36524.25)
		a = z + 1.0 + alpha - floorf(alpha / 4.0)
	var b := a + 1524.0
	var c := floorf((b - 122.1) / 365.25)
	var d := floorf(365.25 * c)
	var e := floorf((b - d) / 30.6001)
	var day := b - d - floorf(30.6001 * e)
	var month := int(e - 1.0) if e < 14.0 else int(e - 13.0)
	var year := int(c - 4716.0) if month > 2 else int(c - 4715.0)
	var mins := int(floorf(f * 1440.0 + 1e-6))
	return {"year": year, "month": month, "day": int(day), "hour": mins / 60, "minute": mins % 60}


# ------------------------------------------------------------ small vector helpers
static func _dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func _cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]])


static func _len(a: PackedFloat64Array) -> float:
	return sqrt(_dot(a, a))


static func _unit(a: PackedFloat64Array) -> PackedFloat64Array:
	var l := _len(a)
	return PackedFloat64Array([a[0] / l, a[1] / l, a[2] / l])
