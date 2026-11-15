class_name GraphicsQuality
extends RefCounted
## Graphics presets (LOW / MEDIUM / HIGH, "Baixo / Médio / Alto" in the options panel) for the
## window's viewport and the 3D scenes in it. First run picks MEDIUM on integrated GPUs and
## HIGH on dedicated ones; the choice persists in user://settings.cfg under [graphics]
## (F3 cycles in the hangar; the options panel's Image rows and the dev menu set it).
##   viewport      3D render scale (FSR below 1.0); LOW also turns the anti-aliasing off
##                 (CwLook.apply_antialiasing asks max_aa()) and makes the soft shadows hard
##   environments  SSAO, SSIL and glow off below their preset (never on where the scene had
##                 them off: the authored values are kept in metadata)
##   lights        directional shadow splits and distance (LOW: one orthogonal map in a
##                 smaller atlas); omni / spot shadows only on HIGH;
##                 lights in the "optional_light" group only on HIGH; on LOW the small
##                 decorative lamps (range <= LAMP_RANGE m: campus and fair lamps, the stage
##                 and stall glows, the lighthouse) switch off
##   foliage       scattered grass, flowers and bushes (CampusScatter in area mode that does
##                 not block walkers: the campus, the island, the conference fair's dressing)
##                 show this share of their instances (MultiMesh.visible_instance_count)
## watch() follows the tree, so every scene added later (the campus, the fair, the hangar)
## gets the preset as it enters; apply(root) sweeps a subtree now; set_level() re-applies
## everything live.

enum Level { LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
const NAMES := ["LOW", "MEDIUM", "HIGH"]
## omni / spot lights up to this range (m) are decorative lamps, off on LOW
const LAMP_RANGE := 24.0

## Per level: 3D render scale (FSR upscaling below 1.0), screen-space effects, shadows, lamps,
## foliage share and the strongest anti-aliasing allowed ("" = the player's choice);
## shadow_atlas is the directional shadow map size (0 = project.godot's).
const PRESETS := {
	Level.LOW: {"scale": 0.6, "ssao": false, "ssil": false, "glow": false,
		"shadow_mode": DirectionalLight3D.SHADOW_ORTHOGONAL, "shadow_distance": 200.0, "shadow_atlas": 2048, "soft_shadows": false, "omni_shadows": false,
		"optional_lights": false, "lamps": false, "foliage": 0.35, "aa": "off", "ambient_boost": 1.6},
	Level.MEDIUM: {"scale": 0.7, "ssao": false, "ssil": false, "glow": true,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "shadow_distance": 220.0, "shadow_atlas": 0, "soft_shadows": true, "omni_shadows": false,
		"optional_lights": false, "lamps": true, "foliage": 0.7, "aa": "", "ambient_boost": 1.35},
	Level.HIGH: {"scale": 1.0, "ssao": true, "ssil": true, "glow": true,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "shadow_distance": 320.0, "shadow_atlas": 0, "soft_shadows": true, "omni_shadows": true,
		"optional_lights": true, "lamps": true, "foliage": 1.0, "aa": "", "ambient_boost": 1.0},
}

static var level: int = -1
static var _watcher: _Watcher


## Hands new nodes to GraphicsQuality as they enter the tree (see watch()).
class _Watcher:
	extends RefCounted

	func on_added(n: Node) -> void:
		if n is Light3D or n is WorldEnvironment or n is MultiMeshInstance3D:
			GraphicsQuality.adopt(n)

	## The campus sky's animation clock (shaders/campus_sky.gdshader reads the cw_sky_time global
	## instead of TIME, so its radiance cubemap is not re-rendered every frame). Wraps like TIME.
	func on_frame() -> void:
		RenderingServer.global_shader_parameter_set(&"cw_sky_time", fmod(Time.get_ticks_msec() / 1000.0, 3600.0))


static func current() -> int:
	if level < 0:
		var cfg := ConfigFile.new()
		level = default_level()
		if cfg.load(SETTINGS_PATH) == OK:
			level = clampi(int(cfg.get_value("graphics", "quality", level)), Level.LOW, Level.HIGH)
	return level


## First run: MEDIUM on integrated GPUs (the target hardware), HIGH on dedicated ones.
static func default_level() -> int:
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return Level.HIGH
	return Level.MEDIUM


static func preset() -> Dictionary:
	return PRESETS[current()]


## Saves the level and applies it to the whole tree now.
static func set_level(l: int) -> void:
	level = clampi(l, Level.LOW, Level.HIGH)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "quality", level)
	cfg.save(SETTINGS_PATH)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		apply(tree.root)


## Share of the scattered foliage instances shown (1.0 = all).
static func foliage_density() -> float:
	return float(preset()["foliage"])


## The strongest anti-aliasing the level allows: "off" on LOW, "" (the player's) otherwise.
static func max_aa() -> String:
	return String(preset()["aa"])


## Starts following the tree: every Light3D, WorldEnvironment and scatter that enters it later
## gets the current preset (once per run).
static func watch() -> void:
	if _watcher != null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_watcher = _Watcher.new()
	tree.node_added.connect(_watcher.on_added)
	tree.process_frame.connect(_watcher.on_frame)


## Window-wide settings: the root viewport's render scale and AA, the soft shadow filters.
static func apply_global() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var p := preset()
	var vp := tree.root
	var scale: float = p["scale"]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	var soft := bool(p["soft_shadows"])
	var q := int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2))
	var dq := int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2))
	RenderingServer.positional_soft_shadow_filter_set_quality(
		(q if soft else RenderingServer.SHADOW_QUALITY_HARD) as RenderingServer.ShadowQuality)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		(dq if soft else RenderingServer.SHADOW_QUALITY_HARD) as RenderingServer.ShadowQuality)
	var atlas := int(p["shadow_atlas"])
	if atlas <= 0:
		atlas = int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096))
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	CwLook.apply_antialiasing()


## Applies the current preset to the scene rooted at `root` (the window viewport, every
## WorldEnvironment, light and foliage scatter under it).
static func apply(root: Node) -> void:
	var vp := root.get_viewport()
	if vp == null or vp == (Engine.get_main_loop() as SceneTree).root or root == (Engine.get_main_loop() as SceneTree).root:
		apply_global()
	else:
		var scale: float = preset()["scale"]
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = scale
	# fill lights in the "optional_light" group turn off below HIGH: where a scene has them, its
	# ambient light makes up for them (authored energy kept in metadata)
	var boost := 1.0
	if not (Engine.get_main_loop() as SceneTree).get_nodes_in_group(&"optional_light").is_empty():
		boost = float(preset()["ambient_boost"])
	for n in root.find_children("*", "WorldEnvironment", true, false):
		adopt(n)
		var env := (n as WorldEnvironment).environment
		if env != null and (boost != 1.0 or env.has_meta("authored_ambient")):
			if not env.has_meta("authored_ambient"):
				env.set_meta("authored_ambient", env.ambient_light_energy)
			env.ambient_light_energy = float(env.get_meta("authored_ambient")) * boost
	for n in root.find_children("*", "Light3D", true, false):
		adopt(n)
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		adopt(n)


## Applies the preset to one node (a WorldEnvironment, a Light3D or a scatter).
static func adopt(n: Node) -> void:
	var p := preset()
	if n is WorldEnvironment:
		_adopt_env((n as WorldEnvironment).environment, p)
	elif n is DirectionalLight3D:
		var d := n as DirectionalLight3D
		if d.shadow_enabled:
			d.directional_shadow_mode = int(p["shadow_mode"]) as DirectionalLight3D.ShadowMode
			d.directional_shadow_max_distance = p["shadow_distance"]
	elif n is OmniLight3D or n is SpotLight3D:
		var l := n as Light3D
		# the authored flags stay in metadata so a higher level can restore them
		if not l.has_meta("authored_shadow"):
			l.set_meta("authored_shadow", l.shadow_enabled)
			l.set_meta("authored_visible", l.visible)
		l.shadow_enabled = bool(l.get_meta("authored_shadow")) and bool(p["omni_shadows"])
		var on := bool(l.get_meta("authored_visible"))
		if l.is_in_group("optional_light"):
			on = on and bool(p["optional_lights"])
		elif is_lamp(l):
			on = on and bool(p["lamps"])
		l.visible = on
	elif n is CampusScatter:
		_adopt_scatter(n as CampusScatter, float(p["foliage"]))


## A small decorative light of the campus or the fair (a lamp, a window glow, the stage
## spot): range up to LAMP_RANGE, under the Campus or the ConferenceFair. The key lights of
## cutscene sets, menu shots and portrait studios are never lamps.
static func is_lamp(l: Light3D) -> bool:
	var r := 0.0
	if l is OmniLight3D:
		r = (l as OmniLight3D).omni_range
	elif l is SpotLight3D:
		r = (l as SpotLight3D).spot_range
	if r <= 0.0 or r > LAMP_RANGE:
		return false
	if l.is_in_group(&"campus_lamps"):
		return true
	var p := l.get_parent()
	while p != null:
		if p is Campus or p is ConferenceFair:
			return true
		p = p.get_parent()
	return false


## Whether a scatter is foliage to thin out: area mode (instances in random order, so the
## first N are an even sample) and nothing the walkers go round (trees, fences, rocks stay).
static func is_foliage(s: CampusScatter) -> bool:
	return s.path.is_empty() and not s.blocks_walkers


static func _adopt_scatter(s: CampusScatter, density: float) -> void:
	if not is_foliage(s) or s.multimesh == null or Engine.is_editor_hint():
		return
	var mm := s.multimesh
	mm.visible_instance_count = -1 if density >= 1.0 else int(ceil(mm.instance_count * density))
	s.sync_chunks()   # a scatter drawn in chunks (CampusScatter._build_chunks) passes it on


static func _adopt_env(env: Environment, p: Dictionary) -> void:
	if env == null:
		return
	if not env.has_meta("authored_ssao"):
		env.set_meta("authored_ssao", env.ssao_enabled)
		env.set_meta("authored_ssil", env.ssil_enabled)
		env.set_meta("authored_glow", env.glow_enabled)
	env.ssao_enabled = bool(env.get_meta("authored_ssao")) and bool(p["ssao"])
	env.ssil_enabled = bool(env.get_meta("authored_ssil")) and bool(p["ssil"])
	env.glow_enabled = bool(env.get_meta("authored_glow")) and bool(p["glow"])


## Cycles LOW -> MEDIUM -> HIGH, applies and returns the new level name.
static func cycle(root: Node) -> String:
	set_level((current() + 1) % 3)
	apply(root)
	return NAMES[current()]
