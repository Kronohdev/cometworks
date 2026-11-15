extends SceneTree
## Headless checks of the real ephemeris (src/flight/ephemeris.gd) and of FlightSolar built on
## it, against published values:
##   1. calendar: Julian dates of known dates and back
##   2. the Moon: Meeus' worked example 47.a (1992-04-12 0h TD), the perigee of the 2016-11-14
##      supermoon (356 509 km), the distance range over 2025-2035, i ~5.145 deg to the ecliptic,
##      the node's 18.6-year regression, the sidereal month
##   3. planets: Venus on 1992-12-20 (Meeus example 32.a, VSOP87), the Earth's perihelion of
##      2026 (Jan 3, 0.98330 AU), the March equinox of 2024 (03:06 UTC), the Mars close
##      approaches of 2003 (0.3727 AU, Aug 27) and 2018 (0.3850 AU, Jul 31), the periods
##   4. satellites: the Galilean moons' periods and distances, Titan, Phobos
##   5. FlightSolar: the PCI frame (pad latitude, Earth's obliquity in PCI, Sun at the pad's
##      morning), the Hermite cache against the exact series, velocity == d(position)/dt
##   6. the comet Mãe-Gelo: a Halley-type orbit whose closest approach to the Earth is at the
##      end of the campaign (week 1300), at a safe but close distance
## Run: godot --headless --path . --script res://tests/test_ephemeris.gd

const AU := 149597870700.0
const DAY := 86400.0

var _failures := 0
var eph: Ephemeris


func _initialize() -> void:
	eph = Ephemeris.shared()
	_check(eph != null and eph.ids.size() >= 19, "Ephemeris script loaded (%d bodies)" % eph.ids.size())
	var t0 := Time.get_ticks_msec()
	_test_calendar()
	_test_moon()
	_test_planets()
	_test_satellites()
	_test_flight_solar()
	_test_comet()
	print("time %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1


static func dist(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


static func vlen(a: PackedFloat64Array) -> float:
	return sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


func _i(id: String) -> int:
	return eph.index_of(id)


## Heliocentric ecliptic longitude (deg 0..360) and latitude of a position.
static func lon_lat(p: PackedFloat64Array) -> Vector2:
	var r := vlen(p)
	return Vector2(fposmod(rad_to_deg(atan2(p[1], p[0])), 360.0), rad_to_deg(asin(p[2] / r)))


## Minimum of f(days) on [a, b] (golden section after a coarse scan): [days, value].
static func minimize(f: Callable, a: float, b: float, n := 200) -> Vector2:
	var best := a
	var bv := INF
	for k in n + 1:
		var d := lerpf(a, b, float(k) / n)
		var v: float = f.call(d)
		if v < bv:
			bv = v
			best = d
	var lo := best - (b - a) / n
	var hi := best + (b - a) / n
	for k in 80:
		var m1 := lo + (hi - lo) * 0.382
		var m2 := lo + (hi - lo) * 0.618
		if float(f.call(m1)) < float(f.call(m2)):
			hi = m2
		else:
			lo = m1
	var x := (lo + hi) * 0.5
	return Vector2(x, f.call(x))


# ------------------------------------------------------------ 1
func _test_calendar() -> void:
	print("calendar")
	_check(absf(Ephemeris.jd_of(2000, 1, 1, 12.0) - 2451545.0) < 1e-9, "J2000.0 = JD 2451545.0")
	_check(absf(Ephemeris.jd_of(1957, 10, 4, 19.0 + 26.0 / 60.0) - 2436116.31) < 0.01, "Sputnik launch JD 2436116.31")
	_check(absf(Ephemeris.jd_of(2026, 10, 28, 12.0) - 2461342.0) < 1e-9, "campaign epoch 2026-10-28 12:00 = JD 2461342.0")
	var d := Ephemeris.date_of_jd(2470442.0)
	print("  campaign end (week 1300, 9100 days): %04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]])
	_check(d["year"] == 2051 and d["month"] == 9 and d["day"] == 27, "JD 2470442.0 = 2051-09-27")
	var back := Ephemeris.date_of_jd(Ephemeris.jd_of(1969, 7, 20, 20.0 + 17.0 / 60.0))
	_check(back["year"] == 1969 and back["month"] == 7 and back["day"] == 20 and back["hour"] == 20 and back["minute"] == 17,
		"date -> JD -> date round trip (Apollo 11 landing, 1969-07-20 20:17)")


# ------------------------------------------------------------ 2
func _test_moon() -> void:
	print("the Moon")
	var days := 2448724.5 - Ephemeris.J2000_JD
	var lbr := eph.moon_lbr(days)
	var t := days / 36525.0
	var lon_date := lbr[0] + Ephemeris.PRECESSION_DEG_CY * t
	print("  1992-04-12 0h TD: lon %.6f (Meeus 133.162655), lat %.6f (-3.229126), dist %.1f km (368409.7)" % [
		lon_date, lbr[1], lbr[2]])
	_check(absf(lon_date - 133.162655) < 0.002 and absf(lbr[1] + 3.229126) < 0.002 and absf(lbr[2] - 368409.7) < 2.0,
		"Meeus example 47.a reproduced (longitude, latitude, distance)")
	# the supermoon perigee of 2016-11-14 (11:21 UTC, 356 509 km)
	var d0 := Ephemeris.days_of(2016, 11, 14, 11.35)
	var per := minimize(func(x: float) -> float: return eph.moon_lbr(x)[2], d0 - 1.0, d0 + 1.0, 96)
	print("  2016-11-14 perigee: %.1f km, %.2f h from 11:21 UTC" % [per.y, (per.x - d0) * 24.0])
	_check(absf(per.y - 356509.0) < 40.0 and absf(per.x - d0) * 24.0 < 1.5, "supermoon perigee 356 509 km within 40 km, on time")
	# distance range and inclination over ten years
	var dmin := INF
	var dmax := 0.0
	var imin := INF
	var imax := 0.0
	var nodes: Array[float] = []
	var prev_lat := 0.0
	var start := Ephemeris.days_of(2025, 1, 1)
	var k := 0
	while k < 3653 * 8:
		var x := start + k * 0.125
		var b := eph.moon_lbr(x)
		dmin = minf(dmin, b[2])
		dmax = maxf(dmax, b[2])
		if k > 0 and prev_lat < 0.0 and b[1] >= 0.0:
			nodes.append(b[0])   # ascending node longitude
		prev_lat = b[1]
		k += 1
	var moon := _i("moon")
	for m in 40:
		var el := eph.elements(moon, start + m * 91.3)
		imin = minf(imin, rad_to_deg(float(el["i"])))
		imax = maxf(imax, rad_to_deg(float(el["i"])))
	print("  2025-2035: distance %.0f .. %.0f km, osculating inclination %.2f .. %.2f deg" % [dmin, dmax, imin, imax])
	_check(dmin > 356300.0 and dmin < 357000.0 and dmax > 406300.0 and dmax < 406800.0, "distance range 356 400 .. 406 700 km")
	_check(imin > 4.9 and imax < 5.4 and (imin + imax) * 0.5 > 5.0 and (imin + imax) * 0.5 < 5.3, "inclination ~5.145 deg to the ecliptic")
	# node regression: longitude of the ascending node drifts back ~19.35 deg/yr
	if nodes.size() > 20:
		var drift := 0.0
		for j in range(1, nodes.size()):
			drift += wrapf(nodes[j] - nodes[j - 1], -180.0, 180.0)
		var per_month := drift / (nodes.size() - 1)
		var period_yr := 360.0 / absf(per_month) * 27.2122 / 365.25
		print("  ascending node: %.3f deg per draconic month -> regression period %.2f yr (18.6)" % [per_month, period_yr])
		_check(per_month < 0.0 and absf(period_yr - 18.6) < 0.5, "nodes regress in ~18.6 years")
	# the sidereal month: least-squares slope of the unwrapped J2000 longitude over ten years
	# (the periodic terms, up to 6 deg, average out)
	var n := 3653 * 4
	var last := eph.moon_lbr(start)[0]
	var acc := 0.0
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for j in n + 1:
		var x := j * 0.25
		if j > 0:
			var l := eph.moon_lbr(start + x)[0]
			acc += wrapf(l - last, -180.0, 180.0)
			last = l
		sx += x
		sy += acc
		sxx += x * x
		sxy += x * acc
	var slope := ((n + 1) * sxy - sx * sy) / ((n + 1) * sxx - sx * sx)
	var sid := 360.0 / slope
	print("  sidereal month %.4f d (27.3217), J2000 longitudes" % sid)
	_check(absf(sid - 27.3217) < 0.002, "sidereal month 27.3217 d")


# ------------------------------------------------------------ 3
func _test_planets() -> void:
	print("planets")
	var dv := Ephemeris.jd_of(1992, 12, 20) - Ephemeris.J2000_JD
	var venus := eph.state(_i("venus"), dv)
	var ll := lon_lat(PackedFloat64Array([venus[0], venus[1], venus[2]]))
	var t := dv / 36525.0
	var lon_date := ll.x + Ephemeris.PRECESSION_DEG_CY * t
	print("  Venus 1992-12-20 0h: L %.4f (VSOP87 26.1143, of date), B %.4f (-2.6207), R %.6f AU (0.724603)" % [
		lon_date, ll.y, vlen(venus) / AU])
	_check(absf(lon_date - 26.1143) < 0.03 and absf(ll.y + 2.6207) < 0.02 and absf(vlen(venus) / AU - 0.724603) < 0.0002,
		"Venus position matches Meeus example 32.a")
	var earth := _i("earth")
	var d26 := Ephemeris.days_of(2026, 1, 3, 17.0)
	var ph := minimize(func(x: float) -> float: return vlen(eph.state(earth, x)), d26 - 3.0, d26 + 3.0, 60)
	print("  Earth perihelion 2026: %.5f AU, %.1f h from Jan 3 17:00" % [ph.y / AU, (ph.x - d26) * 24.0])
	_check(absf(ph.y / AU - 0.983302) < 0.00005 and absf(ph.x - d26) < 1.0, "perihelion 2026-01-03 at 0.98330 AU")
	var deq := Ephemeris.days_of(2024, 3, 20, 3.1)
	var es := eph.state(earth, deq)
	var sun_lon := fposmod(rad_to_deg(atan2(-es[1], -es[0])) + Ephemeris.PRECESSION_DEG_CY * deq / 36525.0 + 180.0, 360.0) - 180.0
	print("  March equinox 2024-03-20 03:06 UTC: Sun's longitude of date %.4f deg (0; 0.01 deg = 15 min)" % sun_lon)
	_check(absf(sun_lon) < 0.012, "Sun at the vernal equinox on 2024-03-20 03:06 UTC")
	var mars := _i("mars")
	var em := func(x: float) -> float:
		var a := eph.state(earth, x)
		var b := eph.state(mars, x)
		return dist(a, b)
	for c: Array in [[2003, 8, 27, 0.37272], [2018, 7, 31, 0.38496], [2020, 10, 6, 0.41492]]:
		var dc := Ephemeris.days_of(c[0], c[1], c[2], 9.0)
		var m := minimize(em, dc - 10.0, dc + 10.0, 80)
		print("  Mars close approach %d-%02d-%02d: %.5f AU (published %.5f), %.1f d off" % [c[0], c[1], c[2], m.y / AU, c[3],
			m.x - dc])
		_check(absf(m.y / AU - float(c[3])) < 0.0006 and absf(m.x - dc) < 1.5, "Earth-Mars %d: %.4f AU on the right day" % [c[0], c[3]])
	for c: Array in [["mercury", 87.969], ["venus", 224.701], ["earth", 365.256], ["mars", 686.98], ["jupiter", 4332.59],
			["saturn", 10759.22], ["uranus", 30685.4], ["neptune", 60189.0], ["pluto", 90560.0]]:
		var el := eph.elements(_i(c[0]), 9797.0)
		var p_days := float(el["period"]) / DAY
		var tol := 0.003 if c[0] in ["mercury", "venus", "earth", "mars"] else 0.02
		_check(absf(p_days - float(c[1])) / float(c[1]) < tol, "%s period %.2f d (%.2f)" % [c[0], p_days, c[1]])


# ------------------------------------------------------------ 4
func _test_satellites() -> void:
	print("satellites")
	for c: Array in [["io", 1.769, 421800.0], ["europa", 3.551, 671100.0], ["ganymede", 7.155, 1070400.0],
			["callisto", 16.689, 1882700.0], ["titan", 15.945, 1221900.0], ["phobos", 0.3189, 9375.0], ["deimos", 1.2624, 23457.0]]:
		var i := _i(c[0])
		var r := vlen(eph.state(i, 9797.0)) / 1000.0
		# sidereal period from the angle swept in ten periods (projected on the orbit plane)
		var p0 := eph.state(i, 9797.0)
		var hn := Ephemeris._cross(PackedFloat64Array([p0[0], p0[1], p0[2]]), PackedFloat64Array([p0[3], p0[4], p0[5]]))
		var swept := 0.0
		var steps := 400
		var prev := PackedFloat64Array([p0[0], p0[1], p0[2]])
		for k in range(1, steps + 1):
			var s := eph.state(i, 9797.0 + float(c[1]) * 10.0 * k / steps)
			var cur := PackedFloat64Array([s[0], s[1], s[2]])
			var cr := Ephemeris._cross(prev, cur)
			swept += atan2(Ephemeris._dot(cr, hn) / vlen(hn), Ephemeris._dot(prev, cur))
			prev = cur
		var per := float(c[1]) * 10.0 / (swept / TAU)
		print("  %s: r %.0f km (a %.0f), sidereal period %.4f d (%.4f)" % [c[0], r, c[2], per, c[1]])
		_check(absf(r - float(c[2])) / float(c[2]) < 0.035 and absf(per - float(c[1])) / float(c[1]) < 0.002,
			"%s distance and period" % c[0])
	# Jupiter's moons orbit in Jupiter's equator (~3 deg to its orbit), Titan in Saturn's (~27 deg)
	var jn := eph.elements(_i("jupiter"), 9797.0)
	for c: Array in [["io", "jupiter", 3.1], ["titan", "saturn", 26.7]]:
		var s := eph.state(_i(c[0]), 9797.0)
		var p := eph.state(_i(c[1]), 9797.0)
		var h1 := Ephemeris._unit(Ephemeris._cross(PackedFloat64Array([s[0], s[1], s[2]]), PackedFloat64Array([s[3], s[4], s[5]])))
		var h2 := Ephemeris._unit(Ephemeris._cross(PackedFloat64Array([p[0], p[1], p[2]]), PackedFloat64Array([p[3], p[4], p[5]])))
		var ang := rad_to_deg(acos(clampf(Ephemeris._dot(h1, h2), -1.0, 1.0)))
		print("  %s's orbit is %.2f deg from %s's orbit (axial tilt %.1f)" % [c[0], ang, c[1], c[2]])
		_check(absf(ang - float(c[2])) < 1.0, "%s orbits in %s's equator" % [c[0], c[1]])
	_check(jn.has("a"), "elements available")


# ------------------------------------------------------------ 5
func _test_flight_solar() -> void:
	print("FlightSolar (PCI frame and cache)")
	var sys := FlightSolar.get_system()
	_check(sys.eph == eph, "FlightSolar is built on the ephemeris")
	var tilt := rad_to_deg(sys.earth_pole.angle_to(sys.ecliptic_normal))
	print("  Earth's pole to the ecliptic pole %.4f deg; pad latitude %.3f deg" % [tilt,
		90.0 - rad_to_deg(sys.earth_pole.angle_to(Vector3.UP))])
	_check(absf(tilt - 23.4393) < 0.001, "obliquity 23.44 deg in the flight frame")
	_check(absf(90.0 - rad_to_deg(sys.earth_pole.angle_to(Vector3.UP)) - FlightSolar.PAD_LAT_DEG) < 1e-3, "pad at its latitude")
	var sun := sys.pos_rel(sys.sun, sys.earth, 0.0)
	var sd := Vector3(sun[0], sun[1], sun[2]).normalized()
	var elev := rad_to_deg(asin(sd.y))
	var east := sd.dot(FlightSolar.PAD_EAST.normalized())
	print("  Sun at the epoch: elevation %.1f deg, east component %.2f, distance %.5f AU" % [elev, east, vlen(sun) / AU])
	_check(elev > 20.0 and elev < 40.0 and east > 0.5, "morning Sun over the pad at the epoch (east, 20..40 deg up)")
	_check(sd.angle_to(FlightSolar.SUN_DIR) < 1e-5, "SUN_DIR is the real Sun direction")
	# the Moon's orbit vs the equator: between 18.3 and 28.6 deg
	var inc_eq := rad_to_deg(sys.orbit_normal_at(sys.moon, 0.0).angle_to(sys.earth_pole))
	print("  the Moon's orbit is %.2f deg from the equator" % inc_eq)
	_check(inc_eq > 18.0 and inc_eq < 29.0, "Moon's orbit 18..29 deg from the equator")
	# cache vs the exact series
	var worst := {}
	for id in ["moon", "earth", "mercury", "mars", "phobos", "io", "titan", "mae_gelo"]:
		var i := sys.index_of(id)
		var w := 0.0
		var wv := 0.0
		for k in 60:
			var t := 3600.0 * 7.31 * k + 1234.5
			var a := sys.state_rel_parent(i, t)
			var b := sys.exact_state_rel_parent(i, t)
			w = maxf(w, dist(a, b))
			wv = maxf(wv, Vector3(a[3] - b[3], a[4] - b[4], a[5] - b[5]).length())
		worst[id] = w
		_check(w < maxf(50.0, vlen(sys.exact_state_rel_parent(i, 0.0)) * 2e-9) and wv < 0.05,
			"%s: cache within %.2f m / %.4f m/s of the series" % [id, w, wv])
	var i_m := sys.moon
	var st := sys.state_rel_parent(i_m, 5.0e5)
	var dp := sys.pos_rel_parent(i_m, 5.0e5 + 0.5)
	var dm := sys.pos_rel_parent(i_m, 5.0e5 - 0.5)
	var vnum := Vector3(dp[0] - dm[0], dp[1] - dm[1], dp[2] - dm[2])
	_check(vnum.distance_to(Vector3(st[3], st[4], st[5])) < 1e-3, "body velocity == d(position)/dt")
	var t_obj := FlightSolar.t_of_date(2026, 10, 28, 12.0)
	_check(absf(t_obj) < 1e-6, "t = 0 is 2026-10-28 12:00")
	var dt := sys.date_at(9100.0 * DAY)
	_check(dt["year"] == 2051 and dt["month"] == 9 and dt["day"] == 27, "week 1300 is 2051-09-27")
	var t_bench := Time.get_ticks_usec()
	for k in 20000:
		sys.pos_rel_parent(sys.moon, 1000.0 + k * 13.7)
	print("  pos_rel_parent: %.2f us per call" % ((Time.get_ticks_usec() - t_bench) / 20000.0))


# ------------------------------------------------------------ 6
func _test_comet() -> void:
	print("the comet Mãe-Gelo")
	var sys := FlightSolar.get_system()
	var c := sys.comet
	_check(c >= 0, "the comet is a body of the system")
	if c < 0:
		return
	var el := eph.elements(eph.index_of("mae_gelo"), FlightSolar.EPOCH_DAYS)
	var p_yr := float(el["period"]) / DAY / 365.25
	var q := float(el["a"]) * (1.0 - float(el["e"])) / AU
	print("  a %.2f AU, e %.4f, q %.3f AU, i %.1f deg, period %.1f yr" % [float(el["a"]) / AU, el["e"], q,
		rad_to_deg(float(el["i"])), p_yr])
	_check(p_yr > 20.0 and p_yr < 200.0 and float(el["e"]) > 0.9 and q < 1.1, "Halley-type orbit (20-200 yr, e > 0.9, inside 1.1 AU)")
	var end_t := 1300.0 * 604800.0
	var f := func(d: float) -> float: return dist(sys.exact_state_rel_parent(c, d * DAY), sys.exact_state_rel_parent(sys.earth, d * DAY))
	var m := minimize(f, end_t / DAY - 60.0, end_t / DAY + 60.0, 240)
	print("  closest approach to the Earth: %.4f AU (%.1f million km) at %.2f days from week 1300" % [m.y / AU,
		m.y / 1.0e9, m.x - end_t / DAY])
	_check(absf(m.x - end_t / DAY) < 1.0, "closest approach on the campaign's last day (the race clock)")
	_check(m.y / AU > 0.03 and m.y / AU < 0.2, "a close but safe pass (0.03 .. 0.2 AU)")
	var start_d := dist(sys.exact_state_rel_parent(c, 0.0), PackedFloat64Array([0.0, 0.0, 0.0])) / AU
	var near_d := dist(sys.exact_state_rel_parent(c, end_t - 104.0 * 604800.0), PackedFloat64Array([0.0, 0.0, 0.0])) / AU
	print("  distance from the Sun: %.1f AU at the campaign start, %.1f AU when it comes within reach (104 weeks left)" % [
		start_d, near_d])
	_check(start_d > near_d and near_d < 12.0, "inbound during the campaign")
