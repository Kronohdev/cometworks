class_name MenuSettings
extends RefCounted
## Player options of the main menu (language, fullscreen, master volume), kept in
## user://settings.cfg under [menu] next to the graphics quality (src/core/graphics_quality.gd).
## apply() runs when the menu opens, so the choice sticks between sessions.

const PATH := "user://settings.cfg"
const SECTION := "menu"
const LOCALES := ["en", "pt"]


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func _store(key: String, value: Variant) -> void:
	var cfg := _cfg()
	cfg.set_value(SECTION, key, value)
	cfg.save(PATH)


## Applies the saved options (first run: the system language if it is Portuguese, else English).
static func apply() -> void:
	var cfg := _cfg()
	var sys := "pt" if OS.get_locale_language() == "pt" else "en"
	TranslationServer.set_locale(String(cfg.get_value(SECTION, "locale", sys)))
	if bool(cfg.get_value(SECTION, "fullscreen", false)) != is_fullscreen():
		_set_window_fullscreen(bool(cfg.get_value(SECTION, "fullscreen", false)))
	_set_bus_volume(float(cfg.get_value(SECTION, "volume", 0.8)))


static func locale() -> String:
	return "pt" if TranslationServer.get_locale().begins_with("pt") else "en"


static func set_locale(code: String) -> void:
	TranslationServer.set_locale(code)
	_store("locale", code)


static func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func set_fullscreen(on: bool) -> void:
	_set_window_fullscreen(on)
	_store("fullscreen", on)


static func volume() -> float:
	return float(_cfg().get_value(SECTION, "volume", 0.8))


## Master volume, 0..1 (linear; 0 mutes the bus).
static func set_volume(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	_set_bus_volume(v)
	_store("volume", v)


static func _set_window_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


static func _set_bus_volume(v: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(bus, v <= 0.001)
