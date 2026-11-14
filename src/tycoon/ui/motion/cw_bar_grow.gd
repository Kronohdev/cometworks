class_name CwBarGrow
extends Node
## Grows a bar from empty when it first shows (the race board, the lanes of the race screen).
## Under a CwSegmentBar the cells light up one after another from zero at the bar's own
## pace (`cells_per_second`); under any other Control (a ColorRect progress line) the drawing
## grows from the `pivot` edge over `seconds`. Copies of list templates grow when created.

## the bar; empty = this node's parent
@export var target: NodePath
@export_range(0.0, 3.0, 0.01) var delay := 0.1
## extra delay per index among the visible siblings of the bar's row (the board cascades)
@export_range(0.0, 0.5, 0.005) var index_delay := 0.06
## which node's index counts for index_delay: the bar (0), its parent (1), ...
@export_range(0, 4) var index_depth := 1
@export_range(0.05, 3.0, 0.01) var seconds := 0.7
## the edge it grows from (x 0 = left)
@export var pivot := Vector2(0.0, 0.5)

var _ctl: Control


func _ready() -> void:
	_ctl = CwMotion.resolve(self, target)
	if _ctl == null or not _ctl.is_visible_in_tree():
		return
	var d := delay + _index() * index_delay
	if CwMotion.reduced():
		return
	if _ctl is CwSegmentBar:
		_grow_segments.call_deferred(d)
		return
	CwMotion.set_pivot(_ctl, pivot)
	CwMotion.set_channel(_ctl, &"grow", Vector2.ZERO, Vector2(0.0, 1.0))
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(_ctl):
			CwMotion.set_channel(_ctl, &"grow", Vector2.ZERO, Vector2(k, 1.0)), 0.0, 1.0, seconds) \
		.set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The segment bar animates value changes itself: start it from zero (after the script that
## fills it has set the value) and let it light up.
func _grow_segments(d: float) -> void:
	var bar := _ctl as CwSegmentBar
	if not is_instance_valid(bar) or not bar.animate:
		return
	bar.set("_shown", 0.0)
	bar.queue_redraw()
	if d <= 0.0:
		bar.set_process(true)
		return
	bar.set_process(false)
	var ref: WeakRef = weakref(bar)   # the screen may close before the timer fires
	get_tree().create_timer(d).timeout.connect(func() -> void:
		var b: Object = ref.get_ref()
		if b:
			(b as Node).set_process(true))


func _index() -> int:
	var n: Node = _ctl
	for i in index_depth:
		if n.get_parent() == null:
			break
		n = n.get_parent()
	var p := n.get_parent()
	if p == null:
		return 0
	var i := 0
	for c in p.get_children():
		if c == n:
			return i
		if c is CanvasItem and (c as CanvasItem).visible:
			i += 1
	return i
