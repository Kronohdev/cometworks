@tool
class_name SurfaceInteractable
extends Node3D
## A point of interest on a planet surface the rover can act on (a rock to drill, an ice patch to
## scan, a crater rim to reach, a view for a photo). The world side places these in its surface
## scenes (scenes/surface/*.tscn, the look is theirs: children meshes / voxel props); the rover
## side finds them by GROUP (SurfaceSession.GROUP, joined in _ready) and distance, no physics.
##
## The rover calls:
##   reached(rover)              once when it comes within reach_radius (crater rims, vistas)
##   interact(rover, action)     when the player uses a tool in reach: "photo", "scan", "drill",
##                               "sample", "drone" (or "" = the first action this POI accepts)
## `rover` is a RoverController (src/rover/rover_controller.gd): read `rover.global_position`,
## `rover.has_tool(&"drill")`, `rover.design` (RoverDesign dict), `rover.power_frac()`.
##
## Override _on_interact(rover, action, result) to add effects (dig a hole, pick up a crystal); set
## result["ok"] = false to refuse. Objectives are matched by SurfaceSession.objective_for() (poi ==
## objective_id, else poi_kind == kind) and reported to SurfaceSession.current automatically.

## an objective this POI fulfilled
signal objective_reached(id: StringName)
## any interaction ({"ok", "science", "message_key", "objective"})
signal interacted(rover: Node, action: StringName, result: Dictionary)

## unique id on the surface ("" = the node name)
@export var interact_id: StringName = &""
## what it is: rock, ice, crater_rim, vista, landing_site, sample_site, vent, dune, ...
@export var kind: StringName = &"rock"
## an exact SurfaceSession objective id / poi this answers ("" = matched by kind)
@export var objective_id: StringName = &""
## actions that work here (empty = any)
@export var actions: PackedStringArray = PackedStringArray(["photo", "scan", "drill", "sample"])
## metres from the rover's centre that count as "in reach"
@export var reach_radius: float = 7.0
## science points for the first successful action of each kind here
@export var science: float = 8.0
## i18n key of the POI's name on the HUD prompt ("" = generic by kind)
@export var name_key: String = ""
## a reach / action makes it "used" (the HUD and mini-map dim it)
var used := {}
var was_reached := false


func _enter_tree() -> void:
	add_to_group(SurfaceSession.GROUP)


func get_interact_id() -> StringName:
	return interact_id if interact_id != &"" else StringName(name)


func accepts(action: StringName) -> bool:
	return actions.is_empty() or String(action) in actions


func in_reach(pos: Vector3) -> bool:
	var d := global_position - pos
	d.y *= 0.5
	return d.length() <= reach_radius


## The rover arrived within reach_radius (called once per POI).
func reached(rover: Node) -> Dictionary:
	if was_reached:
		return {}
	was_reached = true
	var res := {"ok": true, "science": 0.0, "message_key": "", "objective": ""}
	var s := SurfaceSession.current
	if s:
		var o := s.objective_for(self, &"reach")
		if not o.is_empty() and s.report_objective(o["id"], {"poi": String(get_interact_id())}):
			res["objective"] = String(o["id"])
			res["message_key"] = String(o.get("label_key", ""))
			objective_reached.emit(o["id"])
	interacted.emit(rover, &"reach", res)
	return res


## The rover uses a tool here. Returns {"ok", "science", "message_key", "objective"}.
func interact(rover: Node, action: StringName = &"") -> Dictionary:
	if action == &"" and not actions.is_empty():
		action = StringName(actions[0])
	var res := {"ok": accepts(action), "science": 0.0, "message_key": "", "objective": ""}
	if not res["ok"]:
		res["message_key"] = "RV_MSG_NOTHING_HERE"
		return res
	_on_interact(rover, action, res)
	if not res["ok"]:
		return res
	var s := SurfaceSession.current
	if s:
		res["science"] = s.credit_once(get_interact_id(), action, science)
		var o := s.objective_for(self, action)
		if not o.is_empty() and s.report_objective(o["id"], {"poi": String(get_interact_id())}):
			res["objective"] = String(o["id"])
			objective_reached.emit(o["id"])
	elif not used.has(action):
		res["science"] = science
	used[action] = true
	interacted.emit(rover, action, res)
	return res


## Override: effects of an action (res["ok"] = false refuses it, res["message_key"] says why).
func _on_interact(_rover: Node, _action: StringName, _res: Dictionary) -> void:
	pass
