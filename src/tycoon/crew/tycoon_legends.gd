class_name TycoonLegends
extends RefCounted
## As Lendas (data/tycoon/legends.json): Cometlings that pay homage to real people who opened
## the way to the sky, in three roles:
##   hire          comes once to the hiring market (its campaign year, in its era), on a golden
##                 card, with its unique specialisation already learned; once hired its effects
##                 sum into TycoonCrew.spec_effect like any specialisation
##   mentor        no salary: from its era it comments on the briefings it knows about (one
##                 more voice under "A equipe comenta") and gives the agency a small bonus
##                 (mentor_effect: agency_xp, pilot_xp, spec_weeks, gov_reward)
##   rival_leader  the face of a rival agency on the race board and in O Eco da Cauda
## Each one has a "Quem inspirou" card in the encyclopedia (cards()) with the real person, one or
## two plain facts and the source. Pure data + rules on a TycoonState; the only state is
## state.crew["legends"] = {"seen": {legend id: week it came to the market}, "hired": {legend id:
## staff id}}, saved with the crew, so a campaign saved before the Lendas just has none seen yet.

const DATA_PATH := "res://data/tycoon/legends.json"
const KINDS: Array[String] = ["hire", "mentor", "rival_leader"]
const BARS: Array[String] = ["eng", "sci", "ops", "rel"]

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}
## dev menu only (src/dev/cw_dev.gd): every mentor is around, whatever the era
static var dev_mentors := false


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(DATA_PATH)
		_by_id.clear()
		for l: Dictionary in _data.get("legends", []):
			_by_id[String(l["id"])] = l
	return _data


static func all() -> Array:
	return data().get("legends", [])


static func legend(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in all():
		if String(l.get("kind", "")) == kind:
			out.append(l)
	return out


## The translation key of one of a Lenda's texts: TY_LEG_<ID>_<PART> (NAME, ROLE, WAY, SPEC,
## SPEC_DESC, HINT, REAL, FACT; FIRST, FAIL, CHEER for the rival leaders).
static func key(id: String, part: String) -> String:
	return "TY_LEG_%s_%s" % [id.to_upper(), part]


static func name_text(id: String) -> String:
	return TranslationServer.translate(key(id, "NAME"))


static func is_legend(m: Dictionary) -> bool:
	return String(m.get("legend", "")) != ""


## The Lenda's own Cometling scene (legends.json `scene`: scenes/npc/legends/<id>.tscn, a
## LegendCometling), "" while it has none: it then wears the shared Cometling with its colours
## and hat (look). TycoonLeader.dress swaps the body wherever a Lenda shows.
static func scene_path(id: String) -> String:
	var p := String(legend(id).get("scene", ""))
	return p if p != "" and ResourceLoader.exists(p) else ""


static func has_scene(id: String) -> bool:
	return scene_path(id) != ""


## A new instance of the Lenda's own Cometling (null without a scene).
static func instance(id: String) -> LegendCometling:
	var p := scene_path(id)
	if p == "":
		return null
	var ps := load(p) as PackedScene
	return ps.instantiate() as LegendCometling if ps else null


## The look of a Lenda as a staff-like dictionary (portrait studio, TycoonLeader.dress).
static func look(id: String) -> Dictionary:
	var l := legend(id)
	var lk: Dictionary = l.get("look", {})
	var body := String(lk.get("body", "#bfe9ff"))
	return {"id": "legend_" + id, "legend": id, "name": name_text(id), "profession": String(l.get("profession", "")),
		"body": body, "spot": String(lk.get("spot", "#f59a36")), "hat": String(lk.get("hat", "role")),
		"variant": TycoonLeader.nearest_variant(Color(body))}


# ------------------------------------------------------------ state
static func st(s: TycoonState) -> Dictionary:
	if not s.crew.has("rng_state"):
		TycoonCrew.ensure(s)   # the crew dictionary first (it would replace this one)
	if not s.crew.has("legends"):
		s.crew["legends"] = {}
	var l: Dictionary = s.crew["legends"]
	for k in ["seen", "hired"]:
		if not l.has(k):
			l[k] = {}
	return l


static func seen(s: TycoonState, id: String) -> bool:
	return (st(s)["seen"] as Dictionary).has(id)


static func hired(s: TycoonState, id: String) -> bool:
	return (st(s)["hired"] as Dictionary).has(id)


# ------------------------------------------------------------ hiring market
## The legendary candidates of the old market that stay (market_weeks after they came).
static func kept_candidates(s: TycoonState) -> Array:
	var out: Array = []
	var stay := int(data().get("market_weeks", 8))
	for c: Dictionary in s.crew.get("candidates", []):
		if is_legend(c) and s.weeks - int((st(s)["seen"] as Dictionary).get(String(c["legend"]), s.weeks)) < stay:
			out.append(c)
	return out


## Weeks before a legendary candidate leaves the market for good (at least 1).
static func weeks_left(s: TycoonState, id: String) -> int:
	var came := int((st(s)["seen"] as Dictionary).get(id, s.weeks))
	var stay := int(data().get("market_weeks", 8))
	# it leaves with the first market renewal (a new month) once its stay is over
	for w in range(s.weeks + 1, s.weeks + 80):
		if s._month_of(w) != s._month_of(w - 1) and w - came >= stay:
			return w - s.weeks
	return 1


## The Lenda that comes to the market this month ({} if none): the first one in the data whose
## era and campaign year have come and who never came before. Called by TycoonCrew._new_market.
static func arrival(s: TycoonState) -> Dictionary:
	for l in of_kind("hire"):
		var id := String(l["id"])
		if seen(s, id) or not _arrived(s, l):
			continue
		return make_candidate(s, id)
	return {}


## A golden candidate for Lenda `id`: fixed name, look, level and traits (all known), and it is
## marked as seen (it never comes back).
static func make_candidate(s: TycoonState, id: String) -> Dictionary:
	var l := legend(id)
	var lk: Dictionary = l.get("look", {})
	var id_n := int(s.crew.get("next_id", 1))
	s.crew["next_id"] = id_n + 1
	var lv := clampi(int(l.get("level", data().get("hire_level", 3))), 1, TycoonCrew.max_level())
	var c := {"id": "c%03d" % id_n, "legend": id, "name": name_text(id), "profession": String(l.get("profession", "pilot")),
		"level": lv, "xp": (lv - 1) * TycoonCrew.xp_per_level(), "hidden": [], "seed": absi(hash(id)) % 100000 + 1,
		"body": String(lk.get("body", "#bfe9ff")), "spot": String(lk.get("spot", "#f59a36")), "hat": String(lk.get("hat", "role"))}
	var traits: Dictionary = l.get("traits", {})
	for t: String in TycoonCrew.TRAITS:
		c[t] = float(traits.get(t, 0.75))
	c["variant"] = TycoonLeader.nearest_variant(Color(String(c["body"])))
	(st(s)["seen"] as Dictionary)[id] = s.weeks
	s.news.push_front({"key": "TY_LEG_NEWS_MARKET", "args": [String(c["name"])]})
	return c


## A legendary candidate became staff member `m` (TycoonCrew.hire): its look and legend go along.
static func on_hired(s: TycoonState, c: Dictionary, m: Dictionary) -> void:
	if not is_legend(c):
		return
	var id := String(c["legend"])
	m["legend"] = id
	for k in ["body", "spot", "hat"]:
		m[k] = c[k]
	(st(s)["hired"] as Dictionary)[id] = String(m["id"])
	s.news.push_front({"key": "TY_LEG_NEWS_HIRED", "args": [String(m["name"]), key(id, "SPEC")]})


## Dev menu: Lenda `id` (or the first hire not yet on staff) on the market now, at the front.
## Returns the candidate ({} if every legendary hire is already on staff).
static func dev_spawn(s: TycoonState, id := "") -> Dictionary:
	TycoonCrew.ensure(s)
	if id == "":
		for l in of_kind("hire"):
			var lid := String(l["id"])
			if not hired(s, lid) and not _on_market(s, lid):
				id = lid
				break
	if id == "" or String(legend(id).get("kind", "")) != "hire":
		return {}
	var cands: Array = s.crew["candidates"]
	for c: Dictionary in cands.duplicate():
		if String(c.get("legend", "")) == id:
			cands.erase(c)
	(st(s)["seen"] as Dictionary).erase(id)
	var c := make_candidate(s, id)
	cands.push_front(c)
	s.changed.emit()
	return c


static func _on_market(s: TycoonState, id: String) -> bool:
	for c: Dictionary in s.crew.get("candidates", []):
		if String(c.get("legend", "")) == id:
			return true
	return false


# ------------------------------------------------------------ effects
## A staff member's own legendary specialisation (0 for everyone else): TycoonCrew.spec_effect.
static func member_effect(m: Dictionary, k: String) -> float:
	if not is_legend(m):
		return 0.0
	return float((legend(String(m["legend"])).get("effects", {}) as Dictionary).get(k, 0.0))


## The unique specialisation's effects of a Lenda ({key: value}).
static func effects(id: String) -> Dictionary:
	return legend(id).get("effects", {})


## A mentor is around once its era and its campaign year have come.
static func mentor_active(s: TycoonState, id: String) -> bool:
	var l := legend(id)
	return String(l.get("kind", "")) == "mentor" and _arrived(s, l)


static func _arrived(s: TycoonState, l: Dictionary) -> bool:
	if dev_mentors and String(l.get("kind", "")) == "mentor":
		return true
	return s.era() >= int(l.get("era", 1)) and s.year() >= int(l.get("year", 1))


static func active_mentors(s: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in of_kind("mentor"):
		if _arrived(s, l):
			out.append(l)
	return out


## The agency-wide bonus of the mentors around now (summed).
static func mentor_effect(s: TycoonState, k: String) -> float:
	var t := 0.0
	for l in active_mentors(s):
		t += float((l.get("effects", {}) as Dictionary).get(k, 0.0))
	return t


# ------------------------------------------------------------ mentors on the briefings
static func comments_on(l: Dictionary, b: Dictionary) -> bool:
	var c: Dictionary = l.get("comments", {})
	if String(b.get("client", "")) in (c.get("clients", []) as Array):
		return true
	if String(b.get("kind", "")) in (c.get("kinds", []) as Array):
		return true
	if BriefingDesk.best_type(b) in (c.get("types", []) as Array):
		return true
	return BriefingDesk.best_target(b) in (c.get("targets", []) as Array)


## The client's ideal balance (its own, else the best type's).
static func _ratio(s: TycoonState, b: Dictionary) -> Array:
	var r := BriefingDesk.ratio(b)
	return r if r.size() == 4 else s.mission_type(BriefingDesk.best_type(b)).get("ratio", [0.25, 0.25, 0.25, 0.25])


## Bar indices from the most to the least valued.
static func _bars_by_weight(r: Array) -> Array[int]:
	var idx: Array[int] = [0, 1, 2, 3]
	idx.sort_custom(func(a: int, c: int) -> bool: return float(r[a]) > float(r[c]))
	return idx


## A mentor's line on a briefing: {"legend", "key", "args"} ({} when it has nothing to say).
static func hint_line(s: TycoonState, l: Dictionary, b: Dictionary) -> Dictionary:
	var id := String(l["id"])
	var args: Array = []
	var order := _bars_by_weight(_ratio(s, b))
	match String(l.get("hint", "")):
		"top_bar":
			args = ["TY_BAR_" + BARS[order[0]].to_upper()]
		"top_two":
			args = ["TY_BAR_" + BARS[order[0]].to_upper(), "TY_BAR_" + BARS[order[1]].to_upper()]
		"profession":
			var prof := String(Discovery.BAR_PROFESSION.get(BARS[order[0]], ""))
			args = [String(s.profession(prof).get("name_key", prof)), "TY_BAR_" + BARS[order[0]].to_upper()]
		"target":
			args = [String(s.mission_target(BriefingDesk.best_target(b)).get("name_key", ""))]
		"type":
			args = [String(s.mission_type(BriefingDesk.best_type(b)).get("name_key", ""))]
		"module":
			var needs := BriefingDesk.needs(b)
			if needs.is_empty():
				return {}
			args = [PayloadRules.name_key(String(needs[0]))]
		_:
			return {}
	return {"legend": id, "key": key(id, "HINT"), "args": args}


## What the mentors around now say about a briefing (at most `limit` lines). `team_quiet`: the
## staff has no hunch (Discovery.briefing_hints is empty), so the campus mentor speaks up.
static func mentor_hints(s: TycoonState, b: Dictionary, team_quiet: bool, limit := 2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if b.is_empty():
		return out
	for l in active_mentors(s):
		var fallback := bool((l.get("comments", {}) as Dictionary).get("fallback", false))
		if (fallback and not team_quiet) or (not fallback and not comments_on(l, b)):
			continue
		var h := hint_line(s, l, b)
		if not h.is_empty():
			out.append(h)
		if out.size() >= limit:
			break
	return out


# ------------------------------------------------------------ rival leaders
## The Lenda leading rival agency `rival_id` ({} if none).
static func rival_leader(rival_id: String) -> Dictionary:
	for l in of_kind("rival_leader"):
		if String(l.get("rival", "")) == rival_id:
			return l
	return {}


static func rival_leader_id(rival_id: String) -> String:
	return String(rival_leader(rival_id).get("id", ""))


# ------------------------------------------------------------ "Quem inspirou" cards
## Has the agency met this Lenda (its card readable)? A hire once it came to the market, a
## mentor once its era came, a rival leader always (they are on the race board from day one).
static func met(s: TycoonState, id: String) -> bool:
	var l := legend(id)
	match String(l.get("kind", "")):
		"hire":
			return seen(s, id)
		"mentor":
			return _arrived(s, l)
	return not l.is_empty()


static func sources(id: String) -> Array:
	return (legend(id).get("real", {}) as Dictionary).get("sources", [])


static func is_original(id: String) -> bool:
	return bool((legend(id).get("real", {}) as Dictionary).get("original", false))


static func is_living(id: String) -> bool:
	return bool((legend(id).get("real", {}) as Dictionary).get("living", false))


## The cards: [{"id", "kind", "era", "unlocked"}], kind order (hires, mentors, rival leaders)
## then era. A Lenda homaging a real person without a checked source never shows.
static func cards(s: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind in KINDS:
		var list := of_kind(kind)
		list.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return int(a.get("era", 1)) < int(c.get("era", 1)))
		for l in list:
			var id := String(l["id"])
			if sources(id).is_empty() and not is_original(id):
				continue
			out.append({"id": id, "kind": kind, "era": int(l.get("era", 1)), "unlocked": met(s, id)})
	return out
