@tool
class_name SurfaceGroundSnap
extends Node3D
## Keeps a set piece of a surface scene (a boulder, a sign, a flag...) on the procedural
## ground: the PlanetSurface puts every node of its SNAP_GROUP on the voxel terrain once the
## terrain exists (in the editor too, and again when a landform moves). Only x / z and the
## yaw of the node are authored; its height comes from the terrain.

@export var ground_offset: float = 0.0
@export var align_to_slope: bool = false


func _enter_tree() -> void:
	add_to_group(PlanetSurface.SNAP_GROUP)


func snap_to_ground(surface: PlanetSurface) -> void:
	place(self, surface, ground_offset, align_to_slope)


## Puts `node` on the surface's ground at its x / z (+ offset), leaning it with the slope if asked.
static func place(node: Node3D, surface: PlanetSurface, offset := 0.0, align := false) -> void:
	if surface == null or surface.terrain == null or surface.terrain.generator == null:
		return
	var p := node.global_position
	var g := surface.ground_height(p.x, p.z)
	if align:
		var hx := surface.ground_height(p.x + 1.5, p.z) - surface.ground_height(p.x - 1.5, p.z)
		var hz := surface.ground_height(p.x, p.z + 1.5) - surface.ground_height(p.x, p.z - 1.5)
		var up := Vector3(-hx / 3.0, 1.0, -hz / 3.0).normalized()
		var yaw := node.global_rotation.y
		var b := Basis(Vector3.UP, yaw)
		var axis := Vector3.UP.cross(up)
		if axis.length() > 1e-4:
			b = Basis(axis.normalized(), Vector3.UP.angle_to(up)) * b
		node.global_basis = b.scaled(node.global_basis.get_scale())
	node.global_position = Vector3(p.x, g + offset, p.z)
