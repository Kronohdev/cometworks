class_name CrewMemory
extends RefCounted
## Cometlings with memory: every Cometling on a project's team remembers the mission when it
## launches (its code, kind, target and how it went), earns personal milestones ("primeira sonda
## lunar", "sobreviveu a 3 explosões", "veterano de 10 missões") and talks about them: the
## chatter / dialogue context and placeholders below feed data/tycoon/chatter.json and
## data/tycoon/dialogues.json. Pure data + rules on a TycoonState, numbers and milestones in
## data/tycoon/crew_memory.json.
##
## Stored on each staff entry as "memory" (saved with the campaign; a save from before reads as
## empty):
##   {"log": [{"code", "type", "target", "o", "w"}, ...]   newest last, at most `cap` missions;
##           o: "first" (a success on the agency's first mission of that kind and target) |
##           "success" | "partial" | "failure"; w: the launch week
##    "n":   {"missions", "successes", "failures", "partials", "firsts", "exceptional"}  totals
##    "ms":  [{"id", "code", "w"}, ...]                   milestones earned, in order}
##
## Chatter / dialogue context (ChatterBook.context merges context()):
##   mem_missions · mem_successes · mem_failures   the totals
##   mem_last     the outcome of their last mission ("first" | "success" | "partial" | "failure" | "")
##   mem_proud    their last mission was a success less than proud_weeks ago
##   mem_nervous  they are on a project of a kind (mission type) they once saw fail
##   mem_milestones  the milestone ids they earned (Array)
## Placeholders (ChatterBook.vars_for merges vars()): {mission} their last mission's code,
## {mission_ok} their last success, {mission_fail} the failure they are nervous about (else
## their last), {mission_kind} the kind of their last mission, {milestone} their newest
## milestone's name, {missions_n} how many missions they flew.

const DATA_PATH := "res://data/tycoon/crew_memory.json"
const FIELD := "memory"
const COUNTS: Array[String] = ["missions", "successes", "failures", "partials", "firsts", "exceptional"]
const ICONS := "res://ui/cometworks/icons/%s.svg"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(DATA_PATH)
	return _data


static func cap() -> int:
	return int(data().get("cap", 12))


## Hooks the campaign: every launch is written into its team's memory (TycoonState calls it on a
## new campaign and on load; calling it twice is harmless).
static func attach(s: TycoonState) -> void:
	if s.has_meta("memory_hooked"):
		return
	s.set_meta("memory_hooked", true)
	var wr: WeakRef = weakref(s)
	s.mission_launched.connect(func(result: Dictionary) -> void:
		var st := wr.get_ref() as TycoonState
		if st:
			on_launch(st, result))


## A project launched (state.mission_launched): its team, from the project history entry.
static func on_launch(s: TycoonState, result: Dictionary) -> void:
	var entry := ProjectDesk.history_entry(s, String(result.get("project_id", "")))
	if entry.is_empty():
		return
	var staff_ids: Array = entry.get("staff", [])
	record(s, staff_ids, entry)


## The outcome word of a launch: "first" | "success" | "partial" | "failure".
static func outcome_of(entry: Dictionary) -> String:
	if not bool(entry.get("success", false)):
		return "failure"
	if String(entry.get("outcome", "")) == "partial":
		return "partial"
	return "first" if bool(entry.get("novelty", false)) else "success"


## Writes a launched mission (a project history entry: code, type, target, success, outcome,
## novelty, week) into the memory of the Cometlings `staff_ids`. Returns the milestones earned:
## [{"staff_id", "id"}].
static func record(s: TycoonState, staff_ids: Array, entry: Dictionary) -> Array[Dictionary]:
	var earned: Array[Dictionary] = []
	var o := outcome_of(entry)
	var row := {"code": String(entry.get("code", "")), "type": String(entry.get("type", "")),
		"target": String(entry.get("target", "")), "o": o, "w": int(entry.get("week", s.weeks))}
	for sid in staff_ids:
		var m := TycoonCrew.find(s, String(sid))
		if m.is_empty():
			continue
		var mem := of(m)
		var rows: Array = mem["log"]
		rows.append(row.duplicate())
		while rows.size() > cap():
			rows.pop_front()
		var n: Dictionary = mem["n"]
		n["missions"] = int(n["missions"]) + 1
		match o:
			"failure":
				n["failures"] = int(n["failures"]) + 1
			"partial":
				n["partials"] = int(n["partials"]) + 1
			_:
				n["successes"] = int(n["successes"]) + 1
				if o == "first":
					n["firsts"] = int(n["firsts"]) + 1
		if String(entry.get("outcome", "")) == "exceptional":
			n["exceptional"] = int(n["exceptional"]) + 1
		# the milestones: the totals plus the mission just flown
		var ctx := n.duplicate()
		ctx["type"] = row["type"]
		ctx["target"] = row["target"]
		ctx["outcome"] = String(entry.get("outcome", "fail"))
		ctx["success"] = bool(entry.get("success", false))
		ctx["first"] = o == "first"
		var have := milestone_ids(m)
		for ms: Dictionary in data().get("milestones", []):
			var id := String(ms.get("id", ""))
			if id == "" or id in have or not ChatterBook.matches(ms.get("if", {}), ctx):
				continue
			(mem["ms"] as Array).append({"id": id, "code": row["code"], "w": row["w"]})
			have.append(id)
			earned.append({"staff_id": String(sid), "id": id})
		m[FIELD] = mem
	return earned


## A Cometling's memory with every field there (a save from before it reads as empty; JSON
## numbers come back as ints). Stored back on `m`, so changes to it stick.
static func of(m: Dictionary) -> Dictionary:
	var mem: Variant = m.get(FIELD, {})
	if not mem is Dictionary:
		mem = {}
	var out: Dictionary = mem
	if not out.get("log", null) is Array:
		out["log"] = []
	if not out.get("ms", null) is Array:
		out["ms"] = []
	var n: Variant = out.get("n", {})
	if not n is Dictionary:
		n = {}
	for k in COUNTS:
		(n as Dictionary)[k] = int((n as Dictionary).get(k, 0))
	out["n"] = n
	for r: Variant in out["log"]:
		if r is Dictionary:
			r["w"] = int(r.get("w", 0))
	for r: Variant in out["ms"]:
		if r is Dictionary:
			r["w"] = int(r.get("w", 0))
	if not m.is_empty():
		m[FIELD] = out
	return out


## The missions a Cometling remembers, oldest first (at most cap()).
static func missions(m: Dictionary) -> Array:
	return of(m)["log"] if m.has(FIELD) else []


static func count(m: Dictionary, key: String) -> int:
	return int(of(m)["n"].get(key, 0)) if m.has(FIELD) else 0


static func milestone_ids(m: Dictionary) -> Array:
	var out: Array = []
	if not m.has(FIELD):
		return out
	for r: Dictionary in of(m)["ms"]:
		out.append(String(r.get("id", "")))
	return out


## The milestone data of `id` (crew_memory.json), {} when unknown.
static func milestone(id: String) -> Dictionary:
	for ms: Dictionary in data().get("milestones", []):
		if String(ms.get("id", "")) == id:
			return ms
	return {}


## The milestones a Cometling earned, in order: [{"id", "code", "w", "name_key", "desc_key",
## "icon" (a texture path), "color"}], unknown ids skipped.
static func milestones_of(m: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not m.has(FIELD):
		return out
	for r: Dictionary in of(m)["ms"]:
		var ms := milestone(String(r.get("id", "")))
		if ms.is_empty():
			continue
		var row := r.duplicate()
		row["name_key"] = String(ms.get("name_key", ""))
		row["desc_key"] = String(ms.get("desc_key", ""))
		row["icon"] = ICONS % String(ms.get("icon", "star"))
		var cname := String(ms.get("color", "AURORA_TEAL"))
		var col: Variant = (CwPalette as Script).get_script_constant_map().get(cname)
		row["color"] = col if col is Color else CwPalette.AURORA_TEAL
		out.append(row)
	return out


static func _last(rows: Array, outcomes: Array, type_id := "") -> Dictionary:
	for i in range(rows.size() - 1, -1, -1):
		var r: Dictionary = rows[i]
		if String(r.get("o", "")) in outcomes and (type_id == "" or String(r.get("type", "")) == type_id):
			return r
	return {}


## The mission type of the project a Cometling is on ("" when none).
static func _assigned_type(s: TycoonState, m: Dictionary) -> String:
	var pid := String(m.get("assigned", ""))
	if s == null or pid == "":
		return ""
	var p := ProjectDesk.find(s, pid)
	return p.type_id if p else ""


## The chatter / dialogue context keys of a Cometling's memory (see the header).
static func context(s: TycoonState, m: Dictionary) -> Dictionary:
	var rows := missions(m)
	var last: Dictionary = rows[rows.size() - 1] if not rows.is_empty() else {}
	var lo := String(last.get("o", ""))
	var proud := lo in ["first", "success"] and s != null \
		and s.weeks - int(last.get("w", 0)) <= int(data().get("proud_weeks", 26))
	var ty := _assigned_type(s, m)
	return {"mem_missions": count(m, "missions"), "mem_successes": count(m, "successes"),
		"mem_failures": count(m, "failures"), "mem_last": lo, "mem_proud": proud,
		"mem_nervous": ty != "" and not _last(rows, ["failure"], ty).is_empty(),
		"mem_milestones": milestone_ids(m)}


## The placeholders of a Cometling's memory (see the header); missing ones are left out.
static func vars(s: TycoonState, m: Dictionary) -> Dictionary:
	var v := {}
	var rows := missions(m)
	if rows.is_empty():
		return v
	var last: Dictionary = rows[rows.size() - 1]
	v["mission"] = String(last.get("code", ""))
	v["missions_n"] = count(m, "missions")
	if s != null:
		v["mission_kind"] = TranslationServer.translate(String(s.mission_type(String(last.get("type", ""))).get("name_key", "")))
	var ok := _last(rows, ["first", "success"])
	if not ok.is_empty():
		v["mission_ok"] = String(ok.get("code", ""))
	var ty := _assigned_type(s, m)
	var bad := _last(rows, ["failure"], ty) if ty != "" else {}
	if bad.is_empty():
		bad = _last(rows, ["failure"])
	if not bad.is_empty():
		v["mission_fail"] = String(bad.get("code", ""))
	var ms := milestones_of(m)
	if not ms.is_empty():
		v["milestone"] = TranslationServer.translate(String(ms[ms.size() - 1]["name_key"]))
	return v
