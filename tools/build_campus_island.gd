extends SceneTree
## Authoring helper for the campus island (the "Terrain" of scenes/tycoon/campus.tscn): its
## shape, the sea's shore map, the distant coast and the little props around it.
##
## The shape is drawn here as data (PLATEAU, COAST, ISLETS, STACKS, STAIRS below): the flat top
## where the campus stands (y = 0), the coastline, islets, sea stacks and the stairs down to the
## beaches. Between the top and the coast the ground steps down in terraces to a beach where the
## coast is far, and drops as a rocky cliff where it is close (the north and west sides). Cells
## are 1 m voxels; heights snap to 0.25 m.
##
## Writes (re-running replaces these files; nothing is generated at runtime):
##   assets/campus/island/*.res           terrain meshes (plateau, terraces, sand, rock, steps),
##                                         the distant coast and the neighbour island, the shore
##                                         distance map of the sea, the prop meshes (lighthouse,
##                                         boats, buoy, pier, beach umbrella, clouds)
##   assets/campus/island/island_mask.tres where the shore plants keep off (stairs, pier, props)
##   assets/campus/island/fence_mask.tres  the openings of the perimeter fences (stairs, paths)
##   assets/campus/nature/campus_mask.tres `inside` = the island top (the campus plants stay on
##                                         it), plus the stairs and footpaths to keep clear
##   scenes/tycoon/campus_nature.tscn      every campus scatter rolled again inside the top (same
##                                         seeds, so a re-run gives the same plants)
##   scenes/tycoon/campus_dressing.tscn    the perimeter fences follow the edge of the top
## and, only when it does not exist yet or with `-- --scene` (which overwrites hand edits), the
## editor scenes:
##   scenes/tycoon/campus_island.tscn      sea, terrain meshes, far coast, shore plants
##                                         (CampusScatter), pier, boats, buoys, lighthouse,
##                                         clouds, gulls: placed here once, then moved by hand
##   scenes/tycoon/campus_lighthouse.tscn / campus_boat.tscn / campus_fishing_boat.tscn /
##   campus_buoy.tscn                      the props, with their bobbing / beam animations
## The footpaths to the stairs (Roads/PathSouth, Roads/PathNE) and the story signs
## (scenes/tycoon/campus_signs.tscn) are edited by hand; move them along if the shape changes.
## Run (not headless: MultiMesh buffers are read back from a real renderer when saving):
##   godot --path . --script res://tools/build_campus_island.gd [-- --scene]

const DIR := "res://assets/campus/island/"
const SCENE := "res://scenes/tycoon/campus_island.tscn"
const NATURE := "res://scenes/tycoon/campus_nature.tscn"
const DRESSING := "res://scenes/tycoon/campus_dressing.tscn"
const MESHES := "res://assets/campus/nature/meshes/"
const FOLIAGE := "res://assets/campus/nature/foliage.tres"
const GRASS := "res://assets/campus/nature/grass.tres"
const ROCK_MAT := "res://assets/campus/nature/rock.tres"

const SEA_Y := -9.0
const FLOOR_Y := -9.8
## the main grid: 1 m cells
const GX0 := -110
const GZ0 := -90
const GNX := 250
const GNZ := 190
## materials of the cells
enum { WATER, TOP, TERRACE, SAND, ROCK, STEPS }

## The flat island top (y = 0) around the lots, roads and props, clockwise from the north-west
## (world x, z). Chaikin-smoothed. Every lot keeps 3 m or more inside it.
const PLATEAU := [
	Vector2(-60, -26), Vector2(-40, -29), Vector2(-22, -27), Vector2(-14, -31), Vector2(-13, -44),
	Vector2(-6, -51), Vector2(5, -50), Vector2(11, -43), Vector2(12, -31), Vector2(24, -28),
	Vector2(40, -27), Vector2(54, -25), Vector2(70, -14), Vector2(85, -5), Vector2(89, 10),
	Vector2(87, 31), Vector2(78, 38), Vector2(60, 37), Vector2(40, 38), Vector2(24, 36),
	Vector2(12, 38), Vector2(6, 40), Vector2(-6, 40), Vector2(-12, 36), Vector2(-24, 31),
	Vector2(-36, 31), Vector2(-52, 30), Vector2(-61, 25), Vector2(-65, 10), Vector2(-65, -8),
	Vector2(-64, -20),
]
## The coastline: close to the top on the north and west (cliffs), far on the south and east
## (terraces down to the beaches), with a cove in the north-east and one in the south-west.
const COAST := [
	Vector2(-65, -30), Vector2(-42, -33), Vector2(-25, -31), Vector2(-18, -35), Vector2(-17, -48),
	Vector2(-8, -55), Vector2(6, -54), Vector2(15, -47), Vector2(16, -35), Vector2(26, -32),
	Vector2(42, -31), Vector2(52, -33), Vector2(62, -38), Vector2(74, -31), Vector2(87, -16),
	Vector2(93, -6), Vector2(95, 10), Vector2(93, 30), Vector2(87, 41), Vector2(74, 49),
	Vector2(60, 51), Vector2(44, 57), Vector2(28, 65), Vector2(12, 67), Vector2(-4, 64),
	Vector2(-14, 55), Vector2(-21, 45), Vector2(-30, 41), Vector2(-39, 47), Vector2(-51, 46),
	Vector2(-63, 36), Vector2(-69, 24), Vector2(-70, 8), Vector2(-69, -10), Vector2(-68, -24),
]
## islets: centre, radius, top height, look ("grass" top in a rock ring, "sand" bar)
const ISLETS := [
	{"c": Vector2(114, -46), "r": 11.0, "top": -3.0, "kind": "grass"},   # the lighthouse
	{"c": Vector2(-58, 80), "r": 8.0, "top": -8.0, "kind": "sand"},
	{"c": Vector2(-95, -36), "r": 7.0, "top": -5.0, "kind": "grass"},
	{"c": Vector2(118, 48), "r": 6.0, "top": -6.5, "kind": "grass"},
]
## sea stacks: centre, radius, top height
const STACKS := [
	[Vector2(-34, -44), 2.6, 1.0], [Vector2(-50, -42), 3.2, -2.0], [Vector2(-26, -53), 2.0, -4.0],
	[Vector2(29, -43), 2.2, -3.0], [Vector2(-79, 4), 2.8, -1.0], [Vector2(102, 26), 2.5, -2.0],
	[Vector2(97, -22), 2.0, -4.5], [Vector2(-80, -18), 1.8, -5.0],
]
## stairs from the top down to a beach, along z: the strip's x range, the z range searched
## from the top outward, and the direction (+1 south, -1 north)
const STAIRS := [
	{"x": Vector2(-1.5, 1.5), "z": Vector2(30, 80), "dir": 1},
	{"x": Vector2(61.5, 64.5), "z": Vector2(-14, -45), "dir": -1},
]
## the footpaths from the roads to the stairs (x, z, width, depth): road meshes placed by hand in
## scenes/tycoon/campus.tscn (Roads/PathSouth, Roads/PathNE); plants and fences keep off them
const FOOTPATHS := [Rect2(-1.5, 34, 3, 5), Rect2(61, -18.5, 4, 18)]
## the pier on the south beach (deck x, z start and end, deck height)
const PIER := {"x": 24.0, "z0": 58.0, "z1": 78.0, "y": -8.2}

var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var plateau_poly := PackedVector2Array()
var coast_poly := PackedVector2Array()
var h := PackedFloat32Array()
var m := PackedByteArray()
var stair_tops: Array[Rect2] = []
var _props_mat: ShaderMaterial


func _initialize() -> void:
	var scene_too := "--scene" in OS.get_cmdline_user_args() or not FileAccess.file_exists(SCENE)
	DirAccess.make_dir_recursive_absolute(DIR)
	noise.seed = 2026
	noise.frequency = 0.06
	noise2.seed = 77
	noise2.frequency = 0.15
	plateau_poly = _chaikin(PackedVector2Array(PLATEAU), 3)
	coast_poly = _jitter(_chaikin(PackedVector2Array(COAST), 3), 1.8)
	_build_heights()
	_props_mat = _toon_vc()
	ResourceSaver.save(_props_mat, DIR + "props_toon.tres")
	_props_mat = load(DIR + "props_toon.tres")
	var names := {TOP: "plateau", TERRACE: "terraces", SAND: "sand", ROCK: "rock", STEPS: "steps"}
	for id: int in names:
		var mesh := _grid_mesh(h, m, GNX, GNZ, 1.0, Vector2(GX0, GZ0), id, FLOOR_Y)
		ResourceSaver.save(mesh, DIR + names[id] + ".res", ResourceSaver.FLAG_COMPRESS)
		print("%s: %d vertices" % [names[id], mesh.surface_get_array_len(0) if mesh.get_surface_count() > 0 else 0])
	ResourceSaver.save(_shore_map(), DIR + "shore_map.res", ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(_far_coast(), DIR + "far_coast.res", ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(_neighbour(), DIR + "neighbour_island.res", ResourceSaver.FLAG_COMPRESS)
	_prop_meshes()
	var imask := CampusScatterMask.new()
	var av: Array[Rect2] = []
	for r in stair_tops:
		av.append(r.grow(1.5))
	av.append(Rect2(PIER["x"] - 3.0, PIER["z0"] - 3.0, 6.0, PIER["z1"] - PIER["z0"] + 6.0))
	# the beach umbrellas, the lighthouse and its keeper's house, the signs off the island top
	for c: Vector2 in [Vector2(8, 58.5), Vector2(-9, 54), Vector2(6, 59), Vector2(110.5, -49.5)]:
		av.append(Rect2(c - Vector2(2.2, 2.2), Vector2(4.4, 4.4)))
	av.append(Rect2(109, -51, 13, 9))
	imask.avoid = av
	ResourceSaver.save(imask, DIR + "island_mask.tres")
	_update_campus_mask()
	if scene_too:
		await _build_props_scenes()
		await _build_island_scene()
	await _update_nature()
	await _update_dressing()
	print("CAMPUS ISLAND BUILT")
	quit()


# ------------------------------------------------------------------ shape
func _chaikin(p: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var cur := p
	for it in iterations:
		var nxt := PackedVector2Array()
		for i in cur.size():
			var a := cur[i]
			var b := cur[(i + 1) % cur.size()]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		cur = nxt
	return cur


## Pushes every point along the outline's normal by up to `amount` m of smooth noise.
func _jitter(p: PackedVector2Array, amount: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in p.size():
		var a := p[(i - 1 + p.size()) % p.size()]
		var b := p[(i + 1) % p.size()]
		var t := (b - a).normalized()
		var n := Vector2(t.y, -t.x)
		out.append(p[i] + n * noise.get_noise_2d(p[i].x * 1.7, p[i].y * 1.7) * amount)
	return out


func _cell_centre(i: int, k: int) -> Vector2:
	return Vector2(GX0 + i + 0.5, GZ0 + k + 0.5)


## Inside flags of a polygon over the grid (scanline).
func _raster(poly: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(GNX * GNZ)
	for k in GNZ:
		var z := GZ0 + k + 0.5
		var xs: Array[float] = []
		for e in poly.size():
			var a := poly[e]
			var b := poly[(e + 1) % poly.size()]
			if (a.y <= z and b.y > z) or (b.y <= z and a.y > z):
				xs.append(a.x + (z - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for j in range(0, xs.size() - 1, 2):
			var i0 := maxi(0, ceili(xs[j] - GX0 - 0.5))
			var i1 := mini(GNX - 1, floori(xs[j + 1] - GX0 - 0.5))
			for i in range(i0, i1 + 1):
				out[k * GNX + i] = 1
	return out


## Distance (in cells) of every cell to the nearest cell with src = 1 (two-pass chamfer).
static func _chamfer(src: PackedByteArray, nx: int, nz: int) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(nx * nz)
	var big := 1e9
	for i in d.size():
		d[i] = 0.0 if src[i] == 1 else big
	var s2 := 1.41421
	for k in nz:
		for i in nx:
			var idx := k * nx + i
			var v := d[idx]
			if v == 0.0:
				continue
			if i > 0:
				v = minf(v, d[idx - 1] + 1.0)
			if k > 0:
				v = minf(v, d[idx - nx] + 1.0)
				if i > 0:
					v = minf(v, d[idx - nx - 1] + s2)
				if i < nx - 1:
					v = minf(v, d[idx - nx + 1] + s2)
			d[idx] = v
	for k in range(nz - 1, -1, -1):
		for i in range(nx - 1, -1, -1):
			var idx := k * nx + i
			var v := d[idx]
			if v == 0.0:
				continue
			if i < nx - 1:
				v = minf(v, d[idx + 1] + 1.0)
			if k < nz - 1:
				v = minf(v, d[idx + nx] + 1.0)
				if i < nx - 1:
					v = minf(v, d[idx + nx + 1] + s2)
				if i > 0:
					v = minf(v, d[idx + nx - 1] + s2)
			d[idx] = v
	return d


func _build_heights() -> void:
	var in_p := _raster(plateau_poly)
	var in_c := _raster(coast_poly)
	var out_c := PackedByteArray()
	out_c.resize(in_c.size())
	for i in in_c.size():
		out_c[i] = 1 - in_c[i]
	var d_p := _chamfer(in_p, GNX, GNZ)         # metres outside the top
	var d_c := _chamfer(out_c, GNX, GNZ)        # metres inside the coast
	var d_out := _chamfer(in_c, GNX, GNZ)       # metres out at sea
	h.resize(GNX * GNZ)
	m.resize(GNX * GNZ)
	for k in GNZ:
		for i in GNX:
			var idx := k * GNX + i
			var p := _cell_centre(i, k)
			h[idx] = NAN
			m[idx] = WATER
			if in_p[idx] == 1:
				h[idx] = 0.0
				m[idx] = TOP
				continue
			if in_c[idx] == 0:
				# rocks just off the beaches
				if d_out[idx] > 0.5 and d_out[idx] < 5.0 and noise2.get_noise_2d(p.x, p.y) > 0.55:
					h[idx] = -8.25 if noise.get_noise_2d(p.x * 3.0, p.y * 3.0) < 0.2 else -7.5
					m[idx] = ROCK
				continue
			var dp := d_p[idx]
			var dc := d_c[idx]
			var w := dp + dc
			if w < 8.5:
				# cliff: a sheer drop to a rocky ledge at the water, boulders here and there
				if dp < 1.2:
					h[idx] = 0.0
					m[idx] = TOP
				else:
					var b := noise2.get_noise_2d(p.x * 1.3, p.y * 1.3)
					h[idx] = -8.5 if b < 0.35 else (-7.5 if b < 0.6 else -6.5)
					m[idx] = ROCK
				continue
			var beach := clampf(w * 0.3, 4.0, 12.0)
			if dc <= beach:
				h[idx] = -8.7 if dc < beach * 0.6 else -8.45
				m[idx] = SAND
				continue
			var span := w - beach
			var s := clampf(dp / span + noise.get_noise_2d(p.x, p.y) * 0.1, 0.0, 1.0)
			var steps := clampi(int(span / 4.5), 2, 6)
			var lvl := clampi(ceili(s * steps), 1, steps)
			h[idx] = minf(-snappedf(float(lvl) / steps * 7.5, 0.5), -1.0)
			m[idx] = TERRACE
	_add_islets()
	_add_stairs()


func _add_islets() -> void:
	for k in GNZ:
		for i in GNX:
			var idx := k * GNX + i
			if m[idx] != WATER and m[idx] != ROCK:
				continue
			var p := _cell_centre(i, k)
			for il: Dictionary in ISLETS:
				var c: Vector2 = il["c"]
				var a := (p - c).angle()
				var r := float(il["r"]) * (1.0 + 0.22 * noise.get_noise_2d(cos(a) * 9.0 + c.x, sin(a) * 9.0 + c.y))
				var t := p.distance_to(c) / r
				if t >= 1.0:
					continue
				if String(il["kind"]) == "sand":
					h[idx] = float(il["top"]) if t < 0.5 else (-8.5 if t < 0.8 else -8.75)
					m[idx] = SAND
				elif t < 0.6:
					h[idx] = float(il["top"])
					m[idx] = TERRACE
				else:
					h[idx] = lerpf(float(il["top"]) - 1.0, -8.5, smoothstep(0.6, 1.0, t))
					h[idx] = snappedf(h[idx], 1.0)
					m[idx] = ROCK
			for st: Array in STACKS:
				var c2: Vector2 = st[0]
				var d := p.distance_to(c2) / float(st[1])
				d *= 1.0 + 0.15 * noise2.get_noise_2d(p.x * 2.0, p.y * 2.0)
				if d < 1.0:
					h[idx] = float(st[2]) if d < 0.7 else float(st[2]) - 2.0
					m[idx] = ROCK


## Wooden stairs: down the terraces from the island top to the first sand, in even steps.
func _add_stairs() -> void:
	stair_tops.clear()
	for s: Dictionary in STAIRS:
		var xr: Vector2 = s["x"]
		var zr: Vector2 = s["z"]
		var dir := int(s["dir"])
		var top_z := 0.0
		for i in GNX:
			var x := GX0 + i + 0.5
			if x < xr.x or x > xr.y:
				continue
			var k := int(zr.x - GZ0)
			var k_end := int(zr.y - GZ0)
			# from the top outward: the first cell off the top, then the run until the sand
			while k != k_end and m[k * GNX + i] == TOP:
				k += dir
			top_z = GZ0 + k + 0.5 - dir * 0.5
			var run: Array[int] = []
			while k != k_end and m[k * GNX + i] == TERRACE:
				run.append(k)
				k += dir
			var sand_y := h[k * GNX + i] if m[k * GNX + i] == SAND else -8.5
			for t in run.size():
				var y := snappedf(sand_y * float(t + 1) / float(run.size() + 1), 0.25)
				h[run[t] * GNX + i] = minf(y, -0.25)
				m[run[t] * GNX + i] = STEPS
		stair_tops.append(Rect2(xr.x, top_z - 1.5, xr.y - xr.x, 3.0))


# ------------------------------------------------------------------ meshes
## One material's cells of a height grid as voxel columns: merged tops, sides down to the
## lower neighbour (or `floor_y` at sea). UV2.x carries the column's top (shader lip).
func _grid_mesh(hh: PackedFloat32Array, mm: PackedByteArray, nx: int, nz: int, cell: float, origin: Vector2,
		which: int, floor_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for k in nz:
		var i := 0
		while i < nx:
			var idx := k * nx + i
			if mm[idx] != which or is_nan(hh[idx]):
				i += 1
				continue
			var y := hh[idx]
			var j := i + 1
			while j < nx and mm[k * nx + j] == which and hh[k * nx + j] == y:
				j += 1
			var x0 := origin.x + i * cell
			var x1 := origin.x + j * cell
			var z0 := origin.y + k * cell
			var z1 := z0 + cell
			_quad(st, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, y)
			any = true
			i = j
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for k in nz:
		for i in nx:
			var idx := k * nx + i
			if mm[idx] != which or is_nan(hh[idx]):
				continue
			var y := hh[idx]
			for dv: Vector2i in dirs:
				var ni := i + dv.x
				var nk := k + dv.y
				var ny := floor_y
				if ni >= 0 and ni < nx and nk >= 0 and nk < nz and not is_nan(hh[nk * nx + ni]):
					ny = maxf(hh[nk * nx + ni], floor_y)
				if ny >= y - 0.01:
					continue
				var x0 := origin.x + i * cell
				var z0 := origin.y + k * cell
				var n := Vector3(dv.x, 0, dv.y)
				var a: Vector2
				var b: Vector2
				match dv:
					Vector2i(1, 0):
						a = Vector2(x0 + cell, z0)
						b = Vector2(x0 + cell, z0 + cell)
					Vector2i(-1, 0):
						a = Vector2(x0, z0)
						b = Vector2(x0, z0 + cell)
					Vector2i(0, 1):
						a = Vector2(x0, z0 + cell)
						b = Vector2(x0 + cell, z0 + cell)
					_:
						a = Vector2(x0, z0)
						b = Vector2(x0 + cell, z0)
				_quad(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(b.x, ny, b.y), Vector3(a.x, ny, a.y), n, y)
				any = true
	if not any:
		return ArrayMesh.new()
	return st.commit()


## A quad facing `n` (front faces wind clockwise as seen from the front).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, top: float) -> void:
	_tri(st, a, b, c, n, top)
	_tri(st, a, c, d, n, top)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, top: float) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_uv2(Vector2(top, 0.0))
		st.add_vertex(v)


## Metres from every point of the sea to the nearest land, 0.5 m texels (R8, 48 m range).
func _shore_map() -> ImageTexture:
	var x0 := -170.0
	var z0 := -150.0
	var res := 0.5
	var w := 720
	var hgt := 620
	var land := PackedByteArray()
	land.resize(w * hgt)
	for k in hgt:
		for i in w:
			var gi := floori(x0 + (i + 0.5) * res - GX0)
			var gk := floori(z0 + (k + 0.5) * res - GZ0)
			if gi >= 0 and gi < GNX and gk >= 0 and gk < GNZ and not is_nan(h[gk * GNX + gi]):
				land[k * w + i] = 1
	var d := _chamfer(land, w, hgt)
	var img := Image.create(w, hgt, false, Image.FORMAT_L8)
	for k in hgt:
		for i in w:
			img.set_pixel(i, k, Color.from_hsv(0, 0, clampf(d[k * w + i] * res / 48.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## The distant coast to the west, north and north-east (12 m voxels, hills rising inland).
func _far_coast() -> ArrayMesh:
	var cell := 12.0
	var n := 184
	var origin := Vector2(-1104, -1104)
	var hh := PackedFloat32Array()
	var mm := PackedByteArray()
	hh.resize(n * n)
	mm.resize(n * n)
	var hills := FastNoiseLite.new()
	hills.seed = 5
	hills.frequency = 0.004
	hills.fractal_octaves = 4
	for k in n:
		for i in n:
			var idx := k * n + i
			hh[idx] = NAN
			var p := origin + Vector2(i + 0.5, k + 0.5) * cell
			var r := p.length()
			var a := rad_to_deg(atan2(p.x, -p.y))    # 0 = north, 90 = east
			if a < -150.0 or a > 70.0 or r > 1100.0:
				continue
			var edge := minf(a + 150.0, 70.0 - a)     # degrees from the ends of the arc
			var r0 := 640.0 + 150.0 * hills.get_noise_1d(a * 3.0) + maxf(0.0, 40.0 - edge) * 12.0
			if r < r0:
				continue
			var inland := clampf((r - r0) / 140.0, 0.0, 1.0) * clampf(edge / 30.0, 0.15, 1.0)
			var y := SEA_Y + 3.0 + inland * (12.0 + 55.0 * maxf(hills.get_noise_2d(p.x, p.y) + 0.35, 0.0))
			hh[idx] = snappedf(y, 6.0)
			mm[idx] = 1
	return _grid_mesh(hh, mm, n, n, cell, origin, 1, SEA_Y - 2.0)


## A bigger green island in the north-west haze (3 m voxels): a long ridge with a few hills.
func _neighbour() -> ArrayMesh:
	var cell := 3.0
	var n := 64
	var c := Vector2(-310, -190)
	var origin := c - Vector2(n, n) * cell * 0.5
	var hh := PackedFloat32Array()
	var mm := PackedByteArray()
	hh.resize(n * n)
	mm.resize(n * n)
	var hills := FastNoiseLite.new()
	hills.seed = 9
	hills.frequency = 0.025
	hills.fractal_octaves = 3
	for k in n:
		for i in n:
			var idx := k * n + i
			hh[idx] = NAN
			var p := origin + Vector2(i + 0.5, k + 0.5) * cell
			var q := (p - c).rotated(0.5)
			q.x /= 1.5
			var a := q.angle()
			var r := 50.0 * (1.0 + 0.3 * noise.get_noise_2d(cos(a) * 12.0, sin(a) * 12.0))
			var t := q.length() / r
			if t >= 1.0:
				continue
			var lift := clampf(hills.get_noise_2d(p.x, p.y) * 0.9 + 0.55, 0.0, 1.0)
			var y := SEA_Y + 0.5 + pow(1.0 - t, 0.6) * (6.0 + 30.0 * lift)
			hh[idx] = snappedf(y, 1.5)
			mm[idx] = 1
	return _grid_mesh(hh, mm, n, n, cell, origin, 1, SEA_Y - 2.0)


# ------------------------------------------------------------------ prop meshes
func _toon_vc() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cw_toon_solid.gdshader")
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("roughness", 0.9)
	return mat


func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var hx := s * 0.5
	var faces := [
		[Vector3.UP, Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3.DOWN, Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
		[Vector3.RIGHT, Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
		[Vector3.LEFT, Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)],
		[Vector3.BACK, Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3.FORWARD, Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var v: Array[Vector3] = []
		for q in range(1, 5):
			v.append(c + (f[q] as Vector3) * hx)
		_ctri(st, v[0], v[1], v[2], n, col)
		_ctri(st, v[0], v[2], v[3], n, col)


func _ctri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


## An n-sided prism (radius r at the bottom, r2 at the top) between y0 and y1.
func _prism(st: SurfaceTool, c: Vector3, r: float, r2: float, y0: float, y1: float, sides: int, col: Color, caps := true) -> void:
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var p0 := c + Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p1 := c + Vector3(cos(a1) * r, y0, sin(a1) * r)
		var q0 := c + Vector3(cos(a0) * r2, y1, sin(a0) * r2)
		var q1 := c + Vector3(cos(a1) * r2, y1, sin(a1) * r2)
		var am := (a0 + a1) * 0.5
		var n := Vector3(cos(am), (r - r2) / maxf(y1 - y0, 0.01), sin(am)).normalized()
		_ctri(st, p0, p1, q1, n, col)
		_ctri(st, p0, q1, q0, n, col)
		if caps:
			_ctri(st, c + Vector3(0, y1, 0), q0, q1, Vector3.UP, col)
			_ctri(st, c + Vector3(0, y0, 0), p0, p1, Vector3.DOWN, col)


func _save_mesh(st: SurfaceTool, mesh_name: String) -> void:
	var mesh := st.commit()
	ResourceSaver.save(mesh, DIR + mesh_name + ".res", ResourceSaver.FLAG_COMPRESS)


func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _prop_meshes() -> void:
	var white := Color("#f4f1ea")
	var red := Color("#e0524f")
	var stone := Color("#8d939c")
	var dark := Color("#3b4452")
	var wood := Color("#8a6544")
	var wood2 := Color("#76563a")
	# lighthouse: a stone foot, a banded tower, the gallery, the lantern cap and the keeper's house
	var st := _st()
	_prism(st, Vector3.ZERO, 3.6, 3.4, -1.0, 0.8, 8, stone)
	for b in 8:
		var r0 := lerpf(2.1, 1.45, b / 8.0)
		var r1 := lerpf(2.1, 1.45, (b + 1) / 8.0)
		_prism(st, Vector3.ZERO, r0, r1, 0.8 + b * 1.5, 0.8 + (b + 1) * 1.5, 8, red if b % 2 == 1 else white, false)
	_prism(st, Vector3.ZERO, 2.3, 2.3, 12.8, 13.2, 8, dark)
	for k in 8:
		var a := TAU * k / 8.0
		_box(st, Vector3(cos(a) * 2.15, 13.6, sin(a) * 2.15), Vector3(0.12, 0.8, 0.12), dark)
	_prism(st, Vector3.ZERO, 2.2, 2.2, 13.95, 14.05, 8, dark)
	_prism(st, Vector3.ZERO, 1.5, 0.2, 15.6, 17.2, 8, red)
	_box(st, Vector3(0, 17.4, 0), Vector3(0.35, 0.35, 0.35), dark)
	_box(st, Vector3(4.6, 1.8, 1.0), Vector3(4.0, 2.4, 3.4), white)
	for r in 4:
		_box(st, Vector3(4.6, 3.1 + r * 0.35, 1.0), Vector3(4.4, 0.35, 3.8 - r * 1.0), red)
	_box(st, Vector3(4.6, 1.3, 2.75), Vector3(0.9, 1.6, 0.1), wood2)
	_box(st, Vector3(3.4, 2.1, 2.75), Vector3(0.7, 0.7, 0.08), Color("#ffd27a"))
	_save_mesh(st, "lighthouse")
	st = _st()
	_prism(st, Vector3.ZERO, 1.35, 1.35, 13.2, 15.6, 8, Color("#ffe6a8"))
	_save_mesh(st, "lighthouse_lamp")
	# sailboat: a white hull with a blue stripe, a deck, mast, boom, a stepped sail and a flag
	st = _st()
	_box(st, Vector3(0, -0.15, 0), Vector3(1.0, 0.5, 3.4), Color("#2f4f7a"))
	_box(st, Vector3(0, 0.35, -0.2), Vector3(1.8, 0.6, 3.6), white)
	_box(st, Vector3(0, 0.35, 1.8), Vector3(1.2, 0.6, 0.8), white)
	_box(st, Vector3(0, 0.35, 2.35), Vector3(0.6, 0.6, 0.5), white)
	_box(st, Vector3(0, 0.2, -0.2), Vector3(1.84, 0.14, 3.64), Color("#3f6f9a"))
	_box(st, Vector3(0, 0.67, -0.2), Vector3(1.6, 0.06, 3.3), wood)
	_box(st, Vector3(0, 3.6, 0.4), Vector3(0.14, 6.0, 0.14), wood2)
	_box(st, Vector3(0, 1.2, -0.7), Vector3(0.12, 0.12, 2.4), wood2)
	for s in 6:
		var w := 2.2 * (1.0 - s / 6.0)
		_box(st, Vector3(0, 1.6 + s * 0.8, 0.3 - w * 0.5), Vector3(0.06, 0.8, w), Color("#fbf6ec"))
	_box(st, Vector3(0, 6.7, 0.65), Vector3(0.04, 0.3, 0.5), Color("#ff8a3d"))
	_save_mesh(st, "boat_sail")
	# fishing boat: red hull, white cabin with windows, a stubby mast with a lamp
	st = _st()
	_box(st, Vector3(0, -0.1, 0), Vector3(1.2, 0.6, 4.0), Color("#7a2f2f"))
	_box(st, Vector3(0, 0.45, 0), Vector3(2.2, 0.7, 4.6), red)
	_box(st, Vector3(0, 0.45, 2.55), Vector3(1.4, 0.7, 0.6), red)
	_box(st, Vector3(0, 0.82, 0), Vector3(2.0, 0.06, 4.4), wood)
	_box(st, Vector3(0, 1.6, -0.6), Vector3(1.6, 1.5, 1.6), white)
	_box(st, Vector3(0, 2.45, -0.6), Vector3(1.9, 0.2, 1.9), Color("#3f6f9a"))
	_box(st, Vector3(0, 1.8, 0.21), Vector3(1.2, 0.5, 0.04), Color("#7cc8ff"))
	_box(st, Vector3(0, 3.4, -0.6), Vector3(0.12, 1.8, 0.12), dark)
	_box(st, Vector3(0, 4.35, -0.6), Vector3(0.25, 0.2, 0.25), Color("#ffd27a"))
	_box(st, Vector3(0.7, 1.0, 1.4), Vector3(0.5, 0.35, 0.6), Color("#ffd25c"))
	_save_mesh(st, "boat_fishing")
	# buoy: red and white bands, a cage and a little light
	st = _st()
	_prism(st, Vector3.ZERO, 0.6, 0.55, -0.6, 0.2, 8, red)
	_prism(st, Vector3.ZERO, 0.55, 0.45, 0.2, 0.6, 8, white)
	_prism(st, Vector3.ZERO, 0.45, 0.3, 0.6, 1.0, 8, red)
	_box(st, Vector3(0, 1.4, 0), Vector3(0.08, 0.8, 0.08), dark)
	_box(st, Vector3(0, 1.85, 0), Vector3(0.28, 0.22, 0.28), Color("#ffe6a8"))
	_save_mesh(st, "buoy")
	# pier: planks on posts
	st = _st()
	var length: float = PIER["z1"] - PIER["z0"]
	var n_planks := int(length / 0.5)
	for p in n_planks:
		_box(st, Vector3(0, 0, p * 0.5 + 0.25), Vector3(2.4, 0.18, 0.44), wood if p % 2 == 0 else wood2)
	for p in range(0, int(length / 3.0) + 1):
		for sx in [-1.1, 1.1]:
			_box(st, Vector3(sx, -0.9, p * 3.0 + 0.2), Vector3(0.3, 2.0, 0.3), wood2)
	_box(st, Vector3(1.0, 0.45, length - 0.6), Vector3(0.35, 0.7, 0.35), dark)
	_save_mesh(st, "pier")
	# beach umbrella and a towel
	st = _st()
	_box(st, Vector3(0, 1.1, 0), Vector3(0.1, 2.2, 0.1), white)
	var cols := [Color("#ff9a5c"), white, Color("#6fe0be"), white]
	for r in 4:
		var w2 := 2.6 - r * 0.6
		_box(st, Vector3(0, 2.2 + r * 0.18, 0), Vector3(w2, 0.18, w2), cols[r])
	_box(st, Vector3(1.4, 0.03, 0.4), Vector3(1.0, 0.06, 1.9), Color("#7cc8ff"))
	_box(st, Vector3(1.4, 0.04, 0.4), Vector3(1.0, 0.06, 0.3), white)
	_save_mesh(st, "beach_umbrella")
	# clouds: flat-bottomed voxel puffs
	for v in 2:
		st = _st()
		var rng := RandomNumberGenerator.new()
		rng.seed = 300 + v
		_box(st, Vector3(0, 2.0, 0), Vector3(16 + v * 4, 4, 8), white)
		for b in 7:
			var s := Vector3(rng.randf_range(5, 10), rng.randf_range(3, 6), rng.randf_range(4, 7))
			_box(st, Vector3(rng.randf_range(-8, 8), s.y * 0.5 + rng.randf_range(0.5, 2.5), rng.randf_range(-2.5, 2.5)), s, white)
		_save_mesh(st, "cloud_%s" % ["a", "b"][v])


# ------------------------------------------------------------------ scenes
func _terrain_mat(params: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/campus_terrain.gdshader")
	mat.set_shader_parameter("lip_from_uv2", true)
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	return mat


func _mesh_node(parent: Node, node_name: String, mesh: Mesh, mat: Material, pos := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


func _node(parent: Node, n: Node, node_name: String) -> Node:
	n.name = node_name
	parent.add_child(n)
	n.owner = parent if parent.owner == null else parent.owner
	return n


## An AnimationPlayer playing one looping animation on load.
func _anim_player(parent: Node, anim_name: String, length: float, tracks: Array) -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	for t: Array in tracks:
		var ti := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(ti, NodePath(t[0]))
		anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_CUBIC if t.size() < 3 else t[2])
		for key: Array in t[1]:
			anim.track_insert_key(ti, key[0], key[1])
	var lib := AnimationLibrary.new()
	lib.add_animation(anim_name, anim)
	ap.add_animation_library("", lib)
	ap.autoplay = anim_name
	_node(parent, ap, "AnimationPlayer")
	return ap


func _save_scene(root: Node, path: String) -> void:
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed: %s" % path)
	ResourceSaver.save(ps, path)
	print("wrote %s" % path)


func _bob_tracks(node: String, amp: float, roll: float) -> Array:
	return [[node + ":position", [[0.0, Vector3.ZERO], [1.6, Vector3(0, amp, 0)], [3.2, Vector3.ZERO]]],
		[node + ":rotation", [[0.0, Vector3(0, 0, -roll)], [2.1, Vector3(roll * 0.4, 0, roll)], [4.2, Vector3(0, 0, -roll)]]]]


func _build_props_scenes() -> void:
	var mat := _props_mat
	# lighthouse
	var lh := Node3D.new()
	lh.name = "Lighthouse"
	_mesh_node(lh, "Body", load(DIR + "lighthouse.res"), mat)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color("#ffe6a8")
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color("#ffd27a")
	lamp_mat.emission_energy_multiplier = 4.0
	_mesh_node(lh, "Lamp", load(DIR + "lighthouse_lamp.res"), lamp_mat, Vector3.ZERO, false)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffd29a")
	light.light_energy = 2.0
	light.omni_range = 22.0
	light.position = Vector3(0, 14.4, 0)
	_node(lh, light, "Light")
	light.add_to_group(&"campus_lamps", true)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 14.4, 0)
	_node(lh, pivot, "BeamPivot")
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 2.6
	cone.height = 36.0
	cone.radial_segments = 10
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = load("res://shaders/campus_beam.gdshader")
	for side in [1.0, -1.0]:
		var beam := _mesh_node(pivot, "Beam" if side > 0 else "Beam2", cone, beam_mat, Vector3(side * 18.4, 0, 0), false)
		beam.rotation = Vector3(0, 0, PI * 0.5 * side)
		beam.add_to_group(&"campus_night_glow", true)
	_anim_player(lh, "spin", 9.0, [["BeamPivot:rotation", [[0.0, Vector3.ZERO], [4.5, Vector3(0, PI, 0)], [9.0, Vector3(0, TAU, 0)]],
		Animation.INTERPOLATION_LINEAR]])
	_save_scene(lh, "res://scenes/tycoon/campus_lighthouse.tscn")
	lh.free()
	for spec: Array in [["Boat", "boat_sail", "campus_boat"], ["FishingBoat", "boat_fishing", "campus_fishing_boat"],
			["Buoy", "buoy", "campus_buoy"]]:
		var root := Node3D.new()
		root.name = spec[0]
		_mesh_node(root, "Body", load(DIR + spec[1] + ".res"), mat)
		var amp := 0.12 if spec[0] != "Buoy" else 0.18
		var roll := 0.05 if spec[0] != "Buoy" else 0.12
		_anim_player(root, "bob", 4.2, _bob_tracks("Body", amp, roll))
		_save_scene(root, "res://scenes/tycoon/%s.tscn" % spec[2])
		root.free()
	await process_frame


func _scatter(parent: Node, node_name: String, mesh: String, mat: String, ground: MeshInstance3D, count: int, seed_v: int,
		opts := {}) -> CampusScatter:
	var s := CampusScatter.new()
	s.name = node_name
	s.multimesh = MultiMesh.new()
	s.multimesh.mesh = load(MESHES + mesh + ".res")
	s.material_override = load(mat)
	s.mask = load(DIR + "island_mask.tres")
	s.ground = ground
	s.skip_off_ground = true
	s.count = count
	s.seed_value = seed_v
	s.area = Rect2(GX0, GZ0, GNX, GNZ)
	for k: String in opts:
		s.set(k, opts[k])
	parent.add_child(s)
	s.owner = parent.owner
	print("%s: %d" % [node_name, s.scatter()])
	return s


func _build_island_scene() -> void:
	var root := Node3D.new()
	root.name = "Island"
	get_root().add_child(root)
	# the sea
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = load("res://shaders/campus_sea.gdshader")
	var sea_params := {"deep": Color(0.016, 0.04, 0.085), "mid": Color(0.026, 0.085, 0.14), "shallow": Color(0.045, 0.175, 0.2),
		"lagoon": Color(0.15, 0.38, 0.37), "foam_color": Color(0.86, 0.92, 1.0), "use_shore_map": true,
		"shore_map": load(DIR + "shore_map.res"), "shore_rect": Vector4(-170, -150, 360, 310), "shore_range": 48.0,
		"shelf": 26.0, "lagoon_width": 3.0, "wave_scale": 0.12, "wave_strength": 0.35, "wave_speed": 0.6,
		"foam_reach": 7.0, "foam_spacing": 2.6, "foam_speed": 0.45, "foam_strength": 0.9, "roughness_value": 0.16}
	for k: String in sea_params:
		sea_mat.set_shader_parameter(k, sea_params[k])
	var plane := PlaneMesh.new()
	plane.size = Vector2(2600, 2600)
	_mesh_node(root, "Sea", plane, sea_mat, Vector3(0, SEA_Y, 0), false)
	# terrain
	var grass := {"grass_a": Color(0.25, 0.43, 0.25), "grass_b": Color(0.33, 0.5, 0.27), "grass_dry": Color(0.5, 0.49, 0.29),
		"clover": Color(0.19, 0.37, 0.25)}
	var plat := _mesh_node(root, "Plateau", load(DIR + "plateau.res"), _terrain_mat(grass.merged({"brightness": 1.0,
		"rock_a": Color(0.19, 0.2, 0.24), "rock_b": Color(0.28, 0.27, 0.3)})))
	plat.set_meta("walk_outline", plateau_poly)
	_mesh_node(root, "Terraces", load(DIR + "terraces.res"), _terrain_mat(grass.merged({"brightness": 0.86,
		"dry_amount": 0.45, "earth_amount": 0.2})))
	_mesh_node(root, "Sand", load(DIR + "sand.res"), _terrain_mat({"grass_a": Color(0.66, 0.58, 0.44),
		"grass_b": Color(0.72, 0.64, 0.49), "grass_dry": Color(0.6, 0.53, 0.41), "clover": Color(0.63, 0.56, 0.43),
		"earth": Color(0.5, 0.45, 0.37), "earth_amount": 0.4, "cell_size": 0.2, "rock_a": Color(0.47, 0.42, 0.35),
		"rock_b": Color(0.55, 0.49, 0.4), "soil": Color(0.45, 0.4, 0.33), "lip_depth": 0.0, "dry_amount": 0.2}))
	_mesh_node(root, "Rock", load(DIR + "rock.res"), _terrain_mat({"rock_top": true, "rock_a": Color(0.2, 0.22, 0.26),
		"rock_b": Color(0.3, 0.3, 0.32), "soil": Color(0.27, 0.27, 0.29), "lip_depth": 0.0, "brightness": 1.1}))
	var steps_mat := ShaderMaterial.new()
	steps_mat.shader = load("res://shaders/cw_toon_solid.gdshader")
	steps_mat.set_shader_parameter("albedo", Color("#8a6544"))
	_mesh_node(root, "Steps", load(DIR + "steps.res"), steps_mat)
	var far_mat := _terrain_mat(grass.merged({"brightness": 0.8, "cell_size": 2.0, "dry_amount": 0.4, "rock_a": Color(0.2, 0.21, 0.26),
		"rock_b": Color(0.26, 0.26, 0.3)}))
	_mesh_node(root, "FarCoast", load(DIR + "far_coast.res"), far_mat, Vector3.ZERO, false)
	_mesh_node(root, "NeighbourIsland", load(DIR + "neighbour_island.res"), far_mat, Vector3.ZERO, false)
	# shore props
	var shore := _node(root, Node3D.new(), "Shore") as Node3D
	_mesh_node(shore, "Pier", load(DIR + "pier.res"), _props_mat, Vector3(PIER["x"], PIER["y"], PIER["z0"]))
	var umb := load(DIR + "beach_umbrella.res") as Mesh
	var u1 := _mesh_node(shore, "Umbrella", umb, _props_mat, Vector3(8, -8.75, 58.5))
	u1.rotation.y = 0.4
	var u2 := _mesh_node(shore, "Umbrella2", umb, _props_mat, Vector3(-9, -8.75, 54))
	u2.rotation.y = -0.7
	var boats := [["campus_boat", "Sailboat", Vector3(64, SEA_Y, 82), 0.6], ["campus_boat", "Sailboat2", Vector3(-118, SEA_Y, -64), -1.1],
		["campus_fishing_boat", "FishingBoat", Vector3(27.6, SEA_Y, 74), 0.05], ["campus_boat", "Sailboat3", Vector3(140, SEA_Y, 10), 2.2]]
	for b: Array in boats:
		var inst := (load("res://scenes/tycoon/%s.tscn" % b[0]) as PackedScene).instantiate() as Node3D
		_node(shore, inst, b[1])
		inst.position = b[2]
		inst.rotation.y = b[3]
	var buoys := [Vector3(42, SEA_Y, 72), Vector3(8, SEA_Y, 82), Vector3(-14, SEA_Y, 72), Vector3(86, SEA_Y, 58), Vector3(102, SEA_Y, -6)]
	for i in buoys.size():
		var inst2 := (load("res://scenes/tycoon/campus_buoy.tscn") as PackedScene).instantiate() as Node3D
		_node(shore, inst2, "Buoy%d" % (i + 1))
		inst2.position = buoys[i]
		(inst2.get_node("AnimationPlayer") as AnimationPlayer).speed_scale = 0.8 + 0.1 * i
	var lh := (load("res://scenes/tycoon/campus_lighthouse.tscn") as PackedScene).instantiate() as Node3D
	_node(root, lh, "Lighthouse")
	lh.position = Vector3(114, -3.0, -46)
	# shore plants
	var veg := _node(root, Node3D.new(), "Vegetation") as Node3D
	var ter := root.get_node("Terraces") as MeshInstance3D
	var sand := root.get_node("Sand") as MeshInstance3D
	var rock := root.get_node("Rock") as MeshInstance3D
	var t_opts := {"blocks_walkers": true, "walk_footprint": 0.55, "min_spacing": 4.0, "scale_range": Vector2(0.8, 1.15), "tint_variation": 0.08}
	_scatter(veg, "TerraceTreesA", "tree_round_a", FOLIAGE, ter, 34, 31, t_opts)
	_scatter(veg, "TerraceTreesB", "tree_round_c", FOLIAGE, ter, 26, 32, t_opts)
	_scatter(veg, "TerracePines", "tree_pine_b", FOLIAGE, ter, 22, 33, t_opts)
	_scatter(veg, "TerraceBushes", "bush_a", FOLIAGE, ter, 80, 34, {"scale_range": Vector2(0.8, 1.2), "tint_variation": 0.1})
	_scatter(veg, "TerraceFlowers", "bush_flower_a", FOLIAGE, ter, 40, 35, {"clusters": 8, "cluster_radius": 4.0})
	_scatter(veg, "TerraceGrass", "grass_a", GRASS, ter, 500, 36, {"scale_range": Vector2(0.8, 1.3), "tint_variation": 0.1,
		"cast_shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF})
	_scatter(veg, "BeachReeds", "reeds", GRASS, sand, 50, 37, {"scale_range": Vector2(0.8, 1.3)})
	_scatter(veg, "BeachRocks", "rock_b", ROCK_MAT, sand, 24, 38, {"scale_range": Vector2(0.6, 1.4)})
	_scatter(veg, "CliffBoulders", "rock_big", ROCK_MAT, rock, 30, 39, {"scale_range": Vector2(0.7, 1.6), "min_spacing": 5.0})
	_scatter(veg, "CliffRocks", "rock_c", ROCK_MAT, rock, 60, 40, {"scale_range": Vector2(0.7, 1.5)})
	# sky: clouds and gulls
	var sky := _node(root, Node3D.new(), "SkyLife") as Node3D
	var cloud_mat := ShaderMaterial.new()
	cloud_mat.shader = load("res://shaders/campus_cloud.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for v in 2:
		var mmi := MultiMeshInstance3D.new()
		var mmesh := MultiMesh.new()
		mmesh.transform_format = MultiMesh.TRANSFORM_3D
		mmesh.mesh = load(DIR + "cloud_%s.res" % ["a", "b"][v])
		mmesh.instance_count = 9
		mmi.multimesh = mmesh
		mmi.material_override = cloud_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-700, 30, -700), Vector3(1400, 120, 1400))
		_node(sky, mmi, "Clouds%s" % ["A", "B"][v])
		for i in 9:
			var z := rng.randf_range(150, 520) * (-1.0 if rng.randf() < 0.7 else 1.0)
			var s := rng.randf_range(1.0, 2.2)
			var xf := Transform3D(Basis.from_scale(Vector3(s, s * 0.8, s)), Vector3(rng.randf_range(-600, 600), rng.randf_range(55, 110), z))
			mmesh.set_instance_transform(i, xf)
	var gull_mat := ShaderMaterial.new()
	gull_mat.shader = load("res://shaders/campus_birds.gdshader")
	gull_mat.set_shader_parameter("color", Color(0.93, 0.94, 0.96))
	gull_mat.set_shader_parameter("radius", 14.0)
	gull_mat.set_shader_parameter("radius_spread", 6.0)
	gull_mat.set_shader_parameter("bird_scale", 0.9)
	gull_mat.set_shader_parameter("speed", 0.11)
	gull_mat.set_shader_parameter("height_wobble", 2.0)
	gull_mat.set_shader_parameter("glide", 0.75)
	for g: Array in [["Gulls", Vector3(110, 12, -44), 7], ["Gulls2", Vector3(16, 4, 70), 6], ["Gulls3", Vector3(-70, 6, -40), 5]]:
		var mmi2 := MultiMeshInstance3D.new()
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = load(MESHES + "bird.res")
		mm2.instance_count = g[2]
		mmi2.multimesh = mm2
		mmi2.material_override = gull_mat
		mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi2.custom_aabb = AABB(Vector3(-25, -6, -20), Vector3(50, 12, 40))
		mmi2.position = g[1]
		_node(sky, mmi2, g[0])
	await process_frame
	await process_frame
	_save_scene(root, SCENE)
	root.queue_free()
	await process_frame


# ------------------------------------------------------------------ other scenes
func _update_campus_mask() -> void:
	var path := "res://assets/campus/nature/campus_mask.tres"
	var mask := load(path) as CampusScatterMask
	mask.inside = _offset_inward(plateau_poly, 1.5)
	var av: Array[Rect2] = []
	for r: Rect2 in mask.avoid:
		av.append(r)
	for r in stair_tops:
		var g := r.grow(1.0)
		if not av.has(g):
			av.append(g)
	for r: Rect2 in FOOTPATHS:
		var g2 := r.grow(0.6)
		if not av.has(g2):
			av.append(g2)
	mask.avoid = av
	ResourceSaver.save(mask, path)


## The polygon pulled in by `d` m (each point moved along its inward normal).
func _offset_inward(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var sgn := 1.0 if _area(p) > 0.0 else -1.0
	for i in p.size():
		var a := p[(i - 1 + p.size()) % p.size()]
		var b := p[(i + 1) % p.size()]
		var t := (b - a).normalized()
		out.append(p[i] + Vector2(-t.y, t.x) * d * sgn)
	return out


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _load_edit(path: String) -> Node:
	var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	get_root().add_child(root)
	return root


## The campus plants stay on the island top: the old ring of terrace and beach plants goes
## (the island scene has its own) and every scatter is rolled again inside the top (the
## campus mask's `inside`).
func _update_nature() -> void:
	var root := _load_edit(NATURE)
	await process_frame
	for n in ["Terrace", "Beach"]:
		var g := root.get_node_or_null(n)
		if g:
			root.remove_child(g)
			g.free()
	var rocks := root.get_node_or_null("Rocks")
	if rocks:
		for c in rocks.get_children():
			if String(c.name).begins_with("RockBig"):
				rocks.remove_child(c)
				c.free()
	var mask := load("res://assets/campus/nature/campus_mask.tres") as CampusScatterMask
	for sc in root.find_children("*", "MultiMeshInstance3D", true, false):
		if not sc is CampusScatter:
			continue
		var s := sc as CampusScatter
		s.mask = mask
		var before := s.multimesh.instance_count
		print("nature %s: %d -> %d" % [s.name, before, s.scatter()])
	await process_frame
	_save_scene(root, NATURE)
	root.queue_free()


## The perimeter fences run along the island's edge, open at the stairs.
func _update_dressing() -> void:
	var root := _load_edit(DRESSING)
	await process_frame
	var ring := _offset_inward(plateau_poly, 2.5)
	var path := PackedVector3Array()
	for i in range(0, ring.size(), 2):
		path.append(Vector3(ring[i].x, 0, ring[i].y))
	var fmask := CampusScatterMask.new()
	var av: Array[Rect2] = []
	# fence pieces sit one per edge of the ring (about 3.6 m apart): the openings are wide
	# enough to always catch a piece
	for r in stair_tops:
		av.append(r.grow(3.0))
	for r: Rect2 in FOOTPATHS:
		av.append(r.grow(2.0))
	fmask.avoid = av
	ResourceSaver.save(fmask, DIR + "fence_mask.tres")
	fmask = load(DIR + "fence_mask.tres")
	for n in ["Workshop/FenceWood", "Base/FenceSteel"]:
		var f := root.get_node_or_null(n) as CampusScatter
		if f == null:
			continue
		f.path = path
		f.path_closed = true
		f.mask = fmask
		f.margin = 0.0
		print("%s: %d" % [n, f.scatter()])
	await process_frame
	_save_scene(root, DRESSING)
	root.queue_free()
