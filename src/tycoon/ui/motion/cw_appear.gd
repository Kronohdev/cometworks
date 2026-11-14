class_name CwAppear
extends Node
## Entrance (and exit) of one Control: it fades in from `from_alpha`, slides from `offset` and
## grows from `from_scale`, after `delay` (+ `index_delay` per position among its siblings, so
## copies of a list template cascade). Drop it under the Control (or point `target` at it)
## and pick when it plays: on ready, whenever the control becomes visible, and/or when a
## script calls CwMotion.poke(control) (a news line that changed, a toast). play_out()
## runs it backwards (used by CwScreenTransition and by scripts that hide things).
## Only the drawing moves (CwMotion channels): the layout and the hit area stay put.

## the Control to move; empty = this node's parent
@export var target: NodePath
@export_group("Triggers")
@export var on_ready := true
@export var on_visible := false
@export var on_poke := false
@export_group("Shape")
## start offset in px (drawing only)
@export var offset := Vector2(0, 10)
@export var from_scale := Vector2.ONE
@export_range(0.0, 1.0, 0.01) var from_alpha := 0.0
## start rotation in degrees
@export_range(-45.0, 45.0, 0.5) var from_degrees := 0.0
## scale / rotation pivot, as a fraction of the control's size
@export var pivot := Vector2(0.5, 0.5)
@export_group("Timing")
@export_range(0.0, 2.0, 0.01) var seconds := 0.22
@export_range(0.0, 3.0, 0.01) var delay := 0.0
## extra delay per index among the visible siblings (list cascades)
@export_range(0.0, 0.5, 0.005) var index_delay := 0.0
## cap for index_delay so long lists do not wait forever
@export_range(0.0, 3.0, 0.01) var max_index_delay := 0.4
@export var curve := CwMotion.Feel.SMOOTH
@export_group("Exit")
@export_range(0.0, 2.0, 0.01) var out_seconds := 0.14
## exit offset as a fraction of `offset`
@export_range(-2.0, 2.0, 0.05) var out_offset := 0.5

var _tween: Tween
var _ctl: Control


func _ready() -> void:
	_ctl = CwMotion.resolve(self, target)
	if _ctl == null:
		return
	if on_visible:
		_ctl.visibility_changed.connect(func() -> void:
			if _ctl.visible:
				play())
	if on_ready and _ctl.is_visible_in_tree():
		_hide_now()
		play.call_deferred()


func _cw_poke() -> void:
	if on_poke:
		play()


func _hide_now() -> void:
	CwMotion.set_pivot(_ctl, pivot)
	_at(0.0)


## Plays the entrance from the start.
func play() -> void:
	if _ctl == null or not is_inside_tree():
		return
	if _tween:
		_tween.kill()
	CwMotion.set_pivot(_ctl, pivot)
	var d := delay + minf(_index() * index_delay, max_index_delay)
	if CwMotion.reduced():
		_set_fade_only(0.0)
		_tween = create_tween()
		_tween.tween_method(_set_fade_only, 0.0, 1.0, minf(seconds, 0.12)).set_delay(d * 0.5)
		return
	_at(0.0)
	_tween = create_tween()
	CwMotion.shape(_tween.tween_method(_at, 0.0, 1.0, seconds).set_delay(d), curve)


## Runs the exit; returns how long it takes.
func play_out() -> float:
	if _ctl == null or not is_inside_tree():
		return 0.0
	if _tween:
		_tween.kill()
	var s := minf(out_seconds, 0.1) if CwMotion.reduced() else out_seconds
	_tween = create_tween()
	CwMotion.shape(_tween.tween_method(_set_out, 0.0, 1.0, s), CwMotion.Feel.SMOOTH, true)
	return s


## Snaps to the resting state.
func finish() -> void:
	if _tween:
		_tween.kill()
	if _ctl:
		CwMotion.clear_channel(_ctl, &"appear")


func _index() -> int:
	var p := _ctl.get_parent()
	if p == null or index_delay <= 0.0:
		return 0
	var i := 0
	for c in p.get_children():
		if c == _ctl:
			return i
		if c is CanvasItem and (c as CanvasItem).visible:
			i += 1
	return i


func _at(k: float) -> void:
	var inv := 1.0 - k
	CwMotion.set_channel(_ctl, &"appear", offset * inv, from_scale.lerp(Vector2.ONE, k),
		deg_to_rad(from_degrees) * inv, lerpf(from_alpha, 1.0, clampf(k, 0.0, 1.0)))


func _set_fade_only(k: float) -> void:
	CwMotion.set_channel(_ctl, &"appear", Vector2.ZERO, Vector2.ONE, 0.0, lerpf(from_alpha, 1.0, k))


func _set_out(k: float) -> void:
	if CwMotion.reduced():
		CwMotion.set_channel(_ctl, &"appear", Vector2.ZERO, Vector2.ONE, 0.0, 1.0 - k)
		return
	CwMotion.set_channel(_ctl, &"appear", offset * out_offset * k, Vector2.ONE.lerp(from_scale, k * 0.5),
		0.0, 1.0 - k)
