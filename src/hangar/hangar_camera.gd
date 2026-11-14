class_name HangarCamera
extends Node3D
## Orbit camera for the hangar (KSP VAB style), with smoothing: input changes the
## target view and the camera eases toward it every frame.
##   RMB drag: orbit · MMB drag: pan · wheel: zoom · Shift+wheel: height
##   arrows: orbit / height · PageUp/PageDown: zoom
## The Camera3D child lives in scenes/hangar.tscn.

signal view_changed

@export var focus := Vector3(0, 4, 0)
@export_range(-180, 180, 0.1, "radians_as_degrees") var yaw := deg_to_rad(35.0)
@export_range(-85, 85, 0.1, "radians_as_degrees") var pitch := deg_to_rad(12.0)
@export var distance := 22.0
## Higher = snappier. 0 disables smoothing.
@export var smoothing := 10.0
@export var min_distance := 3.0
@export var max_distance := 260.0
@export var min_height := 0.5
@export var max_height := 160.0
## The camera never goes below this height (hangar floor + margin), so it can't clip
## through the floor: the pitch is raised automatically instead.
@export var min_camera_height := 1.2
@export var key_orbit_speed := 1.6  # rad/s
@export var key_height_speed := 0.6  # fraction of distance per second

var target_focus: Vector3
var target_yaw: float
var target_pitch: float
var target_distance: float

var _rotating := false
var _panning := false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	snap_to(focus, yaw, pitch, distance)


func _process(delta: float) -> void:
	_keyboard(delta)
	var k := 1.0 if smoothing <= 0.0 else 1.0 - exp(-smoothing * delta)
	var before := Vector4(focus.length(), yaw, pitch, distance)
	focus = focus.lerp(target_focus, k)
	yaw = lerp_angle(yaw, target_yaw, k)
	pitch = lerpf(pitch, target_pitch, k)
	distance = lerpf(distance, target_distance, k)
	target_pitch = maxf(target_pitch, _min_pitch(target_focus.y, target_distance))
	_apply()
	if not before.is_equal_approx(Vector4(focus.length(), yaw, pitch, distance)):
		view_changed.emit()


func _keyboard(delta: float) -> void:
	# ignore keys while a text field (e.g. part search) has focus
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit:
		return
	if Input.is_key_pressed(KEY_LEFT):
		target_yaw += key_orbit_speed * delta
	if Input.is_key_pressed(KEY_RIGHT):
		target_yaw -= key_orbit_speed * delta
	if Input.is_key_pressed(KEY_UP):
		set_height(target_focus.y + target_distance * key_height_speed * delta)
	if Input.is_key_pressed(KEY_DOWN):
		set_height(target_focus.y - target_distance * key_height_speed * delta)
	if Input.is_key_pressed(KEY_PAGEUP):
		target_distance = clampf(target_distance * (1.0 - 1.2 * delta), min_distance, max_distance)
	if Input.is_key_pressed(KEY_PAGEDOWN):
		target_distance = clampf(target_distance * (1.0 + 1.2 * delta), min_distance, max_distance)


## Jumps to a view without easing (also resets the targets).
func snap_to(f: Vector3, y: float, p: float, d: float) -> void:
	focus = f
	yaw = y
	pitch = p
	distance = d
	target_focus = f
	target_yaw = y
	target_pitch = p
	target_distance = d
	_apply()


## Eases to frame a bounding box (vessel or part).
func frame(b: AABB) -> void:
	target_focus = b.get_center()
	target_focus.y = clampf(target_focus.y, min_height, max_height)
	target_distance = clampf(maxf(b.size.y, maxf(b.size.x, b.size.z)) * 1.55 + 8.0, min_distance, max_distance)


func focus_on(point: Vector3, dist := -1.0) -> void:
	target_focus = Vector3(point.x, clampf(point.y, min_height, max_height), point.z)
	if dist > 0.0:
		target_distance = clampf(dist, min_distance, max_distance)


func set_height(y: float) -> void:
	target_focus.y = clampf(y, min_height, max_height)


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = mb.pressed
				return true
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
				return true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not mb.pressed:
					return true
				var s := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				if mb.shift_pressed:
					set_height(target_focus.y - s * maxf(target_distance * 0.06, 0.25))
				else:
					target_distance = clampf(target_distance * (1.0 + 0.12 * s), min_distance, max_distance)
				return true
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			target_yaw -= mm.relative.x * 0.006
			target_pitch = clampf(target_pitch + mm.relative.y * 0.006, deg_to_rad(-80), deg_to_rad(85))
			return true
		if _panning:
			var k := target_distance * 0.0015
			var right := camera.global_transform.basis.x
			target_focus += -right * mm.relative.x * k
			set_height(target_focus.y + mm.relative.y * k)
			return true
	return false


## Lowest pitch that keeps the camera at or above min_camera_height.
func _min_pitch(focus_y: float, dist: float) -> float:
	return asin(clampf((min_camera_height - focus_y) / maxf(dist, 0.01), -1.0, 1.0))


func _apply() -> void:
	if camera == null:
		return
	pitch = maxf(pitch, _min_pitch(focus.y, distance))
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.global_position = focus + off
	camera.look_at(focus, Vector3.UP)
