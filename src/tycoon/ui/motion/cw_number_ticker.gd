class_name CwNumberTicker
extends Node
## Makes a number Label count to its new value instead of jumping, with a short colour flash
## (green when it goes up, red when it goes down) and a small pop. Drop it under the Label;
## the script that fills the label calls CwNumberTicker.show(label, value, formatter) instead
## of setting `text` (without a ticker under the label that is a plain text set).
## Sound: with the flash comes a blip (`sound_up` / `sound_down`, CwSfx library names); a
## ticker without a flash (flash_strength 0, the launch card's grade) stays silent.

@export_range(0.0, 3.0, 0.01) var seconds := 0.6
@export var flash_up := Color("#5bd68e")
@export var flash_down := Color("#ff5c6c")
## how strongly the flash tints the label (0 = no flash)
@export_range(0.0, 1.0, 0.01) var flash_strength := 0.85
@export_range(0.0, 3.0, 0.01) var flash_seconds := 0.7
## changes smaller than this jump without a flash (weekly upkeep is not news)
@export var flash_min_delta := 0.0
## scale at the peak of the pop (1 = none)
@export var pop_scale := Vector2(1.06, 1.06)
@export var pivot := Vector2(0.0, 0.5)
@export var sound_up: StringName = &"cash_up"
@export var sound_down: StringName = &"cash_down"

var _label: Label
var _value := 0.0
var _shown := 0.0
var _has := false
var _fmt: Callable
var _tween: Tween
var _flash: Tween


## Shows `value` on `label` through its ticker, or sets the text when it has none.
static func show(label: Label, value: float, fmt: Callable) -> void:
	var t := CwMotion.child_of_type(label, CwNumberTicker) as CwNumberTicker
	if t == null or not t.is_inside_tree():
		label.text = fmt.call(value)
		return
	t.to(value, fmt)


func _ready() -> void:
	_label = get_parent() as Label


func to(value: float, fmt: Callable) -> void:
	_fmt = fmt
	if _label == null:
		return
	if not _has or is_equal_approx(value, _value):
		_has = true
		_value = value
		_shown = value
		_label.text = fmt.call(value)
		return
	var delta := value - _value
	_value = value
	if _tween:
		_tween.kill()
	if CwMotion.reduced() or seconds <= 0.0:
		_show(value)
	else:
		_tween = create_tween()
		_tween.tween_method(_show, _shown, value, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if absf(delta) >= flash_min_delta and absf(delta) > 0.0:
		_do_flash(flash_up if delta > 0.0 else flash_down)
		var snd := sound_up if delta > 0.0 else sound_down
		if flash_strength > 0.0 and snd != &"":
			CwSfx.play(snd)


func _show(v: float) -> void:
	_shown = v
	if _label and _fmt.is_valid():
		_label.text = _fmt.call(v)


func _do_flash(col: Color) -> void:
	if _flash:
		_flash.kill()
	var tint := Color.WHITE.lerp(col, flash_strength)
	CwMotion.set_pivot(_label, pivot)
	var reduced := CwMotion.reduced()
	_flash = create_tween()
	_flash.tween_method(func(k: float) -> void:
		if not is_instance_valid(_label):
			return
		_label.self_modulate = tint.lerp(Color.WHITE, k * k)
		if not reduced:
			# a quick pop in the first quarter of the flash
			var p := sin(k * 4.0 * PI) if k < 0.25 else 0.0
			CwMotion.set_channel(_label, &"tick", Vector2.ZERO, Vector2.ONE.lerp(pop_scale, p)), 0.0, 1.0, flash_seconds)
