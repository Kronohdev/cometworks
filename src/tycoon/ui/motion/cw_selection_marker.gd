class_name CwSelectionMarker
extends Control
## The selection marker of a vertical menu: a slim aurora bar that glides to the item with
## the keyboard focus (mouse hover moves the focus on the menu, so both drive it) and fades
## when the focus leaves the menu. Place it as a sibling of the menu panel, outside any
## container (it positions itself), drawn above the panel; point `items` at the container
## of the entries. Moves only when the focus changes.

## container of the menu entries
@export var items: NodePath
@export var color := Color("#3fe0c5")
@export var color_end := Color("#8e7cff")
@export_range(1.0, 12.0, 0.5) var bar_width := 3.0
## px between the bar and the item's left edge (negative = inside the item)
@export var gap := 6.0
## bar height as a fraction of the item's
@export_range(0.2, 1.0, 0.01) var fill := 0.62
@export_range(0.0, 1.0, 0.01) var glide_seconds := 0.22
@export_range(0.0, 1.0, 0.01) var fade_seconds := 0.16
## soft glow drawn around the bar (alpha)
@export_range(0.0, 1.0, 0.01) var glow := 0.35

var _box: Control
var _tween: Tween
var _shown := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_box = get_node_or_null(items) as Control
	get_viewport().gui_focus_changed.connect(_on_focus)


func _on_focus(c: Control) -> void:
	if _box == null or not is_inside_tree():
		return
	var item := _item_of(c)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	if item == null:
		_tween.tween_property(self, "modulate:a", 0.0, fade_seconds)
		_shown = false
		return
	var r := item.get_global_rect()
	var inv := get_parent_control().get_global_transform().affine_inverse() if get_parent_control() else Transform2D.IDENTITY
	var top_left := inv * r.position
	var h := r.size.y * fill
	var target_pos := top_left + Vector2(-gap - bar_width, (r.size.y - h) * 0.5)
	var target_size := Vector2(bar_width, h)
	var s := 0.0 if CwMotion.reduced() or not _shown else glide_seconds
	if s <= 0.0:
		position = target_pos
		size = target_size
	else:
		_tween.tween_property(self, "position", target_pos, s).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "size", target_size, s).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, fade_seconds)
	_shown = true


func _item_of(c: Control) -> Control:
	if c == null or _box == null:
		return null
	var n: Node = c
	while n and n.get_parent() != _box:
		n = n.get_parent()
	return n as Control if n and n.is_visible_in_tree() else null


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if glow > 0.0:
		for i in 3:
			var g := r.grow(2.0 + i * 2.0)
			draw_rect(g, Color(color, glow / (2.0 + i * 2.0)))
	var n := 8
	for i in n:
		var y0 := r.size.y * float(i) / n
		var y1 := r.size.y * float(i + 1) / n
		draw_rect(Rect2(0.0, y0, r.size.x, y1 - y0 + 0.5), color.lerp(color_end, (float(i) + 0.5) / n))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
