class_name RoverMissions
extends RefCounted
## Rover missions in the career (data/tycoon/rover_missions.json). Pure rules on TycoonState:
##   is_rover_mission   a mission in operation of a rover type, or carrying a workshop rover
##   rover_of           its rover (RoverDesign.from_payload of the launch's payload; a rover type
##                      launched without one gets the agency's starter rover)
##   objectives_for     its surface objectives: the briefing's set, else the target's
##   can_drive          arrived (operation) and still alive: the map offers "Controlar o rover"
##   start_drive        a SurfaceSession for it (objectives already done stay done)
##   apply_result       a drive's result back into the mission: new objectives done, science
##                      (capped per mission) into the mission and the research points
##   auto_result        what the rover does alone (deterministic: no campaign RNG)
##   attach             when a rover mission ends, the objectives left are done automatically
##                      where the rover can, and the archive entry gets its "surface" summary
## The drives live in RoverGarage.drives(state)[mission id]:
##   {"done": [objective ids], "science": credited, "distance", "photos", "samples", "drives": n}

const PATH := "res://data/tycoon/rover_missions.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(PATH)
	return _data


static func objective_def(id: String) -> Dictionary:
	var d: Dictionary = (data().get("objectives", {}) as Dictionary).get(id, {})
	if d.is_empty():
		return {}
	var o := d.duplicate(true)
	o["id"] = id
	return o


static func objective_set(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in (data().get("sets", {}) as Dictionary).get(key, []):
		var o := objective_def(String(id))
		if not o.is_empty():
			out.append(o)
	return out


static func sandbox_objectives(body: StringName) -> Array[Dictionary]:
	return objective_set("sandbox:%s" % body)


static func sandbox_design(body: StringName) -> Dictionary:
	var d: Dictionary = (data().get("sandbox_designs", {}) as Dictionary).get(String(body), {})
	if d.is_empty():
		return RoverDesign.starter()
	return RoverDesign.make(String(TranslationServer.translate("RV_SANDBOX_NAME")), String(d["chassis"]), d.get("parts", []))


# ------------------------------------------------------------ the career's rover missions
static func history(state: TycoonState, m: Dictionary) -> Dictionary:
	return ProjectDesk.history_entry(state, String(m.get("project_id", m.get("id", ""))))


static func payload_of(state: TycoonState, m: Dictionary) -> Array:
	return history(state, m).get("payload", [])


static func is_rover_mission(state: TycoonState, m: Dictionary) -> bool:
	if SurfaceSession.body_for_target(String(m.get("target", ""))) == &"":
		return false
	if String(m.get("type", "")) in data().get("types", ["rover"]):
		return true
	return not RoverDesign.from_payload(payload_of(state, m)).is_empty()


## The mission's rover: the workshop rover in its payload, else a starter rover with the
## payload's instruments that a rover can carry.
static func rover_of(state: TycoonState, m: Dictionary) -> Dictionary:
	var payload := payload_of(state, m)
	var d := RoverDesign.from_payload(payload)
	if not d.is_empty():
		return d
	var base := RoverDesign.starter("%s %s" % [String(TranslationServer.translate("RV_STARTER_NAME")), String(m.get("code", ""))])
	var parts: Array = []
	for p: Dictionary in RoverDesign.data().get("parts", []):
		if String(p.get("payload", "")) in payload:
			parts.append(String(p["id"]))
	if parts.is_empty():
		return base
	# the chassis holds two power parts: the best generator and the best battery
	var power: Array = parts.filter(func(x: String) -> bool: return String(RoverDesign.part(x).get("slot", "")) == "power")
	var keep: Array = []
	for group in [["rtg", "solar_wing", "solar"], ["battery_l", "battery"]]:
		for x in group:
			if x in power:
				keep.append(x)
				break
	parts = parts.filter(func(x: String) -> bool: return not x in power or x in keep)
	var out := RoverDesign.make(String(base["name"]), "wheels4", parts)
	if RoverDesign.parts_in(out, "comms").is_empty():
		(out["parts"] as Array).append("beacon")
	if RoverDesign.stats(out)["gen"] <= 0.0 and RoverDesign.stats(out)["store"] <= 0.0:
		(out["parts"] as Array).append("solar")
	if RoverDesign.parts_in(out, "instrument").size() > 3:
		out["chassis"] = "wheels6"
	return out


static func briefing_of(state: TycoonState, m: Dictionary) -> String:
	var b: Dictionary = history(state, m).get("briefing", {})
	return String(b.get("id", ""))


static func objectives_for(state: TycoonState, m: Dictionary) -> Array[Dictionary]:
	var bid := briefing_of(state, m)
	var list := objective_set("briefing:" + bid) if bid != "" else ([] as Array[Dictionary])
	if list.is_empty():
		list = objective_set("target:" + String(m.get("target", "")))
	var done: Array = RoverGarage.drive_of(state, String(m.get("id", ""))).get("done", [])
	for o in list:
		o["done"] = String(o["id"]) in done
	return list


static func can_drive(state: TycoonState, m: Dictionary) -> bool:
	return not m.is_empty() and String(m.get("status", "")) == "ops" and is_rover_mission(state, m)


## The active mission a tracked craft is ({} if it is not one of the player's missions in operation).
static func mission_of_track(state: TycoonState, track: Dictionary) -> Dictionary:
	return MissionOps.find(state, String(track.get("project_id", "")))


## A SurfaceSession for a mission in operation (null if it cannot drive now).
static func start_drive(state: TycoonState, mission_id: String, ctx := {}) -> SurfaceSession:
	var m := MissionOps.find(state, mission_id)
	if not can_drive(state, m):
		return null
	var target := String(m.get("target", ""))
	var c := {"mission_id": mission_id, "code": String(m.get("code", "")), "target": target, "return": "tycoon",
		"pole": target in data().get("pole_targets", [])}
	c.merge(ctx, true)
	return SurfaceSession.start(SurfaceSession.body_for_target(target), rover_of(state, m), objectives_for(state, m), c)


## The total science the mission's objectives are worth.
static func objectives_science(list: Array) -> float:
	var t := 0.0
	for o in list:
		t += float(o.get("science", 0.0))
	return t


## A drive's result back into its mission. Returns the science credited now.
static func apply_result(state: TycoonState, mission_id: String, result: Dictionary) -> float:
	var m := MissionOps.find(state, mission_id)
	var drives := RoverGarage.drives(state)
	var rec: Dictionary = drives.get(mission_id, {"done": [], "science": 0.0, "distance": 0.0, "photos": 0, "samples": 0,
		"drives": 0})
	var done: Array = rec["done"]
	for id in result.get("objectives_done", []):
		if not String(id) in done:
			done.append(String(id))
	var cap := objectives_science(objectives_for(state, m)) * float(data().get("drive_science_cap", 1.6)) \
		+ float(data().get("ground_science", 12.0)) if not m.is_empty() else float(result.get("science", 0.0))
	var add := clampf(float(result.get("science", 0.0)), 0.0, maxf(cap - float(rec["science"]), 0.0))
	rec["science"] = float(rec["science"]) + add
	rec["distance"] = float(rec["distance"]) + float(result.get("distance", 0.0))
	rec["photos"] = int(rec["photos"]) + int(result.get("photos", 0))
	rec["samples"] = int(rec["samples"]) + int(result.get("samples", 0))
	rec["drives"] = int(rec["drives"]) + 1
	drives[mission_id] = rec
	if not m.is_empty() and add > 0.0:
		m["science"] = float(m.get("science", 0.0)) + add
		state.research_points += add * float(MissionOps.data().get("research_share", 0.5))
		state.news.push_front({"key": "RV_NEWS_DRIVE", "args": [String(m.get("code", "")), roundi(add)]})
	state.changed.emit()
	return add


## What the rover does alone: {"done": [ids], "science", "failed": [{"id", "why"}]}. Deterministic.
static func auto_result(rover: Dictionary, objectives: Array, body: String, pole := false) -> Dictionary:
	var st := RoverDesign.stats(rover, body)
	var tools: Array = st["tools"]
	var reach_m := INF if float(st["range_km"]) < 0.0 else float(st["range_km"]) * 1000.0 * 0.5
	var night_ok := float(st["rtg"]) > 0.0 or float(st["store"]) >= 100.0
	var out := {"done": [], "science": 0.0, "failed": []}
	var mult := float(data().get("auto_science", 0.7))
	for o in objectives:
		if bool(o.get("done", false)):
			continue
		var why := ""
		var need := String(o.get("need", ""))
		if need == "photo" and String(o.get("kind", "")) == "panorama":
			need = "photo"
		if need != "" and not need in tools:
			why = "RV_AUTO_NO_TOOL"
		elif need == "drone" and not bool(st["drone_ok"]):
			why = "RV_AUTO_NO_AIR"
		elif float(o.get("climb", 0.0)) > float(st["climb"]):
			why = "RV_AUTO_TOO_STEEP"
		elif bool(o.get("night", false)) and pole and not night_ok:
			why = "RV_AUTO_COLD"
		else:
			var off: Array = o.get("offset", [])
			var dist := Vector2(float(off[0]), float(off[1])).length() if off.size() > 1 else 0.0
			if String(o.get("kind", "")) == "drive":
				dist = float(o.get("amount", 100.0))
			if dist > reach_m:
				why = "RV_AUTO_TOO_FAR"
		if why == "":
			(out["done"] as Array).append(String(o["id"]))
			out["science"] = float(out["science"]) + float(o.get("science", 0.0)) * mult
		else:
			(out["failed"] as Array).append({"id": String(o["id"]), "why": why, "label_key": String(o.get("label_key", ""))})
	return out


# ------------------------------------------------------------ the end of a rover mission
## Listens for missions that end (TycoonState calls it with SpaceTracking.attach). Idempotent.
static func attach(state: TycoonState) -> void:
	if state.has_meta("rover_missions"):
		return
	state.set_meta("rover_missions", true)
	var ref: WeakRef = weakref(state)
	state.mission_completed.connect(func(r: Dictionary) -> void:
		var s := ref.get_ref() as TycoonState
		if s and String(r.get("mission_id", "")) != "":
			finish_mission(s, String(r["mission_id"])))
	state.week_passed.connect(func(_y: int, _w: int) -> void:
		var s := ref.get_ref() as TycoonState
		if s:
			announce_arrivals(s))


## A rover mission that just reached its surface tells the news (once): the map can drive it.
static func announce_arrivals(state: TycoonState) -> void:
	for m in state.active_missions:
		if String(m.get("status", "")) == "ops" and not m.get("rover_news", false) and is_rover_mission(state, m):
			m["rover_news"] = true
			state.news.push_front({"key": "RV_NEWS_ARRIVED", "args": [String(m.get("code", ""))]})


## A rover mission's archive entry gets its "surface" summary; what the player did not drive is
## done automatically where the rover can (only for missions that ended well). Returns the summary.
static func finish_mission(state: TycoonState, mission_id: String) -> Dictionary:
	var entry := {}
	for i in range(state.mission_archive.size() - 1, -1, -1):
		if String(state.mission_archive[i].get("id", "")) == mission_id:
			entry = state.mission_archive[i]
			break
	if entry.is_empty() or entry.has("surface"):
		return entry.get("surface", {})
	var m := entry.duplicate()
	m["project_id"] = String(entry.get("project_id", mission_id))
	if not is_rover_mission(state, m):
		return {}
	var list := objectives_for(state, m)
	var rec := RoverGarage.drive_of(state, mission_id)
	var done: Array = (rec.get("done", []) as Array).duplicate()
	var auto := {"done": [], "science": 0.0, "failed": []}
	if String(entry.get("status", "")) == "done":
		auto = auto_result(rover_of(state, m), list, String(SurfaceSession.body_for_target(String(entry.get("target", "")))),
			String(entry.get("target", "")) in data().get("pole_targets", []))
	for id in auto["done"]:
		if not id in done:
			done.append(id)
	var sci := float(auto["science"])
	if sci > 0.0:
		entry["science"] = float(entry.get("science", 0.0)) + sci
		state.research_points += sci * float(MissionOps.data().get("research_share", 0.5))
	var summary := {"done": done, "total": list.size(), "driven": int(rec.get("drives", 0)) > 0,
		"drive_science": float(rec.get("science", 0.0)), "auto_done": auto["done"], "auto_science": sci,
		"failed": auto["failed"], "rover": String(rover_of(state, m).get("name", "")),
		"distance": float(rec.get("distance", 0.0))}
	entry["surface"] = summary
	return summary


## One line for the mission's page in the archive: "Superfície: 3 de 4 objetivos · 42 de ciência".
static func summary_text(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	var t := TranslationServer.translate("RV_REV_SURFACE") % [(s.get("done", []) as Array).size(), int(s.get("total", 0)),
		roundi(float(s.get("drive_science", 0.0)) + float(s.get("auto_science", 0.0)))]
	t += "  " + TranslationServer.translate("RV_REV_DRIVEN" if s.get("driven", false) else "RV_REV_AUTO")
	var failed: Array = s.get("failed", [])
	if not failed.is_empty():
		var f: Dictionary = failed[0]
		t += "\n" + TranslationServer.translate("RV_REV_FAILED") % [TranslationServer.translate(String(f.get("label_key", ""))),
			TranslationServer.translate(String(f.get("why", "")))]
	return t
