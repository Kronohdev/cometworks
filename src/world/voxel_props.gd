class_name VoxelPropLibrary
extends RefCounted
## Voxel props scattered on the terrain: trees (Earth), boulders (Moon, Mars,
## Mercury, Titan) and ice blocks (Europa). A few template shapes are built from
## 1 m voxels when the profile is applied (naive faces + the same baked AO as
## the terrain), then, inside the chunk jobs, copies are appended to the chunk
## mesh as a second, non-indexed surface (pure native Transform3D * array ops).
## Placement uses a world grid of `cell` meters with hashed jitter, so it does
## not depend on the LOD; chunks with lod > max_lod get no props.
## Read-only after construction -> safe to share between worker threads.

enum Kind { NONE, TREES, BOULDERS, ICE_BLOCKS }

const M := PlanetSurfaceProfile.Mat
const SH := PlanetSurfaceProfile.SHADES
const AO_SRGB := [0.5, 0.68, 0.84, 1.0]

var kind: int = Kind.NONE
var cell := 4.0
var max_lod := 2
var count_variants := 0

var _p_per_cell := 0.0
var _weights := PackedFloat32Array()  # per material
var _clear_r2 := 0.0
## Discs kept free of props (x, z, radius): the set pieces and points of interest of the
## surface scene, flattened sites and ramps (VoxelTerrain.prop_exclusions, read-only in jobs).
var exclusions := PackedVector3Array()
var _seed := 0
var _sea := -1.0e9
var _hi: Array = []  # [PackedVector3Array verts, normals, colors]
var _lo: Array = []


func _init(profile: PlanetSurfaceProfile) -> void:
	kind = profile.prop_kind
	_seed = profile.terrain_seed
	max_lod = profile.prop_max_lod
	if kind == Kind.NONE or profile.prop_density <= 0.0:
		kind = Kind.NONE
		return
	_p_per_cell = profile.prop_density / 1000.0 * cell * cell
	_clear_r2 = pow(profile.flat_zone_radius + 6.0, 2.0) if profile.flat_zone_radius > 0.0 else 0.0
	if profile.has_sea:
		_sea = profile.sea_level + profile.beach_height
	_weights.resize(PlanetSurfaceProfile.MAT_COUNT)
	match kind:
		Kind.TREES:
			_weights[M.SURFACE] = 0.07
			_weights[M.SURFACE_ALT] = 0.03
			_weights[M.ACCENT] = 1.0
		_:
			_weights[M.SURFACE] = 1.0
			_weights[M.SURFACE_ALT] = 1.6
			_weights[M.ACCENT] = 0.6
			_weights[M.ROCK] = 2.5
			_weights[M.SAND] = 0.15
			_weights[M.ICE] = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(profile.terrain_seed * 92821 + kind)
	var ca := profile.prop_color_a
	var cb := profile.prop_color_b
	for v in 6:
		var grid := {}
		match kind:
			Kind.TREES:
				if v % 3 == 2:
					_conifer(grid, rng, ca.darkened(0.12), cb)
				else:
					_round_tree(grid, rng, ca, cb)
			Kind.BOULDERS:
				_boulder(grid, rng, ca, cb, 0.7 + v * 0.35)
			Kind.ICE_BLOCKS:
				_ice_block(grid, rng, ca, cb, 1 + v % 3)
		_hi.append(_mesh(grid, 1))
		_lo.append(_mesh(_downsample(grid), 2))
	count_variants = _hi.size()


# ------------------------------------------------------------------ templates

func _round_tree(g: Dictionary, rng: RandomNumberGenerator, leaves: Color, trunk: Color) -> void:
	var th := rng.randi_range(2, 4)
	for y in th + 1:
		g[Vector3i(0, y, 0)] = trunk
	var r := rng.randf_range(1.6, 2.7)
	var cy := th + r * 0.75
	var ri := int(ceilf(r))
	for z in range(-ri, ri + 1):
		for y in range(int(floorf(cy - r)), int(ceilf(cy + r)) + 1):
			for x in range(-ri, ri + 1):
				var d := Vector3(x, (y - cy) / 0.85, z).length()
				if d <= r and (d < r - 0.8 or rng.randf() < 0.75):
					var c := leaves * rng.randf_range(0.86, 1.1)
					g[Vector3i(x, y, z)] = Color(c.r, c.g, c.b)


func _conifer(g: Dictionary, rng: RandomNumberGenerator, leaves: Color, trunk: Color) -> void:
	var th := rng.randi_range(1, 2)
	var h := rng.randi_range(6, 9)
	for y in th + h - 1:
		g[Vector3i(0, y, 0)] = trunk
	for k in h:
		var y := th + k
		var t := float(k) / h
		var r := (1.0 - t) * rng.randf_range(2.0, 2.6) + 0.3
		if k % 2 == 1:
			r *= 0.75
		var ri := int(ceilf(r))
		for z in range(-ri, ri + 1):
			for x in range(-ri, ri + 1):
				if Vector2(x, z).length() <= r:
					var c := leaves * rng.randf_range(0.85, 1.08)
					g[Vector3i(x, y, z)] = Color(c.r, c.g, c.b)


func _boulder(g: Dictionary, rng: RandomNumberGenerator, light: Color, dark: Color, size: float) -> void:
	var rx := size * rng.randf_range(0.8, 1.3)
	var rz := size * rng.randf_range(0.8, 1.3)
	var ry := size * rng.randf_range(0.55, 0.85)
	var ix := int(ceilf(rx))
	var iz := int(ceilf(rz))
	var iy := int(ceilf(ry))
	var o := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
	for z in range(-iz, iz + 1):
		for y in range(-1, iy + 1):
			for x in range(-ix, ix + 1):
				var p := (Vector3(x, y, z) - o) / Vector3(rx, ry, rz)
				var d := p.length() + rng.randf_range(-0.12, 0.12)
				if d <= 1.0:
					var c := light.lerp(dark, clampf(rng.randf() * 0.6 + (0.4 if y <= 0 else 0.0), 0.0, 1.0))
					g[Vector3i(x, y, z)] = c


func _ice_block(g: Dictionary, rng: RandomNumberGenerator, light: Color, dark: Color, size: int) -> void:
	var sx := size + rng.randi_range(0, 1)
	var sz := size + rng.randi_range(0, 1)
	var sy := size + rng.randi_range(1, 2)
	for z in range(-sz, sz + 1):
		for x in range(-sx, sx + 1):
			var top := sy - int(absf(x + z * 0.5) * 0.5)  # slanted top like a tilted block
			for y in range(-1, top + 1):
				if (absf(x) == sx and absf(z) == sz) and rng.randf() < 0.7:
					continue
				g[Vector3i(x, y, z)] = light.lerp(dark, rng.randf() * 0.35 + (0.3 if y < 1 else 0.0))


## Half-resolution version for far chunks (voxel kept if >= 3 of 8 are solid).
func _downsample(g: Dictionary) -> Dictionary:
	var acc := {}
	for k: Vector3i in g:
		var q := Vector3i(floori(k.x / 2.0), floori(k.y / 2.0), floori(k.z / 2.0))
		if not acc.has(q):
			acc[q] = [0, Color(0, 0, 0)]
		var e: Array = acc[q]
		e[0] += 1
		e[1] += g[k]
	var out := {}
	for q: Vector3i in acc:
		var e: Array = acc[q]
		if e[0] >= 3:
			out[q] = (e[1] as Color) / float(e[0])
	return out


## Naive voxel faces with per-vertex AO -> triangle list [verts, normals, colors].
func _mesh(g: Dictionary, vs: int) -> Array:
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var cols := PackedColorArray()
	var ao_f: Array[float] = []
	for a in 4:
		ao_f.append(pow(AO_SRGB[a], 2.2))
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for k: Vector3i in g:
		var base := (g[k] as Color).srgb_to_linear()
		for n: Vector3i in dirs:
			if g.has(k + n):
				continue
			# tangent axes u, v with cross(u, v) = n
			var u: Vector3i
			var v: Vector3i
			if n.x != 0:
				u = Vector3i(0, 1, 0) if n.x > 0 else Vector3i(0, 0, 1)
				v = Vector3i(0, 0, 1) if n.x > 0 else Vector3i(0, 1, 0)
			elif n.y != 0:
				u = Vector3i(0, 0, 1) if n.y > 0 else Vector3i(1, 0, 0)
				v = Vector3i(1, 0, 0) if n.y > 0 else Vector3i(0, 0, 1)
			else:
				u = Vector3i(1, 0, 0) if n.z > 0 else Vector3i(0, 1, 0)
				v = Vector3i(0, 1, 0) if n.z > 0 else Vector3i(1, 0, 0)
			var front := k + n
			# face origin: the corner of the voxel at -u, -v on the face plane
			var o := Vector3(k) + Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5 - Vector3(u) * 0.5 - Vector3(v) * 0.5
			var corners := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]
			var pos: Array[Vector3] = []
			var lv: Array[int] = []
			for cc: Vector2i in corners:
				var su := u if cc.x == 1 else -u
				var sv := v if cc.y == 1 else -v
				var s1 := g.has(front + su)
				var s2 := g.has(front + sv)
				var c3 := g.has(front + su + sv)
				lv.append(0 if (s1 and s2) else 3 - int(s1) - int(s2) - int(c3))
				pos.append((o + Vector3(u) * cc.x + Vector3(v) * cc.y) * vs)
			var order := [1, 2, 3, 1, 3, 0] if lv[0] + lv[2] < lv[1] + lv[3] else [0, 1, 2, 0, 2, 3]
			for idx: int in order:
				verts.append(pos[idx])
				nrms.append(Vector3(n))
				var f: float = ao_f[lv[idx]]
				cols.append(Color(base.r * f, base.g * f, base.b * f, 1.0))
	return [verts, nrms, cols]


# ------------------------------------------------------------------ placement

## Appends props of one chunk (min corner ox, oz; voxel size s) into the given
## triangle-list arrays. heights/tops: the chunk's (n+2)² grids. Thread-safe.
func append_chunk(out_v: PackedVector3Array, out_n: PackedVector3Array, out_c: PackedColorArray,
		heights: PackedInt32Array, tops: PackedInt32Array, n: int, s: float, ox: float, oz: float, lod: int) -> int:
	if kind == Kind.NONE or lod > max_lod:
		return 0
	var lib: Array = _hi if lod <= 1 else _lo
	var size := n * s
	var cells := int(size / cell)
	var gx0 := int(floorf(ox / cell))
	var gz0 := int(floorf(oz / cell))
	var w := n + 2
	var placed := 0
	for cz in cells:
		for cx in cells:
			var gx := gx0 + cx
			var gz := gz0 + cz
			var hs := VoxelTerrainGenerator._hash(gx * 3 + _seed, gz * 5 - _seed, 7717)
			var r0 := VoxelTerrainGenerator._u01(hs, 1)
			if r0 >= _p_per_cell:
				continue
			# integer-meter position inside the cell (keeps the voxel grid aligned)
			var px := floorf(gx * cell + VoxelTerrainGenerator._u01(hs, 2) * cell) + 0.5
			var pz := floorf(gz * cell + VoxelTerrainGenerator._u01(hs, 3) * cell) + 0.5
			if px * px + pz * pz < _clear_r2:
				continue
			var blocked := false
			for e in exclusions:
				if (px - e.x) * (px - e.x) + (pz - e.y) * (pz - e.y) < e.z * e.z:
					blocked = true
					break
			if blocked:
				continue
			var i := clampi(int(floorf((px - ox) / s)), 0, n - 1) + 1
			var j := clampi(int(floorf((pz - oz) / s)), 0, n - 1) + 1
			var k := j * w + i
			var mat := tops[k] / SH
			if r0 >= _p_per_cell * _weights[mat]:
				continue
			var hv := heights[k]
			if hv * s < _sea:
				continue
			# skip steep spots (neighbors much lower/higher)
			var dh := maxi(maxi(absi(heights[k + 1] - hv), absi(heights[k - 1] - hv)), maxi(absi(heights[k + w] - hv), absi(heights[k - w] - hv)))
			if dh * s > 2.0:
				continue
			var vi := int(VoxelTerrainGenerator._u01(hs, 4) * count_variants) % count_variants
			var rot := int(VoxelTerrainGenerator._u01(hs, 5) * 4.0) & 3
			var basis := Basis(Vector3.UP, rot * PI * 0.5)
			var xf := Transform3D(basis, Vector3(px - ox - 0.5, hv * s, pz - oz - 0.5))
			var tpl: Array = lib[vi]
			out_v.append_array(xf * (tpl[0] as PackedVector3Array))
			out_n.append_array(Transform3D(basis, Vector3.ZERO) * (tpl[1] as PackedVector3Array))
			out_c.append_array(tpl[2])
			placed += 1
	return placed
