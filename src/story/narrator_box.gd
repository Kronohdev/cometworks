class_name NarratorBox
extends Control
## Vovô Edmundo Halleyzinho telling a story (scenes/story/narrator_box.tscn): the speech bubble
## of his lessons (the tutorial's CwPanelTop look) with his live portrait (halley_portrait.tscn),
## his name and the line typed out. Everything you see is in the scene; this script types the
## text and moves his portrait (talking while it types, a habit or a one-shot per line).
## Used by the story cutscenes (src/cutscene/cutscene.gd); any screen can drop the scene in
## and call say() / hush().
##   say(text, pose, face)   a new line (typed out; pose: one of Halleyzinho.HABITS or a
##                           Cometling one-shot; face: a Cometling expression)
##   finish_typing()         shows the whole line at once (a tap)
##   hush()                  the bubble goes away
## The portrait's viewport only renders while the bubble is up.

## a line came up / finished typing
signal line_started(text: String)
signal line_typed

## letters per second of the typewriter
@export_range(5.0, 200.0, 1.0) var type_speed := 50.0

var _typing := false
var _shown := 0.0
var _text := ""

@onready var bubble: Control = %Bubble
@onready var text_label: Label = %Text
@onready var portrait: SubViewportContainer = %Portrait
@onready var halley: Halleyzinho = %Portrait.get_node("Viewport/Halley")


func _ready() -> void:
	bubble.visible = false
	text_label.text = ""
	_live(false)


## A new line: the bubble comes up (if it was down), the text types out and Vovô talks.
func say(text: String, pose := "", face := "") -> void:
	_text = text
	text_label.text = text
	_shown = 0.0
	_typing = not CwMotion.reduced() and type_speed > 0.0
	text_label.visible_characters = 0 if _typing else -1
	if not bubble.visible:
		bubble.visible = true
		_live(true)
	if face != "":
		halley.set_expression(face, 5.0)
	if pose != "":
		if pose in Halleyzinho.HABITS:
			halley.play_habit(pose)
		elif Cometling.ONESHOTS.has(pose):
			halley.play(pose)
	halley.talk(_typing)
	line_started.emit(text)
	if not _typing:
		line_typed.emit()


## The bubble goes away (the line is over, or the story ended).
func hush() -> void:
	_typing = false
	_text = ""
	text_label.text = ""
	if bubble.visible:
		bubble.visible = false
		halley.talk(false)
		_live(false)


## Shows the rest of the line at once.
func finish_typing() -> void:
	if not _typing:
		return
	_typing = false
	text_label.visible_characters = -1
	halley.talk(false)
	line_typed.emit()


func is_typing() -> bool:
	return _typing


func is_showing() -> bool:
	return bubble.visible


## The line on show ("" when the bubble is down).
func current_text() -> String:
	return _text


## Seconds the typewriter needs for `text` at this box's speed.
func type_seconds(text: String) -> float:
	return float(text.length()) / maxf(type_speed, 1.0)


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * type_speed
	var total := text_label.get_total_character_count()
	if int(_shown) >= total:
		finish_typing()
	else:
		text_label.visible_characters = int(_shown)


func _live(on: bool) -> void:
	var vp := portrait.get_node("Viewport") as SubViewport
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
