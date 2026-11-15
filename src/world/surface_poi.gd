@tool
class_name SurfacePoi
extends SurfaceInteractable
## A point of interest of the free play (a historic landing site homage, a crater rim, a rille,
## a rock to drill, a view...). Placed by hand in a surface scene (its look: the child set
## piece scenes of scenes/surface/props/), it sits on the ground by itself (group
## PlanetSurface.SNAP_GROUP) and takes its kind, name, actions, reach and science from
## data/surface_explore.json by `entry_id` (SurfaceExplore.poi_entry). The rover reaches it and
## uses its tools on it (SurfaceInteractable); the first time is a discovery in the body's log
## (SurfaceExplore listens to `interacted`), and every action answers with the place's fact.

## id of the POI in data/surface_explore.json (bodies.<body>.pois[].id)
@export var entry_id: StringName = &""
## metres above the ground once snapped (negative sinks it a little)
@export var ground_offset: float = 0.0
## lean the node with the slope under it (small props); off for big set pieces
@export var align_to_slope: bool = false

## the data entry ({} when not found)
var entry: Dictionary = {}


func _enter_tree() -> void:
	super()
	add_to_group(PlanetSurface.SNAP_GROUP)


func _ready() -> void:
	apply_entry(SurfaceExplore.poi_entry(entry_id))


## Takes the POI's data (also used by the tests and SurfaceExplore).
func apply_entry(e: Dictionary) -> void:
	entry = e
	if e.is_empty():
		return
	if interact_id == &"":
		interact_id = StringName(e.get("id", entry_id))
	kind = StringName(e.get("kind", kind))
	name_key = String(e.get("name_key", name_key))
	science = float(e.get("science", science))
	reach_radius = float(e.get("reach", reach_radius))
	var acts: Array = e.get("actions", [])
	if not acts.is_empty():
		actions = PackedStringArray(acts)


func fact_key() -> String:
	return String(entry.get("fact_key", ""))


func snap_to_ground(surface: PlanetSurface) -> void:
	SurfaceGroundSnap.place(self, surface, ground_offset, align_to_slope)


## Every action answers with the place's fact (the rover HUD shows it as its message).
func _on_interact(_rover: Node, _action: StringName, res: Dictionary) -> void:
	if fact_key() != "":
		res["message_key"] = fact_key()
