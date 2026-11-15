class_name CwKeys
extends RefCounted
## The campaign's main keys as InputMap actions the player can rebind (the options panel's
## Accessibility page lists them, MenuOptionsPanel). Each action has one rebindable key (the
## first event; saved in user://settings.cfg under [keys] as a keycode) and fixed extras that
## always work (the arrow keys, the keypad). Esc is never rebindable (it always steps back).
## The actions are registered in code (ensure()), so scenes that start on their own (tests,
## the dev menu's direct campaign) have them too. TycoonMain (pause, speeds, map) and
## CampusCamera (pan, turn, zoom, frame, home) read them.

const PATH := "user://settings.cfg"
const SECTION := "keys"
## [action, default key, fixed extra keys, label key] in the order the list shows them
const ACTIONS := [
	[&"cw_pause", KEY_SPACE, [], "KEYS_PAUSE"],
	[&"cw_speed_1", KEY_1, [], "KEYS_SPEED_1"],
	[&"cw_speed_2", KEY_2, [], "KEYS_SPEED_2"],
	[&"cw_speed_3", KEY_3, [], "KEYS_SPEED_3"],
	[&"cw_map", KEY_M, [], "KEYS_MAP"],
	[&"cw_cam_frame", KEY_F, [], "KEYS_CAM_FRAME"],
	[&"cw_cam_home", KEY_HOME, [], "KEYS_CAM_HOME"],
	[&"cw_cam_forward", KEY_W, [KEY_UP], "KEYS_CAM_FORWARD"],
	[&"cw_cam_back", KEY_S, [KEY_DOWN], "KEYS_CAM_BACK"],
	[&"cw_cam_left", KEY_A, [KEY_LEFT], "KEYS_CAM_LEFT"],
	[&"cw_cam_right", KEY_D, [KEY_RIGHT], "KEYS_CAM_RIGHT"],
	[&"cw_cam_turn_left", KEY_Q, [], "KEYS_CAM_TURN_LEFT"],
	[&"cw_cam_turn_right", KEY_E, [], "KEYS_CAM_TURN_RIGHT"],
	[&"cw_cam_zoom_in", KEY_EQUAL, [KEY_KP_ADD], "KEYS_CAM_ZOOM_IN"],
	[&"cw_cam_zoom_out", KEY_MINUS, [KEY_KP_SUBTRACT], "KEYS_CAM_ZOOM_OUT"],
]
## keys that can never be bound (they belong to the whole game)
const RESERVED: Array[int] = [KEY_ESCAPE, KEY_F1, KEY_F12]

static var _ensured := false


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for a: Array in ACTIONS:
		out.append(a[0])
	return out


static func _row(id: StringName) -> Array:
	for a: Array in ACTIONS:
		if a[0] == id:
			return a
	return []


static func label_key(id: StringName) -> String:
	var r := _row(id)
	return String(r[3]) if not r.is_empty() else String(id)


static func default_key(id: StringName) -> int:
	var r := _row(id)
	return int(r[1]) if not r.is_empty() else KEY_NONE


static func _key_event(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k as Key
	return e


## Registers the actions with their default keys (once; existing actions are left alone).
static func ensure() -> void:
	if _ensured and InputMap.has_action(ACTIONS[0][0]):
		return
	_ensured = true
	for a: Array in ACTIONS:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
			_set_events(a[0], int(a[1]))


static func _set_events(id: StringName, k: int) -> void:
	InputMap.action_erase_events(id)
	InputMap.action_add_event(id, _key_event(k))
	for extra: int in _row(id)[2]:
		InputMap.action_add_event(id, _key_event(extra))


## Registers the actions and puts the saved keys on them.
static func apply() -> void:
	ensure()
	var cfg := _cfg()
	for a: Array in ACTIONS:
		_set_events(a[0], int(cfg.get_value(SECTION, String(a[0]), a[1])))


## The rebindable key of an action now (its first event).
static func key_of(id: StringName) -> int:
	ensure()
	for e in InputMap.action_get_events(id):
		if e is InputEventKey:
			var k := e as InputEventKey
			return int(k.keycode if k.keycode != KEY_NONE else k.physical_keycode)
	return KEY_NONE


## The key's name as the keyboard shows it ("Space", "W", "Home").
static func key_text(id: StringName) -> String:
	var k := key_of(id)
	return OS.get_keycode_string(k as Key) if k != KEY_NONE else "—"


static func can_bind(k: int) -> bool:
	return k != KEY_NONE and k not in RESERVED and k not in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]


## Puts key `k` on `id` and saves it. An action that had `k` takes `id`'s old key (a swap),
## so no two actions share a key. Returns the action that was swapped (&"" for none).
static func rebind(id: StringName, k: int) -> StringName:
	if _row(id).is_empty() or not can_bind(k):
		return &""
	ensure()
	var old := key_of(id)
	var swapped: StringName = &""
	for other: StringName in ids():
		if other != id and key_of(other) == k:
			swapped = other
			_set_events(other, old)
	_set_events(id, k)
	_save()
	return swapped


## Every action back to its default key.
static func reset_defaults() -> void:
	ensure()
	for a: Array in ACTIONS:
		_set_events(a[0], int(a[1]))
	var cfg := _cfg()
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
	cfg.save(PATH)


static func _save() -> void:
	var cfg := _cfg()
	for id: StringName in ids():
		cfg.set_value(SECTION, String(id), key_of(id))
	cfg.save(PATH)


## True when `event` presses action `id` (registering the actions first).
static func pressed(event: InputEvent, id: StringName) -> bool:
	ensure()
	return event.is_action_pressed(id, false, false)


## True while action `id` is held.
static func held(id: StringName) -> bool:
	ensure()
	return Input.is_action_pressed(id)
