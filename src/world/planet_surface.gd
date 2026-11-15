@tool
class_name PlanetSurface
extends Node3D
## Root of scenes/surface/planet_surface.tscn. Owns the authored WorldEnvironment,
## Sun, Terrain (VoxelTerrain) and Water nodes and applies a PlanetSurfaceProfile
## to all of them: sky shader colors, sun color/angle, ambient, fog, liquid and
## the physics gravity of the world. Change `profile` (inspector or code) and
## everything updates, in the editor too.
## Authored landforms (SurfaceTerrainFeature nodes anywhere below this node, by convention
## under "Features") go to the terrain with the profile; then every node of SNAP_GROUP
## (points of interest, collectibles, set pieces: SurfacePoi, SurfaceGroundSnap) is put
## back on the ground with snap_to_ground(self).

signal profile_changed(profile: PlanetSurfaceProfile)

const SNAP_GROUP := &"surface_snap"

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
var _feature_timer := -1.0


func _ready() -> void:
	_apply_focus()
	apply_profile()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		CwLook.reset_tints()   # the campus / the menu get their own cartoon light back


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


## The editor moved / changed a feature: rebuild shortly (several edits in a row = one rebuild).
func request_feature_rebuild() -> void:
	_feature_timer = 0.25


func collect_features() -> Array:
	var out: Array = []
	for n in find_children("*", "SurfaceTerrainFeature", true, false):
		if (n as Node3D).visible:
			out.append((n as SurfaceTerrainFeature).to_feature())
	return out


## Discs (x, z, radius) the scattered boulders keep out of: flattened sites, ramps, every
## point of interest / find / challenge ring / spawn below this node (their set pieces stay clear).
func collect_prop_exclusions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in find_children("*", "SurfaceTerrainFeature", true, false):
		var f := n as SurfaceTerrainFeature
		var fp := _local_xz(f)
		if f.shape == SurfaceTerrainFeature.Shape.FLAT:
			out.append(Vector3(fp.x, fp.z, f.size_a + f.size_b))
		elif f.shape == SurfaceTerrainFeature.Shape.RAMP:
			out.append(Vector3(fp.x, fp.z, f.size_a + f.size_b + 6.0))
	for n in find_children("*", "SurfaceInteractable", true, false):
		var p := _local_xz(n as Node3D)
		out.append(Vector3(p.x, p.z, float(n.get("reach_radius")) + 3.0))
	for n in find_children("*", "SurfaceChallenge", true, false):
		var p := _local_xz(n as Node3D)
		out.append(Vector3(p.x, p.z, float(n.get("radius")) + 2.0))
	for n in find_children("*", "Marker3D", true, false):
		if n.is_in_group(SurfaceSession.SPAWN_GROUP):
			var p := _local_xz(n as Node3D)
			out.append(Vector3(p.x, p.z, 8.0))
	return out


## Position of a descendant relative to this node (works before entering the tree).
func _local_xz(n: Node3D) -> Vector3:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c and c != self:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t.origin


## The node the terrain streams around (the rover, the camera...), null if none.
func get_focus() -> Node3D:
	return _focus


## Puts every node of SNAP_GROUP below this surface on the ground.
func snap_content() -> void:
	if terrain == null or terrain.generator == null or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(SNAP_GROUP):
		if is_ancestor_of(n) and n.has_method("snap_to_ground"):
			n.call("snap_to_ground", self)


func _process(delta: float) -> void:
	if _feature_timer >= 0.0:
		_feature_timer -= delta
		if _feature_timer < 0.0:
			terrain.set_features(collect_features())
			snap_content()
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
	terrain.features = collect_features()
	terrain.prop_exclusions = collect_prop_exclusions()
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
	if not Engine.is_editor_hint() and is_inside_tree():
		CwLook.set_global(&"cw_shadow_tint", p.shadow_tint)
		CwLook.set_global(&"cw_shadow_fill", p.shadow_fill)
	snap_content()
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
