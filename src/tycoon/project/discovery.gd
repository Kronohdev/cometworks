class_name Discovery
extends RefCounted
## The agency's discovery journal ("Caderno de descobertas"): what it has learned about the
## hidden ideals by flying (Game Dev Tycoon style). Kept in TycoonState.discovery:
##   attempts {type: launches}       the ideal balance of a type shows after reveal_ratio_after
##   combos {"type|target": {"n", "best", "tier", "great"}}   type x target tried, best grade,
##                                    compat tier, a great combo got
##   instr {"type|target": {module: "great" | "good" | "useless" | "bad"}}   instrument ratings
##   env {target: true}               the hidden environment (night, cold, low sun) is known
##   teams {type: {"grade", "profs" {profession: n}}}   the team of the best grade
##   notes [{"week", "key", "args"}]   the journal's feed, newest first
##   study {type: tier}               mission studies of the lab (FocusStudy): tier 3 = the balance
##   all (bool)                       dev: everything revealed
##   board / taken / done             the briefing board (BriefingDesk)
## Techs reveal some facts early (payload.json reveal_by_tech) and Cometlings of the staff give
## hints on a briefing (curious scientists, seasoned engineers, veterans).

const RATINGS := {2: "great", 1: "good", 0: "useless", -1: "bad"}
const BAR_PROFESSION := {"eng": "systems_engineer", "sci": "scientist", "ops": "flight_controller",
	"rel": "test_technician"}


static func d(state: TycoonState) -> Dictionary:
	var j := state.discovery
	for k in ["attempts", "combos", "instr", "env", "teams", "taken", "done"]:
		if not j.has(k):
			j[k] = {}
	for k in ["notes", "board"]:
		if not j.has(k):
			j[k] = []
	if not j.has("all"):
		j["all"] = false
	return j


static func key(type_id: String, target_id: String) -> String:
	return "%s|%s" % [type_id, target_id]


static func cfg() -> Dictionary:
	return BriefingDesk.disc()


static func _tech_reveals(state: TycoonState, kind: String, id: String) -> bool:
	var rv: Dictionary = PayloadRules.section("reveal_by_tech")
	for tech: String in rv:
		if id in (rv[tech] as Dictionary).get(kind, []) and TycoonResearch.is_done(state, tech):
			return true
	return false


# ------------------------------------------------------------ queries
## `briefing_id`: a briefing whose story tells the target's environment ("teaches") counts.
static func env_known(state: TycoonState, target_id: String, briefing_id := "") -> bool:
	var j := d(state)
	if j["all"] or (PayloadRules.env_true(target_id).get("hidden", []) as Array).is_empty():
		return true
	if target_id in ((BriefingDesk.briefing(briefing_id).get("teaches", {}) as Dictionary).get("env", []) as Array):
		return true
	return bool((j["env"] as Dictionary).get(target_id, false)) or _tech_reveals(state, "env", target_id)


## "Strong sun · long nights · freezing cold", "?" for the facts the agency does not know.
static func env_text(s: TycoonState, target: String, briefing := "") -> String:
	var known := env_known(s, target, briefing)
	var e := PayloadRules.env_true(target)
	var hidden: Array = e.get("hidden", []) if not known else []
	var parts: Array[String] = []
	if "sun" in hidden:
		parts.append(TranslationServer.translate("TY_PL_ENV_SUN_UNKNOWN"))
	else:
		var sun := float(e.get("sun", 1.0))
		parts.append(TranslationServer.translate("TY_PL_ENV_SUN_STRONG" if sun >= 0.9 else ("TY_PL_ENV_SUN_WEAK" if sun >= 0.45 else "TY_PL_ENV_SUN_FAINT")))
	if "night" in hidden:
		parts.append(TranslationServer.translate("TY_PL_ENV_NIGHT_UNKNOWN"))
	else:
		var n := float(e.get("night", 0.0))
		parts.append(TranslationServer.translate("TY_PL_ENV_NIGHT_NONE" if n <= 0.0 else ("TY_PL_ENV_NIGHT_SHORT" if n <= 1.0
			else ("TY_PL_ENV_NIGHT_LONG" if n <= 5.0 else "TY_PL_ENV_NIGHT_LUNAR"))))
	if "cold" in hidden:
		parts.append(TranslationServer.translate("TY_PL_ENV_COLD_UNKNOWN"))
	else:
		parts.append(TranslationServer.translate("TY_PL_ENV_COLD" if e.get("cold", false) else "TY_PL_ENV_MILD"))
	return " · ".join(parts)


static func attempts(state: TycoonState, type_id: String) -> int:
	return int((d(state)["attempts"] as Dictionary).get(type_id, 0))


static func ratio_known(state: TycoonState, type_id: String) -> bool:
	var j := d(state)
	return j["all"] or attempts(state, type_id) >= int(cfg().get("reveal_ratio_after", 2)) \
		or _tech_reveals(state, "ratio", type_id) \
		or int((j.get("study", {}) as Dictionary).get(type_id, 0)) >= FocusStudy.MAX_TIER


## Rating of a module flown on a type at a target: "great" | "good" | "useless" | "bad", "" unknown.
static func instr_rating(state: TycoonState, type_id: String, target_id: String, module_id: String) -> String:
	var j := d(state)
	if j["all"]:
		return String(RATINGS.get(MissionFit.instrument_fit(type_id, target_id, module_id), ""))
	return String(((j["instr"] as Dictionary).get(key(type_id, target_id), {}) as Dictionary).get(module_id, ""))


static func combo(state: TycoonState, type_id: String, target_id: String) -> Dictionary:
	var j := d(state)
	var c: Dictionary = (j["combos"] as Dictionary).get(key(type_id, target_id), {})
	if j["all"] and c.is_empty():
		var mult := ProjectRules.compat(state.mission_type(type_id), target_id)
		if mult > 0.0:
			return {"n": 0, "best": 0.0, "tier": ProjectRules.compat_tier(mult), "great": false}
	return c


## Is the compat tier of this type x target known (flown, or revealed)?
static func compat_known(state: TycoonState, type_id: String, target_id: String) -> bool:
	return not combo(state, type_id, target_id).is_empty() or ProjectDesk.compat_known(state, type_id, target_id)


static func team_note(state: TycoonState, type_id: String) -> Dictionary:
	return (d(state)["teams"] as Dictionary).get(type_id, {})


static func notes(state: TycoonState) -> Array:
	return d(state)["notes"]


## How many things the journal knows (for the HUD / screens): combos, ratings, envs, ratios.
static func count(state: TycoonState) -> int:
	var j := d(state)
	var n: int = (j["combos"] as Dictionary).size() + (j["env"] as Dictionary).size()
	for k: String in j["instr"]:
		n += (j["instr"][k] as Dictionary).size()
	for t: Dictionary in state.mdata.get("types", []):
		n += 1 if ratio_known(state, String(t["id"])) else 0
	return n


## The lever ranges that give a balance close to `ideal` in each phase: for each of the 3
## phases, [[lo, hi, best] x 3 levers] in percent. The best split maximises the phase's focus
## match with the ideal; the range covers the splits within lever_slack of it (lever_step).
static func lever_ranges(ideal: Array) -> Array:
	var step := int(cfg().get("lever_step", 5))
	var slack := float(cfg().get("lever_slack", 0.02))
	var out: Array = []
	for k in 3:
		var combos: Array = []
		var best := -1.0
		for a in range(0, 101, step):
			for b in range(0, 101 - a, step):
				var c := 100 - a - b
				var f := ProjectRules.focus(k, [a / 100.0, b / 100.0, c / 100.0])
				var m := MissionProject.ratio_match(MissionProject.fractions_of(f), ideal)
				combos.append([m, a, b, c])
				best = maxf(best, m)
		var lo := [100, 100, 100]
		var hi := [0, 0, 0]
		var top: Array = []
		for e: Array in combos:
			if float(e[0]) >= best - slack:
				for i in 3:
					lo[i] = mini(lo[i], int(e[i + 1]))
					hi[i] = maxi(hi[i], int(e[i + 1]))
			if float(e[0]) >= best - 1e-6 and top.is_empty():
				top = e
		var row: Array = []
		for i in 3:
			row.append([lo[i], hi[i], int(top[i + 1])])
		out.append(row)
	return out


# ------------------------------------------------------------ hints on a briefing
## What the staff can tell about a briefing before the plan (at most 3 lines):
##   a curious scientist / researcher names a module the job needs that the journal has not
##   rated yet; a skilled engineer / controller / tester warns about a hidden fact of the target;
##   a veteran (level >= hint.level) bets on the mission type; the journal recalls a combo flown.
## [{"who", "key", "args"}]
static func briefing_hints(state: TycoonState, b: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if b.is_empty():
		return out
	var h: Dictionary = cfg().get("hint", {})
	var ty := BriefingDesk.best_type(b)
	var tg := BriefingDesk.best_target(b)
	var crew: Array[Dictionary] = state.staff
	# a module the job needs
	for m in crew:
		if String(m.get("profession", "")) in ["scientist", "researcher"] and float(m.get("curiosity", 0.0)) >= float(h.get("curiosity", 0.6)):
			for need in BriefingDesk.needs(b):
				if instr_rating(state, ty, tg, String(need)) == "":
					out.append({"who": String(m.get("name", "")), "key": "TY_BF_HINT_MODULE",
						"args": [String(m.get("name", "")), PayloadRules.name_key(String(need))]})
					break
			break
	# a hidden fact of the target
	if not env_known(state, tg):
		var hidden: Array = PayloadRules.env_true(tg).get("hidden", [])
		for m in crew:
			if String(m.get("profession", "")) in ["systems_engineer", "flight_controller", "test_technician"] \
					and (float(m.get("skill", 0.0)) >= float(h.get("skill", 0.6)) or int(m.get("level", 1)) >= int(h.get("level", 3))):
				out.append({"who": String(m.get("name", "")), "key": "TY_BF_HINT_ENV_" + String(hidden[0]).to_upper(),
					"args": [String(m.get("name", "")), String(state.mission_target(tg).get("name_key", ""))]})
				break
	# a veteran's bet on the type
	for m in crew:
		if int(m.get("level", 1)) >= int(h.get("level", 3)):
			out.append({"who": String(m.get("name", "")), "key": "TY_BF_HINT_TYPE",
				"args": [String(m.get("name", "")), String(state.mission_type(ty).get("name_key", ""))]})
			break
	# the journal remembers
	if out.size() < 3:
		var c := combo(state, ty, tg)
		if not c.is_empty() and int(c.get("n", 0)) > 0:
			out.append({"who": "", "key": "TY_BF_HINT_JOURNAL", "args": [String(state.mission_type(ty).get("name_key", "")),
				String(state.mission_target(tg).get("name_key", "")), "%.1f" % float(c.get("best", 0.0))]})
	return out.slice(0, 3)


# ------------------------------------------------------------ learning
static func note(state: TycoonState, k: String, args: Array) -> void:
	var n: Array = d(state)["notes"]
	n.push_front({"week": state.weeks, "key": k, "args": args})
	while n.size() > int(cfg().get("notes_keep", 30)):
		n.pop_back()


## A project launched: the journal writes down what this flight taught. Returns the notes
## added (the review screen says "+N in the journal").
static func record(state: TycoonState, p: MissionProject, report: Dictionary, grade: float, success: bool) -> Array[Dictionary]:
	var j := d(state)
	var before: int = (j["notes"] as Array).size()
	var added: Array[Dictionary] = []
	var tname := String(state.mission_type(p.type_id).get("name_key", ""))
	var gname := String(state.mission_target(p.target_id).get("name_key", ""))
	# the ideal balance of the type
	var knew_ratio := ratio_known(state, p.type_id)
	var focus_before := FocusStudy.tier(state, p.type_id)
	var att: Dictionary = j["attempts"]
	att[p.type_id] = int(att.get(p.type_id, 0)) + 1
	if not knew_ratio and ratio_known(state, p.type_id):
		added.append({"key": "TY_JN_NOTE_RATIO", "args": [tname]})
	elif focus_before == 0 and FocusStudy.tier(state, p.type_id) >= 1:
		# the first flight of a type tells which bar mattered most (FocusStudy tier 1)
		added.append({"key": "TY_JN_NOTE_FOCUS_FLIGHT", "args": [tname]})
	# the combo
	var ck := key(p.type_id, p.target_id)
	var combos: Dictionary = j["combos"]
	var mult := p.compat(state)
	var c: Dictionary = combos.get(ck, {})
	if c.is_empty():
		added.append({"key": "TY_JN_NOTE_COMBO_" + ProjectRules.compat_tier(mult).to_upper(), "args": [tname, gname]})
	var was_great := bool(c.get("great", false))
	c["n"] = int(c.get("n", 0)) + 1
	c["best"] = maxf(float(c.get("best", 0.0)), grade)
	c["tier"] = ProjectRules.compat_tier(mult)
	c["great"] = was_great or (success and bool(report.get("great", false)))
	combos[ck] = c
	if c["great"] and not was_great:
		added.append({"key": "TY_JN_NOTE_GREAT", "args": [tname, gname]})
	# instrument ratings (the ones flown, and the ones the client missed)
	var ins: Dictionary = j["instr"]
	var row: Dictionary = ins.get(ck, {})
	var rated: Array = PayloadRules.instruments(p.payload)
	for m in report.get("missing", []):
		if PayloadRules.module(String(m)).get("kind", "") == "instrument" and not m in rated:
			rated.append(m)
	for m in rated:
		var r := String(RATINGS.get(MissionFit.instrument_fit(p.type_id, p.target_id, String(m)), "useless"))
		if not row.has(m):
			added.append({"key": "TY_JN_NOTE_INSTR_" + r.to_upper(), "args": [PayloadRules.name_key(String(m)), tname, gname]})
		row[m] = r
	ins[ck] = row
	# the environment, once a spacecraft got there
	if success and not env_known(state, p.target_id):
		(j["env"] as Dictionary)[p.target_id] = true
		for f: String in PayloadRules.env_true(p.target_id).get("hidden", []):
			added.append({"key": "TY_JN_NOTE_ENV_" + f.to_upper(), "args": [gname]})
	elif success:
		(j["env"] as Dictionary)[p.target_id] = true
	# the team of the best grade
	var teams: Dictionary = j["teams"]
	var tn: Dictionary = teams.get(p.type_id, {})
	if grade > float(tn.get("grade", -1.0)):
		var profs := {}
		for m in p.team(state):
			var pr := String(m.get("profession", ""))
			profs[pr] = int(profs.get(pr, 0)) + 1
		teams[p.type_id] = {"grade": grade, "profs": profs, "target": p.target_id}
	for a in added:
		note(state, String(a["key"]), a["args"])
	return added


## Dev menu: the journal knows everything (every rating, environment, balance and combo tier).
static func reveal_all(state: TycoonState) -> void:
	var j := d(state)
	j["all"] = true
	for t: Dictionary in state.mdata.get("targets", []):
		(j["env"] as Dictionary)[String(t["id"])] = true
	note(state, "TY_JN_NOTE_ALL", [])
	state.changed.emit()
