class_name CwAccess
extends RefCounted
## Accessibility options, kept in user://settings.cfg under [access] (the options panel's
## "Acessibilidade" page, MenuOptionsPanel):
##   colour-blind the agency and briefing-kind colours switch to the Okabe-Ito palette and the
##                markers and swatches draw a shape cue on top (CwPalette.colorblind, cue_of,
##                draw_cue), so they are never told apart by hue alone.
## The key bindings (CwKeys) and the graphics quality (GraphicsQuality) live in the same file.
## ensure_applied() runs once per run from any scene that starts on its own (the menu, the
## campaign); setters apply live.

const PATH := "user://settings.cfg"
const SECTION := "access"
## group of the controls that draw colour-blind cues (redrawn when the mode changes)
const CUE_GROUP := &"cw_cue"

static var _applied := false


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func _store(key: String, value: Variant) -> void:
	var cfg := _cfg()
	cfg.set_value(SECTION, key, value)
	cfg.save(PATH)


## Colour-blind friendly colours and shape cues (off by default).
static func colorblind() -> bool:
	return bool(_cfg().get_value(SECTION, "colorblind", false))


static func set_colorblind(on: bool) -> void:
	_store("colorblind", on)
	apply_colorblind()


static func apply_colorblind() -> void:
	CwPalette.colorblind = colorblind()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for n in tree.get_nodes_in_group(CUE_GROUP):
			if n.has_method(&"refresh_cue"):
				n.call(&"refresh_cue")
			elif n is CanvasItem:
				(n as CanvasItem).queue_redraw()


## Applies everything saved: colour-blind mode, key bindings and the graphics
## quality (which also starts watching new scenes for lights, environments and scatters).
static func apply() -> void:
	_applied = true
	_drop_retired()
	apply_colorblind()
	CwKeys.apply()
	GraphicsQuality.watch()
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		GraphicsQuality.apply(tree.root)   # what is already in the tree; the watch takes the rest


## apply() once per run.
static func ensure_applied() -> void:
	if not _applied:
		apply()


## Settings no longer offered (the old UI text size, "ui_scale") are removed from the file
## instead of applied.
static func _drop_retired() -> void:
	var cfg := _cfg()
	if cfg.has_section_key(SECTION, "ui_scale"):
		cfg.erase_section_key(SECTION, "ui_scale")
		cfg.save(PATH)
