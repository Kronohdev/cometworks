extends SceneTree
## Cometlings with memory (src/tycoon/crew/crew_memory.gd, data/tycoon/crew_memory.json):
##   - a launch is written into its team's memory (code, kind, target, outcome first / success /
##     partial / failure, week), never into the others'
##   - personal milestones (first mission, first success, pioneer, first lunar probe, survived 3
##     explosions, veteran of 10 missions...) are earned once, in order
##   - the stored missions are capped per Cometling while the totals and milestones stay whole,
##     and the memory stays small in the save
##   - old saves (no "memory") load with an empty memory and save without one; a memory saved
##     and loaded comes back the same (ints, not floats) and launches after a load still count
##   - the chatter / dialogue context (mem_proud, mem_nervous, mem_last...) and placeholders
##     ({mission}, {mission_ok}, {mission_fail}, {milestone}...): every memory line of
##     chatter.json and dialogues.json fills all its placeholders, pride after a success, nerves
##     on a project of a kind that once failed, and the "Lembra das suas missões?" choice
## Run: godot --headless --path . --script res://tests/test_crew_memory.gd

var _failures := 0


func _staff() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": "a", "name": "Ana", "profession": "systems_engineer", "level": 1},
		{"id": "b", "name": "Bia", "profession": "scientist", "level": 1},
		{"id": "c", "name": "Caio", "profession": "pilot", "level": 2, "xp": 100.0},
		{"id": "d", "name": "Duda", "profession": "flight_controller", "level": 1}]
	return out


func _initialize() -> void:
	TranslationServer.set_locale("pt_BR")
	_launches()
	_cap_and_milestones()
	_saves()
	_talk()
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _state(seed := 11) -> TycoonState:
	var s := TycoonState.new_campaign(seed, _staff())
	TycoonCrew.ensure(s)
	s.cash = 5.0e6
	return s


## Starts a sounding with `team` and flies it at once with the forced outcome; the history entry.
func _fly(s: TycoonState, team: Array, outcome: String, type_id := "sounding", target_id := "suborbital") -> Dictionary:
	var p := ProjectDesk.start_project(s, type_id, target_id, team)
	if p == null:
		_check(false, "project %s/%s starts (%s)" % [type_id, target_id, ProjectDesk.start_error(s, type_id, target_id, team)])
		return {}
	ProjectDesk.dev_force_outcome = outcome
	ProjectDesk.dev_finish_development(s, p.id)
	ProjectDesk.dev_force_outcome = ""
	return ProjectDesk.history_entry(s, p.id)


# ------------------------------------------------------------ launches
func _launches() -> void:
	print("launches")
	var s := _state()
	var a := TycoonCrew.find(s, "a")
	_check(CrewMemory.missions(a).is_empty() and not a.has("memory"), "a new Cometling remembers nothing (and stores nothing)")
	var h := _fly(s, ["a", "b"], "success")
	_check(not h.is_empty() and bool(h["success"]), "SND-01 flew")
	var rows := CrewMemory.missions(a)
	_check(rows.size() == 1 and String(rows[0]["code"]) == String(h["code"]) and String(rows[0]["type"]) == "sounding"
		and String(rows[0]["target"]) == "suborbital" and int(rows[0]["w"]) == s.weeks,
		"the team remembers the mission: %s" % str(rows))
	_check(String(rows[0]["o"]) == "first", "the agency's very first mission is a first-ever (%s)" % rows[0].get("o"))
	_check(CrewMemory.missions(TycoonCrew.find(s, "b")).size() == 1, "every team member remembers it")
	_check(CrewMemory.missions(TycoonCrew.find(s, "c")).is_empty(), "who was not on the team does not")
	var ids := CrewMemory.milestone_ids(a)
	_check(ids == ["first_mission", "first_success", "pioneer"], "first milestones in order: %s" % str(ids))
	var h2 := _fly(s, ["a", "c"], "fail")
	_check(not h2.is_empty() and not bool(h2["success"]), "SND-02 failed")
	rows = CrewMemory.missions(a)
	_check(rows.size() == 2 and String(rows[1]["o"]) == "failure", "a failure is remembered as one")
	_check("survivor_1" in CrewMemory.milestone_ids(a) and CrewMemory.milestone_ids(TycoonCrew.find(s, "c")) == ["first_mission", "survivor_1"],
		"a first explosion is a milestone (a newcomer: %s)" % str(CrewMemory.milestone_ids(TycoonCrew.find(s, "c"))))
	var h3 := _fly(s, ["a"], "partial")
	_check(String(CrewMemory.missions(a)[2]["o"]) == "partial" and String(h3.get("outcome", "")) == "partial", "a partial is remembered as one")
	var h4 := _fly(s, ["a"], "success")
	_check(String(CrewMemory.missions(a)[3]["o"]) == "success", "a later success is a plain success (no first-ever)")
	_check(CrewMemory.count(a, "missions") == 4 and CrewMemory.count(a, "successes") == 2
		and CrewMemory.count(a, "failures") == 1 and CrewMemory.count(a, "partials") == 1 and CrewMemory.count(a, "firsts") == 1,
		"totals: %s" % str(CrewMemory.of(a)["n"]))
	_check(CrewMemory.outcome_of(h4) == "success" and CrewMemory.outcome_of(h2) == "failure", "outcome_of reads history entries")


# ------------------------------------------------------------ cap and milestones
func _entry(code: String, success: bool, outcome: String, week: int, type_id := "orbiter", target_id := "lunar_orbit") -> Dictionary:
	return {"code": code, "type": type_id, "target": target_id, "success": success, "outcome": outcome, "novelty": false, "week": week}


func _cap_and_milestones() -> void:
	print("cap and milestones")
	var s := _state(12)
	var cap := CrewMemory.cap()
	_check(cap >= 5 and cap <= 30, "the stored history is capped (%d missions)" % cap)
	var got: Array[Dictionary] = CrewMemory.record(s, ["b"], _entry("ORB-01", true, "full", 10))
	_check(got.map(func(e: Dictionary) -> String: return String(e["id"])) == ["first_mission", "first_success", "first_lunar_probe"],
		"a lunar orbiter: first lunar probe (%s)" % str(got))
	for i in 3:
		CrewMemory.record(s, ["b"], _entry("ORB-%02d" % (i + 2), false, "fail", 20 + i))
	var b := TycoonCrew.find(s, "b")
	_check("survivor_3" in CrewMemory.milestone_ids(b), "sobreviveu a 3 explosões")
	_check(not "veteran_5" in CrewMemory.milestone_ids(b), "4 missions: no veteran of 5 yet")
	for i in 20:
		CrewMemory.record(s, ["b"], _entry("TEL-%02d" % (i + 1), true, "exceptional" if i == 5 else "full", 30 + i, "telescope", "geo"))
	var rows := CrewMemory.missions(b)
	_check(rows.size() == cap, "only the newest %d missions are kept (%d)" % [cap, rows.size()])
	_check(String(rows[rows.size() - 1]["code"]) == "TEL-20" and String(rows[0]["code"]) == "TEL-%02d" % (21 - cap),
		"the oldest ones go first")
	_check(CrewMemory.count(b, "missions") == 24 and CrewMemory.count(b, "failures") == 3, "the totals stay whole (24 missions)")
	var ids := CrewMemory.milestone_ids(b)
	_check("veteran_5" in ids and "veteran_10" in ids and "first_orbit" in ids and "exceptional" in ids,
		"veteran of 5 and 10, first orbit, flawless: %s" % str(ids))
	var uniq := {}
	for id in ids:
		uniq[id] = true
	_check(uniq.size() == ids.size(), "each milestone is earned once")
	var size := JSON.stringify(b["memory"]).length()
	_check(size < 2000, "a full memory stays small in the save (%d chars)" % size)
	var ms := CrewMemory.milestones_of(b)
	_check(ms.size() == ids.size() and ms[0]["color"] is Color and ResourceLoader.exists(String(ms[0]["icon"])),
		"milestones carry their names, colours and icons")
	var all_icons := true
	for m: Dictionary in CrewMemory.data().get("milestones", []):
		all_icons = all_icons and ResourceLoader.exists(CrewMemory.ICONS % String(m.get("icon", "")))
		_check(tr(String(m["name_key"])) != String(m["name_key"]) and tr(String(m["desc_key"])) != String(m["desc_key"]),
			"milestone %s is translated" % m["id"])
	_check(all_icons, "every milestone icon exists")


# ------------------------------------------------------------ saves
func _saves() -> void:
	print("saves")
	var s := _state(13)
	_fly(s, ["a", "d"], "success")
	_fly(s, ["a"], "fail")
	var d := JSON.parse_string(JSON.stringify(s.to_dict())) as Dictionary
	var l := TycoonState.from_dict(d)
	var a0 := TycoonCrew.find(s, "a")
	var a1 := TycoonCrew.find(l, "a")
	_check(JSON.stringify(CrewMemory.of(a1)) == JSON.stringify(CrewMemory.of(a0)), "the memory comes back the same after save / load")
	_check(CrewMemory.of(a1)["n"]["missions"] is int and (CrewMemory.missions(a1)[0]["w"]) is int, "numbers come back as ints")
	_check(not TycoonCrew.find(l, "b").has("memory") and not (d["staff"] as Array)[1].has("memory"),
		"a Cometling without missions saves no memory")
	TycoonCrew.ensure(l)
	l.cash = 5.0e6
	_fly(l, ["a", "b"], "success")
	_check(CrewMemory.count(TycoonCrew.find(l, "a"), "missions") == 3 and CrewMemory.missions(TycoonCrew.find(l, "b")).size() == 1,
		"launches after a load still go into memory")
	# an old save: staff with no memory at all, or a broken one
	var old := s.to_dict().duplicate(true)
	for m: Dictionary in old["staff"]:
		m.erase("memory")
	(old["staff"] as Array)[3]["memory"] = "garbage"
	var o := TycoonState.from_dict(JSON.parse_string(JSON.stringify(old)) as Dictionary)
	var oa := TycoonCrew.find(o, "a")
	_check(CrewMemory.missions(oa).is_empty() and CrewMemory.milestone_ids(oa).is_empty() and CrewMemory.count(oa, "missions") == 0,
		"an old save loads with empty memories")
	var od := TycoonCrew.find(o, "d")
	_check(CrewMemory.missions(od).is_empty() and int(CrewMemory.context(o, od)["mem_missions"]) == 0, "a broken memory reads as empty")
	var ctx := ChatterBook.context(o, oa)
	_check(int(ctx["mem_missions"]) == 0 and String(ctx["mem_last"]) == "" and not bool(ctx["mem_proud"]) and not bool(ctx["mem_nervous"]),
		"an empty memory gives a quiet context")
	_check(not ChatterBook.vars_for(o, oa).has("mission"), "and no mission placeholders")


# ------------------------------------------------------------ chatter and dialogue
func _talk() -> void:
	print("chatter and dialogue")
	var s := _state(14)
	var h1 := _fly(s, ["a", "b"], "success")
	var a := TycoonCrew.find(s, "a")
	var ctx := ChatterBook.context(s, a)
	var v := ChatterBook.vars_for(s, a)
	_check(bool(ctx["mem_proud"]) and String(ctx["mem_last"]) == "first" and int(ctx["mem_missions"]) == 1,
		"pride right after a success (%s)" % str(ctx))
	_check(String(v["mission"]) == String(h1["code"]) and String(v["mission_ok"]) == String(h1["code"]) and String(v.get("milestone", "")) != "",
		"placeholders: the mission's name, the success, the newest milestone")
	s.weeks += int(CrewMemory.data().get("proud_weeks", 26)) + 1
	_check(not bool(ChatterBook.context(s, a)["mem_proud"]), "pride fades after proud_weeks")
	var h2 := _fly(s, ["b"], "fail")
	var b := TycoonCrew.find(s, "b")
	_check(not bool(ChatterBook.context(s, b)["mem_nervous"]), "a failure alone is no nerves: not on a project")
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", ["b", "c"])
	var cb := ChatterBook.context(s, b)
	var vb := ChatterBook.vars_for(s, b)
	_check(bool(cb["mem_nervous"]) and String(vb["mission_fail"]) == String(h2["code"]),
		"nervous on a new sounding after %s failed (%s)" % [h2["code"], vb.get("mission_fail")])
	_check(not bool(ChatterBook.context(s, TycoonCrew.find(s, "c"))["mem_nervous"]), "a teammate who never saw it fail is calm")
	# every memory line fills its placeholders, for the nervous one and the proud one
	s.weeks -= int(CrewMemory.data().get("proud_weeks", 26)) + 1
	var speakers := [[cb, vb], [ChatterBook.context(s, a), ChatterBook.vars_for(s, a)]]
	var lines: Array = []
	var ch := ChatterBook.chatter()
	for l: Dictionary in ch.get("lines", []):
		if String(l["text_key"]).begins_with("TY_MEM_"):
			lines.append([l.get("if", {}), String(l["text_key"])])
	for pr: Dictionary in ch.get("pairs", []):
		if String(pr["a_key"]).begins_with("TY_MEM_"):
			lines.append([pr.get("if", {}), String(pr["a_key"])])
			lines.append([pr.get("if", {}), String(pr["b_key"])])
	for n: Dictionary in (ChatterBook.dialogues()["trees"]["cometling"]["nodes"] as Dictionary).values():
		for l: Dictionary in n.get("lines", []):
			if String(l["text_key"]).begins_with("TY_MEM_"):
				lines.append([l.get("if", {}), String(l["text_key"])])
	_check(lines.size() >= 20, "%d memory lines in chatter and dialogues" % lines.size())
	var said := {}
	var unfilled := 0
	for sp: Array in speakers:
		var vv: Dictionary = (sp[1] as Dictionary).duplicate()
		vv["other"] = "Duda"
		vv["hint"] = ""
		for ln: Array in lines:
			if ChatterBook.matches(ln[0], sp[0]) or String(ln[1]).ends_with("_B"):
				var t := ChatterBook.text(String(ln[1]), vv)
				said[ln[1]] = true
				if "{" in t or t == String(ln[1]):
					unfilled += 1
					print("    unfilled: %s -> %s" % [ln[1], t])
	_check(unfilled == 0, "memory lines fill every placeholder (%d lines said)" % said.size())
	_check(said.has("TY_MEM_CHAT_NERVOUS_1") and said.has("TY_MEM_CHAT_PROUD_1") and said.has("TY_MEM_CHAT_REMEMBER_1"),
		"nervous, proud and remembering lines all come up")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var nervous_pick := 0
	for i in 60:
		if String(ChatterBook.pick(ch["lines"], cb, rng)["text_key"]).begins_with("TY_MEM_CHAT_NERVOUS"):
			nervous_pick += 1
	_check(nervous_pick >= 6, "a nervous Cometling often says so (%d of 60 bubbles)" % nervous_pick)
	var txt := ChatterBook.text("TY_MEM_CHAT_REMEMBER_1", ChatterBook.vars_for(s, a))
	_check(txt.contains(String(h1["code"])), "Lembra da ...: \"%s\"" % txt)
	# the dialogue: the memory choice, and the line names the mission
	var r := DialogueRun.new(s, a)
	r.start(rng)
	var idx := -1
	var cs := r.choices()
	for c: Dictionary in cs:
		if String(c["text"]) == tr("TY_MEM_DLG_ASK"):
			idx = int(c["index"])
	_check(idx >= 0, "the talk offers 'Lembra das suas missões?' to a Cometling with missions")
	if idx >= 0:
		r.choose(idx)
		_check(String(r.line.get("text_key", "")).begins_with("TY_MEM_DLG_") and r.text().contains(String(h1["code"]))
			and not "{" in r.text(), "they answer about their own mission: \"%s\"" % r.text())
	var rc := DialogueRun.new(s, TycoonCrew.find(s, "d"))
	rc.start(rng)
	var offered := false
	for c: Dictionary in rc.choices():
		offered = offered or String(c["text"]) == tr("TY_MEM_DLG_ASK")
	_check(not offered, "a Cometling with no missions is not asked about them")
	var rn := DialogueRun.new(s, b)
	rn.start(rng, "memory")
	_check(String(rn.line.get("text_key", "")) == "TY_MEM_DLG_NERVOUS" or not "{" in rn.text(),
		"the nervous Cometling talks about %s: \"%s\"" % [h2["code"], rn.text()])
	if p:
		ProjectDesk.scrub(s, p.id)


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
