class_name FlightCamera
extends Node3D
## Chase / orbit camera around the active vessel. Angles are measured in the local
## horizon frame (radial up at the vessel), so the horizon stays level whatever the
## rocket does; RMB drag orbits, the wheel zooms, everything is smoothed.

@export var distance := 60.0
@export var min_distance := 6.0
@export var max_distance := 4000.0
@export var yaw := 0.0
@export var pitch := 0.12
@export var smooth := 8.0
## world direction the camera sits on for yaw = 0 (set by the flight scene: south of the pad)
@export var reference := Vector3(0.447, 0, 0.894)

var target := Vector3.ZERO
var up := Vector3.UP
var _yaw := 0.0
var _pitch := 0.12
var _dist := 60.0
var _dragging := false
## how far above the centre the target is framed (fraction of the distance)
@export var frame_lift := 0.09
## optional shake (launch rumble), metres
var shake := 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_yaw = yaw
	_pitch = pitch
	_dist = distance


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.88)
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * 1.13)
			return true
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		pitch = clampf(pitch + mm.relative.y * 0.005, maxf(-1.45, _min_pitch(distance)), 1.45)
		return true
	return false


func set_view(new_yaw: float, new_pitch: float, new_distance: float, snap := false) -> void:
	yaw = new_yaw
	pitch = new_pitch
	distance = new_distance
	if snap:
		_yaw = yaw
		_pitch = pitch
		_dist = distance


## Lowest the camera may go, in metres along local up relative to the focus point
## (ground / pad top + margin minus the focus altitude). Set every frame by FlightWorld.
var min_height := -INF


## Pitch that keeps the camera `min_height` above/below the focus at distance d.
func _min_pitch(d: float) -> float:
	if min_height == -INF or d <= 0.01:
		return -1.45
	return asin(clampf(min_height / d, -1.0, 1.0))


func update_camera(delta: float, focus: Vector3, local_up: Vector3) -> void:
	var k := 1.0 - exp(-smooth * delta)
	# never below the ground: raise the pitch instead (target and eased value)
	pitch = clampf(maxf(pitch, _min_pitch(distance)), -1.45, 1.5)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, distance, k)
	_pitch = clampf(maxf(_pitch, _min_pitch(_dist)), -1.45, 1.5)
	target = focus
	up = up.slerp(local_up, clampf(delta * 3.0, 0.0, 1.0)).normalized() if up.dot(local_up) > -0.9 else local_up
	# horizon frame: reference projected on the horizontal plane
	var ref := (reference - up * reference.dot(up))
	if ref.length() < 0.01:
		ref = up.cross(Vector3.RIGHT)
	ref = ref.normalized()
	var side := up.cross(ref).normalized()
	var horiz := ref * cos(_yaw) + side * sin(_yaw)
	var offset := (horiz * cos(_pitch) + up * sin(_pitch)) * _dist
	var jitter := Vector3.ZERO
	if shake > 0.0:
		jitter = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake
		jitter -= local_up * minf(jitter.dot(local_up), 0.0)
	global_position = focus + offset + jitter
	camera.global_position = global_position
	# frame the subject a little above the screen centre (the navball sits at the bottom):
	# aim slightly below it (a rotation; a v_offset would move the camera into the ground)
	camera.look_at(focus - up * _dist * frame_lift, up)
