class_name CampusDayCycle
extends Node
## A slow golden hour -> dusk -> night -> dawn cycle over the campus, driven by the campaign
## clock (one cycle every `weeks_per_cycle` weeks, smooth inside a week thanks to
## TycoonClock.week_fraction(); it stops while the game is paused). Every look is a curve or
## a gradient over the cycle phase (0 = golden hour, ~0.45 = night, ~0.8 = dawn), authored in
## the inspector (scenes/tycoon/tycoon_main.tscn: DayCycle):
##   sun elevation (deg) / energy / colour, moon energy / colour, ambient energy / colour,
##   exposure, saturation and contrast, fog colour and density, sky colours (zenith, mid,
##   horizon), sky glow and stars, building windows (glow gain of the voxel material) and
##   lamp energies, and the cartoon look's shadow tint, rim and ink colours. Windows and lamps glow brighter at night. Night is a "blue hour": a
##   luminous blue sky, cool moonlight, lifted ambient and warm windows and lamps, so the
##   campus stays readable. Unset curves leave the scene's own values alone.
## Lights anywhere under the campus in the group "campus_lamps" follow the lamp energy like the
## street lamps (the lighthouse); geometry in "campus_night_glow" fades in as the lamps rise
## above their golden-hour level (the lighthouse beams).

@export var enabled := true
## the campus scene (Campus node) whose lights, environment and lamps are driven
@export var campus: Node3D
@export_range(1.0, 104.0, 0.5) var weeks_per_cycle := 12.0
## phase at week 0 (0 = golden hour)
@export_range(0.0, 1.0, 0.01) var phase_offset := 0.0
## preview a phase in the running game (< 0 = follow the clock)
@export_range(-0.01, 1.0, 0.01) var force_phase := -0.01

@export_group("Sun and moon")
@export var sun_elevation: Curve
@export var sun_energy: Curve
@export var sun_color: Gradient
@export var moon_energy: Curve
@export var moon_color: Gradient
@export_group("Ambient")
@export var ambient_energy: Curve
@export var ambient_color: Gradient
@export var exposure: Curve
## colour grade: saturation and contrast of the Environment adjustment
@export var saturation: Curve
@export var contrast: Curve
@export_group("Fog")
## haze colour (light colour of the Environment fog) and density
@export var fog_color: Gradient
@export var fog_density: Curve
@export_group("Sky")
@export var zenith_color: Gradient
@export var mid_color: Gradient
@export var horizon_color: Gradient
@export var sky_glow: Curve
@export var stars: Curve
@export var aurora: Curve
@export_group("Lights")
## glow gain of the buildings' voxel material (windows, screens)
@export var window_glow: Curve
## tint of the pale window lights (glow_tint of the voxel material): warm lamplight at night
@export var window_tint: Gradient
@export var lamp_energy: Curve
@export var voxel_material: ShaderMaterial
@export_group("Toon")
## colour the shadow side of the cartoon light leans to (shader global cw_shadow_tint, see
## shaders/include/cw_toon.gdshaderinc): warm at dusk, blue at night
@export var shadow_tint: Gradient
## rim light of the cartoon look (cw_rim_color): the colour of the sky / aurora
@export var rim_color: Gradient
## ink of the outlines (cw_outline_color)
@export var outline_color: Gradient

## how often (ms) the running cycle writes the sky material (see _process)
const SKY_STEP_MSEC := 200

var phase := 0.0
var _sky_msec := -SKY_STEP_MSEC
var _sky_phase := -1.0
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial
var _sun_azimuth := Vector2(0.0, -1.0)
var _lamps: Array[Light3D] = []
var _lamp_base: Array[float] = []
var _floods: Array[Light3D] = []
var _flood_base: Array[float] = []
var _glows: Array[GeometryInstance3D] = []


func _ready() -> void:
	if campus == null:
		return
	_sun = campus.get_node_or_null("Lights/Dusk") as DirectionalLight3D
	_moon = campus.get_node_or_null("Lights/Moon") as DirectionalLight3D
	var we := campus.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment
		if _env and _env.sky:
			_sky = _env.sky.sky_material as ShaderMaterial
	if _sun:
		var d := _sun.global_basis.z
		_sun_azimuth = Vector2(d.x, d.z).normalized()
	for n in campus.get_node("Props").get_children():
		if n is OmniLight3D:
			_lamps.append(n)
			_lamp_base.append((n as Light3D).light_energy)
	for n in campus.get_tree().get_nodes_in_group(&"campus_lamps"):
		if n is Light3D and campus.is_ancestor_of(n) and not _lamps.has(n):
			_lamps.append(n)
			_lamp_base.append((n as Light3D).light_energy)
	for n in campus.get_tree().get_nodes_in_group(&"campus_night_glow"):
		if n is GeometryInstance3D and campus.is_ancestor_of(n):
			_glows.append(n)
	var fl := campus.get_node_or_null("Dressing/Base/FloodLights")
	if fl:
		for n in fl.get_children():
			if n is Light3D:
				_floods.append(n)
				_flood_base.append((n as Light3D).light_energy)


## The toon tints are global: put the project values back when the campus goes away.
func _exit_tree() -> void:
	CwLook.reset_tints()


func _process(_delta: float) -> void:
	if not enabled or campus == null:
		return
	var main := get_parent()
	var p := phase
	if force_phase >= 0.0:
		p = force_phase
	else:
		var st = main.get("state")
		var clock = main.get("clock")
		if st == null or clock == null:
			return
		if (clock as TycoonClock).speed == 0:
			return
		var weeks := float(st.weeks) + (clock as TycoonClock).week_fraction()
		p = fposmod(weeks / weeks_per_cycle + phase_offset, 1.0)
	# the sky's colours change slowly: writing them re-renders and re-filters its radiance
	# cubemap, so they follow every SKY_STEP_MSEC (or at once after a jump of the phase)
	var now := Time.get_ticks_msec()
	var sky := now - _sky_msec >= SKY_STEP_MSEC or absf(p - _sky_phase) > 0.02
	if sky:
		_sky_msec = now
		_sky_phase = p
	apply(p, sky)


## Sets every look for a cycle phase (0..1); `sky` = false leaves the sky material as it is.
func apply(p: float, sky := true) -> void:
	phase = p
	if _sun:
		var e := deg_to_rad(_c(sun_elevation, p, 20.0))
		var to_sun := Vector3(_sun_azimuth.x * cos(e), sin(e), _sun_azimuth.y * cos(e))
		var up := Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD
		_sun.global_basis = Basis.looking_at(-to_sun, up)
		_sun.light_energy = _c(sun_energy, p, 2.6)
		_sun.visible = _sun.light_energy > 0.01
		if sun_color:
			_sun.light_color = sun_color.sample(p)
		if _sky and sky:
			_sky.set_shader_parameter("sun_dir", to_sun)
	if _moon:
		_moon.light_energy = _c(moon_energy, p, 0.38)
		if moon_color:
			_moon.light_color = moon_color.sample(p)
	if _env:
		_env.ambient_light_energy = _c(ambient_energy, p, 0.6)
		if ambient_color:
			_env.ambient_light_color = ambient_color.sample(p)
		_env.tonemap_exposure = _c(exposure, p, 1.05)
		if saturation:
			_env.adjustment_saturation = saturation.sample_baked(p)
		if contrast:
			_env.adjustment_contrast = contrast.sample_baked(p)
		if fog_color:
			_env.fog_light_color = fog_color.sample(p)
		if fog_density:
			_env.fog_density = fog_density.sample_baked(p)
	if _sky and sky:
		if zenith_color:
			_sky.set_shader_parameter("zenith_color", zenith_color.sample(p))
		if mid_color:
			_sky.set_shader_parameter("mid_color", mid_color.sample(p))
		if horizon_color:
			_sky.set_shader_parameter("horizon_color", horizon_color.sample(p))
		_sky.set_shader_parameter("glow_strength", _c(sky_glow, p, 1.6))
		_sky.set_shader_parameter("star_brightness", _c(stars, p, 1.5))
		_sky.set_shader_parameter("aurora_strength", _c(aurora, p, 0.32))
	if voxel_material:
		voxel_material.set_shader_parameter("glow_gain", _c(window_glow, p, 1.0))
		if window_tint:
			voxel_material.set_shader_parameter("glow_tint", window_tint.sample(p))
	if shadow_tint:
		CwLook.set_global(&"cw_shadow_tint", shadow_tint.sample(p))
	if rim_color:
		CwLook.set_global(&"cw_rim_color", rim_color.sample(p))
	if outline_color:
		CwLook.set_global(&"cw_outline_color", outline_color.sample(p))
	var lamp := _c(lamp_energy, p, 1.0)
	for i in _lamps.size():
		_lamps[i].light_energy = _lamp_base[i] * lamp
	for i in _floods.size():
		_floods[i].light_energy = _flood_base[i] * lamp
	var night := clampf((lamp - 1.05) / 0.5, 0.0, 1.0)
	for g in _glows:
		g.transparency = 1.0 - night
		g.visible = night > 0.01


static func _c(curve: Curve, p: float, fallback: float) -> float:
	return curve.sample_baked(p) if curve else fallback
