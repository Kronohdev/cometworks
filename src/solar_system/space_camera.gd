class_name SpaceCamera
extends Node3D
## Orbit / fly camera for the solar-system map. The Camera3D child is authored in
## scenes/solar_system/solar_system.tscn.
##   RMB drag: orbit · wheel / PageUp / PageDown: zoom (exponential) · MMB drag: pan
##   WASD / arrows: fly the focus point along the view plane · Q/E: down/up
## focus_on(node) tracks a moving body; every change eases in smoothly (exponential
## smoothing toward target values, frame-rate independent).

signal focus_changed(target: Node3D)

@export var focus := Vector3.ZERO
@export_range(-180, 180, 0.1, "radians_as_degrees") var yaw := deg_to_rad(-30.0)
@export_range(-89, 89, 0.1, "radians_as_degrees") var pitch := deg_to_rad(28.0)
@export var distance := 300.0
@export var min_distance := 2.0
@export var max_distance := 2600.0
## Higher = snappier. 0 disables smoothing.
@export var smoothing := 6.0
@export var orbit_sensitivity := 0.006
@export var zoom_step := 1.15
@export var fly_speed := 0.8  # fraction of distance per second

var target_yaw: float
var target_pitch: float
var target_distance: float
## Body being tracked (null = free focus point).
var target: Node3D = null
var target_radius := 1.0

var _free_focus := Vector3.ZERO
## Offset that eases to zero after a focus change, so the camera glides between bodies.
var _glide := Vector3.ZERO
var _rotating := false
var _panning := false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	snap_to(focus, yaw, pitch, distance)


func snap_to(f: Vector3, y: float, p: float, d: float) -> void:
	target = null
	_free_focus = f
	_glide = Vector3.ZERO
	focus = f
	yaw = y
	pitch = p
	distance = d
	target_yaw = y
	target_pitch = p
	target_distance = d
	_apply()


## Track `node` (a SolarBody's Anchor or any Node3D). `radius` sets the zoom limits.
func focus_on(node: Node3D, radius: float, view_distance := -1.0) -> void:
	var old := focus
	target = node
	target_radius = maxf(radius, 0.1)
	min_distance = target_radius * 1.35
	_glide = old - node.global_position
	target_distance = view_distance if view_distance > 0.0 else target_radius * 5.5
	focus_changed.emit(node)


func free_focus(at: Vector3, view_distance := -1.0) -> void:
	_glide = focus - at
	target = null
	_free_focus = at
	min_distance = 2.0
	if view_distance > 0.0:
		target_distance = view_distance
	focus_changed.emit(null)


func _process(delta: float) -> void:
	_keyboard(delta)
	var k := 1.0 if smoothing <= 0.0 else 1.0 - exp(-smoothing * delta)
	var base := target.global_position if is_instance_valid(target) else _free_focus
	_glide = _glide.lerp(Vector3.ZERO, k)
	focus = base + _glide
	target_distance = clampf(target_distance, min_distance, max_distance)
	yaw = lerp_angle(yaw, target_yaw, k)
	pitch = lerpf(pitch, target_pitch, k)
	# zoom eases in log space so big jumps (Sun -> Neptune) feel even
	distance = exp(lerpf(log(distance), log(target_distance), k))
	_apply()


func _apply() -> void:
	var off := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
	global_position = focus + off
	if off.length_squared() > 1e-8:
		look_at(focus, Vector3.UP)


func _keyboard(delta: float) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit:
		return
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_E):
		v.y += 1
	if Input.is_key_pressed(KEY_Q):
		v.y -= 1
	if Input.is_key_pressed(KEY_PAGEUP):
		target_distance /= pow(zoom_step, delta * 8.0)
	if Input.is_key_pressed(KEY_PAGEDOWN):
		target_distance *= pow(zoom_step, delta * 8.0)
	if v != Vector3.ZERO:
		_detach()
		var b := global_transform.basis
		var fwd := Vector3(b.z.x, 0, b.z.z).normalized()
		var right := Vector3(b.x.x, 0, b.x.z).normalized()
		_free_focus += (right * v.x + fwd * v.z + Vector3.UP * v.y) * distance * fly_speed * delta


func _detach() -> void:
	if is_instance_valid(target):
		_free_focus = focus
		_glide = Vector3.ZERO
		target = null
		min_distance = 2.0
		focus_changed.emit(null)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					target_distance /= zoom_step
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					target_distance *= zoom_step
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			target_yaw -= mm.relative.x * orbit_sensitivity
			target_pitch = clampf(target_pitch + mm.relative.y * orbit_sensitivity, deg_to_rad(-88), deg_to_rad(88))
		elif _panning:
			_detach()
			var b := global_transform.basis
			var s := distance * 0.0016
			_free_focus += (-b.x * mm.relative.x + b.y * mm.relative.y) * s
