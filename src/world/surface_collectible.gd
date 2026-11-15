@tool
class_name SurfaceCollectible
extends SurfaceInteractable
## A small find lying on a surface (scenes/surface/props/collectible.tscn): a meteorite, an ice
## crystal, an odd rock or a comet crumb (a bit of the Mãe-Gelo's tail, lore). Driving over it
## picks it up (the rover's reach check calls reached(), the fly camera's helper too); the
## sample tool works as well. SurfaceExplore logs it per body, so a find stays picked up in the
## career save and is hidden next time. The look: one child per type (Meteorite, Ice, OddRock,
## Crumb), the one of `type` is shown and turns slowly with its glint.

signal collected(node: SurfaceCollectible)

enum Type { METEORITE, ICE, ODD_ROCK, COMET_CRUMB }
const TYPE_IDS := ["meteorite", "ice", "odd_rock", "comet_crumb"]
const VISUALS := ["Meteorite", "Ice", "OddRock", "Crumb"]

@export var type: Type = Type.METEORITE:
	set(v):
		type = v
		_show_type()
## comet crumbs: which lore line of data/surface_explore.json crumb_lore it tells
@export var lore_index: int = 0
@export var ground_offset: float = 0.0

var is_collected := false
var _t := 0.0


func _enter_tree() -> void:
	super()
	add_to_group(PlanetSurface.SNAP_GROUP)


func _ready() -> void:
	kind = &"collectible"
	name_key = String(SurfaceExplore.collectible_type(type_id()).get("name_key", ""))
	science = float(SurfaceExplore.collectible_type(type_id()).get("science", 2.0))
	if actions.is_empty() or actions == PackedStringArray(["photo", "scan", "drill", "sample"]):
		actions = PackedStringArray(["sample", "scan"])
	reach_radius = minf(reach_radius, 4.0)
	_show_type()
	if not Engine.is_editor_hint():
		interacted.connect(_on_interacted)
		_t = float(hash(name) % 1000) * 0.01


func type_id() -> String:
	return TYPE_IDS[int(type)]


func snap_to_ground(surface: PlanetSurface) -> void:
	SurfaceGroundSnap.place(self, surface, ground_offset, false)


func _show_type() -> void:
	if not is_inside_tree():
		return
	for i in VISUALS.size():
		var n := get_node_or_null(VISUALS[i]) as Node3D
		if n:
			n.visible = i == int(type)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or is_collected:
		return
	_t += delta
	var v := get_node_or_null(VISUALS[int(type)]) as Node3D
	if v:
		v.rotation.y = _t * 0.7
		v.position.y = 0.15 + sin(_t * 2.2) * 0.08


func _on_interacted(_rover: Node, action: StringName, _res: Dictionary) -> void:
	if action == &"reach" or action == &"sample" or action == &"scan":
		collect()


## Picks it up: hidden, out of the rover's lists, `collected` emitted (once).
func collect() -> void:
	if is_collected:
		return
	is_collected = true
	collected.emit(self)
	hide_collected()


## Hidden and out of the interactables (also for a find the log already has).
func hide_collected() -> void:
	is_collected = true
	was_reached = true
	visible = false
	remove_from_group(SurfaceSession.GROUP)
	set_process(false)
