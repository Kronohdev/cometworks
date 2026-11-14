class_name RocketFamilies
extends RefCounted
## The agency's rocket families (GDD 8.2): saved designs reused flight after flight, like the
## game engines of Game Dev Tycoon. A family is a design (parts) with a name and its flight
## heritage: every successful flight raises its trust (rockets.json heritage.step, up to max),
## a failure lowers it (fail_drop, down to min). The family's reliability is the design's
## hardware reliability x trust; repeat units also get cheaper (RocketDesigner.unit_cost).
## Lives in TycoonState.rockets: {"families": [{"id", "name", "parts", "flights", "successes",
## "failures", "trust", "created_week", "last_week"}], "next": n}. Pure rules, headless.


static func _db(state: TycoonState) -> Dictionary:
	if not state.rockets.has("families"):
		state.rockets["families"] = []
		state.rockets["next"] = 1
	return state.rockets


static func families(state: TycoonState) -> Array:
	return _db(state)["families"]


static func find(state: TycoonState, id: String) -> Dictionary:
	for f: Dictionary in families(state):
		if String(f["id"]) == id:
			return f
	return {}


## The family with exactly these parts, {} if none.
static func find_parts(state: TycoonState, parts: Dictionary) -> Dictionary:
	for f: Dictionary in families(state):
		if RocketDesigner.same_parts(f.get("parts", {}), parts):
			return f
	return {}


static func heritage() -> Dictionary:
	return RocketDesigner.section("heritage")


## The trust a new family of these parts starts with: debut, or debut_known_core when a family
## with the same main stage has flown well.
static func debut_trust(state: TycoonState, parts: Dictionary) -> float:
	var h := heritage()
	var known := find_parts(state, parts)
	if not known.is_empty():
		return trust(known)
	var core := String(RocketDesigner.normalize(parts)["core"])
	for f: Dictionary in families(state):
		if String(RocketDesigner.normalize(f.get("parts", {}))["core"]) == core and int(f.get("successes", 0)) > 0:
			return float(h.get("debut_known_core", h.get("debut", 0.9)))
	return float(h.get("debut", 0.9))


static func trust(fam: Dictionary) -> float:
	return float(fam.get("trust", heritage().get("debut", 0.9)))


static func flights(fam: Dictionary) -> int:
	return int(fam.get("flights", 0))


## Hardware reliability x trust: the chance the rocket does its part (before the review).
static func reliability(state: TycoonState, parts: Dictionary) -> float:
	return float(RocketDesigner.stats(parts)["rel"]) * debut_trust(state, parts)


## A name for a new family: the next bird of rockets.json family_names, with a number once the
## list has been used.
static func next_name(state: TycoonState) -> String:
	var names: Array = RocketDesigner.data().get("family_names", ["Cometa"])
	var used := {}
	for f: Dictionary in families(state):
		used[String(f.get("name", ""))] = true
	var round_n := 1
	while round_n < 20:
		for n in names:
			var cand := String(n) if round_n == 1 else "%s %d" % [String(n), round_n]
			if not used.has(cand):
				return cand
		round_n += 1
	return "Cometa %d" % int(_db(state)["next"])


## A family for these parts: the existing one, else a new one (named `name_hint` or the next
## free name). Returns the family.
static func ensure(state: TycoonState, parts: Dictionary, name_hint := "") -> Dictionary:
	var known := find_parts(state, parts)
	if not known.is_empty():
		if name_hint.strip_edges() != "" and name_hint.strip_edges() != String(known["name"]):
			known["name"] = name_hint.strip_edges()
		return known
	var db := _db(state)
	var n := int(db.get("next", 1))
	db["next"] = n + 1
	var fam := {"id": "fam%d" % n, "name": name_hint.strip_edges() if name_hint.strip_edges() != "" else next_name(state),
		"parts": RocketDesigner.normalize(parts), "flights": 0, "successes": 0, "failures": 0,
		"trust": debut_trust(state, parts), "created_week": state.weeks, "last_week": -1}
	(db["families"] as Array).append(fam)
	return fam


static func rename(state: TycoonState, id: String, new_name: String) -> void:
	var f := find(state, id)
	if not f.is_empty() and new_name.strip_edges() != "":
		f["name"] = new_name.strip_edges()
		state.changed.emit()


## A flight of the family: heritage up after a success, trust down after a failure.
static func record_flight(state: TycoonState, id: String, success: bool) -> void:
	var f := find(state, id)
	if f.is_empty():
		return
	var h := heritage()
	f["flights"] = flights(f) + 1
	f["last_week"] = state.weeks
	if success:
		f["successes"] = int(f.get("successes", 0)) + 1
		f["trust"] = minf(trust(f) + float(h.get("step", 0.02)), float(h.get("max", 1.0)))
	else:
		f["failures"] = int(f.get("failures", 0)) + 1
		f["trust"] = maxf(trust(f) - float(h.get("fail_drop", 0.06)), float(h.get("min", 0.7)))


## Families that reach this mission, the most reliable first.
static func fitting(state: TycoonState, type_id: String, target_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in families(state):
		if RocketDesigner.check(state, f.get("parts", {}), type_id, target_id)["reaches"]:
			out.append(f)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return reliability(state, a["parts"]) > reliability(state, b["parts"]))
	return out


## The family a new project takes by default: the most reliable one that has flown and reaches
## the mission ({} if none).
static func best_fitting(state: TycoonState, type_id: String, target_id: String) -> Dictionary:
	for f in fitting(state, type_id, target_id):
		if flights(f) > 0 and int(f.get("successes", 0)) > 0:
			return f
	return {}


## Changes whenever a family's heritage does (a cache key for the designer's proposals).
static func heritage_stamp(state: TycoonState) -> int:
	var n := 0
	for f: Dictionary in families(state):
		n += 1 + flights(f) * 7 + int(f.get("successes", 0)) * 13
	return n


## from_dict() hook: JSON numbers come back as floats.
static func restore(state: TycoonState, d: Dictionary) -> void:
	state.rockets = d.duplicate(true)
	if d.is_empty():
		return
	var db := _db(state)
	db["next"] = int(db.get("next", 1))
	for f: Dictionary in db["families"]:
		for k in ["flights", "successes", "failures", "created_week", "last_week"]:
			f[k] = int(f.get(k, 0))
		f["trust"] = float(f.get("trust", heritage().get("debut", 0.9)))
