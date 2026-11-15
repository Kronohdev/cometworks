@tool
class_name PartInstance
extends Node3D
## One placed (or held) part. The attach tree mirrors the scene tree: attached
## children are Node3D children, so moving a part moves its subtree. Runs in the
## editor too (@tool), so saved vessel scenes (scenes/examples/*.tscn) show the
## assembled rocket node by node.
##
## Picking is analytic (ray vs. cylinder or box built from the model bounds), so it
## does not depend on physics bodies being in sync.

## Catalog id from data/parts.json; changing it in the inspector swaps the model.
@export var part_id: String = "":
	set(v):
		part_id = v
		data = PartDB.get_part(v)
		if is_inside_tree():
			_build()
## Node on the parent this part is attached to: "top", "bottom", "slot:N", "side", "surface".
@export var parent_node_name: String = ""
## Node on this part used for the attachment: "top", "bottom", "sidechild", "surface".
@export var own_node_name: String = ""
## Parts placed together by symmetry share the same tag (-1 = no symmetry). Used by saved scenes.
@export var sym_tag: int = -1

const VOXEL_MATERIAL := preload("res://scenes/hangar/voxel_part.tres")

var data: Dictionary = {}
var aabb: AABB = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
## Runtime list of PartInstances placed together by symmetry (empty if none).
var sym_group: Array = []
var pickable := true

var _model: Node3D


static func create(id: String) -> PartInstance:
	var pi := PartInstance.new()
	pi.part_id = id
	pi.name = id
	pi._build()
	return pi


func _ready() -> void:
	if _model == null and part_id != "":
		_build()


func _build() -> void:
	if _model:
		_model.free()
		_model = null
	var scene := PartDB.model_scene(part_id)
	if scene:
		_model = scene.instantiate()
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		mi.mesh = bm
		mi.position.y = 0.5
		_model = mi
	_model.name = "_Model"
	# internal child: never saved into scenes, never treated as an attached part
	add_child(_model, false, Node.INTERNAL_MODE_FRONT)
	apply_voxel_material(_model)
	aabb = _compute_aabb(_model)


## Greedy-meshed part models (UV2 present) use the shared voxel material, which
## rebuilds the per-voxel color jitter in the shader (one material for every part).
static func apply_voxel_material(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false) + ([root] if root is MeshInstance3D else []):
		var mi := n as MeshInstance3D
		if mi.mesh and mi.mesh.get_surface_count() > 0 \
				and (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0:
			mi.material_override = VOXEL_MATERIAL


static func _compute_aabb(n: Node) -> AABB:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).transform * (n as MeshInstance3D).get_aabb()
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


static var _model_aabbs: Dictionary = {}


## The bounds a part's model gives it (what _build() sets `aabb` to), cached per part id: the
## real size of a part without building its model (a box part: the 1 m placeholder).
static func model_aabb(id: String) -> AABB:
	if not _model_aabbs.has(id):
		var scene := PartDB.model_scene(id)
		var box := AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
		if scene:
			var m := scene.instantiate()
			box = _compute_aabb(m)
			m.free()
		_model_aabbs[id] = box
	return _model_aabbs[id]


## Gives a part read off the tree (a packed vessel loaded with Vessel.load_scene: no model is
## built until it enters the tree) its real size, without building the model.
func ensure_size() -> void:
	if _model == null and part_id != "":
		aabb = model_aabb(part_id)


func set_pickable(on: bool) -> void:
	pickable = on
	for c in part_children():
		c.set_pickable(on)


func set_ghost(on: bool) -> void:
	## Held parts render translucent so the attach target stays visible.
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).transparency = 0.4 if on else 0.0


## Small "clunk" squash on the model when the part is attached (visual only:
## the attach tree and the physics-ish properties are not affected).
func pulse() -> void:
	if _model == null or not is_inside_tree():
		return
	_model.scale = Vector3(1.05, 0.93, 1.05)
	var tw := create_tween()
	tw.tween_property(_model, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Overlay material on this part's own model (not its children); null clears it.
func set_highlight(mat: Material) -> void:
	if _model == null:
		return
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = mat
	if _model is MeshInstance3D:
		(_model as MeshInstance3D).material_overlay = mat


func part_children() -> Array[PartInstance]:
	var out: Array[PartInstance] = []
	for c in get_children():
		if c is PartInstance:
			out.append(c)
	return out


func part_parent() -> PartInstance:
	return get_parent() as PartInstance


func subtree() -> Array[PartInstance]:
	var out: Array[PartInstance] = [self]
	for c in part_children():
		out.append_array(c.subtree())
	return out


# ------------------------------------------------------------ shape and picking
## Body radius around the part axis (x = z = 0). Uses the smaller of the X/Z extents so
## side details (cable raceways, pumps) don't push surface attachments outward.
func radius() -> float:
	var rx := maxf(absf(aabb.position.x), absf(aabb.end.x))
	var rz := maxf(absf(aabb.position.z), absf(aabb.end.z))
	return minf(rx, rz)


func height() -> float:
	return aabb.size.y


## Round parts (tanks, engines, fairings...) are picked and surface-attached as cylinders,
## the rest (bus, panels, radial decouplers, fins) as boxes.
func is_round() -> bool:
	var cat: String = data.get("category", "")
	if PartDB.is_radial_decoupler(data) or part_id.begins_with("fin") or part_id == "grid_fins":
		return false
	var sx := aabb.size.x
	var sz := aabb.size.z
	return cat in ["tank", "engine", "structure", "aero", "command", "future"] and absf(sx - sz) < 0.15 * maxf(sx, sz)


## Ray (world space) against this part's shape. Returns {"t": float, "point": Vector3, "normal": Vector3 (local)} or {}.
func ray_hit(from: Vector3, dir: Vector3) -> Dictionary:
	var inv := global_transform.affine_inverse()
	var o := inv * from
	var d := (inv.basis * dir).normalized()
	var hit := _ray_cylinder(o, d) if is_round() else _ray_box(o, d)
	if hit.is_empty():
		return {}
	hit["point"] = global_transform * (o + d * float(hit["t"]))
	return hit


func _ray_cylinder(o: Vector3, d: Vector3) -> Dictionary:
	var r := radius()
	var y0 := aabb.position.y
	var y1 := aabb.end.y
	var best := INF
	var n := Vector3.ZERO
	var a := d.x * d.x + d.z * d.z
	if a > 1e-9:
		var b := 2.0 * (o.x * d.x + o.z * d.z)
		var c := o.x * o.x + o.z * o.z - r * r
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var t := (-b - sqrt(disc)) / (2.0 * a)
			var y := o.y + d.y * t
			if t > 0.0 and y >= y0 and y <= y1:
				best = t
				n = Vector3(o.x + d.x * t, 0, o.z + d.z * t).normalized()
	if absf(d.y) > 1e-9:
		for cap in [y0, y1]:
			var t: float = (cap - o.y) / d.y
			var p := o + d * t
			if t > 0.0 and t < best and p.x * p.x + p.z * p.z <= r * r:
				best = t
				n = Vector3(0, 1 if cap == y1 else -1, 0)
	return {} if best == INF else {"t": best, "normal": n}


func _ray_box(o: Vector3, d: Vector3) -> Dictionary:
	var tmin := -INF
	var tmax := INF
	var axis := -1
	var face_sign := 0.0
	for i in 3:
		var lo := aabb.position[i]
		var hi := aabb.end[i]
		if absf(d[i]) < 1e-9:
			if o[i] < lo or o[i] > hi:
				return {}
			continue
		var t1 := (lo - o[i]) / d[i]
		var t2 := (hi - o[i]) / d[i]
		var s := -1.0
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
			s = 1.0
		if t1 > tmin:
			tmin = t1
			axis = i
			face_sign = s
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return {}
	if tmin <= 0.0 or axis < 0:
		return {}
	var n := Vector3.ZERO
	n[axis] = face_sign
	return {"t": tmin, "normal": n}


# ------------------------------------------------------------ attach nodes (local space)
func has_node_point(n: String) -> bool:
	var att: Dictionary = data.get("attach", {})
	match n:
		"top":
			return att.get("top") != null
		"bottom":
			return att.get("bottom") != null and att.get("bottom") != "engines"
		"side":
			return PartDB.is_radial_decoupler(data)
	if n.begins_with("slot:"):
		return int(n.substr(5)) < int(data.get("engine_slots", 0))
	return false


func node_size(n: String) -> String:
	var att: Dictionary = data.get("attach", {})
	if n == "top" or n == "bottom":
		var v: Variant = att.get(n)
		return v if v is String else ""
	return "slot" if n.begins_with("slot:") else n


func node_local(n: String) -> Vector3:
	match n:
		"top":
			return Vector3(0, aabb.end.y, 0)
		"bottom":
			return Vector3(0, aabb.position.y, 0)
		"side":
			return Vector3(aabb.end.x, aabb.get_center().y, 0)
	if n.begins_with("slot:"):
		var k := int(n.substr(5))
		var slots := int(data.get("engine_slots", 1))
		if k == 0:
			return Vector3(0, aabb.position.y, 0)
		var ring := slots - 1
		var r := radius() * 0.66  # same layout as tools/voxel_gen.py b_thrust_plate
		var a := TAU * float(k - 1) / float(ring)
		return Vector3(cos(a) * r, aabb.position.y, sin(a) * r)
	return Vector3.ZERO


func node_names() -> Array[String]:
	var out: Array[String] = []
	for n in ["top", "bottom", "side"]:
		if has_node_point(n):
			out.append(n)
	for k in int(data.get("engine_slots", 0)):
		out.append("slot:%d" % k)
	return out


func occupied_nodes() -> Array[String]:
	var out: Array[String] = []
	for c in part_children():
		out.append(c.parent_node_name)
	if part_parent() and own_node_name in ["top", "bottom"]:
		out.append(own_node_name)
	return out


func free_nodes() -> Array[String]:
	var occ := occupied_nodes()
	var out: Array[String] = []
	for n in node_names():
		if not occ.has(n):
			out.append(n)
	return out


func can_radial_attach() -> bool:
	return bool(data.get("attach", {}).get("radial", false))


# ------------------------------------------------------------ physics-ish properties
func wet_mass() -> float:
	return PartDB.wet_mass(data)


func dry_mass() -> float:
	return float(data.get("mass_kg", 0.0))


func center_global() -> Vector3:
	return global_transform * aabb.get_center()


func thrust_point_global() -> Vector3:
	return global_transform * Vector3(0, aabb.position.y, 0)


## Lateral area used for the center-of-lift estimate. Fins act as lifting surfaces.
func lift_weight() -> float:
	var area := aabb.size.y * maxf(aabb.size.x, aabb.size.z)
	if part_id.begins_with("fin_") or part_id == "grid_fins":
		return area * 4.0
	if PartDB.is_engine(data):
		return area * 0.5
	return area
