class_name SurfaceDustDevil
extends Node3D
## A Martian dust devil (scenes/surface/props/dust_devil.tscn): the particle column authored in
## the scene drifts slowly around where it was placed, hugging the ground. Visual only.

## metres it may wander from its start
@export var wander_radius: float = 60.0
## drift speed (m/s)
@export var speed: float = 2.5

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _planet: PlanetSurface
var _rng := RandomNumberGenerator.new()
var _ground_t := 0.0


func _ready() -> void:
	_home = global_position
	_rng.seed = hash(name)
	_target = _pick()
	var n := get_parent()
	while n and not (n is PlanetSurface):
		n = n.get_parent()
	_planet = n as PlanetSurface


func _pick() -> Vector3:
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * wander_radius
	return _home + Vector3(cos(a) * r, 0.0, sin(a) * r)


func _process(delta: float) -> void:
	var p := global_position
	var to := _target - p
	to.y = 0.0
	if to.length() < 2.0:
		_target = _pick()
	else:
		p += to.normalized() * speed * delta
	_ground_t -= delta
	if _ground_t <= 0.0 and _planet and _planet.terrain and _planet.terrain.generator:
		_ground_t = 0.25
		p.y = _planet.ground_height(p.x, p.z)
	global_position = p
