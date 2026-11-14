class_name JointDecor
extends Node3D
## Visual covers between stacked parts (child of the Vessel node, so it follows the
## vessel). Rebuilt from the attach tree after every change:
##   - joint collars: a thin ring over each stack seam between round parts of similar size
##   - engine shrouds: when an engine has a part attached below it (next stage /
##     decoupler), a shroud spans from the tank above to the part below, hiding the
##     gap like the engine fairings in KSP. Purely visual: no mass, not pickable.
## Templates are editor scenes: scenes/hangar/joint_collar.tscn and engine_shroud.tscn.

const COLLAR_SCENE := preload("res://scenes/hangar/joint_collar.tscn")
const SHROUD_SCENE := preload("res://scenes/hangar/engine_shroud.tscn")
## Round part categories that get collars at their stack seams.
const COLLAR_CATEGORIES := ["tank", "structure", "command", "aero", "future"]
const COLLAR_HEIGHT_FRAC := 0.045  # collar height as a fraction of the joint diameter
const COLLAR_MIN_H := 0.08
const COLLAR_PAD := 1.02

@export var vessel: Vessel


func _ready() -> void:
	if vessel == null:
		vessel = get_parent() as Vessel


## Diameter class radius of a stack node, falling back to the body radius.
static func node_radius(p: PartInstance, n: String) -> float:
	var size := p.node_size(n)
	if PartDB.size_classes.has(size):
		return float(PartDB.size_classes[size]) * 0.5
	return p.radius()


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	if vessel == null or vessel.root == null:
		return
	for p in vessel.all_parts():
		var parent := p.part_parent()
		if parent == null or not (p.own_node_name in ["top", "bottom"]) or not (p.parent_node_name in ["top", "bottom"]):
			continue
		if PartDB.is_engine(p.data):
			_maybe_shroud(parent, p)
		elif PartDB.is_engine(parent.data):
			continue  # seam under an engine is covered by its shroud
		else:
			_maybe_collar(parent, p)


func _maybe_collar(a: PartInstance, b: PartInstance) -> void:
	if not (a.data.get("category", "") in COLLAR_CATEGORIES and b.data.get("category", "") in COLLAR_CATEGORIES):
		return
	if PartDB.is_fairing(a.data) or PartDB.is_fairing(b.data):
		return
	var ra := node_radius(a, b.parent_node_name)
	var rb := node_radius(b, b.own_node_name)
	if absf(ra - rb) > 0.15 * maxf(ra, rb):
		return  # different diameters: that's an adapter's job
	var r := maxf(ra, rb) * COLLAR_PAD
	var h := maxf(r * 2.0 * COLLAR_HEIGHT_FRAC, COLLAR_MIN_H)
	var seam := b.global_transform * b.node_local(b.own_node_name)
	var col: MeshInstance3D = COLLAR_SCENE.instantiate()
	var mesh := (col.mesh as CylinderMesh).duplicate() as CylinderMesh
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	col.mesh = mesh
	add_child(col)
	col.global_transform = Transform3D(b.global_transform.basis, seam)


## Shroud around `engine` if it sits between its parent (above) and another part below.
func _maybe_shroud(parent: PartInstance, engine: PartInstance) -> void:
	if engine.own_node_name != "top" or engine.parent_node_name != "bottom":
		return
	var below: PartInstance = null
	for c in engine.part_children():
		if c.parent_node_name == "bottom":
			below = c
	if below == null or below.part_id.begins_with("interstage_"):
		return
	var top_w := parent.global_transform * parent.node_local("bottom")
	var bot_w := below.global_transform * below.node_local(below.own_node_name)
	var height := top_w.distance_to(bot_w)
	if height < 0.05:
		return
	var shroud: MeshInstance3D = SHROUD_SCENE.instantiate()
	var mesh := (shroud.mesh as CylinderMesh).duplicate() as CylinderMesh
	mesh.top_radius = node_radius(parent, "bottom") * 1.005
	mesh.bottom_radius = node_radius(below, below.own_node_name) * 1.005
	mesh.height = height
	shroud.mesh = mesh
	add_child(shroud)
	shroud.global_transform = Transform3D(parent.global_transform.basis, (top_w + bot_w) * 0.5)
