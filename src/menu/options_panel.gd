class_name MenuOptionsPanel
extends PanelContainer
## Options of the main menu (scenes/menu/options_panel.tscn): language EN / PT, window or
## fullscreen, master, music and effects volume, the visual style (Cartoon / Classic, CwLook)
## and the ink outlines. Layout and styles live in the scene; this script reads and
## writes MenuSettings and emits `closed` on Back / Esc. Motion: full or reduced (the UI
## motion components, src/tycoon/ui/motion/, keep only short fades when reduced).

signal closed

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


func _ready() -> void:
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
	_show_volume()


func focus_first() -> void:
	(lang_pt if lang_pt.button_pressed else lang_en).grab_focus()


func _show_volume() -> void:
	volume_value.text = "%3d %%" % int(volume.value)
	music_value.text = "%3d %%" % int(music_volume.value)
	sfx_value.text = "%3d %%" % int(sfx_volume.value)


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
