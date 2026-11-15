class_name CampusSign
extends Node3D
## One story sign on the campus island (scenes/tycoon/campus_sign.tscn, placed by hand in
## scenes/tycoon/campus_signs.tscn). The look is all in the scene: the wooden board with its
## frame, nails and posts (Board), one painted face per kind with its little voxel picture
## (Board/Faces/Lore a comet, History a rocket, Joke a smiley), the tarp that covers it until it
## uncovers (Board/Cover) and the little star over an unread sign (NewMark). This script only
## switches them; the hover tag is CampusSigns' (a sticker on the screen, campus_signs.tscn).

## the sign's id in data/tycoon/story_signs.json
@export var sign_id := ""
## how much the sign grows under the mouse
@export var hover_scale := 1.12

var kind := "lore"
var unlocked := true
var read := false
var _hover := false
var _tween: Tween

@onready var faces: Node3D = $Board/Faces
@onready var cover: Node3D = $Board/Cover
@onready var new_mark: Node3D = $NewMark
@onready var board: Node3D = $Board
@onready var pick: Marker3D = $PickPoint


## Shows the face of the sign's kind (lore / history / joke).
func set_kind(k: String) -> void:
	kind = k
	for f in faces.get_children():
		(f as Node3D).visible = String(f.name).to_lower() == k


## Covered until it uncovers; the star marks an uncovered sign nobody has read.
func set_state(is_unlocked: bool, is_read: bool) -> void:
	unlocked = is_unlocked
	read = is_read
	cover.visible = not unlocked
	faces.visible = unlocked
	new_mark.visible = unlocked and not read


## The mouse is over the sign: it grows a little (CampusSigns shows the tag).
func set_hover(on: bool) -> void:
	if on == _hover:
		return
	_hover = on
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(board, "scale", Vector3.ONE * (hover_scale if on else 1.0), 0.18)


func is_hovered() -> bool:
	return _hover


## Where the board is (the point the mouse is tested against).
func pick_point() -> Vector3:
	return pick.global_position


## Where the hover tag points: just over the board (the unread star's place).
func tag_point() -> Vector3:
	return new_mark.global_position
