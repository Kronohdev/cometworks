class_name VoxelTerrainGenerator
extends RefCounted
## Deterministic height/material field of one PlanetSurfaceProfile.
## Built on the main thread (copies every value it needs and duplicates the
## noises), then only READ from worker threads, so one instance is shared by
## all chunk jobs.
##
## Layers (meters): continents + ridged mountains (masked by continents) +
## detail + regional tilt + dunes + lineae ridges - accent depression; craters
## are then stamped on the sampled grid and the landing zone is flattened.

const M := PlanetSurfaceProfile.Mat
const SH := PlanetSurfaceProfile.SHADES
## Floats stored per sample in the scratch grid: height, patch, lineae, detail, dune.
const STRIDE := 5
## cos/sin of the three lineae family orientations (0°, 62°, 118°).
const LIN_ROT := [1.0, 0.0, 0.4695, 0.8829, -0.4695, 0.8829]

var palette: PackedColorArray
var sea_level := 0.0
var has_sea := false
var flat_height := 0.0
var subsurface_depth := 3.0
var strata_thickness := 3.0

var _cont: FastNoiseLite
var _ridge: FastNoiseLite
var _detail: FastNoiseLite
var _patch: FastNoiseLite
var _lin: FastNoiseLite
var _seed := 0
var _base_h := 0.0
var _cont_amp := 0.0
var _ridge_amp := 0.0
var _ridge_lo := 0.0
var _ridge_hi := 1.0
var _det_amp := 0.0
var _slope_x := 0.0
var _slope_z := 0.0
var _alt_thr := 0.0
var _acc_thr := 0.0
var _acc_dep := 0.0
var _dune_amp := 0.0
var _dune_wl := 40.0
var _dune_warp := 0.0
var _dune_max := 0.0
var _dune_dir := Vector2.RIGHT
var _lin_w := 0.0
var _lin_h := 0.0
var _depth_ratio := 0.2
var _rim_ratio := 0.04
var _ejecta := 0.0
var _beach := 0.0
var _polar := false
var _snow_line := 0.0
var _snow_blend := 0.0
var _fz_r := 0.0
var _fz_blend := 1.0
var _paved := false
var _cliff := 1.6
var _crater_classes: Array = []  # of [r_lo, r_hi, cell, prob]


func _init(profile: PlanetSurfaceProfile) -> void:
	_seed = profile.terrain_seed
	_cont = _dup_noise(profile.continents, 11)
	_ridge = _dup_noise(profile.ridges, 23)
	_detail = _dup_noise(profile.detail, 37)
	_patch = _dup_noise(profile.patches, 41)
	_lin = _dup_noise(profile.lineae, 53)
	_base_h = profile.base_height
	_cont_amp = profile.continent_amplitude
	_ridge_amp = profile.ridge_amplitude
	_ridge_lo = profile.ridge_mask_low
	_ridge_hi = profile.ridge_mask_high
	_det_amp = profile.detail_amplitude
	_slope_x = profile.regional_slope.x * 0.001
	_slope_z = profile.regional_slope.y * 0.001
	_alt_thr = profile.alt_threshold
	_acc_thr = profile.accent_threshold
	_acc_dep = profile.accent_depression
	_dune_amp = profile.dune_amplitude
	_dune_wl = maxf(profile.dune_wavelength, 1.0)
	_dune_warp = profile.dune_warp
	_dune_max = profile.dune_max_continent
	var a := deg_to_rad(profile.dune_direction_deg)
	_dune_dir = Vector2(cos(a), sin(a))
	_lin_w = profile.lineae_width
	_lin_h = profile.lineae_height
	_depth_ratio = profile.crater_depth_ratio
	_rim_ratio = profile.crater_rim_ratio
	_ejecta = profile.crater_ejecta_bright
	_beach = profile.beach_height
	_polar = profile.polar_ice
	_snow_line = profile.snow_line
	_snow_blend = profile.snow_blend
	_fz_r = profile.flat_zone_radius
	_fz_blend = maxf(profile.flat_zone_blend, 0.01)
	_paved = profile.flat_zone_paved
	_cliff = profile.cliff_slope
	subsurface_depth = profile.subsurface_depth
	strata_thickness = profile.strata_thickness
	has_sea = profile.has_sea
	sea_level = profile.sea_level
	palette = profile.build_palette()
	_build_crater_classes(profile)
	# landing-zone height = natural height at the origin (without craters)
	var probe := PackedFloat32Array()
	probe.resize(STRIDE)
	_base_sample(0.0, 0.0, probe, 0)
	flat_height = probe[0] + profile.flat_zone_offset
	if has_sea:
		flat_height = maxf(flat_height, sea_level + _beach + 1.5)


func _dup_noise(n: FastNoiseLite, salt: int) -> FastNoiseLite:
	if n == null:
		return null
	var d := n.duplicate() as FastNoiseLite
	d.seed = n.seed + _seed * 7919 + salt
	return d


func _build_crater_classes(profile: PlanetSurfaceProfile) -> void:
	if profile.crater_density <= 0.0:
		return
	var k := maxi(profile.crater_size_classes, 1)
	var rmin := maxf(profile.crater_min_radius, 0.5)
	var rmax := maxf(profile.crater_max_radius, rmin * 1.01)
	var e: float = profile.crater_size_exponent
	for i in k:
		var r_lo := rmin * pow(rmax / rmin, float(i) / k)
		var r_hi := rmin * pow(rmax / rmin, float(i + 1) / k)
		# craters per m² in this size bin (cumulative power law N(>R) ∝ R^-e)
		var n_lo: float = profile.crater_density * pow(r_lo / rmin, -e)
		var n_hi: float = profile.crater_density * pow(r_hi / rmin, -e)
		var n: float = (n_lo - n_hi) / 1.0e6
		if n <= 0.0:
			continue
		var cell := maxf(2.0 * r_hi, sqrt(1.0 / n))
		_crater_classes.append([r_lo, r_hi, cell, minf(n * cell * cell, 1.0)])


# ------------------------------------------------------------------ public API

## Terrain height in meters at a world point (craters and landing zone included).
func height_at(x: float, z: float) -> float:
	var d := PackedFloat32Array()
	d.resize(STRIDE)
	_base_sample(x, z, d, 0)
	var hh := PackedFloat32Array([d[0]])
	var bright := PackedFloat32Array([0.0])
	_stamp_craters(hh, bright, x, z, 1.0, 1, 1, 0.0)
	return _flatten(hh[0], x, z)


## World height of the voxel top surface at (x, z) for a given voxel size.
func voxel_top_at(x: float, z: float, voxel_size: float = 1.0) -> float:
	var cx := (floorf(x / voxel_size) + 0.5) * voxel_size
	var cz := (floorf(z / voxel_size) + 0.5) * voxel_size
	return floorf(height_at(cx, cz) / voxel_size + 0.5) * voxel_size


## Samples the (n+2)² column centers of a chunk whose min corner is (ox, oz)
## with spacing s (one extra ring for neighbors/AO). Returns quantized heights
## (in voxels) and palette indices of the top and subsurface materials.
func sample_chunk(ox: float, oz: float, s: float, n: int) -> Dictionary:
	var w := n + 2
	var cnt := w * w
	var data := PackedFloat32Array()
	data.resize(cnt * STRIDE)
	var x0 := ox - 0.5 * s
	var z0 := oz - 0.5 * s
	for j in w:
		var z := z0 + j * s
		for i in w:
			_base_sample(x0 + i * s, z, data, (j * w + i) * STRIDE)
	var hf := PackedFloat32Array()
	hf.resize(cnt)
	for k in cnt:
		hf[k] = data[k * STRIDE]
	var bright := PackedFloat32Array()
	bright.resize(cnt)
	_stamp_craters(hf, bright, x0, z0, s, w, w, s * 0.7)
	var heights := PackedInt32Array()
	heights.resize(cnt)
	var hmin := 1 << 30
	var hmax := -(1 << 30)
	var inv_s := 1.0 / s
	for j in w:
		for i in w:
			var k := j * w + i
			var h := _flatten(hf[k], x0 + i * s, z0 + j * s)
			hf[k] = h
			var hv := int(floorf(h * inv_s + 0.5))
			heights[k] = hv
			hmin = mini(hmin, hv)
			hmax = maxi(hmax, hv)
	var tops := PackedInt32Array()
	tops.resize(cnt)
	var subs := PackedInt32Array()
	subs.resize(cnt)
	var inv2s := 0.5 * inv_s
	var pad_half := floorf(_fz_r * 0.55)
	var use_shades := _patch != null and s <= 4.0
	for j in range(1, w - 1):
		for i in range(1, w - 1):
			var k := j * w + i
			var h := hf[k]
			var b := k * STRIDE
			var patch := data[b + 1]
			var lin := data[b + 2]
			var det := data[b + 3]
			var slope := maxf(absf(hf[k + 1] - hf[k - 1]), absf(hf[k + w] - hf[k - w])) * inv2s
			var x := x0 + i * s
			var z := z0 + j * s
			# patchy shade variants at a medium scale (several voxels wide); far
			# LODs use one shade so faces keep merging (the shader adds jitter)
			var shade := 1
			if use_shades:
				var sv := _patch.get_noise_2d(x * 4.0 + 91.0, z * 4.0 - 47.0)
				if sv < -0.2:
					shade = 0
				elif sv > 0.2:
					shade = 2
			var mat: int = M.SURFACE
			var sub: int = M.SUBSURFACE
			if _paved and absf(x) < pad_half and absf(z) < pad_half:
				# square concrete pad: 8 m slabs, darker 1 m border and center cross
				mat = M.PAD
				sub = M.PAD
				shade = 1 if ((int(floorf(x * 0.125)) + int(floorf(z * 0.125))) & 1) == 0 else 2
				if maxf(absf(x), absf(z)) > pad_half - 1.0 or (absf(x) < 0.6 or absf(z) < 0.6) and maxf(absf(x), absf(z)) < 6.0:
					shade = 0
			elif has_sea and h < sea_level - 0.6:
				mat = M.SEABED
				sub = M.SAND
			elif has_sea and h < sea_level + _beach + det * 1.5:
				mat = M.SAND
				sub = M.SAND
			elif slope > _cliff:
				mat = M.ROCK
				sub = M.ROCK
			elif _polar and h > _snow_line + (patch + det * 0.5) * _snow_blend:
				mat = M.ICE
				sub = M.ICE
			elif lin > 0.42:
				mat = M.ACCENT
				shade = 0 if lin > 0.75 else 1
			elif patch > _acc_thr:
				mat = M.ACCENT
			elif data[b + 4] > 0.35:
				mat = M.SAND
				sub = M.SAND
			elif patch > _alt_thr:
				mat = M.SURFACE_ALT
			if _ejecta > 0.0 and bright[k] * _ejecta > 0.35 + det * 0.25:
				if mat == M.SURFACE or mat == M.SURFACE_ALT or mat == M.ACCENT:
					mat = M.SURFACE_ALT
					shade = 2
			tops[k] = mat * SH + shade
			subs[k] = sub * SH + 1
	return {"heights": heights, "tops": tops, "subs": subs, "hmin": hmin, "hmax": hmax}


# ------------------------------------------------------------------ internals

func _base_sample(x: float, z: float, out: PackedFloat32Array, o: int) -> void:
	var c := 0.0
	if _cont:
		c = _cont.get_noise_2d(x, z)
	var h := _base_h + c * _cont_amp + x * _slope_x + z * _slope_z
	if _ridge:
		var m := smoothstep(_ridge_lo, _ridge_hi, c)
		if m > 0.0:
			var r := _ridge.get_noise_2d(x, z) * 0.5 + 0.5
			h += r * r * m * _ridge_amp
	var det := 0.0
	if _detail:
		det = _detail.get_noise_2d(x, z)
		h += det * _det_amp
	var patch := 0.0
	if _patch:
		patch = _patch.get_noise_2d(x, z)
		if _acc_dep != 0.0:
			h -= _acc_dep * smoothstep(_acc_thr - 0.08, _acc_thr + 0.12, patch)
	var dune := 0.0
	if _dune_amp > 0.0:
		var dm := 1.0 - smoothstep(_dune_max - 0.3, _dune_max, c)
		if dm > 0.0:
			var warp := 0.0
			if _cont:
				warp = _cont.get_noise_2d(x * 9.7 + 311.0, z * 9.7 - 173.0)
			var along := (x * _dune_dir.x + z * _dune_dir.y) / _dune_wl + warp * _dune_warp
			var ph := along - floorf(along)
			# gentle windward slope, steep slip face
			var prof := ph / 0.78 if ph < 0.78 else (1.0 - ph) / 0.22
			prof = prof * prof * (3.0 - 2.0 * prof)
			h += prof * _dune_amp * dm * (0.65 + 0.35 * det)
			dune = dm
	var lin := 0.0
	if _lin:
		# three families of long, gently curving bands (zero-crossings of a
		# stretched noise), like Europa's crossing lineae of different ages
		var ridge := 0.0
		for f in 3:
			var c0: float = LIN_ROT[f * 2]
			var s0: float = LIN_ROT[f * 2 + 1]
			var u := x * c0 + z * s0
			var v := z * c0 - x * s0
			var su := u * 0.3 + f * 1733.0
			var sv := v * 1.6 - f * 977.0
			var n0 := _lin.get_noise_2d(su, sv)
			var wdt := _lin_w * (1.0 - 0.3 * f)  # meters
			# distance (m) to the zero crossing = |n| / |grad n|
			var gu := (_lin.get_noise_2d(su + 0.6, sv) - n0) / 0.6 * 0.3
			var gv := (_lin.get_noise_2d(su, sv + 0.6) - n0) / 0.6 * 1.6
			var dist := absf(n0) / maxf(sqrt(gu * gu + gv * gv), 1e-5)
			if dist < wdt:
				var band := 1.0 - smoothstep(wdt * 0.45, wdt, dist)
				lin = maxf(lin, band * (1.0 - 0.2 * f))
				# double ridge: two crests with a central trough
				var q := dist / wdt
				ridge = maxf(ridge, (1.0 - smoothstep(0.55, 1.0, q)) * (0.5 + 0.5 * smoothstep(0.0, 0.4, q)) * (1.0 - 0.3 * f))
		h += ridge * _lin_h
	out[o] = h
	out[o + 1] = patch
	out[o + 2] = lin
	out[o + 3] = det
	out[o + 4] = dune


func _flatten(h: float, x: float, z: float) -> float:
	if _fz_r <= 0.0:
		return h
	var d := sqrt(x * x + z * z)
	if d >= _fz_r + _fz_blend:
		return h
	var w := 1.0 - smoothstep(_fz_r, _fz_r + _fz_blend, d)
	return lerpf(h, flat_height, w)


static func _hash(a: int, b: int, c: int) -> int:
	var h := (a * 374761393 + b * 668265263 + c * 1274126177) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1103515245) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 668265261) & 0xFFFFFFFF
	return h ^ (h >> 15)


static func _u01(h: int, k: int) -> float:
	return float(_hash(h, k, 977) & 0xFFFFFF) / 16777216.0


## Adds every crater overlapping the grid (w×hn samples at x0 + i*s, z0 + j*s)
## to `hf`. Craters smaller than min_r are skipped (sub-voxel at this LOD).
## Rasterizing per crater (instead of testing every crater per sample) keeps
## the cost proportional to the cratered area.
func _stamp_craters(hf: PackedFloat32Array, bright: PackedFloat32Array, x0: float, z0: float, s: float,
		w: int, hn: int, min_r: float) -> void:
	if _crater_classes.is_empty():
		return
	var x1 := x0 + (w - 1) * s
	var z1 := z0 + (hn - 1) * s
	for ci in _crater_classes.size():
		var cls: Array = _crater_classes[ci]
		var r_lo: float = cls[0]
		var r_hi: float = cls[1]
		if r_hi < min_r:
			continue
		var cell: float = cls[2]
		var prob: float = cls[3]
		var reach := r_hi * 1.9
		var gx0 := int(floorf((x0 - reach) / cell))
		var gx1 := int(floorf((x1 + reach) / cell))
		var gz0 := int(floorf((z0 - reach) / cell))
		var gz1 := int(floorf((z1 + reach) / cell))
		for gz in range(gz0, gz1 + 1):
			for gx in range(gx0, gx1 + 1):
				var hsh := _hash(gx + _seed * 31, gz - _seed * 17, ci * 7 + 3)
				if _u01(hsh, 1) >= prob:
					continue
				var cx := (gx + _u01(hsh, 2)) * cell
				var cz := (gz + _u01(hsh, 3)) * cell
				var r := r_lo * pow(r_hi / r_lo, _u01(hsh, 4))
				if r < min_r:
					continue
				var infl := r * 1.9
				var i0 := maxi(int(ceilf((cx - infl - x0) / s)), 0)
				var i1 := mini(int(floorf((cx + infl - x0) / s)), w - 1)
				var j0 := maxi(int(ceilf((cz - infl - z0) / s)), 0)
				var j1 := mini(int(floorf((cz + infl - z0) / s)), hn - 1)
				if i0 > i1 or j0 > j1:
					continue
				var age := 0.35 + 0.65 * _u01(hsh, 5)  # 1 = fresh, lower = degraded
				var depth := 2.0 * r * _depth_ratio * age
				var rim := 2.0 * r * _rim_ratio * age
				var fresh := age > 0.82
				var inv_r := 1.0 / r
				var peak := r > 150.0
				for j in range(j0, j1 + 1):
					var dz := (z0 + j * s - cz) * inv_r
					for i in range(i0, i1 + 1):
						var dx := (x0 + i * s - cx) * inv_r
						var t2 := dx * dx + dz * dz
						if t2 >= 3.61:
							continue
						var t := sqrt(t2)
						var dh: float
						if t < 1.0:
							# bowl with a flat-ish floor rising to the rim crest at t = 1
							dh = -depth + (depth + rim) * t2 * t2 * (0.6 + 0.4 * t)
							if peak and t < 0.22:
								var q := 1.0 - t / 0.22
								dh += depth * 0.45 * q * q
						else:
							var q := 1.0 - (t - 1.0) / 0.9
							dh = rim * q * q * q
						var k := j * w + i
						hf[k] += dh
						if fresh and t < 1.7:
							bright[k] = maxf(bright[k], 1.0 - absf(t - 1.0) / 0.7)
