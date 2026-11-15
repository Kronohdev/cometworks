class_name CwAccess
extends RefCounted
## Accessibility options, kept in user://settings.cfg under [access] (the options panel's
## "Acessibilidade" page, MenuOptionsPanel):
##   text size    the UI scale, one of UI_SCALES (90 / 100 / 115 / 130 %). Applied as the root
##                window's content_scale_factor, so with the project's canvas_items / expand
##                stretch every layout keeps its anchors and simply gets a smaller logical view
##                (1600x900 at 130 % is 1231x692); tests/test_ui_fit.gd --ui-scale=1.3 checks
##                that the HUD and the screens still fit.
##   colour-blind the agency and briefing-kind colours switch to the Okabe-Ito palette and the
##                markers and swatches draw a shape cue on top (CwPalette.colorblind, cue_of,
##                draw_cue), so they are never told apart by hue alone.
## The key bindings (CwKeys) and the graphics quality (GraphicsQuality) live in the same file.
## ensure_applied() runs once per run from any scene that starts on its own (the menu, the
## campaign); setters apply live.

const PATH := "user://settings.cfg"
const SECTION := "access"
const UI_SCALES: Array[float] = [0.9, 1.0, 1.15, 1.3]
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


## The saved text size (1.0 = 100 %), snapped to UI_SCALES.
static func ui_scale() -> float:
	return snap_scale(float(_cfg().get_value(SECTION, "ui_scale", 1.0)))


## The UI_SCALES entry nearest to `s`.
static func snap_scale(s: float) -> float:
	var best := 1.0
	for u: float in UI_SCALES:
		if absf(u - s) < absf(best - s):
			best = u
	return best


static func set_ui_scale(s: float) -> void:
	_store("ui_scale", snap_scale(s))
	apply_ui_scale()


static func apply_ui_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.content_scale_factor = ui_scale()


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


## Applies everything saved: text size, colour-blind mode, key bindings and the graphics
## quality (which also starts watching new scenes for lights, environments and scatters).
static func apply() -> void:
	_applied = true
	apply_ui_scale()
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
