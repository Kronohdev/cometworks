class_name CwTooltipFade
extends Node
## Fades tooltips in (and lifts them `rise` px) instead of popping them. Drop one anywhere in
## a scene (the HUD, the main menu); while it is in the tree it watches for the engine's
## tooltip popup and animates its contents when it appears.

@export_range(0.0, 1.0, 0.01) var seconds := 0.14
@export var rise := Vector2(0, 4)


func _enter_tree() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is PopupPanel and (n as Window).theme_type_variation == &"TooltipPanel":
		_fade.call_deferred(n)


func _fade(w: Node) -> void:
	if not is_instance_valid(w) or not w.is_inside_tree():
		return
	var parts: Array[Control] = []
	for c in w.get_children(true):
		if c is Control:
			parts.append(c)
	if parts.is_empty():
		return
	var reduced := CwMotion.reduced()
	var tw := create_tween().set_parallel(true)
	for c in parts:
		var ref: WeakRef = weakref(c)
		tw.tween_method(func(k: float) -> void:
			var c2 := ref.get_ref() as Control
			if c2:
				CwMotion.set_channel(c2, &"tip", Vector2.ZERO if reduced else rise * (1.0 - k), Vector2.ONE, 0.0, k),
			0.0, 1.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
