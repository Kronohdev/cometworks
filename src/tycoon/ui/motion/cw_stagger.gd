class_name CwStagger
extends Node
## Cascades the children of a container in, one after another: each visible Control child
## fades in from `offset` / `from_scale`, `step` seconds after the previous one. Point
## `target` at the container (empty = this node's parent; keep this node outside lists that
## scripts walk). With `animate_added`, children added later (copies of a list template)
## come in the same way, so filled lists cascade without any script help.

## the container whose children cascade; empty = this node's parent
@export var target: NodePath
@export_group("Triggers")
@export var on_ready := true
@export var on_visible := false
@export var on_poke := false
## children added after the first play also come in (template copies)
@export var animate_added := true
@export_group("Shape")
@export var offset := Vector2(0, 10)
@export var from_scale := Vector2.ONE
@export var pivot := Vector2(0.5, 0.5)
@export_group("Timing")
@export_range(0.0, 3.0, 0.01) var delay := 0.05
@export_range(0.0, 0.5, 0.005) var step := 0.035
@export_range(0.0, 2.0, 0.01) var seconds := 0.24
## the cascade never waits more than this for the last child
@export_range(0.0, 3.0, 0.01) var max_delay := 0.5
@export var curve := CwMotion.Feel.SMOOTH

var _box: Control
var _tween: Tween
var _played_at := -1.0
var _pending: Array[Control] = []


func _ready() -> void:
	_box = CwMotion.resolve(self, target)
	if _box == null:
		return
	if on_visible:
		_box.visibility_changed.connect(func() -> void:
			if _box.visible:
				play())
	if animate_added:
		_box.child_entered_tree.connect(_on_added)
	if on_ready and _box.is_visible_in_tree():
		_hide_all()
		play.call_deferred()


func _cw_poke() -> void:
	if on_poke:
		play()


func _items() -> Array[Control]:
	var out: Array[Control] = []
	for c in _box.get_children():
		if c is Control and (c as Control).visible:
			out.append(c)
	return out


func _hide_all() -> void:
	for c in _items():
		CwMotion.set_channel(c, &"stagger", Vector2.ZERO, Vector2.ONE, 0.0, 0.0)


## Plays the cascade over the current children.
func play() -> void:
	if _box == null or not is_inside_tree():
		return
	if _tween:
		_tween.kill()
	_played_at = Time.get_ticks_msec() / 1000.0
	var items := _items()
	if items.is_empty():
		return
	_tween = create_tween().set_parallel(true)
	for i in items.size():
		_add_item(items[i], delay + minf(i * step, max_delay))


func _add_item(c: Control, d: float) -> void:
	CwMotion.set_pivot(c, pivot)
	var reduced := CwMotion.reduced()
	_item_at(0.0, c, reduced)
	if _tween == null or not _tween.is_valid():
		_tween = create_tween().set_parallel(true)
	CwMotion.shape(_tween.tween_method(_item_at.bind(c, reduced), 0.0, 1.0, minf(seconds, 0.12) if reduced else seconds)
		.set_delay(d * (0.5 if reduced else 1.0)), curve)


func _item_at(k: float, c: Control, reduced: bool) -> void:
	if not is_instance_valid(c):
		return
	if reduced:
		CwMotion.set_channel(c, &"stagger", Vector2.ZERO, Vector2.ONE, 0.0, k)
		return
	var inv := 1.0 - k
	CwMotion.set_channel(c, &"stagger", offset * inv, from_scale.lerp(Vector2.ONE, k), 0.0, clampf(k, 0.0, 1.0))


func _on_added(n: Node) -> void:
	if _played_at < 0.0 or not n is Control or not is_inside_tree() or not can_process():
		return
	var c := n as Control
	# copies arrive in a burst (one refresh): each one a step after the one before
	_pending.append(c)
	if _pending.size() == 1:
		_flush.call_deferred()


func _flush() -> void:
	var batch := _pending.duplicate()
	_pending.clear()
	if not is_inside_tree() or not can_process():
		return   # a screen moved out to play its exit re-enters the tree: leave it be
	var elapsed := Time.get_ticks_msec() / 1000.0 - _played_at
	# right after the screen opened, keep to the opening cascade's rhythm
	var base := maxf(delay - elapsed, 0.0)
	_tween = create_tween().set_parallel(true)
	var i := 0
	for c: Control in batch:
		if is_instance_valid(c) and c.is_inside_tree() and c.visible:
			_add_item(c, base + minf(i * step, max_delay))
			i += 1
	if i == 0:
		_tween.kill()
