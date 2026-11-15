class_name ChatterBook
extends RefCounted
## What the Cometlings say: the speech bubble lines of the campus (data/tycoon/chatter.json) and
## the dialogue trees of "Conversar" (data/tycoon/dialogues.json), the player's bubble settings
## and the shared condition language both files use. Pure data + rules, no scene access.
##
## Context: one Dictionary per speaker (context()), the same keys for bubbles and dialogues:
##   profession  staff profession id ("pilot", "systems_engineer", ...; "" for Vovô)
##   mood        "happy" (morale 70+) | "ok" | "low" (under 40)    morale  0..100
##   tired       true after many weeks in a row on a project (or very low morale)
##   status      TycoonCrew.status(): "nap" | "adapting" | "training" | "busy" | "idle"
##   doing       "walking" | "working" | "idle" | "napping"  (the campus walker, activity())
##   place       where they are or are going: a building kind ("lab", "pad", "hq", "workshop",
##               "control", "antenna", "training", "factory") or a campus spot ("bench",
##               "plaza", "statue", "lookout"); "" when nowhere in particular
##   era 1..5 · year · comet_years (whole years left until the comet) · staff (head count)
##   time        "golden" | "night" | "dawn" (the campus day cycle)
##   events      recent things: "launch_success", "launch_failure", "milestone", "rival_first",
##               "new_hire", "new_era" (CampusChatter keeps them for a while)
##   money       "ok" | "low" (under two months of salaries) | "broke" (in the red)
##   team_mood   the agency's average morale: "happy" | "ok" | "low"
##   who         bubbles only: a talker's own id (metadata talk_id, e.g. "halleyzinho"); a
##               talker only says the lines made for it ("if": {"who": id})
##   leader (bool) · legend (Lenda id or "") · level · project (bool: on a project)
##   race_place  the player's place in the race (1 = in front; RaceDirector.standings)
##   milestones  the race milestones the player has taken (Array of ids: "first_satellite"...)
##   missions_done  missions the agency has finished (flown and judged)
##   dialogue only: has_hint (bool), talked_week (bool: the weekly morale nudge was used),
##   flags (Array of what this speaker remembers, set by the "flag" effect), where ("campus" |
##   "briefing" | "race": where the talk was opened), rival_vs (a rival leader's talk only:
##   "ahead" | "behind" | "even", their agency against the player's)
##
## Conditions ("if" in the data) are Dictionaries; every key must hold:
##   "key": value         equal (a list value: any of them; a list in the context: contains)
##   "key_min" / "key_max": number at least / at most
##   "not_key": value     the opposite of "key": value
## Lines pick among the matching ones, weighted by "weight" (default 1) and by how specific
## they are (each condition makes a line likelier than the generic ones).
##
## Settings (user://settings.cfg [tycoon], the in-game settings' Image tab): speech_bubbles
## (on / off) and bubble_rate ("few" | "normal" | "many": how often and how many at once).

const CHATTER_PATH := "res://data/tycoon/chatter.json"
const DIALOGUE_PATH := "res://data/tycoon/dialogues.json"
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "tycoon"
const KEY_ON := "speech_bubbles"
const KEY_RATE := "bubble_rate"
const RATES: Array[String] = ["few", "normal", "many"]
## each condition of a line multiplies its weight by (1 + SPECIFIC)
const SPECIFIC := 2.0

static var _chatter: Dictionary = {}
static var _dialogues: Dictionary = {}
static var _on := -1
static var _rate := ""


static func chatter() -> Dictionary:
	if _chatter.is_empty():
		_chatter = TycoonState.load_json(CHATTER_PATH)
	return _chatter


static func dialogues() -> Dictionary:
	if _dialogues.is_empty():
		_dialogues = TycoonState.load_json(DIALOGUE_PATH)
	return _dialogues


# ------------------------------------------------------------ settings
static func enabled() -> bool:
	if _on < 0:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		_on = 1 if bool(cfg.get_value(SETTINGS_SECTION, KEY_ON, true)) else 0
	return _on == 1


static func set_enabled(on: bool) -> void:
	_on = 1 if on else 0
	_store(KEY_ON, on)


static func rate() -> String:
	if _rate == "":
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		_rate = String(cfg.get_value(SETTINGS_SECTION, KEY_RATE, "normal"))
		if not _rate in RATES:
			_rate = "normal"
	return _rate


static func set_rate(r: String) -> void:
	_rate = r if r in RATES else "normal"
	_store(KEY_RATE, _rate)


## The numbers of the current rate: {"max" (bubbles at once), "gap" [min, max seconds between
## two new ones], "pair" (chance of a two-Cometling exchange)}.
static func rate_cfg(r := "") -> Dictionary:
	var rates: Dictionary = chatter().get("rates", {})
	return rates.get(r if r != "" else rate(), rates.get("normal", {"max": 3, "gap": [3.0, 7.0], "pair": 0.25}))


static func _store(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, key, value)
	cfg.save(SETTINGS_PATH)


# ------------------------------------------------------------ context
## The context of a speaker (see the header). `m`: their staff entry ({} for someone outside
## the staff, like Vovô); `activity`: the walker's activity() ({} when unknown); `world`:
## {"events": [...], "time": "night"} from the campus.
static func context(s: TycoonState, m: Dictionary, activity := {}, world := {}) -> Dictionary:
	var morale := float(m.get("morale", 70.0))
	var ctx := {
		"profession": String(m.get("profession", "")),
		"morale": morale,
		"mood": "happy" if morale >= 70.0 else ("low" if morale < 40.0 else "ok"),
		"status": TycoonCrew.status(m) if not m.is_empty() else "idle",
		"tired": int(m.get("busy_weeks", 0)) >= int(chatter().get("tired_weeks", 6)) or morale < 32.0,
		"level": int(m.get("level", 1)),
		"project": String(m.get("assigned", "")) != "",
		"leader": not m.is_empty() and TycoonLeader.is_leader(m),
		"legend": String(m.get("legend", "")),
		"doing": String(activity.get("doing", "napping" if bool(m.get("napping", false)) else "idle")),
		"place": String(activity.get("place", "")),
		"events": world.get("events", []),
		"time": String(world.get("time", "golden")),
	}
	if s != null:
		ctx["era"] = s.era()
		ctx["year"] = s.year()
		ctx["comet_years"] = int(ceil(float(s.comet_weeks_left()) / s.weeks_per_year()))
		ctx["staff"] = s.staff.size()
		var avg := TycoonCrew.average_morale(s) if not s.staff.is_empty() else 70.0
		ctx["team_mood"] = "happy" if avg >= 70.0 else ("low" if avg < 45.0 else "ok")
		var pay := s.monthly_salaries()
		ctx["money"] = "broke" if s.cash < 0.0 else ("low" if s.cash < pay * float(chatter().get("low_money_months", 2.0)) else "ok")
		ctx["missions_done"] = s.project_history.size()
		if s.race:
			ctx["race_place"] = race_place(s)
			var taken: Array = []
			for c: Dictionary in s.race.claims_of(RaceDirector.PLAYER):
				taken.append(String(c.get("milestone", c.get("id", ""))))
			ctx["milestones"] = taken
	return ctx


## The player's place in the race (1 = in front).
static func race_place(s: TycoonState) -> int:
	if s == null or s.race == null:
		return 1
	var st := s.race.standings()
	for i in st.size():
		if bool(st[i].get("player", false)):
			return i + 1
	return st.size()


## Does `ctx` meet every condition of `cond`?
static func matches(cond: Variant, ctx: Dictionary) -> bool:
	if not cond is Dictionary:
		return true
	for k: String in cond:
		if not _holds(k, cond[k], ctx):
			return false
	return true


static func _holds(k: String, want: Variant, ctx: Dictionary) -> bool:
	if k.begins_with("not_"):
		return not _holds(k.substr(4), want, ctx)
	if k.ends_with("_min"):
		return float(ctx.get(k.trim_suffix("_min"), 0.0)) >= float(want)
	if k.ends_with("_max"):
		return float(ctx.get(k.trim_suffix("_max"), 0.0)) <= float(want)
	var have: Variant = ctx.get(k, null)
	if have is Array:
		if want is Array:
			for w in want:
				if w in have:
					return true
			return false
		if want is bool:
			return (not (have as Array).is_empty()) == want
		return want in have
	if want is Array:
		for w in want:
			if _same(have, w):
				return true
		return false
	return _same(have, want)


static func _same(a: Variant, b: Variant) -> bool:
	if b is bool:
		return bool(a) == b if a != null else not b
	if b is float or b is int:
		return a != null and (a is float or a is int) and is_equal_approx(float(a), float(b))
	return String(a if a != null else "") == String(b)


## How many conditions a line carries (more = more specific).
static func specificity(entry: Dictionary) -> int:
	var c: Variant = entry.get("if", {})
	return (c as Dictionary).size() if c is Dictionary else 0


## A weighted pick among the entries whose "if" holds for `ctx`; entries whose `id_field` is in
## `avoid` are skipped while others remain. {} when none matches.
static func pick(entries: Array, ctx: Dictionary, rng: RandomNumberGenerator, avoid: Array = [],
		id_field := "text_key") -> Dictionary:
	var ok: Array[Dictionary] = []
	for e: Dictionary in entries:
		if matches(e.get("if", {}), ctx):
			ok.append(e)
	if ok.is_empty():
		return {}
	var fresh := ok.filter(func(e: Dictionary) -> bool: return not String(e.get(id_field, "")) in avoid)
	if not fresh.is_empty():
		ok.assign(fresh)
	var total := 0.0
	var w: Array[float] = []
	for e in ok:
		var x := float(e.get("weight", 1.0)) * (1.0 + SPECIFIC * specificity(e))
		w.append(x)
		total += x
	var r := rng.randf() * total
	for i in ok.size():
		r -= w[i]
		if r <= 0.0:
			return ok[i]
	return ok[ok.size() - 1]


# ------------------------------------------------------------ text
## A translated line with its {placeholders} filled from `vars`.
static func text(key: String, vars := {}) -> String:
	var t := TranslationServer.translate(key)
	return t.format(vars) if not vars.is_empty() else t


## The placeholders every line may use: {name}, {profession}, {project}, {agency}, {leader},
## {left} (time until the comet), {race_place}, {my_count} (milestones the player took),
## {next_goal} (the player's next milestone), plus {legend_real}, {legend_fact}, {legend_way}
## for a Lenda ({rival}, {rival_count} in a rival leader's talk: DialogueRun.for_legend).
static func vars_for(s: TycoonState, m: Dictionary) -> Dictionary:
	var v := {"name": String(m.get("name", TranslationServer.translate("TY_CAM_COMETLING")))}
	if s == null:
		return v
	var prof_key := String(s.profession(String(m.get("profession", ""))).get("name_key", ""))
	v["profession"] = TranslationServer.translate(prof_key) if prof_key != "" else ""
	v["agency"] = s.agency_name
	v["leader"] = String(TycoonLeader.member(s).get("name", s.agency_name))
	v["project"] = project_code(s, String(m.get("assigned", "")))
	v["left"] = time_left(s)
	if s.race:
		v["race_place"] = race_place(s)
		v["my_count"] = s.race.claims_of(RaceDirector.PLAYER).size()
		var nx := s.race.next_of(RaceDirector.PLAYER)
		var goal_key := "TY_RACE_ALL_DONE"
		if nx < s.race.milestones.size():
			goal_key = String(s.race.milestones[nx].get("short_key", s.race.milestones[nx].get("name_key", "")))
		v["next_goal"] = TranslationServer.translate(goal_key)
	var lg := String(m.get("legend", ""))
	if lg != "":
		v["legend_real"] = TranslationServer.translate(TycoonLegends.key(lg, "REAL"))
		v["legend_fact"] = TranslationServer.translate(TycoonLegends.key(lg, "FACT"))
		v["legend_way"] = TranslationServer.translate(TycoonLegends.key(lg, "WAY"))
	return v


## The code of a mission project ("SND-01"), "" when there is none.
static func project_code(s: TycoonState, project_id: String) -> String:
	if project_id == "":
		return ""
	for p: MissionProject in s.mission_projects:
		if p.id == project_id:
			return p.code
	return project_id


## "3 anos" / "1 ano" / "menos de um ano" until the comet passes.
static func time_left(s: TycoonState) -> String:
	var years := s.comet_weeks_left() / s.weeks_per_year()
	if years <= 0:
		return TranslationServer.translate("TY_DLG_LEFT_LT1")
	if years == 1:
		return TranslationServer.translate("TY_DLG_LEFT_ONE")
	return TranslationServer.translate("TY_DLG_LEFT_MANY").format({"n": years})


# ------------------------------------------------------------ the speaker in the world
## The staff entry of a talking node: a campus Crowd Cometling's (Campus.cometling_member), else
## any node with a member_id property or metadata (a Lenda's own scene); {} for nobody.
static func member_of(s: TycoonState, campus: Node, n: Node) -> Dictionary:
	if n == null or s == null:
		return {}
	if campus and campus.has_method("cometling_member"):
		var m: Dictionary = campus.call("cometling_member", n)
		if not m.is_empty():
			return m
	var id := ""
	if n.get("member_id") != null:
		id = String(n.get("member_id"))
	elif n.has_meta("member_id"):
		id = String(n.get_meta("member_id"))
	return TycoonCrew.find(s, id) if id != "" else {}


## The point above a talking node's head where its bubble hangs: a "TalkAnchor" child when it
## has one (a Lenda's own scene may author it), else the emote spot of its Cometling (the
## node itself, a "Creature" child or the first Cometling below it), else 2 m above it.
static func head_point(n: Node3D) -> Vector3:
	if n == null:
		return Vector3.ZERO
	var a := n.get_node_or_null("TalkAnchor") as Node3D
	if a:
		return a.global_position
	var c := find_creature(n)
	if c and c.emote_sprite:
		return c.emote_sprite.global_position
	return n.global_position + Vector3.UP * 2.0


## The Cometling model of a talking node (itself, its "Creature" child or the first one below).
static func find_creature(n: Node) -> Cometling:
	if n == null:
		return null
	if n is Cometling:
		return n as Cometling
	var c := n.get_node_or_null("Creature") as Cometling
	if c:
		return c
	for ch in n.get_children():
		var f := find_creature(ch)
		if f:
			return f
	return null
