class_name RoverGarage
extends RefCounted
## The career's rover garage, saved in TycoonState.rovers:
##   {"designs": [RoverDesign dicts, newest last],
##    "drives": {mission id: SurfaceSession result of the player's drives on that mission}}
## Static functions; a state null is the dev sandbox's garage (kept in memory only).

const MAX_DESIGNS := 24

static var _sandbox: Dictionary = {}


static func store(state: TycoonState) -> Dictionary:
	var st: Dictionary = state.rovers if state else _sandbox
	if not st.get("designs") is Array:
		st["designs"] = []
	if not st.get("drives") is Dictionary:
		st["drives"] = {}
	return st


static func designs(state: TycoonState) -> Array:
	return store(state)["designs"]


static func find(state: TycoonState, design_name: String) -> Dictionary:
	for d: Dictionary in designs(state):
		if String(d.get("name", "")) == design_name:
			return d
	return {}


## Saves a design under its name (same name: replaced). Returns the saved copy ({} if it has no name).
static func save_design(state: TycoonState, d: Dictionary) -> Dictionary:
	var n := RoverDesign.normalize(d)
	n["name"] = String(n["name"]).strip_edges()
	if String(n["name"]) == "":
		return {}
	var list := designs(state)
	for i in list.size():
		if String(list[i].get("name", "")) == n["name"]:
			list[i] = n
			return n
	list.append(n)
	while list.size() > MAX_DESIGNS:
		list.pop_front()
	return n


static func delete(state: TycoonState, design_name: String) -> bool:
	var list := designs(state)
	for i in list.size():
		if String(list[i].get("name", "")) == design_name:
			list.remove_at(i)
			return true
	return false


## A name no saved design has yet: "Tatu", "Tatu 2", ...
static func free_name(state: TycoonState, base: String) -> String:
	if find(state, base).is_empty():
		return base
	var i := 2
	while not find(state, "%s %d" % [base, i]).is_empty():
		i += 1
	return "%s %d" % [base, i]


static func drives(state: TycoonState) -> Dictionary:
	return store(state)["drives"]


static func drive_of(state: TycoonState, mission_id: String) -> Dictionary:
	return drives(state).get(mission_id, {})
