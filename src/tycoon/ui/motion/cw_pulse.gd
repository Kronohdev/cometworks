class_name CwPulse
extends Node
## A soft pulse of a Control: it swells to `peak_scale`, brightens by `glow` and settles.
## On poke it beats once (a countdown that just ticked: CwMotion.poke(label)); with `loop`
## it breathes forever, one breath every `period` seconds (a logo, a title). Loops are the
## only motion that runs while nothing happens, so keep them to one or two per screen; they
## stop under reduce motion.

## the Control to pulse; empty = this node's parent
@export var target: NodePath
@export var on_poke := true
@export var loop := false
@export var peak_scale := Vector2(1.05, 1.05)
## brightness multiplier at the peak (1 = none)
@export_range(1.0, 2.0, 0.01) var glow := 1.25
## tint at the peak (white = only brightness)
@export var tint := Color.WHITE
@export_range(0.05, 3.0, 0.01) var beat_seconds := 0.45
@export_range(0.5, 20.0, 0.1) var period := 4.0
@export var pivot := Vector2(0.5, 0.5)

var _ctl: Control
var _tween: Tween
var _base := Color.WHITE


func _ready() -> void:
	_ctl = CwMotion.resolve(self, target)
	if _ctl == null:
		return
	_base = _ctl.self_modulate
	CwMotion.set_pivot(_ctl, pivot)
	if loop and not CwMotion.reduced():
		_tween = create_tween().set_loops()
		_tween.tween_method(_at, 0.0, 1.0, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_method(_at, 1.0, 0.0, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _cw_poke() -> void:
	if on_poke:
		beat()


## One beat.
func beat() -> void:
	if _ctl == null or not is_inside_tree() or loop:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(t: float) -> void: _at(sin(t * PI)), 0.0, 1.0, beat_seconds)
	_tween.tween_callback(_at.bind(0.0))


func _at(k: float) -> void:
	if not is_instance_valid(_ctl):
		return
	if not CwMotion.reduced():
		CwMotion.set_channel(_ctl, &"pulse", Vector2.ZERO, Vector2.ONE.lerp(peak_scale, k))
	var g := lerpf(1.0, glow, k)
	var c := _base * Color(g, g, g, 1.0) * Color.WHITE.lerp(tint, k)
	_ctl.self_modulate = Color(c, _base.a)
