extends SceneTree
## Headless tests of the voxel planet surfaces:
##  1. every PlanetSurfaceProfile in resources/planets loads, with NSSDC gravity
##  2. greedy meshing on small known grids (exact quad counts, area conservation,
##     winding) and on random grids (merged area == naive face area)
##  3. determinism: same seed -> identical chunk mesh hash; other seed -> different
##  4. streaming integration: a VoxelTerrain around a focus loads, builds collision
##     and a ray hits the exact voxel top; prints generation/meshing performance.
## Run: godot --headless --path . --script res://tests/test_voxel_terrain.gd

## NSSDC fact sheet surface gravity (m/s²), see docs/planet_surfaces.md
const GRAVITY := {
	"earth": 9.80, "moon": 1.62, "mars": 3.71, "mercury": 3.70, "europa": 1.315, "titan": 1.354,
}

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	_test_profiles()
	_test_greedy_known()
	_test_greedy_random()
	_test_determinism()
	_test_perf()
	await _test_scenes()
	await _test_streaming()
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL: " + msg)


func _profile(id: String) -> PlanetSurfaceProfile:
	return load("res://resources/planets/%s.tres" % id) as PlanetSurfaceProfile


# ------------------------------------------------------------------ 1. profiles

func _test_profiles() -> void:
	print("[profiles]")
	var dir := DirAccess.open("res://resources/planets")
	var found := 0
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var p := load("res://resources/planets/" + f) as PlanetSurfaceProfile
		_check(p != null, "%s is a PlanetSurfaceProfile" % f)
		if p == null:
			continue
		found += 1
		var id := String(p.id)
		_check(f.get_basename() == id, "%s id matches file name" % f)
		_check(GRAVITY.has(id), "%s has a reference gravity" % id)
		if GRAVITY.has(id):
			var g: float = GRAVITY[id]
			_check(absf(p.gravity - g) < 0.006, "%s gravity %.3f == %.3f" % [id, p.gravity, g])
		_check(p.continents != null and p.detail != null, "%s has noise layers" % id)
		_check(p.build_palette().size() == PlanetSurfaceProfile.MAT_COUNT * PlanetSurfaceProfile.SHADES, "%s palette" % id)
		_check(p.has_atmosphere == (p.surface_pressure_kpa > 0.0), "%s atmosphere flag vs pressure" % id)
		var gen := VoxelTerrainGenerator.new(p)
		var h := gen.height_at(0.0, 0.0)
		_check(is_finite(h) and absf(h) < 5000.0, "%s height at origin finite (%.1f)" % [id, h])
		if p.has_sea:
			_check(gen.flat_height > p.sea_level, "%s landing zone above the sea" % id)
		print("  %-8s g=%.3f m/s²  origin h=%.1f m" % [id, p.gravity, h])
	_check(found >= 6, "at least 6 profiles (found %d)" % found)


# ------------------------------------------------------------------ 2. greedy meshing

## Builds an (n+2)² grid from a callable h(i, j) over grid coords (border ring included).
func _grid(n: int, hf: Callable) -> Dictionary:
	var w := n + 2
	var heights := PackedInt32Array()
	var tops := PackedInt32Array()
	var subs := PackedInt32Array()
	heights.resize(w * w)
	tops.resize(w * w)
	subs.resize(w * w)
	for j in w:
		for i in w:
			heights[j * w + i] = hf.call(clampi(i, 1, n), clampi(j, 1, n))
			tops[j * w + i] = 1
			subs[j * w + i] = 7
	return {"heights": heights, "tops": tops, "subs": subs}


func _mesh(g: Dictionary, n: int, ao: bool, skirt: int = 0) -> Dictionary:
	return VoxelGreedyMesher.build(g["heights"], g["tops"], g["subs"], n, 1.0,
		{"palette": PackedColorArray([Color.WHITE]), "ao": ao, "skirt": skirt, "sub_voxels": 2})


## Area per face direction (+Y and sides) and winding check.
func _analyze(m: Dictionary) -> Dictionary:
	var arrays: Array = m["arrays"]
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var top_area := 0.0
	var side_area := 0.0
	var bad_winding := 0
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		var cr := (b - a).cross(c - a)
		var n := nr[idx[t]]
		# Godot front faces are clockwise: cross(b-a, c-a) points away from the viewer
		if cr.dot(n) >= 0.0:
			bad_winding += 1
		var area := cr.length() * 0.5
		if n.y > 0.5:
			top_area += area
		else:
			side_area += area
	return {"top": top_area, "side": side_area, "bad": bad_winding}


func _test_greedy_known() -> void:
	print("[greedy meshing: known grids]")
	var n := 4
	var flat := _grid(n, func(_i: int, _j: int) -> int: return 1)
	var m := _mesh(flat, n, true)
	_check(m["quads"] == 1, "flat 4x4 -> 1 quad (got %d)" % m["quads"])
	_check(m["naive_faces"] == 16, "flat 4x4 naive = 16 faces (got %d)" % m["naive_faces"])
	var step := _grid(n, func(i: int, _j: int) -> int: return 2 if i <= 2 else 1)
	m = _mesh(step, n, false)
	_check(m["quads"] == 3, "step without AO -> 3 quads: 2 tops + 1 side (got %d)" % m["quads"])
	_check(m["naive_faces"] == 20, "step naive = 16 tops + 4 sides (got %d)" % m["naive_faces"])
	m = _mesh(step, n, true)
	_check(m["quads"] == 4, "step with AO -> 4 quads (AO strip splits the low top) (got %d)" % m["quads"])
	var a := _analyze(m)
	_check(is_equal_approx(a["top"], 16.0) and is_equal_approx(a["side"], 4.0), "step areas 16/4 (got %s/%s)" % [a["top"], a["side"]])
	_check(a["bad"] == 0, "step winding clockwise (%d bad)" % a["bad"])
	# pyramid: 1 column of height 3 in the middle of a 3x3 at height 1
	var pyr := _grid(3, func(i: int, j: int) -> int: return 3 if i == 2 and j == 2 else 1)
	m = _mesh(pyr, 3, false)
	_check(m["naive_faces"] == 9 + 8, "pillar naive = 9 tops + 4 sides x 2 voxels (got %d)" % m["naive_faces"])
	_check(m["quads"] == 5 + 8, "pillar quads = 5 greedy tops + 4 sides x 2 colors (top voxel, subsurface) (got %d)" % m["quads"])
	# skirts add border faces only
	m = _mesh(flat, n, false, 2)
	_check(m["naive_faces"] == 16 + 4 * 4 * 2, "skirt adds 2 voxels on each border column side (got %d)" % m["naive_faces"])
	_check(m["quads"] == 1 + 4 * 2, "skirts merge to 2 quads per side: top color + subsurface (got %d)" % m["quads"])


func _test_greedy_random() -> void:
	print("[greedy meshing: random grids]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var total_q := 0
	var total_n := 0
	for trial in 20:
		var n := 8 + (trial % 3) * 8
		var hs := {}
		var g := _grid(n, func(i: int, j: int) -> int:
			var k := Vector2i(i, j)
			if not hs.has(k):
				hs[k] = rng.randi_range(0, 5) if trial % 2 == 0 else int(3.0 + 2.5 * sin(i * 0.7) + 2.0 * cos(j * 0.5))
			return hs[k])
		for ao in [false, true]:
			var m := _mesh(g, n, ao, trial % 3)
			var a := _analyze(m)
			var naive: int = m["naive_faces"]
			_check(is_equal_approx(a["top"], float(n * n)), "trial %d top area %.1f == %d" % [trial, a["top"], n * n])
			_check(is_equal_approx(a["side"], float(naive - n * n)), "trial %d side area %.1f == %d" % [trial, a["side"], naive - n * n])
			_check(a["bad"] == 0, "trial %d winding" % trial)
			total_q += m["quads"]
			total_n += naive
	print("  random grids: %d quads vs %d naive faces (%.0f%% fewer)" % [total_q, total_n, 100.0 * (1.0 - float(total_q) / total_n)])


# ------------------------------------------------------------------ 3. determinism

func _chunk_hash(gen: VoxelTerrainGenerator, key: Vector3i) -> String:
	var opts := {"palette": gen.palette, "ao": true, "ao_strength": 0.9, "skirt": 3, "sub_voxels": 2, "strata_m": 3.0}
	var m := VoxelTerrain.build_chunk_data(gen, key, 32, opts)
	var arrays: Array = m["arrays"]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(arrays[Mesh.ARRAY_VERTEX]))
	ctx.update(var_to_bytes(arrays[Mesh.ARRAY_COLOR]))
	ctx.update(var_to_bytes(arrays[Mesh.ARRAY_INDEX]))
	return ctx.finish().hex_encode()


func _test_determinism() -> void:
	print("[determinism]")
	for id in ["moon", "earth", "europa"]:
		var p1 := _profile(id)
		var p2 := (load("res://resources/planets/%s.tres" % id) as PlanetSurfaceProfile).duplicate(true) as PlanetSurfaceProfile
		var g1 := VoxelTerrainGenerator.new(p1)
		var g2 := VoxelTerrainGenerator.new(p2)
		for key in [Vector3i(0, 0, 0), Vector3i(3, -2, 0), Vector3i(-1, 1, 2), Vector3i(1, 0, 5)]:
			var h1 := _chunk_hash(g1, key)
			var h2 := _chunk_hash(g2, key)
			_check(h1 == h2, "%s chunk %s deterministic" % [id, key])
		p2.terrain_seed += 1
		var g3 := VoxelTerrainGenerator.new(p2)
		_check(_chunk_hash(g3, Vector3i(3, -2, 0)) != _chunk_hash(g1, Vector3i(3, -2, 0)), "%s other seed differs" % id)
		print("  %s chunk (3,-2,lod0) sha256 %s…" % [id, _chunk_hash(g1, Vector3i(3, -2, 0)).substr(0, 16)])


# ------------------------------------------------------------------ 4. performance + streaming

func _test_perf() -> void:
	print("[single-thread chunk cost, 32x32 columns]")
	for id in ["earth", "moon", "mars", "mercury", "europa", "titan"]:
		var gen := VoxelTerrainGenerator.new(_profile(id))
		var line := "  %-8s" % id
		var q_all := 0
		var n_all := 0
		for lod in [0, 2, 4, 6]:
			var opts := {"palette": gen.palette, "ao": true, "ao_strength": 0.9, "skirt": 3,
				"sub_voxels": maxi(int(roundf(gen.subsurface_depth / float(1 << lod))), 1), "strata_m": gen.strata_thickness}
			var t_sample := 0
			var t_mesh := 0
			var runs := 6
			for r in runs:
				var key := Vector3i(r * 3 - 7, (r * 5) % 7 - 3, lod)
				var s := float(1 << lod)
				var t0 := Time.get_ticks_usec()
				var d := gen.sample_chunk(key.x * 32 * s, key.y * 32 * s, s, 32)
				var t1 := Time.get_ticks_usec()
				var m := VoxelGreedyMesher.build(d["heights"], d["tops"], d["subs"], 32, s, opts)
				var t2 := Time.get_ticks_usec()
				t_sample += t1 - t0
				t_mesh += t2 - t1
				q_all += m["quads"]
				n_all += m["naive_faces"]
			line += "  L%d %.1f+%.1f ms" % [lod, t_sample / 1000.0 / runs, t_mesh / 1000.0 / runs]
		line += "  (sample+mesh)  greedy %d vs naive %d quads: -%.0f%%" % [q_all, n_all, 100.0 * (1.0 - float(q_all) / n_all)]
		print(line)


func _test_scenes() -> void:
	print("[scenes]")
	for f in DirAccess.get_files_at("res://scenes/surface"):
		if not f.ends_with(".tscn"):
			continue
		var ps := load("res://scenes/surface/" + f) as PackedScene
		_check(ps != null, "%s loads" % f)
		if ps == null:
			continue
		var node := ps.instantiate()
		root.add_child(node)
		for i in 3:
			await process_frame
		var surf: PlanetSurface = node as PlanetSurface
		if surf == null:
			surf = node.get_node_or_null("PlanetSurface") as PlanetSurface
		if surf:
			_check(surf.profile != null and surf.terrain.generator != null, "%s applies a profile" % f)
			_check(surf.world_env.environment.sky != null, "%s has a sky" % f)
			if f.begins_with(String(surf.profile.id)):
				_check(f == "%s_surface.tscn" % surf.profile.id, "%s uses its own profile" % f)
		print("  %s ok" % f)
		node.queue_free()
		await process_frame


func _test_streaming() -> void:
	print("[streaming integration]")
	var scene := (load("res://scenes/surface/planet_surface.tscn") as PackedScene).instantiate() as PlanetSurface
	scene.profile = _profile("moon")
	var focus := Node3D.new()
	scene.add_child(focus)
	root.add_child(scene)
	scene.set_focus(focus)
	var terrain := scene.terrain
	var ground := terrain.get_height(5.5, 7.5)
	focus.position = Vector3(5.5, ground + 20.0, 7.5)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		frames += 1
		if Time.get_ticks_msec() - t0 > 400 and terrain.is_idle():
			break
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	var st := terrain.get_stats()
	print("  moon: %d chunks %s, %d collision chunks, %d tris (naive %d) in %.2f s (%d frames, %d threads), avg %.1f ms/chunk/thread" % [
		st["chunks"], st["per_lod"], st["collision_chunks"], st["tris"], st["naive_tris"], dt, frames,
		OS.get_processor_count(), st["gen_ms_avg"]])
	_check(terrain.is_idle(), "terrain finished streaming")
	_check(st["chunks"] > 50, "many chunks loaded (%d)" % st["chunks"])
	_check(st["tris"] > 0 and st["tris"] < st["naive_tris"], "greedy tris below naive")
	_check(terrain.is_collision_ready(focus.global_position, 20.0), "collision around focus")
	for f in 3:
		await physics_frame
	var space := scene.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(5.5, ground + 50.0, 7.5), Vector3(5.5, ground - 50.0, 7.5))
	var hit := space.intersect_ray(q)
	_check(not hit.is_empty(), "ray hits terrain collision")
	if not hit.is_empty():
		var hy: float = (hit["position"] as Vector3).y
		_check(absf(hy - ground) < 0.01, "collision at voxel top (%.3f vs %.3f)" % [hy, ground])
	_check(is_equal_approx(PhysicsServer3D.area_get_param(scene.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY), 1.62),
		"world gravity set to the Moon's")
	# move far away: old chunks must be released and the new area streamed
	focus.position = Vector3(3000.0, terrain.get_height(3000.0, 0.0) + 20.0, 0.0)
	t0 = Time.get_ticks_msec()
	frames = 0
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		frames += 1
		if Time.get_ticks_msec() - t0 > 400 and terrain.is_idle():
			break
	var st2 := terrain.get_stats()
	print("  after 3 km jump: %d chunks, %d collision chunks in %.2f s" % [st2["chunks"], st2["collision_chunks"], (Time.get_ticks_msec() - t0) / 1000.0])
	_check(absf(st2["chunks"] - st["chunks"]) < st["chunks"] * 0.5, "chunk count stays bounded after moving")
	_check(terrain.is_collision_ready(focus.global_position, 20.0), "collision follows the focus")
	scene.queue_free()
	await process_frame
