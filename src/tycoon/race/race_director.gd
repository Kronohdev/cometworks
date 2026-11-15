class_name RaceDirector
extends RefCounted
## The race to the Moon (GDD section 13): the 15 milestones of data/tycoon/milestones.json,
## the three rival agencies of data/tycoon/rivals.json, the Tail Radio lines and the
## newspaper front pages, and the final score when the Mother-Ice passes (section 16.2).
## Pure data, no scene access: TycoonState owns one (`state.race`) and calls advance_week()
## once a week. The player takes milestones through the state's mission_launched /
## mission_completed results; the rivals are simulated in the abstract once a month with
## their own RNG, seeded from the campaign seed, so player choices never change their luck.
## Several agencies can take the same milestone: the first gets the prize, later ones a share.

## Someone took a milestone; `order` 0 = first.
signal claimed(milestone_id: String, by: String, order: int)
signal rival_failed(rival_id: String, milestone_id: String)
## A big event made the front page of "O Eco da Cauda" (see `pending_pages`).
signal front_page(page: Dictionary)
## The comet passed: `result` is score() plus the standings.
signal campaign_finished(result: Dictionary)

const MILESTONES_PATH := "res://data/tycoon/milestones.json"
const RIVALS_PATH := "res://data/tycoon/rivals.json"
const PLAYER := "player"
const OUTCOMES := ["fail", "partial", "full", "exceptional"]
const KEEP_PAGES := 40
const KEEP_SAMPLES := 60

var mdata: Dictionary = {}
var rdata: Dictionary = {}
var milestones: Array = []
var rng := RandomNumberGenerator.new()
## milestone id -> [{"by": "player" | rival id, "week": int}] in the order they were taken
var claims: Dictionary = {}
## rival id -> {"next": index of the milestone pursued, "cooldown": months, "fails": int, "dropped": [ids]}
var ai: Dictionary = {}
## science downlinked by the player's missions (sum of mission_completed "science")
var science_total := 0.0
## player's reputation, sampled monthly (last 5 years)
var rep_samples: Array = []
## front pages printed so far (newest first) and the ones not shown yet (oldest first)
var pages: Array = []
var pending_pages: Array = []
var finished := false
var final_result: Dictionary = {}
var _last_fail_page := -100000
var _state_ref: WeakRef


func _init(s: TycoonState = null, d: Dictionary = {}) -> void:
	mdata = TycoonState.load_json(MILESTONES_PATH)
	rdata = TycoonState.load_json(RIVALS_PATH)
	milestones = mdata.get("milestones", [])
	if s == null:
		return
	_state_ref = weakref(s)
	rng.seed = s.campaign_seed * 7919 + 104729
	for m: Dictionary in milestones:
		claims[m["id"]] = []
	for r: Dictionary in s.rivals:
		ai[String(r["id"])] = {"next": 0, "cooldown": 0, "fails": 0, "dropped": []}
	if not d.is_empty():
		_load(d)
	s.mission_launched.connect(_on_mission.bind("launched"))
	s.mission_completed.connect(_on_mission.bind("completed"))
	_sync_counters()


func _s() -> TycoonState:
	return _state_ref.get_ref() as TycoonState if _state_ref else null


# ------------------------------------------------------------ data
func milestone(id: String) -> Dictionary:
	for m: Dictionary in milestones:
		if m["id"] == id:
			return m
	return {}


func milestone_index(id: String) -> int:
	for i in milestones.size():
		if milestones[i]["id"] == id:
			return i
	return -1


## Rival definition: the rules.json entry (id, name_key, color, capacity) merged with its
## personality from rivals.json.
func rival(id: String) -> Dictionary:
	var out: Dictionary = {}
	var s := _s()
	if s:
		for r: Dictionary in s.rivals:
			if String(r["id"]) == id:
				out = r.duplicate()
	out.merge(rdata.get("rivals", {}).get(id, {}))
	return out


## Agency ids in board order: the player first, then the rivals.
func agencies() -> Array[String]:
	var out: Array[String] = [PLAYER]
	var s := _s()
	if s:
		for r: Dictionary in s.rivals:
			out.append(String(r["id"]))
	return out


## Display name of an agency: the player's name as is, a rival's translation key.
func agency_name(id: String) -> String:
	var s := _s()
	if id == PLAYER:
		return s.agency_name if s else "Cometworks"
	return String(rival(id).get("name_key", id))


## An agency's colour (its colour-blind friendly one when that mode is on, CwPalette.agency).
func agency_color(id: String) -> Color:
	if id == PLAYER:
		return CwPalette.agency("player", CwPalette.IGNITION)
	return CwPalette.agency(id, Color(String(rival(id).get("color", "#8c9ab5"))))


func claims_of(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in milestones:
		var list: Array = claims.get(m["id"], [])
		for i in list.size():
			if String(list[i]["by"]) == id:
				out.append({"milestone": m["id"], "week": int(list[i]["week"]), "order": i})
	return out


func has_claimed(milestone_id: String, by: String) -> bool:
	for c: Dictionary in claims.get(milestone_id, []):
		if String(c["by"]) == by:
			return true
	return false


## {"by", "week"} of the first agency to take the milestone, {} if nobody yet.
func first_of(milestone_id: String) -> Dictionary:
	var list: Array = claims.get(milestone_id, [])
	return list[0] if not list.is_empty() else {}


func firsts_of(id: String) -> int:
	var n := 0
	for m: Dictionary in milestones:
		if String(first_of(m["id"]).get("by", "")) == id:
			n += 1
	return n


## Index of the next milestone nobody has taken yet (milestones.size() when all are taken).
func frontier() -> int:
	for i in milestones.size():
		if (claims.get(milestones[i]["id"], []) as Array).is_empty():
			return i
	return milestones.size()


## Index of the milestone an agency works on next: a rival's current target, or the
## player's first milestone not yet taken.
func next_of(id: String) -> int:
	if ai.has(id):
		return int(ai[id]["next"])
	for i in milestones.size():
		if not has_claimed(milestones[i]["id"], id):
			return i
	return milestones.size()


func rival_state(id: String) -> Dictionary:
	return ai.get(id, {})


# ------------------------------------------------------------ weekly tick
## Called by TycoonState.advance_week() after the week moved on.
func advance_week() -> void:
	var s := _s()
	if s == null or finished:
		return
	if s.is_over():
		_finish()
		return
	if s._month_of(s.weeks - 1) != s._month_of(s.weeks):
		rep_samples.append(s.reputation)
		while rep_samples.size() > KEEP_SAMPLES:
			rep_samples.pop_front()
		_rivals_month()


func _rivals_month() -> void:
	var s := _s()
	var wpy := s.weeks_per_year()
	var yr := s.year()
	var grace := int(mdata.get("grace_years", 1))
	var leader := 0
	for id in agencies():
		leader = maxi(leader, claims_of(id).size())
	for r: Dictionary in s.rivals:
		var id := String(r["id"])
		var st: Dictionary = ai[id]
		if int(st["cooldown"]) > 0:
			st["cooldown"] = int(st["cooldown"]) - 1
			continue
		var idx := int(st["next"])
		if idx >= milestones.size():
			continue
		var m: Dictionary = milestones[idx]
		var p := rival(id)
		var yrs: Array = m.get("years", [1, 25])
		if yr > int(yrs[1]) + grace or not _requires_met(m, id):
			(st["dropped"] as Array).append(m["id"])
			st["next"] = idx + 1
			s.news.push_front({"key": "TY_RACE_NEWS_DROP", "args": [agency_name(id), m["name_key"]]})
			continue
		var crewed := bool(m.get("crewed", false))
		var gate := (int(yrs[0]) - 1) * wpy + int(p.get("delay_weeks", 0)) + (int(p.get("crewed_delay_weeks", 0)) if crewed else 0)
		if s.weeks < gate:
			continue
		var lag := clampf(float(leader - claims_of(id).size()) / 3.0, 0.0, 1.5)
		var push := 1.0
		if yr >= int(yrs[1]):
			push = float(rdata.get("push_late", 2.6))
		elif yr >= int(yrs[1]) - 1:
			push = float(rdata.get("push_last_year", 1.6))
		var chance := float(rdata.get("attempt_base", 0.12)) * float(p.get("capacity", 1.0)) * float(p.get("pace", 1.0)) \
			* (float(p.get("crewed_mult", 1.0)) if crewed else 1.0) / maxf(float(m.get("difficulty", 1.0)), 0.1) \
			* (1.0 + float(rdata.get("elastic", 0.5)) * lag) * push * TycoonDifficulty.factor(s, "rival_speed")
		if rng.randf() >= chance:
			continue
		var fail := float(rdata.get("fail_base", 0.5)) * (1.0 - float(p.get("reliability", 0.8))) * float(p.get("boldness", 1.0))
		if rng.randf() < fail:
			var sb: Array = p.get("setback_months", [3, 6])
			var months := rng.randi_range(int(sb[0]), int(sb[1]))
			st["cooldown"] = months
			st["fails"] = int(st["fails"]) + 1
			_leader_says(id, "FAIL")   # under the headline line (pushed first)
			s.news.push_front({"key": "TY_RACE_NEWS_FAIL", "args": [agency_name(id), m["name_key"]]})
			rival_failed.emit(id, String(m["id"]))
			# a spectacular miss on a milestone nobody holds yet makes the front page (once a year at most)
			if bool(m.get("front_page", false)) and first_of(m["id"]).is_empty() \
					and s.weeks - _last_fail_page >= int(rdata.get("fail_front_page_gap_weeks", 52)):
				_last_fail_page = s.weeks
				_print_page({"kind": "fail", "milestone": m["id"], "by": id, "months": months})
			continue
		st["next"] = idx + 1
		claim(String(m["id"]), id)


func _requires_met(m: Dictionary, by: String) -> bool:
	for req: String in m.get("requires", []):
		if not has_claimed(req, by):
			return false
	return true


# ------------------------------------------------------------ the player's missions
func _on_mission(result: Dictionary, on: String) -> void:
	if finished:
		return
	if on == "completed":
		science_total += float(result.get("science", 0.0))
	for m: Dictionary in milestones:
		if has_claimed(m["id"], PLAYER) or not _requires_met(m, PLAYER):
			continue
		for c: Dictionary in m.get("conditions", []):
			if matches(c, result, on):
				claim(String(m["id"]), PLAYER)
				break


static func outcome_rank(outcome: String) -> int:
	return OUTCOMES.find(outcome)


## Does a mission result satisfy one milestone condition?
static func matches(c: Dictionary, result: Dictionary, on: String) -> bool:
	if String(c.get("on", "completed")) != on:
		return false
	var types: Array = c.get("types", [])
	if not types.is_empty() and not types.has(String(result.get("type", ""))):
		return false
	var targets: Array = c.get("targets", [])
	if not targets.is_empty() and not targets.has(String(result.get("target", ""))):
		return false
	var outcome := String(result.get("outcome", "full" if bool(result.get("success", false)) else "fail"))
	if result.has("success") and not bool(result["success"]):
		outcome = "fail"
	return outcome_rank(outcome) >= outcome_rank(String(c.get("min_outcome", "partial")))


# ------------------------------------------------------------ claiming
## Records that `by` took a milestone (no-op if it already holds it): prize, reputation and
## hype for the player (full for the first, a share after), capacity for a rival, the radio
## line, the front page and the state's milestone_claimed signal.
func claim(milestone_id: String, by: String) -> bool:
	var s := _s()
	var m := milestone(milestone_id)
	if s == null or m.is_empty() or has_claimed(milestone_id, by):
		return false
	var list: Array = claims[milestone_id]
	var order := list.size()
	list.append({"by": by, "week": s.weeks})
	var share := 1.0 if order == 0 else float(mdata.get("second_share", 0.3))
	if by == PLAYER:
		var half := 1.0 if order == 0 else 0.5
		s.cash += float(m.get("prize", 0)) * share * TycoonDifficulty.factor(s, "income")
		s.reputation = clampf(s.reputation + float(m.get("rep", 0)) * half, 0.0, 100.0)
		s.hype = clampf(s.hype + float(m.get("hype", 0)) * half, 0.0, 100.0)
	else:
		for r: Dictionary in s.rivals:
			if String(r["id"]) == by:
				r["capacity"] = float(r.get("capacity", 1.0)) * (1.0 + float(rdata.get("growth_first" if order == 0 else "growth_later", 0.03)))
	if order == 0:
		# a rival leader's word goes under the headline line (pushed first)
		if by == PLAYER:
			_leader_cheers(milestone_index(milestone_id))
		else:
			_leader_says(by, "FIRST")
		s.news.push_front({"key": "TY_RACE_NEWS_FIRST", "args": [agency_name(by), m["name_key"]]})
	else:
		s.news.push_front({"key": "TY_RACE_NEWS_LATER", "args": [agency_name(by), m["name_key"], order + 1]})
	_sync_counters()
	claimed.emit(milestone_id, by, order)
	s.milestone_claimed.emit(milestone_id, by)
	if order == 0 and (bool(m.get("front_page", false)) or by == PLAYER):
		_print_page({"kind": "first", "milestone": milestone_id, "by": by})
	s.changed.emit()
	return true


## A rival's leader (TycoonLegends) has a word on the Tail Radio: "<leader>: <line>", where
## `part` is FIRST (it took a first) or FAIL (an attempt went wrong).
func _leader_says(rival_id: String, part: String) -> void:
	var lid := TycoonLegends.rival_leader_id(rival_id)
	if lid != "" and _s():
		_s().news.push_front({"key": "TY_RACE_LEADER_SAYS", "args": [TycoonLegends.key(lid, "NAME"), TycoonLegends.key(lid, part)]})


## The player took a first: one rival leader (in turn, by milestone) sends a word.
func _leader_cheers(index: int) -> void:
	var s := _s()
	if s == null or s.rivals.is_empty():
		return
	var lid := TycoonLegends.rival_leader_id(String(s.rivals[posmod(index, s.rivals.size())]["id"]))
	if lid != "":
		s.news.push_front({"key": TycoonLegends.key(lid, "CHEER"), "args": [s.agency_name]})


## The leader Lenda of an agency ({} for the player and rivals without one).
func leader_of(id: String) -> Dictionary:
	return TycoonLegends.rival_leader(id) if id != PLAYER else {}


## Keeps TycoonState's plain counters (state.milestones, rivals[].milestones) in step, so
## race_board() and the HUD keep working.
func _sync_counters() -> void:
	var s := _s()
	if s == null:
		return
	s.milestones = claims_of(PLAYER).size()
	for r: Dictionary in s.rivals:
		r["milestones"] = claims_of(String(r["id"])).size()


# ------------------------------------------------------------ newspaper
## The player's rocket failed (ProjectDesk.launch, E2): a front page of kind "launch_fail"
## that names what broke (the Design Review's risk: "cause_key") and the odds it had.
func report_launch_failure(entry: Dictionary) -> void:
	if finished or _s() == null:
		return
	_print_page({"kind": "launch_fail", "by": PLAYER, "code": String(entry.get("code", "")),
		"type": String(entry.get("type", "")), "target": String(entry.get("target", "")),
		"cause_key": String(entry.get("cause_key", "")), "p_success": float(entry.get("p_success", 0.0)),
		"rocket": String((entry.get("rocket", {}) as Dictionary).get("name", ""))})


func _print_page(page: Dictionary) -> void:
	var s := _s()
	page["week"] = s.weeks
	page["issue"] = pages.size() + 1
	pages.push_front(page)
	while pages.size() > KEEP_PAGES:
		pages.pop_back()
	pending_pages.append(page)
	front_page.emit(page)


## The oldest front page not shown yet ({} if none), removed from the queue.
func pop_page() -> Dictionary:
	return pending_pages.pop_front() if not pending_pages.is_empty() else {}


# ------------------------------------------------------------ the end
func _finish() -> void:
	var s := _s()
	finished = true
	s.news.push_front({"key": "TY_RACE_NEWS_COMET", "args": []})
	final_result = score()
	campaign_finished.emit(final_result)


## Race points of an agency: 1 per first, second_weight per later claim.
func race_points(id: String) -> float:
	var w2 := float(mdata.get("score", {}).get("second_weight", 0.3))
	var pts := 0.0
	for c in claims_of(id):
		pts += 1.0 if int(c["order"]) == 0 else w2
	return pts


func met_comet(id: String) -> bool:
	for m: Dictionary in milestones:
		if bool(m.get("victory", false)) and has_claimed(m["id"], id):
			return true
	return false


## Agencies ranked by race points (the comet rendezvous counts double), best first:
## [{"id", "name", "color", "points", "count", "firsts", "comet", "player"}]
func standings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in agencies():
		var pts := race_points(id) + (1.0 if met_comet(id) else 0.0)
		out.append({"id": id, "name": agency_name(id), "color": agency_color(id), "points": pts,
			"count": claims_of(id).size(), "firsts": firsts_of(id), "comet": met_comet(id), "player": id == PLAYER})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["points"]), float(b["points"])):
			return float(a["points"]) > float(b["points"])
		return bool(a["player"]) and not bool(b["player"]))
	return out


## Final score (GDD section 16.2), recomputable at any time:
## {"rows": [{"id", "key", "detail", "ratio" 0..1, "points", "max"}], "total", "max", "comet",
##  "comet_bonus", "standings", "rank"}
func score() -> Dictionary:
	var s := _s()
	var sc: Dictionary = mdata.get("score", {})
	var w: Dictionary = sc.get("weights", {})
	var n := maxi(milestones.size(), 1)
	var rows: Array[Dictionary] = []
	var race := race_points(PLAYER)
	rows.append(_row("race", "TY_SCORE_RACE", race / n, w, "%d / %d" % [claims_of(PLAYER).size(), n]))
	rows.append(_row("science", "TY_SCORE_SCIENCE", science_total / float(sc.get("science_ref", 3000)), w,
		"%d" % roundi(science_total)))
	var rep := s.reputation
	if not rep_samples.is_empty():
		rep = 0.0
		for v in rep_samples:
			rep += float(v)
		rep /= rep_samples.size()
	rows.append(_row("reputation", "TY_SCORE_REPUTATION", rep / 100.0, w, "%d" % roundi(rep)))
	rows.append(_row("cash", "TY_SCORE_CASH", s.cash / float(sc.get("cash_ref", 5000000)), w, "%d" % roundi(s.cash)))
	var levels := 0
	for m in s.staff:
		levels += int(m.get("level", 1))
	rows.append(_row("cometlings", "TY_SCORE_COMETLINGS", float(levels) / float(sc.get("cometlings_ref", 40)), w,
		"%d · Σ %d" % [s.staff.size(), levels]))
	var firsts := firsts_of(PLAYER)
	rows.append(_row("firsts", "TY_SCORE_FIRSTS", float(firsts) / float(sc.get("firsts_ref", 8)), w, "%d" % firsts))
	var total := 0
	var max_total := 0
	for r in rows:
		total += int(r["points"])
		max_total += int(r["max"])
	var comet := met_comet(PLAYER)
	var bonus := int(sc.get("comet_bonus", 200)) if comet else 0
	var st := standings()
	var rank := 1
	for i in st.size():
		if st[i]["player"]:
			rank = i + 1
	return {"rows": rows, "total": total + bonus, "max": max_total, "comet": comet, "comet_bonus": bonus,
		"standings": st, "rank": rank}


static func _row(id: String, key: String, ratio: float, w: Dictionary, detail: String) -> Dictionary:
	var r := clampf(ratio, 0.0, 1.0)
	var mx := int(w.get(id, 100))
	return {"id": id, "key": key, "detail": detail, "ratio": r, "points": roundi(r * mx), "max": mx}


# ------------------------------------------------------------ save / load
func to_dict() -> Dictionary:
	return {"rng_seed": str(rng.seed), "rng_state": str(rng.state), "claims": claims, "ai": ai,
		"science_total": science_total, "rep_samples": rep_samples, "pages": pages, "pending_pages": pending_pages,
		"finished": finished, "last_fail_page": _last_fail_page}


func _load(d: Dictionary) -> void:
	if d.has("rng_seed"):
		rng.seed = int(String(d["rng_seed"]))
	if d.has("rng_state"):
		rng.state = int(String(d["rng_state"]))
	for id: String in d.get("claims", {}):
		var list: Array = []
		for c: Dictionary in d["claims"][id]:
			list.append({"by": String(c["by"]), "week": int(c["week"])})
		claims[id] = list
	for id: String in d.get("ai", {}):
		var a: Dictionary = d["ai"][id]
		var dropped: Array = []
		for x in a.get("dropped", []):
			dropped.append(String(x))
		ai[id] = {"next": int(a.get("next", 0)), "cooldown": int(a.get("cooldown", 0)), "fails": int(a.get("fails", 0)),
			"dropped": dropped}
	science_total = float(d.get("science_total", 0.0))
	rep_samples = (d.get("rep_samples", []) as Array).duplicate()
	pages = _pages(d.get("pages", []))
	pending_pages = _pages(d.get("pending_pages", []))
	finished = bool(d.get("finished", false))
	_last_fail_page = int(d.get("last_fail_page", -100000))
	if finished:
		final_result = score()


static func _pages(list: Array) -> Array:
	var out: Array = []
	for p: Dictionary in list:
		var q := p.duplicate()
		for k in ["week", "issue", "months"]:
			if q.has(k):
				q[k] = int(q[k])
		out.append(q)
	return out
