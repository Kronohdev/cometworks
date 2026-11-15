class_name JointDecor
extends Node3D
## Visual covers between stacked parts (child of the Vessel node, so it follows the
## vessel; a second one under the hangar's Loose node covers the loose subassemblies).
## Rebuilt from the attach tree after every change:
##   - junction blocks: many models only reach their full body below the node plane
##     (pegs, antennas, feed lines on top of an avionics core). The block fills the gap
##     between the two solid body faces (data/part_joints.json, tools/joint_profiles.py),
##     so the stack reads as one piece instead of resting on the tips of the details.
##     New joints grow in; while a part is held, preview() shows the block it would make.
##   - joint collars: a thin ring over each stack seam between round parts of similar size
##   - engine shrouds: when an engine has a part attached below it (next stage /
##     decoupler), a shroud spans from the tank above to the part below, hiding the
##     gap like the engine fairings in KSP. Purely visual: no mass, not pickable.
## Templates are editor scenes: scenes/hangar/joint_block.tscn, joint_collar.tscn and
## engine_shroud.tscn.

const BLOCK_SCENE := preload("res://scenes/hangar/joint_block.tscn")
const COLLAR_SCENE := preload("res://scenes/hangar/joint_collar.tscn")
const SHROUD_SCENE := preload("res://scenes/hangar/engine_shroud.tscn")
## Round part categories that get collars at their stack seams.
const COLLAR_CATEGORIES := ["tank", "structure", "command", "aero", "future"]
const COLLAR_HEIGHT_FRAC := 0.045  # collar height as a fraction of the joint diameter
const COLLAR_MIN_H := 0.08
const COLLAR_PAD := 1.02
## Gaps shorter than this are left alone (m).
const MIN_BLOCK_GAP := 0.03
## An end whose details cover more of the footprint than this is a tapering shape
## (cone, dome, nozzle) that is meant to be seen: no block there.
const MAX_DETAIL := 0.2
const BLOCK_RADIUS_FRAC := 0.97
## How far the block reaches into each body, so no seam light leaks through (m).
const BLOCK_OVERLAP := 0.04
const GROW_TIME := 0.35
## More new joints than this in one rebuild (a loaded vessel) appear without animation.
const MAX_ANIMATED := 8

@export var vessel: Vessel

## Joint keys of the previous rebuild: only joints that are new get the grow animation.
var _known := {}
var _preview: MeshInstance3D


func _ready() -> void:
	if vessel == null:
		vessel = get_parent() as Vessel


## Diameter class radius of a stack node, falling back to the body radius.
static func node_radius(p: PartInstance, n: String) -> float:
	var size := p.node_size(n)
	if PartDB.size_classes.has(size):
		return float(PartDB.size_classes[size]) * 0.5
	return p.radius()


## Gap between the node plane of `p` at node `n` and its solid body face, and that
## face's radius: {"gap", "r"}. Tapering ends report no gap.
static func end_gap(p: PartInstance, n: String) -> Dictionary:
	var r := node_radius(p, n)
	var j: Dictionary = p.data.get("joint", {})
	if not (n in ["top", "bottom"]) or j.is_empty() or PartDB.is_fairing(p.data):
		return {"gap": 0.0, "r": r}
	var gap := float(j.get(n + "_gap", 0.0))
	if gap <= 0.0 or float(j.get(n + "_detail", 1.0)) > MAX_DETAIL:
		return {"gap": 0.0, "r": r}
	return {"gap": gap, "r": minf(float(j.get(n + "_r", r)), r * 1.05)}


## Junction block between part `a` (node `an`) and part `b` (node `bn`) from their current
## global transforms: {"center", "basis", "height", "radius"}, or {} when they touch.
static func block_between(a: PartInstance, an: String, b: PartInstance, bn: String) -> Dictionary:
	var ga := end_gap(a, an)
	var gb := end_gap(b, bn)
	if float(ga["gap"]) + float(gb["gap"]) < MIN_BLOCK_GAP:
		return {}
	var pa := a.global_transform * (a.node_local(an) + _inward(an) * float(ga["gap"]))
	var pb := b.global_transform * (b.node_local(bn) + _inward(bn) * float(gb["gap"]))
	var span := pa.distance_to(pb)
	if span < MIN_BLOCK_GAP:
		return {}
	return {"center": (pa + pb) * 0.5, "basis": a.global_transform.basis.orthonormalized(),
		"height": span + BLOCK_OVERLAP * 2.0,
		"radius": minf(float(ga["r"]), float(gb["r"])) * BLOCK_RADIUS_FRAC}


static func _inward(n: String) -> Vector3:
	return Vector3.DOWN if n == "top" else Vector3.UP


func rebuild() -> void:
	rebuild_parts(vessel.all_parts() if vessel and vessel.root else ([] as Array[PartInstance]))


## Rebuilds the covers for every stack joint among `parts`.
func rebuild_parts(parts: Array[PartInstance]) -> void:
	for c in get_children():
		if c != _preview:
			c.queue_free()
	var seen := {}
	var fresh: Array = []  # [node, kind] of joints that did not exist in the last rebuild
	for p in parts:
		var parent := p.part_parent()
		if parent == null or not (p.own_node_name in ["top", "bottom"]) or not (p.parent_node_name in ["top", "bottom"]):
			continue
		var key := p.get_instance_id()  # not get_path(): a part may be off the tree (a breakup piece)
		seen[key] = true
		var made: Array = []
		if PartDB.is_engine(p.data):
			made.append_array(_maybe_shroud(parent, p))
			made.append_array(_maybe_block(parent, p))
		elif PartDB.is_engine(parent.data):
			continue  # seam under an engine is covered by its shroud
		else:
			made.append_array(_maybe_block(parent, p))
			made.append_array(_maybe_collar(parent, p))
		if not _known.has(key):
			fresh.append_array(made)
	if fresh.size() <= MAX_ANIMATED and not _known.is_empty():
		for n: Node3D in fresh:
			_grow(n)
	_known = seen


func _maybe_block(a: PartInstance, b: PartInstance) -> Array:
	var blk := block_between(a, b.parent_node_name, b, b.own_node_name)
	if blk.is_empty():
		return []
	var m: MeshInstance3D = BLOCK_SCENE.instantiate()
	_shape_block(m, blk)
	add_child(m)
	m.global_transform = Transform3D(blk["basis"], blk["center"])
	return [m]


static func _shape_block(m: MeshInstance3D, blk: Dictionary) -> void:
	var cur := m.mesh as CylinderMesh
	if is_equal_approx(cur.top_radius, blk["radius"]) and is_equal_approx(cur.height, blk["height"]):
		return
	var mesh := cur.duplicate() as CylinderMesh
	mesh.top_radius = blk["radius"]
	mesh.bottom_radius = blk["radius"]
	mesh.height = blk["height"]
	m.mesh = mesh


func _maybe_collar(a: PartInstance, b: PartInstance) -> Array:
	if not (a.data.get("category", "") in COLLAR_CATEGORIES and b.data.get("category", "") in COLLAR_CATEGORIES):
		return []
	if PartDB.is_fairing(a.data) or PartDB.is_fairing(b.data):
		return []
	var ra := node_radius(a, b.parent_node_name)
	var rb := node_radius(b, b.own_node_name)
	if absf(ra - rb) > 0.15 * maxf(ra, rb):
		return []  # different diameters: that's an adapter's job
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
	return [col]


## Shroud around `engine` if it sits between its parent (above) and another part below.
func _maybe_shroud(parent: PartInstance, engine: PartInstance) -> Array:
	if engine.own_node_name != "top" or engine.parent_node_name != "bottom":
		return []
	var below: PartInstance = null
	for c in engine.part_children():
		if c.parent_node_name == "bottom":
			below = c
	if below == null or below.part_id.begins_with("interstage_"):
		return []
	var top_w := parent.global_transform * parent.node_local("bottom")
	var bot_w := below.global_transform * below.node_local(below.own_node_name)
	var height := top_w.distance_to(bot_w)
	if height < 0.05:
		return []
	var shroud: MeshInstance3D = SHROUD_SCENE.instantiate()
	var mesh := (shroud.mesh as CylinderMesh).duplicate() as CylinderMesh
	mesh.top_radius = node_radius(parent, "bottom") * 1.005
	mesh.bottom_radius = node_radius(below, below.own_node_name) * 1.005
	mesh.height = height
	shroud.mesh = mesh
	add_child(shroud)
	shroud.global_transform = Transform3D(parent.global_transform.basis, (top_w + bot_w) * 0.5)
	return [shroud]


## New joints extend out of the seam (blocks and shrouds) or settle onto it (collars).
func _grow(n: Node3D) -> void:
	var collar := n.scene_file_path == COLLAR_SCENE.resource_path
	n.scale = Vector3(1.3, 1.0, 1.3) if collar else Vector3(1.0, 0.02, 1.0)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, GROW_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Shows the block that attaching `b` (node `bn`) to `a` (node `an`) would create, at the
## parts' current transforms (follows the held part while it glides into place).
func preview(a: PartInstance, an: String, b: PartInstance, bn: String) -> void:
	var blk := block_between(a, an, b, bn)
	if blk.is_empty():
		hide_preview()
		return
	if _preview == null:
		_preview = BLOCK_SCENE.instantiate()
		_preview.transparency = 0.45
		add_child(_preview)
	_shape_block(_preview, blk)
	_preview.visible = true
	_preview.global_transform = Transform3D(blk["basis"], blk["center"])


func hide_preview() -> void:
	if _preview:
		_preview.visible = false
