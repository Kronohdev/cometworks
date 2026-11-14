class_name TycoonResearch
extends RefCounted
## Research and technology (GDD section 10): the tech tree of data/tycoon/research.json,
## research points (PP) every week from the researchers seated in the lab (scientists help
## less) plus the science other systems add to `TycoonState.research_points`, the research
## being funded (and a queue), and what a finished tech unlocks. Pure rules on a TycoonState,
## headless. Sub-state lives in `TycoonState.research`:
##   {"active": tech id or "", "queue": [ids], "progress": {id: PP spent}, "pp_week": last
##    week's output, "licensed": {id: rival id}, "study": the mission study, FocusStudy}
## A finished tech sets `unlocked[id] = true` and one `unlocked["<kind>:<id>"] = true` per
## unlock (type:, target:, rocket:, part:, option:, spec:), so other systems only read `unlocked`.

const PATH := "res://data/tycoon/research.json"
const UNLOCK_KINDS := {"types": "type", "targets": "target", "rockets": "rocket", "parts": "part", "options": "option",
	"specs": "spec"}

static var _db: Dictionary = {}
static var _by_id: Dictionary = {}


static func db() -> Dictionary:
	if _db.is_empty():
		_db = TycoonState.load_json(PATH)
		_by_id.clear()
		for t: Dictionary in _db.get("techs", []):
			_by_id[String(t["id"])] = t
	return _db


static func techs() -> Array:
	return db().get("techs", [])


static func tech(id: String) -> Dictionary:
	db()
	return _by_id.get(id, {})


static func branch(id: String) -> Dictionary:
	return db().get("branches", {}).get(id, {})


static func rs(s: TycoonState) -> Dictionary:
	if s.research.is_empty():
		s.research = {"active": "", "queue": [], "progress": {}, "pp_week": 0.0, "licensed": {}}
	return s.research


# ------------------------------------------------------------ tree state
static func is_done(s: TycoonState, id: String) -> bool:
	return bool(s.unlocked.get(id, false))


static func progress(s: TycoonState, id: String) -> float:
	return float(rs(s)["progress"].get(id, 0.0))


static func fraction(s: TycoonState, id: String) -> float:
	var t := tech(id)
	if t.is_empty():
		return 0.0
	return 1.0 if is_done(s, id) else clampf(progress(s, id) / float(t["cost"]), 0.0, 1.0)


static func prereqs_done(s: TycoonState, id: String) -> bool:
	for p: String in tech(id).get("prereq", []):
		if not is_done(s, p):
			return false
	return true


## Techs up to one era ahead of the calendar can be researched (`era_lookahead`).
static func era_open(s: TycoonState, id: String) -> bool:
	return int(tech(id).get("era", 1)) <= s.era() + int(db().get("era_lookahead", 1))


static func can_research(s: TycoonState, id: String) -> bool:
	return not tech(id).is_empty() and not is_done(s, id) and prereqs_done(s, id) and era_open(s, id)


## "done" | "researching" | "queued" | "available" | "locked"
static func node_state(s: TycoonState, id: String) -> String:
	if is_done(s, id):
		return "done"
	var r := rs(s)
	if String(r["active"]) == id:
		return "researching"
	if id in r["queue"]:
		return "queued"
	return "available" if can_research(s, id) else "locked"


static func active(s: TycoonState) -> String:
	return String(rs(s)["active"])


static func queue(s: TycoonState) -> Array:
	return rs(s)["queue"]


## Fund a research: it starts now when nothing is being researched, else it joins the queue.
## Funding the active one or a queued one again cancels it (progress is kept).
static func fund(s: TycoonState, id: String) -> bool:
	var r := rs(s)
	if String(r["active"]) == id:
		r["active"] = ""
		_next_from_queue(s)
		s.changed.emit()
		return true
	if id in r["queue"]:
		(r["queue"] as Array).erase(id)
		s.changed.emit()
		return true
	if not can_research(s, id):
		return false
	if String(r["active"]) == "":
		r["active"] = id
	else:
		(r["queue"] as Array).append(id)
	s.changed.emit()
	return true


static func _next_from_queue(s: TycoonState) -> void:
	var r := rs(s)
	var q: Array = r["queue"]
	while String(r["active"]) == "" and not q.is_empty():
		var nx := String(q.pop_front())
		if can_research(s, nx):
			r["active"] = nx


## Most PP the tech can absorb in one week (cost / weeks): research also takes time.
static func weekly_cap(id: String) -> float:
	var t := tech(id)
	return float(t.get("cost", 0)) / maxf(float(t.get("weeks", 1)), 1.0)


## Weeks until the tech is done at today's lab output if funded now (-1: never, no PP).
static func weeks_left(s: TycoonState, id: String) -> int:
	var left := float(tech(id).get("cost", 0)) - progress(s, id)
	var pool := s.research_points
	var ppw := pp_per_week(s)
	var cap := weekly_cap(id)
	var n := 0
	while left > 0.001:
		pool += ppw
		var draw := minf(minf(pool, left), cap)
		if draw <= 0.0 or n > 520:
			return -1
		left -= draw
		pool -= draw
		n += 1
	return n


# ------------------------------------------------------------ research points
static func lab_level(s: TycoonState) -> int:
	return int(s.building("lab").get("level", 0))


static func lab_seats(s: TycoonState) -> int:
	var seats: Array = db().get("lab_seats", [1, 2, 4, 6])
	return int(seats[clampi(lab_level(s), 0, seats.size() - 1)])


static func effect(s: TycoonState, key: String) -> float:
	var total := 0.0
	for t: Dictionary in techs():
		if is_done(s, String(t["id"])):
			total += float(t.get("effects", {}).get(key, 0.0))
	return total


## PP a staff member makes in a week when seated in the lab (0 if not a researcher/scientist).
static func member_pp(m: Dictionary) -> float:
	var d := db()
	var f := 0.0
	match String(m.get("profession", "")):
		"researcher":
			f = 1.0
		"scientist":
			f = float(d.get("scientist_factor", 0.35))
	if f <= 0.0:
		return 0.0
	var lvl := float(int(m.get("level", 1)) - 1)
	return float(d.get("pp_per_researcher_week", 8.0)) * (0.4 + 0.6 * float(m.get("skill", 0.5))) * f \
		* (1.0 + float(d.get("level_step", 0.08)) * lvl)


## Who sits in the lab this week: free (unassigned) researchers first, then scientists, up
## to the lab's seats. Returns [{"member", "pp"}] best first.
static func seated(s: TycoonState) -> Array[Dictionary]:
	var cand: Array[Dictionary] = []
	for m in s.staff:
		if String(m.get("assigned", "")) != "" or not TycoonCrew.is_working(m):
			continue
		var pp := member_pp(m) * (1.0 + TycoonCrew.spec_effect(m, "research"))
		if pp > 0.0:
			cand.append({"member": m, "pp": pp})
	cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pp"]) > float(b["pp"]))
	return cand.slice(0, lab_seats(s))


static func lab_mult(s: TycoonState) -> float:
	var mults: Array = db().get("lab_mult", [0.5, 1.0, 1.0, 1.5])
	return float(mults[clampi(lab_level(s), 0, mults.size() - 1)]) * (1.0 + effect(s, "pp_mult"))


static func pp_per_week(s: TycoonState) -> float:
	var total := 0.0
	for e in seated(s):
		total += float(e["pp"])
	return total * lab_mult(s)


# ------------------------------------------------------------ weekly
## One week: the lab makes PP into the pool; the mission study being made (FocusStudy) draws
## first, then the funded research draws from the pool (at most cost / weeks per week) and
## finishes when it has drawn its cost.
static func weekly(s: TycoonState) -> void:
	var r := rs(s)
	var made := pp_per_week(s)
	r["pp_week"] = made
	s.research_points += made
	# a mission study (FocusStudy) draws from the pool first: it is small and quick
	FocusStudy.weekly(s)
	_next_from_queue(s)
	var id := String(r["active"])
	if id == "":
		return
	if not can_research(s, id):
		r["active"] = ""
		_next_from_queue(s)
		return
	var cost := float(tech(id)["cost"])
	var draw := minf(minf(s.research_points, cost - progress(s, id)), weekly_cap(id))
	if draw > 0.0:
		r["progress"][id] = progress(s, id) + draw
		s.research_points -= draw
	if progress(s, id) >= cost - 0.001:
		complete(s, id)


## Marks a tech done and applies its unlocks (also used by tests and saves of early eras).
static func complete(s: TycoonState, id: String) -> void:
	var t := tech(id)
	if t.is_empty() or is_done(s, id):
		return
	var r := rs(s)
	r["progress"][id] = float(t["cost"])
	s.unlocked[id] = true
	var u: Dictionary = t.get("unlocks", {})
	for k: String in UNLOCK_KINDS:
		for x in u.get(k, []):
			s.unlocked["%s:%s" % [UNLOCK_KINDS[k], x]] = true
	if String(r["active"]) == id:
		r["active"] = ""
	(r["queue"] as Array).erase(id)
	_next_from_queue(s)
	s.news.push_front({"key": "TY_NEWS_TECH", "args": ["TY_TECH_" + id.to_upper()]})


## Unlocks of a tech as display rows: [{"kind": "type"|"target"|"rocket"|"option"|"spec"|"part"|"effect",
## "id", "key" (translation key) or "name" (parts: name from data/parts.json), "value" (effects)}].
static func unlock_list(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := tech(id)
	var u: Dictionary = t.get("unlocks", {})
	for k: String in ["types", "targets", "rockets", "options", "specs", "parts"]:
		for x in u.get(k, []):
			var kind := String(UNLOCK_KINDS[k])
			var row := {"kind": kind, "id": String(x)}
			match kind:
				"type":
					row["key"] = _mission_key("types", String(x))
				"target":
					row["key"] = _mission_key("targets", String(x))
				"part":
					row["name"] = PartDB.part_name(String(x))
				"rocket":
					# "Alongados (tanques)": the part and the slot it goes in
					var c := RocketDesigner.component(String(x))
					var cn := TranslationServer.translate(String(c.get("name_key", x)))
					var sn := TranslationServer.translate(String(RocketDesigner.slot(String(c.get("slot", ""))).get("name_key", "")))
					row["key"] = String(c.get("name_key", x))
					row["name"] = cn if sn == "" or cn.to_lower().contains(sn.to_lower()) else "%s (%s)" % [cn, sn.to_lower()]
				_:
					row["key"] = "TY_%s_%s" % [kind.to_upper(), String(x).to_upper()]
			out.append(row)
	for e: String in t.get("effects", {}):
		out.append({"kind": "effect", "id": e, "key": "TY_EFFECT_" + e.to_upper(), "value": t["effects"][e]})
	return out


static var _missions: Dictionary = {}


static func _mission_key(list: String, id: String) -> String:
	if _missions.is_empty():
		_missions = TycoonState.load_json(TycoonState.MISSIONS_PATH)
	for m: Dictionary in _missions.get(list, []):
		if m["id"] == id:
			return String(m.get("name_key", id))
	return id


# ------------------------------------------------------------ mission vocabulary
## Ids unlocked by some tech (types or targets); the others only need their era.
static func _gated(list: String) -> Dictionary:
	var out := {}
	for t: Dictionary in techs():
		for x in t.get("unlocks", {}).get(list, []):
			out[String(x)] = String(t["id"])
	return out


static func tech_for_type(id: String) -> String:
	return String(_gated("types").get(id, ""))


static func tech_for_target(id: String) -> String:
	return String(_gated("targets").get(id, ""))


## The tech that opens a specialisation ("" for those there from the start).
static func tech_for_spec(id: String) -> String:
	return String(_gated("specs").get(id, ""))


## A mission type is available once the tech that unlocks it is done (types no tech unlocks,
## like the sounding rocket, only need their era).
static func mission_type_available(s: TycoonState, id: String) -> bool:
	var t := s.mission_type(id)
	if t.is_empty():
		return false
	var by := tech_for_type(id)
	return is_done(s, by) if by != "" else s.era() >= int(t.get("era", 1))


## A target with "approach_weeks" (the comet) is only within reach in the campaign's last weeks.
static func mission_target_available(s: TycoonState, id: String) -> bool:
	var t := s.mission_target(id)
	if t.is_empty():
		return false
	if int(t.get("approach_weeks", 0)) > 0 and s.comet_weeks_left() > int(t["approach_weeks"]):
		return false
	var by := tech_for_target(id)
	return is_done(s, by) if by != "" else s.era() >= int(t.get("era", 1))


## Can this type fly to this target, beyond each one being open? Crewed flights to the targets
## of projects.json launch.crewed_target_tech also need that tech. Returns "" or the reason
## (a translation key).
static func pair_error(s: TycoonState, type_id: String, target_id: String) -> String:
	if not ProjectRules.is_crewed(type_id):
		return ""
	var l := ProjectRules.section("launch")
	var need := String((l.get("crewed_target_tech", {}) as Dictionary).get(target_id, ""))
	if need != "" and not is_done(s, need):
		return String(l.get("crewed_target_error", "TY_PJ_ERR_TARGET"))
	return ""


static func pair_available(s: TycoonState, type_id: String, target_id: String) -> bool:
	return pair_error(s, type_id, target_id) == ""


# ------------------------------------------------------------ licensing (GDD 10 / 12)
static func license_value(id: String) -> float:
	var d := db()
	return float(tech(id).get("cost", 0)) * float(d.get("license_cr_per_pp", 500)) * float(d.get("license_fraction", 0.45))


static func can_license(s: TycoonState, id: String) -> bool:
	return is_done(s, id) and not rs(s)["licensed"].has(id) and not s.rivals.is_empty()


## Licenses a finished tech to a rival: cash now, the rival gets a little stronger in the race.
static func license(s: TycoonState, id: String) -> bool:
	if not can_license(s, id):
		return false
	var rv: Dictionary = s.rivals[s.rng.randi_range(0, s.rivals.size() - 1)]
	rv["capacity"] = float(rv.get("capacity", 1.0)) + float(db().get("license_rival_capacity", 0.03))
	rs(s)["licensed"][id] = String(rv.get("id", ""))
	TycoonFinance.add(s, "licences", license_value(id))
	s.news.push_front({"key": "TY_NEWS_LICENSE", "args": ["TY_TECH_" + id.to_upper(), String(rv.get("name_key", ""))]})
	s.changed.emit()
	return true
