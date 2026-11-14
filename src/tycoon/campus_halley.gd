class_name CampusHalley
extends Node3D
## Vovô Edmundo on the campus in the agency's first year (the "Halley" node of tycoon_main.tscn,
## placed in the editor on the bench by the workshop): he sits there watching, and when one of
## his lessons starts (TycoonTutorial.lesson_started) he gets up, turns to the camera and waves,
## then sits down again when it ends. From the second year on he stays home on the hill.

## the last campaign year he comes down to the campus
@export var last_year := 1
## where he stands to wave, from the bench (local: down to the ground and a step forward)
@export var stand_offset := Vector3(0.0, -0.55, 0.75)

var main: TycoonMain
var _seat := Vector3.ZERO
var _standing := false

@onready var halley: Halleyzinho = $Halleyzinho


func _ready() -> void:
	main = owner as TycoonMain
	halley.listen_to_events = false
	halley.play("sit")
	_seat = halley.position
	if main:
		_refresh.call_deferred()   # the main screen binds its state and lessons after its children


func _refresh() -> void:
	if main == null or main.state == null:
		return
	if main.tutorial and not main.tutorial.lesson_started.is_connected(_on_lesson_started):
		main.tutorial.lesson_started.connect(_on_lesson_started)
		main.tutorial.lesson_finished.connect(_on_lesson_finished)
	if not main.state.year_passed.is_connected(_on_year):
		main.state.year_passed.connect(_on_year)
	visible = main.state.year() <= last_year


func _on_year(_year: int) -> void:
	_refresh()


func _on_lesson_started(_id: String) -> void:
	if not visible:
		return
	_standing = true
	halley.play("idle")
	_move_to(_seat + stand_offset)
	var cam := get_viewport().get_camera_3d()
	if cam:
		halley.look_at_point(cam.global_position, 0.8)
	halley.play_sequence(["wave", "nod"])


func _on_lesson_finished(_id: String, _skipped: bool) -> void:
	if not _standing:
		return
	_standing = false
	halley.clear_look()
	halley.play("sit")
	_move_to(_seat)


## A small hop between the bench and the ground.
func _move_to(p: Vector3) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(halley, "position", p, 0.45)
