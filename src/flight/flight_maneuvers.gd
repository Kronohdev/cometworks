class_name FlightManeuvers
extends RefCounted
## The list of planned maneuver nodes (sorted by time) and the editing rules shared by
## the map gizmo, the node panel and the tests: add / delete, Δv edits, time drags
## (never into the past, order kept), "one orbit later / earlier", and the picking helpers
## that turn a point on a predicted segment into a time.

signal changed

## a node cannot be dragged closer than this to "now" (s)
const MIN_LEAD := 5.0

var nodes: Array[FlightManeuverNode] = []
## bumped on every edit (the trajectory cache compares it)
var version := 0


func add(t: float, dv := Vector3.ZERO) -> FlightManeuverNode:
	var n := FlightManeuverNode.new(t, dv)
	nodes.append(n)
	_sort()
	_bump()
	return n


func remove(n: FlightManeuverNode) -> void:
	nodes.erase(n)
	_bump()


func clear() -> void:
	nodes.clear()
	_bump()


func first() -> FlightManeuverNode:
	return nodes[0] if not nodes.is_empty() else null


func index_of(n: FlightManeuverNode) -> int:
	return nodes.find(n)


func set_dv(n: FlightManeuverNode, dv: Vector3) -> void:
	if n.dv == dv:
		return
	n.dv = dv
	_bump()


func add_dv(n: FlightManeuverNode, d: Vector3) -> void:
	set_dv(n, n.dv + d)


## Moves a node in time; it stays after `now` + MIN_LEAD and after the previous node, before
## the next one (a node cannot jump over its neighbours: the plan downstream depends on it).
func set_time(n: FlightManeuverNode, t: float, now: float) -> void:
	var i := nodes.find(n)
	var lo := now + MIN_LEAD
	var hi := INF
	if i > 0:
		lo = maxf(lo, nodes[i - 1].time + 1.0)
	if i >= 0 and i < nodes.size() - 1:
		hi = nodes[i + 1].time - 1.0
	var nt := clampf(t, lo, maxf(lo, hi))
	if nt == n.time:
		return
	n.time = nt
	_bump()


func _sort() -> void:
	nodes.sort_custom(func(a: FlightManeuverNode, b: FlightManeuverNode) -> bool: return a.time < b.time)


func _bump() -> void:
	version += 1
	changed.emit()


# ------------------------------------------------------------ picking helpers
## Time at fraction f between samples i and i + 1 of a segment (linear in the sample's
## anomaly spacing, which is what the stored times follow closely).
static func time_on_segment(seg: FlightTrajectory.Segment, i: int, f: float) -> float:
	var n := seg.times.size()
	if n == 0:
		return seg.t0
	i = clampi(i, 0, n - 1)
	if i >= n - 1:
		return seg.times[n - 1]
	return lerpf(seg.times[i], seg.times[i + 1], clampf(f, 0.0, 1.0))


## Closest stored sample segment to a point given relative to the segment's body:
## {"i", "f", "d"} (d in metres).
static func nearest_on_segment(seg: FlightTrajectory.Segment, p: PackedFloat64Array) -> Dictionary:
	var best := {"i": 0, "f": 0.0, "d": INF}
	var n := seg.times.size()
	for i in n - 1:
		var ax := seg.pts[i * 3]
		var ay := seg.pts[i * 3 + 1]
		var az := seg.pts[i * 3 + 2]
		var bx := seg.pts[i * 3 + 3] - ax
		var by := seg.pts[i * 3 + 4] - ay
		var bz := seg.pts[i * 3 + 5] - az
		var l2 := bx * bx + by * by + bz * bz
		var f := 0.0
		if l2 > 0.0:
			f = clampf(((p[0] - ax) * bx + (p[1] - ay) * by + (p[2] - az) * bz) / l2, 0.0, 1.0)
		var dx := ax + bx * f - p[0]
		var dy := ay + by * f - p[1]
		var dz := az + bz * f - p[2]
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		if d < float(best["d"]):
			best = {"i": i, "f": f, "d": d}
	return best
