class_name CrewIntro
extends Control
## The Cometlings Crew intro (scenes/menu/intro.tscn), the game's first scene, about 10 s:
##   1. deep space, the stars come up
##   2. a comet streaks in and circles, its tail drawing the emblem's ring
##   3. a flash: the sky disc pops in under the ring
##   4. the Cometling drops onto the Moon holding a Brazilian flag high, lands with a puff
##   5. plants the flag (dust, a shake), the flag unfurls and flutters
##   6. waves; a light sweeps the emblem, a burst of stars, "apresenta"
##   7. fades to the language screen (scenes/menu/language_select.tscn), which goes on to the
##      main menu; both load in the background meanwhile
## Any key, click or touch skips. Everything visual is in the scene; this script only times it.

const MENU := "res://scenes/menu/main_menu.tscn"
## shown after the intro on every launch; it opens the menu (LanguageSelect)
const LANGUAGE := "res://scenes/menu/language_select.tscn"
const LENGTH := 10.0
## the comet: entry curve (stage coordinates), then a lap of the ring, then away
const ENTRY := [Vector2(980, -560), Vector2(560, -120), Vector2(300, 268), Vector2(0, 268)]
const ENTRY_T := Vector2(0.6, 2.0)
const LAP_T := Vector2(2.0, 3.6)
const EXIT_T := Vector2(3.6, 4.1)
const RING_R := 268.0
const TRAIL_POINTS := 46

## Quit instead of opening the language screen at the end (movie capture: --write-movie).
@export var quit_at_end := false

var t := 0.0
var _cues: Array = []
var _leaving := false
var _holding := true
var _plunge := 0.0
var _wave := false

@onready var stage: Node2D = %Stage
@onready var emblem: Node2D = %Emblem
@onready var sky: Sprite2D = %Sky
@onready var ring: Sprite2D = %Ring
@onready var shine: Sprite2D = %Shine
@onready var crew: Node2D = %Crew
@onready var arm: Node2D = %ArmPivot
@onready var flag: Node2D = %Flag
@onready var cloth: Sprite2D = %Cloth
@onready var comet: Node2D = %Comet
@onready var trail: Line2D = %Trail
@onready var sparks: GPUParticles2D = %Sparks
@onready var land_dust: GPUParticles2D = %LandDust
@onready var plant_dust: GPUParticles2D = %PlantDust
@onready var burst: GPUParticles2D = %Burst
@onready var presents: Label = %Presents
@onready var skip: Label = %Skip
@onready var flash: ColorRect = %Flash
@onready var fade: ColorRect = %Fade

var _hand0 := Vector2.ZERO      # the hand in Crew space with the arm at rest
var _held := Vector2(39, -120)  # the flag's offset while held (planted = 0)
var _stage_home := Vector2.ZERO
var _crew_home := Vector2.ZERO


func _ready() -> void:
	MenuSettings.apply()
	for path in [LANGUAGE, MENU]:
		if ResourceLoader.load_threaded_request(path) != OK:
			push_warning("CrewIntro: could not start loading %s" % path)
	presents.text = tr("INTRO_PRESENTS")
	skip.text = tr("INTRO_SKIP")
	_hand0 = %HandMark.position
	_stage_home = stage.position
	(ring.material as ShaderMaterial).set_shader_parameter("progress", 0.0)
	(shine.material as ShaderMaterial).set_shader_parameter("pos", -0.6)
	(cloth.material as ShaderMaterial).set_shader_parameter("amplitude", 0.0)
	sky.scale = Vector2.ZERO
	_crew_home = crew.position
	crew.position.y = _crew_home.y - 900.0
	crew.visible = false
	arm.rotation_degrees = -30.0
	(cloth.material as ShaderMaterial).set_shader_parameter("reveal", 0.0)
	presents.modulate.a = 0.0
	skip.modulate.a = 0.0
	flash.modulate.a = 0.0
	fade.modulate.a = 1.0
	comet.visible = false
	trail.clear_points()
	_cues = [
		[0.0, _c_open], [0.6, _c_comet_in], [2.0, _c_lap], [3.6, _c_sky], [4.2, _c_drop],
		[4.65, _c_land], [5.1, _c_raise], [5.6, _c_plant], [5.85, _c_impact], [6.7, _c_wave],
		[7.0, _c_finale], [7.6, _c_presents], [9.2, _c_leave],
	]


func _process(delta: float) -> void:
	t += delta
	while not _cues.is_empty() and t >= float(_cues[0][0]):
		var c: Callable = _cues.pop_front()[1]
		c.call()
	_move_comet()
	_carry_flag()
	if _wave:
		arm.rotation_degrees = -20.0 + sin((t - 6.7) * 9.0) * 16.0
	emblem.position.y = sin(t * 1.3) * 4.0 if t > 4.6 else 0.0


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if pressed and t > 0.3 and not (quit_at_end or OS.get_cmdline_user_args().has("--intro-quit")):
		get_viewport().set_input_as_handled()
		_leave(0.35)


# --- the comet ---------------------------------------------------------------------------
func _move_comet() -> void:
	if not comet.visible:
		return
	var p := comet.position
	if t < ENTRY_T.y:
		var u := ease(clampf((t - ENTRY_T.x) / (ENTRY_T.y - ENTRY_T.x), 0.0, 1.0), -1.6)
		p = _bezier(u)
	elif t < LAP_T.y:
		var u := clampf((t - LAP_T.x) / (LAP_T.y - LAP_T.x), 0.0, 1.0)
		var a := PI / 2.0 + TAU * ease(u, -1.3)
		p = Vector2(cos(a), sin(a)) * RING_R
		(ring.material as ShaderMaterial).set_shader_parameter("progress", ease(u, -1.3))
	elif t < EXIT_T.y:
		(ring.material as ShaderMaterial).set_shader_parameter("progress", 1.0)
		var u := clampf((t - EXIT_T.x) / (EXIT_T.y - EXIT_T.x), 0.0, 1.0)
		p = Vector2(0, RING_R).lerp(Vector2(1100, -720), ease(u, 2.2))
	else:
		(ring.material as ShaderMaterial).set_shader_parameter("progress", 1.0)
		comet.visible = false
		sparks.emitting = false
		var tw := _tw()
		tw.tween_property(trail, "modulate:a", 0.0, 0.3)
		tw.tween_callback(trail.clear_points)
		return
	comet.position = p
	trail.add_point(p)
	while trail.get_point_count() > TRAIL_POINTS:
		trail.remove_point(0)


func _bezier(u: float) -> Vector2:
	var a: Vector2 = ENTRY[0]
	var b: Vector2 = ENTRY[1]
	var c: Vector2 = ENTRY[2]
	var d: Vector2 = ENTRY[3]
	var v := 1.0 - u
	return a * v * v * v + b * 3.0 * v * v * u + c * 3.0 * v * u * u + d * u * u * u


# --- the flag in the Cometling's hand --------------------------------------------------------
func _carry_flag() -> void:
	if not crew.visible:
		return
	var pivot := arm.position
	var hand := pivot + (_hand0 - pivot).rotated(arm.rotation)
	var follow := hand - _hand0 + _held
	flag.position = follow.lerp(Vector2.ZERO, _plunge) if _holding else Vector2.ZERO


# --- cues ----------------------------------------------------------------------------------
func _c_open() -> void:
	_tw().tween_property(fade, "modulate:a", 0.0, 0.8)


func _c_comet_in() -> void:
	comet.visible = true
	sparks.emitting = true
	CwSfx.play(&"comic_whoosh", 0.9)


func _c_lap() -> void:
	CwSfx.play(&"photo_develop", 1.1)


func _c_sky() -> void:
	flash.modulate.a = 0.85
	_tw().tween_property(flash, "modulate:a", 0.0, 0.55)
	_tw().tween_property(sky, "scale", Vector2.ONE * 0.4517, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shake(5.0, 0.25)
	CwSfx.play(&"comic_pop")
	CwSfx.play(&"comic_whoosh", 1.4, -6.0)


func _c_drop() -> void:
	crew.visible = true
	_tw().tween_property(crew, "position:y", _crew_home.y, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	CwSfx.play(&"launch_fall_whistle", 1.3, -8.0)


func _c_land() -> void:
	crew.scale = Vector2(1.18, 0.8)
	_tw().tween_property(crew, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	land_dust.restart()
	_shake(4.0, 0.18)
	CwSfx.play(&"launch_fwoomp", 1.2, -4.0)
	CwSfx.play(&"voice_happy")


func _c_raise() -> void:
	_tw().tween_property(arm, "rotation_degrees", -48.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _c_plant() -> void:
	var tw := _tw()
	tw.tween_property(arm, "rotation_degrees", 14.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "_plunge", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _c_impact() -> void:
	_holding = false
	plant_dust.restart()
	_shake(9.0, 0.3)
	CwSfx.play(&"comic_clac")
	CwSfx.play(&"comic_boom", 1.3, -6.0)
	var mat := cloth.material as ShaderMaterial
	_tw().tween_method(func(v: float) -> void: mat.set_shader_parameter("reveal", v), 0.0, 1.0, 0.7) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# a strong flap from the impact that settles into a gentle ripple
	var flap := _tw()
	flap.tween_method(func(v: float) -> void: mat.set_shader_parameter("amplitude", v), 0.0, 0.07, 0.25)
	flap.tween_method(func(v: float) -> void: mat.set_shader_parameter("amplitude", v), 0.07, 0.022, 1.8) 		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tw().tween_property(arm, "rotation_degrees", -20.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _c_wave() -> void:
	_wave = true
	CwSfx.play(&"voice_cheer")


func _c_finale() -> void:
	burst.restart()
	CwSfx.play(&"stinger_milestone")
	CwSfx.play(&"confetti_pop")
	_tw().tween_method(func(v: float) -> void: (shine.material as ShaderMaterial).set_shader_parameter("pos", v),
		-0.6, 1.6, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	emblem.scale = Vector2.ONE * 1.04
	_tw().tween_property(emblem, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _c_presents() -> void:
	var y := presents.position.y
	presents.position.y = y + 16.0
	_tw().tween_property(presents, "modulate:a", 1.0, 0.6)
	_tw().tween_property(presents, "position:y", y, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw().tween_property(skip, "modulate:a", 0.6, 0.6)


func _c_leave() -> void:
	_leave(0.8)


func _leave(time: float) -> void:
	if _leaving:
		return
	_leaving = true
	var tw := _tw()
	tw.tween_property(fade, "modulate:a", 1.0, time)
	tw.tween_callback(_open_menu)


func _open_menu() -> void:
	if quit_at_end or OS.get_cmdline_user_args().has("--intro-quit"):
		get_tree().quit()
		return
	# the language screen; the menu keeps loading in the background and that screen opens it
	var ps := ResourceLoader.load_threaded_get(LANGUAGE) as PackedScene
	if ps == null:
		ps = load(LANGUAGE) as PackedScene
	get_tree().change_scene_to_packed(ps)


func _shake(amount: float, time: float) -> void:
	if MenuSettings.reduce_motion():
		return
	var tw := _tw()
	var steps := 6
	for i in steps:
		var k := 1.0 - float(i) / steps
		tw.tween_property(stage, "position", _stage_home + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * k, time / steps)
	tw.tween_property(stage, "position", _stage_home, time / steps)


func _tw() -> Tween:
	return create_tween()
