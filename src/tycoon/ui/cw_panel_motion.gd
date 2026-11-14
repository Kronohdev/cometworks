class_name CwPanelMotion
extends Node
## Drop this node under any panel (Control) to give it the Cometworks entrance (GDD section
## 22.6): when the panel becomes visible it slides `distance` px from `from_side` and fades in
## over `seconds` with a cubic ease-out. No bounce: the interface stays calm. Works with
## containers too (it animates the panel's visual offset and modulate, never its layout).

enum Side { BELOW, ABOVE, LEFT, RIGHT }

@export var distance := 8.0
@export var seconds := 0.14
@export var from_side := Side.BELOW
## also play when the scene starts with the panel already visible
@export var on_ready := false

var _tween: Tween
var _panel: Control


func _ready() -> void:
	_panel = get_parent() as Control
	if _panel == null:
		return
	_panel.visibility_changed.connect(_on_visibility)
	if on_ready and _panel.visible:
		play.call_deferred()


func _on_visibility() -> void:
	if _panel.visible:
		play()


func play() -> void:
	if _panel == null or not is_inside_tree():
		return
	if _tween:
		_tween.kill()
	var off := Vector2.ZERO
	match from_side:
		Side.BELOW:
			off = Vector2(0, distance)
		Side.ABOVE:
			off = Vector2(0, -distance)
		Side.LEFT:
			off = Vector2(-distance, 0)
		Side.RIGHT:
			off = Vector2(distance, 0)
	# the panel's own CanvasItem transform offsets the drawing without touching the layout
	_panel.modulate.a = 0.0
	_set_offset(off)
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate:a", 1.0, seconds)
	_tween.tween_method(_set_offset, off, Vector2.ZERO, seconds)


func _set_offset(o: Vector2) -> void:
	var t := _panel.get_transform()
	t.origin += o
	RenderingServer.canvas_item_set_transform(_panel.get_canvas_item(), t)
