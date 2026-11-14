class_name TycoonContracts
extends RefCounted
## Contract board (GDD sections 6.1, 12 and 15.4): 3 to 6 offers renewed every month from
## the mission types and targets the agency can fly, from government programmes, commercial
## clients and the Space Apps inspired family; accept / decline; the deadline (penalty when it
## passes); rivals taking commercial offers before the player; paying the reward, the bonus
## (grade >= 8) or the penalty when the mission ends (TycoonState.complete_contract).
## Contracts live in `TycoonState.contracts` (schema there) with these extra keys:
##   "sponsor" (sponsor or Space Apps id), "kind" ("government" | "commercial" | "space_apps"),
##   "weeks_allowed", "offered_week", "accepted_week", "grade", "late" (bool), "pp" (science
##   bonus of Space Apps contracts), "problem_key" / "data_key" (Space Apps texts).
## Board bookkeeping in `TycoonState.contract_board`: {"seq": int, "month": month key}.

const PATH := "res://data/tycoon/contracts.json"

static var _db: Dictionary = {}


static func db() -> Dictionary:
	if _db.is_empty():
		_db = TycoonState.load_json(PATH)
	return _db


static func board(s: TycoonState) -> Dictionary:
	if s.contract_board.is_empty():
		s.contract_board = {"seq": 0, "month": -1}
	return s.contract_board


static func sponsor(id: String) -> Dictionary:
	for sp: Dictionary in db().get("sponsors", []):
		if sp["id"] == id:
			return sp
	for sp: Dictionary in db().get("space_apps", []):
		if sp["id"] == id:
			return sp
	return {}


static func find(s: TycoonState, id: String) -> Dictionary:
	for c in s.contracts:
		if String(c.get("id", "")) == id:
			return c
	return {}


static func with_status(s: TycoonState, status: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in s.contracts:
		if String(c.get("status", "")) == status:
			out.append(c)
	return out


static func offers(s: TycoonState) -> Array[Dictionary]:
	return with_status(s, "offer")


static func accepted(s: TycoonState) -> Array[Dictionary]:
	return with_status(s, "accepted")


## Contracts the agency can hold at the same time: base + HQ level + research effects.
static func max_active(s: TycoonState) -> int:
	return int(db().get("active_base", 1)) + int(s.building("hq").get("level", 1)) \
		+ int(TycoonResearch.effect(s, "contract_slots"))


static func can_accept(s: TycoonState, id: String) -> bool:
	var c := find(s, id)
	return not c.is_empty() and String(c["status"]) == "offer" and accepted(s).size() < max_active(s) \
		and s.mission_type_available(String(c["type"])) and s.mission_target_available(String(c["target"])) \
		and TycoonResearch.pair_available(s, String(c["type"]), String(c["target"]))


static func accept(s: TycoonState, id: String) -> bool:
	if not can_accept(s, id):
		return false
	var c := find(s, id)
	c["status"] = "accepted"
	c["accepted_week"] = s.weeks
	c["deadline_week"] = s.weeks + int(c["weeks_allowed"])
	if String(c.get("kind", "")) == "space_apps":
		s.news.push_front({"key": "TY_NEWS_SA_SIGNED", "args": [String(c["sponsor_key"])]})
	else:
		s.news.push_front({"key": "TY_NEWS_CONTRACT_SIGNED", "args": [String(c["sponsor_key"]), _what_key(c)]})
	s.changed.emit()
	return true


static func decline(s: TycoonState, id: String) -> bool:
	var c := find(s, id)
	if c.is_empty() or String(c["status"]) != "offer":
		return false
	s.contracts.erase(c)
	s.changed.emit()
	return true


static func _what_key(c: Dictionary) -> String:
	return String(TycoonResearch._mission_key("types", String(c["type"])))


## Does a project's bar grades ({"eng": 7.2, ...}, 0..10) meet the contract's minimums?
static func meets_requirements(c: Dictionary, bar_grades: Dictionary) -> bool:
	var mins: Dictionary = c.get("min_bars", {})
	for b: String in mins:
		if float(bar_grades.get(b, 0.0)) < float(mins[b]):
			return false
	return true


# ------------------------------------------------------------ completion
## A mission tied to a contract ended: success pays the reward (plus the bonus when the grade
## reaches bonus_grade) and reputation; failure costs the penalty and reputation. Space Apps
## contracts also return science as research points.
static func complete(s: TycoonState, id: String, grade: float, success: bool) -> void:
	var c := find(s, id)
	if c.is_empty() or String(c["status"]) != "accepted":
		return
	var d := db()
	var sp := sponsor(String(c["sponsor"]))
	c["grade"] = grade
	if success:
		c["status"] = "done"
		TycoonFinance.add(s, "contracts", float(c["reward"]))
		var rep := float(sp.get("rep", d.get("rep_success", 2.0)))
		if grade >= float(d.get("bonus_grade", 8.0)):
			TycoonFinance.add(s, "bonus", float(c["bonus"]))
			rep += float(d.get("rep_bonus", 1.0))
		s.reputation = clampf(s.reputation + rep, 0.0, 100.0)
		s.research_points += float(c.get("pp", 0.0))
		var paid := float(c["reward"]) + (float(c["bonus"]) if grade >= float(d.get("bonus_grade", 8.0)) else 0.0)
		s.news.push_front({"key": "TY_NEWS_SA_DONE" if String(c.get("kind", "")) == "space_apps" else "TY_NEWS_CONTRACT_DONE",
			"args": [String(c["sponsor_key"]), TycoonHUD.fmt_cr(paid)]})
	else:
		_fail(s, c, false)
	_prune(s)
	s.changed.emit()


static func _fail(s: TycoonState, c: Dictionary, late: bool) -> void:
	var d := db()
	c["status"] = "failed"
	c["late"] = late
	TycoonFinance.add(s, "penalties", -float(c["penalty"]))
	s.reputation = clampf(s.reputation + float(d.get("rep_late" if late else "rep_fail", -3.0)), 0.0, 100.0)
	s.news.push_front({"key": "TY_NEWS_CONTRACT_LATE" if late else "TY_NEWS_CONTRACT_FAILED",
		"args": [String(c["sponsor_key"]), TycoonHUD.fmt_cr(float(c["penalty"]))]})


## Keeps the last `keep_history` finished contracts.
static func _prune(s: TycoonState) -> void:
	var keep := int(db().get("keep_history", 30))
	var finished: Array[Dictionary] = []
	for c in s.contracts:
		if String(c["status"]) in ["done", "failed"]:
			finished.append(c)
	while finished.size() > keep:
		s.contracts.erase(finished.pop_front())


# ------------------------------------------------------------ weekly / monthly
## Deadlines and rivals, every week.
static func weekly(s: TycoonState) -> void:
	var late := false
	for c in accepted(s):
		if s.weeks > int(c.get("deadline_week", 0)):
			_fail(s, c, true)
			late = true
	if late:
		_prune(s)
	# rivals take commercial offers (GDD 6.1): an offer may vanish before the player signs it
	var p := float(db().get("rival_take_week", 0.05))
	for c in offers(s):
		if String(c.get("kind", "")) != "commercial" or s.rivals.is_empty():
			continue
		if s.rng.randf() < p:
			var rv := _pick_rival(s)
			s.contracts.erase(c)
			s.news.push_front({"key": "TY_NEWS_RIVAL_CONTRACT", "args": [String(rv.get("name_key", "")), String(c["sponsor_key"])]})


static func _pick_rival(s: TycoonState) -> Dictionary:
	var tot := 0.0
	for r in s.rivals:
		tot += float(r.get("capacity", 1.0))
	var x := s.rng.randf() * tot
	for r in s.rivals:
		x -= float(r.get("capacity", 1.0))
		if x <= 0.0:
			return r
	return s.rivals[-1]


## Renews the board when the month changed (or it was never filled).
static func ensure_offers(s: TycoonState) -> void:
	var k := TycoonFinance.month_key(s)
	if int(board(s)["month"]) != k:
		renew(s)


## New month: the unsigned offers go away and 3..6 new ones arrive.
static func renew(s: TycoonState) -> void:
	board(s)["month"] = TycoonFinance.month_key(s)
	for c in offers(s):
		s.contracts.erase(c)
	var d := db()
	var n := s.rng.randi_range(int(d.get("offers_min", 3)), int(d.get("offers_max", 6)))
	# a Space Apps contract first, when one fits what the agency can fly
	if s.rng.randf() < float(d.get("space_apps_chance", 0.45)):
		var sa := _space_apps_offer(s)
		if not sa.is_empty():
			s.contracts.append(sa)
			n -= 1
	var tries := 0
	while n > 0 and tries < 40:
		tries += 1
		var c := _regular_offer(s)
		if c.is_empty():
			continue
		s.contracts.append(c)
		n -= 1


static func _available_pairs(s: TycoonState, types: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in s.mdata.get("types", []):
		var tid := String(t["id"])
		if not types.is_empty() and not tid in types:
			continue
		if not s.mission_type_available(tid):
			continue
		var compat: Dictionary = t.get("compat", {})
		for tg: String in compat:
			# (and some rocket of the agency gets there, E2)
			if float(compat[tg]) >= 1.0 and s.mission_target_available(tg) and TycoonResearch.pair_available(s, tid, tg) \
					and RocketDesigner.reachable(s, tid, tg):
				# newer types are more wanted: weight 1 + 2 when the type is of the current era
				out.append({"type": tid, "target": tg, "w": 1.0 + (2.0 if int(t.get("era", 1)) >= s.era() else 0.0)})
	return out


static func _pick_weighted(s: TycoonState, items: Array) -> Dictionary:
	var tot := 0.0
	for it: Dictionary in items:
		tot += float(it.get("w", 1.0))
	var x := s.rng.randf() * tot
	for it: Dictionary in items:
		x -= float(it.get("w", 1.0))
		if x <= 0.0:
			return it
	return items[-1] if not items.is_empty() else {}


static func _new_id(s: TycoonState) -> String:
	var b := board(s)
	b["seq"] = int(b["seq"]) + 1
	return "c%d" % int(b["seq"])


static func _reward(s: TycoonState, type_id: String, mult: float) -> float:
	var d := db()
	var em: Array = d.get("era_mult", [1.0])
	var r := float(d.get("reward_base", 140000)) * float(s.mission_type(type_id).get("size", 1.0)) \
		* float(em[clampi(s.era() - 1, 0, em.size() - 1)]) * mult * s.rng.randf_range(0.9, 1.2) \
		* TycoonDifficulty.factor(s, "income")
	var step := float(d.get("round_to", 5000))
	return maxf(roundf(r / step) * step, step)


static func _base(s: TycoonState, type_id: String, target: String, reward: float) -> Dictionary:
	var d := db()
	var t := s.mission_type(type_id)
	var allowed := int(round(float(t.get("weeks", 4)) * float(d.get("deadline_mult", 3.0)))) \
		+ int(d.get("deadline_extra", 8)) + s.rng.randi_range(0, 4)
	return {"id": _new_id(s), "type": type_id, "target": target, "reward": reward,
		"bonus": roundf(reward * float(d.get("bonus_frac", 0.25))),
		"penalty": roundf(reward * float(d.get("penalty_frac", 0.3))),
		"weeks_allowed": allowed, "offered_week": s.weeks, "deadline_week": s.weeks + allowed, "status": "offer"}


static func _regular_offer(s: TycoonState) -> Dictionary:
	var d := db()
	var sp_list: Array = d.get("sponsors", [])
	var sp: Dictionary = sp_list[s.rng.randi_range(0, sp_list.size() - 1)]
	var pairs := _available_pairs(s, sp.get("types", []))
	if pairs.is_empty():
		return {}
	var pick := _pick_weighted(s, pairs)
	var c := _base(s, String(pick["type"]), String(pick["target"]), _reward(s, String(pick["type"]), float(sp.get("reward_mult", 1.0))))
	c["sponsor"] = sp["id"]
	c["sponsor_key"] = sp["name_key"]
	c["kind"] = sp["kind"]
	# 1 or 2 minimum bar grades from what the sponsor cares about
	var bars: Array = sp.get("bars", ["eng"])
	var mins := {}
	var nb := mini(bars.size(), s.rng.randi_range(1, 2))
	for i in nb:
		var v := float(d.get("min_bar_base", 4.5)) + float(d.get("min_bar_per_era", 0.4)) * (s.era() - 1) + s.rng.randf_range(0.0, 1.5)
		mins[String(bars[i])] = minf(roundf(v * 2.0) / 2.0, 8.0)
	c["min_bars"] = mins
	return c


static func _space_apps_offer(s: TycoonState) -> Dictionary:
	var fits: Array[Dictionary] = []
	for sa: Dictionary in db().get("space_apps", []):
		if not s.mission_type_available(String(sa["type"])) or not s.mission_target_available(String(sa["target"])):
			continue
		var busy := false
		for c in s.contracts:
			if String(c.get("sponsor", "")) == sa["id"] and String(c["status"]) in ["offer", "accepted"]:
				busy = true
		if not busy:
			fits.append(sa)
	if fits.is_empty():
		return {}
	var sa: Dictionary = fits[s.rng.randi_range(0, fits.size() - 1)]
	var c := _base(s, String(sa["type"]), String(sa["target"]), _reward(s, String(sa["type"]), float(sa.get("reward_mult", 1.1))))
	c["sponsor"] = sa["id"]
	c["sponsor_key"] = sa["name_key"]
	c["kind"] = "space_apps"
	c["min_bars"] = (sa.get("bars", {}) as Dictionary).duplicate()
	c["pp"] = float(sa.get("pp", 0)) * s.era()
	c["problem_key"] = sa.get("problem_key", "")
	c["data_key"] = sa.get("data_key", "")
	return c
