class_name MenuUnlocks
extends RefCounted
## The menus a new career unlocks while it plays (data/tycoon/menu_unlocks.json): a new career
## starts with the essentials (the campus, the clock, the mission board, the pause menu) and
## each HUD menu appears when it becomes relevant (the first project, the first launch, money
## trouble, research points, a race milestone, era 2...), with a little pop and one of Vovô's
## lessons (HudUnlocker, src/tycoon/tutorial/hud_unlocker.gd), so the player learns one system
## at a time.
##   - items: {"id", "nodes", "screen", "name_key", "lesson", "start", "when", "fair_week", "lot"}
##     nodes     the HUD nodes the item shows: "%Name" (a unique name in tycoon_hud.tscn),
##               "Crew" (a rail button, a child of %VBox) or "Side/Race" (a path from the HUD
##               root). A node that does not exist (yet) is skipped, so the table may name
##               buttons other features add later.
##     screen    the HUD screen it opens: opening that screen by any way (a project flow, the
##               dev menu) unlocks the item too
##     lesson    the lesson Vovô tells when it appears (tutorials.json, trigger "unlock")
##     start     open from the first week
##     when      conditions, any one unlocks the item; the keys of one condition must all hold:
##                 projects n       mission projects started (under way or done)
##                 launches n       missions flown (the project history)
##                 research_points n   points in the research pool
##                 cash_below n     money under n
##                 reputation n     reputation at least n
##                 era n / weeks n  the era / the career week
##                 building lot     that lot has a building
##                 milestones n     race milestones taken by anyone
##                 contracts n      contracts signed
##                 item id          another item is open (keeps an order)
##                 lesson id        a lesson was heard
##                 screen name      that screen was opened once
##     fair_week modo feira: the week at which it unlocks anyway (see fair mode below)
##     lot       a lot whose panel opens when it appears (the hangar key is in the workshop's)
##   To add a menu: put its button in the HUD scene (a rail button named after its screen is
##   wired by TycoonHUD on its own) and add an item here with its node name and conditions.
##   A button nobody lists here is always visible.
## Progress per career: TycoonState.tutorials["menus"] = {"open": {id: true}, "shown": {id: true},
## "screens": {name: true}}, saved with the campaign. A campaign without it (saves from before
## this, the demonstration saves, "Já sei jogar") has every menu open.
## Fair mode (modo feira, 1 s a week) uses a fast version: the same order and lessons, and every
## item also unlocks at its fair_week, so a booth visitor sees the whole HUD in about twenty
## weeks (seconds) of play even without flying a mission.
## Global switch for new careers: user://settings.cfg [tycoon] menus_gradual (the settings' Game
## tab); test scripts get every menu open unless HudUnlocker.allow_in_scripts is set.

const PATH := "res://data/tycoon/menu_unlocks.json"
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "tycoon"
const SETTINGS_KEY := "menus_gradual"
const KEY := "menus"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(PATH)
	return _data


static func items() -> Array:
	return data().get("items", [])


static func ids() -> Array[String]:
	var out: Array[String] = []
	for it: Dictionary in items():
		out.append(String(it.get("id", "")))
	return out


static func item(id: String) -> Dictionary:
	for it: Dictionary in items():
		if String(it.get("id", "")) == id:
			return it
	return {}


## The item whose screen is `screen_name` ({} when none).
static func item_for_screen(screen_name: String) -> Dictionary:
	for it: Dictionary in items():
		if screen_name != "" and String(it.get("screen", "")) == screen_name:
			return it
	return {}


## The item that shows HUD node `node_ref` (as written in the table, e.g. "%SolarMap").
static func item_for_node(node_ref: String) -> Dictionary:
	for it: Dictionary in items():
		for n in it.get("nodes", []):
			if String(n) == node_ref or String(n).trim_prefix("%") == node_ref:
				return it
	return {}


# ------------------------------------------------------------ the global switch
static func enabled_for_new() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, true))


static func set_enabled_for_new(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, on)
	cfg.save(SETTINGS_PATH)


# ------------------------------------------------------------ progress (per career)
static func _menus(state: TycoonState) -> Dictionary:
	if state == null or not state.tutorials.get(KEY) is Dictionary:
		return {}
	return state.tutorials[KEY]


## True while this career still unlocks menus as it plays.
static func gradual(state: TycoonState) -> bool:
	return state != null and state.tutorials.get(KEY) is Dictionary


## A new career starts with only the start items open.
static func begin(state: TycoonState) -> void:
	if state == null:
		return
	var m := {"open": {}, "shown": {}, "screens": {}}
	for it: Dictionary in items():
		if bool(it.get("start", false)):
			m["open"][String(it["id"])] = true
			m["shown"][String(it["id"])] = true
	state.tutorials[KEY] = m


## "Já sei jogar": every menu open now in this career.
static func unlock_all(state: TycoonState) -> void:
	if state:
		state.tutorials.erase(KEY)


static func is_open(state: TycoonState, id: String) -> bool:
	if not gradual(state):
		return true
	return bool((_menus(state).get("open", {}) as Dictionary).get(id, false))


## Open and already revealed on the HUD (its pop and lesson played).
static func is_shown(state: TycoonState, id: String) -> bool:
	if not gradual(state):
		return true
	return is_open(state, id) and bool((_menus(state).get("shown", {}) as Dictionary).get(id, false))


static func open_count(state: TycoonState) -> int:
	var n := 0
	for id in ids():
		if is_open(state, id):
			n += 1
	return n


## Opens item `id` (not yet revealed). True when it was closed.
static func open(state: TycoonState, id: String) -> bool:
	if not gradual(state) or is_open(state, id) or item(id).is_empty():
		return false
	var m := _menus(state)
	if not m.get("open") is Dictionary:
		m["open"] = {}
	m["open"][id] = true
	return true


static func mark_shown(state: TycoonState, id: String) -> void:
	if not gradual(state):
		return
	var m := _menus(state)
	if not m.get("shown") is Dictionary:
		m["shown"] = {}
	m["shown"][id] = true


## Open items not revealed yet, in table order.
static func pending(state: TycoonState) -> Array[String]:
	var out: Array[String] = []
	if not gradual(state):
		return out
	for id in ids():
		if is_open(state, id) and not is_shown(state, id):
			out.append(id)
	return out


## Remembers that `screen_name` was opened; opens its item. Returns the item opened ("" if none).
static func note_screen(state: TycoonState, screen_name: String) -> String:
	if not gradual(state) or screen_name == "":
		return ""
	var m := _menus(state)
	if not m.get("screens") is Dictionary:
		m["screens"] = {}
	m["screens"][screen_name] = true
	var it := item_for_screen(screen_name)
	if not it.is_empty() and open(state, String(it["id"])):
		return String(it["id"])
	return ""


## Opens every item whose conditions now hold (fair mode: also every item past its fair_week).
## Returns the ids opened, in table order.
static func check(state: TycoonState, fair := false) -> Array[String]:
	var out: Array[String] = []
	if not gradual(state):
		return out
	for it: Dictionary in items():
		var id := String(it.get("id", ""))
		if is_open(state, id):
			continue
		var go := bool(it.get("start", false))
		if fair and it.has("fair_week") and state.weeks >= int(it["fair_week"]):
			go = true
		for c in it.get("when", []):
			if not go and c is Dictionary and met(state, c):
				go = true
		if go and open(state, id):
			out.append(id)
	return out


## True when every key of condition `c` holds for this career.
static func met(state: TycoonState, c: Dictionary) -> bool:
	for k: String in c:
		var v: Variant = c[k]
		var ok := true
		match k:
			"projects":
				ok = state.mission_projects.size() + state.project_history.size() >= int(v)
			"launches":
				ok = state.project_history.size() >= int(v)
			"research_points":
				ok = state.research_points >= float(v)
			"cash_below":
				ok = state.cash < float(v)
			"reputation":
				ok = state.reputation >= float(v)
			"era":
				ok = state.era() >= int(v)
			"weeks":
				ok = state.weeks >= int(v)
			"building":
				ok = int(state.building(String(v)).get("level", 0)) > 0
			"milestones":
				ok = _milestones_taken(state) >= int(v)
			"contracts":
				ok = state.contracts.size() >= int(v)
			"item":
				ok = is_open(state, String(v))
			"lesson":
				ok = TutorialBook.seen(state, String(v))
			"screen":
				ok = bool((_menus(state).get("screens", {}) as Dictionary).get(String(v), false))
			_:
				ok = false   # an unknown key never holds (a typo should not open everything)
		if not ok:
			return false
	return true


static func _milestones_taken(state: TycoonState) -> int:
	var n := state.milestones
	for r: Dictionary in state.rivals:
		n += int(r.get("milestones", 0))
	return n
