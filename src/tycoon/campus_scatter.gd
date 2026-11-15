@tool
class_name CampusScatter
extends MultiMeshInstance3D
## Scatters one mesh over the campus as a MultiMesh (grass tufts, flowers, bushes, trees,
## rocks, fence segments), editable in the editor: pick the mesh, the area or the path, the
## count and the look, then press "Scatter now". The result is stored in the scene's
## MultiMesh, so nothing is generated at runtime.
##   area mode   `count` instances in `area` (XZ, metres), optionally in `clusters` clumps,
##               avoiding the rectangles of `mask` (lots, roads, plaza) and each other
##   path mode   instances every `spacing` metres along `path` (fences, hedges, kerbs),
##               turned to follow it
## Each instance gets a random yaw (or the path's), a scale in scale_range and, when
## `tint_variation` > 0, a slight colour tint (Godot multiplies it into the vertex colour).

@export_tool_button("Scatter now") var scatter_button := scatter

@export var mask: CampusScatterMask
@export var seed_value := 1
@export_group("Area")
@export var area := Rect2(-68, -49, 148, 102)
@export var count := 100
## > 0: instances gather in this many clumps of cluster_radius
@export var clusters := 0
@export var cluster_radius := 4.0
## extra clearance from the mask rectangles (m)
@export var margin := 0.5
## minimum distance between instances (m, 0 = any)
@export var min_spacing := 0.0
@export_group("Path")
## when not empty: place along this polyline (XZ used, Y = height) instead of the area
@export var path: PackedVector3Array = PackedVector3Array()
@export var spacing := 4.0
@export var path_closed := false
@export_group("Look")
@export var height := 0.0
@export var scale_range := Vector2(0.85, 1.15)
## random yaw in area mode (radians); 0 keeps every instance aligned
@export var yaw_jitter := TAU
@export_range(0.0, 0.5, 0.01) var tint_variation := 0.0
@export var tint_color := Color(1, 1, 1, 1)
## optional: instances sit on top of this mesh (a hill, a dome) instead of at Y = 0;
## `height` is then added on top of the surface
@export var ground: MeshInstance3D
## with a `ground`: drop the instances that would not land on it (over the sea, off a terrace)
@export var skip_off_ground := false
@export_group("Walkers")
## The campus Cometlings walk around the instances (trees, bushes, rocks, fences) instead of
## through them (grass, flowers); see src/tycoon/campus_nav.gd.
@export var blocks_walkers := false
## Footprint of one instance: the mesh's bounding box on the ground, scaled by this (trees:
## the trunk and the low branches, not the whole crown).
@export_range(0.1, 1.5, 0.05) var walk_footprint := 1.0

## In the running game a scatter spread wider than this (m) is drawn in square chunks of this
## size (child MultiMeshInstance3D nodes, see _build_chunks).
const CHUNK_SIZE := 40.0

var _ground_tris: TriangleMesh
## runtime chunks and, per chunk, the indices of its instances in `multimesh` (ascending)
var _chunks: Array[MultiMeshInstance3D] = []
var _chunk_ids: Array[PackedInt32Array] = []


func _ready() -> void:
	if not Engine.is_editor_hint():
		_build_chunks()


## A MultiMesh is culled as one box: a scatter over the whole island (trees, terrace bushes,
## rocks) was drawn whole into every shadow cascade, into each face of a lamp's shadow cube and
## in every view, however little of it the camera or the light sees. The running game draws it
## as chunks of CHUNK_SIZE m instead, each culled on its own; this node keeps the MultiMesh
## (placed(), the walk grid, the graphics level's foliage share read and write it) but draws
## nothing itself. Same instances, same order, same look. Scatters with a visibility range stay
## whole (the range is measured to the node's box, so chunks would fade differently).
func _build_chunks() -> void:
	var mm := multimesh
	if mm == null or mm.mesh == null or mm.transform_format != MultiMesh.TRANSFORM_3D or mm.instance_count < 2:
		return
	if visibility_range_end > 0.0 or visibility_range_begin > 0.0:
		return
	var buf := mm.buffer
	var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
	var groups := {}   # Vector2i chunk -> Array of instance indices (ascending)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in mm.instance_count:
		var o := i * stride
		if o + stride > buf.size():
			return
		var p := Vector2(buf[o + 3], buf[o + 11])
		lo = lo.min(p)
		hi = hi.max(p)
		var key := Vector2i(floori(p.x / CHUNK_SIZE), floori(p.y / CHUNK_SIZE))
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(i)
	if groups.size() < 2 or (hi.x - lo.x <= CHUNK_SIZE and hi.y - lo.y <= CHUNK_SIZE):
		return
	for key: Vector2i in groups:
		var ids := PackedInt32Array(groups[key] as Array)
		var part := PackedFloat32Array()
		part.resize(ids.size() * stride)
		for j in ids.size():
			var src := ids[j] * stride
			for k in stride:
				part[j * stride + k] = buf[src + k]
		var cm := MultiMesh.new()
		cm.transform_format = MultiMesh.TRANSFORM_3D
		cm.use_colors = mm.use_colors
		cm.use_custom_data = mm.use_custom_data
		cm.mesh = mm.mesh
		cm.instance_count = ids.size()
		cm.buffer = part
		var c := MultiMeshInstance3D.new()
		c.name = "Chunk_%d_%d" % [key.x, key.y]
		c.multimesh = cm
		c.material_override = material_override
		c.material_overlay = material_overlay
		c.cast_shadow = cast_shadow
		c.layers = layers
		c.gi_mode = gi_mode
		c.transparency = transparency
		c.extra_cull_margin = extra_cull_margin
		c.lod_bias = lod_bias
		c.ignore_occlusion_culling = ignore_occlusion_culling
		add_child(c, false, Node.INTERNAL_MODE_BACK)
		_chunks.append(c)
		_chunk_ids.append(ids)
	# this node stops drawing: the chunks do it
	layers = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sync_chunks()


## True when the instances are drawn by chunks (the running game, wide scatters).
func is_chunked() -> bool:
	return not _chunks.is_empty()


## Carries the MultiMesh's visible_instance_count (the graphics level's foliage share: the
## first N instances) over to the chunks, so they show exactly the same instances.
func sync_chunks() -> void:
	if _chunks.is_empty() or multimesh == null:
		return
	var n := multimesh.visible_instance_count
	for i in _chunks.size():
		var ids := _chunk_ids[i]
		_chunks[i].multimesh.visible_instance_count = -1 if n < 0 else ids.bsearch(n)


## The instance transforms of the MultiMesh, read from its buffer (also works headless, where
## MultiMesh.get_instance_transform() returns identity).
func placed() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var mm := multimesh
	if mm == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
		return out
	var buf := mm.buffer
	var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
	for i in mm.instance_count:
		var o := i * stride
		if o + 12 > buf.size():
			break
		out.append(Transform3D(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
			Vector3(buf[o + 2], buf[o + 6], buf[o + 10]), Vector3(buf[o + 3], buf[o + 7], buf[o + 11])))
	return out


## (Re)builds the MultiMesh. Returns the number of instances.
func scatter() -> int:
	var mm := multimesh
	if mm == null:
		mm = MultiMesh.new()
		multimesh = mm
	var mesh := mm.mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var xf: Array[Transform3D] = []
	_ground_tris = ground.mesh.generate_triangle_mesh() if ground and ground.mesh else null
	if path.size() >= 2:
		xf = _along_path(rng)
	else:
		xf = _in_area(rng)
	var use_tint := tint_variation > 0.0 or tint_color != Color.WHITE
	mm.instance_count = 0
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_tint
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if use_tint:
			var k := 1.0 + rng.randf_range(-tint_variation, tint_variation)
			var c := Color(tint_color.r * k, tint_color.g * k * rng.randf_range(0.97, 1.03), tint_color.b * k, 1.0)
			mm.set_instance_color(i, c)
	return xf.size()


func _in_area(rng: RandomNumberGenerator) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var centres: Array[Vector2] = []
	for c in clusters:
		centres.append(_free_point(rng, area, cluster_radius))
	var placed: Array[Vector2] = []
	var tries := 0
	while out.size() < count and tries < count * 30:
		tries += 1
		var p: Vector2
		if clusters > 0:
			var c: Vector2 = centres[rng.randi() % centres.size()]
			var r := cluster_radius * sqrt(rng.randf())
			var a := rng.randf() * TAU
			p = c + Vector2(cos(a), sin(a)) * r
		else:
			p = Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if not area.has_point(p) or _masked(p, margin):
			continue
		if min_spacing > 0.0:
			var near := false
			for q in placed:
				if q.distance_squared_to(p) < min_spacing * min_spacing:
					near = true
					break
			if near:
				continue
		var gy := _ground_y(p)
		if skip_off_ground and is_nan(gy):
			continue
		placed.append(p)
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var b := Basis(Vector3.UP, rng.randf() * yaw_jitter).scaled(Vector3(s, s, s))
		out.append(Transform3D(b, Vector3(p.x, height + (0.0 if is_nan(gy) else gy), p.y)))
	return out


func _free_point(rng: RandomNumberGenerator, r: Rect2, keep: float) -> Vector2:
	for i in 60:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		if not _masked(p, keep * 0.5):
			return p
	return r.get_center()


func _along_path(rng: RandomNumberGenerator) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var pts := path.duplicate()
	if path_closed:
		pts.append(path[0])
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z)
		var length := seg.length()
		if length < 0.01:
			continue
		var n := maxi(1, int(round(length / spacing)))
		var yaw := atan2(-seg.y, seg.x)
		for k in n:
			var t := (float(k) + 0.5) / n
			var p := a.lerp(b, t)
			if _masked(Vector2(p.x, p.z), margin):
				continue
			var s := rng.randf_range(scale_range.x, scale_range.y)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(length / n / spacing, s, 1.0))
			out.append(Transform3D(basis, Vector3(p.x, height + p.y, p.z)))
	return out


## Height of the ground mesh's top under p (this node's local XZ), 0 without a ground, NAN
## when the ground is not under p.
func _ground_y(p: Vector2) -> float:
	if _ground_tris == null or not is_inside_tree() or not ground.is_inside_tree():
		return 0.0
	var to_ground := ground.global_transform.affine_inverse() * global_transform
	var from := to_ground * Vector3(p.x, 1000.0, p.y)
	var dir := to_ground.basis * Vector3.DOWN
	var hit := _ground_tris.intersect_ray(from, dir)
	if hit.is_empty():
		return NAN
	return (to_ground.affine_inverse() * (hit["position"] as Vector3)).y


func _masked(p: Vector2, m: float) -> bool:
	if mask == null:
		return false
	if mask.inside.size() >= 3 and not Geometry2D.is_point_in_polygon(p, mask.inside):
		return true
	for r: Rect2 in mask.avoid:
		if r.grow(m).has_point(p):
			return true
	return false
