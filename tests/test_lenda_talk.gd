extends SceneTree
## The Lendas talk (data/tycoon/dialogues.json "lenda_<id>" trees, DialogueRun.for_legend,
## CometlingDialogue.open_legend):
##   - trees: every Lenda of legends.json has its own tree; start node, menus and gotos exist,
##     every node can be reached from the start, the talk can end; every line and choice is
##     translated in pt and en and fits the box; mentors and rival leaders never nudge morale or
##     write tips (they are not staff); poses and faces are known
##   - talking: every choice of every Lenda gives a filled line (no {placeholder} left) in both
##     languages, early and late in the campaign
##   - rivalry: a rival leader's banter follows the race (their agency ahead, behind, level)
##   - places: a hired Lenda walking the campus opens her own tree with "Conversar"; a mentor's
##     bubble on a briefing has "Conversar" and opens the box over the screen; a rival leader's
##     agency page on the race board too; closing the screen closes the talk
##   - the Lenda-to-Lenda campus exchanges exist and their speakers are hires
## Run: godot --headless --path . --script res://tests/test_lenda_talk.gd

const MAX_DIALOGUE := 190
const NO_STAFF_EFFECTS := ["morale", "hint"]
## condition keys the trees may use (ChatterBook.context + DialogueRun)
const CTX_KEYS := ["profession", "mood", "morale", "tired", "status", "doing", "place", "era", "year",
	"comet_years", "staff", "time", "events", "money", "team_mood", "who", "leader", "legend", "level",
	"project", "has_hint", "talked_week", "flags", "where", "rival_vs", "race_place", "milestones", "missions_done"]

var _failures := 0


func _initialize() -> void:
	await process_frame
	_trees()
	_talking()
	_rivalry()
	_pairs()
	await _places()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)


func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


func _cond_keys(c: Variant, bad: Array[String], where: String) -> void:
	if not c is Dictionary:
		return
	for k: String in c:
		var base := k.trim_prefix("not_").trim_suffix("_min").trim_suffix("_max")
		if not base in CTX_KEYS:
			bad.append("%s: %s" % [where, k])


# ------------------------------------------------------------ trees
func _trees() -> void:
	print("trees")
	var d := ChatterBook.dialogues()
	var by: Dictionary = d.get("by_legend", {})
	var trees: Dictionary = d.get("trees", {})
	var problems: Array[String] = []
	var keys: Dictionary = {}
	var n := 0
	for l: Dictionary in TycoonLegends.all():
		var id := String(l["id"])
		var kind := String(l.get("kind", ""))
		var tid := String(by.get(id, ""))
		if tid == "" or not trees.has(tid) or tid == String(d.get("legend", "legend")):
			problems.append("%s has no tree of its own" % id)
			continue
		n += 1
		var t: Dictionary = trees[tid]
		var nodes: Dictionary = t.get("nodes", {})
		var menus: Dictionary = t.get("menus", {})
		if not nodes.has(String(t.get("start", "start"))):
			problems.append("%s: no start node" % tid)
			continue
		# every node reachable, every goto real, an end
		var seen := {}
		var todo: Array[String] = [String(t.get("start", "start"))]
		var ends := false
		while not todo.is_empty():
			var nid: String = todo.pop_back()
			if seen.has(nid):
				continue
			seen[nid] = true
			var node: Dictionary = nodes.get(nid, {})
			if node.is_empty():
				problems.append("%s: goto %s does not exist" % [tid, nid])
				continue
			for ln: Dictionary in node.get("lines", []):
				keys[String(ln.get("text_key", ""))] = tid
				_cond_keys(ln.get("if", {}), problems, tid)
				var pose := String(ln.get("pose", ""))
				if pose != "" and not (Cometling.ONESHOTS.has(pose) or pose in Cometling.LOOP_ACTIONS or pose in Halleyzinho.HABITS):
					problems.append("%s: pose %s" % [tid, pose])
				var face := String(ln.get("face", ""))
				if face != "" and not face in Cometling.EXPRESSIONS:
					problems.append("%s: face %s" % [tid, face])
			var effects: Array = node.get("effects", []).duplicate()
			var ch: Variant = node.get("choices", [])
			if ch is String:
				if not menus.has(ch):
					problems.append("%s: menu %s does not exist" % [tid, ch])
				ch = menus.get(ch, [])
			for c: Dictionary in ch:
				keys[String(c.get("text_key", ""))] = tid
				_cond_keys(c.get("if", {}), problems, tid)
				effects.append_array(c.get("effects", []))
				if bool(c.get("end", false)) or String(c.get("goto", "")) == "":
					ends = true
				else:
					todo.append(String(c["goto"]))
				for e: Dictionary in c.get("effects", []):
					if e.has("say"):
						keys[String(e["say"])] = tid
			if kind != "hire":
				for e: Dictionary in effects:
					for k: String in NO_STAFF_EFFECTS:
						if e.has(k):
							problems.append("%s (%s) nudges %s" % [tid, kind, k])
		for nid: String in nodes:
			if not seen.has(nid) and tid.begins_with("lenda_"):
				problems.append("%s: node %s cannot be reached" % [tid, nid])
		if not ends:
			problems.append("%s: the talk never ends" % tid)
		if kind == "rival_leader":
			var cover := {}
			for ln: Dictionary in (nodes.get("race", {}) as Dictionary).get("lines", []):
				var rv: Variant = (ln.get("if", {}) as Dictionary).get("rival_vs", null)
				for v in (rv if rv is Array else [rv]):
					cover[v] = true
			if not (cover.has("ahead") and cover.has("behind") and cover.has("even")):
				problems.append("%s: the race banter does not cover ahead / behind / even" % tid)
	_check(n == TycoonLegends.all().size() and n >= 19, "every Lenda (%d) has her own tree" % n)
	_check(problems.is_empty(), "trees are whole: nodes, menus, gotos, reachability, endings, conditions, poses %s" % (str(problems.slice(0, 8)) if not problems.is_empty() else ""))
	var missing: Array[String] = []
	var long: Array[String] = []
	for loc in ["pt_BR", "en"]:
		TranslationServer.set_locale(loc)
		for k: String in keys:
			var tx := tr(k)
			if k == "" or tx == k:
				missing.append("%s:%s" % [loc, k])
			elif tx.length() > MAX_DIALOGUE:
				long.append("%s:%s" % [loc, k])
	TranslationServer.set_locale("pt_BR")
	_check(missing.is_empty(), "%d keys translated in pt and en %s" % [keys.size(), str(missing.slice(0, 6)) if not missing.is_empty() else ""])
	_check(long.is_empty(), "every line fits the box (%d chars) %s" % [MAX_DIALOGUE, str(long) if not long.is_empty() else ""])


# ------------------------------------------------------------ talking
func _state(late: bool) -> TycoonState:
	var s := TycoonState.new_campaign(21, TycoonMain._roster_staff())
	TycoonLeader.found(s, TycoonLeader.make_default(_rng(4)))
	if late:
		s.weeks = 3 * 5 * s.weeks_per_year() + 30   # era 4
		for m: String in ["suborbital", "first_satellite", "long_signal", "cometling_space", "probe_moon"]:
			s.race.claim(m, RaceDirector.PLAYER)
	return s


func _talking() -> void:
	print("talking")
	var bad: Array[String] = []
	var lines := 0
	for late in [false, true]:
		var s := _state(late)
		for loc in ["pt_BR", "en"]:
			TranslationServer.set_locale(loc)
			for l: Dictionary in TycoonLegends.all():
				var id := String(l["id"])
				var where := "race" if String(l.get("kind", "")) == "rival_leader" else ("briefing" if String(l.get("kind", "")) == "mentor" else "campus")
				var r0 := DialogueRun.for_legend(s, id, where)
				if not r0.start(_rng(1)):
					bad.append("%s does not start" % id)
					continue
				var opts := r0.choices()
				for o in opts.size() + 1:
					var r := DialogueRun.for_legend(s, id, where)
					r.start(_rng(o + 7))
					var txt := r.text()
					if o > 0:
						var c: Dictionary = opts[o - 1]
						if bool(c.get("end", false)):
							continue
						r.choose(int(c["index"]))
						txt = r.text()
					lines += 1
					if txt == "" or "{" in txt or txt.begins_with("TY_"):
						bad.append("%s %s: %s" % [loc, id, txt.left(50)])
	TranslationServer.set_locale("pt_BR")
	_check(lines > 150 and bad.is_empty(), "%d answers of every Lenda come out filled in both languages, early and late %s" % [lines, str(bad.slice(0, 6)) if not bad.is_empty() else ""])
	# a mentor away from the staff: nothing to nudge
	var s2 := _state(false)
	var m := DialogueRun.for_legend(s2, "dora", "briefing")
	_check(m.member.is_empty() and m.tree_id == "lenda_dora" and m.ctx["where"] == "briefing" and m.ctx["legend"] == "dora",
		"a mentor talks from a briefing with her own tree and nothing to nudge")


# ------------------------------------------------------------ rivalry
func _race_line(s: TycoonState, id: String) -> Dictionary:
	var r := DialogueRun.for_legend(s, id, "race")
	r.start(_rng(3))
	for c in r.choices():
		var key := String((r._choice_list()[int(c["index"])] as Dictionary).get("goto", ""))
		if key == "race":
			r.choose(int(c["index"]))
			return {"vs": String(r.ctx.get("rival_vs", "")), "key": String(r.line.get("text_key", "")), "text": r.text()}
	return {"vs": String(r.ctx.get("rival_vs", "")), "key": "", "text": ""}


func _rivalry() -> void:
	print("rivalry")
	var s := _state(false)
	var even := _race_line(s, "gagarinho")
	_check(even["vs"] == "even" and String(even["key"]).ends_with("_EVEN"), "level race: %s" % even["key"])
	s.race.claim("suborbital", "aurora")
	s.race.claim("first_satellite", "aurora")
	var ahead := _race_line(s, "gagarinho")
	_check(ahead["vs"] == "ahead" and String(ahead["key"]).ends_with("_AHEAD") and String(ahead["text"]).contains("2"),
		"Aurora in front: Gagarinho teases (%s)" % String(ahead["text"]).left(70))
	var s2 := _state(false)
	for m: String in ["suborbital", "first_satellite", "long_signal"]:
		s2.race.claim(m, RaceDirector.PLAYER)
	for rid in ["gagarinho", "cifrinha", "herschelinha"]:
		var behind := _race_line(s2, rid)
		_check(behind["vs"] == "behind" and String(behind["key"]).ends_with("_BEHIND"), "player in front: %s concedes (%s)" % [rid, behind["key"]])


# ------------------------------------------------------------ campus exchanges
func _pairs() -> void:
	print("Lenda exchanges")
	var hires: Array = []
	for l in TycoonLegends.of_kind("hire"):
		hires.append(String(l["id"]))
	var n := 0
	var bad: Array[String] = []
	for p: Dictionary in ChatterBook.chatter().get("pairs", []):
		var a := String((p.get("if", {}) as Dictionary).get("legend", ""))
		var b := String((p.get("b_if", {}) as Dictionary).get("legend", ""))
		if a == "" and b == "":
			continue
		n += 1
		if not a in hires or not b in hires:
			bad.append("%s/%s" % [a, b])
	_check(n >= 6 and bad.is_empty(), "%d Lenda-to-Lenda exchanges between hires %s" % [n, str(bad) if not bad.is_empty() else ""])


# ------------------------------------------------------------ places
func _places() -> void:
	print("places")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(4)
	main.race_flow.autosave = false
	main.clock.set_speed(1)
	var s := main.state
	var talk := main.talk
	var hud := main.hud
	# a hired Lenda on the campus
	s.cash = 1.0e8
	var cand := TycoonLegends.dev_spawn(s, "katia")
	var err := TycoonCrew.hire(s, String(cand.get("id", "")))
	_check(err == "", "Kátia is hired (%s)" % err)
	await _frames(10)
	var walker: Node3D = null
	for w in main.campus.cometlings():
		if String(main.campus.cometling_member(w).get("legend", "")) == "katia":
			walker = w
	_check(walker != null, "she walks the campus")
	if walker:
		main.camera.follow(walker)
		await _frames(2)
		_check(talk.can_talk(walker) and talk.open(walker), "\"Conversar\" opens with her")
		_check(talk.run != null and talk.run.tree_id == "lenda_katia" and talk.run.ctx["where"] == "campus",
			"...in her own tree (%s)" % (talk.run.tree_id if talk.run else ""))
		talk.close()
		main.camera.release()
	# a mentor from her bubble on a briefing (a briefing a mentor comments on, put on the board)
	TycoonLegends.dev_mentors = true
	var bid := ""
	for b: Dictionary in BriefingDesk.briefings():
		if not TycoonLegends.mentor_hints(s, b, Discovery.briefing_hints(s, b).is_empty()).is_empty():
			bid = String(b["id"])
			break
	if bid != "" and BriefingDesk.offer(s, bid).is_empty():
		BriefingDesk.spawn(s, bid)
	hud.open_screen("briefings", {"briefing_id": bid})
	await _frames(3)
	var scr: Node = hud.get_node("%Screens").get_child(0) if hud.get_node("%Screens").get_child_count() > 0 else null
	var pressed := ""
	if scr:
		for row in scr.get_node("%Hints").get_children():
			if row.has_meta("from_template") and row.has_meta("legend") and (row as Control).visible:
				var link := row.get_node_or_null("Row/VBox/Head/Talk") as LinkButton
				if link and link.visible:
					pressed = String(row.get_meta("legend"))
					link.pressed.emit()
					break
	await _frames(2)
	_check(pressed != "" and talk.is_open() and talk.legend_id() == pressed and talk.run.tree_id == "lenda_" + pressed
		and talk.run.ctx["where"] == "briefing", "a mentor's bubble on a briefing has \"Conversar\" (%s)" % pressed)
	_check(talk.box.visible and talk.is_visible_in_tree(), "the box shows over the mission board")
	await _press(KEY_ESCAPE)
	_check(not talk.is_open() and hud.current_screen() == "briefings", "Esc closes the talk first, the board stays")
	# every mentor can be asked from a screen
	var ok := 0
	for l in TycoonLegends.of_kind("mentor"):
		hud.talk_to_legend(String(l["id"]), "briefing")
		await _frames(1)
		if talk.is_open() and talk.run.tree_id == DialogueRun.tree_for(TycoonLegends.look(String(l["id"]))):
			ok += 1
		talk.close()
	_check(ok == TycoonLegends.of_kind("mentor").size(), "every mentor talks from the board (%d)" % ok)
	hud.close_screen()
	await _frames(2)
	TycoonLegends.dev_mentors = false
	# a rival leader from the race board
	hud.open_screen("race")
	await _frames(3)
	var race := hud.get_node("%Screens").get_child(0) if hud.get_node("%Screens").get_child_count() > 0 else null
	if race:
		race.call("open_agency", "quietude")
		await _frames(2)
		(race.get_node("%LeaderTalk") as LinkButton).pressed.emit()
		await _frames(2)
	_check(talk.is_open() and talk.legend_id() == "herschelinha" and talk.run.ctx["where"] == "race"
		and talk.run.ctx.has("rival_vs"), "the race board's agency page has \"Conversar\" with its leader")
	hud.close_screen()
	await _frames(3)
	_check(not talk.is_open(), "closing the screen closes the talk")
	main.queue_free()
	await _frames(3)


func _press(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	root.push_input(e)
	await _frames(2)
	var u := InputEventKey.new()
	u.keycode = key
	u.pressed = false
	root.push_input(u)
	await _frames(2)


func _frames(k: int) -> void:
	for i in k:
		await process_frame
