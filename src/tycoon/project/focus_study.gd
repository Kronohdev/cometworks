class_name FocusStudy
extends RefCounted
## Mission studies ("Estudos de missão"): the lab's way to learn which quality bars a mission
## type leans on without flying it again and again (Game Dev Tycoon's research of a genre).
## Each type has three levels of knowledge, the focus tier:
##   1  the bar that matters most and the one that matters least
##   2  every bar's weight in words (a lot / some / a little) and, in each development phase,
##      which lever wants more or less of the team's time (arrows)
##   3  the exact ideal share of each bar (the marker on the meters), the lever ranges and the
##      balance match: the same as the journal knew after two flights
## Flying teaches too: one launch of the type gives tier 1, Discovery.ratio_known (two launches,
## a tech of payload.json reveal_by_tech, the dev menu) gives tier 3.
## A study of the next tier costs PP (from the lab's pool, shared with the tech being
## researched: the study draws first), a few weeks at least (cost / weeks per week) and some
## money paid when it starts; more researchers in the lab finish it sooner. Numbers in
## data/tycoon/research.json "studies". State:
##   TycoonState.discovery["study"]  {type: tier reached by studying}  (Discovery.d keeps it)
##   TycoonState.research["study"]   {"active": type or "", "progress": {type: PP of its next tier}}
## (a type with a progress entry has its next tier paid for). Pure rules, headless.

const MAX_TIER := 3
## tier-2 words for a bar's ideal share: "high" >= high_at, "low" <= low_at, else "mid"
const LEVELS: Array[String] = ["low", "mid", "high"]


static func cfg() -> Dictionary:
	return TycoonResearch.db().get("studies", {})


static func _known(s: TycoonState) -> Dictionary:
	var j := Discovery.d(s)
	if not j.has("study"):
		j["study"] = {}
	return j["study"]


static func _rs(s: TycoonState) -> Dictionary:
	var r := TycoonResearch.rs(s)
	if not r.has("study"):
		r["study"] = {"active": "", "progress": {}}
	return r["study"]


# ------------------------------------------------------------ what the agency knows
## The tier reached by studying alone (0..3).
static func studied(s: TycoonState, type_id: String) -> int:
	return clampi(int(_known(s).get(type_id, 0)), 0, MAX_TIER)


## What the agency knows of a type's ideal balance, 0..3 (studies, flights, techs, dev).
static func tier(s: TycoonState, type_id: String) -> int:
	if Discovery.ratio_known(s, type_id):
		return MAX_TIER
	var t := studied(s, type_id)
	if Discovery.attempts(s, type_id) >= int(cfg().get("flight_tier1", 1)):
		t = maxi(t, 1)
	return t


## The ideal of the mission type (never a briefing client's own: the story tells that one).
static func ideal(s: TycoonState, type_id: String) -> Array[float]:
	var r: Array = s.mission_type(type_id).get("ratio", [0.25, 0.25, 0.25, 0.25])
	var out: Array[float] = [0.25, 0.25, 0.25, 0.25]
	for b in mini(4, r.size()):
		out[b] = float(r[b])
	return out


## Bar indices of the largest share (ties included).
static func top_bars(s: TycoonState, type_id: String) -> Array[int]:
	return _extreme(ideal(s, type_id), true)


## Bar indices of the smallest share (ties included).
static func bottom_bars(s: TycoonState, type_id: String) -> Array[int]:
	return _extreme(ideal(s, type_id), false)


static func _extreme(v: Array[float], most: bool) -> Array[int]:
	var best := v[0]
	for x in v:
		best = maxf(best, x) if most else minf(best, x)
	var out: Array[int] = []
	for b in 4:
		if absf(v[b] - best) < 0.001:
			out.append(b)
	return out


## "high" | "mid" | "low": a bar's weight in words (tier 2).
static func level(s: TycoonState, type_id: String, bar: int) -> String:
	var v := ideal(s, type_id)[bar]
	if v >= float(cfg().get("high_at", 0.3)) - 0.001:
		return "high"
	if v <= float(cfg().get("low_at", 0.15)) + 0.001:
		return "low"
	return "mid"


## The balance the agency believes in at tier 2: the levels as shares (high / mid / low weights
## of studies.level_share, normalised). Tier 3 knows the real one.
static func coarse_ideal(s: TycoonState, type_id: String) -> Array[float]:
	var share: Dictionary = cfg().get("level_share", {"high": 0.35, "mid": 0.25, "low": 0.12})
	var out: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var t := 0.0
	for b in 4:
		out[b] = float(share.get(level(s, type_id, b), 0.25))
		t += out[b]
	for b in 4:
		out[b] /= maxf(t, 0.001)
	return out


## What the screens show for each bar at the agency's tier: [{"bar", "tier", "mark"
## ("top" | "bottom" | "high" | "mid" | "low" | "" unknown), "ideal" (tier 3, else -1)}].
static func bar_marks(s: TycoonState, type_id: String) -> Array[Dictionary]:
	var t := tier(s, type_id)
	var idl := ideal(s, type_id)
	var tops := top_bars(s, type_id)
	var bottoms := bottom_bars(s, type_id)
	var out: Array[Dictionary] = []
	for b in 4:
		var mark := ""
		if t >= 2:
			mark = level(s, type_id, b)
		elif t == 1:
			mark = "top" if b in tops else ("bottom" if b in bottoms else "")
		out.append({"bar": b, "tier": t, "mark": mark, "ideal": idl[b] if t >= MAX_TIER else -1.0})
	return out


## The best lever split of phase k for what the agency knows (tier 2: the coarse balance,
## tier 3: the real one): [best % x 3], [] below tier 2.
static func best_split(s: TycoonState, type_id: String, k: int) -> Array[int]:
	var t := tier(s, type_id)
	var out: Array[int] = []
	if t < 2:
		return out
	var r: Array = Discovery.lever_ranges(ideal(s, type_id) if t >= MAX_TIER else coarse_ideal(s, type_id))[clampi(k, 0, 2)]
	for i in 3:
		out.append(int(r[i][2]))
	return out


## The lever arrows of phase k (tier 2+): +1 more time here, -1 less, 0 about a third each.
static func lever_arrows(s: TycoonState, type_id: String, k: int) -> Array[int]:
	var best := best_split(s, type_id, k)
	var out: Array[int] = []
	if best.is_empty():
		return out
	var hi := int(cfg().get("arrow_up", 45))
	var lo := int(cfg().get("arrow_down", 20))
	for v in best:
		out.append(1 if v >= hi else (-1 if v <= lo else 0))
	return out


## The lever of phase k that feeds the most important bar most (tier 1+): -1 when unknown.
static func focus_lever(s: TycoonState, type_id: String, k: int) -> int:
	if tier(s, type_id) < 1:
		return -1
	var tops := top_bars(s, type_id)
	var m := ProjectRules.feed_matrix(k)
	var best := -1
	var best_w := 0.0
	for i in m.size():
		var w := 0.0
		for b in tops:
			w += float(m[i][b])
		if w > best_w + 0.001:
			best_w = w
			best = i
	return best


# ------------------------------------------------------------ studying
## Costs of studying `type_id` up to tier `to_tier` (1..3): {"pp", "weeks", "cash"} (scaled by
## the era of the type: studies.era_mult).
static func cost(s: TycoonState, type_id: String, to_tier: int) -> Dictionary:
	var c := cfg()
	var tiers: Array = c.get("tiers", [])
	if tiers.is_empty() or to_tier < 1:
		return {"pp": 0.0, "weeks": 0, "cash": 0.0}
	var td: Dictionary = tiers[clampi(to_tier - 1, 0, tiers.size() - 1)]
	var em: Array = c.get("era_mult", [1.0])
	var era := int(s.mission_type(type_id).get("era", 1))
	var m := float(em[clampi(era - 1, 0, em.size() - 1)])
	var cm: Array = c.get("cash_era_mult", em)
	var mc := float(cm[clampi(era - 1, 0, cm.size() - 1)])
	return {"pp": roundf(float(td.get("pp", 10)) * m), "weeks": int(td.get("weeks", 2)), "cash": roundf(float(td.get("cash", 5000)) * mc)}


static func next_tier(s: TycoonState, type_id: String) -> int:
	return tier(s, type_id) + 1


## Can the type be studied: one the agency can fly (or has flown), not fully known.
static func can_study(s: TycoonState, type_id: String) -> bool:
	if s.mission_type(type_id).is_empty() or tier(s, type_id) >= MAX_TIER:
		return false
	return s.mission_type_available(type_id) or Discovery.attempts(s, type_id) > 0


static func active(s: TycoonState) -> String:
	return String(_rs(s).get("active", ""))


static func progress(s: TycoonState, type_id: String) -> float:
	return float((_rs(s)["progress"] as Dictionary).get(type_id, 0.0))


static func paid(s: TycoonState, type_id: String) -> bool:
	return (_rs(s)["progress"] as Dictionary).has(type_id)


## 0..1 of the next tier.
static func fraction(s: TycoonState, type_id: String) -> float:
	var c := cost(s, type_id, next_tier(s, type_id))
	return clampf(progress(s, type_id) / maxf(float(c["pp"]), 0.001), 0.0, 1.0) if tier(s, type_id) < MAX_TIER else 1.0


## Why the study cannot start ("" when it can): a translation key.
static func start_error(s: TycoonState, type_id: String) -> String:
	if not can_study(s, type_id):
		return "TY_ST_ERR_KNOWN" if tier(s, type_id) >= MAX_TIER else "TY_ST_ERR_LOCKED"
	if not paid(s, type_id) and s.cash < float(cost(s, type_id, next_tier(s, type_id))["cash"]):
		return "TY_ST_ERR_CASH"
	return ""


## Starts (or resumes) studying the type's next tier; the money is paid the first time.
## Another study in progress pauses (its progress is kept). False when start_error() says no.
static func start(s: TycoonState, type_id: String) -> bool:
	if start_error(s, type_id) != "":
		return false
	var st := _rs(s)
	if not paid(s, type_id):
		TycoonFinance.add(s, "projects", -float(cost(s, type_id, next_tier(s, type_id))["cash"]))
		(st["progress"] as Dictionary)[type_id] = 0.0
	st["active"] = type_id
	s.changed.emit()
	return true


## Stops the active study (progress and payment kept).
static func stop(s: TycoonState) -> void:
	_rs(s)["active"] = ""
	s.changed.emit()


## Most PP the study takes in a week (cost / weeks).
static func weekly_cap(s: TycoonState, type_id: String) -> float:
	var c := cost(s, type_id, next_tier(s, type_id))
	return float(c["pp"]) / maxf(float(c["weeks"]), 1.0)


## Weeks until the active tier is done at today's lab output (-1: never).
static func weeks_left(s: TycoonState, type_id: String) -> int:
	if tier(s, type_id) >= MAX_TIER:
		return 0
	var left := float(cost(s, type_id, next_tier(s, type_id))["pp"]) - progress(s, type_id)
	var pool := s.research_points
	var ppw := TycoonResearch.pp_per_week(s)
	var cap := weekly_cap(s, type_id)
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


## One week (TycoonResearch.weekly, after the lab made its PP and before the tech draws):
## the active study draws from the pool and may reach its tier.
static func weekly(s: TycoonState) -> void:
	var st := _rs(s)
	var id := String(st.get("active", ""))
	if id == "":
		return
	if not can_study(s, id) or not paid(s, id):
		st["active"] = ""
		return
	var need := float(cost(s, id, next_tier(s, id))["pp"])
	var draw := minf(minf(s.research_points, need - progress(s, id)), weekly_cap(s, id))
	if draw > 0.0:
		(st["progress"] as Dictionary)[id] = progress(s, id) + draw
		s.research_points -= draw
	if progress(s, id) >= need - 0.001:
		complete_tier(s, id)


## The next tier of the type is learned (also the dev menu): the journal and the news say so.
static func complete_tier(s: TycoonState, type_id: String) -> void:
	var t := tier(s, type_id)
	if t >= MAX_TIER or s.mission_type(type_id).is_empty():
		return
	var st := _rs(s)
	_known(s)[type_id] = t + 1
	(st["progress"] as Dictionary).erase(type_id)
	if String(st.get("active", "")) == type_id:
		st["active"] = ""
	var tname := String(s.mission_type(type_id).get("name_key", type_id))
	Discovery.note(s, "TY_JN_NOTE_STUDY_%d" % (t + 1), [tname])
	s.news.push_front({"key": "TY_NEWS_STUDY", "args": [tname, t + 1]})
	s.changed.emit()


## Dev menu: every type the agency can fly (or every type with `all_types`) fully studied.
static func reveal_all(s: TycoonState, all_types := false) -> int:
	var n := 0
	for t: Dictionary in s.mdata.get("types", []):
		var id := String(t["id"])
		if not all_types and not can_study(s, id):
			continue
		while tier(s, id) < MAX_TIER:
			complete_tier(s, id)
			n += 1
	return n


# ------------------------------------------------------------ advice
## Why a bar runs low with this team (independent of the hidden ideal): bars no one on the
## team has as their profession's primary bar. Returns bar indices.
static func orphan_bars(s: TycoonState, staff_ids: Array) -> Array[int]:
	var out: Array[int] = []
	for b in 4:
		var has := false
		for m in s.staff:
			if String(m.get("id", "")) in staff_ids \
					and String(s.profession(String(m.get("profession", ""))).get("primary", "")) == ProjectRules.BARS[b]:
				has = true
		if not has:
			out.append(b)
	return out


## Is the bar one the agency knows the type leans on (tier 1 top, tier 2 "high", tier 3 >= bar_min)?
static func known_important(s: TycoonState, type_id: String, bar: int) -> bool:
	var t := tier(s, type_id)
	if t >= MAX_TIER:
		return ideal(s, type_id)[bar] >= float(BriefingDesk.disc().get("team", {}).get("bar_min", 0.25)) - 0.001
	if t == 2:
		return level(s, type_id, bar) == "high"
	if t == 1:
		return bar in top_bars(s, type_id)
	return false


## Is the bar one the agency knows the type barely needs (tier 1 bottom, tier 2 "low", tier 3
## below bar_min)?
static func known_unimportant(s: TycoonState, type_id: String, bar: int) -> bool:
	var t := tier(s, type_id)
	if t >= MAX_TIER:
		return ideal(s, type_id)[bar] < float(BriefingDesk.disc().get("team", {}).get("bar_min", 0.25)) - 0.001
	if t == 2:
		return level(s, type_id, bar) == "low"
	if t == 1:
		return bar in bottom_bars(s, type_id)
	return false
