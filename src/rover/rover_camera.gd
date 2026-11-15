class_name RoverCamera
extends Camera3D
## Chase camera of the rover drive (scenes/surface/rover_drive.tscn): behind and above the rover,
## smoothed, never under the ground. Hold the right mouse button (or Q / E) to swing around,
## wheel to zoom, C to reset behind the rover.

@export var distance: float = 9.0
@export var min_distance: float = 4.0
@export var max_distance: float = 28.0
@export var height: float = 3.4
@export var look_height: float = 1.2
@export var follow: float = 5.0
@export var mouse_sensitivity: float = 0.006

var target: RoverController
var orbit := 0.0
var tilt := 0.0
var _dragging := false
var _pos := Vector3.ZERO
var _snap := true


func snap() -> void:
	_snap = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = clampf(distance * 0.9, min_distance, max_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = clampf(distance * 1.1, min_distance, max_distance)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		orbit -= mm.relative.x * mouse_sensitivity
		tilt = clampf(tilt + mm.relative.y * mouse_sensitivity, -0.25, 0.9)
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_C:
		orbit = 0.0
		tilt = 0.0


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if Input.is_physical_key_pressed(KEY_Q):
		orbit += delta * 1.6
	if Input.is_physical_key_pressed(KEY_E):
		orbit -= delta * 1.6
	var a := target.yaw + orbit
	var back := Vector3(sin(a), 0.0, cos(a))
	var h := height + tilt * distance
	var want := target.position + back * distance + Vector3.UP * h
	var g := target.ground(want.x, want.z) + 1.2
	want.y = maxf(want.y, g)
	if _snap:
		_pos = want
		_snap = false
	else:
		_pos = _pos.lerp(want, clampf(follow * delta, 0.0, 1.0))
	_pos.y = maxf(_pos.y, target.ground(_pos.x, _pos.z) + 1.0)
	global_position = _pos
	var look := target.position + Vector3.UP * look_height
	if global_position.distance_to(look) > 0.1:
		look_at(look, Vector3.UP)
