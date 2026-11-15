@tool
class_name VoxelTerrain
extends Node3D
## Streaming, LOD'd, chunked voxel terrain for one PlanetSurfaceProfile.
##
## Pipeline (see docs/planet_surfaces.md):
##  1. Every `update_interval` a quadtree is walked around the focus node: a node
##     of size S (chunk_size voxels of 2^lod meters) splits while the focus is
##     closer than lod_factor·S (hysteresis on merge). Leaves = wanted chunks.
##  2. Missing chunks are queued nearest-first and generated on WorkerThreadPool
##     (height sampling, materials, greedy meshing, props: all off the main thread).
##  3. The main thread turns finished arrays into ArrayMeshes on pooled
##     MeshInstance3D nodes within `upload_budget_ms` per frame.
##  4. Old chunks are removed only once the area they cover is fully shown by
##     newer chunks (no holes while LOD changes), or when out of range.
##  5. Collision: separate 1 m trimesh chunks within collision_radius of the focus.
## The 1 m LOD adds half-block step slabs in front of every 1-block rise (VoxelGreedyMesher
## "steps"), which RoverController.surface() drives on.
## Culling: every chunk is its own MeshInstance3D, so Godot frustum-culls per
## chunk; chunks beyond view_distance are never built; buried faces are never
## meshed; far LODs do not cast shadows.

signal profile_applied

@export var profile: PlanetSurfaceProfile:
	set = set_profile
## Node the terrain streams around (camera, lander...). Empty = this node.
@export var focus_path: NodePath
## Single material for every chunk (shaders/surface_terrain.gdshader).
@export var material: Material

@export_group("Chunks and LOD")
## Columns per chunk side (every LOD uses the same count, voxels grow 2× per LOD).
@export_range(8, 64, 8) var chunk_size: int = 32
## Coarsest LOD: voxel size 2^max_lod m.
@export_range(0, 9) var max_lod: int = 7
## Split a node while distance < lod_factor × node size. Higher = more detail.
@export_range(1.0, 6.0, 0.05) var lod_factor: float = 2.0
## Merge back only beyond lod_factor × hysteresis (prevents LOD flicker).
@export_range(1.0, 2.0, 0.01) var lod_hysteresis: float = 1.15
@export var view_distance: float = 6000.0
## Voxels each border column extends downwards to hide LOD cracks.
@export_range(0, 16) var skirt_voxels: int = 3

@export_group("Look")
@export var ambient_occlusion: bool = true
@export_range(0.0, 1.0, 0.01) var ao_strength: float = 0.9
## Chunks with lod <= this cast shadows (far ones are outside the shadow range anyway).
@export_range(0, 9) var shadow_max_lod: int = 2
## Trees / boulders / ice blocks from the profile's Props group.
@export var props_enabled: bool = true

@export_group("Streaming")
@export var update_interval: float = 0.12
## Max chunk jobs in flight (0 = CPU threads - 2).
@export var max_jobs_in_flight: int = 0
## Main-thread time per frame for attaching finished chunks.
@export var upload_budget_ms: float = 2.5

@export_group("Collision")
@export var collision_enabled: bool = true
## Radius (m) around the focus with 1 m voxel trimesh collision.
@export var collision_radius: float = 56.0
@export_flags_3d_physics var collision_layer: int = 1

@export_group("Editor preview")
## Generate chunks while editing the scene (not saved into the scene).
@export var editor_preview: bool = true:
	set(v):
		editor_preview = v
		if is_inside_tree() and Engine.is_editor_hint():
			rebuild()
@export var editor_preview_distance: float = 1200.0
@export_range(0, 9) var editor_max_lod: int = 5
## Stream around the editor's 3D camera instead of this node.
@export var editor_follow_camera: bool = false
@export_tool_button("Rebuild terrain", "Reload") var _rebuild_button: Callable = rebuild

var generator: VoxelTerrainGenerator
var props: VoxelPropLibrary
## Authored terrain features (SurfaceTerrainFeature.to_feature() dicts) the PlanetSurface
## collects from its scene; applied with the profile (set_features rebuilds).
var features: Array = []
## Discs (x, z, radius) kept free of props: set pieces, points of interest (PlanetSurface).
var prop_exclusions := PackedVector3Array()

var _epoch := 0
var _chunks := {}  # Vector3i(cx, cz, lod) -> MeshInstance3D
var _chunk_info := {}  # Vector3i -> Vector2i(quads, naive_faces)
var _pending := {}  # Vector3i -> true (job in flight)
var _queue: Array[Vector3i] = []
var _leaves := {}  # desired leaves
var _inner := {}  # desired inner (split) nodes
var _tasks: Array[int] = []
var _results: Array[Dictionary] = []
var _mutex := Mutex.new()
var _pool: Array[MeshInstance3D] = []
var _col_bodies := {}  # Vector2i -> StaticBody3D
var _col_pending := {}
var _col_wanted := {}
var _col_queue: Array[Vector2i] = []
var _timer := 0.0
var _chunk_root: Node3D
var _col_root: Node3D
var _focus_cache := Vector3.ZERO
var _prune_dirty := false

# stats
var gen_count := 0
var gen_usec_total := 0
var gen_usec_last := 0
var tris_total := 0
var naive_tris_total := 0
## Main-thread cost of the terrain per frame (exponential average / last max).
var main_ms_avg := 0.0
var main_ms_max := 0.0


func _ready() -> void:
	_chunk_root = Node3D.new()
	_chunk_root.name = "Chunks"
	add_child(_chunk_root, false, Node.INTERNAL_MODE_BACK)
	_col_root = Node3D.new()
	_col_root.name = "Collision"
	add_child(_col_root, false, Node.INTERNAL_MODE_BACK)
	if profile and generator == null:
		_apply_profile()


func _exit_tree() -> void:
	_wait_all_tasks()


func set_profile(p: PlanetSurfaceProfile) -> void:
	if profile and profile.changed.is_connected(_on_profile_changed):
		profile.changed.disconnect(_on_profile_changed)
	profile = p
	if profile and Engine.is_editor_hint():
		profile.changed.connect(_on_profile_changed)
	if is_inside_tree():
		_apply_profile()


func _on_profile_changed() -> void:
	rebuild()


## New authored features: drops every chunk and regenerates.
func set_features(list: Array) -> void:
	features = list
	if is_inside_tree() and profile:
		_apply_profile()


## Drops every chunk and regenerates from the current profile.
func rebuild() -> void:
	if is_inside_tree():
		_apply_profile()


func _apply_profile() -> void:
	_epoch += 1
	_clear_all()
	generator = VoxelTerrainGenerator.new(profile) if profile else null
	if generator and not features.is_empty():
		generator.set_features(features)
	props = VoxelPropLibrary.new(profile) if profile and props_enabled else null
	if props:
		props.exclusions = prop_exclusions
	_timer = update_interval
	profile_applied.emit()


func _clear_all() -> void:
	for key in _chunks:
		_recycle(_chunks[key])
	_chunks.clear()
	_chunk_info.clear()
	_pending.clear()
	_queue.clear()
	_leaves.clear()
	_inner.clear()
	for k in _col_bodies:
		(_col_bodies[k] as Node).queue_free()
	_col_bodies.clear()
	_col_pending.clear()
	_col_wanted.clear()
	_col_queue.clear()
	tris_total = 0
	naive_tris_total = 0
	gen_count = 0
	gen_usec_total = 0
	_mutex.lock()
	_results.clear()
	_mutex.unlock()


func _active() -> bool:
	if generator == null:
		return false
	if Engine.is_editor_hint():
		return editor_preview
	return true


# ------------------------------------------------------------------ public API

## World height of the 1 m voxel surface at (x, z) (for spawning/landing).
func get_height(x: float, z: float) -> float:
	if generator == null:
		return 0.0
	return generator.voxel_top_at(x - global_position.x, z - global_position.z, 1.0) + global_position.y


## True when no job is queued, running or waiting for upload.
func is_idle() -> bool:
	_mutex.lock()
	var r := _results.is_empty()
	_mutex.unlock()
	if _focus_position().distance_to(_focus_cache) > 1.0:
		return false
	return r and _tasks.is_empty() and _queue.is_empty() and _col_queue.is_empty() and not _prune_dirty


## True when collision exists around a world position (radius <= collision_radius).
func is_collision_ready(world_pos: Vector3, radius: float = 8.0) -> bool:
	var p := world_pos - global_position
	var cs := float(chunk_size)
	for cz in range(int(floorf((p.z - radius) / cs)), int(floorf((p.z + radius) / cs)) + 1):
		for cx in range(int(floorf((p.x - radius) / cs)), int(floorf((p.x + radius) / cs)) + 1):
			if not _col_bodies.has(Vector2i(cx, cz)):
				return false
	return true


func get_stats() -> Dictionary:
	var per_lod := PackedInt32Array()
	per_lod.resize(max_lod + 1)
	for key: Vector3i in _chunks:
		if key.z <= max_lod:
			per_lod[key.z] += 1
	return {
		"chunks": _chunks.size(),
		"per_lod": per_lod,
		"jobs": _tasks.size(),
		"queued": _queue.size() + _col_queue.size(),
		"tris": tris_total,
		"naive_tris": naive_tris_total,
		"gen_ms_avg": (gen_usec_total / 1000.0 / gen_count) if gen_count > 0 else 0.0,
		"gen_ms_last": gen_usec_last / 1000.0,
		"gen_count": gen_count,
		"collision_chunks": _col_bodies.size(),
		"main_ms_avg": main_ms_avg,
		"main_ms_max": main_ms_max,
	}


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if not _active():
		if Engine.is_editor_hint() and not _chunks.is_empty():
			_clear_all()
		return
	var t0 := Time.get_ticks_usec()
	_collect_tasks()
	_upload_results()
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		_focus_cache = _focus_position()
		_update_desired(_focus_cache)
		_update_collision_wanted(_focus_cache)
		_prune_dirty = true
	if _prune_dirty:
		_prune()
	_schedule()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	main_ms_avg = lerpf(main_ms_avg, ms, 0.05)
	main_ms_max = maxf(main_ms_max * 0.995, ms)


func _focus_position() -> Vector3:
	var p := global_position
	if Engine.is_editor_hint():
		if editor_follow_camera:
			var ei := Engine.get_singleton(&"EditorInterface")
			if ei:
				var vp: SubViewport = ei.call("get_editor_viewport_3d", 0)
				if vp and vp.get_camera_3d():
					p = vp.get_camera_3d().global_position
	elif not focus_path.is_empty():
		var n := get_node_or_null(focus_path) as Node3D
		if n:
			p = n.global_position
	return p - global_position


func _eff_max_lod() -> int:
	return mini(max_lod, editor_max_lod) if Engine.is_editor_hint() else max_lod


func _eff_view() -> float:
	return editor_preview_distance if Engine.is_editor_hint() else view_distance


func _update_desired(f: Vector3) -> void:
	var prev_inner := _inner
	_leaves = {}
	_inner = {}
	var top := _eff_max_lod()
	var vd := _eff_view()
	var ground := generator.height_at(f.x, f.z)
	var dy := maxf(absf(f.y - ground) - 2.0, 0.0)
	var root_size := float(chunk_size << top)
	var x0 := int(floorf((f.x - vd) / root_size))
	var x1 := int(floorf((f.x + vd) / root_size))
	var z0 := int(floorf((f.z - vd) / root_size))
	var z1 := int(floorf((f.z + vd) / root_size))
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			_walk(Vector3i(cx, cz, top), f, dy, vd, prev_inner)
	# queue: missing leaves, nearest first
	var missing: Array = []
	for key: Vector3i in _leaves:
		if not _chunks.has(key) and not _pending.has(key):
			missing.append([_leaves[key], key])
	missing.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_queue.clear()
	for m: Array in missing:
		_queue.append(m[1])


func _walk(key: Vector3i, f: Vector3, dy: float, vd: float, prev_inner: Dictionary) -> void:
	var size := float(chunk_size << key.z)
	var minx := key.x * size
	var minz := key.y * size
	var dx := maxf(maxf(minx - f.x, f.x - (minx + size)), 0.0)
	var dz := maxf(maxf(minz - f.z, f.z - (minz + size)), 0.0)
	var dxz := sqrt(dx * dx + dz * dz)
	if dxz > vd:
		return
	var d := sqrt(dxz * dxz + dy * dy)
	var thr := lod_factor * size * (lod_hysteresis if prev_inner.has(key) else 1.0)
	if key.z > 0 and d < thr:
		_inner[key] = true
		var cx := key.x * 2
		var cz := key.y * 2
		for k in 4:
			_walk(Vector3i(cx + (k & 1), cz + (k >> 1), key.z - 1), f, dy, vd, prev_inner)
	else:
		_leaves[key] = d


## True when the area of `key` is fully drawn by wanted, ready chunks.
func _covered(key: Vector3i) -> bool:
	if _leaves.has(key):
		return _chunks.has(key)
	if _inner.has(key):
		var cx := key.x * 2
		var cz := key.y * 2
		for k in 4:
			if not _covered(Vector3i(cx + (k & 1), cz + (k >> 1), key.z - 1)):
				return false
		return true
	for l in range(key.z + 1, _eff_max_lod() + 1):
		var sh := l - key.z
		var anc := Vector3i(key.x >> sh, key.y >> sh, l)
		if _leaves.has(anc):
			return _chunks.has(anc)
	return true  # outside the wanted area


func _prune() -> void:
	_prune_dirty = false
	var drop: Array[Vector3i] = []
	for key: Vector3i in _chunks:
		if not _leaves.has(key) and _covered(key):
			drop.append(key)
	for key in drop:
		var info: Vector2i = _chunk_info.get(key, Vector2i.ZERO)
		tris_total -= info.x * 2
		naive_tris_total -= info.y * 2
		_chunk_info.erase(key)
		_recycle(_chunks[key])
		_chunks.erase(key)


func _max_jobs() -> int:
	# leave two hardware threads for the main and render threads
	return max_jobs_in_flight if max_jobs_in_flight > 0 else maxi(2, OS.get_processor_count() - 2)


func _mesh_opts(lod: int, collision: bool) -> Dictionary:
	var s := float(1 << lod)
	return {
		"palette": generator.palette,
		"ao": ambient_occlusion,
		"ao_strength": ao_strength,
		"skirt": skirt_voxels,
		"sub_voxels": maxi(int(roundf(generator.subsurface_depth / s)), 1),
		"strata_m": generator.strata_thickness,
		"collision": collision,
		"props": props,
		# half-block step slabs on the 1 m voxels (the rover drives the same shape)
		"steps": lod == 0,
	}


func _schedule() -> void:
	var cap := _max_jobs()
	# collision near the focus first (a lander may be waiting), then visuals
	while _tasks.size() < cap and not _col_queue.is_empty():
		var c: Vector2i = _col_queue.pop_front()
		if not _col_wanted.has(c) or _col_bodies.has(c) or _col_pending.has(c):
			continue
		_col_pending[c] = true
		var key := Vector3i(c.x, c.y, 0)
		_tasks.append(WorkerThreadPool.add_task(
			_run_job.bind(key, true, generator, _epoch, chunk_size, _mesh_opts(0, true)), false, "voxel collision"))
	while _tasks.size() < cap and not _queue.is_empty():
		var key: Vector3i = _queue.pop_front()
		if not _leaves.has(key) or _chunks.has(key) or _pending.has(key):
			continue
		_pending[key] = true
		_tasks.append(WorkerThreadPool.add_task(
			_run_job.bind(key, false, generator, _epoch, chunk_size, _mesh_opts(key.z, false)), false, "voxel chunk"))


## Runs on a worker thread: touches no node, only its arguments and _results.
func _run_job(key: Vector3i, collision: bool, gen: VoxelTerrainGenerator, epoch: int, n: int, opts: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var res := build_chunk_data(gen, key, n, opts)
	if collision:
		res.erase("arrays")
		res.erase("prop_arrays")
	res["key"] = key
	res["collision"] = collision
	res["epoch"] = epoch
	res["usec"] = Time.get_ticks_usec() - t0
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()


## Samples and meshes one chunk (pure; used by jobs and tests).
static func build_chunk_data(gen: VoxelTerrainGenerator, key: Vector3i, n: int, opts: Dictionary) -> Dictionary:
	var s := float(1 << key.z)
	var size := n * s
	var d := gen.sample_chunk(key.x * size, key.y * size, s, n)
	var m := VoxelGreedyMesher.build(d["heights"], d["tops"], d["subs"], n, s, opts)
	m["hmin"] = d["hmin"]
	m["hmax"] = d["hmax"]
	m["props"] = 0
	var lib: VoxelPropLibrary = opts.get("props")
	if lib and lib.kind != VoxelPropLibrary.Kind.NONE:
		var pv := PackedVector3Array()
		var pn := PackedVector3Array()
		var pc := PackedColorArray()
		m["props"] = lib.append_chunk(pv, pn, pc, d["heights"], d["tops"], n, s, key.x * size, key.y * size, key.z)
		if pv.size() > 0:
			var pa := []
			pa.resize(Mesh.ARRAY_MAX)
			pa[Mesh.ARRAY_VERTEX] = pv
			pa[Mesh.ARRAY_NORMAL] = pn
			pa[Mesh.ARRAY_COLOR] = pc
			m["prop_arrays"] = pa
			# props are not merged: count them in both totals so the ratio stays honest
			m["quads"] = (m["quads"] as int) + pv.size() / 6
			m["naive_faces"] = (m["naive_faces"] as int) + pv.size() / 6
			if m.has("faces"):
				(m["faces"] as PackedVector3Array).append_array(pv)
	return m


func _collect_tasks() -> void:
	var i := 0
	while i < _tasks.size():
		var id := _tasks[i]
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_tasks.remove_at(i)
		else:
			i += 1


func _wait_all_tasks() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()


func _upload_results() -> void:
	var t_end := Time.get_ticks_usec() + int(upload_budget_ms * 1000.0)
	var col_budget := 2
	while Time.get_ticks_usec() < t_end:
		_mutex.lock()
		var res: Dictionary = {} if _results.is_empty() else _results.pop_front()
		_mutex.unlock()
		if res.is_empty():
			break
		if res["epoch"] != _epoch:
			continue
		var key: Vector3i = res["key"]
		gen_count += 1
		gen_usec_last = res["usec"]
		gen_usec_total += gen_usec_last
		if res["collision"]:
			var c := Vector2i(key.x, key.y)
			_col_pending.erase(c)
			if _col_wanted.has(c) and not _col_bodies.has(c):
				_add_collision(c, res["faces"])
				col_budget -= 1
				if col_budget <= 0:
					break
			continue
		_pending.erase(key)
		if not _leaves.has(key) or _chunks.has(key):
			continue
		# the ArrayMesh is built here: RenderingServer resource creation from
		# worker threads raced with the renderer (RID errors), uploads are cheap
		var mesh: ArrayMesh = null
		var arrays: Array = res["arrays"]
		if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var pa: Array = res.get("prop_arrays", [])
			if not pa.is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pa)
		var mi := _take_instance()
		var s := float(1 << key.z)
		var size := chunk_size * s
		mi.position = Vector3(key.x * size, 0.0, key.y * size)
		mi.mesh = mesh
		mi.set_instance_shader_parameter(&"voxel_size", s)
		mi.set_instance_shader_parameter(&"lod_level", float(key.z))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key.z <= shadow_max_lod \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = true
		_chunks[key] = mi
		var q: int = res["quads"]
		var nv: int = res["naive_faces"]
		_chunk_info[key] = Vector2i(q, nv)
		tris_total += q * 2
		naive_tris_total += nv * 2
		_prune_dirty = true


func _take_instance() -> MeshInstance3D:
	var mi: MeshInstance3D
	if _pool.is_empty():
		mi = MeshInstance3D.new()
		mi.material_override = material
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_chunk_root.add_child(mi)
	else:
		mi = _pool.pop_back()
		mi.material_override = material
	return mi


func _recycle(mi: MeshInstance3D) -> void:
	mi.mesh = null
	mi.visible = false
	if _pool.size() < 256:
		_pool.append(mi)
	else:
		mi.queue_free()


# ------------------------------------------------------------------ collision

func _update_collision_wanted(f: Vector3) -> void:
	_col_wanted.clear()
	_col_queue.clear()
	if not collision_enabled or Engine.is_editor_hint():
		for c in _col_bodies.keys():
			(_col_bodies[c] as Node).queue_free()
		_col_bodies.clear()
		return
	var cs := float(chunk_size)
	var r := collision_radius
	var list: Array = []
	for cz in range(int(floorf((f.z - r) / cs)), int(floorf((f.z + r) / cs)) + 1):
		for cx in range(int(floorf((f.x - r) / cs)), int(floorf((f.x + r) / cs)) + 1):
			var dx := maxf(maxf(cx * cs - f.x, f.x - (cx + 1) * cs), 0.0)
			var dz := maxf(maxf(cz * cs - f.z, f.z - (cz + 1) * cs), 0.0)
			var d := sqrt(dx * dx + dz * dz)
			if d <= r:
				var c := Vector2i(cx, cz)
				_col_wanted[c] = true
				if not _col_bodies.has(c) and not _col_pending.has(c):
					list.append([d, c])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e: Array in list:
		_col_queue.append(e[1])
	# drop bodies well outside the radius (hysteresis: 1.5 chunk)
	for c: Vector2i in _col_bodies.keys():
		if _col_wanted.has(c):
			continue
		var dx := maxf(maxf(c.x * cs - f.x, f.x - (c.x + 1) * cs), 0.0)
		var dz := maxf(maxf(c.y * cs - f.z, f.z - (c.y + 1) * cs), 0.0)
		if sqrt(dx * dx + dz * dz) > r + cs * 1.5:
			(_col_bodies[c] as Node).queue_free()
			_col_bodies.erase(c)


func _add_collision(c: Vector2i, faces: PackedVector3Array) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = collision_layer
	body.collision_mask = 0
	body.position = Vector3(c.x * chunk_size, 0.0, c.y * chunk_size)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	_col_root.add_child(body)
	_col_bodies[c] = body
