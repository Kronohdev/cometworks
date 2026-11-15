class_name LanguageSelect
extends Control
## The language screen (scenes/menu/language_select.tscn), between the team intro and the main
## menu, on every launch. A Cometling stands on the Moon between two flag stations
## (LanguageStation): Brazil / "Português" on the left, the United States / "English" on the
## right. It walks or runs after the mouse (its x, clamped to the walk between the podiums),
## faces where it goes, and waves when it reaches a flag, which wobbles and pops its plaque.
## The highlighted language is the side it is heading to; the subtitle and the hints preview
## that language. Hovering a flag highlights it, clicking it chooses it; ←/→ (A/D, the d-pad,
## the stick) move to a side, Enter / Space / A choose the highlighted one.
## Choosing: the Cometling jumps and cheers, confetti, a sound, the locale is applied at once
## (MenuSettings.set_locale also saves it), then a fade to the main menu, which the intro
## started loading in the background (a threaded load; requested here when opened directly).
## The last chosen language starts highlighted with the Cometling at its flag, so Enter
## confirms straight away. Everything visual is in the scene; this script only drives it.

signal chosen(locale: String)

const MENU := "res://scenes/menu/main_menu.tscn"
const SCENE := "res://scenes/menu/language_select.tscn"
const SIDES := ["pt", "en"]
## seconds after opening before a key or click can choose (a key mashed to skip the intro
## should not choose the language too)
const GRACE := 0.45

## the Moon's top in Stage px: its curve is the ellipse of ui/menu/language/moon.png
## (tools/language_select_art.py: rx 1500, ry 640) with its top at (stage centre, ground_y)
@export var ground_y := 590.0
@export var moon_radius := Vector2(1500, 640)
## where the Cometling stops next to each flag (Stage px): left = Português, right = English
@export var walk_x := Vector2(540, 1060)
## running speed (Stage px / s) and how fast it gets there
@export var max_speed := 600.0
@export var accel := 2200.0
## seconds of celebration before the fade, and of the fade
@export var celebrate_time := 1.6
@export var fade_time := 0.55
## false: stay here after choosing (tests)
@export var open_menu_on_choice := true

var selected := "pt"
var confirmed := false
var _celebrated := false
var _x := 0.0          # the Cometling's x, Stage px
var _v := 0.0          # its speed, Stage px / s
var _target := 0.0     # where it walks to, Stage px
var _at := ""          # the flag it stands at ("" between them)
var _yaw := 0.0
var _ppu := 180.0      # Stage px per metre at the Cometling's depth
var _t := 0.0
var _confirm_t := 0.0
var _leaving := false
var _bobbers: Array = []   # [node, base y, phase]
var _shoot_in := 2.5       # seconds to the next shooting star

@onready var stage: Control = %Stage
@onready var view: SubViewport = %Viewport
@onready var camera: Camera3D = %Camera3D
@onready var creature: Node3D = %Creature
@onready var stations := {"pt": %PT as LanguageStation, "en": %EN as LanguageStation}
@onready var subtitle: Label = %Subtitle
@onready var move_hint: Label = %MoveHint
@onready var confirm_hint: Label = %ConfirmHint
@onready var go: Control = %Go
@onready var go_label: Label = %GoLabel
@onready var cheer: GPUParticles2D = %Cheer
@onready var stars: GPUParticles2D = %Stars
@onready var shooting_star: Sprite2D = %ShootingStar
@onready var fade: ColorRect = %Fade


func _ready() -> void:
	TranslationServer.set_locale(MenuSettings.saved_locale())
	if ResourceLoader.load_threaded_get_status(MENU) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		if ResourceLoader.load_threaded_request(MENU) != OK:
			push_warning("LanguageSelect: could not start loading the menu")
	for loc: String in stations:
		var st: LanguageStation = stations[loc]
		st.hovered.connect(_on_hovered)
		st.picked.connect(func(loc: String) -> void:
			if _t >= GRACE:
				choose(loc))
	for n: Node in get_tree().get_nodes_in_group(&"lang_bob"):
		if is_ancestor_of(n):
			_bobbers.append([n, (n as Node2D).position.y, randf() * TAU])
	resized.connect(_layout)
	_layout()
	_ppu = _measure_ppu()
	selected = MenuSettings.locale()
	_target = _end_of(selected)
	_x = _target
	_at = selected
	_yaw = _rest_yaw()
	_place_creature()
	_light()
	_refresh_texts()
	go.visible = false
	fade.modulate.a = 1.0
	create_tween().tween_property(fade, "modulate:a", 0.0, 0.5)
	# a hello from the flag it starts at
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		if not confirmed:
			_on_arrive(selected))


func _layout() -> void:
	stars.position = size * 0.5


## A shooting star across the upper sky, right to left.
func _shoot() -> void:
	var from := Vector2(randf_range(0.55, 0.95) * size.x, randf_range(150.0, 260.0))
	var dir := Vector2.from_angle(shooting_star.rotation)
	shooting_star.position = from
	shooting_star.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(shooting_star, "position", from + dir * 420.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var fade_tw := create_tween()
	fade_tw.tween_property(shooting_star, "modulate:a", 0.9, 0.2)
	fade_tw.tween_property(shooting_star, "modulate:a", 0.0, 0.6)


# --- input -------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if confirmed:
		return
	if event is InputEventMouseMotion:
		var local := stage.get_global_transform_with_canvas().affine_inverse() * (event as InputEventMouseMotion).position
		walk_to(local.x)


func _unhandled_input(event: InputEvent) -> void:
	if confirmed or event.is_echo():
		return
	if event.is_action_pressed(&"ui_left") or _key(event, KEY_A):
		walk_to(walk_x.x)
	elif event.is_action_pressed(&"ui_right") or _key(event, KEY_D):
		walk_to(walk_x.y)
	elif event.is_action_pressed(&"ui_accept"):
		if _t >= GRACE:
			choose(selected)
	else:
		return
	get_viewport().set_input_as_handled()


static func _key(event: InputEvent, code: Key) -> bool:
	return event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == code


## Sends the Cometling toward a Stage x (clamped to the walk between the flags); the language on
## that side becomes the highlighted one.
func walk_to(stage_x: float) -> void:
	if confirmed:
		return
	_target = clampf(stage_x, walk_x.x, walk_x.y)
	var mid := (walk_x.x + walk_x.y) * 0.5
	var dead := 18.0
	var side := selected
	if _target < mid - dead:
		side = "pt"
	elif _target > mid + dead:
		side = "en"
	_select(side)


func _on_hovered(loc: String) -> void:
	if not confirmed:
		_target = _end_of(loc)
		_select(loc)


func _select(loc: String) -> void:
	if loc == selected:
		return
	selected = loc
	CwSfx.play(&"menu_hover", 1.0 if loc == "pt" else 1.12)
	_light()
	_refresh_texts()


## Chooses a language: applies and saves it, celebrates, then goes on to the main menu.
func choose(loc: String) -> void:
	if confirmed or not loc in SIDES:
		return
	confirmed = true
	_confirm_t = 0.0
	selected = loc
	_target = _end_of(loc)
	MenuSettings.set_locale(loc)
	_light()
	_refresh_texts()
	CwSfx.play(&"menu_select")
	chosen.emit(loc)
	if absf(_x - _target) < 30.0:
		_celebrate()


# --- the walk --------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	_walk(delta)
	_place_creature()
	for b: Array in _bobbers:
		var n := b[0] as Node2D
		n.position.y = float(b[1]) + sin(_t * 0.7 + float(b[2])) * 7.0
		n.rotation = sin(_t * 0.4 + float(b[2])) * 0.06
	_shoot_in -= delta
	if _shoot_in <= 0.0:
		_shoot_in = randf_range(4.5, 8.0)
		_shoot()
	if confirmed and not _celebrated:
		_confirm_t += delta
		if absf(_x - _target) < 30.0 or _confirm_t > 1.4:
			_celebrate()


func _walk(delta: float) -> void:
	var gap := _target - _x
	var want := clampf(gap * 7.0, -max_speed, max_speed)
	_v = move_toward(_v, want, accel * delta)
	if absf(gap) < 2.0 and absf(_v) < 30.0:
		_v = 0.0
		_x = _target
	_x += _v * delta
	creature.call("set_move_velocity", Vector3(_v / _ppu, 0.0, 0.0))
	var target_yaw := _rest_yaw()
	if absf(_v) > 30.0:
		target_yaw = signf(_v) * deg_to_rad(80.0)
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-9.0 * delta))
	# arriving at a flag
	var here := ""
	if _x <= walk_x.x + 12.0:
		here = "pt"
	elif _x >= walk_x.y - 12.0:
		here = "en"
	if here != "" and here != _at and absf(_v) < 160.0:
		_at = here
		_on_arrive(here)
	elif here == "" and absf(_x - _end_of(_at if _at != "" else selected)) > 50.0:
		_at = ""


## Facing when standing: toward the camera, turned a little to the flag it is next to.
func _rest_yaw() -> float:
	var mid := (walk_x.x + walk_x.y) * 0.5
	return deg_to_rad(-22.0 if _x < mid else 22.0)


func _on_arrive(loc: String) -> void:
	var st: LanguageStation = stations[loc]
	st.arrive()
	if confirmed:
		return
	creature.call("play", "wave")
	creature.call("show_emote", "heart" if loc == "pt" else "star", 1.6)
	CwSfx.play(&"voice_happy", 1.0 if loc == "pt" else 1.1)


func _celebrate() -> void:
	if _celebrated:
		return
	_celebrated = true
	var st: LanguageStation = stations[selected]
	st.celebrate()
	creature.call("stop_shot")
	creature.call("play_sequence", ["jump", "cheer"])
	creature.call("show_emote", "sparkle", 1.8)
	creature.call("set_expression", "joy", 3.0)
	cheer.position = Vector2(_x, _ground(_x) - 120.0)
	cheer.restart()
	CwSfx.play(&"confetti_pop")
	CwSfx.play(&"voice_cheer")
	CwSfx.play(&"comic_pop", 1.2, -4.0)
	go_label.text = tr("LANG_GO")
	go.visible = true
	go.pivot_offset = go.size * 0.5
	go.modulate.a = 0.0
	go.scale = Vector2.ONE * 0.6
	var tw := create_tween().set_parallel()
	tw.tween_property(go, "modulate:a", 1.0, 0.2)
	tw.tween_property(go, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(celebrate_time).timeout.connect(_leave)


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, fade_time)
	tw.tween_callback(_open_menu)


func _open_menu() -> void:
	if not open_menu_on_choice:
		return
	var ps: PackedScene = null
	if ResourceLoader.load_threaded_get_status(MENU) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ps = ResourceLoader.load_threaded_get(MENU) as PackedScene
	if ps == null:
		ps = load(MENU) as PackedScene
	get_tree().change_scene_to_packed(ps)


# --- the stage -------------------------------------------------------------------------------
## The Moon's top under a Stage x.
func _ground(x: float) -> float:
	var dx := clampf((x - stage.size.x * 0.5) / moon_radius.x, -1.0, 1.0)
	return ground_y + moon_radius.y * (1.0 - sqrt(1.0 - dx * dx))


func _end_of(loc: String) -> float:
	return walk_x.x if loc == "pt" else walk_x.y


## The point of the Cometling's plane (z = 0) seen at a Stage pixel.
func _world_at(px: Vector2) -> Vector3:
	var o := camera.project_ray_origin(px)
	var d := camera.project_ray_normal(px)
	if absf(d.z) < 0.0001:
		return o
	return o + d * (-o.z / d.z)


func _measure_ppu() -> float:
	var a := _world_at(Vector2(0, ground_y))
	var b := _world_at(Vector2(100, ground_y))
	return 100.0 / maxf(a.distance_to(b), 0.0001)


func _place_creature() -> void:
	creature.position = _world_at(Vector2(_x, _ground(_x)))
	creature.rotation.y = _yaw


func _light() -> void:
	for loc: String in stations:
		(stations[loc] as LanguageStation).set_lit(loc == selected)


## The subtitle and the hints preview the highlighted language.
func _refresh_texts() -> void:
	subtitle.text = text_in("LANG_SUBTITLE", selected)
	move_hint.text = text_in("LANG_HINT_MOVE", selected)
	confirm_hint.text = text_in("LANG_HINT_CONFIRM", selected)


## A key's text in a given language ("pt" / "en"), whatever the current locale.
static func text_in(key: String, loc: String) -> String:
	for t: Translation in TranslationServer.find_translations(loc, false):
		var m := t.get_message(key)
		if m != &"":
			return String(m)
	return TranslationServer.translate(key)
