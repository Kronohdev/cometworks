class_name SurfaceLog
extends RefCounted
## The discovery log of the free play on the surfaces ("Diário de campo"), per body: places
## found and the rover actions done there, finds picked up, challenges done (with the best
## time) and photos taken. In a career it lives in the career save, inside the discovery
## journal (TycoonState.discovery["surfaces"], saved with it); outside a career (the main
## menu's free play) in user://surface_log.json. Science is credited once per thing logged.
##   {"bodies": {body: {"found": {poi: week}, "actions": {poi: [action]}, "collected": {id: true},
##     "challenges": {id: {"done": true, "best": seconds, "tries": n}}, "photos": n, "visits": n}},
##    "all": false (dev: every body open)}

## the free-play file (tests point it elsewhere)
static var free_path := "user://surface_log.json"

## the career, or null (free play from the menu)
var state: TycoonState
var data: Dictionary = {}


static func open(p_state: TycoonState = null) -> SurfaceLog:
	var l := SurfaceLog.new()
	l.state = p_state
	if p_state:
		var j := p_state.discovery
		if not (j.get("surfaces", null) is Dictionary):
			j["surfaces"] = {}
		l.data = j["surfaces"]
	elif FileAccess.file_exists(free_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(free_path))
		l.data = parsed if parsed is Dictionary else {}
	if not (l.data.get("bodies", null) is Dictionary):
		l.data["bodies"] = {}
	return l


## Writes the free-play file (a career is saved with the career).
func save() -> void:
	if state != null:
		return
	var f := FileAccess.open(free_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func body(id: String) -> Dictionary:
	var bodies: Dictionary = data["bodies"]
	if not (bodies.get(id, null) is Dictionary):
		bodies[id] = {}
	var b: Dictionary = bodies[id]
	for k in ["found", "actions", "collected", "challenges"]:
		if not (b.get(k, null) is Dictionary):
			b[k] = {}
	for k in ["photos", "visits"]:
		b[k] = int(b.get(k, 0))
	return b


func is_found(body_id: String, poi: String) -> bool:
	return (body(body_id)["found"] as Dictionary).has(poi)


## True the first time.
func mark_found(body_id: String, poi: String) -> bool:
	var f: Dictionary = body(body_id)["found"]
	if f.has(poi):
		return false
	f[poi] = state.weeks if state else 0
	return true


## True the first time this action is done at this place.
func mark_action(body_id: String, poi: String, action: String) -> bool:
	var a: Dictionary = body(body_id)["actions"]
	var list: Array = a.get(poi, [])
	if action in list:
		return false
	list.append(action)
	a[poi] = list
	return true


func actions_at(body_id: String, poi: String) -> Array:
	return (body(body_id)["actions"] as Dictionary).get(poi, [])


func is_collected(body_id: String, id: String) -> bool:
	return (body(body_id)["collected"] as Dictionary).has(id)


func mark_collected(body_id: String, id: String) -> bool:
	var c: Dictionary = body(body_id)["collected"]
	if c.has(id):
		return false
	c[id] = true
	return true


func challenge(body_id: String, id: String) -> Dictionary:
	return (body(body_id)["challenges"] as Dictionary).get(id, {})


## A challenge done in `seconds` (0 = untimed): {"first": bool, "best": bool}.
func record_challenge(body_id: String, id: String, seconds := 0.0) -> Dictionary:
	var c: Dictionary = body(body_id)["challenges"]
	var e: Dictionary = c.get(id, {})
	var first := not bool(e.get("done", false))
	var best := first
	e["done"] = true
	e["tries"] = int(e.get("tries", 0)) + 1
	if seconds > 0.0 and (not e.has("best") or seconds < float(e["best"])):
		e["best"] = snappedf(seconds, 0.1)
		best = true
	c[id] = e
	return {"first": first, "best": best}


func add_photo(body_id: String) -> void:
	var b := body(body_id)
	b["photos"] = int(b["photos"]) + 1


func add_visit(body_id: String) -> void:
	var b := body(body_id)
	b["visits"] = int(b["visits"]) + 1


func found_count(body_id: String) -> int:
	return (body(body_id)["found"] as Dictionary).size()


func collected_count(body_id: String) -> int:
	return (body(body_id)["collected"] as Dictionary).size()


func challenges_done(body_id: String) -> int:
	var n := 0
	for k: String in body(body_id)["challenges"]:
		n += 1 if bool((body(body_id)["challenges"][k] as Dictionary).get("done", false)) else 0
	return n


# ------------------------------------------------------------ unlocks (career)
## Bodies whose surface the career has reached (a finished landing there, or a lander / rover
## at work there now); Earth always. Without a career (menu free play) every body is open.
static func unlocked_bodies(p_state: TycoonState) -> Array[String]:
	var out: Array[String] = []
	var bodies: Dictionary = SurfaceExplore.data().get("bodies", {})
	for id: String in bodies:
		if is_unlocked(p_state, id):
			out.append(id)
	return out


static func is_unlocked(p_state: TycoonState, body_id: String) -> bool:
	var b: Dictionary = SurfaceExplore.data().get("bodies", {}).get(body_id, {})
	if b.is_empty():
		return false
	if p_state == null or bool(b.get("always", false)):
		return true
	var surf: Variant = p_state.discovery.get("surfaces", {})
	if surf is Dictionary and bool((surf as Dictionary).get("all", false)):
		return true
	var u: Dictionary = b.get("unlock", {})
	var targets: Array = u.get("targets", [])
	var types: Array = u.get("types", [])
	for m: Dictionary in p_state.mission_archive:
		if String(m.get("target", "")) in targets and String(m.get("type", "")) in types \
				and String(m.get("outcome", "fail")) != "fail":
			return true
	for m: Dictionary in p_state.active_missions:
		if String(m.get("target", "")) in targets and String(m.get("type", "")) in types \
				and String(m.get("status", "")) == "ops":
			return true
	return false


## Dev menu / tests: every body open in this career.
static func unlock_all(p_state: TycoonState) -> void:
	if p_state == null:
		return
	if not (p_state.discovery.get("surfaces", null) is Dictionary):
		p_state.discovery["surfaces"] = {}
	(p_state.discovery["surfaces"] as Dictionary)["all"] = true
