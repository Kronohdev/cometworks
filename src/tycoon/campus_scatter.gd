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
		placed.append(p)
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var b := Basis(Vector3.UP, rng.randf() * yaw_jitter).scaled(Vector3(s, s, s))
		out.append(Transform3D(b, Vector3(p.x, height, p.y)))
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


func _masked(p: Vector2, m: float) -> bool:
	if mask == null:
		return false
	for r: Rect2 in mask.avoid:
		if r.grow(m).has_point(p):
			return true
	return false
