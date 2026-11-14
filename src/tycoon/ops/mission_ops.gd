class_name MissionOps
extends RefCounted
## Weekly operation of the missions in space (GDD sections 7 and 14, step E5). Pure data and
## rules on TycoonState.active_missions, no scene access, so it runs headless. Numbers come
## from data/tycoon/ops.json; every random draw uses the state's seeded `rng`.
##
## Per mission, per week: cruise to the target (weeks by target), then operations:
##   generated  = gen_per_week * modifiers
##   stored     = min(storage, stored + generated)     # the excess is LOST
##   downlinked = min(downlink_possible, stored)       # antenna network x distance x contact
##   science   += downlinked * value                   # only data on the ground counts
## One decision event per mission (2-3 choices, consequences in ops.json), answered by the
## player on the map or resolved to its default after a few weeks. At the end the mission
## leaves `active_missions` for `mission_archive` and `mission_completed` is emitted.
##
## Fields this module adds to a mission (on top of the shared schema in TycoonState):
##   age, cruise_weeks, ops_weeks, storage, gen_rate, value, value_mult, buffer_mult,
##   antenna_gain, health, gen_mult, gen_mult_weeks, data_gen, data_lost, last_gen,
##   last_down, last_lost, event, decision_week, decision ({} or {"event", "since"}),
##   choice, cause, log [{"age", "key"}], ops_ready.
## Set at launch by ProjectDesk: spec_science / spec_downlink (the team's specialisations).

const OPS_PATH := "res://data/tycoon/ops.json"
const ENCYCLOPEDIA_PATH := "res://data/tycoon/encyclopedia.json"

static var _data: Dictionary = {}
static var _book: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(OPS_PATH)
	return _data


static func target_ops(target_id: String) -> Dictionary:
	return data().get("targets", {}).get(target_id, {})


static func type_ops(type_id: String) -> Dictionary:
	return data().get("types", {}).get(type_id, {})


static func event_def(event_id: String) -> Dictionary:
	for e: Dictionary in data().get("events", []):
		if e["id"] == event_id:
			return e
	return {}


## Level of the antenna network: the antenna building's finished level (0 = only the small
## campus dish).
static func antenna_level(state: TycoonState) -> int:
	return clampi(int(state.building("antenna").get("level", 0)), 0, 3)


static func network_gain(level: int) -> float:
	var g: Array = data().get("network", {}).get("gain", [1.0])
	return float(g[clampi(level, 0, g.size() - 1)])


## Fraction of the week the mission sees a ground station with this network level.
static func contact(target_id: String, level: int) -> float:
	var c: Array = target_ops(target_id).get("contact", [1.0])
	return float(c[clampi(level, 0, c.size() - 1)])


## Gb per week the network can bring down from this mission at antenna level `level`.
static func downlink_rate_at(m: Dictionary, level: int) -> float:
	var target := String(m.get("target", ""))
	var t := target_ops(target)
	var gain := float(m.get("antenna_gain", type_ops(String(m.get("type", ""))).get("antenna", 1.0)))
	return float(data().get("base_downlink", 40.0)) * network_gain(level) * float(t.get("link", 1.0)) \
		* contact(target, level) * gain * (1.0 + float(m.get("spec_downlink", 0.0)))


static func downlink_rate(state: TycoonState, m: Dictionary) -> float:
	return downlink_rate_at(m, antenna_level(state))


## Science multiplier from the scientists on staff (+5% each, up to 5).
static func scientist_bonus(state: TycoonState) -> float:
	var n := 0
	for s in state.staff:
		if String(s.get("profession", "")) == "scientist":
			n += 1
	var d := data()
	return 1.0 + float(d.get("scientist_bonus_each", 0.05)) * mini(n, int(d.get("scientist_bonus_max", 5)))


## Flight controllers on staff show the risk of each choice before the player picks.
static func reveals_risk(state: TycoonState) -> bool:
	for s in state.staff:
		if String(s.get("profession", "")) == "flight_controller":
			return true
	return false


static func find(state: TycoonState, mission_id: String) -> Dictionary:
	for m in state.active_missions:
		if String(m.get("id", "")) == mission_id:
			return m
	return {}


## Missions waiting for the player's decision.
static func pending_decisions(state: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in state.active_missions:
		if not (m.get("decision", {}) as Dictionary).is_empty():
			out.append(m)
	return out


# ------------------------------------------------------------ weekly step
## The one call from TycoonState.advance_week().
static func advance_week(state: TycoonState) -> void:
	var finished: Array[Dictionary] = []
	for m in state.active_missions:
		init_mission(state, m)
		if m["status"] == "cruise" or m["status"] == "ops":
			_step(state, m)
		if m["status"] == "done" or m["status"] == "lost":
			finished.append(m)
	for m in finished:
		_finish(state, m)


## Fills the operation fields of a mission appended at launch (idempotent).
static func init_mission(state: TycoonState, m: Dictionary) -> void:
	if m.get("ops_ready", false):
		return
	var t := target_ops(String(m.get("target", "")))
	var ty := type_ops(String(m.get("type", "")))
	var d := data()
	var outcome := String(m.get("outcome", "full"))
	m["age"] = 0
	m["cruise_weeks"] = int(m.get("cruise_weeks", t.get("cruise_weeks", 1)))
	m["ops_weeks"] = maxi(int(m.get("ops_weeks", ty.get("ops_weeks", 8))), 1)
	m["weeks_total"] = int(m["cruise_weeks"]) + int(m["ops_weeks"])
	m["storage"] = float(m.get("storage", ty.get("storage", 30.0)))
	m["gen_rate"] = float(m.get("gen_per_week", ty.get("gen_per_week", 5.0))) \
		* float(d.get("outcome_gen", {}).get(outcome, 1.0))
	m["value"] = float(m.get("value", ty.get("value", 1.0)))
	m["antenna_gain"] = float(m.get("antenna_gain", ty.get("antenna", 1.0)))
	m["value_mult"] = 1.0
	m["buffer_mult"] = 1.0
	m["health"] = clampf(float(m.get("health", 1.0)) * float(d.get("outcome_health", {}).get(outcome, 1.0)), 0.0, 1.0)
	m["gen_mult"] = 1.0
	m["gen_mult_weeks"] = 0
	for k in ["data_stored", "data_down", "data_gen", "data_lost", "science", "last_gen", "last_down", "last_lost"]:
		m[k] = float(m.get(k, 0.0))
	m["start_week"] = int(m.get("start_week", state.weeks))
	m["status"] = "cruise" if int(m["cruise_weeks"]) > 0 else "ops"
	m["decision"] = {}
	m["choice"] = -1
	m["cause"] = ""
	m["log"] = []
	# the one decision event of this mission: drawn now, opens on a seeded week of operations
	m["event"] = ""
	m["decision_week"] = -1
	var cands: Array[Dictionary] = []
	var total_w := 0.0
	for e: Dictionary in d.get("events", []):
		if _event_fits(e, m, t):
			cands.append(e)
			total_w += float(e.get("weight", 1.0))
	if not cands.is_empty():
		var r := state.rng.randf() * total_w
		var pick: Dictionary = cands[-1]
		for e in cands:
			r -= float(e.get("weight", 1.0))
			if r <= 0.0:
				pick = e
				break
		m["event"] = pick["id"]
		var ops := int(m["ops_weeks"])
		var first := maxi(1, mini(int(pick.get("min_ops", 1)) - 1, ops))
		m["decision_week"] = int(m["cruise_weeks"]) + state.rng.randi_range(first, maxi(first, ops - 3))
	if outcome == "fail" or not bool(m.get("success", true)):
		m["status"] = "lost"
		m["cause"] = "TY_OPS_CAUSE_LAUNCH"
	m["ops_ready"] = true


static func _event_fits(e: Dictionary, m: Dictionary, t: Dictionary) -> bool:
	var target := String(m.get("target", ""))
	if int(m.get("ops_weeks", 0)) < int(e.get("min_ops", 1)):
		return false
	if e.has("targets") and not (e["targets"] as Array).has(target):
		return false
	if e.has("classes") and not (e["classes"] as Array).has(String(t.get("class", ""))):
		return false
	if e.has("not_targets") and (e["not_targets"] as Array).has(target):
		return false
	return true


static func _step(state: TycoonState, m: Dictionary) -> void:
	m["age"] = int(m["age"]) + 1
	var age := int(m["age"])
	m["last_gen"] = 0.0
	m["last_down"] = 0.0
	m["last_lost"] = 0.0
	if age <= int(m["cruise_weeks"]):
		m["status"] = "cruise"
	else:
		if m["status"] == "cruise":
			_log(m, "TY_OPS_LOG_ARRIVED")
		m["status"] = "ops"
		var g := float(m["gen_rate"])
		if int(m["gen_mult_weeks"]) > 0:
			g *= float(m["gen_mult"])
			m["gen_mult_weeks"] = int(m["gen_mult_weeks"]) - 1
		var cap := float(m["storage"]) * float(m["buffer_mult"])
		var stored := float(m["data_stored"])
		var kept := minf(g, maxf(cap - stored, 0.0))
		stored += kept
		var down := minf(downlink_rate(state, m), stored)
		stored -= down
		m["data_stored"] = stored
		m["data_gen"] = float(m["data_gen"]) + g
		m["data_lost"] = float(m["data_lost"]) + (g - kept)
		m["data_down"] = float(m["data_down"]) + down
		m["last_gen"] = g
		m["last_down"] = down
		m["last_lost"] = g - kept
		_credit(state, m, down * float(m["value"]) * float(m["value_mult"]) * scientist_bonus(state)
			* (1.0 + float(m.get("spec_science", 0.0))))
	# random faults: rarer on a healthy spacecraft
	var hz := float(target_ops(String(m["target"])).get("hazard", 0.0)) * (2.0 - float(m["health"]))
	if hz > 0.0 and state.rng.randf() < hz:
		_lose(m, "TY_OPS_CAUSE_FAULT")
		return
	# the decision event: opens on its week, falls back to the default choice after a while
	var dec: Dictionary = m["decision"]
	if not dec.is_empty():
		if age - int(dec.get("since", age)) >= int(data().get("decision_timeout_weeks", 3)):
			decide(state, String(m["id"]), default_choice(String(m["event"])), true)
	elif String(m["event"]) != "" and int(m["choice"]) < 0 and age >= int(m["decision_week"]) \
			and m["status"] == "ops":
		m["decision"] = {"event": m["event"], "since": age}
		state.news.push_front({"key": "TY_OPS_NEWS_DECISION", "args": [String(m.get("code", "")),
			"TY_OPS_EV_%s_TITLE" % String(m["event"]).to_upper()]})
	if m["status"] != "lost" and age >= int(m["weeks_total"]):
		m["status"] = "done"


static func _credit(state: TycoonState, m: Dictionary, sci: float) -> void:
	if sci <= 0.0:
		return
	m["science"] = float(m["science"]) + sci
	state.research_points += sci * float(data().get("research_share", 0.5))


static func _lose(m: Dictionary, cause: String) -> void:
	m["status"] = "lost"
	m["cause"] = cause
	m["decision"] = {}
	_log(m, cause)


static func _log(m: Dictionary, key: String) -> void:
	(m["log"] as Array).append({"age": int(m.get("age", 0)), "key": key})


static func default_choice(event_id: String) -> int:
	var choices: Array = event_def(event_id).get("choices", [])
	for i in choices.size():
		if choices[i].get("default", false):
			return i
	return 0


## The probability that a choice loses the mission (for the decision card).
static func choice_risk(event_id: String, index: int) -> float:
	var choices: Array = event_def(event_id).get("choices", [])
	if index < 0 or index >= choices.size():
		return 0.0
	return float(choices[index].get("effects", {}).get("risk", 0.0))


## The player's answer to a mission's pending decision (a serializable command:
## mission id + choice index). Returns false when there is nothing to decide.
static func decide(state: TycoonState, mission_id: String, index: int, auto := false) -> bool:
	var m := find(state, mission_id)
	if m.is_empty() or (m.get("decision", {}) as Dictionary).is_empty():
		return false
	var choices: Array = event_def(String(m["event"])).get("choices", [])
	if index < 0 or index >= choices.size():
		return false
	var fx: Dictionary = choices[index].get("effects", {})
	m["decision"] = {}
	m["choice"] = index
	_log(m, String(choices[index]["key"]))
	if fx.has("buffer_mult"):
		m["buffer_mult"] = float(m["buffer_mult"]) * float(fx["buffer_mult"])
	if fx.has("value_mult"):
		m["value_mult"] = float(m["value_mult"]) * float(fx["value_mult"])
	if fx.has("free_stored"):
		var freed := float(m["data_stored"]) * float(fx["free_stored"])
		m["data_stored"] = float(m["data_stored"]) - freed
		m["data_lost"] = float(m["data_lost"]) + freed
	if fx.has("gen_mult"):
		m["gen_mult"] = float(fx["gen_mult"])
		m["gen_mult_weeks"] = int(fx.get("gen_weeks", 1))
	if fx.has("ops_weeks"):
		var elapsed_ops := maxi(int(m["age"]) - int(m["cruise_weeks"]), 0)
		m["ops_weeks"] = maxi(int(m["ops_weeks"]) + int(fx["ops_weeks"]), elapsed_ops + 1)
		m["weeks_total"] = int(m["cruise_weeks"]) + int(m["ops_weeks"])
	if fx.has("cash"):
		state.cash += float(fx["cash"])
	if fx.has("science"):
		_credit(state, m, float(fx["science"]))
	if fx.has("health"):
		m["health"] = clampf(float(m["health"]) + float(fx["health"]), 0.0, 1.0)
	var cause := "TY_OPS_CAUSE_%s" % String(m["event"]).to_upper()
	if fx.has("risk") and state.rng.randf() < float(fx["risk"]):
		_lose(m, cause)
	elif float(m["health"]) <= 0.0:
		_lose(m, cause)
	state.news.push_front({"key": "TY_OPS_NEWS_AUTO" if auto else "TY_OPS_NEWS_DECIDED",
		"args": [String(m.get("code", "")), String(choices[index]["key"])]})
	if not auto:
		if m["status"] == "lost":
			_finish(state, m)
		state.changed.emit()
	return true


# ------------------------------------------------------------ end of mission
static func _finish(state: TycoonState, m: Dictionary) -> void:
	var done: bool = m["status"] == "done"
	if done:
		var samples := float(type_ops(String(m["type"])).get("samples", 0.0))
		if samples > 0.0:
			_credit(state, m, samples * scientist_bonus(state))
			_log(m, "TY_OPS_LOG_SAMPLES")
	var gen := float(m["data_gen"])
	var ret := float(m["data_down"]) / gen if gen > 0.0 else (1.0 if done else 0.0)
	var ops_grade := 0.0
	if done:
		ops_grade = clampf(10.0 * (0.65 * ret + 0.35 * float(m["health"])), 0.0, 10.0)
	var entry := {
		"id": m.get("id", ""), "code": m.get("code", ""), "type": m.get("type", ""), "target": m.get("target", ""),
		"project_id": m.get("project_id", ""), "contract_id": m.get("contract_id", ""),
		"start_week": int(m["start_week"]), "end_week": state.weeks, "status": m["status"],
		"outcome": String(m.get("outcome", "full")) if done else "fail",
		"grade": float(m.get("grade", ops_grade)), "ops_grade": ops_grade,
		"science": float(m["science"]), "data_gen": gen, "data_down": float(m["data_down"]),
		"data_lost": float(m["data_lost"]) + (float(m["data_stored"]) if done else 0.0),
		"return": ret, "event": m.get("event", ""), "choice": int(m.get("choice", -1)), "cause": m.get("cause", ""),
		"antenna_level": antenna_level(state), "lesson": lesson(state, m)}
	state.mission_archive.append(entry)
	state.active_missions.erase(m)
	if done:
		state.news.push_front({"key": "TY_OPS_NEWS_DONE", "args": [String(entry["code"]), roundi(entry["science"])]})
	else:
		state.news.push_front({"key": "TY_OPS_NEWS_LOST", "args": [String(entry["code"]), String(entry["cause"])]})
	state.mission_completed.emit({"project_id": entry["project_id"], "code": entry["code"], "type": entry["type"],
		"target": entry["target"], "grade": entry["grade"], "success": done, "outcome": entry["outcome"],
		"contract_id": entry["contract_id"], "science": entry["science"], "mission_id": entry["id"],
		"status": entry["status"], "data_gen": gen, "data_down": entry["data_down"], "data_lost": entry["data_lost"]})


## The limiting factor of a mission (GDD 15.3): {"key", "args"} for the archive and report.
static func lesson(state: TycoonState, m: Dictionary) -> Dictionary:
	if m["status"] == "lost":
		return {"key": "TY_OPS_LIM_LOST", "args": [String(m.get("cause", "TY_OPS_CAUSE_FAULT"))]}
	var gen := float(m["data_gen"])
	if gen <= 0.0:
		return {"key": "TY_OPS_LIM_NONE", "args": []}
	var lost_pct := roundi(100.0 * (float(m["data_lost"]) + float(m["data_stored"])) / gen)
	if lost_pct >= 20:
		var lv := antenna_level(state)
		if lv < 3:
			var now := maxf(downlink_rate_at(m, lv), 0.001)
			var ratio := downlink_rate_at(m, lv + 1) / now
			return {"key": "TY_OPS_LIM_LINK", "args": [lost_pct, lv + 1, "%.1f" % ratio]}
		return {"key": "TY_OPS_LIM_STORAGE", "args": [lost_pct]}
	return {"key": "TY_OPS_LIM_OK", "args": [100 - lost_pct]}


# ------------------------------------------------------------ encyclopedia (GDD 15.1)
static func book_data() -> Dictionary:
	if _book.is_empty():
		_book = TycoonState.load_json(ENCYCLOPEDIA_PATH)
	return _book


## Encyclopedia cards with a checked source, each with "unlocked". Cards without a source
## (verified false or no url) never appear.
static func encyclopedia(state: TycoonState) -> Array[Dictionary]:
	var flown := {}
	for m in state.active_missions:
		flown[String(m.get("type", ""))] = true
	for m in state.mission_archive:
		flown[String(m.get("type", ""))] = true
	var out: Array[Dictionary] = []
	for c: Dictionary in book_data().get("cards", []):
		if not c.get("verified", false) or String(c.get("url", "")) == "":
			continue
		var card := c.duplicate()
		var on := false
		for t in c.get("types", []):
			on = on or flown.has(String(t))
		if c.has("antenna_level"):
			on = on or antenna_level(state) >= int(c["antenna_level"])
		card["unlocked"] = on
		out.append(card)
	return out
