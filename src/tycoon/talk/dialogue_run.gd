class_name DialogueRun
extends RefCounted
## One conversation with a Cometling (or Vovô Edmundo, a Lenda, anyone with a tree) walking
## through a dialogue tree of data/tycoon/dialogues.json. Pure rules: the dialogue box
## (CometlingDialogue) shows text() and choices() and calls choose(); tests drive it directly.
##
## Tree format: {"trees": {id: {"start": node id, "nodes": {...}, "menus": {...}}},
##               "by_legend": {legend id: tree id}, "legend": tree id, "leader": tree id,
##               "default": tree id}
##   node   {"lines": [line, ...], "choices": [choice, ...] | "<menu id>", "effects": [effect, ...]}
##   line   {"text_key", "if" (condition, ChatterBook), "weight", "pose" (a Cometling one-shot or a
##          Halleyzinho habit), "face" (an expression)}: one is picked among those whose "if"
##          holds, specific lines first (ChatterBook.pick)
##   choice {"text_key", "goto" (node id), "if", "end" (true: the conversation ends),
##          "once" (true: hidden after it was picked in this conversation), "effects"}
##   effect {"morale": n}   morale + n, once a week per speaker (talked_week)
##          {"flag": name}  the speaker remembers it (condition "flags": name)
##          {"hint": true}  the speaker's tip about the current mission goes into the
##                          Caderno (the discovery journal), once a week per speaker
##          {"lesson": id}  Vovô replays a lesson when the conversation ends (the box does it)
##          {"say": key}    a speech bubble over the speaker after the box closes
## Where it is kept: TycoonState.story["talk"] = {"week": {who: week of the last morale nudge},
## "hint": {who: week of the last tip}, "flags": {who: {flag: true}}}, saved with the campaign.
## Randomness (which line) comes from the RNG given to start(), never from the campaign's.

## the morale nudge of the "morale" effect is capped at once a week per speaker
const STORE := "talk"

var state: TycoonState
## the speaker's staff entry ({} for someone outside the staff)
var member: Dictionary = {}
## who the memory is kept for (the staff id, or "halleyzinho" for Vovô)
var who := ""
var tree_id := ""
var tree: Dictionary = {}
var node_id := ""
## the line on show (the data entry)
var line: Dictionary = {}
var ctx: Dictionary = {}
var vars: Dictionary = {}
var rng: RandomNumberGenerator
## what this conversation did, in order: {"effect": "morale" | "morale_capped" | "flag" | "hint" |
## "hint_known" | "lesson" | "say", ...}
var done: Array[Dictionary] = []
## what the box should do when it closes ({"lesson": id} / {"say": key})
var after: Array[Dictionary] = []
## a short note for the box under the text ("" = none)
var note := ""
var _picked := {}
var _seen_lines: Array[String] = []
var _over := false


## The tree of a speaker: the node's own (metadata "talk_tree"), a Lenda's, the leader's, or the
## default one.
static func tree_for(m: Dictionary, node: Node = null) -> String:
	var d := ChatterBook.dialogues()
	if node and node.has_meta("talk_tree"):
		return String(node.get_meta("talk_tree"))
	var lg := String(m.get("legend", ""))
	if lg != "":
		return String((d.get("by_legend", {}) as Dictionary).get(lg, d.get("legend", "legend")))
	if not m.is_empty() and TycoonLeader.is_leader(m):
		return String(d.get("leader", "leader"))
	return String(d.get("default", "cometling"))


static func has_tree(id: String) -> bool:
	return (ChatterBook.dialogues().get("trees", {}) as Dictionary).has(id)


func _init(s: TycoonState, m: Dictionary, p_tree := "", p_who := "", world := {}, activity := {}) -> void:
	state = s
	member = m
	tree_id = p_tree if p_tree != "" else tree_for(m)
	tree = (ChatterBook.dialogues().get("trees", {}) as Dictionary).get(tree_id, {})
	who = p_who if p_who != "" else String(m.get("id", tree_id))
	ctx = ChatterBook.context(s, m, activity, world)
	ctx["where"] = String(world.get("where", "campus"))
	vars = ChatterBook.vars_for(s, m)
	var hint := hint_text()
	vars["hint"] = hint
	ctx["has_hint"] = hint != ""
	_refresh_memory()


## A talk with Lenda `id` away from the staff: a mentor from a briefing ("briefing"), a rival
## leader from the race board ("race"), or any Lenda by its id (tests, the dev menu). Its own
## tree (by_legend), its look as the speaker, nothing to nudge (mentors and rival leaders are
## not staff: no morale, no Caderno tip) and, for a rival leader, how the race stands between
## their agency and the player's: ctx rival_vs ("ahead" | "behind" | "even") and the
## placeholders {rival}, {rival_count}. A hired Lenda talks as its staff entry instead.
static func for_legend(s: TycoonState, id: String, where := "campus", world := {}) -> DialogueRun:
	var staff_id := String((TycoonLegends.st(s)["hired"] as Dictionary).get(id, "")) if s else ""
	var m: Dictionary = TycoonCrew.find(s, staff_id) if staff_id != "" else {}
	var w := world.duplicate()
	w["where"] = where
	if not m.is_empty():
		return DialogueRun.new(s, m, "", "", w)
	var look := TycoonLegends.look(id)
	var r := DialogueRun.new(s, look, tree_for(look), id, w)
	r.member = {}
	var l := TycoonLegends.legend(id)
	if String(l.get("kind", "")) == "rival_leader" and s and s.race:
		var rid := String(l.get("rival", ""))
		var mine := s.race.race_points(RaceDirector.PLAYER) + (1.0 if s.race.met_comet(RaceDirector.PLAYER) else 0.0)
		var theirs := s.race.race_points(rid) + (1.0 if s.race.met_comet(rid) else 0.0)
		r.ctx["rival_vs"] = "even" if absf(mine - theirs) < 0.05 else ("ahead" if theirs > mine else "behind")
		r.vars["rival"] = TranslationServer.translate(s.race.agency_name(rid))
		r.vars["rival_count"] = s.race.claims_of(rid).size()
	return r


## Starts at the tree's start node (or `at`). False when the tree has no such node.
func start(r: RandomNumberGenerator, at := "") -> bool:
	rng = r
	_over = false
	return goto(at if at != "" else String(tree.get("start", "start")))


func is_over() -> bool:
	return _over


func goto(id: String) -> bool:
	var n: Dictionary = (tree.get("nodes", {}) as Dictionary).get(id, {})
	if n.is_empty():
		_over = true
		return false
	node_id = id
	note = ""
	line = pick_line(n.get("lines", []))
	_seen_lines.append(String(line.get("text_key", "")))
	for e: Dictionary in n.get("effects", []):
		_apply(e)
	_refresh_memory()
	return true


## Specific lines first: one of the lines with an "if" that holds (the most specific weigh
## more), else one of the lines without conditions; lines already said in this conversation
## wait while others remain.
func pick_line(lines: Array) -> Dictionary:
	var specific: Array = []
	var plain: Array = []
	for l: Dictionary in lines:
		if ChatterBook.specificity(l) == 0:
			plain.append(l)
		elif ChatterBook.matches(l.get("if", {}), ctx):
			specific.append(l)
	var fresh := func(a: Array) -> Array:
		return a.filter(func(l: Dictionary) -> bool: return not String(l.get("text_key", "")) in _seen_lines)
	var pool: Array = specific
	if (fresh.call(specific) as Array).is_empty() and not (fresh.call(plain) as Array).is_empty():
		pool = plain   # the fitting lines were said already: something else this time
	elif specific.is_empty():
		pool = plain
	var out := ChatterBook.pick(pool, ctx, rng, _seen_lines)
	if out.is_empty() and not lines.is_empty():
		out = lines[0]
	return out


## The line on show, translated, its {placeholders} filled.
func text() -> String:
	return ChatterBook.text(String(line.get("text_key", "")), vars)


## The choices on show: [{"text", "index"}] (index for choose()).
func choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list := _choice_list()
	for i in list.size():
		var c: Dictionary = list[i]
		if not ChatterBook.matches(c.get("if", {}), ctx):
			continue
		if bool(c.get("once", false)) and _picked.has(_choice_id(c)):
			continue
		out.append({"text": ChatterBook.text(String(c.get("text_key", "")), vars), "index": i,
			"end": bool(c.get("end", false))})
	return out


## Picks choice `index` (from choices()): its effects, then its node or the end. Returns false
## when the conversation is over.
func choose(index: int) -> bool:
	var list := _choice_list()
	if _over or index < 0 or index >= list.size():
		return false
	var c: Dictionary = list[index]
	_picked[_choice_id(c)] = true
	for e: Dictionary in c.get("effects", []):
		_apply(e)
	if bool(c.get("end", false)) or String(c.get("goto", "")) == "":
		_over = true
		return false
	return goto(String(c["goto"]))


func pose() -> String:
	return String(line.get("pose", ""))


func face() -> String:
	return String(line.get("face", ""))


func _choice_list() -> Array:
	var n: Dictionary = (tree.get("nodes", {}) as Dictionary).get(node_id, {})
	var c: Variant = n.get("choices", [])
	if c is String:
		return (tree.get("menus", {}) as Dictionary).get(c, [])
	return c if c is Array else []


func _choice_id(c: Dictionary) -> String:
	return "%s>%s" % [c.get("text_key", ""), c.get("goto", "")]


# ------------------------------------------------------------ memory and effects
## The conversation memory of the campaign (TycoonState.story["talk"]), made when first written.
func memory() -> Dictionary:
	if state == null:
		return {}
	if not state.story.get(STORE) is Dictionary:
		state.story[STORE] = {}
	var t: Dictionary = state.story[STORE]
	for k in ["week", "hint", "flags"]:
		if not t.get(k) is Dictionary:
			t[k] = {}
	return t


## Reads the memory without writing anything (a talk that changes nothing leaves no trace).
func _peek(part: String) -> Dictionary:
	if state == null or not state.story.get(STORE) is Dictionary:
		return {}
	var p: Variant = (state.story[STORE] as Dictionary).get(part, {})
	return p if p is Dictionary else {}


func _refresh_memory() -> void:
	var weeks := state.weeks if state else -1
	var w := _peek("week")
	ctx["talked_week"] = w.has(who) and int(w[who]) == weeks
	ctx["flags"] = (_peek("flags").get(who, {}) as Dictionary).keys()


func _apply(e: Dictionary) -> void:
	if e.has("morale"):
		_morale(int(e["morale"]))
	if e.has("flag"):
		if state:
			var f: Dictionary = memory()["flags"]
			if not f.get(who) is Dictionary:
				f[who] = {}
			f[who][String(e["flag"])] = true
		done.append({"effect": "flag", "flag": String(e["flag"])})
	if bool(e.get("hint", false)):
		_hint()
	if e.has("lesson"):
		after.append({"lesson": String(e["lesson"])})
		done.append({"effect": "lesson", "lesson": String(e["lesson"])})
	if e.has("say"):
		after.append({"say": String(e["say"])})
		done.append({"effect": "say", "key": String(e["say"])})


func _morale(n: int) -> void:
	if state == null or member.is_empty():
		return
	var t := memory()
	if t["week"].has(who) and int(t["week"][who]) == state.weeks:
		done.append({"effect": "morale_capped"})
		note = ChatterBook.text("TY_DLG_NOTE_AGAIN", vars)
		return
	t["week"][who] = state.weeks
	var before := float(member.get("morale", 70.0))
	member["morale"] = clampf(before + n, 0.0, 100.0)
	var gained := int(round(float(member["morale"]) - before))
	ctx["morale"] = float(member["morale"])
	done.append({"effect": "morale", "amount": gained})
	note = ChatterBook.text("TY_DLG_NOTE_MORALE", {"name": vars.get("name", ""), "n": gained}) if gained > 0 \
		else ChatterBook.text("TY_DLG_NOTE_AGAIN", vars)
	state.changed.emit()


func _hint() -> void:
	var h := hint_entry()
	if state == null or h.is_empty():
		return
	var t := memory()
	if t["hint"].has(who) and int(t["hint"][who]) == state.weeks:
		done.append({"effect": "hint_known"})
		return
	t["hint"][who] = state.weeks
	Discovery.note(state, String(h["key"]), h.get("args", []))
	done.append({"effect": "hint", "key": String(h["key"])})
	note = ChatterBook.text("TY_DLG_NOTE_HINT", vars)


# ------------------------------------------------------------ the tip about the mission
## The briefing the speaker would talk about: their project's, else any project's, else the
## first one on the mission board. {} when there is none.
func briefing() -> Dictionary:
	if state == null:
		return {}
	var pid := String(member.get("assigned", ""))
	var any := ""
	for p: MissionProject in state.mission_projects:
		if p.briefing_id == "":
			continue
		if p.id == pid:
			return BriefingDesk.briefing(p.briefing_id)
		if any == "":
			any = p.briefing_id
	if any != "":
		return BriefingDesk.briefing(any)
	for o: Dictionary in state.discovery.get("board", []):
		var b := BriefingDesk.briefing(String(o.get("id", "")))
		if not b.is_empty():
			return b
	return {}


## The team hint (Discovery.briefing_hints, the briefing's "A equipe comenta") this speaker can
## give: their own first, else a journal line. {"key", "args"} or {}.
func hint_entry() -> Dictionary:
	var b := briefing()
	if b.is_empty():
		return {}
	var hints := Discovery.briefing_hints(state, b)
	var name := String(member.get("name", ""))
	for h in hints:
		if name != "" and String(h.get("who", "")) == name:
			return h
	for h in hints:
		if String(h.get("who", "")) == "":
			return h
	return {}


## The tip in the speaker's own voice ("" when they have none): the briefing hint's first-person
## form (TY_DLG_HINT_*, without their name), or the hint as the briefing screen says it.
func hint_text() -> String:
	var h := hint_entry()
	if h.is_empty():
		return ""
	var key := String(h.get("key", ""))
	var args: Array = (h.get("args", []) as Array).duplicate()
	var own := "TY_DLG_" + key.trim_prefix("TY_BF_")
	if String(h.get("who", "")) != "" and not args.is_empty():
		args.remove_at(0)   # the speaker's name
	if TranslationServer.translate(own) != own:
		return TycoonHUD.news_text({"key": own, "args": args})
	return TycoonHUD.news_text(h)
