@tool
class_name SurfaceChallenge
extends Node3D
## Where a little challenge of the free play starts (scenes/surface/props/challenge_ring.tscn):
## the race to a crater rim starts when the rover leaves this ring, the jump is the ramp this
## ring sits at the foot of. The rules (type, target, time, air time, texts) come from
## data/surface_explore.json by `entry_id`; SurfaceExplore runs them (find_all / collect_all /
## deliver need no node, but may have one). The ring sits on the ground by itself.

## id of the challenge in data/surface_explore.json (bodies.<body>.challenges[].id)
@export var entry_id: StringName = &""
## start zone radius (m)
@export var radius: float = 9.0
@export var ground_offset: float = 0.05

var entry: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(PlanetSurface.SNAP_GROUP)
	add_to_group(&"surface_challenge")


func _ready() -> void:
	entry = SurfaceExplore.challenge_entry(entry_id)


func snap_to_ground(surface: PlanetSurface) -> void:
	SurfaceGroundSnap.place(self, surface, ground_offset, false)


func in_zone(pos: Vector3) -> bool:
	var d := pos - global_position
	d.y = 0.0
	return d.length() <= radius
