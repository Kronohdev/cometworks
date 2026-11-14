class_name FlightSky
extends WorldEnvironment
## Drives shaders/flight_sky.gdshader and the environment from the camera position
## (doubles): altitude, local up, the camera relative to the launch site, plus the Sun
## light, fog and exposure as the sky goes from blue to black. Sun / Moon directions and
## the planet orientation are fixed in the inertial frame (no Earth rotation).

## Launch-site latitude / longitude on the voxel Earth texture
## (scenes/flight/textures/earth_site.json, chosen by src/flight/gen/make_flight_textures.py).
@export var pad_lat := 3.0
@export var pad_lon := 67.0
## Render direction of the sea at the pad (= launch direction); must match the generator.
@export var site_east := Vector3(0.894, 0, -0.447)
@export var sun_direction := Vector3(0.55, 0.42, 0.72)
@export var moon_direction := Vector3(-0.62, 0.5, 0.6)
@export var sun_light: DirectionalLight3D
## Fog density at sea level (thins with the air)
@export var fog_density_sl := 0.00014
@export var ambient_ground := 0.55
@export var ambient_space := 0.4

var _mat: ShaderMaterial


func _ready() -> void:
	_mat = environment.sky.sky_material as ShaderMaterial
	_mat.set_shader_parameter("planet_to_tex", planet_to_tex())
	_mat.set_shader_parameter("sun_dir", sun_direction.normalized())
	_mat.set_shader_parameter("moon_dir", moon_direction.normalized())
	_mat.set_shader_parameter("planet_radius", FlightOrbit.R)
	# in-scattering samples (half-resolution pass) per quality level
	_mat.set_shader_parameter("scatter_steps", [6, 9, 12][GraphicsQuality.current()])
	if sun_light:
		sun_light.look_at_from_position(Vector3.ZERO, -sun_direction.normalized(),
			Vector3.UP if absf(sun_direction.normalized().y) < 0.99 else Vector3.RIGHT)


## Rotation from render/PCI directions to the texture's planet-fixed frame (same as
## site_matrix() in the generator): pad up -> pad direction, sea -> increasing longitude.
func planet_to_tex() -> Basis:
	var la := deg_to_rad(pad_lat)
	var lo := deg_to_rad(pad_lon)
	var u_p := Vector3(cos(la) * cos(lo), sin(la), cos(la) * sin(lo))
	var e_p := Vector3(-sin(lo), 0.0, cos(lo))
	var n_p := u_p.cross(e_p)
	var e_r := site_east.normalized()
	var u_r := Vector3.UP
	var n_r := u_r.cross(e_r)
	var a := Basis(e_r, u_r, n_r)
	var b := Basis(e_p, u_p, n_p)
	return b * a.transposed()


## Sun / Moon directions (from the camera, PCI) and the Moon's angular radius, from the
## solar system at the current mission time (FlightWorld._update_sky_bodies).
func set_bodies(sun_dir: Vector3, moon_dir: Vector3, moon_radius: float) -> void:
	if not sun_dir.is_equal_approx(sun_direction):
		sun_direction = sun_dir
		_mat.set_shader_parameter("sun_dir", sun_dir)
		if sun_light:
			sun_light.look_at_from_position(Vector3.ZERO, -sun_dir,
				Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.RIGHT)
	if not moon_dir.is_equal_approx(moon_direction):
		moon_direction = moon_dir
		_mat.set_shader_parameter("moon_dir", moon_dir)
	_mat.set_shader_parameter("moon_radius", moon_radius)


## cam_pci: camera position in the inertial frame (doubles); site_origin_pci: the launch
## site scene's origin in the same frame.
func update_camera(cam_pci: PackedFloat64Array, site_origin_pci: PackedFloat64Array, map_mode: bool) -> void:
	if has_meta("frozen"):
		return
	var r := sqrt(cam_pci[0] * cam_pci[0] + cam_pci[1] * cam_pci[1] + cam_pci[2] * cam_pci[2])
	var alt := r - FlightOrbit.R
	var up := Vector3(cam_pci[0] / r, cam_pci[1] / r, cam_pci[2] / r)
	_mat.set_shader_parameter("cam_alt", alt)
	_mat.set_shader_parameter("up_dir", up)
	_mat.set_shader_parameter("cam_site", Vector3(cam_pci[0] - site_origin_pci[0], cam_pci[1] - site_origin_pci[1],
		cam_pci[2] - site_origin_pci[2]))
	_mat.set_shader_parameter("map_mode", 1.0 if map_mode else 0.0)
	var air := clampf(FlightOrbit.density(alt) / FlightOrbit.RHO0, 0.0, 1.0)
	var env := environment
	env.fog_enabled = air > 0.002
	env.fog_density = fog_density_sl * air
	# daylight at the camera (the sun may be below the horizon in orbit)
	var sun_up := up.dot(sun_direction.normalized())
	var day := smoothstep(-0.25, 0.1, sun_up)
	# Ambient and fog colours are set here instead of being read from the sky's radiance
	# cubemap: re-filtering that cubemap every frame (the sky changes with the camera) cost
	# ~8 ms on an integrated GPU. Ground: blue sky light; space: dim blue earthshine.
	var k := sqrt(air)
	env.ambient_light_color = Color(0.36, 0.46, 0.66).lerp(Color(0.62, 0.72, 0.9), k)
	env.ambient_light_energy = lerpf(ambient_space, ambient_ground, k) * lerpf(0.35, 1.0, day)
	# fog = the sky colour near the horizon (pale blue by day, darker at dusk)
	env.fog_light_color = Color(0.5, 0.6, 0.75).lerp(Color(0.74, 0.82, 0.92), day)
	env.fog_light_energy = lerpf(0.25, 1.0, day)
	if sun_light:
		# the planet eclipses the sun at night: fade the light as it sets for the camera
		var horizon := -sqrt(maxf(1.0 - pow(FlightOrbit.R / r, 2.0), 0.0))
		var lit := smoothstep(horizon - 0.01, horizon + 0.01, sun_up)
		sun_light.light_energy = lerpf(2.7, 2.4, air) * lit
		sun_light.light_color = MarginPalette.SUN.lerp(Color(1.0, 0.75, 0.5), clampf(1.0 - sun_up * 4.0, 0.0, 1.0) * air)
