class_name BuildingFx
extends Node3D
## The working life of one campus building (scenes/tycoon/fx/building_fx_<kind>.tscn: smoke
## from the factory stack, welding sparks, bubbling beakers, blinking screens, signal rings over
## the dishes, a crane swinging its load...). CampusEffects puts one on every building and tells
## it how busy the building is; everything you see is authored in the scene, this script only
## turns it up and down:
##   activity          0 = nobody there (idle: slow loops, no smoke) .. 1 = staffed and busy;
##                     eased by `ease_speed` per second
##   GPUParticles3D    emit `amount_ratio` = lerp(idle, 1, activity), where idle is the node's
##                     metadata `idle` (default 0: the emitter stops when the building is empty)
##   AnimationPlayer   plays its autoplay loop with speed_scale = lerp(idle_speed, 1, activity)
##                     (metadata `constant` = true: always at speed 1, e.g. a weather vane)
##   Light3D           energy = authored energy * lerp(idle, 1, activity) (metadata `idle`,
##                     default `light_idle`)
##   any child         metadata era_min / era_max / level_min / level_max: shown only on those
##                     looks; metadata `interior` = true: only while the cutaway shows the inside
##                     (CampusBuilding.is_open()), so nothing inside costs anything from afar;
##                     metadata `outside` = true: only while the building is closed (a string of
##                     flags across the front wall, which folds away with the cutaway)
## Particles stop beyond `lod_distance` from the camera.

@export_range(0.0, 1.0, 0.01) var idle_speed := 0.2
@export_range(0.0, 1.0, 0.01) var light_idle := 0.25
## activity easing (units per second)
@export var ease_speed := 0.8
## camera distance (m) beyond which the particles stop
@export var lod_distance := 160.0

var activity := 0.0
var target_activity := 0.0
var era := 1
var level := 1
## the building this belongs to (its parent), for the cutaway state
var building: Node3D

var _particles: Array[GPUParticles3D] = []
var _players: Array[AnimationPlayer] = []
var _lights: Array[Light3D] = []
var _light_base: Array[float] = []
var _interior: Array[Node3D] = []
var _outside: Array[Node3D] = []
var _was_open := false
var _far := false


func _ready() -> void:
	building = get_parent() as Node3D
	for n in find_children("*", "GPUParticles3D", true, false):
		_particles.append(n as GPUParticles3D)
	for n in find_children("*", "AnimationPlayer", true, false):
		_players.append(n as AnimationPlayer)
	for n in find_children("*", "Light3D", true, false):
		_lights.append(n as Light3D)
		_light_base.append((n as Light3D).light_energy)
	for n in find_children("*", "Node3D", true, false):
		if n.get_meta("interior", false):
			_interior.append(n as Node3D)
		if n.get_meta("outside", false):
			_outside.append(n as Node3D)
	_apply(true)


## Shows the props of an era and level (children with era_min / era_max / level_min / level_max).
func set_look(p_era: int, p_level: int) -> void:
	era = p_era
	level = p_level
	_apply_look(self)
	_sync_interior(true)


func _apply_look(n: Node) -> void:
	for c in n.get_children():
		if c is Node3D and (c.has_meta("era_min") or c.has_meta("era_max") or c.has_meta("level_min") or c.has_meta("level_max")):
			var on := era >= int(c.get_meta("era_min", 1)) and era <= int(c.get_meta("era_max", 5)) \
				and level >= int(c.get_meta("level_min", 1)) and level <= int(c.get_meta("level_max", 3))
			(c as Node3D).visible = on
		_apply_look(c)


## How busy the building is, 0..1 (eased towards it).
func set_activity(a: float) -> void:
	target_activity = clampf(a, 0.0, 1.0)


## Jumps to the target activity now (screenshots, tests).
func snap() -> void:
	activity = target_activity
	_apply(true)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var far := cam != null and cam.global_position.distance_to(global_position) > lod_distance
	var changed := far != _far
	_far = far
	if not is_equal_approx(activity, target_activity):
		activity = move_toward(activity, target_activity, delta * ease_speed)
		changed = true
	_sync_interior(false)
	if changed:
		_apply(false)


func _sync_interior(force: bool) -> void:
	var open := building != null and building.has_method("is_open") and bool(building.call("is_open"))
	if open == _was_open and not force:
		return
	_was_open = open
	for n in _interior:
		n.visible = open and _look_allows(n)
	for n in _outside:
		n.visible = not open and _look_allows(n)
	_apply(false)


func _look_allows(n: Node) -> bool:
	return era >= int(n.get_meta("era_min", 1)) and era <= int(n.get_meta("era_max", 5)) \
		and level >= int(n.get_meta("level_min", 1)) and level <= int(n.get_meta("level_max", 3))


func _apply(_force: bool) -> void:
	for p in _particles:
		var ratio := lerpf(float(p.get_meta("idle", 0.0)), 1.0, activity)
		p.amount_ratio = clampf(ratio, 0.0, 1.0)
		var on := ratio > 0.02 and not _far and p.is_visible_in_tree()
		if p.emitting != on:
			p.emitting = on
	for ap in _players:
		ap.speed_scale = 1.0 if ap.get_meta("constant", false) else lerpf(idle_speed, 1.0, activity)
	for i in _lights.size():
		_lights[i].light_energy = _light_base[i] * lerpf(float(_lights[i].get_meta("idle", light_idle)), 1.0, activity)


## The emitters that are emitting right now (tests).
func emitting_count() -> int:
	var n := 0
	for p in _particles:
		if p.emitting:
			n += 1
	return n
