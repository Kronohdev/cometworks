class_name TutorialBook
extends RefCounted
## The lessons of Vovô Edmundo Halleyzinho (data/tycoon/tutorials.json) and where they are kept:
##   - lessons: {"id", "title", "desc", "icon", "trigger", "replay", "requires", "steps"}
##     trigger  when it starts the first time:
##              {"on": "campus"}                       the campus with nothing open
##              {"on": "screen", "screen": "crew"}     a HUD screen opens
##              {"on": "lot"}                          the lot panel opens
##              {"on": "signal", "signal": "era_changed", "min": 2}   a TycoonState signal
##                                                     (min: its first argument at least)
##     replay   the screen the library opens before replaying it ("" = the campus)
##     requires lesson ids the campaign must have seen first
##     steps    [{"line", "target", "advance", "place", "pose"}]
##              line     i18n key of what he says (two short lines at most)
##              target   UI node to light up: "hud:<path>" or "screen:<path>" (a NodePath from
##                       that scene's root, "%Name" for unique names); no scope = the screen
##                       for screen lessons, the HUD for the others
##              advance  {"on": "next"} (default) | {"on": "click"} (the target is pressed) |
##                       {"on": "screen", "screen": name} | {"on": "signal", "signal": name};
##                       "Próximo" always works too
##              place    where the bubble goes: "auto" (default, away from the target),
##                       "top", "bottom", "center"
##              pose     what he does on that line: a Cometling one-shot ("wave", "nod",
##                       "point", "bow", "laugh"...) or one of Halleyzinho.HABITS
##   - progress per campaign: TycoonState.tutorials {"seen": {id: true}} (saved with the game)
##   - the global switch: user://settings.cfg [tycoon] tutorials (the settings' Game tab; the
##     bubble's "Não mostrar mais" turns it off)

const PATH := "res://data/tycoon/tutorials.json"
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "tycoon"
const SETTINGS_KEY := "tutorials"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


static func lessons() -> Array:
	return data().get("lessons", [])


static func ids() -> Array[String]:
	var out: Array[String] = []
	for l: Dictionary in lessons():
		out.append(String(l.get("id", "")))
	return out


static func lesson(id: String) -> Dictionary:
	for l: Dictionary in lessons():
		if String(l.get("id", "")) == id:
			return l
	return {}


## The lessons that start when `on` happens (e.g. "screen" with key "crew").
static func triggered_by(on: String, key := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in lessons():
		var t: Dictionary = l.get("trigger", {})
		if String(t.get("on", "")) != on:
			continue
		if on == "screen" and String(t.get("screen", "")) != key:
			continue
		if on == "signal" and String(t.get("signal", "")) != key:
			continue
		out.append(l)
	return out


## Scope of a step's target ("hud" or "screen") and the path inside it.
static func target_of(l: Dictionary, step: Dictionary) -> Array:
	var t := String(step.get("target", ""))
	if t == "":
		return ["", ""]
	var scope := "screen" if String(l.get("trigger", {}).get("on", "")) == "screen" else "hud"
	var at := t.find(":")
	if at > 0:
		scope = t.substr(0, at)
		t = t.substr(at + 1)
	return [scope, t]


# ------------------------------------------------------------ the global switch
static func enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, true))


static func set_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, on)
	cfg.save(SETTINGS_PATH)


# ------------------------------------------------------------ progress (per campaign)
static func seen(state: TycoonState, id: String) -> bool:
	return state != null and bool(state.tutorials.get("seen", {}).get(id, false))


static func mark_seen(state: TycoonState, id: String) -> void:
	if state == null:
		return
	if not state.tutorials.get("seen") is Dictionary:
		state.tutorials["seen"] = {}
	state.tutorials["seen"][id] = true


static func seen_count(state: TycoonState) -> int:
	var n := 0
	for id in ids():
		if seen(state, id):
			n += 1
	return n


## Every lesson starts again in this campaign.
static func reset(state: TycoonState) -> void:
	if state:
		state.tutorials["seen"] = {}


## Can lesson `l` start in this campaign (not seen, its requirements seen)?
static func ready_for(state: TycoonState, l: Dictionary) -> bool:
	var id := String(l.get("id", ""))
	if id == "" or seen(state, id):
		return false
	for r in l.get("requires", []):
		if not seen(state, String(r)):
			return false
	return true
