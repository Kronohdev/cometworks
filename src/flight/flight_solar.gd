class_name FlightSolar
extends RefCounted
## The flight's solar system for patched conics: every body of data/solar_system.json with
## its gravitational parameter, radius, sphere of influence and a circular orbit around
## its parent, positioned from the JPL J2000 mean longitudes at the mission epoch.
##
## Frames: everything is expressed in the flight's inertial axes (PCI, see FlightOrbit:
## +Y = up at the launch pad). Positions are doubles (PackedFloat64Array).
##   - Planets move on circular orbits in their real inclined planes (inclination about the
##     line of nodes, JPL elements). The ecliptic is placed so that, at mission time 0, the
##     Sun is exactly where the flight sky draws it (sun_dir) and the ecliptic normal is
##     the one closest to the launch-orbit normal: an eastward parking orbit then contains
##     the Earth's orbital velocity (prograde / retrograde escapes need no plane change).
##   - The Moon orbits in the launch plane (like KSP's Mun; the real orbit is 18-28 deg off
##     the equator), with its real phase: its elongation from the Sun at the epoch.
##   - Europa follows Jupiter's orbit plane, arbitrary phase (as in the solar-system map).
## GM: standard values for the Sun, Earth (== FlightOrbit.MU) and Moon; the other bodies use
## g * R^2 from the data. SOI radius: r = a (GM / GM_parent)^(2/5).

const DATA_PATH := "res://data/solar_system.json"
## Mission epoch in days after J2000 (2026-10-28, the build date of the map; a Mars
## transfer window opens ~19 days later with these mean longitudes).
const EPOCH_DAYS := 9797.0
const DAY := 86400.0
## Sun direction (PCI) at mission time 0 and the launch-orbit normal (pad up x east), the
## values authored in scenes/flight/flight.tscn.
const SUN_DIR := Vector3(0.72, 0.45, 0.42)
const LAUNCH_NORMAL := Vector3(-0.447, 0.0, -0.894)
const GM_OVERRIDE := {"sun": 1.32712440018e20, "earth": FlightOrbit.MU, "moon": 4.9048695e12}
## atmosphere top (m) used for drag, rails warp and impact warnings; only Earth's is modelled
const ATMO := {"earth": FlightOrbit.ATMO_TOP}

static var _instance: FlightSolar = null

var ids: PackedStringArray = []
var names: Array[Dictionary] = []
var kinds: PackedStringArray = []
var parent: PackedInt32Array = []
var children: Array[PackedInt32Array] = []
var mu: PackedFloat64Array = []
var radius: PackedFloat64Array = []
var soi: PackedFloat64Array = []
## orbit radius around the parent (m) and angular rate (rad/s)
var sma: PackedFloat64Array = []
var rate: PackedFloat64Array = []
## argument of latitude at mission time 0 (rad)
var phase: PackedFloat64Array = []
## orbit-plane basis (PCI): position = sma (cos u P + sin u Q)
var plane_p: Array[PackedFloat64Array] = []
var plane_q: Array[PackedFloat64Array] = []
var atmo_top: PackedFloat64Array = []
var colors: Array[Color] = []
var sun := 0
var earth := 0
var moon := 0
var ecliptic_normal := Vector3.UP


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


func build(sun_dir: Vector3, launch_normal: Vector3) -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var au_m: float = float(data["au_km"]) * 1000.0
	var bodies: Array = data["bodies"]
	for b: Dictionary in bodies:
		ids.append(String(b["id"]))
	for b: Dictionary in bodies:
		var id: String = b["id"]
		names.append(b["name"])
		kinds.append(String(b["type"]))
		parent.append(ids.find(String(b["parent"])))
		var r_m: float = float(b["radius_km"]) * 1000.0
		radius.append(r_m)
		mu.append(float(GM_OVERRIDE.get(id, float(b["surface_gravity_ms2"]) * r_m * r_m)))
		var a := 0.0
		if b.has("semi_major_axis_au") and float(b["semi_major_axis_au"]) > 0.0:
			a = float(b["semi_major_axis_au"]) * au_m
		elif b.has("semi_major_axis_km"):
			a = float(b["semi_major_axis_km"]) * 1000.0
		sma.append(a)
		var period_s: float = float(b["orbital_period_days"]) * DAY
		rate.append(TAU / period_s if period_s > 0.0 else 0.0)
		atmo_top.append(float(ATMO.get(id, 0.0)))
		var pal: Array = (b["visual"] as Dictionary).get("palette", ["#cccccc"])
		var c := Color.html(String(pal[mini(1, pal.size() - 1)]))
		colors.append(c.lerp(Color.WHITE, 0.25))
		children.append(PackedInt32Array())
		phase.append(0.0)
		plane_p.append(PackedFloat64Array([1.0, 0.0, 0.0]))
		plane_q.append(PackedFloat64Array([0.0, 0.0, -1.0]))
	sun = ids.find("sun")
	earth = ids.find("earth")
	moon = ids.find("moon")
	for i in ids.size():
		if parent[i] >= 0:
			children[parent[i]].append(i)
	for i in ids.size():
		soi.append(INF if parent[i] < 0 else sma[i] * pow(mu[i] / mu[parent[i]], 0.4))
	# --- ecliptic frame in PCI axes
	var s := sun_dir.normalized()
	var nl := launch_normal.normalized()
	ecliptic_normal = (nl - s * nl.dot(s)).normalized()
	var n_e := ecliptic_normal
	var be: Dictionary = bodies[earth]
	var l_earth := deg_to_rad(float(be["mean_longitude_j2000_deg"])) + rate[earth] * EPOCH_DAYS * DAY
	var u := -s
	var w := n_e.cross(u)
	var x_e := u * cos(l_earth) - w * sin(l_earth)
	var y_e := u * sin(l_earth) + w * cos(l_earth)
	for i in ids.size():
		var b: Dictionary = bodies[i]
		if parent[i] != sun:
			continue
		var inc := deg_to_rad(float(b.get("orbital_inclination_deg", 0.0)))
		var node := deg_to_rad(float(b.get("longitude_ascending_node_deg", 0.0)))
		var lon := deg_to_rad(float(b.get("mean_longitude_j2000_deg", 0.0))) + rate[i] * EPOCH_DAYS * DAY
		# ecliptic coordinates of P (ascending node) and Q, then to PCI
		var pe := Vector3(cos(node), sin(node), 0.0)
		var qe := Vector3(-sin(node) * cos(inc), cos(node) * cos(inc), sin(inc))
		plane_p[i] = _to_pci(pe, x_e, y_e, n_e)
		plane_q[i] = _to_pci(qe, x_e, y_e, n_e)
		phase[i] = lon - node
	# Moon: launch plane, real elongation from the Sun
	if moon >= 0:
		var bm: Dictionary = bodies[moon]
		var l_moon := deg_to_rad(float(bm["mean_longitude_j2000_deg"])) + rate[moon] * EPOCH_DAYS * DAY
		var elong := l_moon - (l_earth + PI)
		var sp := (s - nl * s.dot(nl)).normalized()
		var tp := nl.cross(sp)
		plane_p[moon] = PackedFloat64Array([sp.x, sp.y, sp.z])
		plane_q[moon] = PackedFloat64Array([tp.x, tp.y, tp.z])
		phase[moon] = elong
	# other moons: their parent's orbit plane
	for i in ids.size():
		if i == moon or parent[i] < 0 or parent[i] == sun:
			continue
		plane_p[i] = plane_p[parent[i]]
		plane_q[i] = plane_q[parent[i]]
		var b: Dictionary = bodies[i]
		phase[i] = deg_to_rad(float(b.get("mean_longitude_j2000_deg", 0.0))) + rate[i] * EPOCH_DAYS * DAY


static func _to_pci(v: Vector3, x_e: Vector3, y_e: Vector3, n_e: Vector3) -> PackedFloat64Array:
	var o := x_e * v.x + y_e * v.y + n_e * v.z
	return PackedFloat64Array([o.x, o.y, o.z])


# ------------------------------------------------------------ positions (mission time t, s)
## Position of body i relative to its parent.
func pos_rel_parent(i: int, t: float) -> PackedFloat64Array:
	if parent[i] < 0:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var u := phase[i] + rate[i] * t
	var c := cos(u) * sma[i]
	var s := sin(u) * sma[i]
	var bp := plane_p[i]
	var bq := plane_q[i]
	return PackedFloat64Array([bp[0] * c + bq[0] * s, bp[1] * c + bq[1] * s, bp[2] * c + bq[2] * s])


## [x, y, z, vx, vy, vz] of body i relative to its parent.
func state_rel_parent(i: int, t: float) -> PackedFloat64Array:
	if parent[i] < 0:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var u := phase[i] + rate[i] * t
	var cu := cos(u)
	var su := sin(u)
	var a := sma[i]
	var av := a * rate[i]
	var bp := plane_p[i]
	var bq := plane_q[i]
	return PackedFloat64Array([
		a * (bp[0] * cu + bq[0] * su), a * (bp[1] * cu + bq[1] * su), a * (bp[2] * cu + bq[2] * su),
		av * (-bp[0] * su + bq[0] * cu), av * (-bp[1] * su + bq[1] * cu), av * (-bp[2] * su + bq[2] * cu)])


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


## Orbit-plane normal of body i (PCI, unit).
func orbit_normal(i: int) -> Vector3:
	var bp := plane_p[i]
	var bq := plane_q[i]
	return Vector3(bp[0], bp[1], bp[2]).cross(Vector3(bq[0], bq[1], bq[2])).normalized()


## Orbit period of body i around its parent (s).
func period(i: int) -> float:
	return TAU / rate[i] if rate[i] > 0.0 else INF
