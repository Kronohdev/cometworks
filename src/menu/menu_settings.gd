class_name MenuSettings
extends RefCounted
## Player options of the main menu (language, fullscreen, master / music / effects volume,
## visual style, outlines and anti-aliasing - the last three stored by CwLook under [graphics];
## the campus camera's sensitivity / invert / buttons / edge pan under [camera]),
## kept in user://settings.cfg under [menu] next to the graphics quality
## (src/core/graphics_quality.gd). apply() runs when the menu opens, so the choice sticks
## between sessions; the volumes are also applied by the sound player (CwSfx) on start.
## The accessibility options (colour-blind mode, key bindings) and the graphics
## quality live in CwAccess, CwKeys and GraphicsQuality, in the same file.
## Volumes scale the buses of default_bus_layout.tres: the levels authored there are the
## 100 % mix, the sliders only turn them down.

const PATH := "user://settings.cfg"
const SECTION := "menu"
const LOCALES := ["en", "pt"]
## bus -> settings key of the slider that scales it ("Effects" covers SFX, UI and ambience)
const BUS_KEYS := {"Master": "volume", "Music": "music_volume", "SFX": "sfx_volume", "UI": "sfx_volume",
	"Ambience": "sfx_volume"}
const VOLUME_DEFAULTS := {"volume": 0.8, "music_volume": 0.7, "sfx_volume": 0.9}
## campus camera options (CampusCamera.apply_settings), kept under [camera]: sensitivities are
## multipliers, orbit_button is the mouse button that turns the view ("middle" or "right", the
## other one pans), edge_scroll pans at the screen edges
const CAMERA_SECTION := "camera"
const CAMERA_DEFAULTS := {"rotate_sensitivity": 1.0, "zoom_sensitivity": 1.0, "invert_rotate": false,
	"invert_tilt": false, "invert_zoom": false, "orbit_button": "middle", "edge_scroll": false}

## bus name -> its authored volume (dB) in the bus layout, read once
static var _base_db := {}


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
	TranslationServer.set_locale(saved_locale())
	if bool(cfg.get_value(SECTION, "fullscreen", false)) != is_fullscreen():
		_set_window_fullscreen(bool(cfg.get_value(SECTION, "fullscreen", false)))
	apply_audio()
	CwLook.apply()
	CwAccess.apply()   # colour-blind colours, keys, graphics quality


## Applies the saved volumes to the audio buses.
static func apply_audio() -> void:
	var cfg := _cfg()
	for bus: String in BUS_KEYS:
		var key: String = BUS_KEYS[bus]
		_set_bus(bus, float(cfg.get_value(SECTION, key, VOLUME_DEFAULTS[key])))


## The language chosen in the options ("pt" / "en"); first run: the system language if it is
## Portuguese, else English. The hangar and the flight opened on their own use it too.
static func saved_locale() -> String:
	var sys := "pt" if OS.get_locale_language() == "pt" else "en"
	return String(_cfg().get_value(SECTION, "locale", sys))


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
	return _volume("volume")


## Master volume, 0..1 (linear; 0 mutes the bus).
static func set_volume(v: float) -> void:
	_set_volume("volume", v)


static func music_volume() -> float:
	return _volume("music_volume")


## Music volume, 0..1 (the Music bus).
static func set_music_volume(v: float) -> void:
	_set_volume("music_volume", v)


static func sfx_volume() -> float:
	return _volume("sfx_volume")


## Effects volume, 0..1 (the SFX, UI and Ambience buses).
static func set_sfx_volume(v: float) -> void:
	_set_volume("sfx_volume", v)


static func _volume(key: String) -> float:
	return float(_cfg().get_value(SECTION, key, VOLUME_DEFAULTS[key]))


static func _set_volume(key: String, v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	for bus: String in BUS_KEYS:
		if BUS_KEYS[bus] == key:
			_set_bus(bus, v)
	_store(key, v)


## Reduce motion: the UI motion components (src/tycoon/ui/motion/) skip slides, scales,
## wiggles and idle loops and keep only short fades.
static func reduce_motion() -> bool:
	return bool(_cfg().get_value(SECTION, "reduce_motion", false))


static func set_reduce_motion(on: bool) -> void:
	_store("reduce_motion", on)
	CwMotion.set_reduced(on)


## Campus weather (rain, clouds, gusts; CampusWeather, src/tycoon/fx/campus_weather.gd): purely
## visual, on by default. Applied live to the weather in the game right now.
static func weather() -> bool:
	return bool(_cfg().get_value(SECTION, "weather", true))


static func set_weather(on: bool) -> void:
	_store("weather", on)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.call_group(&"cw_weather", "load_settings")


## Visual style: true = Cartoon (toon light and ink outlines), false = Classic. Applied live to
## every material and outline (CwLook, src/core/cw_look.gd).
static func toon_style() -> bool:
	return CwLook.toon()


static func set_toon_style(on: bool) -> void:
	CwLook.set_toon(on)


## Ink outlines of the cartoon style on or off (applied live).
static func outlines() -> bool:
	return CwLook.outlines()


static func set_outlines(on: bool) -> void:
	CwLook.set_outlines(on)


## A campus camera option (CAMERA_DEFAULTS when never saved).
static func camera_value(key: String) -> Variant:
	return _cfg().get_value(CAMERA_SECTION, key, CAMERA_DEFAULTS.get(key))


## Saves a campus camera option and applies it to the cameras in the game right now.
static func set_camera_value(key: String, value: Variant) -> void:
	var cfg := _cfg()
	cfg.set_value(CAMERA_SECTION, key, value)
	cfg.save(PATH)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.call_group(CampusCamera.GROUP, "load_settings")


## Anti-aliasing of the 3D view: "smaa", "msaa4" or "off" (applied live, CwLook).
static func antialiasing() -> String:
	return CwLook.antialiasing()


static func set_antialiasing(mode: String) -> void:
	CwLook.set_antialiasing(mode)


static func _set_window_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


## Scales a bus to v (0..1) of its authored level; 0 mutes it. Missing buses are skipped.
static func _set_bus(bus_name: String, v: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	if not _base_db.has(bus_name):
		_base_db[bus_name] = AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_volume_db(bus, float(_base_db[bus_name]) + linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(bus, v <= 0.001)
