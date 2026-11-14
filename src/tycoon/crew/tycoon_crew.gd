class_name TycoonCrew
extends RefCounted
## The agency's Cometlings as staff (GDD section 9): the hiring market, hiring and firing,
## XP and levels, morale and naps, specialisations and salaries. Pure data + rules on a
## TycoonState (no scene access), numbers in data/tycoon/crew.json.
##
## State lives in two places, both saved with the campaign:
##   state.staff  one Dictionary per Cometling (TycoonState.staff schema) plus the fields
##                added here: "adapt_weeks", "train_weeks", "specs" [spec ids], "busy_weeks"
##                (weeks in a row on a project), "napping", "hidden" [traits not yet known],
##                "seed" (look rhythm), "hired_week"
##   state.crew   {"rng_state", "next_id", "candidates": [...]}: the market and its own RNG,
##                seeded from the campaign seed, so crew draws never shift other systems'
##
## For the project system:
##   TycoonCrew.is_working(m)          false while napping, settling in or training
##   TycoonCrew.add_xp(state, id, xp)  XP for a Cometling (levels up, returns levels gained)
##   TycoonCrew.spec_effect(m, key)    summed effect of its specialisations ("points_eng",
##                                     "defects", "science", "downlink", "crew_risk", ...)
##   TycoonCrew.spec_effect_for(m, key, type, target)  the same with the forms that only count
##                                     on some missions (key_<type>, key_<target>, key_lunar)
##   TycoonCrew.points_mult(m, bar, type, target)  1 + spec bonus on a quality bar
##   TycoonCrew.team_effect(s, ids, key, type, target)  an effect summed over a team
## Who reads which effect: points_* / team_points / defects / defect_removal /
## secondary_affinity (MissionProject), crew_risk / rocket_rel (DesignReview), science /
## downlink (ProjectDesk -> MissionOps), research (TycoonResearch), team_xp / overwork_weeks /
## failure_morale (here).
## Morale reacts by itself to state.mission_launched (success / failure of a project whose id
## is in the members' "assigned").

const DATA_PATH := "res://data/tycoon/crew.json"
const TRAITS := ["skill", "curiosity", "courage"]

static var _data: Dictionary = {}
## dev menu only (src/dev/cw_dev.gd): hiring ignores the staff limit of the buildings
static var dev_ignore_limit := false


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(DATA_PATH)
	return _data


static func morale_rule(key: String, fallback := 0.0) -> float:
	return float(data().get("morale", {}).get(key, fallback))


# ------------------------------------------------------------ setup
## Makes sure the crew part of the state is ready (market, member fields, mission hooks).
## Every function here calls it, so an old save or a fresh campaign just works.
static func ensure(s: TycoonState) -> void:
	if not s.crew.has("rng_state"):
		var r := RandomNumberGenerator.new()
		r.seed = hash("crew:%d" % s.campaign_seed)
		s.crew = {"rng_state": str(r.state), "next_id": 1, "candidates": []}
		_new_market(s, r)
		_store(s, r)
	for m in s.staff:
		_fill(m)
	if not s.has_meta("crew_hooked"):
		s.set_meta("crew_hooked", true)
		var wr: WeakRef = weakref(s)
		s.mission_launched.connect(func(result: Dictionary) -> void:
			var st := wr.get_ref() as TycoonState
			if st:
				mission_result(st, result))


static func _fill(m: Dictionary) -> void:
	var defaults := {"adapt_weeks": 0, "train_weeks": 0, "specs": [], "busy_weeks": 0, "napping": false,
		"hidden": [], "seed": hash(String(m.get("id", ""))) % 100000, "hired_week": 0}
	for k: String in defaults:
		if not m.has(k):
			m[k] = defaults[k]
	for k in ["adapt_weeks", "train_weeks", "busy_weeks", "hired_week", "seed"]:
		m[k] = int(m[k])  # JSON numbers come back as floats


static func _rng(s: TycoonState) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("crew:%d" % s.campaign_seed)
	r.state = String(s.crew.get("rng_state", str(r.state))).to_int()
	return r


static func _store(s: TycoonState, r: RandomNumberGenerator) -> void:
	s.crew["rng_state"] = str(r.state)


# ------------------------------------------------------------ queries
static func find(s: TycoonState, staff_id: String) -> Dictionary:
	for m in s.staff:
		if String(m.get("id", "")) == staff_id:
			return m
	return {}


static func building_level(s: TycoonState, kind: String) -> int:
	var lv := 0
	for lot_id: String in s.buildings:
		var b: Dictionary = s.buildings[lot_id]
		if String(b.get("kind", "")) == kind:
			lv = maxi(lv, int(b.get("level", 0)))
	return lv


## Most staff the headquarters can hold (data: staff_limit_by_hq, by HQ level).
static func staff_limit(s: TycoonState) -> int:
	var lim: Array = data().get("staff_limit_by_hq", [0, 8, 12, 16])
	return int(lim[clampi(building_level(s, "hq"), 0, lim.size() - 1)])


static func training_level(s: TycoonState) -> int:
	return building_level(s, "training")


## Monthly salary of one Cometling (or candidate): by level and profession (same rule as
## TycoonState.monthly_salaries).
static func salary(s: TycoonState, m: Dictionary) -> float:
	var base := float(s.rules.get("salary_month_base", 4000))
	var step := float(s.rules.get("salary_level_step", 0.25))
	var mult := float(s.profession(String(m.get("profession", ""))).get("salary_mult", 1.0))
	return base * (1.0 + step * (int(m.get("level", 1)) - 1)) * mult


static func hire_fee(s: TycoonState, c: Dictionary) -> float:
	return salary(s, c) * float(data().get("hire_fee_salaries", 2.0))


static func profession_color(s: TycoonState, profession_id: String) -> Color:
	return Color(String(s.profession(profession_id).get("color", "#8c9ab5")))


## The creature role whose accessories fit a profession (hard hat, helmet, goggles, vest).
static func look_role(profession_id: String) -> String:
	return String(data().get("look_role", {}).get(profession_id, "ground"))


static func xp_per_level() -> float:
	return float(data().get("xp_per_level", 100))


static func max_level() -> int:
	return int(data().get("max_level", 6))


## 0..1 progress toward the next level (1 at the top level).
static func level_progress(m: Dictionary) -> float:
	if int(m.get("level", 1)) >= max_level():
		return 1.0
	return clampf((float(m.get("xp", 0.0)) - (int(m.get("level", 1)) - 1) * xp_per_level()) / xp_per_level(), 0.0, 1.0)


## Can this Cometling put points into a project this week?
static func is_working(m: Dictionary) -> bool:
	return not bool(m.get("napping", false)) and int(m.get("adapt_weeks", 0)) <= 0 \
		and int(m.get("train_weeks", 0)) <= 0


## "nap" | "adapting" | "training" | "busy" (on a project) | "idle"
static func status(m: Dictionary) -> String:
	if bool(m.get("napping", false)):
		return "nap"
	if int(m.get("adapt_weeks", 0)) > 0:
		return "adapting"
	if int(m.get("train_weeks", 0)) > 0:
		return "training"
	return "busy" if String(m.get("assigned", "")) != "" else "idle"


static func trait_known(m: Dictionary, trait_name: String) -> bool:
	return not (trait_name in m.get("hidden", []))


static func candidates(s: TycoonState) -> Array:
	ensure(s)
	return s.crew.get("candidates", [])


static func find_candidate(s: TycoonState, cand_id: String) -> Dictionary:
	for c: Dictionary in candidates(s):
		if String(c.get("id", "")) == cand_id:
			return c
	return {}


## Weeks until the market brings new candidates (the next month).
static func weeks_to_market(s: TycoonState) -> int:
	var k := 1
	while k < 8 and s._month_of(s.weeks + k) == s._month_of(s.weeks):
		k += 1
	return k


static func average_morale(s: TycoonState) -> float:
	if s.staff.is_empty():
		return 0.0
	var t := 0.0
	for m in s.staff:
		t += float(m.get("morale", 0.0))
	return t / s.staff.size()


# ------------------------------------------------------------ specialisations
static func spec(spec_id: String) -> Dictionary:
	for sp: Dictionary in data().get("specs", []):
		if sp["id"] == spec_id:
			return sp
	return {}


## The tiers a specialisation can be learned in: "tiers" [1, 2] or the single "tier".
static func spec_tiers(sp: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if sp.has("tiers"):
		for t in sp["tiers"]:
			out.append(int(t))
	else:
		out.append(int(sp.get("tier", 1)))
	return out


## Has the research opened this specialisation? (The ones no tech lists are there from the start.)
static func spec_researched(s: TycoonState, spec_id: String) -> bool:
	var tech := TycoonResearch.tech_for_spec(spec_id)
	return tech == "" or bool(s.unlocked.get("spec:" + spec_id, false)) or TycoonResearch.is_done(s, tech)


## Specs a Cometling can pick in a tier (1: level 3, by profession; 2: level 5, for anyone, or
## the professions it lists). With the state: only those the research has opened, and none it
## already has.
static func spec_options(m: Dictionary, tier: int, s: TycoonState = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sp: Dictionary in data().get("specs", []):
		if not (tier in spec_tiers(sp)):
			continue
		var profs: Array = sp.get("professions", [])
		if not profs.is_empty() and not (String(m.get("profession", "")) in profs):
			continue
		if s != null and (not spec_researched(s, String(sp["id"])) or String(sp["id"]) in m.get("specs", [])):
			continue
		out.append(sp)
	return out


## Specs of this tier the Cometling's profession could pick once research opens them (the
## crew sheet names them under the choice).
static func spec_locked(m: Dictionary, tier: int, s: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sp in spec_options(m, tier):
		if not spec_researched(s, String(sp["id"])):
			out.append(sp)
	return out


## The specialisation slots of a Cometling: [{"tier", "level" (needed), "unlocked",
## "chosen" (spec id or ""), "training_needed" (centre level), "can_choose", "reason"}].
static func spec_slots(s: TycoonState, m: Dictionary) -> Array[Dictionary]:
	var levels: Array = data().get("spec_levels", [3, 5])
	var need: Array = data().get("spec_training_level", [1, 2])
	var chosen: Array = m.get("specs", [])
	var out: Array[Dictionary] = []
	for i in levels.size():
		var slot := {"tier": i + 1, "level": int(levels[i]), "unlocked": int(m.get("level", 1)) >= int(levels[i]),
			"chosen": String(chosen[i]) if i < chosen.size() else "", "training_needed": int(need[i]),
			"can_choose": false, "reason": ""}
		if slot["chosen"] == "":
			if not slot["unlocked"]:
				slot["reason"] = "TY_CREW_SPEC_LOCKED"
			elif i > chosen.size():
				slot["reason"] = "TY_CREW_SPEC_ORDER"
			elif training_level(s) < int(need[i]):
				slot["reason"] = "TY_CREW_SPEC_NEED_TRAINING"
			elif int(m.get("train_weeks", 0)) > 0:
				slot["reason"] = "TY_CREW_SPEC_IN_TRAINING"
			else:
				slot["can_choose"] = true
		out.append(slot)
	return out


static func spec_cost(s: TycoonState, m: Dictionary) -> float:
	return salary(s, m) * float(data().get("spec_cost_salaries", 1.0))


## Does this Cometling have a specialisation waiting to be chosen?
static func spec_pending(s: TycoonState, m: Dictionary) -> bool:
	for slot in spec_slots(s, m):
		if slot["chosen"] == "" and slot["unlocked"] and String(slot["reason"]) != "TY_CREW_SPEC_ORDER":
			return true
	return false


## Sends a Cometling to the training centre to learn a specialisation. Returns "" when done,
## else the translation key of the reason.
static func choose_spec(s: TycoonState, staff_id: String, spec_id: String) -> String:
	ensure(s)
	var m := find(s, staff_id)
	if m.is_empty():
		return "TY_CREW_ERR_NONE"
	var specs: Array = m["specs"]
	var slots := spec_slots(s, m)
	if specs.size() >= slots.size():
		return "TY_CREW_ERR_NONE"
	var slot: Dictionary = slots[specs.size()]
	if not slot["can_choose"]:
		return String(slot["reason"])
	var ok := false
	for sp in spec_options(m, int(slot["tier"]), s):
		ok = ok or sp["id"] == spec_id
	if not ok:
		return "TY_CREW_ERR_NONE"
	var cost := spec_cost(s, m)
	if s.cash < cost:
		return "TY_CREW_ERR_CASH"
	s.cash -= cost
	specs.append(spec_id)
	m["train_weeks"] = maxi(int(data().get("spec_weeks", 2)) + int(TycoonLegends.mentor_effect(s, "spec_weeks")), 1)
	s.news.push_front({"key": "TY_CREW_NEWS_SPEC", "args": [String(m["name"]), "TY_CREW_SPEC_" + spec_id.to_upper()]})
	s.changed.emit()
	return ""


## Summed effect of a Cometling's specialisations (see data/tycoon/crew.json "effects").
static func spec_effect(m: Dictionary, key: String) -> float:
	var t := 0.0
	for spec_id in m.get("specs", []):
		t += float(spec(String(spec_id)).get("effects", {}).get(key, 0.0))
	return t + TycoonLegends.member_effect(m, key)   # a Lenda's unique specialisation


## The effect on a mission of this type at this target: the plain key plus its narrower forms,
## key_<type> (points_crewed_landing), key_<target> (points_comet, points_lunar_pole) and
## key_lunar for every Moon target (points_sci_lunar).
static func spec_effect_for(m: Dictionary, key: String, type_id := "", target_id := "") -> float:
	var t := spec_effect(m, key)
	if type_id != "":
		t += spec_effect(m, key + "_" + type_id)
	if target_id != "":
		t += spec_effect(m, key + "_" + target_id)
		if target_id.begins_with("lunar"):
			t += spec_effect(m, key + "_lunar")
	return t


## 1 + the spec bonus on a quality bar ("eng" | "sci" | "ops" | "rel"), with the bonuses that
## only count on some missions ("points" on every bar, "points_<bar>", their _type / _target forms).
static func points_mult(m: Dictionary, bar: String, type_id := "", target_id := "") -> float:
	return 1.0 + spec_effect_for(m, "points_" + bar, type_id, target_id) + spec_effect_for(m, "points", type_id, target_id)


## Sum of an effect over a team (staff ids) on a mission of this type at this target.
static func team_effect(s: TycoonState, staff_ids: Array, key: String, type_id := "", target_id := "") -> float:
	var t := 0.0
	for m in s.staff:
		if String(m.get("id", "")) in staff_ids:
			t += spec_effect_for(m, key, type_id, target_id)
	return t


# ------------------------------------------------------------ XP and levels
## Adds XP to a Cometling (the training centre makes it faster; a mentor on the same project
## too). Levels up at every xp_per_level, up to max_level. Returns the levels gained. Does not
## emit `changed` (the caller usually does it once for the whole week).
static func add_xp(s: TycoonState, staff_id: String, xp: float) -> int:
	ensure(s)
	var m := find(s, staff_id)
	if m.is_empty() or xp <= 0.0:
		return 0
	var mult := 1.0 + float(data().get("training_xp_bonus", 0.15)) * training_level(s) \
		+ TycoonLegends.mentor_effect(s, "agency_xp")   # a mentor teaching the whole campus
	if String(m.get("profession", "")) == "pilot":
		mult += TycoonLegends.mentor_effect(s, "pilot_xp")
	var proj := String(m.get("assigned", ""))
	if proj != "":
		for o in s.staff:
			if o != m and String(o.get("assigned", "")) == proj:
				mult += spec_effect(o, "team_xp")
	m["xp"] = float(m.get("xp", 0.0)) + xp * mult
	var old := int(m["level"])
	var lv := mini(int(float(m["xp"]) / xp_per_level()) + 1, max_level())
	if lv <= old:
		return 0
	m["level"] = lv
	m["morale"] = minf(float(m["morale"]) + morale_rule("level_up_gain", 6.0), 100.0)
	s.news.push_front({"key": "TY_CREW_NEWS_LEVEL", "args": [String(m["name"]), lv]})
	if spec_pending(s, m):
		s.news.push_front({"key": "TY_CREW_NEWS_SPEC_READY", "args": [String(m["name"])]})
	return lv - old


# ------------------------------------------------------------ hiring market
## Dev only (src/dev/cw_dev.gd): a fresh set of candidates now, as at the start of a month.
static func dev_refresh_market(s: TycoonState) -> void:
	ensure(s)
	var r := _rng(s)
	_new_market(s, r)
	_store(s, r)
	s.changed.emit()


static func _new_market(s: TycoonState, r: RandomNumberGenerator) -> void:
	var legends := TycoonLegends.kept_candidates(s)   # a Lenda stays a while
	var profs: Array = []
	for p: Dictionary in s.pdata.get("professions", []):
		profs.append(String(p["id"]))
	for i in range(profs.size() - 1, 0, -1):  # seeded shuffle
		var j := r.randi_range(0, i)
		var tmp: Variant = profs[i]
		profs[i] = profs[j]
		profs[j] = tmp
	var out: Array = []
	var n := mini(int(data().get("candidates_per_month", 3)), profs.size())
	for i in n:
		out.append(_candidate(s, r, String(profs[i]), out))
	# a Lenda of this era comes once, on a golden card at the front (no draw from the crew RNG)
	var lg := TycoonLegends.arrival(s)
	if not lg.is_empty():
		legends.append(lg)
	s.crew["candidates"] = legends + out


static func _candidate(s: TycoonState, r: RandomNumberGenerator, prof: String, others: Array) -> Dictionary:
	var id_n := int(s.crew.get("next_id", 1))
	s.crew["next_id"] = id_n + 1
	var c := {"id": "c%03d" % id_n, "profession": prof, "seed": r.randi() % 100000 + 1}
	for t in TRAITS:
		c[t] = snappedf(r.randf_range(0.25, 0.9), 0.01)
	# the profession's main trait leans high: they chose this job for a reason
	var main := "curiosity" if prof in ["scientist", "researcher"] else ("courage" if prof == "pilot" else "skill")
	c[main] = maxf(float(c[main]), snappedf(r.randf_range(0.55, 0.97), 0.01))
	var chance := float(data().get("candidate_level_chance_per_era", 0.12))
	var lv := 1
	for k in 2:
		if r.randf() < chance * (s.era() - k):
			lv += 1
	c["level"] = lv
	c["xp"] = (lv - 1) * xp_per_level()
	c["name"] = _unique_name(s, r, others)
	c["variant"] = _least_used_variant(s, r, others)
	var hidden: Array = TRAITS.duplicate()
	while hidden.size() > int(data().get("hidden_at_start", 2)):
		hidden.remove_at(r.randi() % hidden.size())
	c["hidden"] = hidden
	return c


static func _unique_name(s: TycoonState, r: RandomNumberGenerator, others: Array) -> String:
	var taken := {}
	for m in s.staff:
		taken[String(m.get("name", ""))] = true
	for c: Dictionary in others:
		taken[String(c.get("name", ""))] = true
	var n := CrewRoster.generate_name(r)
	for i in 20:
		if not taken.has(n):
			break
		n = CrewRoster.generate_name(r)
	return n


static func _least_used_variant(s: TycoonState, r: RandomNumberGenerator, others: Array) -> int:
	var use: Array[int] = []
	use.resize(CometlingLooks.count())
	use.fill(0)
	for m in s.staff:
		use[posmod(int(m.get("variant", 0)), use.size())] += 1
	for c: Dictionary in others:
		use[posmod(int(c.get("variant", 0)), use.size())] += 1
	var lowest: int = use.min()
	var pick: Array[int] = []
	for i in use.size():
		if use[i] == lowest:
			pick.append(i)
	return pick[r.randi() % pick.size()]


## Can this candidate be hired now? "" if yes, else the translation key of the reason.
static func can_hire(s: TycoonState, cand_id: String) -> String:
	var c := find_candidate(s, cand_id)
	if c.is_empty():
		return "TY_CREW_ERR_NONE"
	if s.staff.size() >= staff_limit(s) and not dev_ignore_limit:
		return "TY_CREW_ERR_LIMIT"
	if s.cash < hire_fee(s, c):
		return "TY_CREW_ERR_CASH"
	return ""


## Hires a candidate: pays the fee, the Cometling joins with adaptation weeks (no work yet)
## and their hidden traits still hidden until they settle in. Returns "" or the error key.
static func hire(s: TycoonState, cand_id: String) -> String:
	var err := can_hire(s, cand_id)
	if err != "":
		return err
	var c := find_candidate(s, cand_id)
	s.cash -= hire_fee(s, c)
	var m := {"id": "h%03d" % int(s.crew.get("next_id", 1)), "name": c["name"], "profession": c["profession"],
		"level": int(c["level"]), "xp": float(c["xp"]), "skill": c["skill"], "curiosity": c["curiosity"],
		"courage": c["courage"], "morale": morale_rule("hire_start", 75.0), "variant": int(c["variant"]),
		"assigned": "", "adapt_weeks": int(data().get("adapt_weeks", 2)), "train_weeks": 0, "specs": [],
		"busy_weeks": 0, "napping": false, "hidden": (c["hidden"] as Array).duplicate(), "seed": int(c["seed"]),
		"hired_week": s.weeks}
	s.crew["next_id"] = int(s.crew.get("next_id", 1)) + 1
	TycoonLegends.on_hired(s, c, m)
	m = s.normalize_staff(m, s.staff.size())
	_fill(m)
	s.staff.append(m)
	(s.crew["candidates"] as Array).erase(c)
	s.news.push_front({"key": "TY_CREW_NEWS_HIRED", "args": [String(m["name"]),
		String(s.profession(String(m["profession"])).get("name_key", ""))]})
	s.changed.emit()
	return ""


## Lets a Cometling go (not while on a project). The others feel it a little.
static func fire(s: TycoonState, staff_id: String) -> String:
	ensure(s)
	var m := find(s, staff_id)
	if m.is_empty():
		return "TY_CREW_ERR_NONE"
	if bool(m.get("leader", false)):
		return "TY_LEADER_ERR_FIRE"   # the leader is you (TycoonLeader)
	if String(m.get("assigned", "")) != "":
		return "TY_CREW_ERR_ASSIGNED"
	s.staff.erase(m)
	for o in s.staff:
		o["morale"] = maxf(float(o["morale"]) - morale_rule("fire_drop", 4.0), 0.0)
	s.news.push_front({"key": "TY_CREW_NEWS_FIRED", "args": [String(m["name"])]})
	s.changed.emit()
	return ""


# ------------------------------------------------------------ weekly rules
## One week for the crew (called by TycoonState.advance_week after the monthly bills):
## settling in, training, overwork and rest, naps below the threshold, late salaries, the
## market reveals a hidden trait per candidate and renews itself each month.
static func on_week(s: TycoonState) -> void:
	ensure(s)
	var r := _rng(s)
	var month_change := s._month_of(s.weeks - 1) != s._month_of(s.weeks)
	var late := month_change and s.cash < 0.0
	for m in s.staff:
		_member_week(s, m, late)
	if late:
		s.news.push_front({"key": "TY_CREW_NEWS_LATE", "args": []})
	if month_change:
		_new_market(s, r)
	else:
		for c: Dictionary in s.crew.get("candidates", []):
			var hidden: Array = c.get("hidden", [])
			if not hidden.is_empty():
				hidden.remove_at(r.randi() % hidden.size())
	_store(s, r)


static func _member_week(s: TycoonState, m: Dictionary, late: bool) -> void:
	var morale := float(m.get("morale", 70.0))
	if int(m["adapt_weeks"]) > 0:
		m["adapt_weeks"] = int(m["adapt_weeks"]) - 1
		if m["adapt_weeks"] == 0:
			m["hidden"] = []
			s.news.push_front({"key": "TY_CREW_NEWS_SETTLED", "args": [String(m["name"])]})
	if int(m["train_weeks"]) > 0:
		m["train_weeks"] = int(m["train_weeks"]) - 1
	if bool(m["napping"]):  # the nap is over: a bit more rested
		m["napping"] = false
		morale += morale_rule("nap_recover", 14.0)
	var on_project := String(m.get("assigned", "")) != ""
	if on_project and is_working(m):
		m["busy_weeks"] = int(m["busy_weeks"]) + 1
	else:
		m["busy_weeks"] = maxi(int(m["busy_weeks"]) - 2, 0)
	var limit := morale_rule("overwork_weeks", 8.0) + spec_effect(m, "overwork_weeks")
	if int(m["busy_weeks"]) > limit:
		morale -= morale_rule("overwork_drop", 3.0)
	elif not on_project and morale < morale_rule("rest_cap", 85.0):
		morale = minf(morale + morale_rule("rest_recover", 2.0), morale_rule("rest_cap", 85.0))
	if late:
		morale -= morale_rule("late_salary_drop", 10.0)
	morale = clampf(morale, 0.0, 100.0)
	m["morale"] = morale
	if morale < morale_rule("nap_below", 30.0):
		m["napping"] = true


## Morale after a launch (state.mission_launched): the project's crew feel it fully, the rest
## of the agency a share of it; courage softens failures.
static func mission_result(s: TycoonState, result: Dictionary) -> void:
	var pid := String(result.get("project_id", ""))
	var success := bool(result.get("success", false))
	var outcome := String(result.get("outcome", ""))
	for m in s.staff:
		var delta := 0.0
		if success:
			delta = morale_rule("exceptional_gain" if outcome == "exceptional" else "success_gain", 8.0)
		else:
			delta = -morale_rule("failure_drop", 12.0) * (1.2 - 0.6 * float(m.get("courage", 0.5))) \
				* maxf(1.0 + spec_effect(m, "failure_morale"), 0.0)
		if pid == "" or String(m.get("assigned", "")) != pid:
			delta *= morale_rule("agency_share", 0.35)
		m["morale"] = clampf(float(m.get("morale", 70.0)) + delta, 0.0, 100.0)
