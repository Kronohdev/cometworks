class_name CwScreenTransition
extends Node
## Opening and closing of a full screen or a modal (scenes/tycoon/ui/screens/*.tscn). Drop it
## under the screen's root and point it at the parts:
##   backdrop -> the dimming ColorRect behind (fades in / out)
##   panel    -> the main panel: slides from `slide`, grows from `from_scale` and fades in;
##               with `overshoot` it pops a little past its size and settles (modals)
##   extra    -> other panels that come in after the main one, `extra_step` apart
## Children cascades inside the panel are CwStagger nodes placed in the scene.
## TycoonHUD.close_screen() calls leave(): the screen leaves the Screens layer at once (so the
## next screen and the game logic carry on), stops taking input and plays the exit, and is
## freed when it ends.
## Sound: `open_sound` as it comes in, `close_sound` as it leaves (CwSfx library names; empty
## = silent).

@export var backdrop: NodePath
@export var panel: NodePath
@export var extra: Array[NodePath] = []
@export_group("In")
@export_range(0.0, 1.5, 0.01) var in_seconds := 0.26
@export_range(0.0, 1.5, 0.01) var backdrop_seconds := 0.2
@export var slide := Vector2(0, 16)
@export var from_scale := Vector2(0.97, 0.97)
## modal pop: the panel grows a little past its size and settles
@export var overshoot := false
@export_range(0.0, 1.0, 0.01) var delay := 0.0
@export_range(0.0, 0.5, 0.01) var extra_step := 0.05
@export var extra_slide := Vector2(0, 12)
@export_group("Out")
@export_range(0.0, 1.0, 0.01) var out_seconds := 0.16
## exit offset (the panel sinks a little while it fades)
@export var out_slide := Vector2(0, 8)
@export var out_scale := Vector2(0.98, 0.98)
@export_group("Sound")
@export var open_sound: StringName = &"ui_open"
@export var close_sound: StringName = &"ui_close"

var _tween: Tween
var _leaving := false


## The transition of a screen, or null.
static func of(screen: Node) -> CwScreenTransition:
	return CwMotion.child_of_type(screen, CwScreenTransition) as CwScreenTransition


func _ready() -> void:
	_set_in(0.0)
	play_in.call_deferred()


func _parts() -> Array[Control]:
	var out: Array[Control] = []
	for p: NodePath in [panel] + extra:
		var c := get_node_or_null(p) as Control
		if c:
			out.append(c)
	return out


func play_in() -> void:
	if not is_inside_tree() or _leaving:
		return
	if _tween:
		_tween.kill()
	if open_sound != &"":
		CwSfx.play(open_sound)
	var reduced := CwMotion.reduced()
	_tween = create_tween().set_parallel(true)
	var bd := get_node_or_null(backdrop) as Control
	if bd:
		_tween.tween_method(_backdrop_at.bind(bd), 0.0, 1.0, backdrop_seconds).set_delay(delay)
	var parts := _parts()
	for i in parts.size():
		var c := parts[i]
		CwMotion.set_pivot(c, Vector2(0.5, 0.5))
		var s := minf(in_seconds, 0.12) if reduced else in_seconds
		var tw := _tween.tween_method(_part_at.bind(c, i, reduced), 0.0, 1.0, s).set_delay(delay + i * extra_step)
		CwMotion.shape(tw, CwMotion.Feel.OVERSHOOT if overshoot and i == 0 and not reduced else CwMotion.Feel.SMOOTH)


func _set_in(k: float) -> void:
	var bd := get_node_or_null(backdrop) as Control
	if bd:
		_backdrop_at(k, bd)
	var parts := _parts()
	for i in parts.size():
		_part_at(k, parts[i], i, CwMotion.reduced())


func _backdrop_at(k: float, bd: Control) -> void:
	CwMotion.set_channel(bd, &"screen", Vector2.ZERO, Vector2.ONE, 0.0, k)


func _part_at(k: float, c: Control, i: int, reduced: bool) -> void:
	if not is_instance_valid(c):
		return
	var a := clampf(k * 1.6, 0.0, 1.0)   # the fade leads the slide: the panel reads early
	if reduced:
		CwMotion.set_channel(c, &"screen", Vector2.ZERO, Vector2.ONE, 0.0, clampf(k, 0.0, 1.0))
		return
	var inv := 1.0 - k
	var off := (slide if i == 0 else extra_slide) * inv
	var sc := from_scale.lerp(Vector2.ONE, k) if i == 0 else Vector2.ONE
	CwMotion.set_channel(c, &"screen", off, sc, 0.0, a)


## Plays the exit; returns its length in seconds.
func play_out() -> float:
	_leaving = true
	if _tween:
		_tween.kill()
	if close_sound != &"":
		CwSfx.play(close_sound)
	var reduced := CwMotion.reduced()
	var s := minf(out_seconds, 0.1) if reduced else out_seconds
	_tween = create_tween().set_parallel(true)
	var bd := get_node_or_null(backdrop) as Control
	if bd:
		_tween.tween_method(_backdrop_at.bind(bd), 1.0, 0.0, s)
	for c in _parts():
		var ref: WeakRef = weakref(c)
		_tween.tween_method(func(k: float) -> void:
			var c2 := ref.get_ref() as Control
			if c2 == null:
				return
			if reduced:
				CwMotion.set_channel(c2, &"screen", Vector2.ZERO, Vector2.ONE, 0.0, 1.0 - k)
			else:
				CwMotion.set_channel(c2, &"screen", out_slide * k, Vector2.ONE.lerp(out_scale, k), 0.0, 1.0 - k),
			0.0, 1.0, s).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	return s


## Takes `screen` (a child of the HUD's Screens layer) out with its exit animation: it is
## moved to `holder` at `index` (below the Screens layer, so a screen opening in its place
## draws on top), stops processing and taking input, and is freed when the exit ends.
## Returns false (and does nothing) when the screen has no transition.
static func leave(screen: Control, holder: Node, index: int) -> bool:
	var t := of(screen)
	if t == null or not screen.is_inside_tree():
		return false
	var vp := screen.get_viewport()
	var focus := vp.gui_get_focus_owner() if vp else null
	if focus and screen.is_ancestor_of(focus):
		focus.release_focus()
	screen.get_parent().remove_child(screen)
	holder.add_child(screen)
	holder.move_child(screen, clampi(index, 0, holder.get_child_count() - 1))
	_mute(screen)
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	var s := t.play_out()
	t._tween.chain().tween_callback(screen.queue_free)
	if s <= 0.0:
		screen.queue_free()
	return true


static func _mute(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(n as Control).focus_mode = Control.FOCUS_NONE
	for c in n.get_children():
		_mute(c)
