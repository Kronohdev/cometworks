class_name MenuOptionsPanel
extends PanelContainer
## Options of the main menu (scenes/menu/options_panel.tscn): language EN / PT, window or
## fullscreen, master volume. Layout and styles live in the scene; this script reads and
## writes MenuSettings and emits `closed` on Back / Esc.

signal closed

@onready var lang_en: Button = %LangEN
@onready var lang_pt: Button = %LangPT
@onready var win: Button = %Windowed
@onready var full: Button = %Fullscreen
@onready var volume: HSlider = %Volume
@onready var volume_value: Label = %VolumeValue
@onready var back: Button = %Back


func _ready() -> void:
	lang_en.pressed.connect(MenuSettings.set_locale.bind("en"))
	lang_pt.pressed.connect(MenuSettings.set_locale.bind("pt"))
	win.pressed.connect(MenuSettings.set_fullscreen.bind(false))
	full.pressed.connect(MenuSettings.set_fullscreen.bind(true))
	volume.value_changed.connect(func(v: float) -> void:
		MenuSettings.set_volume(v / 100.0)
		_show_volume())
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
	_show_volume()


func focus_first() -> void:
	(lang_pt if lang_pt.button_pressed else lang_en).grab_focus()


func _show_volume() -> void:
	volume_value.text = "%3d %%" % int(volume.value)


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
