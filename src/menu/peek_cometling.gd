class_name PeekCometling
extends Control
## A Cometling that leans out from behind the menu panel and waves (scenes/menu/peek_cometling.tscn).
## The little 3D stage (SubViewport with its own world: light, camera, Cometling) is
## authored in the scene; place this Control in the menu where the Cometling should end
## up, *behind* the panel in the tree, and it slides in from `hidden_offset`.
## The UI stays calm; the Cometling is the one that bounces.

@export var hidden_offset := Vector2(-110, 0)
@export var slide_in := 0.38
@export var slide_out := 0.22
@export var emotes: PackedStringArray = ["happy", "heart", "star", "rocket"]

var shown := false
var _home := Vector2.ZERO
var _tween: Tween
var _emote_i := 0

@onready var creature: Node3D = $View/Viewport/Creature


func _ready() -> void:
	_home = position
	position = _home + hidden_offset
	visible = false


func peek() -> void:
	if shown:
		return
	shown = true
	visible = true
	_kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", _home, slide_in).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	creature.call("play", "wave")
	creature.call("show_emote", emotes[_emote_i % emotes.size()], 1.8)
	_emote_i += 1


func unpeek() -> void:
	if not shown:
		return
	shown = false
	_kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", _home + hidden_offset, slide_out).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: visible = false)


func _kill() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
