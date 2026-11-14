class_name FlightTrajectory
extends RefCounted
## Patched-conic trajectory prediction (KSP style). From a state vector around one body
## the vessel follows a two-body conic (FlightConic) until the first of:
##   - ESCAPE     it leaves the body's sphere of influence -> continues around the parent
##   - ENCOUNTER  it enters the SOI of one of the body's children (Moon, planets)
##   - IMPACT     it reaches the surface
##   - NODE       a maneuver node: the node's Δv is added and the plan goes on (dashed)
##   - HORIZON    one revolution (closed orbits) without events
## Encounter search: the conic is sampled uniformly in eccentric / hyperbolic anomaly
## (dense where the vessel moves fast, never misses a periapsis pass), every child body is
## tested at each sample (entry into its SOI, or a distance minimum refined by
## golden-section search), and the SOI boundary is located by bisection in time.
## The samples are kept (positions relative to the segment's body + times) so the map can
## draw and pick the trajectory without recomputing anything.
## Pure math on RefCounted data: safe to run on a worker thread.

enum End { HORIZON, ESCAPE, ENCOUNTER, IMPACT, NODE }

const MAX_SEGMENTS := 12
const MAX_AFTER_LAST_NODE := 5
## samples per revolution (quality 1)
const SAMPLES_PER_REV := 260
const MAX_SAMPLES := 3000


class Segment:
	extends RefCounted
	var body := 0
	var conic: FlightConic
	var t0 := 0.0
	var t1 := 0.0
	var end := End.HORIZON
	var next_body := -1
	## 0 = the current trajectory, k = after the k-th maneuver node
	var plan := 0
	var node_index := -1
	## samples: positions (x, y, z triplets, metres, relative to `body`) and their times
	var pts := PackedFloat64Array()
	var times := PackedFloat64Array()

	func point(i: int) -> PackedFloat64Array:
		return PackedFloat64Array([pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2]])

	func count() -> int:
		return times.size()


var segments: Array[Segment] = []
var t_start := 0.0
var start_body := 0
var target := -1
## closest approach to the target body: {"t", "d", "seg"} (empty if none found)
var closest := {}
## the current (unplanned) prediction stays exact until this time (then re-predict)
var valid_until := INF
var compute_ms := 0.0


## Predicts from state (r, v) around `body` at time t. `nodes`: FlightManeuverNode sorted by
## time (filled in place: body, state, dv_world). `quality` scales the sample count
## (0.4 while dragging a node).
static func predict(sys: FlightSolar, body: int, r: PackedFloat64Array, v: PackedFloat64Array, t: float,
		nodes: Array = [], target_body := -1, quality := 1.0) -> FlightTrajectory:
	var t_clock := Time.get_ticks_usec()
	var tr := FlightTrajectory.new()
	tr.t_start = t
	tr.start_body = body
	tr.target = target_body
	var cur := body
	var pr := r.duplicate()
	var pv := v.duplicate()
	var tt := t
	var plan := 0
	var node_i := 0
	var after_last := 0
	var exclude := -1
	for n: FlightManeuverNode in nodes:
		n.valid = false
	# skip nodes far in the past (a node being executed stays: its remainder applies now)
	while node_i < nodes.size() and (nodes[node_i] as FlightManeuverNode).time < t - 1.0e5:
		node_i += 1
	for iter in MAX_SEGMENTS:
		if FlightOrbit.length(pr) < 1.0:
			break
		var conic := FlightConic.from_state(pr, pv, sys.mu[cur], tt)
		var seg := Segment.new()
		seg.body = cur
		seg.conic = conic
		seg.t0 = tt
		seg.plan = plan
		var has_node := node_i < nodes.size()
		var node_t := INF
		if has_node:
			node_t = maxf((nodes[node_i] as FlightManeuverNode).time, tt)
		var t_end: float
		if conic.is_closed():
			t_end = tt + conic.period
		else:
			t_end = tt + 3.0e8
		var end := End.HORIZON
		if has_node and (node_t <= t_end or conic.is_closed()):
			t_end = node_t
			end = End.NODE
		if sys.parent[cur] >= 0:
			var t_esc := conic.time_to_radius(sys.soi[cur], tt, true)
			if t_esc < t_end:
				t_end = t_esc
				end = End.ESCAPE
		if conic.rp < sys.radius[cur]:
			var t_imp := conic.time_to_radius(sys.radius[cur], tt, false)
			if t_imp < t_end:
				t_end = t_imp
				end = End.IMPACT
		if not conic.is_closed() and end == End.HORIZON:
			# open orbit around the root body: stop drawing far out
			t_end = minf(t_end, tt + 3.0e8)
		var enc := tr._sample_and_search(sys, seg, t_end, exclude, quality)
		if not enc.is_empty() and float(enc["t"]) < t_end:
			t_end = enc["t"]
			end = End.ENCOUNTER
			seg.next_body = enc["body"]
			tr._trim(seg, t_end)
		seg.t1 = t_end
		seg.end = end
		tr.segments.append(seg)
		if plan == 0 and end == End.HORIZON and not has_node:
			tr.valid_until = t_end
		if end == End.HORIZON or end == End.IMPACT:
			break
		var s := conic.state_at(t_end)
		exclude = -1
		match end:
			End.ESCAPE:
				var par := sys.parent[cur]
				var o := sys.state_rel(cur, par, t_end)
				for k in 6:
					s[k] += o[k]
				exclude = cur
				seg.next_body = par
				cur = par
			End.ENCOUNTER:
				var o := sys.state_rel(seg.next_body, cur, t_end)
				for k in 6:
					s[k] -= o[k]
				cur = seg.next_body
			End.NODE:
				var nd: FlightManeuverNode = nodes[node_i]
				seg.node_index = node_i
				nd.body = cur
				nd.state = s.duplicate()
				# while a burn is under way the planned vector is frozen (the state moves)
				if not nd.locked:
					nd.dv_world = FlightManeuverNode.to_world(s, nd.dv)
				nd.valid = true
				var rn := sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2])
				var gm := sys.mu[cur]
				if not nd.locked:
					nd.energy_before = (s[3] * s[3] + s[4] * s[4] + s[5] * s[5]) * 0.5 - gm / rn
				s[3] += nd.dv_world[0] - nd.burned.x
				s[4] += nd.dv_world[1] - nd.burned.y
				s[5] += nd.dv_world[2] - nd.burned.z
				if not nd.locked:
					nd.energy_after = (s[3] * s[3] + s[4] * s[4] + s[5] * s[5]) * 0.5 - gm / rn
				node_i += 1
				plan += 1
		pr = PackedFloat64Array([s[0], s[1], s[2]])
		pv = PackedFloat64Array([s[3], s[4], s[5]])
		tt = t_end
		if node_i >= nodes.size() and plan > 0:
			after_last += 1
			if after_last > MAX_AFTER_LAST_NODE:
				break
	tr.compute_ms = (Time.get_ticks_usec() - t_clock) / 1000.0
	return tr


## Samples the segment's conic between seg.t0 and t_end (stored in seg.pts / seg.times)
## and looks for the earliest SOI entry into a child of seg.body. Also tracks the closest
## approach to the target. Returns {"t", "body"} or {}.
func _sample_and_search(sys: FlightSolar, seg: Segment, t_end: float, exclude: int, quality: float) -> Dictionary:
	var c := seg.conic
	var kids: PackedInt32Array = sys.children[seg.body]
	var nk := kids.size()
	var count: int
	var x0 := 0.0
	var x1 := 0.0
	var mode := 0  # 0 ellipse, 1 hyperbola, 2 time (degenerate)
	if c.degenerate:
		mode = 2
		count = int(160 * quality) + 16
	elif c.e < 1.0:
		var m0 := c.n * (seg.t0 - c.t_peri)
		var m1 := c.n * (t_end - c.t_peri)
		x0 = _unwrapped_e(c, m0)
		x1 = _unwrapped_e(c, m1)
		count = clampi(int(ceil((x1 - x0) / TAU * SAMPLES_PER_REV * quality)), 24, MAX_SAMPLES)
	else:
		mode = 1
		x0 = c.anomaly_at(seg.t0)
		x1 = c.anomaly_at(t_end)
		count = clampi(int(SAMPLES_PER_REV * quality), 40, MAX_SAMPLES)
	seg.pts.resize((count + 1) * 3)
	seg.times.resize(count + 1)
	var dprev := PackedFloat64Array()
	var dprev2 := PackedFloat64Array()
	var seen_out := PackedByteArray()
	dprev.resize(nk)
	dprev2.resize(nk)
	seen_out.resize(nk)
	for k in nk:
		dprev[k] = INF
		dprev2[k] = INF
		seen_out[k] = 0 if kids[k] == exclude else 1
	var best_t := INF
	var best_body := -1
	var tgt_k := kids.find(target)
	var tgt_min := INF
	var tgt_i := -1
	for i in count + 1:
		var f := float(i) / float(count)
		var ts: float
		var p: PackedFloat64Array
		if mode == 2:
			ts = seg.t0 + (t_end - seg.t0) * f
			p = c.position_at(ts)
		else:
			var x := x0 + (x1 - x0) * f
			ts = c.time_at_anomaly(x)
			if i == 0:
				ts = seg.t0
			elif i == count:
				ts = t_end
			p = c.position_at_anomaly(x)
		seg.pts[i * 3] = p[0]
		seg.pts[i * 3 + 1] = p[1]
		seg.pts[i * 3 + 2] = p[2]
		seg.times[i] = ts
		if ts >= best_t:
			continue
		for k in nk:
			var kb := kids[k]
			var q := sys.pos_rel_parent(kb, ts)
			var dx := p[0] - q[0]
			var dy := p[1] - q[1]
			var dz := p[2] - q[2]
			var d := sqrt(dx * dx + dy * dy + dz * dz)
			var rs := sys.soi[kb]
			if k == tgt_k and d < tgt_min:
				tgt_min = d
				tgt_i = i
			if i == 0 and absf(d - rs) < rs * 1e-3:
				# starting on this SOI's boundary (just left it): count it only after leaving
				seen_out[k] = 0
			if seen_out[k] == 0:
				if d > rs * 1.001:
					seen_out[k] = 1
				dprev2[k] = dprev[k]
				dprev[k] = d
				continue
			if d < rs:
				var t_lo := seg.times[i - 1] if i > 0 else seg.t0
				var te := seg.t0 if i == 0 else _bisect_entry(sys, c, kb, t_lo, ts)
				if te < best_t:
					best_t = te
					best_body = kb
			elif i >= 2 and dprev[k] < dprev2[k] and dprev[k] <= d and dprev[k] < rs * 4.0:
				# a distance minimum between samples i-2 .. i: is it inside the SOI?
				var ta := seg.times[i - 2]
				var tb := ts
				var tm := _golden_min(sys, c, kb, ta, tb)
				if _dist(sys, c, kb, tm) < rs:
					var te := _bisect_entry(sys, c, kb, ta, tm)
					if te < best_t:
						best_t = te
						best_body = kb
			dprev2[k] = dprev[k]
			dprev[k] = d
	if tgt_i >= 0:
		var ta := seg.times[maxi(tgt_i - 1, 0)]
		var tb := seg.times[mini(tgt_i + 1, count)]
		var tm := _golden_min(sys, c, target, ta, tb)
		var dm := _dist(sys, c, target, tm)
		if closest.is_empty() or dm < float(closest["d"]):
			closest = {"t": tm, "d": dm, "seg": segments.size(), "body": seg.body}
	if best_body < 0:
		return {}
	return {"t": best_t, "body": best_body}


## Cuts the stored samples at time t_cut (the encounter), adding the exact end point.
func _trim(seg: Segment, t_cut: float) -> void:
	var n := seg.times.size()
	var keep := n
	for i in n:
		if seg.times[i] >= t_cut:
			keep = i
			break
	seg.times.resize(keep + 1)
	seg.pts.resize((keep + 1) * 3)
	var p := seg.conic.position_at(t_cut)
	seg.times[keep] = t_cut
	seg.pts[keep * 3] = p[0]
	seg.pts[keep * 3 + 1] = p[1]
	seg.pts[keep * 3 + 2] = p[2]


static func _unwrapped_e(c: FlightConic, m: float) -> float:
	var w := fposmod(m + PI, TAU) - PI
	return c.anomaly_at(c.t_peri + w / c.n) + (m - w)


static func _dist(sys: FlightSolar, c: FlightConic, kb: int, t: float) -> float:
	var p := c.position_at(t)
	var q := sys.pos_rel_parent(kb, t)
	return sqrt((p[0] - q[0]) * (p[0] - q[0]) + (p[1] - q[1]) * (p[1] - q[1]) + (p[2] - q[2]) * (p[2] - q[2]))


## Time of the SOI boundary crossing between t_out (outside) and t_in (inside).
static func _bisect_entry(sys: FlightSolar, c: FlightConic, kb: int, t_out: float, t_in: float) -> float:
	var rs := sys.soi[kb]
	var lo := t_out
	var hi := t_in
	for i in 48:
		var mid := (lo + hi) * 0.5
		if _dist(sys, c, kb, mid) < rs:
			hi = mid
		else:
			lo = mid
		if hi - lo < 0.01:
			break
	return hi


static func _golden_min(sys: FlightSolar, c: FlightConic, kb: int, ta: float, tb: float) -> float:
	var g := 0.6180339887498949
	var a := ta
	var b := tb
	var x1 := b - g * (b - a)
	var x2 := a + g * (b - a)
	var f1 := _dist(sys, c, kb, x1)
	var f2 := _dist(sys, c, kb, x2)
	for i in 40:
		if f1 < f2:
			b = x2
			x2 = x1
			f2 = f1
			x1 = b - g * (b - a)
			f1 = _dist(sys, c, kb, x1)
		else:
			a = x1
			x1 = x2
			f1 = f2
			x2 = a + g * (b - a)
			f2 = _dist(sys, c, kb, x2)
		if b - a < 0.5:
			break
	return (a + b) * 0.5


# ------------------------------------------------------------ queries
## Segment index containing absolute time t on plan 0 (the current trajectory), or -1.
func current_segment_at(t: float) -> int:
	for i in segments.size():
		var s := segments[i]
		if s.plan != 0:
			break
		if t >= s.t0 - 1e-6 and t <= s.t1 + 1e-6:
			return i
	return -1


## First plan-0 event after time t: {"t", "kind", "seg"} (SOI changes and impact).
func next_event(t: float) -> Dictionary:
	for i in segments.size():
		var s := segments[i]
		if s.plan != 0:
			break
		if s.t1 > t and (s.end == End.ESCAPE or s.end == End.ENCOUNTER or s.end == End.IMPACT):
			return {"t": s.t1, "kind": s.end, "seg": i}
	return {}


## Encounter summary for plan `plan` (or any if -1): first segment around a body other than
## the start body that was entered by ENCOUNTER -> {"body", "t_enter", "t_pe", "pe_alt"}.
func encounter_summary(sys: FlightSolar, plan := -1) -> Dictionary:
	for i in range(1, segments.size()):
		var s := segments[i]
		var prev := segments[i - 1]
		if prev.end != End.ENCOUNTER or (plan >= 0 and s.plan != plan):
			continue
		var c := s.conic
		var t_pe := c.time_at_true_anomaly(0.0, s.t0) if not c.degenerate else INF
		var pe_alt := c.rp - sys.radius[s.body]
		if t_pe > s.t1:
			# the segment ends before the periapsis (impact or escape first)
			t_pe = s.t1
			pe_alt = FlightOrbit.length(c.position_at(s.t1)) - sys.radius[s.body]
		return {"body": s.body, "t_enter": s.t0, "t_pe": t_pe, "pe_alt": pe_alt, "seg": i}
	return {}
