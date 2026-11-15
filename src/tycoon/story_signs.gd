class_name StorySigns
extends RefCounted
## The story signs ("placas") around the campus island: little wooden signs that tell the
## Cometlings' lore, real space history (with the fact and its source) and campus jokes.
## The signs are data (data/tycoon/story_signs.json: id, kind, icon, unlock, text keys in
## i18n/story_sign_strings.csv); where they stand is the editor scene
## scenes/tycoon/campus_signs.tscn (one CampusSign per id). Some start covered and uncover
## with time: an era, a year, a race milestone the player took, a number of launches or a
## building on the campus. The signs the player has read are kept in the save
## (TycoonState.signs = {"read": {id: true}}; old saves simply have none read).

const DATA := "res://data/tycoon/story_signs.json"
const KINDS := ["lore", "history", "joke"]
const UNLOCK_KEYS := ["era", "year", "milestone", "launches", "building"]

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(DATA)
		_by_id.clear()
		for s: Dictionary in _data.get("signs", []):
			_by_id[String(s.get("id", ""))] = s
	return _data


static func all() -> Array:
	return data().get("signs", [])


static func ids() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in all():
		out.append(String(s.get("id", "")))
	return out


## The sign's data ({} when there is no such sign).
static func find(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func total() -> int:
	return all().size()


## True when every condition of the sign's `unlock` holds for this campaign.
static func is_unlocked(state: TycoonState, id: String) -> bool:
	var s := find(id)
	if s.is_empty() or state == null:
		return false
	var u: Dictionary = s.get("unlock", {})
	if u.has("era") and state.era() < int(u["era"]):
		return false
	if u.has("year") and state.year() < int(u["year"]):
		return false
	if u.has("milestone") and (state.race == null or not state.race.has_claimed(String(u["milestone"]), RaceDirector.PLAYER)):
		return false
	if u.has("launches") and state.project_history.size() < int(u["launches"]):
		return false
	if u.has("building") and int(state.building(String(u["building"])).get("level", 0)) <= 0:
		return false
	return true


## What uncovers a covered sign, in the player's language ("Opens in era 3"); "" when open.
static func lock_text(state: TycoonState, id: String) -> String:
	var u: Dictionary = find(id).get("unlock", {})
	var parts: Array[String] = []
	if u.has("era") and (state == null or state.era() < int(u["era"])):
		parts.append(TranslationServer.translate("SIGN_LOCK_ERA") % int(u["era"]))
	if u.has("year") and (state == null or state.year() < int(u["year"])):
		parts.append(TranslationServer.translate("SIGN_LOCK_YEAR") % int(u["year"]))
	if u.has("milestone") and not is_unlocked(state, id):
		var mid := String(u["milestone"])
		var key := ""
		if state and state.race:
			key = String(state.race.milestone(mid).get("name_key", ""))
		parts.append(TranslationServer.translate("SIGN_LOCK_MILESTONE") % (TranslationServer.translate(key) if key != "" else mid))
	if u.has("launches") and (state == null or state.project_history.size() < int(u["launches"])):
		var n := int(u["launches"])
		parts.append(TranslationServer.translate("SIGN_LOCK_LAUNCH_ONE") if n == 1
			else TranslationServer.translate("SIGN_LOCK_LAUNCHES") % n)
	if u.has("building") and (state == null or int(state.building(String(u["building"])).get("level", 0)) <= 0):
		var lot := String(u["building"])
		var name_key := ""
		if state:
			name_key = String(state.building_type(state.lot_kind(lot)).get("name_key", ""))
		parts.append(TranslationServer.translate("SIGN_LOCK_BUILDING") % (TranslationServer.translate(name_key) if name_key != "" else lot))
	return " · ".join(parts)


static func is_read(state: TycoonState, id: String) -> bool:
	return state != null and bool((state.signs.get("read", {}) as Dictionary).get(id, false))


## Marks an uncovered sign as read. True when it was not read before.
static func mark_read(state: TycoonState, id: String) -> bool:
	if state == null or find(id).is_empty() or not is_unlocked(state, id) or is_read(state, id):
		return false
	if not state.signs.has("read"):
		state.signs["read"] = {}
	(state.signs["read"] as Dictionary)[id] = true
	return true


## How many signs the player has read (ids that still exist).
static func read_count(state: TycoonState) -> int:
	var n := 0
	for id in ids():
		if is_read(state, id):
			n += 1
	return n


static func unlocked_count(state: TycoonState) -> int:
	var n := 0
	for id in ids():
		if is_unlocked(state, id):
			n += 1
	return n


## Ids of the uncovered signs nobody has read yet.
static func unread(state: TycoonState) -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		if is_unlocked(state, id) and not is_read(state, id):
			out.append(id)
	return out
