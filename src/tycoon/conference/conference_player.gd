class_name ConferencePlayer
extends Node3D
## The player's leader Cometling at the Conferência dos Cometinhos' fair
## (scenes/tycoon/conference/conference_fair.tscn, node Player; the body is the shared Cometling
## dressed by TycoonLeader.dress). Third person, over the shoulder: the camera sits behind and a
## little above the right shoulder and looks where the mouse (or the right stick) points; WASD /
## the arrows / the left stick walk relative to the camera, Shift (or the left trigger) runs, and
## the body turns toward where it walks. The fair gives `collide` (a step is clipped against the
## stands, the Lendas and the venue's edge) and turns `enabled` off while a conversation or the
## pause menu is up. No physics bodies: the venue is flat.
## Tunables come from data/tycoon/conference.json "player" (ConferenceBook.player_cfg).

@export var walk_speed := 4.2
@export var run_speed := 7.5
@export var turn_rate := 12.0
@export var mouse_sensitivity := 0.0028
## radians per second at full stick
@export var stick_sensitivity := 2.6
@export var camera_distance := 4.2
@export var camera_height := 2.15
## the camera's sideways offset to the right (m): the "shoulder"
@export var shoulder := 0.85
@export var pitch_min_deg := -40.0
@export var pitch_max_deg := 35.0

var camera: Camera3D
var creature: Cometling
## camera yaw (rad; 0 looks toward -Z) and pitch (rad; negative looks down)
var yaw := 0.0
var pitch := -0.18
## input on (off while talking or in the pause menu)
var enabled := true
## func(from: Vector2, to: Vector2) -> Vector2: where a step from `from` toward `to` ends
var collide := Callable()
var velocity := Vector3.ZERO


func _ready() -> void:
	creature = get_node_or_null("Creature") as Cometling
	_tune_gait()


func configure() -> void:
	walk_speed = ConferenceBook.player_cfg("walk_speed", walk_speed)
	run_speed = ConferenceBook.player_cfg("run_speed", run_speed)
	turn_rate = ConferenceBook.player_cfg("turn_rate", turn_rate)
	mouse_sensitivity = ConferenceBook.player_cfg("mouse_sensitivity", mouse_sensitivity)
	stick_sensitivity = ConferenceBook.player_cfg("stick_sensitivity", stick_sensitivity)
	camera_distance = ConferenceBook.player_cfg("camera_distance", camera_distance)
	camera_height = ConferenceBook.player_cfg("camera_height", camera_height)
	shoulder = ConferenceBook.player_cfg("shoulder", shoulder)
	pitch_min_deg = ConferenceBook.player_cfg("pitch_min", pitch_min_deg)
	pitch_max_deg = ConferenceBook.player_cfg("pitch_max", pitch_max_deg)
	_tune_gait()


## The body walks at walk_speed and runs only with Shift: its walk / run blend is set from
## these speeds (in the Cometling's own units, it stands scaled up).
func _tune_gait() -> void:
	if creature == null:
		return
	var s := maxf(creature.scale.x, 0.01)
	creature.run_speed = Vector2(walk_speed * 1.12, maxf(run_speed * 0.9, walk_speed * 1.3)) / s


## Puts the body where it starts, the camera behind it looking the same way.
func place(at: Vector3, facing_yaw: float) -> void:
	position = at
	rotation.y = facing_yaw
	yaw = facing_yaw + PI   # the body faces +Z at yaw 0; the camera looks toward -Z
	velocity = Vector3.ZERO
	update_camera(0.0, true)


## The way the camera looks, flat (unit, y = 0).
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func head() -> Vector3:
	return global_position + Vector3.UP * 1.5


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * mouse_sensitivity
		pitch = clampf(pitch - mm.relative.y * mouse_sensitivity, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # a click in the world takes the mouse back
		get_viewport().set_input_as_handled()


static func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


static func _axis(a: JoyAxis) -> float:
	var v := Input.get_joy_axis(0, a)
	return 0.0 if absf(v) < 0.2 else v


## The walk input on this frame: x = right, y = forward (length <= 1).
func move_input() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var v := Vector2(_key(KEY_D) + _key(KEY_RIGHT) - _key(KEY_A) - _key(KEY_LEFT),
		_key(KEY_W) + _key(KEY_UP) - _key(KEY_S) - _key(KEY_DOWN))
	v += Vector2(_axis(JOY_AXIS_LEFT_X), -_axis(JOY_AXIS_LEFT_Y))
	return v.limit_length(1.0)


func running() -> bool:
	return enabled and (Input.is_physical_key_pressed(KEY_SHIFT) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5)


func _process(delta: float) -> void:
	step(delta)


## One frame of walking and of the camera (the fair runs it; tests call it with their delta).
func step(delta: float) -> void:
	if enabled:
		var look := Vector2(_axis(JOY_AXIS_RIGHT_X), _axis(JOY_AXIS_RIGHT_Y))
		yaw -= look.x * stick_sensitivity * delta
		pitch = clampf(pitch - look.y * stick_sensitivity * delta, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	var inp := move_input()
	var fwd := forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var wish := right * inp.x + fwd * inp.y
	var target := wish * (run_speed if running() else walk_speed)
	velocity = velocity.lerp(target, 1.0 - exp(-delta * 10.0))
	if velocity.length() < 0.02 and inp == Vector2.ZERO:
		velocity = Vector3.ZERO
	var from := Vector2(position.x, position.z)
	var to := from + Vector2(velocity.x, velocity.z) * delta
	if collide.is_valid():
		to = collide.call(from, to)
	position = Vector3(to.x, position.y, to.y)
	var moved := Vector3(to.x - from.x, 0.0, to.y - from.y) / maxf(delta, 0.0001)
	if moved.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(moved.x, moved.z), 1.0 - exp(-delta * turn_rate))
	if creature:
		creature.set_move_velocity(moved if delta > 0.0 else Vector3.ZERO)
	update_camera(delta)


## Over the shoulder: behind the head, `shoulder` to the right, looking along yaw / pitch.
func update_camera(delta: float, snap := false) -> void:
	if camera == null:
		return
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var pivot := global_position + Vector3.UP * camera_height
	var want := pivot + b * Vector3(shoulder, 0.0, camera_distance)
	want.y = maxf(want.y, global_position.y + 0.45)   # never under the floor
	if snap or delta <= 0.0:
		camera.global_position = want
	else:
		camera.global_position = camera.global_position.lerp(want, 1.0 - exp(-delta * 14.0))
	camera.global_basis = b
