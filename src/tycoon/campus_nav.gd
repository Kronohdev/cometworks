class_name CampusNav
extends RefCounted
## Where the campus Cometlings may walk: a grid of CELL metre cells over the plateau, in the
## campus' local space (x, z), built by src/tycoon/campus.gd from what stands on the campus
## and asked by src/tycoon/campus_walker.gd for paths.
##
##   footprints   every solid thing as a box on the ground: lamp poles and lot frames (meshes),
##                dressing props (each instanced scene as one box), scattered trees, bushes,
##                rocks and fences (CampusScatter nodes with `blocks_walkers`), plus the
##                buildings, read from their walk masks (assets/campus/<kind>/<kind>_walk.png,
##                written by tools/build_campus_buildings.py: walls and furniture block, the
##                doorways and the floor between the furniture are free).
##   cells        blocked when a footprint touches them; "near" within `near_radius` of one
##                (paths keep away from things when they can); "road" on the road meshes.
##   paths        A* (AStarGrid2D) with a cost per cell (roads cheap, lawns dearer, near things
##                dearer still), then straightened where a straight line crosses no blocked
##                cell and no cell dearer than the stretch it replaces.
## A walker's centre never enters a blocked cell (the walker checks every step), so it never
## enters a footprint either.

const CELL := 0.25
const F_SOLID := 1
const F_NEAR := 2
const F_ROAD := 4
## a cell is blocked when a footprint comes within half its diagonal of the cell centre
const HALF_DIAG := CELL * 0.7072

var origin := Vector2.ZERO
var nx := 0
var nz := 0
var road_cost := 1.0
var grass_cost := 1.6
var near_cost := 4.0
var near_radius := 0.75
## heights (m) a footprint must reach into to block: lower things are stepped over, higher
## ones (lamp heads, canopies' tops) are walked under
var band := Vector2(0.25, 2.0)

## [{"c": Vector2 centre, "u": Vector2 unit x axis, "h": Vector2 half extents, "name"}]
var boxes: Array[Dictionary] = []
## building walk masks placed on the campus: [{"inv": Transform2D campus -> lot, "data":
## PackedByteArray, "w": int, "row0": int, "rows": int, "hx", "hz", "scaffold_row0": int}]
var masks: Array[Dictionary] = []

var _flags := PackedByteArray()
var _astar := AStarGrid2D.new()
## cell paths already found (start cell, end cell) -> ids; walkers mostly go spot to spot
var _paths := {}
## search statistics (tests and tuning): A* searches, their total and longest time (us), how
## many found nothing
var stats := {"searches": 0, "us": 0, "max_us": 0, "failed": 0}
## boxes by BUCKET metre square (footprint_at)
var _buckets := {}
const BUCKET := 4.0
static var _mask_images := {}


# ------------------------------------------------------------ building
func setup(rect: Rect2) -> void:
	origin = (rect.position / CELL).floor() * CELL
	var end := (rect.end / CELL).ceil() * CELL
	nx = int(round((end.x - origin.x) / CELL))
	nz = int(round((end.y - origin.y) / CELL))
	_flags = PackedByteArray()
	_flags.resize(nx * nz)
	boxes.clear()
	masks.clear()
	_buckets.clear()
	_paths.clear()


## A footprint box: `xf` places a local box (centre `c`, half extents `h`, in x / z) on the campus.
func add_box(xf: Transform3D, aabb: AABB, label := "") -> void:
	var c3 := xf * aabb.get_center()
	# vertical reach: the box must reach into the band
	var lo := INF
	var hi := -INF
	for i in 8:
		var y := (xf * aabb.get_endpoint(i)).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if hi < band.x or lo > band.y:
		return
	var ax := Vector2(xf.basis.x.x, xf.basis.x.z)
	var az := Vector2(xf.basis.z.x, xf.basis.z.z)
	var sx := ax.length()
	var sz := az.length()
	if sx < 1e-5 or sz < 1e-5:
		return
	var b := {"c": Vector2(c3.x, c3.z), "u": ax / sx,
		"h": Vector2(aabb.size.x * 0.5 * sx, aabb.size.z * 0.5 * sz), "name": label}
	boxes.append(b)
	var c: Vector2 = b["c"]
	var r := (b["h"] as Vector2).length()
	for bk in range(floori((c.y - r) / BUCKET), floori((c.y + r) / BUCKET) + 1):
		for bi in range(floori((c.x - r) / BUCKET), floori((c.x + r) / BUCKET) + 1):
			var bkey := Vector2i(bi, bk)
			if not _buckets.has(bkey):
				_buckets[bkey] = []
			_buckets[bkey].append(boxes.size() - 1)
	_raster_box(b)


## A building's walk mask: `kind` picks assets/campus/<kind>/<kind>_walk.png, `xf` is the lot on
## the campus; `era` / `level` pick the layer (level 0 = nothing built), `scaffold` adds the
## construction site.
func add_mask(kind: String, xf: Transform3D, era: int, level: int, scaffold: bool) -> void:
	var img := mask_image(kind)
	if img == null or (level <= 0 and not scaffold):
		return
	var data := img.get_data()
	var w := img.get_width()
	var rows := img.get_height() / 16
	var hx := w * CELL * 0.5
	var hz := rows * CELL * 0.5
	var m := {"kind": kind, "data": data, "w": w, "rows": rows, "hx": hx, "hz": hz,
		"inv": _flat(xf).affine_inverse(), "layers": []}
	if level > 0:
		m["layers"].append(((clampi(era, 1, 5) - 1) * 3 + clampi(level, 1, 3) - 1) * rows)
	if scaffold:
		m["layers"].append(15 * rows)
	masks.append(m)
	var flat := _flat(xf)
	for row0: int in m["layers"]:
		for k in rows:
			var base := (row0 + k) * w
			var lz := -hz + (k + 0.5) * CELL
			for i in w:
				var v := data[base + i]
				if v == 0:
					continue
				var p := flat * Vector2(-hx + (i + 0.5) * CELL, lz)
				var ci := floori((p.x - origin.x) / CELL)
				var ck := floori((p.y - origin.y) / CELL)
				if ci < 0 or ck < 0 or ci >= nx or ck >= nz:
					continue
				_flags[ck * nx + ci] |= F_SOLID if v >= 200 else F_NEAR


static func mask_image(kind: String) -> Image:
	if not _mask_images.has(kind):
		var path := "res://assets/campus/%s/%s_walk.png" % [kind, kind]
		var img: Image = null
		if ResourceLoader.exists(path):
			img = load(path) as Image
		if img:
			img = img.duplicate() as Image
			if img.get_format() != Image.FORMAT_L8:
				img.convert(Image.FORMAT_L8)
		_mask_images[kind] = img
	return _mask_images[kind]


## Road cells (walked on gladly): a road mesh's box on the campus.
func add_road(xf: Transform3D, aabb: AABB) -> void:
	var r := _cell_rect(xf, aabb, 0.0)
	for k in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var p := origin + Vector2(i + 0.5, k + 0.5) * CELL
			if _box_dist(_xf_box(xf, aabb), p) <= 0.0:
				_flags[k * nx + i] |= F_ROAD


## Blocks every cell whose centre lies outside `poly` (campus x, z): the walkers keep to the
## island's flat top (the walk_outline metadata of Terrain/Plateau, see src/tycoon/campus.gd).
func block_outside(poly: PackedVector2Array) -> void:
	if poly.size() < 3:
		return
	for k in nz:
		var z := origin.y + (k + 0.5) * CELL
		var xs: Array[float] = []
		for e in poly.size():
			var a := poly[e]
			var b := poly[(e + 1) % poly.size()]
			if (a.y <= z and b.y > z) or (b.y <= z and a.y > z):
				xs.append(a.x + (z - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var j := 0
		var inside := false
		for i in nx:
			var x := origin.x + (i + 0.5) * CELL
			while j < xs.size() and xs[j] <= x:
				inside = not inside
				j += 1
			if not inside:
				_flags[k * nx + i] |= F_SOLID


## Makes the A* grid from the cells. Call after adding everything.
func finish() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, nx, nz)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	# the heuristic counts one per metre of lawn: costs are scaled so the lawn is 1 (the search
	# then leans on the heuristic; paths may be a little longer than the cheapest on the
	# roads, and it explores far fewer cells)
	var k := 1.0 / maxf(grass_cost, 0.01)
	_astar.fill_weight_scale_region(Rect2i(0, 0, nx, nz), grass_cost * k)
	for idx in _flags.size():
		var f := _flags[idx]
		if f == 0:
			continue
		var id := Vector2i(idx % nx, idx / nx)
		if f & F_SOLID:
			_astar.set_point_solid(id, true)
		elif f & F_NEAR:
			_astar.set_point_weight_scale(id, near_cost * k)
		elif f & F_ROAD:
			_astar.set_point_weight_scale(id, road_cost * k)


## Debug picture of the grid (dev menu, Campus.dev_show_nav): one pixel per cell, row 0 at the
## lowest z; blocked red, near a footprint orange, road blue, lawn clear.
func debug_image() -> Image:
	var img := Image.create(maxi(nx, 1), maxi(nz, 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for idx in _flags.size():
		var f := _flags[idx]
		if f == 0:
			continue
		var c := Color(0.95, 0.2, 0.25, 0.7) if f & F_SOLID else (Color(1.0, 0.6, 0.15, 0.45) if f & F_NEAR
			else Color(0.3, 0.55, 1.0, 0.35))
		img.set_pixel(idx % nx, idx / nx, c)
	return img


# ------------------------------------------------------------ queries
## True when a walker's centre may stand at `p` (campus x, z): inside the grid, not blocked.
func is_free(p: Vector2) -> bool:
	var c := cell_of(p)
	return _in(c) and (_flags[c.y * nx + c.x] & F_SOLID) == 0


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / CELL), floori((p.y - origin.y) / CELL))


func cell_centre(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


## True when `p` lies inside a footprint itself (not the grid's rounding): a prop box or a
## blocked cell of a building's walk mask. Used by tests.
func footprint_at(p: Vector2) -> String:
	for bi: int in _buckets.get(Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET)), []):
		if _box_dist(boxes[bi], p) < 0.0:
			return String(boxes[bi]["name"])
	for m in masks:
		var lp: Vector2 = (m["inv"] as Transform2D) * p
		var i := floori((lp.x + float(m["hx"])) / CELL)
		var k := floori((lp.y + float(m["hz"])) / CELL)
		if i < 0 or k < 0 or i >= int(m["w"]) or k >= int(m["rows"]):
			continue
		for row0: int in m["layers"]:
			if (m["data"] as PackedByteArray)[(row0 + k) * int(m["w"]) + i] >= 200:
				return String(m["kind"])
	return ""


## The nearest free cell centre to `p` (itself when free), at least `keep` metres from every
## point of `others` when possible; `p` when nothing is free within `max_r`.
func free_point_near(p: Vector2, others: Array = [], keep := 0.0, max_r := 8.0) -> Vector2:
	var c := cell_of(p)
	if is_free(p) and _clear_of(p, others, keep):
		return p
	var rmax := int(ceil(max_r / CELL))
	var best := p
	var best_d := INF
	for r in range(1, rmax + 1):
		for dk in range(-r, r + 1):
			for di in range(-r, r + 1):
				if absi(di) != r and absi(dk) != r:
					continue
				var cc := c + Vector2i(di, dk)
				if not _in(cc) or (_flags[cc.y * nx + cc.x] & (F_SOLID | F_NEAR)) != 0:
					continue
				var q := cell_centre(cc)
				if not _clear_of(q, others, keep):
					continue
				var d := q.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = q
		if best_d < INF:
			return best
	# nothing roomy: accept near cells
	for r in range(1, rmax + 1):
		for dk in range(-r, r + 1):
			for di in range(-r, r + 1):
				if absi(di) != r and absi(dk) != r:
					continue
				var cc := c + Vector2i(di, dk)
				if _in(cc) and (_flags[cc.y * nx + cc.x] & F_SOLID) == 0 and _clear_of(cell_centre(cc), others, keep):
					return cell_centre(cc)
	return p


## A walking path from `from` to `to` (campus x, z), straightened; empty when there is none.
## `avoid`: points (other Cometlings) treated as blocked within `avoid_radius` for this path.
func find_path(from: Vector2, to: Vector2, avoid: Array = [], avoid_radius := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if nx == 0:
		return out
	var temp: Array[Vector2i] = []
	if not avoid.is_empty() and avoid_radius > 0.0:
		var rr := int(ceil(avoid_radius / CELL))
		for q: Vector2 in avoid:
			var qc := cell_of(q)
			for dk in range(-rr, rr + 1):
				for di in range(-rr, rr + 1):
					var cc := qc + Vector2i(di, dk)
					if not _in(cc) or _astar.is_point_solid(cc):
						continue
					if cell_centre(cc).distance_to(q) <= avoid_radius:
						_astar.set_point_solid(cc, true)
						temp.append(cc)
	var a := cell_of(from)
	if not _in(a) or _astar.is_point_solid(a):
		a = cell_of(_nearest_open(from))
	var b := cell_of(to)
	var end := to
	if not _in(b) or _astar.is_point_solid(b):
		var q := _nearest_open(to)
		b = cell_of(q)
		end = q
	var ids: Array[Vector2i] = []
	var key := Vector4i(a.x, a.y, b.x, b.y)
	if temp.is_empty() and _paths.has(key):
		ids = _paths[key]
	elif _in(a) and _in(b) and not _astar.is_point_solid(a) and not _astar.is_point_solid(b):
		var t0 := Time.get_ticks_usec()
		ids = _astar.get_id_path(a, b)
		var us := Time.get_ticks_usec() - t0
		stats["searches"] += 1
		stats["us"] += us
		stats["max_us"] = maxi(stats["max_us"], us)
		if ids.is_empty():
			stats["failed"] += 1
		if temp.is_empty():
			if _paths.size() > 4000:
				_paths.clear()
			_paths[key] = ids
	for cc in temp:
		_astar.set_point_solid(cc, false)
	if ids.is_empty():
		return out
	# turn points of the cell path
	var pts: Array[Vector2] = [from]
	var idx: Array[int] = [0]
	for i in range(1, ids.size() - 1):
		if ids[i] - ids[i - 1] != ids[i + 1] - ids[i]:
			pts.append(cell_centre(ids[i]))
			idx.append(i)
	pts.append(cell_centre(ids[ids.size() - 1]))
	idx.append(ids.size() - 1)
	if end != pts[pts.size() - 1]:
		pts.append(end)
		idx.append(ids.size() - 1)
	# straighten: from each point, jump to the farthest later point in plain sight that is no
	# dearer than the cells in between
	var i := 0
	out.append(pts[0])
	while i < pts.size() - 1:
		var best := i + 1
		for j in range(mini(pts.size() - 1, i + 14), i, -1):
			var worst := 0.0
			for q in [pts[i], pts[j]]:
				var cq := _cost(cell_of(q))
				worst = maxf(worst, cq if cq < INF else near_cost)
			for s in range(idx[i], idx[j] + 1):
				worst = maxf(worst, _cost(ids[s]))
			if _line_ok(pts[i], pts[j], worst):
				best = j
				break
		out.append(pts[best])
		i = best
	return out


## True when the straight line a -> b crosses no blocked cell and no cell dearer than max_cost.
func line_ok(a: Vector2, b: Vector2, max_cost := INF) -> bool:
	return _line_ok(a, b, max_cost)


# ------------------------------------------------------------ internals
func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < nx and c.y < nz


func _cost(c: Vector2i) -> float:
	if not _in(c):
		return INF
	var f := _flags[c.y * nx + c.x]
	if f & F_SOLID:
		return INF
	if f & F_NEAR:
		return near_cost
	if f & F_ROAD:
		return road_cost
	return grass_cost


func _line_ok(a: Vector2, b: Vector2, max_cost: float) -> bool:
	var ga := (a - origin) / CELL
	var gb := (b - origin) / CELL
	var i := floori(ga.x)
	var k := floori(ga.y)
	var ie := floori(gb.x)
	var ke := floori(gb.y)
	var d := gb - ga
	var si := 1 if d.x > 0.0 else -1
	var sk := 1 if d.y > 0.0 else -1
	var tdx := absf(1.0 / d.x) if absf(d.x) > 1e-9 else INF
	var tdz := absf(1.0 / d.y) if absf(d.y) > 1e-9 else INF
	var tmx := (float(i + (1 if si > 0 else 0)) - ga.x) / d.x if absf(d.x) > 1e-9 else INF
	var tmz := (float(k + (1 if sk > 0 else 0)) - ga.y) / d.y if absf(d.y) > 1e-9 else INF
	var guard := absi(ie - i) + absi(ke - k) + 4
	while true:
		if _cost(Vector2i(i, k)) > max_cost + 1e-4:
			return false
		if (i == ie and k == ke) or guard <= 0:
			break
		guard -= 1
		if absf(tmx - tmz) < 1e-9:
			# through a corner: both side cells count (supercover)
			if _cost(Vector2i(i + si, k)) > max_cost + 1e-4 or _cost(Vector2i(i, k + sk)) > max_cost + 1e-4:
				return false
			tmx += tdx
			tmz += tdz
			i += si
			k += sk
		elif tmx < tmz:
			tmx += tdx
			i += si
		else:
			tmz += tdz
			k += sk
	return true


func _nearest_open(p: Vector2) -> Vector2:
	var c := cell_of(p)
	for r in range(0, 24):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dk in range(-r, r + 1):
			for di in range(-r, r + 1):
				if absi(di) != r and absi(dk) != r:
					continue
				var cc := c + Vector2i(di, dk)
				if _in(cc) and not _astar.is_point_solid(cc):
					var d := cell_centre(cc).distance_squared_to(p)
					if d < best_d:
						best_d = d
						best = cc
		if best.x >= 0:
			return cell_centre(best)
	return p


func _clear_of(p: Vector2, others: Array, keep: float) -> bool:
	for q: Vector2 in others:
		if p.distance_to(q) < keep:
			return false
	return true


func _flat(xf: Transform3D) -> Transform2D:
	return Transform2D(Vector2(xf.basis.x.x, xf.basis.x.z), Vector2(xf.basis.z.x, xf.basis.z.z),
		Vector2(xf.origin.x, xf.origin.z))


func _xf_box(xf: Transform3D, aabb: AABB) -> Dictionary:
	var c3 := xf * aabb.get_center()
	var ax := Vector2(xf.basis.x.x, xf.basis.x.z)
	var az := Vector2(xf.basis.z.x, xf.basis.z.z)
	return {"c": Vector2(c3.x, c3.z), "u": ax.normalized(),
		"h": Vector2(aabb.size.x * 0.5 * ax.length(), aabb.size.z * 0.5 * az.length())}


## Signed distance from p to a box (negative inside).
func _box_dist(b: Dictionary, p: Vector2) -> float:
	var u: Vector2 = b["u"]
	var d: Vector2 = p - (b["c"] as Vector2)
	var l := Vector2(d.dot(u), d.dot(Vector2(-u.y, u.x)))
	var q := l.abs() - (b["h"] as Vector2)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


func _cell_rect(xf: Transform3D, aabb: AABB, grow: float) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := xf * aabb.get_endpoint(i)
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	lo -= Vector2(grow, grow)
	hi += Vector2(grow, grow)
	var a := Vector2i(maxi(0, floori((lo.x - origin.x) / CELL)), maxi(0, floori((lo.y - origin.y) / CELL)))
	var b := Vector2i(mini(nx, floori((hi.x - origin.x) / CELL) + 1), mini(nz, floori((hi.y - origin.y) / CELL) + 1))
	return Rect2i(a, (b - a).max(Vector2i.ZERO))


func _raster_box(b: Dictionary) -> void:
	var c: Vector2 = b["c"]
	var h: Vector2 = b["h"]
	var reach := h.length() + near_radius + HALF_DIAG
	var a := Vector2i(maxi(0, floori((c.x - reach - origin.x) / CELL)), maxi(0, floori((c.y - reach - origin.y) / CELL)))
	var e := Vector2i(mini(nx, floori((c.x + reach - origin.x) / CELL) + 1), mini(nz, floori((c.y + reach - origin.y) / CELL) + 1))
	for k in range(a.y, e.y):
		for i in range(a.x, e.x):
			var d := _box_dist(b, origin + Vector2(i + 0.5, k + 0.5) * CELL)
			if d <= HALF_DIAG:
				_flags[k * nx + i] |= F_SOLID
			elif d <= near_radius + HALF_DIAG:
				_flags[k * nx + i] |= F_NEAR
