class_name CwLook
extends RefCounted
## The visual style of Cometworks: "Cartoon" (the toon light of shaders/include/cw_toon.gdshaderinc
## plus the ink outlines of scenes/fx/cw_outline.tscn) or "Clássico" (plain Lambert / GGX light,
## no outlines). Both are global: the toon light reads the shader global `cw_toon`, and every
## outline node (group "cw_outline") shows or hides itself. The choice persists in
## user://settings.cfg under [graphics] next to the quality level (MenuSettings exposes it to
## the options panel). The look's tunables live in project.godot (shader_globals); scenes may
## tint the shadows and the rim (the campus day cycle does, CwToonTint nodes do) and put the
## project values back with reset_tints().

const PATH := "user://settings.cfg"
const SECTION := "graphics"
const GROUP := &"cw_outline"
## globals a scene may tint at run time; reset_tints() restores the project.godot values
const TINT_GLOBALS := [&"cw_shadow_tint", &"cw_shadow_fill", &"cw_rim_color", &"cw_rim_strength",
	&"cw_outline_color", &"cw_outline_strength"]

static var _applied := false
static var _toon_value := 1.0


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func _store(key: String, value: Variant) -> void:
	var cfg := _cfg()
	cfg.set_value(SECTION, key, value)
	cfg.save(PATH)


## True for the cartoon style (the default).
static func toon() -> bool:
	return String(_cfg().get_value(SECTION, "style", "cartoon")) != "classic"


static func set_toon(on: bool) -> void:
	_store("style", "cartoon" if on else "classic")
	apply()


## Ink outlines on (the default). Only drawn in the cartoon style.
static func outlines() -> bool:
	return bool(_cfg().get_value(SECTION, "outlines", true))


static func set_outlines(on: bool) -> void:
	_store("outlines", on)
	apply()


## Whether outline nodes should draw now (cartoon style and outlines on).
static func outlines_visible() -> bool:
	return toon() and outlines()


## Applies the saved style: the toon global and every outline node in the tree.
static func apply() -> void:
	_applied = true
	_toon_value = 1.0 if toon() else 0.0
	RenderingServer.global_shader_parameter_set(&"cw_toon", _toon_value)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.call_group(GROUP, &"refresh")


## The value last given to the cw_toon global (1 cartoon, 0 classic).
static func toon_value() -> float:
	return _toon_value


## Applies the saved style once per run (outline nodes call it on _ready, so any scene that
## starts on its own gets the player's choice).
static func ensure_applied() -> void:
	if not _applied:
		apply()


static func set_global(param: StringName, value: Variant) -> void:
	RenderingServer.global_shader_parameter_set(param, value)


## The project.godot value of a shader global.
static func default_value(param: StringName) -> Variant:
	var s: Variant = ProjectSettings.get_setting("shader_globals/" + String(param))
	if s is Dictionary:
		return (s as Dictionary).get("value")
	return null


## Puts the tintable globals back to their project.godot values.
static func reset_tints() -> void:
	for p: StringName in TINT_GLOBALS:
		var v: Variant = default_value(p)
		if v != null:
			RenderingServer.global_shader_parameter_set(p, v)
