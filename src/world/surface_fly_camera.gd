class_name SurfaceFlyCamera
extends Camera3D
## Free-fly camera for exploring planet surfaces.
## WASD move · Q/E (or Ctrl/Space) down/up · hold right mouse to look
## (or left click to capture, Esc to release) · Shift = fast · wheel = speed.
## Physical keys are read directly, so no InputMap actions are required.

signal speed_changed(speed: float)

@export var speed: float = 25.0
@export var fast_multiplier: float = 8.0
@export var min_speed: float = 1.0
@export var max_speed: float = 4000.0
@export var mouse_sensitivity: float = 0.0025
## Velocity smoothing (higher = snappier).
@export var acceleration: float = 8.0
## Keep at least this far above the terrain (needs `terrain`).
@export var min_clearance: float = 1.6
@export var terrain_path: NodePath
## On start, move to `start_offset` from the origin above the ground and look at the origin.
@export var place_on_start: bool = true
@export var start_offset: Vector3 = Vector3(-70.0, 38.0, 90.0)

var velocity := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _looking := false
var _captured := false
var _terrain: VoxelTerrain


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x
	if not terrain_path.is_empty():
		_terrain = get_node_or_null(terrain_path) as VoxelTerrain
	if place_on_start:
		_place.call_deferred()


func _place() -> void:
	if _terrain == null:
		return
	var g0 := _terrain.get_height(0.0, 0.0)
	var g := _terrain.get_height(start_offset.x, start_offset.z)
	global_position = Vector3(start_offset.x, maxf(g, g0) + start_offset.y, start_offset.z)
	look_toward(Vector3(0.0, g0 + 4.0, 0.0))


func set_terrain(t: VoxelTerrain) -> void:
	_terrain = t


## Points the camera at a world position (keeps yaw/pitch in sync).
func look_toward(target: Vector3) -> void:
	var d := (target - global_position).normalized()
	_yaw = atan2(-d.x, -d.z)
	_pitch = asin(clampf(d.y, -1.0, 1.0))
	_apply_rotation()
	velocity = Vector3.ZERO


func _apply_rotation() -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_looking = mb.pressed
				if not _captured:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_LEFT:
				if mb.pressed and not _captured:
					_captured = true
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_set_speed(speed * 1.25)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_set_speed(speed / 1.25)
	elif event is InputEventMouseMotion and (_looking or _captured):
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, -1.55, 1.55)
		_apply_rotation()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_captured = false
		_looking = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_speed(v: float) -> void:
	speed = clampf(v, min_speed, max_speed)
	speed_changed.emit(speed)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir -= basis.z
	if Input.is_physical_key_pressed(KEY_S):
		dir += basis.z
	if Input.is_physical_key_pressed(KEY_A):
		dir -= basis.x
	if Input.is_physical_key_pressed(KEY_D):
		dir += basis.x
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL):
		dir -= Vector3.UP
	var target := Vector3.ZERO
	if dir != Vector3.ZERO:
		var sp := speed * (fast_multiplier if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		target = dir.normalized() * sp
	velocity = velocity.lerp(target, clampf(acceleration * delta, 0.0, 1.0))
	global_position += velocity * delta
	if _terrain and min_clearance > 0.0:
		var g := _terrain.get_height(global_position.x, global_position.z) + min_clearance
		if global_position.y < g:
			global_position.y = g
			velocity.y = maxf(velocity.y, 0.0)
