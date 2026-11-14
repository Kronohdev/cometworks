class_name GraphicsQuality
extends RefCounted
## Graphics presets (LOW / MEDIUM / HIGH) applied to a viewport and its WorldEnvironment.
## First run picks MEDIUM on integrated GPUs and HIGH on dedicated ones; the choice
## persists in user://settings.cfg (F3 cycles in the hangar).
## Any scene can call GraphicsQuality.apply(self) in _ready and cycle() on a key (F3).

enum Level { LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
const NAMES := ["LOW", "MEDIUM", "HIGH"]

## Per level: 3D render scale (FSR upscaling below 1.0), screen-space effects, shadows.
const PRESETS := {
	Level.LOW: {"scale": 0.6, "ssao": false, "ssil": false, "glow": false, "fog": true,
		"shadow_cascades": 1, "shadow_distance": 120.0, "omni_shadows": false,
		"optional_lights": false, "ambient_boost": 1.6},
	Level.MEDIUM: {"scale": 0.7, "ssao": false, "ssil": false, "glow": true, "fog": true,
		"shadow_cascades": 2, "shadow_distance": 220.0, "omni_shadows": false,
		"optional_lights": false, "ambient_boost": 1.35},
	Level.HIGH: {"scale": 1.0, "ssao": true, "ssil": true, "glow": true, "fog": true,
		"shadow_cascades": 4, "shadow_distance": 320.0, "omni_shadows": true,
		"optional_lights": true, "ambient_boost": 1.0},
}

static var level: int = -1


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


static func set_level(l: int) -> void:
	level = clampi(l, Level.LOW, Level.HIGH)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "quality", level)
	cfg.save(SETTINGS_PATH)


## Applies the current preset to the scene rooted at `root` (its viewport, every
## WorldEnvironment and every shadowed light under it).
static func apply(root: Node) -> void:
	var p: Dictionary = PRESETS[current()]
	var vp := root.get_viewport()
	var scale: float = p["scale"]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	for we in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		if env == null:
			continue
		# lights in the "optional_light" group are fill lights; below HIGH they turn off and
		# the ambient light makes up for them (authored energy kept in metadata)
		if not env.has_meta("authored_ambient"):
			env.set_meta("authored_ambient", env.ambient_light_energy)
		env.ambient_light_energy = float(env.get_meta("authored_ambient")) * float(p["ambient_boost"])
		env.ssao_enabled = p["ssao"]
		env.ssil_enabled = p["ssil"]
		env.glow_enabled = p["glow"]
		env.fog_enabled = p["fog"]
	for l in root.find_children("*", "DirectionalLight3D", true, false):
		var d := l as DirectionalLight3D
		if d.shadow_enabled:
			d.directional_shadow_mode = [DirectionalLight3D.SHADOW_ORTHOGONAL,
				DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
				DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][[0, 1, 1, 2, 2][int(p["shadow_cascades"])]]
			d.directional_shadow_max_distance = p["shadow_distance"]
	for l in root.find_children("*", "Light3D", true, false):
		if l is OmniLight3D or l is SpotLight3D:
			# keep the authored flag in metadata so HIGH can restore it
			if not l.has_meta("authored_shadow"):
				l.set_meta("authored_shadow", (l as Light3D).shadow_enabled)
			(l as Light3D).shadow_enabled = bool(l.get_meta("authored_shadow")) and bool(p["omni_shadows"])
		if (l as Node).is_in_group("optional_light"):
			(l as Light3D).visible = bool(p["optional_lights"])


## Cycles LOW -> MEDIUM -> HIGH, applies and returns the new level name.
static func cycle(root: Node) -> String:
	set_level((current() + 1) % 3)
	apply(root)
	return NAMES[current()]
