class_name CampusWeather
extends Node3D
## Purely visual weather and night sky over the campus (the Weather node of
## scenes/tycoon/fx/campus_effects.tscn). Nothing here touches the campaign: the weather has
## its own RandomNumberGenerator (seeded with `weather_seed`), so saved and unsaved campaigns
## play out the same whatever the sky does.
##   Weather   "clear", "cloudy" or "rain", picked by `weights` every min..max_seconds of real
##             time. Rain (streaks) and Splashes (rings on the ground) follow the camera; the
##             Clouds drift with the wind and wrap around `cloud_area`, more of them and greyer
##             when it rains: each one is high toon Puffs (hidden while the camera is above them)
##             and a soft Shadow decal sliding over the campus right under them. The
##             wind sways the trees and grass harder (`foliage_materials`' sway, put back on exit).
##             Off in the settings (MenuSettings.weather()): always clear, no clouds.
##   Night     from the day cycle's phase through the `night` curve: the campus fireflies
##             (Campus/Life/Fireflies) glow only at night, a ShootingStar crosses the sky now and
##             then, and the comet of the sky shader grows era after era (`comet_scale_by_era`,
##             on its length and brightness: it is getting closer).
## Reduce motion: no shooting stars.

signal weather_changed(kind: String)

const GROUP := &"cw_weather"
const KINDS := ["clear", "cloudy", "rain"]

## the settings switch (MenuSettings.weather()); load_settings() reads it
@export var enabled := true
@export_group("Weather")
## how likely each kind is when the weather changes
@export var weights: Dictionary[String, float] = {"clear": 5.0, "cloudy": 3.0, "rain": 2.0}
@export var min_seconds := 50.0
@export var max_seconds := 120.0
## rain fade in / out (amount per second)
@export var rain_fade := 0.2
@export var weather_seed := 4242
## the weather the campus starts with
@export var start_kind := "clear"
@export_group("Rain")
## the rain falls from this high (m) over a point `rain_ahead` metres in front of the camera
@export var rain_height := 22.0
@export var rain_ahead := 24.0
## how much darker the campus gets in full rain (the Environment's brightness adjustment)
@export_range(0.0, 1.0, 0.01) var rain_dim := 0.18
## rain streaks at full rain (GPUParticles3D amount_ratio)
@export_range(0.0, 1.0, 0.01) var rain_ratio := 1.0
@export_group("Clouds")
## the clouds drift inside this rectangle (x, z) and wrap around
@export var cloud_area := Rect2(-170, -150, 340, 300)
## metres per second at wind 1
@export var cloud_speed := 3.0
## share of the clouds out per weather kind
@export var cloud_cover: Dictionary[String, float] = {"clear": 0.25, "cloudy": 0.75, "rain": 1.0}
@export var cloud_color := Color(1, 1, 1)
@export var rain_cloud_color := Color(0.58, 0.62, 0.7)
## how fast a cloud puffs in or out (scale per second)
@export var cloud_pop := 0.35
## how dark the cloud shadows on the ground are (the Shadow decal's alpha)
@export_range(0.0, 1.0, 0.01) var cloud_shadow := 0.8
## the cloud puffs hide while the camera is higher than this (m): they would sit in the view
@export var puff_hide_height := 120.0
@export_group("Wind")
## wind strength per weather kind (0..1)
@export var wind_by_kind: Dictionary[String, float] = {"clear": 0.2, "cloudy": 0.45, "rain": 0.8}
## direction the clouds and the wind go (x, z)
@export var wind_dir := Vector2(0.8, 0.35)
## foliage materials whose `sway` follows the wind (put back on exit)
@export var foliage_materials: Array[ShaderMaterial] = []
## extra sway at wind 1 (times the authored sway)
@export var sway_gain := 1.4
@export_group("Night")
## night amount (0..1) over the day-cycle phase
@export var night: Curve
## seconds between shooting stars at full night (random in x..y)
@export var shooting_star_every := Vector2(7.0, 18.0)
## the sky shader's comet length / brightness per era (1..5), times the authored values
@export var comet_scale_by_era: PackedFloat32Array = PackedFloat32Array([0.45, 0.6, 0.78, 1.0, 1.3])

var kind := "clear"
var rain_amount := 0.0
var wind := 0.2
var campus: Node3D
var day_cycle: Node
var era := 1

var _rng := RandomNumberGenerator.new()
var _left := 0.0
var _star_left := 5.0
var _fireflies: GPUParticles3D
var _sky: ShaderMaterial
var _env: Environment
var _brightness_base := 1.0
var _comet_base := {}
var _sway_base: Array[float] = []
var _cloud_mat: ShaderMaterial

@onready var rain: GPUParticles3D = $Rain
@onready var splashes: GPUParticles3D = $Splashes
@onready var clouds: Node3D = $Clouds
@onready var shooting_star: Node3D = $ShootingStar


func _ready() -> void:
	add_to_group(GROUP)
	_rng.seed = weather_seed
	for m in foliage_materials:
		_sway_base.append(float(m.get_shader_parameter("sway")) if m else 0.0)
	for c in clouds.get_children():
		c.set_meta("pop", 0.0)
		_show_cloud(c as Node3D, 0.0, false)
		if _cloud_mat == null:
			var mi := c.find_child("Puff*", true, false) as MeshInstance3D
			if mi:
				_cloud_mat = mi.get_surface_override_material(0) as ShaderMaterial
	load_settings()
	set_kind(start_kind)
	_left = _rng.randf_range(min_seconds, max_seconds)


## Hooks the weather to the campus (its fireflies and sky) and the day cycle.
func setup(p_campus: Node3D, p_day_cycle: Node) -> void:
	campus = p_campus
	day_cycle = p_day_cycle
	if campus:
		_fireflies = campus.get_node_or_null("Life/Fireflies") as GPUParticles3D
		var we := campus.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we and we.environment:
			_env = we.environment
			_brightness_base = _env.adjustment_brightness
		if we and we.environment and we.environment.sky:
			_sky = we.environment.sky.sky_material as ShaderMaterial
		if _sky and _sky.shader:
			var names := {}
			for u in _sky.shader.get_shader_uniform_list():
				names[String(u["name"])] = true
			for p in ["comet_length", "comet_brightness"]:
				if names.has(p):
					_comet_base[p] = float(_sky.get_shader_parameter(p))
	set_era(era)


## Reads the settings switch (MenuSettings.weather()).
func load_settings() -> void:
	set_enabled(MenuSettings.weather())


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		set_kind("clear")


## Changes the weather now ("clear", "cloudy", "rain"; anything but clear is ignored while off).
func set_kind(k: String) -> void:
	if not k in KINDS:
		return
	if not enabled:
		k = "clear"
	var was := kind
	kind = k
	if was != kind:
		weather_changed.emit(kind)


## The sky shader's comet for an era (closer and brighter as the comet comes).
func set_era(e: int) -> void:
	era = clampi(e, 1, 5)
	if _sky == null or comet_scale_by_era.is_empty():
		return
	var s := comet_scale_by_era[mini(era, comet_scale_by_era.size()) - 1]
	for p: String in _comet_base:
		# the tail grows with the scale, the glow a little less
		var k := s if p == "comet_length" else clampf(0.7 + 0.3 * s, 0.7, 1.2)
		_sky.set_shader_parameter(p, float(_comet_base[p]) * k)


func night_amount() -> float:
	var p := float(day_cycle.get("phase")) if day_cycle else 0.0
	return clampf(night.sample_baked(p), 0.0, 1.0) if night else 0.0


func _exit_tree() -> void:
	for i in foliage_materials.size():
		if foliage_materials[i]:
			foliage_materials[i].set_shader_parameter("sway", _sway_base[i])
	if _sky:
		for p: String in _comet_base:
			_sky.set_shader_parameter(p, _comet_base[p])
	if _env:
		_env.adjustment_brightness = _brightness_base


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left = _rng.randf_range(min_seconds, max_seconds)
		set_kind(_pick())
	var want_rain := 1.0 if kind == "rain" else 0.0
	rain_amount = move_toward(rain_amount, want_rain, delta * rain_fade)
	wind = lerpf(wind, float(wind_by_kind.get(kind, 0.2)), clampf(delta * 0.3, 0.0, 1.0))
	_follow_camera()
	_rain_look()
	_drift_clouds(delta)
	_sway()
	_night(delta)


func _pick() -> String:
	var total := 0.0
	for k: String in weights:
		total += maxf(weights[k], 0.0)
	var r := _rng.randf() * total
	for k: String in weights:
		r -= maxf(weights[k], 0.0)
		if r <= 0.0:
			return k
	return "clear"


func _follow_camera() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var p := from
	if dir.y < -0.05:
		p = from + dir * minf(-from.y / dir.y, 90.0)
	p.y = 0.0
	# the streaks fall just in front of the camera (close to it they read even from far up),
	# the splashes ring on the ground it looks at
	rain.global_position = from + dir * rain_ahead + Vector3(0, rain_height * 0.5, 0)
	splashes.global_position = p + Vector3(0, 0.08, 0)


func _rain_look() -> void:
	var on := rain_amount > 0.01
	rain.amount_ratio = rain_amount * rain_ratio
	splashes.amount_ratio = rain_amount
	if rain.emitting != on:
		rain.emitting = on
	if splashes.emitting != on:
		splashes.emitting = on
	if _cloud_mat:
		_cloud_mat.set_shader_parameter("albedo", cloud_color.lerp(rain_cloud_color, rain_amount))
	if _env and _env.adjustment_enabled:
		_env.adjustment_brightness = _brightness_base * (1.0 - rain_dim * rain_amount)


func _drift_clouds(delta: float) -> void:
	var cover := float(cloud_cover.get(kind, 0.3)) if enabled else 0.0
	var n := clouds.get_child_count()
	var move := Vector3(wind_dir.x, 0.0, wind_dir.y).normalized() * cloud_speed * (0.4 + wind) * delta
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	# the puffs float high: from a camera above them (zoomed far out) only their shadows show
	var low := cam == null or cam.global_position.y < puff_hide_height
	for i in n:
		var c := clouds.get_child(i) as Node3D
		var on := float(i) < cover * float(n) - 0.01
		var s := move_toward(float(c.get_meta("pop", 0.0)), 1.0 if on else 0.0, delta * cloud_pop)
		c.set_meta("pop", s)
		_show_cloud(c, s, low)
		if s <= 0.0:
			continue
		c.position += move
		var a := cloud_area
		if c.position.x > a.end.x:
			c.position.x -= a.size.x
		elif c.position.x < a.position.x:
			c.position.x += a.size.x
		if c.position.z > a.end.y:
			c.position.z -= a.size.y
		elif c.position.z < a.position.y:
			c.position.z += a.size.y


## One cloud at `s` (0 gone .. 1 fully out): its Puffs grow from nothing, its Shadow decal on
## the ground fades in (weaker at night, when there is no sun to cast it).
func _show_cloud(c: Node3D, s: float, puffs_visible: bool) -> void:
	var puffs := c.get_node_or_null("Puffs") as Node3D
	if puffs:
		puffs.scale = Vector3.ONE * maxf(s, 0.001)
		puffs.visible = s > 0.002 and puffs_visible
	var sh := c.get_node_or_null("Shadow") as Decal
	if sh:
		var a := s * cloud_shadow * (1.0 - 0.85 * night_amount()) * (1.0 + 0.4 * rain_amount)
		sh.modulate.a = a
		sh.visible = a > 0.005


func _sway() -> void:
	for i in foliage_materials.size():
		if foliage_materials[i]:
			foliage_materials[i].set_shader_parameter("sway", _sway_base[i] * (1.0 + sway_gain * wind))


func _night(delta: float) -> void:
	var nt := night_amount()
	if _fireflies:
		var r := nt * (1.0 - rain_amount)
		_fireflies.amount_ratio = r
		var on := r > 0.03
		if _fireflies.emitting != on:
			_fireflies.emitting = on
	if nt < 0.6 or CwMotion.reduced() or rain_amount > 0.3:
		return
	_star_left -= delta
	if _star_left <= 0.0:
		_star_left = _rng.randf_range(shooting_star_every.x, shooting_star_every.y)
		shoot_star()


## A shooting star somewhere in the sky around the campus.
func shoot_star() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var centre := cam.global_position if cam else Vector3.ZERO
	var look := (-cam.global_basis.z) if cam else Vector3.FORWARD
	var yaw := atan2(look.x, look.z) + _rng.randf_range(-0.6, 0.6)
	var dist := _rng.randf_range(260.0, 340.0)
	shooting_star.global_position = Vector3(centre.x + sin(yaw) * dist, _rng.randf_range(110.0, 170.0), centre.z + cos(yaw) * dist)
	shooting_star.global_basis = Basis(Vector3.UP, yaw + PI * 0.5 + _rng.randf_range(-0.5, 0.5)) * Basis(Vector3.BACK, _rng.randf_range(0.2, 0.5))
	var ap := shooting_star.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		ap.stop()
		ap.play("streak")
