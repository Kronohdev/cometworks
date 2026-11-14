class_name CampusCometling
extends Node3D
## A Cometling walking around the campus (scenes/tycoon/campus_cometling.tscn; the campus
## scene holds a Crowd of instances, editable in the editor): picks a spot (a building door, the bench, the
## pad), walks there along the road network (spot -> its door -> main road -> the target's
## door -> target; interior spots add a "via" point just inside the doorway), plays the
## spot's action for a while, then picks another. No navmesh: the
## campus roads are straight lines (main road at z = 2, cross road at x = 0).

const ROAD_Z := 2.0
const SPEED := 2.4

## colour variant and role shown until the crew roster assigns one
@export_range(0, 8) var variant := 0
@export_enum("ground", "pilot", "engineer", "scientist") var role: String = "ground"

var campus: Node3D
var creature: Node3D
var _path: Array[Vector3] = []
var _target := {}
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _roles := ["ground", "pilot", "engineer", "scientist"]


func _ready() -> void:
	creature = $Creature
	CometlingLooks.apply(creature as Cometling, variant, role)


## Called by the campus when this Cometling starts walking (starts where it was placed).
func setup(c: Node3D, rng_seed: int, p_variant: int, p_role: String) -> void:
	campus = c
	_rng.seed = rng_seed
	creature = $Creature
	variant = p_variant
	role = p_role
	if not role in _roles:
		role = "engineer" if role in ["systems", "propulsion", "tester"] else ("scientist" if role == "researcher" else "ground")
	CometlingLooks.apply(creature as Cometling, variant, role)
	_timer = _rng.randf_range(0.2, 2.0)


func _process(delta: float) -> void:
	if creature == null or campus == null:
		return
	if _path.is_empty():
		creature.call("set_move_velocity", Vector3.ZERO)
		_timer -= delta
		if _timer <= 0.0:
			_pick()
		return
	var to := _path[0] - position
	to.y = 0.0
	var d := to.length()
	if d < 0.25:
		_path.pop_front()
		if _path.is_empty():
			_arrive()
		return
	var v := to / d * SPEED
	position += v * delta
	rotation.y = lerp_angle(rotation.y, atan2(v.x, v.z), 1.0 - exp(-delta * 10.0))
	creature.call("set_move_velocity", v)


func _pick() -> void:
	var spots: Array[Dictionary] = campus.call("all_spots")
	if spots.is_empty():
		_timer = 2.0
		return
	var t: Dictionary = spots[_rng.randi() % spots.size()]
	# a little jitter so two Cometlings at the same spot do not overlap
	var jitter := Vector3(_rng.randf_range(-0.9, 0.9), 0, _rng.randf_range(-0.6, 0.6))
	# straight legs on the road network: out the door, along the main road, in the door
	var tdoor: Vector3 = t["door"]
	_path.clear()
	if not _target.is_empty():
		if _target.has("via"):
			_path.append(_target["via"])
		_path.append(_target["door"])
		_path.append(Vector3((_target["door"] as Vector3).x, 0, ROAD_Z))
	else:
		_path.append(Vector3(position.x, 0, ROAD_Z))
	_path.append(Vector3(tdoor.x, 0, ROAD_Z))
	_path.append(tdoor)
	if t.has("via"):
		_path.append(t["via"])   # just inside the doorway (interior spots)
	_path.append((t["pos"] as Vector3) + jitter)
	_target = t
	creature.call("play", "idle")


func _arrive() -> void:
	creature.call("set_move_velocity", Vector3.ZERO)
	rotation.y = float(_target.get("yaw", rotation.y))
	creature.call("play", String(_target.get("action", "idle")))
	if _rng.randf() < 0.35:
		var em := ["wrench", "star", "note", "rocket", "heart", "exclaim"]
		creature.call("show_emote", em[_rng.randi() % em.size()], 1.8)
	_timer = _rng.randf_range(5.0, 12.0)
