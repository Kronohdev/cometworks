class_name VoxelGreedyMesher
extends RefCounted
## Greedy mesher for heightmap voxel columns (pure function, thread-safe).
##
## Input: an (n+2)×(n+2) grid of column heights in voxels (one border ring for
## neighbor faces and AO), palette indices of each column's top and subsurface
## material. Output: one quad per merged run of coplanar faces that share the
## same color AND the same 4 per-vertex AO values (so baked AO stays exact).
##  - Top faces: full 2D greedy merge on the n×n grid (key = height+color+AO).
##  - Side faces: vertical run-length merge per column side, then the runs are
##    merged sideways along the slice when (y0, y1, color, AO) match.
## Underground faces are never generated (only the exposed shell), and border
## columns get "skirts" extending down `skirt` voxels to hide cracks between
## chunks of different LOD.
## Vertex colors = linear palette color × AO (same AO curve as tools/voxel_gen.py);
## the per-voxel color jitter is done in shaders/surface_terrain.gdshader.

const SH := PlanetSurfaceProfile.SHADES
const MAT_ROCK := PlanetSurfaceProfile.Mat.ROCK
const MAT_STRATA := PlanetSurfaceProfile.Mat.ROCK_STRATA
## AO brightness per occlusion level 0..3 (sRGB, like voxel_gen.py), squared to linear at build.
const AO_SRGB := [0.5, 0.68, 0.84, 1.0]
## Quad corner -> canonical AO slot. Corners: c0=p, c1=p+v, c2=p+u+v, c3=p+u.
## Canonical slot = (a+1)/2 + 2*(b+1)/2 for the two in-plane axes (vertical, tangent).
const MAP_A := [0, 1, 3, 2]  # top (a=x,b=z), -X, +Z
const MAP_B := [0, 2, 3, 1]  # +X, -Z

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _i := PackedInt32Array()
var _palette := PackedColorArray()
var _ao_f := PackedFloat32Array()


## heights/tops/subs: (n+2)² arrays. s: voxel size (m). Options:
##   palette (PackedColorArray), ao (bool), ao_strength (0..1), skirt (voxels),
##   sub_voxels (int), strata_m (float), collision (bool).
## Returns {arrays, quads, naive_faces, faces (PackedVector3Array, if collision)}.
static func build(heights: PackedInt32Array, tops: PackedInt32Array, subs: PackedInt32Array, n: int,
		s: float, opts: Dictionary) -> Dictionary:
	var palette: PackedColorArray = opts.get("palette", PackedColorArray([Color.WHITE]))
	var use_ao: bool = opts.get("ao", true)
	var ao_strength: float = opts.get("ao_strength", 1.0)
	var skirt: int = opts.get("skirt", 0)
	var sub_vox: int = opts.get("sub_voxels", 3)
	var strata_m: float = opts.get("strata_m", 0.0)
	var ao_f := PackedFloat32Array()
	for a in 4:
		var lv: float = AO_SRGB[a]
		ao_f.append(lerpf(1.0, pow(lv, 2.2), ao_strength))
	var st := VoxelGreedyMesher.new()
	st._palette = palette
	st._ao_f = ao_f
	var w := n + 2
	var naive := 0
	var quads := 0

	# ---------------------------------------------------------- top faces
	var keys := PackedInt64Array()
	keys.resize(n * n)
	for j in n:
		for i in n:
			var k := (j + 1) * w + (i + 1)
			var h := heights[k]
			var ao := 0xFF
			if use_ao:
				ao = 0
				for slot in 4:
					var sx := 1 if (slot & 1) else -1
					var sz := w if (slot & 2) else -w
					var s1 := heights[k + sx] > h
					var s2 := heights[k + sz] > h
					var c := heights[k + sx + sz] > h
					ao |= _ao_level(s1, s2, c) << (slot * 2)
			keys[j * n + i] = (int(h + 1048576) << 16) | (tops[k] << 8) | ao
	naive += n * n
	var used := PackedByteArray()
	used.resize(n * n)
	for j in n:
		for i in n:
			var idx := j * n + i
			if used[idx]:
				continue
			var key := keys[idx]
			var qw := 1
			while i + qw < n and not used[idx + qw] and keys[idx + qw] == key:
				qw += 1
			var qh := 1
			var grow := true
			while grow and j + qh < n:
				var row := (j + qh) * n + i
				for t in qw:
					if used[row + t] or keys[row + t] != key:
						grow = false
						break
				if grow:
					qh += 1
			for b in qh:
				var row := (j + b) * n + i
				for t in qw:
					used[row + t] = 1
			var hv := (key >> 16) - 1048576
			var p0 := Vector3(i * s, hv * s, j * s)
			# u along +Z, v along +X  => cross(u, v) = +Y
			st._quad(p0, Vector3(0, 0, qh * s), Vector3(qw * s, 0, 0), Vector3.UP,
				(key >> 8) & 0xFF, key & 0xFF, MAP_A)
			quads += 1

	# ---------------------------------------------------------- side faces
	# dir: 0 +X, 1 -X, 2 +Z, 3 -Z
	for dir in 4:
		var along_x := dir >= 2  # slice runs along x (Z faces) or along z (X faces)
		var front := [1, -1, w, -w][dir] as int
		var tan := 1 if along_x else w  # tangent step in the grid
		var normal: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][dir]
		var cmap: Array = MAP_B if (dir == 0 or dir == 3) else MAP_A
		for sl in n:
			var open := {}  # (y0, y1, key) -> t_start * 4096 + t_last
			for t in n:
				var i := t if along_x else sl
				var j := sl if along_x else t
				var k := (j + 1) * w + (i + 1)
				var hv := heights[k]
				var hn := heights[k + front]
				var border := (dir == 0 and i == n - 1) or (dir == 1 and i == 0) \
					or (dir == 2 and j == n - 1) or (dir == 3 and j == 0)
				var y_start := hn
				if border and skirt > 0:
					y_start = mini(hn, hv) - skirt
				if y_start >= hv:
					continue
				naive += hv - y_start
				var top_c := tops[k]
				var sub_c := subs[k]
				var hf := heights[k + front]
				var hfm := heights[k + front - tan]
				var hfp := heights[k + front + tan]
				var run_y0 := y_start
				var run_key := -1
				for y in range(y_start, hv):
					var depth := hv - 1 - y
					var col: int
					if depth == 0:
						col = top_c
					elif depth < sub_vox:
						col = sub_c
					else:
						col = _rock(y, s, strata_m)
					var ao := 0xFF
					if use_ao:
						# slot bits: a = vertical (y-1 / y+1), b = tangent (-t / +t)
						ao = _ao_level(hf > y - 1, hfm > y, hfm > y - 1) \
							| (_ao_level(hf > y + 1, hfm > y, hfm > y + 1) << 2) \
							| (_ao_level(hf > y - 1, hfp > y, hfp > y - 1) << 4) \
							| (_ao_level(hf > y + 1, hfp > y, hfp > y + 1) << 6)
					var key := (col << 8) | ao
					if key != run_key:
						if run_key >= 0:
							st._open_run(open, run_y0, y - 1, run_key, t, dir, sl, s, normal, cmap)
						run_key = key
						run_y0 = y
				st._open_run(open, run_y0, hv - 1, run_key, t, dir, sl, s, normal, cmap)
			for comp in open:
				st._emit_side(comp, open[comp], dir, sl, s, normal, cmap)
				quads += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = st._v
	arrays[Mesh.ARRAY_NORMAL] = st._n
	arrays[Mesh.ARRAY_COLOR] = st._c
	arrays[Mesh.ARRAY_INDEX] = st._i
	quads = st._i.size() / 6
	var out := {"arrays": arrays, "quads": quads, "naive_faces": naive}
	if opts.get("collision", false):
		out["faces"] = triangle_faces(st._v, st._i)
	return out


## De-indexes a triangle mesh into the face list ConcavePolygonShape3D wants.
static func triangle_faces(verts: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for q in idx.size():
		faces[q] = verts[idx[q]]
	return faces

static func _ao_level(s1: bool, s2: bool, c: bool) -> int:
	if s1 and s2:
		return 0
	return 3 - int(s1) - int(s2) - int(c)


static func _rock(y: int, s: float, strata_m: float) -> int:
	if strata_m < s * 0.99:
		return MAT_ROCK * SH + 1
	var band := int(floorf((y * s) / strata_m))
	var r := posmod(band * 7 + (band >> 2) * 3, 5)
	if r == 0:
		return MAT_STRATA * SH + 1
	if r == 3:
		return MAT_STRATA * SH + 0
	return MAT_ROCK * SH + (r % 3)


## Registers a vertical run; merges it with the run of the previous column of
## the same slice if (y0, y1, key) match, otherwise flushes the old one.
func _open_run(open: Dictionary, y0: int, y1: int, key: int, t: int, dir: int,
		sl: int, s: float, normal: Vector3, cmap: Array) -> void:
	var comp := ((y0 + 131072) << 38) | ((y1 + 131072) << 20) | key
	if open.has(comp):
		var span: int = open[comp]
		if (span & 4095) == t - 1:
			open[comp] = (span & ~4095) | t
			return
		_emit_side(comp, span, dir, sl, s, normal, cmap)
	open[comp] = t * 4096 + t


func _emit_side(comp: int, span: int, dir: int, sl: int, s: float, normal: Vector3,
		cmap: Array) -> void:
	var y0 := ((comp >> 38) & 0x3FFFF) - 131072
	var y1 := ((comp >> 20) & 0x3FFFF) - 131072
	var key := comp & 0xFFFF
	var t0 := span >> 12
	var t1 := span & 4095
	var hgt := (y1 - y0 + 1) * s
	var length := (t1 - t0 + 1) * s
	var p0: Vector3
	var u: Vector3
	var v: Vector3
	match dir:
		0:  # +X: u = Y, v = Z
			p0 = Vector3((sl + 1) * s, y0 * s, t0 * s)
			u = Vector3(0, hgt, 0)
			v = Vector3(0, 0, length)
		1:  # -X: u = Z, v = Y
			p0 = Vector3(sl * s, y0 * s, t0 * s)
			u = Vector3(0, 0, length)
			v = Vector3(0, hgt, 0)
		2:  # +Z: u = X, v = Y
			p0 = Vector3(t0 * s, y0 * s, (sl + 1) * s)
			u = Vector3(length, 0, 0)
			v = Vector3(0, hgt, 0)
		_:  # -Z: u = Y, v = X
			p0 = Vector3(t0 * s, y0 * s, sl * s)
			u = Vector3(0, hgt, 0)
			v = Vector3(length, 0, 0)
	_quad(p0, u, v, normal, (key >> 8) & 0xFF, key & 0xFF, cmap)


## Corners c0=p0, c1=p0+v, c2=p0+u+v, c3=p0+u with cross(u, v) = normal, which
## is clockwise seen from the front (Godot's front-face winding).
func _quad(p0: Vector3, u: Vector3, v: Vector3, normal: Vector3, col: int, ao: int,
		cmap: Array) -> void:
	var base := _v.size()
	var c: Color = _palette[col] if col < _palette.size() else Color.MAGENTA
	_v.append(p0)
	_v.append(p0 + v)
	_v.append(p0 + u + v)
	_v.append(p0 + u)
	var a := PackedInt32Array()
	a.resize(4)
	for corner in 4:
		var lvl := (ao >> ((cmap[corner] as int) * 2)) & 3
		a[corner] = lvl
		var f := _ao_f[lvl]
		_n.append(normal)
		_c.append(Color(c.r * f, c.g * f, c.b * f, 1.0))
	# split along the diagonal joining the brighter pair (no AO anisotropy)
	if a[0] + a[2] < a[1] + a[3]:
		_i.append_array([base + 1, base + 2, base + 3, base + 1, base + 3, base])
	else:
		_i.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
