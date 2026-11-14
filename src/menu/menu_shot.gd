@tool
class_name MenuShot
extends Node3D
## One shot of the main-menu attract loop (scenes/menu/shots/*.tscn). Everything is authored
## in the shot's scene: its own WorldEnvironment, lights, props, Cometlings and Camera3D.
## This script only moves the camera and starts the cues:
##   - camera: eases along the Marker3D nodes in `path` (a smooth curve through their
##     positions). Without `look_target` it also blends their rotations, so each marker is a
##     framing you can line up in the editor ("preview" scrubs the camera along the path).
##   - cues: the AnimationPlayer's `animation` starts with the shot (rocket liftoff, cheers,
##     emotes: method tracks on the Cometlings, value tracks on props).
##   - `watchers` turn their heads toward `watch_target` every frame (a crowd following a rocket).
## The director (src/menu/menu_director.gd) calls begin() and waits for `finished`.

signal finished

@export var duration := 11.0
## Translation key of the observatory readout under the menu (e.g. MENU_SHOT_LAUNCH).
@export var caption_key := ""
@export var camera: Camera3D
## Camera path: markers in order. One marker = a locked-off shot.
@export var path: Array[Node3D] = []
## Optional: the camera keeps looking at this node instead of using the markers' rotation.
@export var look_target: Node3D
## 0 = constant speed along the path, 1 = ease in and out (gentle starts and stops).
@export_range(0.0, 1.0) var easing := 0.5
@export var animation_player: AnimationPlayer
@export var animation := &"shot"
## Cometlings whose heads follow watch_target.
@export var watchers: Array[Node3D] = []
@export var watch_target: Node3D
@export_range(0.0, 1.0) var watch_weight := 0.9
## Editor only: places the camera at this fraction of the path.
@export_range(0.0, 1.0) var preview := 0.0:
	set(v):
		preview = v
		if Engine.is_editor_hint() and is_inside_tree():
			place_camera(v)

var time := 0.0
var _running := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	place_camera(0.0)
	if animation_player:
		animation_player.stop()


## Starts the shot from the beginning (camera at the first marker, cues from 0 s).
func begin() -> void:
	time = 0.0
	_running = true
	if camera:
		camera.make_current()
	place_camera(0.0)
	if animation_player and animation_player.has_animation(animation):
		animation_player.play(animation)
		animation_player.seek(0.0, true)


## 0..1 progress through the shot.
func progress() -> float:
	return clampf(time / maxf(duration, 0.01), 0.0, 1.0)


## Jumps to `t` seconds (screenshot tools): camera and cues follow.
func seek(t: float) -> void:
	time = t
	place_camera(progress())
	if animation_player and animation_player.has_animation(animation):
		animation_player.seek(t, true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _running:
		return
	time += delta
	place_camera(progress())
	if watch_target:
		var p := watch_target.global_position
		for w in watchers:
			if w and w.has_method("look_at_point"):
				w.call("look_at_point", p, watch_weight)
	if time >= duration:
		_running = false
		finished.emit()


func place_camera(u: float) -> void:
	if camera == null or path.is_empty():
		return
	u = lerpf(u, u * u * (3.0 - 2.0 * u), easing)
	var n := path.size()
	var pos: Vector3
	var rot: Quaternion
	if n == 1:
		pos = path[0].global_position
		rot = path[0].global_basis.get_rotation_quaternion()
	else:
		var f := u * float(n - 1)
		var i := mini(int(f), n - 2)
		var t := f - float(i)
		var p0 := path[maxi(i - 1, 0)].global_position
		var p1 := path[i].global_position
		var p2 := path[i + 1].global_position
		var p3 := path[mini(i + 2, n - 1)].global_position
		pos = _catmull(p0, p1, p2, p3, t)
		rot = path[i].global_basis.get_rotation_quaternion().slerp(
			path[i + 1].global_basis.get_rotation_quaternion(), t)
	if look_target:
		var dir := look_target.global_position - pos
		if dir.length_squared() > 1e-6:
			camera.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
			return
	camera.global_transform = Transform3D(Basis(rot), pos)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
