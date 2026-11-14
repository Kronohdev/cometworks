class_name CwPanelMotion
extends Node
## Drop this node under any panel (Control) to give it the Cometworks entrance (GDD section
## 22.6): when the panel becomes visible it slides `distance` px from `from_side` and fades in
## over `seconds` with a cubic ease-out. No bounce: the interface stays calm. Works with
## containers too: it moves the panel's drawing through a CwMotion channel, never its layout,
## so it composes with the other motion components (src/tycoon/ui/motion/).

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
	if CwMotion.reduced():
		off = Vector2.ZERO
	_tween = create_tween()
	_tween.tween_method(func(k: float) -> void:
		CwMotion.set_channel(_panel, &"panel", off * (1.0 - k), Vector2.ONE, 0.0, k), 0.0, 1.0, seconds) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	CwMotion.set_channel(_panel, &"panel", off, Vector2.ONE, 0.0, 0.0)
