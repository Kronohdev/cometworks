class_name MenuOptionsPanel
extends PanelContainer
## Options of the main menu (scenes/menu/options_panel.tscn): language EN / PT, window or
## fullscreen, master, music and effects volume, the visual style (Cartoon / Classic, CwLook),
## the ink outlines, the anti-aliasing (SMAA / MSAA 4x / off, applied live) and the campus
## weather (rain and clouds on / off, MenuSettings.set_weather, applied live). Layout and
## styles live in the scene; this script reads and writes MenuSettings and emits `closed` on Back / Esc. Motion: full or reduced (the UI
## motion components, src/tycoon/ui/motion/, keep only short fades when reduced).
## The Camera page (the header tabs; Grid rows with metadata page = "camera") holds the campus
## camera's turn and zoom sensitivity, invert turn / tilt / zoom, which mouse button turns
## (the other pans) and edge scrolling (MenuSettings.set_camera_value, applied live).
## Rows with metadata page = "tycoon" (the Cometlings' speech bubbles and their frequency)
## only show in the in-game settings, which list them in `rows`.
## Graphics quality Baixo / Médio / Alto (GraphicsQuality, applied live; Baixo also turns the
## anti-aliasing off, so the AA keys grey out). The Accessibility page (metadata page =
## "access"): text size 90 / 100 / 115 / 130 % and the colour-blind friendly colours
## (CwAccess), and the key list (CwKeys): one row per action, copies of the hidden
## KeyTemplate; pressing a row's key waits for the next key (Esc cancels), a key another action
## had is swapped onto it, "Restore keys" puts the defaults back.

signal closed

## When not empty, only these Grid rows show (node names, label and control), and the
## General / Camera tabs hide: a host screen that splits the options over its own tabs (the
## in-game settings) picks the rows of each copy here, in the inspector.
@export var rows: PackedStringArray = PackedStringArray()

@onready var lang_en: Button = %LangEN
@onready var lang_pt: Button = %LangPT
@onready var win: Button = %Windowed
@onready var full: Button = %Fullscreen
@onready var volume: HSlider = %Volume
@onready var volume_value: Label = %VolumeValue
@onready var music_volume: HSlider = %MusicVolume
@onready var music_value: Label = %MusicValue
@onready var sfx_volume: HSlider = %SfxVolume
@onready var sfx_value: Label = %SfxValue
@onready var back: Button = %Back
@onready var motion_full: Button = %MotionFull
@onready var motion_reduced: Button = %MotionReduced
@onready var style_toon: Button = %StyleToon
@onready var style_classic: Button = %StyleClassic
@onready var outlines_on: Button = %OutlinesOn
@onready var outlines_off: Button = %OutlinesOff
@onready var cam_rotate: HSlider = %CamRotate
@onready var cam_rotate_value: Label = %CamRotateValue
@onready var cam_zoom: HSlider = %CamZoom
@onready var cam_zoom_value: Label = %CamZoomValue
@onready var invert_rotate: Button = %InvertRotate
@onready var invert_tilt: Button = %InvertTilt
@onready var invert_zoom: Button = %InvertZoom
@onready var orbit_middle: Button = %OrbitMiddle
@onready var orbit_right: Button = %OrbitRight
@onready var edge_on: Button = %EdgeOn
@onready var edge_off: Button = %EdgeOff
@onready var page_general: Button = %PageGeneral
@onready var page_camera: Button = %PageCamera
@onready var grid: GridContainer = $Margin/VBox/Grid
@onready var aa_smaa: Button = %AASmaa
@onready var aa_msaa4: Button = %AAMsaa4
@onready var aa_off: Button = %AAOff
@onready var weather_on: Button = %WeatherOn
@onready var weather_off: Button = %WeatherOff
## the in-game rows (metadata page = "tycoon", shown only where `rows` lists them): the
## Cometlings' speech bubbles on / off and how chatty they are (ChatterBook)
@onready var bubbles_on: Button = %BubblesOn
@onready var bubbles_off: Button = %BubblesOff
@onready var rate_buttons := {"few": %RateFew, "normal": %RateNormal, "many": %RateMany}
@onready var page_access: Button = %PageAccess
@onready var quality_buttons := {GraphicsQuality.Level.LOW: %QualityLow, GraphicsQuality.Level.MEDIUM: %QualityMedium,
	GraphicsQuality.Level.HIGH: %QualityHigh}
## text size buttons, in CwAccess.UI_SCALES order
@onready var text_buttons: Array[Button] = [%Text90, %Text100, %Text115, %Text130]
@onready var colorblind_on: Button = %ColorblindOn
@onready var colorblind_off: Button = %ColorblindOff
@onready var key_template: Control = %KeyTemplate
@onready var keys_hint: Label = %KeysHint

## the action whose key row waits for a key (&"" when none)
var listening: StringName = &""


func _ready() -> void:
	page_general.pressed.connect(show_page.bind(""))
	page_camera.pressed.connect(show_page.bind("camera"))
	page_access.pressed.connect(show_page.bind("access"))
	show_page("")
	lang_en.pressed.connect(MenuSettings.set_locale.bind("en"))
	lang_pt.pressed.connect(MenuSettings.set_locale.bind("pt"))
	win.pressed.connect(MenuSettings.set_fullscreen.bind(false))
	full.pressed.connect(MenuSettings.set_fullscreen.bind(true))
	volume.value_changed.connect(func(v: float) -> void:
		MenuSettings.set_volume(v / 100.0)
		_show_volume())
	music_volume.value_changed.connect(func(v: float) -> void:
		MenuSettings.set_music_volume(v / 100.0)
		_show_volume())
	sfx_volume.value_changed.connect(func(v: float) -> void:
		MenuSettings.set_sfx_volume(v / 100.0)
		_show_volume()
		CwSfx.play(&"menu_hover"))   # a sample of the new level
	motion_full.pressed.connect(MenuSettings.set_reduce_motion.bind(false))
	motion_reduced.pressed.connect(MenuSettings.set_reduce_motion.bind(true))
	style_toon.pressed.connect(func() -> void:
		MenuSettings.set_toon_style(true)
		sync())
	style_classic.pressed.connect(func() -> void:
		MenuSettings.set_toon_style(false)
		sync())
	outlines_on.pressed.connect(MenuSettings.set_outlines.bind(true))
	outlines_off.pressed.connect(MenuSettings.set_outlines.bind(false))
	cam_rotate.value_changed.connect(func(v: float) -> void:
		MenuSettings.set_camera_value("rotate_sensitivity", v / 100.0)
		_show_camera())
	cam_zoom.value_changed.connect(func(v: float) -> void:
		MenuSettings.set_camera_value("zoom_sensitivity", v / 100.0)
		_show_camera())
	invert_rotate.toggled.connect(func(on: bool) -> void: MenuSettings.set_camera_value("invert_rotate", on))
	invert_tilt.toggled.connect(func(on: bool) -> void: MenuSettings.set_camera_value("invert_tilt", on))
	invert_zoom.toggled.connect(func(on: bool) -> void: MenuSettings.set_camera_value("invert_zoom", on))
	orbit_middle.pressed.connect(MenuSettings.set_camera_value.bind("orbit_button", "middle"))
	orbit_right.pressed.connect(MenuSettings.set_camera_value.bind("orbit_button", "right"))
	edge_on.pressed.connect(MenuSettings.set_camera_value.bind("edge_scroll", true))
	edge_off.pressed.connect(MenuSettings.set_camera_value.bind("edge_scroll", false))
	aa_smaa.pressed.connect(MenuSettings.set_antialiasing.bind("smaa"))
	aa_msaa4.pressed.connect(MenuSettings.set_antialiasing.bind("msaa4"))
	aa_off.pressed.connect(MenuSettings.set_antialiasing.bind("off"))
	weather_on.pressed.connect(MenuSettings.set_weather.bind(true))
	weather_off.pressed.connect(MenuSettings.set_weather.bind(false))
	bubbles_on.pressed.connect(func() -> void:
		ChatterBook.set_enabled(true)
		sync())
	bubbles_off.pressed.connect(func() -> void:
		ChatterBook.set_enabled(false)
		sync())
	for r: String in rate_buttons:
		(rate_buttons[r] as Button).pressed.connect(ChatterBook.set_rate.bind(r))
	for l: int in quality_buttons:
		(quality_buttons[l] as Button).pressed.connect(func() -> void:
			GraphicsQuality.set_level(l)
			sync())
	for i in text_buttons.size():
		text_buttons[i].pressed.connect(CwAccess.set_ui_scale.bind(CwAccess.UI_SCALES[i]))
	colorblind_on.pressed.connect(CwAccess.set_colorblind.bind(true))
	colorblind_off.pressed.connect(CwAccess.set_colorblind.bind(false))
	%KeysReset.pressed.connect(func() -> void:
		listening = &""
		CwKeys.reset_defaults()
		_fill_keys())
	back.pressed.connect(func() -> void: closed.emit())
	sync()


## Puts the controls in the state of the current settings.
func sync() -> void:
	var pt := MenuSettings.locale() == "pt"
	lang_pt.set_pressed_no_signal(pt)
	lang_en.set_pressed_no_signal(not pt)
	var fs := MenuSettings.is_fullscreen()
	full.set_pressed_no_signal(fs)
	win.set_pressed_no_signal(not fs)
	volume.set_value_no_signal(roundf(MenuSettings.volume() * 100.0))
	music_volume.set_value_no_signal(roundf(MenuSettings.music_volume() * 100.0))
	sfx_volume.set_value_no_signal(roundf(MenuSettings.sfx_volume() * 100.0))
	var reduced := MenuSettings.reduce_motion()
	motion_reduced.set_pressed_no_signal(reduced)
	motion_full.set_pressed_no_signal(not reduced)
	var toon := MenuSettings.toon_style()
	style_toon.set_pressed_no_signal(toon)
	style_classic.set_pressed_no_signal(not toon)
	var lines := MenuSettings.outlines()
	outlines_on.set_pressed_no_signal(lines)
	outlines_off.set_pressed_no_signal(not lines)
	# outlines belong to the cartoon style
	outlines_on.disabled = not toon
	outlines_off.disabled = not toon
	cam_rotate.set_value_no_signal(roundf(float(MenuSettings.camera_value("rotate_sensitivity")) * 100.0))
	cam_zoom.set_value_no_signal(roundf(float(MenuSettings.camera_value("zoom_sensitivity")) * 100.0))
	invert_rotate.set_pressed_no_signal(bool(MenuSettings.camera_value("invert_rotate")))
	invert_tilt.set_pressed_no_signal(bool(MenuSettings.camera_value("invert_tilt")))
	invert_zoom.set_pressed_no_signal(bool(MenuSettings.camera_value("invert_zoom")))
	var right := String(MenuSettings.camera_value("orbit_button")) == "right"
	orbit_right.set_pressed_no_signal(right)
	orbit_middle.set_pressed_no_signal(not right)
	var edge := bool(MenuSettings.camera_value("edge_scroll"))
	edge_on.set_pressed_no_signal(edge)
	edge_off.set_pressed_no_signal(not edge)
	var aa := MenuSettings.antialiasing()
	aa_smaa.set_pressed_no_signal(aa == "smaa")
	aa_msaa4.set_pressed_no_signal(aa == "msaa4")
	aa_off.set_pressed_no_signal(aa == "off")
	var weather := MenuSettings.weather()
	weather_on.set_pressed_no_signal(weather)
	weather_off.set_pressed_no_signal(not weather)
	var talk := ChatterBook.enabled()
	bubbles_on.set_pressed_no_signal(talk)
	bubbles_off.set_pressed_no_signal(not talk)
	for r: String in rate_buttons:
		var b := rate_buttons[r] as Button
		b.set_pressed_no_signal(ChatterBook.rate() == r)
		b.disabled = not talk
	var q := GraphicsQuality.current()
	for l: int in quality_buttons:
		(quality_buttons[l] as Button).set_pressed_no_signal(l == q)
	# the "Baixo" level turns the anti-aliasing off whatever the choice
	for b: Button in [aa_smaa, aa_msaa4, aa_off]:
		b.disabled = GraphicsQuality.max_aa() != ""
	var ui := CwAccess.ui_scale()
	for i in text_buttons.size():
		text_buttons[i].set_pressed_no_signal(is_equal_approx(CwAccess.UI_SCALES[i], ui))
	var cb := CwAccess.colorblind()
	colorblind_on.set_pressed_no_signal(cb)
	colorblind_off.set_pressed_no_signal(not cb)
	_fill_keys()
	_show_volume()
	_show_camera()


## The key list: one row per CwKeys action (copies of the hidden KeyTemplate).
func _fill_keys() -> void:
	var ids := CwKeys.ids()
	var rows := _key_rows(ids.size())
	for i in ids.size():
		var id: StringName = ids[i]
		var row := rows[i]
		row.set_meta("action", id)
		(row.get_node("Name") as Label).text = tr(CwKeys.label_key(id))
		var b := row.get_node("Key") as Button
		b.text = tr("MENU_OPT_KEYS_PRESS") if listening == id else CwKeys.key_text(id)
		b.set_pressed_no_signal(listening == id)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.toggle_mode = true
			b.pressed.connect(func() -> void: listen(StringName(row.get_meta("action"))))
	keys_hint.text = tr("MENU_OPT_KEYS_LISTEN") if listening != &"" else tr("MENU_OPT_KEYS_HINT")


## `count` copies of the hidden KeyTemplate (made once, kept after).
func _key_rows(count: int) -> Array[Control]:
	var out: Array[Control] = []
	for c in key_template.get_parent().get_children():
		if c != key_template:
			out.append(c)
	while out.size() < count:
		var c := key_template.duplicate() as Control
		c.visible = true
		key_template.get_parent().add_child(c)
		out.append(c)
	return out


## Waits for the next key for action `id` (the same action again stops waiting).
func listen(id: StringName) -> void:
	listening = &"" if listening == id else id
	_fill_keys()


func _input(event: InputEvent) -> void:
	if listening == &"" or not is_visible_in_tree():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	var code := int(k.keycode if k.keycode != KEY_NONE else k.physical_keycode)
	if code == KEY_ESCAPE:
		listening = &""
	elif CwKeys.can_bind(code):
		CwKeys.rebind(listening, code)
		listening = &""
	_fill_keys()


func focus_first() -> void:
	(lang_pt if lang_pt.button_pressed else lang_en).grab_focus()


func _show_volume() -> void:
	volume_value.text = "%3d %%" % int(volume.value)
	music_value.text = "%3d %%" % int(music_volume.value)
	sfx_value.text = "%3d %%" % int(sfx_volume.value)


## Shows one page of the options grid: "" the general rows, "camera" the camera rows,
## "access" the accessibility rows (text size, colour-blind, keys).
func show_page(page: String) -> void:
	if not rows.is_empty():
		for c in grid.get_children():
			(c as CanvasItem).visible = rows.has(String(c.name))
		page_general.get_parent().visible = false
		return
	for c in grid.get_children():
		(c as CanvasItem).visible = String(c.get_meta("page", "")) == page
	page_camera.set_pressed_no_signal(page == "camera")
	page_access.set_pressed_no_signal(page == "access")
	page_general.set_pressed_no_signal(page == "")


func _show_camera() -> void:
	cam_rotate_value.text = "%3d %%" % int(cam_rotate.value)
	cam_zoom_value.text = "%3d %%" % int(cam_zoom.value)


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
