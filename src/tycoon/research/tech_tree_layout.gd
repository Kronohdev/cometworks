class_name TechTreeLayout
extends RefCounted
## Where each technology sits on the research tree (scenes/tycoon/ui/screens/research.tscn), worked
## out from the data alone so new techs (any era, any branch) find a place by themselves:
##   - the tree grows bottom to top: era 1 is the lowest row, the last era the crown
##   - left to right the techs follow their limb (research.json "tree.limbs": rocketry, comms,
##     the core trunk, science, crew, exploration); a branch with no limb goes to "default_limb"
##   - inside a row each tech leans towards its limb's lane and towards the average place of its
##     prerequisites (fewer crossing branches), then the row is spread so no two cards are closer
##     than one lane (least squares under a minimum gap, the pool-adjacent-violators way)
##   - a tech may pin itself with "tree_pos": [lane, row] (row 0 = era 1; fractions allowed)
## Pure and headless: tests/test_research_tree.gd checks every tech is placed, no cards overlap
## and every prerequisite has its branch.
## compute() returns {
##   "rects": {id: Rect2}            the card of each tech, in tree (world) pixels
##   "size": Vector2                 the whole tree, roots and crown included
##   "eras": [{"era", "y", "h"}]     each era's band (top y and height)
##   "lanes": [{"limb", "x"}]        each limb's lane centre (for its sign at the crown)
##   "trunk_x", "ground_y"           the trunk's x and the ground line
##   "edges": [{"from", "to"}]       one per prerequisite (from = the prerequisite)
##   "roots": [ids]                  techs with no prerequisite (they grow from the trunk) }

const DEFAULTS := {"card": [150, 70], "lane_w": 168.0, "era_h": 124.0, "margin_left": 104.0, "margin_right": 16.0,
	"margin_top": 34.0, "ground_h": 44.0, "arch": 24.0, "default_limb": "science", "trunk_limb": "core"}


static func opts_from(db: Dictionary) -> Dictionary:
	var o := DEFAULTS.duplicate()
	var t: Dictionary = db.get("tree", {})
	for k: String in t:
		o[k] = t[k]
	return o


## The limbs left to right: [{"id", "branches": [...], ...}] (a fallback when the data has none).
static func limbs(o: Dictionary) -> Array:
	var l: Array = o.get("limbs", [])
	if l.is_empty():
		return [{"id": "core", "branches": []}]
	return l


## The lane (0 = leftmost) a branch leans to.
static func lane_of_branch(o: Dictionary, branch: String) -> int:
	var ls := limbs(o)
	var fallback := 0
	for i in ls.size():
		var l: Dictionary = ls[i]
		if branch in Array(l.get("branches", [])):
			return i
		if String(l.get("id", "")) == String(o.get("default_limb", "")):
			fallback = i
	return fallback


static func compute(techs: Array, o: Dictionary = DEFAULTS) -> Dictionary:
	var card := Vector2(float(o["card"][0]), float(o["card"][1]))
	var lane_w := float(o["lane_w"])
	var era_h := float(o["era_h"])
	var ml := float(o["margin_left"])
	var mt := float(o["margin_top"])
	var ls := limbs(o)
	var n_lanes := maxi(ls.size(), 1)
	var n_eras := 1
	var by_era := {}
	var by_id := {}
	for t: Dictionary in techs:
		var e := maxi(int(t.get("era", 1)), 1)
		n_eras = maxi(n_eras, e)
		if not by_era.has(e):
			by_era[e] = []
		(by_era[e] as Array).append(t)
		by_id[String(t["id"])] = t
	# x in lanes (0 = the leftmost lane's centre), row by row from the roots up
	var lane_x := {}
	var min_x := 0.0
	var max_x := float(n_lanes - 1)
	for e in range(1, n_eras + 1):
		var row: Array = by_era.get(e, [])
		var items: Array = []
		for i in row.size():
			var t: Dictionary = row[i]
			var id := String(t["id"])
			if t.has("tree_pos"):
				continue
			var pref := float(lane_of_branch(o, String(t.get("branch", ""))))
			var sum := 0.0
			var cnt := 0
			for p in t.get("prereq", []):
				if lane_x.has(String(p)):
					sum += float(lane_x[String(p)])
					cnt += 1
			if cnt > 0:
				pref = pref * 0.55 + (sum / cnt) * 0.45
			items.append({"id": id, "pref": pref, "order": i})
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(float(a["pref"]), float(b["pref"])):
				return float(a["pref"]) < float(b["pref"])
			return int(a["order"]) < int(b["order"]))
		var xs := spread(items.map(func(it: Dictionary) -> float: return float(it["pref"])), 1.0)
		# then inside the lanes (a row with more techs than lanes is centred on them)
		var extra := maxf(float(xs.size() - n_lanes), 0.0) * 0.5
		xs = bound(xs, 1.0, -extra, float(n_lanes - 1) + extra)
		for i in xs.size():
			lane_x[String(items[i]["id"])] = xs[i]
			min_x = minf(min_x, xs[i])
			max_x = maxf(max_x, xs[i])
	# pinned techs
	var row_of := {}
	for t: Dictionary in techs:
		var id := String(t["id"])
		row_of[id] = float(int(t.get("era", 1)) - 1)
		if t.has("tree_pos"):
			var tp: Array = t["tree_pos"]
			lane_x[id] = float(tp[0])
			row_of[id] = float(tp[1]) if tp.size() > 1 else row_of[id]
			min_x = minf(min_x, float(tp[0]))
			max_x = maxf(max_x, float(tp[0]))
	var trunk_lane := float(n_lanes - 1) * 0.5
	for i in ls.size():
		if String((ls[i] as Dictionary).get("id", "")) == String(o.get("trunk_limb", "core")):
			trunk_lane = float(i)   # the trunk rises up the core lane (its cards sit on the wood)
	# to pixels: lane centre -> card rect; rows from the crown down, each row an arch (the cards
	# further from the trunk sit a little higher, like branches reaching up and out)
	var x0 := ml - min_x * lane_w
	var reach := maxf(maxf(trunk_lane - min_x, max_x - trunk_lane), 1.0)
	var arch := float(o.get("arch", 0.0))
	var rects := {}
	for id: String in lane_x:
		var cx := x0 + (float(lane_x[id]) + 0.5) * lane_w
		var row := float(row_of[id])
		var cy := mt + (float(n_eras - 1) - row + 0.5) * era_h
		if not (by_id[id] as Dictionary).has("tree_pos"):
			cy -= arch * pow(minf(absf(float(lane_x[id]) - trunk_lane) / reach, 1.0), 1.3)
		rects[id] = Rect2(Vector2(roundf(cx - card.x * 0.5), roundf(cy - card.y * 0.5)), card)
	var width := x0 + (max_x + 1.0) * lane_w + float(o["margin_right"])
	var ground_y := mt + n_eras * era_h
	var eras: Array = []
	for e in range(1, n_eras + 1):
		eras.append({"era": e, "y": mt + float(n_eras - e) * era_h, "h": era_h})
	var lanes: Array = []
	for i in ls.size():
		lanes.append({"limb": String((ls[i] as Dictionary).get("id", "")), "x": x0 + (i + 0.5) * lane_w})
	var edges: Array = []
	var roots: Array = []
	for t: Dictionary in techs:
		var pre: Array = t.get("prereq", [])
		var any := false
		for p in pre:
			if by_id.has(String(p)):
				edges.append({"from": String(p), "to": String(t["id"])})
				any = true
		if not any:
			roots.append(String(t["id"]))
	return {"rects": rects, "size": Vector2(width, ground_y + float(o["ground_h"])), "eras": eras, "lanes": lanes,
		"trunk_x": x0 + (trunk_lane + 0.5) * lane_w, "ground_y": ground_y, "edges": edges, "roots": roots}


## Least-squares positions for sorted preferences `p` with at least `gap` between neighbours:
## x_i = q_i + i*gap where q is the isotonic (non-decreasing) fit of p_i - i*gap.
static func spread(p: Array, gap: float) -> Array[float]:
	var blocks: Array = []   # [sum, count]
	for i in p.size():
		blocks.append([float(p[i]) - i * gap, 1])
		while blocks.size() > 1:
			var b: Array = blocks[blocks.size() - 1]
			var a: Array = blocks[blocks.size() - 2]
			if float(a[0]) / int(a[1]) <= float(b[0]) / int(b[1]):
				break
			blocks.pop_back()
			blocks[blocks.size() - 1] = [float(a[0]) + float(b[0]), int(a[1]) + int(b[1])]
	var out: Array[float] = []
	for b: Array in blocks:
		var v := float(b[0]) / int(b[1])
		for k in int(b[1]):
			out.append(v + out.size() * gap)
	return out


## Sorted positions pushed inside [lo, hi] keeping `gap` between neighbours (a forward then a
## backward pass; it holds whenever (n - 1) * gap fits in hi - lo).
static func bound(xs: Array[float], gap: float, lo: float, hi: float) -> Array[float]:
	var out := xs.duplicate()
	var n := out.size()
	for i in n:
		out[i] = maxf(out[i], lo if i == 0 else out[i - 1] + gap)
	for i in range(n - 1, -1, -1):
		out[i] = minf(out[i], hi if i == n - 1 else out[i + 1] - gap)
	return out


## Every tech id the given tech needs, directly or not (its path of prerequisites).
static func ancestors(techs_by_id: Dictionary, id: String) -> Dictionary:
	var out := {}
	var stack: Array = [id]
	while not stack.is_empty():
		var cur := String(stack.pop_back())
		for p in (techs_by_id.get(cur, {}) as Dictionary).get("prereq", []):
			if not out.has(String(p)):
				out[String(p)] = true
				stack.append(String(p))
	return out
