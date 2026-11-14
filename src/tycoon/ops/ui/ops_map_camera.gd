class_name OpsMapCamera
extends Camera3D
## Orbit camera of the mission map: turns around a focus point (yaw / pitch), zooms by
## distance, and glides smoothly when the focus moves (a body, a mission). The framing
## presets (Earth, Moon, the whole system) are exported so they are tuned in the editor.

@export var yaw := -0.6
@export var pitch := 0.42
@export var distance := 24.0
@export var min_distance := 1.6
@export var max_distance := 80.0
@export_range(0.0, 1.0) var min_pitch := 0.05
@export_range(0.0, 1.6) var max_pitch := 1.45
## smoothing rate (1/s) of position, distance and angles
@export var smoothing := 6.0
## the focus point is shifted on screen (x, y in fractions of the view) so the panels do not
## cover what the camera looks at
@export var screen_offset := Vector2(-0.08, 0.07)

var focus := Vector3.ZERO
var _focus_now := Vector3.ZERO
var _dist_now := 24.0
var _yaw_now := -0.6
var _pitch_now := 0.42


func _ready() -> void:
	_dist_now = distance
	_yaw_now = yaw
	_pitch_now = pitch
	_focus_now = focus
	_apply()


func orbit(d: Vector2) -> void:
	yaw -= d.x * 0.006
	pitch = clampf(pitch + d.y * 0.005, min_pitch, max_pitch)


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)


func frame(point: Vector3, dist: float) -> void:
	focus = point
	distance = clampf(dist, min_distance, max_distance)


## Jumps to the current target (no glide), for the first frame and screenshots.
func snap() -> void:
	_focus_now = focus
	_dist_now = distance
	_yaw_now = yaw
	_pitch_now = pitch
	_apply()


func _process(delta: float) -> void:
	var k := 1.0 - exp(-smoothing * delta)
	_focus_now = _focus_now.lerp(focus, k)
	_dist_now = lerpf(_dist_now, distance, k)
	_yaw_now = lerp_angle(_yaw_now, yaw, k)
	_pitch_now = lerpf(_pitch_now, pitch, k)
	_apply()


func _apply() -> void:
	var dir := Vector3(cos(_pitch_now) * sin(_yaw_now), sin(_pitch_now), cos(_pitch_now) * cos(_yaw_now))
	var eye := _focus_now + dir * _dist_now
	look_at_from_position(eye, _focus_now, Vector3.UP)
	# shift the image so the focus sits off-centre (h_offset / v_offset are in world units)
	var half_h := tan(deg_to_rad(fov) * 0.5) * _dist_now
	h_offset = -screen_offset.x * 2.0 * half_h * 16.0 / 9.0
	v_offset = -screen_offset.y * 2.0 * half_h
