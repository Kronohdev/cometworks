class_name RoofBirds
extends Node3D
## A few birds perched on a lamp head or a ledge (scenes/tycoon/fx/roof_birds.tscn): they peck
## and hop (AnimationPlayer "perch", looping) until the camera comes closer than
## `flee_distance`, then they fly off ("fly"). Once the camera has stayed further than
## `return_distance` for `return_seconds`, they are back on their perch (unseen from there).

@export var flee_distance := 14.0
@export var return_distance := 45.0
@export var return_seconds := 10.0
## seconds into "perch" this flock starts, so neighbouring flocks do not peck in step
@export var phase := 0.0

var away := false
var _far_for := 0.0

@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	come_back()
	if anim.has_animation("perch"):
		anim.seek(fposmod(phase, anim.get_animation("perch").length), true)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	if not away:
		if d < flee_distance:
			fly_off()
		return
	if d > return_distance:
		_far_for += delta
		if _far_for >= return_seconds:
			come_back()
	else:
		_far_for = 0.0


func fly_off() -> void:
	away = true
	_far_for = 0.0
	anim.play("fly")


func come_back() -> void:
	away = false
	_far_for = 0.0
	anim.play("perch")
