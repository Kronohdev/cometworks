@tool
class_name PlanetSurface
extends Node3D
## Root of scenes/surface/planet_surface.tscn. Owns the authored WorldEnvironment,
## Sun, Terrain (VoxelTerrain) and Water nodes and applies a PlanetSurfaceProfile
## to all of them: sky shader colors, sun color/angle, ambient, fog, liquid and
## the physics gravity of the world. Change `profile` (inspector or code) and
## everything updates, in the editor too.

signal profile_changed(profile: PlanetSurfaceProfile)

@export var profile: PlanetSurfaceProfile:
	set = set_profile
## Node the terrain streams around and the water follows (camera, lander...).
@export var focus_path: NodePath:
	set(v):
		focus_path = v
		if is_node_ready():
			_apply_focus()
## Set the world's default gravity to the profile's value at runtime.
@export var apply_world_gravity: bool = true

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var terrain: VoxelTerrain = $Terrain
@onready var water: MeshInstance3D = $Water
@onready var landing_site: Marker3D = $LandingSite

var _focus: Node3D


func _ready() -> void:
	_apply_focus()
	apply_profile()


func set_profile(p: PlanetSurfaceProfile) -> void:
	profile = p
	if is_node_ready():
		apply_profile()


func set_focus(node: Node3D) -> void:
	focus_path = get_path_to(node) if node else NodePath()


func _apply_focus() -> void:
	_focus = get_node_or_null(focus_path) as Node3D if not focus_path.is_empty() else null
	if terrain:
		terrain.focus_path = terrain.get_path_to(_focus) if _focus else NodePath()


func _process(_delta: float) -> void:
	if _focus and water.visible:
		# the water plane follows the focus; its shader works in world space
		water.global_position = Vector3(snappedf(_focus.global_position.x, 64.0), water.global_position.y,
			snappedf(_focus.global_position.z, 64.0))


## Ground height (top of the 1 m voxels) at a world position.
func ground_height(x: float, z: float) -> float:
	return terrain.get_height(x, z)


func apply_profile() -> void:
	if profile == null:
		return
	var p := profile
	terrain.profile = p
	_apply_environment(p)
	_apply_sun(p)
	water.visible = p.has_sea
	water.position.y = p.sea_level
	var wm := water.get_surface_override_material(0) as ShaderMaterial
	if wm:
		wm.set_shader_parameter(&"shallow_color", p.water_shallow_color)
		wm.set_shader_parameter(&"deep_color", p.water_deep_color)
	if apply_world_gravity and not Engine.is_editor_hint() and is_inside_tree():
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, p.gravity)
	profile_changed.emit(p)


func _apply_environment(p: PlanetSurfaceProfile) -> void:
	var env := world_env.environment
	if env == null:
		return
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = p.ambient_color
	env.ambient_light_energy = p.ambient_energy
	env.tonemap_exposure = p.exposure
	env.fog_enabled = p.fog_enabled
	env.fog_light_color = p.fog_color
	env.fog_density = p.fog_density
	env.fog_aerial_perspective = p.fog_aerial_perspective
	env.fog_sun_scatter = p.fog_sun_scatter
	env.fog_height = p.fog_height
	env.fog_height_density = p.fog_height_density
	env.fog_sky_affect = 0.0
	var sky_mat := env.sky.sky_material as ShaderMaterial if env.sky else null
	if sky_mat:
		sky_mat.set_shader_parameter(&"zenith_color", p.sky_zenith_color)
		sky_mat.set_shader_parameter(&"horizon_color", p.sky_horizon_color)
		sky_mat.set_shader_parameter(&"ground_color", p.sky_ground_color)
		sky_mat.set_shader_parameter(&"gradient_power", p.sky_gradient_power)
		sky_mat.set_shader_parameter(&"star_intensity", p.star_intensity)
		sky_mat.set_shader_parameter(&"sun_color", p.sun_color)
		sky_mat.set_shader_parameter(&"sun_size_deg", p.sun_size_deg)
		sky_mat.set_shader_parameter(&"glow_color", p.sun_glow_color)
		sky_mat.set_shader_parameter(&"glow_strength", p.sun_glow_strength)
		sky_mat.set_shader_parameter(&"body_enabled", p.sky_body_enabled)
		sky_mat.set_shader_parameter(&"body_dir", p.sky_body_direction())
		sky_mat.set_shader_parameter(&"body_size_deg", p.sky_body_size_deg)
		sky_mat.set_shader_parameter(&"body_color_a", p.sky_body_color_a)
		sky_mat.set_shader_parameter(&"body_color_b", p.sky_body_color_b)
		sky_mat.set_shader_parameter(&"body_bands", p.sky_body_bands)


func _apply_sun(p: PlanetSurfaceProfile) -> void:
	var to_sun := p.sun_direction()
	var up := Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD
	sun.basis = Basis.looking_at(-to_sun, up)
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
