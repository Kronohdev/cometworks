class_name BriefingDesk
extends RefCounted
## Mission briefings (data/tycoon/briefings.json): the cards clients, scientists, the race and
## the Cometlings' dreams hand the agency. Each tells a situation and a goal with a deadline and
## a budget, never the answer; its hidden solution (targets, types, needed modules, maybe the
## client's own ideal balance) is scored by MissionFit. The board holds `board.size` offers,
## each for a while (offer_weeks); a project started for one takes it off the board; when the
## project launches the briefing pays by how well it went (goal met, partly, late, over budget).
## Board state lives in TycoonState.discovery (Discovery.d): "board" [offers], "taken" {id:
## project id}, "done" {id: best grade}. Random picks use a generator seeded from the campaign
## seed and the week, so the shared campaign rng is left alone.

const PATH := "res://data/tycoon/briefings.json"

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(PATH)
		_by_id.clear()
		for b: Dictionary in _data.get("briefings", []):
			_by_id[String(b["id"])] = b
	return _data


static func briefings() -> Array:
	return data().get("briefings", [])


static func briefing(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


## The discovery tunables (briefings.json "discovery").
static func disc() -> Dictionary:
	return data().get("discovery", {})


static func title_key(id: String) -> String:
	return "TY_BF_%s_TITLE" % id.to_upper()


static func story_key(id: String) -> String:
	return "TY_BF_%s_STORY" % id.to_upper()


static func goal_key(id: String) -> String:
	return "TY_BF_%s_GOAL" % id.to_upper()


static func kind_key(kind: String) -> String:
	return "TY_BF_KIND_" + kind.to_upper()


## Highest-scored key of a {id: score} dictionary.
static func best_of(d: Dictionary) -> String:
	var best := ""
	var bv := -1.0
	for k: String in d:
		if float(d[k]) > bv:
			bv = float(d[k])
			best = k
	return best


static func solution(b: Dictionary) -> Dictionary:
	return b.get("solution", {})


static func best_type(b: Dictionary) -> String:
	return best_of(solution(b).get("types", {}))


## The client's favourite target (the data keeps it one the best type can fly to).
static func best_target(b: Dictionary) -> String:
	return best_of(solution(b).get("targets", {}))


static func needs(b: Dictionary) -> Array:
	return solution(b).get("need", [])


## The client's own ideal balance (eng, sci, ops, rel), [] when the mission type's counts.
static func ratio(b: Dictionary) -> Array:
	return solution(b).get("ratio", [])


# ------------------------------------------------------------ board
## Can this briefing be offered now? Its era has come, it is not solved nor taken, the agency
## can fly its best type to its best target with a rocket it can build, and build its needs.
static func eligible(state: TycoonState, b: Dictionary) -> bool:
	var id := String(b.get("id", ""))
	var dd := Discovery.d(state)
	if int(b.get("era", 1)) > state.era() or is_solved(state, id) or (dd["taken"] as Dictionary).has(id):
		return false
	var ty := best_type(b)
	var tg := best_target(b)
	if not state.mission_type_available(ty) or not state.mission_target_available(tg) \
			or not TycoonResearch.pair_available(state, ty, tg):
		return false
	if ProjectRules.compat(state.mission_type(ty), tg) <= 0.0 or not RocketDesigner.reachable(state, ty, tg):
		return false
	for m in needs(b):
		if not PayloadRules.is_available(state, String(m)):
			return false
	return true


static func is_solved(state: TycoonState, id: String) -> bool:
	return float((Discovery.d(state)["done"] as Dictionary).get(id, -1.0)) >= goal_grade(briefing(id))


static func goal_grade(b: Dictionary) -> float:
	return float(b.get("goal_grade", 6.0))


static func offers(state: TycoonState) -> Array:
	ensure(state)
	return Discovery.d(state)["board"]


static func offer(state: TycoonState, id: String) -> Dictionary:
	for o: Dictionary in Discovery.d(state)["board"]:
		if String(o.get("id", "")) == id:
			return o
	return {}


static func _rng(state: TycoonState, salt := 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([state.campaign_seed, state.weeks, "briefings", salt])
	return r


## Once a week (ProjectDesk.advance_week): expired offers leave; every refresh_weeks (or when
## the board is empty) new ones come.
static func week(state: TycoonState) -> void:
	_prune(state)
	var every := maxi(int((data().get("board", {}) as Dictionary).get("refresh_weeks", 4)), 1)
	if state.weeks % every == 0 or (Discovery.d(state)["board"] as Array).is_empty():
		_fill(state)


## Keeps the board filled (the screens call this when they look at it).
static func ensure(state: TycoonState) -> void:
	_prune(state)
	_fill(state)


## Drops expired offers and those the agency can no longer take.
static func _prune(state: TycoonState) -> void:
	var board: Array = Discovery.d(state)["board"]
	for o: Dictionary in board.duplicate():
		var b := briefing(String(o.get("id", "")))
		if b.is_empty() or state.weeks >= int(o.get("expires_week", 0)) or (not o.get("dev", false) and not eligible(state, b)):
			board.erase(o)


## Adds offers up to the board size (newer eras and unseen briefings likelier).
static func _fill(state: TycoonState) -> void:
	var dd := Discovery.d(state)
	var board: Array = dd["board"]
	var cfg: Dictionary = data().get("board", {})
	var size := int(cfg.get("size", 3))
	if board.size() >= size:
		return
	var on := {}
	for o: Dictionary in board:
		on[String(o["id"])] = true
	var pool: Array[Dictionary] = []
	for b: Dictionary in briefings():
		if not on.has(String(b["id"])) and eligible(state, b):
			pool.append(b)
	var r := _rng(state)
	while board.size() < size and not pool.is_empty():
		var tot := 0.0
		for b in pool:
			tot += _weight(state, b)
		var x := r.randf() * tot
		var pick: Dictionary = pool[-1]
		for b in pool:
			x -= _weight(state, b)
			if x <= 0.0:
				pick = b
				break
		pool.erase(pick)
		board.append(make_offer(state, pick, r))


## Newer briefings (of the current era) and ones never seen are likelier.
static func _weight(state: TycoonState, b: Dictionary) -> float:
	var w := 1.0 + 2.0 * float(int(b.get("era", 1)) >= state.era())
	if not (Discovery.d(state)["done"] as Dictionary).has(String(b["id"])):
		w += 1.0
	return w


## An offer for a briefing: reward and budget priced for the current era, deadline, the
## Cometling who dreams it (dreams).
static func make_offer(state: TycoonState, b: Dictionary, r: RandomNumberGenerator = null) -> Dictionary:
	if r == null:
		r = _rng(state, 7)
	var d := data()
	var ty := best_type(b)
	var tg := best_target(b)
	var em: Array = d.get("era_mult", [1.0])
	var step := float(d.get("round_to", 5000))
	var reward := float(d.get("reward_base", 140000)) * float(state.mission_type(ty).get("size", 1.0)) \
		* float(em[clampi(state.era() - 1, 0, em.size() - 1)]) * float(b.get("reward_mult", 1.0)) 		* TycoonDifficulty.factor(state, "income")
	if String(b.get("client", "")).begins_with("TY_SP_GOV"):   # a mentor's voice in the council (TycoonLegends)
		reward *= 1.0 + TycoonLegends.mentor_effect(state, "gov_reward")
	reward = maxf(roundf(reward / step) * step, step)
	var est := ProjectDesk.estimate(state, ty, {}, tg)
	var budget := float(d.get("budget_mult", 1.7)) * (float(est["total"]) + PayloadRules.cost(PayloadRules.default_payload(state, ty, tg)))
	budget = maxf(roundf(budget / step) * step, step)
	var ow: Array = (d.get("board", {}) as Dictionary).get("offer_weeks", [18, 30])
	var o := {"id": String(b["id"]), "offered_week": state.weeks,
		"expires_week": state.weeks + r.randi_range(int(ow[0]), int(ow[1])), "reward": reward, "budget": budget,
		"deadline": int(b.get("deadline", 30)), "client": ""}
	if String(b.get("kind", "")) == "dream":
		var names: Array[String] = []
		for m in state.staff:
			names.append(String(m.get("name", "")))
		o["client"] = names[r.randi_range(0, names.size() - 1)] if not names.is_empty() else "Cometling"
	return o


## The client's name as text for an offer.
static func client_text(o: Dictionary) -> String:
	var b := briefing(String(o.get("id", "")))
	var kind := String(b.get("kind", "science"))
	if kind == "dream":
		return TranslationServer.translate("TY_BF_CL_DREAM") % String(o.get("client", ""))
	var key := String(b.get("client", (data().get("clients", {}) as Dictionary).get(kind, "")))
	return TranslationServer.translate(key)


## Dev menu: puts a briefing on the board now (even out of its era or already solved), at the
## top. False if the id does not exist.
static func spawn(state: TycoonState, id: String) -> bool:
	var b := briefing(id)
	if b.is_empty():
		return false
	var dd := Discovery.d(state)
	(dd["taken"] as Dictionary).erase(id)
	(dd["done"] as Dictionary).erase(id)
	var board: Array = dd["board"]
	for o: Dictionary in board.duplicate():
		if String(o["id"]) == id:
			board.erase(o)
	var o := make_offer(state, b)
	o["expires_week"] = state.weeks + 52
	o["dev"] = true
	board.push_front(o)
	state.changed.emit()
	return true


# ------------------------------------------------------------ projects
## A project started for a briefing: the offer leaves the board (its terms go with the project).
static func take(state: TycoonState, id: String, project_id: String) -> Dictionary:
	var dd := Discovery.d(state)
	var o := offer(state, id)
	if o.is_empty():
		o = make_offer(state, briefing(id))
	(dd["board"] as Array).erase(offer(state, id))
	(dd["taken"] as Dictionary)[id] = project_id
	# the story told the place's environment: the journal keeps it
	for t in (briefing(id).get("teaches", {}) as Dictionary).get("env", []):
		(dd["env"] as Dictionary)[String(t)] = true
	return o


## The project was cancelled before it flew: the briefing can come back.
static func release(state: TycoonState, id: String) -> void:
	(Discovery.d(state)["taken"] as Dictionary).erase(id)


## The project launched: what the client pays. Returns {"met" ("full" | "partial" | "missed"),
## "reward", "late", "over_budget", "rep", "pp", "hype"} and pays it.
static func complete(state: TycoonState, p: MissionProject, grade: float, success: bool) -> Dictionary:
	var b := briefing(p.briefing_id)
	var out := {"met": "missed", "reward": 0.0, "late": false, "over_budget": false, "rep": 0.0, "pp": 0.0, "hype": 0.0}
	if b.is_empty():
		return out
	var d := data()
	var terms: Dictionary = p.briefing_terms
	var dd := Discovery.d(state)
	(dd["taken"] as Dictionary).erase(p.briefing_id)
	var done: Dictionary = dd["done"]
	done[p.briefing_id] = maxf(float(done.get(p.briefing_id, 0.0)), grade if success else 0.0)
	var frac := 0.0
	if success and grade >= goal_grade(b):
		out["met"] = "full"
		frac = 1.0 + (float(d.get("bonus_frac", 0.25)) if grade >= float(d.get("bonus_grade", 8.5)) else 0.0)
	elif success and grade >= float(d.get("partial_grade", 4.0)):
		out["met"] = "partial"
		frac = float(d.get("partial_reward", 0.5))
	var deadline := p.start_week + int(terms.get("deadline", b.get("deadline", 30)))
	out["late"] = state.weeks > deadline
	if out["late"]:
		frac *= float(d.get("late_reward", 0.5))
	var budget := float(terms.get("budget", 0.0))
	out["over_budget"] = budget > 0.0 and p.cost_spent > budget
	if out["over_budget"]:
		frac *= float(d.get("over_budget_reward", 0.8))
	var reward := roundf(float(terms.get("reward", 0.0)) * frac)
	out["reward"] = reward
	if reward > 0.0:
		TycoonFinance.add(state, "contracts", reward)
	var share := 1.0 if out["met"] == "full" else (0.5 if out["met"] == "partial" else 0.0)
	out["rep"] = float(b.get("rep", 1.0)) * share
	out["pp"] = float(b.get("pp", 0.0)) * share
	out["hype"] = float(b.get("hype", 0.0)) * share
	state.reputation = clampf(state.reputation + float(out["rep"]), 0.0, 100.0)
	state.research_points += float(out["pp"])
	state.hype = clampf(state.hype + float(out["hype"]), 0.0, 100.0)
	state.news.push_front({"key": "TY_BF_NEWS_" + String(out["met"]).to_upper(), "args": [title_key(p.briefing_id)]})
	return out
