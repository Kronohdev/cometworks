class_name LanguageStation
extends Control
## One flag station of the language screen (scenes/menu/language_select.tscn): a flag on a
## podium on the Moon, its glow, its sparkles and confetti, and the plaque with the language's
## name (always in its own language). The art is in the scene; this script only animates it:
##   - lit (the highlighted language): the glow comes up and breathes, the flag grows a little
##     and flutters harder, the plaque brightens; unlit it rests dimmed
##   - arrive(): the Cometling got here: the flag wobbles and the plaque pops
##   - celebrate(): the language was chosen: confetti, a big wobble and a big pop
## The Control is the hit area: hovering it says `hovered`, a click or a tap says `picked`.

signal hovered(locale: String)
signal picked(locale: String)

@export var locale := "pt"
## flutter of the cloth (the intro_flag_wave shader's amplitude) unlit / lit
@export var flutter := Vector2(0.012, 0.032)

var lit := false
var _w := 0.0          # 0 unlit .. 1 lit, eased
var _t := 0.0
var _pop := 1.0        # extra scale of the plaque (tweened)
var _wob := 0.0        # extra rotation of the flag (tweened, degrees)
var _tw_pop: Tween
var _tw_wob: Tween

@onready var flag: Node2D = $Art/Flag
@onready var cloth: Sprite2D = $Art/Flag/Cloth
@onready var glow: Sprite2D = $Glow
@onready var plaque: Control = $Plaque
@onready var sparkles: GPUParticles2D = $Sparkles
@onready var confetti: GPUParticles2D = $Confetti


func _ready() -> void:
	mouse_entered.connect(func() -> void: hovered.emit(locale))
	plaque.resized.connect(_center_pivot)
	_center_pivot()
	_t = randf() * 10.0
	_apply()


func _center_pivot() -> void:
	plaque.pivot_offset = plaque.size * 0.5


func _gui_input(event: InputEvent) -> void:
	var click: bool = (event is InputEventMouseButton and event.pressed
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if click:
		accept_event()
		picked.emit(locale)


func set_lit(on: bool) -> void:
	lit = on
	sparkles.emitting = on


## The Cometling arrived next to this flag.
func arrive() -> void:
	_wobble([9.0, -6.0, 3.5, -1.5, 0.0], 0.13)
	_pop_plaque(1.22, 0.7)


## This language was chosen.
func celebrate() -> void:
	confetti.restart()
	_wobble([9.0, -7.0, 4.5, -2.5, 1.0, 0.0], 0.12)
	_pop_plaque(1.38, 1.0)


func _process(delta: float) -> void:
	_t += delta
	_w = move_toward(_w, 1.0 if lit else 0.0, delta * 3.2)
	_apply()


func _apply() -> void:
	var w := ease(_w, -1.8)
	var breathe := 0.5 + 0.5 * sin(_t * 2.2)
	glow.modulate.a = lerpf(0.12, 0.75 + 0.2 * breathe, w)
	glow.scale = Vector2.ONE * lerpf(1.6, 1.9 + 0.08 * breathe, w)
	flag.scale = Vector2.ONE * lerpf(0.95, 1.04, w)
	flag.rotation_degrees = _wob + sin(_t * 1.3) * 0.8 * w
	(cloth.material as ShaderMaterial).set_shader_parameter("amplitude", lerpf(flutter.x, flutter.y, w))
	plaque.scale = Vector2.ONE * lerpf(0.9, 1.0, w) * _pop
	plaque.modulate = Color(0.62, 0.6, 0.82, 0.9).lerp(Color.WHITE, w)


func _wobble(steps: Array, step_time: float) -> void:
	if MenuSettings.reduce_motion():
		return
	if _tw_wob and _tw_wob.is_valid():
		_tw_wob.kill()
	_tw_wob = create_tween()
	for d: float in steps:
		_tw_wob.tween_property(self, "_wob", d, step_time).set_trans(Tween.TRANS_SINE)


func _pop_plaque(peak: float, settle: float) -> void:
	if MenuSettings.reduce_motion():
		return
	if _tw_pop and _tw_pop.is_valid():
		_tw_pop.kill()
	_pop = peak
	_tw_pop = create_tween()
	_tw_pop.tween_property(self, "_pop", 1.0, settle).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
