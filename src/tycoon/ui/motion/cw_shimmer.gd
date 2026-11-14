@tool
class_name CwShimmer
extends ColorRect
## Idle shimmer for the one primary call to action ("Novo projeto", "Nova campanha"): a
## slanted band of light crosses the button every `period` seconds (shaders/cw_ui_shimmer
## .gdshader, additive, GPU only). Add it as a child of the button, full rect, a couple of
## px inside its corners; it ignores the mouse, hides while the button is disabled and is
## off under reduce motion.

const SHADER := preload("res://shaders/cw_ui_shimmer.gdshader")

@export var tint := Color(1.0, 0.95, 0.85):
	set(v):
		tint = v
		_push()
@export_range(0.5, 30.0, 0.1) var period := 5.0:
	set(v):
		period = v
		_push()
@export_range(0.1, 5.0, 0.05) var sweep_seconds := 1.1:
	set(v):
		sweep_seconds = v
		_push()
@export_range(0.02, 0.8, 0.01) var width := 0.16:
	set(v):
		width = v
		_push()
@export_range(-1.0, 1.0, 0.01) var slant := 0.35:
	set(v):
		slant = v
		_push()
@export_range(0.0, 1.0, 0.01) var strength := 0.22:
	set(v):
		strength = v
		_push()
## corner radius of the button as a fraction of its height (0.5 = a pill): the band is masked to it
@export_range(0.0, 0.5, 0.01) var corner := 0.5:
	set(v):
		corner = v
		_push()
## seconds into the cycle (offsets shimmers that share a screen)
@export var phase := 0.0:
	set(v):
		phase = v
		_push()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not material is ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = SHADER
		material = m
	_push()
	resized.connect(_push)
	if Engine.is_editor_hint():
		return
	if CwMotion.reduced():
		visible = false
		return
	var b := get_parent() as BaseButton
	if b:
		b.draw.connect(func() -> void: visible = not b.disabled)
		visible = not b.disabled


func _push() -> void:
	var m := material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("period", period)
	m.set_shader_parameter("sweep_seconds", sweep_seconds)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("slant", slant)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("phase", phase)
	m.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	m.set_shader_parameter("corner", corner)
