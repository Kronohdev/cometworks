extends SceneTree
## The Cometlings talk: speech bubbles on the campus and "Conversar".
##   - data: every bubble line, exchange and dialogue line is translated in pt and en, bubbles
##     are short, every tree's nodes and gotos exist, every pose / face / emote is known
##   - conditions (ChatterBook.matches): equal, lists, _min / _max, not_, events; the speaker
##     context (mood, money, tiredness) and specific lines winning over generic ones
##   - bubbles (CampusChatter): they start by themselves, never more than the rate's max at once,
##     a speaker rests after talking, lines fit the speaker (a napping Cometling only snores,
##     a launch failure colours the lines), a two-Cometling exchange gets its answer, a screen
##     or the setting turned off hides them; the setting is kept in user://settings.cfg
##   - dialogue trees (DialogueRun): the right tree per speaker (default, leader, Lenda, Vovô),
##     choices with conditions and "once", the weekly morale nudge (capped, back the next
##     week), the mission tip written into the Journal, flags remembered and saved
##   - the box (CometlingDialogue): opens on a Cometling (it stops, the clock holds), number
##     keys pick choices, Esc closes it first and only it (the next Esc lets go of the
##     Cometling), the clock gets its speed back
##   - no randomness leaks into the campaign: bubbles and talks leave the campaign RNG and state
##     as they were, and a campaign with bubbles running equals one without
## The player's bubble settings are put back as they were at the end.
## Run: godot --headless --path . --script res://tests/test_dialogue.gd

const MAX_BUBBLE := 64
const MAX_DIALOGUE := 190

var _failures := 0
var _on := true
var _rate := "normal"


func _initialize() -> void:
	_on = ChatterBook.enabled()
	_rate = ChatterBook.rate()
	_data()
	_conditions()
	_trees()
	await _campus()
	await _isolation()
	ChatterBook.set_enabled(_on)
	ChatterBook.set_rate(_rate)
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


# ------------------------------------------------------------ data
func _data() -> void:
	print("data")
	_check(ChatterBook.new() is RefCounted and DialogueRun.has_tree("cometling"), "the talk scripts load (ChatterBook, DialogueRun)")
	var ch := ChatterBook.chatter()
	var lines: Array = ch.get("lines", [])
	var pairs: Array = ch.get("pairs", [])
	_check(lines.size() >= 120 and pairs.size() >= 12, "%d bubble lines and %d exchanges in %s" % [lines.size(), pairs.size(), ChatterBook.CHATTER_PATH])
	var bubble_keys: Array[String] = []
	for l: Dictionary in lines:
		bubble_keys.append(String(l.get("text_key", "")))
	for p: Dictionary in pairs:
		bubble_keys.append(String(p.get("a_key", "")))
		bubble_keys.append(String(p.get("b_key", "")))
	var bad := 0
	var long := 0
	for loc in ["pt_BR", "en"]:
		TranslationServer.set_locale(loc)
		for k in bubble_keys:
			var t := tr(k)
			if k == "" or t == k:
				bad += 1
				print("    untranslated (%s): %s" % [loc, k])
			elif t.length() > MAX_BUBBLE:
				long += 1
				print("    too long for a bubble (%s): %s" % [loc, k])
	_check(bad == 0, "every bubble line is translated in pt and en (%d missing)" % bad)
	_check(long == 0, "every bubble line is short (%d longer than %d)" % [long, MAX_BUBBLE])
	for e: Dictionary in ch.get("emotes", []):
		_check(String(e.get("emote", "")) in Cometling.EMOTES, "emote '%s' is a Cometling emote" % e.get("emote"))
	for ev: String in ch.get("reactions", {}):
		var r: Dictionary = ch["reactions"][ev]
		_check(Cometling.ONESHOTS.has(String(r.get("pose", ""))), "reaction pose '%s' is a one-shot" % r.get("pose"))
		for em in r.get("emotes", []):
			_check(String(em) in Cometling.EMOTES, "reaction emote '%s' exists" % em)
	for r in ChatterBook.RATES:
		var c := ChatterBook.rate_cfg(r)
		_check(int(c.get("max", 0)) >= 1 and (c.get("gap", []) as Array).size() == 2, "rate '%s' has a max and a gap" % r)
	_check(int(ChatterBook.rate_cfg("few")["max"]) < int(ChatterBook.rate_cfg("many")["max"]), "Poucos shows fewer bubbles than Muitos")
	# the trees
	var d := ChatterBook.dialogues()
	var trees: Dictionary = d.get("trees", {})
	for id in ["cometling", "leader", "legend", "halleyzinho"]:
		_check(trees.has(id), "dialogue tree '%s' exists" % id)
	var dbad := 0
	var dlong := 0
	var broken := 0
	for tid: String in trees:
		var t: Dictionary = trees[tid]
		var nodes: Dictionary = t.get("nodes", {})
		if not nodes.has(String(t.get("start", ""))):
			broken += 1
			print("    %s: no start node" % tid)
		for nid: String in nodes:
			var n: Dictionary = nodes[nid]
			for l: Dictionary in n.get("lines", []):
				for loc in ["pt_BR", "en"]:
					TranslationServer.set_locale(loc)
					var k := String(l.get("text_key", ""))
					if tr(k) == k:
						dbad += 1
						print("    untranslated (%s): %s" % [loc, k])
					elif tr(k).length() > MAX_DIALOGUE:
						dlong += 1
						print("    too long (%s): %s" % [loc, k])
				var pose := String(l.get("pose", ""))
				if pose != "" and not (Cometling.ONESHOTS.has(pose) or pose in Cometling.LOOP_ACTIONS or pose in Halleyzinho.HABITS):
					broken += 1
					print("    %s/%s: unknown pose %s" % [tid, nid, pose])
				var face := String(l.get("face", ""))
				if face != "" and not face in Cometling.EXPRESSIONS:
					broken += 1
					print("    %s/%s: unknown face %s" % [tid, nid, face])
			var ch_list: Variant = n.get("choices", [])
			if ch_list is String:
				ch_list = (t.get("menus", {}) as Dictionary).get(ch_list, null)
				if ch_list == null:
					broken += 1
					print("    %s/%s: unknown menu" % [tid, nid])
					continue
			for c: Dictionary in ch_list:
				var g := String(c.get("goto", ""))
				if g != "" and not nodes.has(g):
					broken += 1
					print("    %s/%s: goto %s does not exist" % [tid, nid, g])
				if g == "" and not bool(c.get("end", false)):
					broken += 1
					print("    %s/%s: a choice that neither goes on nor ends" % [tid, nid])
				for loc in ["pt_BR", "en"]:
					TranslationServer.set_locale(loc)
					if tr(String(c.get("text_key", ""))) == String(c.get("text_key", "")):
						dbad += 1
	TranslationServer.set_locale("pt_BR")
	_check(dbad == 0, "every dialogue line and choice is translated (%d missing)" % dbad)
	_check(dlong == 0, "every dialogue line fits the box (%d too long)" % dlong)
	_check(broken == 0, "every tree is whole: start nodes, gotos, menus, poses and faces (%d problems)" % broken)
	for k in ["TY_DLG_TALK", "TY_DLG_TALK_TIP", "TY_CHAT_SET_BUBBLES", "TY_CHAT_SET_RATE", "TY_CHAT_RATE_FEW",
			"TY_CHAT_RATE_MANY", "TY_DLG_NOTE_MORALE", "TY_DLG_NOTE_HINT", "TY_DLG_LEFT_MANY"]:
		_check(tr(k) != k, "UI key %s is translated" % k)


# ------------------------------------------------------------ conditions
func _conditions() -> void:
	print("conditions")
	var ctx := {"profession": "pilot", "morale": 35.0, "mood": "low", "era": 2, "events": ["launch_failure"],
		"tired": true, "place": "lab", "doing": "working", "flags": []}
	_check(ChatterBook.matches({"profession": "pilot"}, ctx), "equal")
	_check(not ChatterBook.matches({"profession": "scientist"}, ctx), "not equal")
	_check(ChatterBook.matches({"profession": ["scientist", "pilot"]}, ctx), "any of a list")
	_check(ChatterBook.matches({"era_min": 2, "era_max": 3}, ctx) and not ChatterBook.matches({"era_min": 3}, ctx), "_min / _max")
	_check(ChatterBook.matches({"not_doing": "napping"}, ctx) and not ChatterBook.matches({"not_place": "lab"}, ctx), "not_")
	_check(ChatterBook.matches({"events": "launch_failure"}, ctx) and not ChatterBook.matches({"events": "milestone"}, ctx), "a list in the context contains")
	_check(ChatterBook.matches({"tired": true, "mood": "low"}, ctx) and not ChatterBook.matches({"tired": false}, ctx), "booleans and several keys")
	_check(ChatterBook.matches({"flags": false}, ctx) and not ChatterBook.matches({"flags": "x"}, ctx), "an empty list")
	_check(ChatterBook.matches({}, ctx), "no condition always holds")
	var s := TycoonState.new_campaign(7, TycoonMain._roster_staff())
	var m: Dictionary = s.staff[0]
	m["morale"] = 85.0
	_check(ChatterBook.context(s, m)["mood"] == "happy", "morale 85 is happy")
	m["morale"] = 20.0
	m["busy_weeks"] = 0
	var c := ChatterBook.context(s, m)
	_check(c["mood"] == "low" and c["tired"] == true, "morale 20 is low and tired")
	m["morale"] = 60.0
	m["busy_weeks"] = 9
	_check(ChatterBook.context(s, m)["tired"] == true and ChatterBook.context(s, m)["mood"] == "ok", "nine weeks on a project is tired")
	s.cash = -10.0
	_check(ChatterBook.context(s, m)["money"] == "broke", "in the red is broke")
	s.cash = 1e9
	_check(ChatterBook.context(s, m)["money"] == "ok", "rich is ok")
	_check(ChatterBook.context(s, m, {"doing": "walking", "place": "pad"})["place"] == "pad", "the walker's activity goes in")
	# specific lines win: a napping Cometling only snores, a failure colours the lines
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lines: Array = ChatterBook.chatter()["lines"].filter(func(l: Dictionary) -> bool: return not (l.get("if", {}) as Dictionary).has("who"))
	var nap := ChatterBook.context(s, m, {"doing": "napping"})
	var snore := true
	for i in 30:
		if not String(ChatterBook.pick(lines, nap, rng)["text_key"]).begins_with("TY_CHAT_NAP"):
			snore = false
	_check(snore, "a napping Cometling only says sleep lines")
	var fail := ChatterBook.context(s, m, {"doing": "idle"}, {"events": ["launch_failure"]})
	var n_fail := 0
	for i in 100:
		if String(ChatterBook.pick(lines, fail, rng)["text_key"]).begins_with("TY_CHAT_LAUNCH_FAIL"):
			n_fail += 1
	_check(n_fail >= 15, "after a launch failure the lines lean to it (%d of 100)" % n_fail)
	var none := 0
	for i in 100:
		if String(ChatterBook.pick(lines, ChatterBook.context(s, m, {"doing": "idle"}), rng)["text_key"]).begins_with("TY_CHAT_LAUNCH_FAIL"):
			none += 1
	_check(none == 0, "without the event nobody talks about a failure")


# ------------------------------------------------------------ trees
func _trees() -> void:
	print("dialogue trees")
	var s := TycoonState.new_campaign(11, TycoonMain._roster_staff())
	TycoonLeader.found(s, TycoonLeader.make_default(_rng(3)))
	var rng := _rng(9)
	var m: Dictionary = s.staff[0]
	for x in s.staff:
		if not TycoonLeader.is_leader(x):
			m = x
			break
	_check(DialogueRun.tree_for(m) == "cometling", "a Cometling talks with the default tree")
	_check(DialogueRun.tree_for(TycoonLeader.member(s)) == "leader", "the leader talks to themselves")
	_check(DialogueRun.tree_for({"legend": "katia"}) == "legend", "a Lenda has the Lendas' tree")
	_check(DialogueRun.tree_for({"legend": "halleyzinho"}) == "halleyzinho", "a Lenda can have her own tree (by_legend)")
	var node := Node3D.new()
	node.set_meta("talk_tree", "halleyzinho")
	_check(DialogueRun.tree_for({}, node) == "halleyzinho", "a node's talk_tree metadata picks the tree")
	node.free()
	# a conversation
	m["morale"] = 60.0
	m["napping"] = false
	var r := DialogueRun.new(s, m)
	_check(r.start(rng) and r.node_id == "hello" and r.text() != "", "the conversation starts with a hello: \"%s\"" % r.text())
	var names := _choice_keys(r)
	_check(names.has("TY_DLG_ASK_FEEL") and names.has("TY_DLG_ASK_WORK") and names.has("TY_DLG_ASK_HINT")
		and names.has("TY_DLG_ASK_COMET") and names.has("TY_DLG_BYE"), "the hello offers feel / work / tip / comet / bye")
	var before := float(m["morale"])
	r.choose(_index_of(r, "TY_DLG_ASK_FEEL"))
	_check(r.node_id == "feel" and is_equal_approx(float(m["morale"]), before + 3.0), "asking how they feel nudges morale +3 (%.0f -> %.0f)" % [before, float(m["morale"])])
	_check(r.note != "" and r.done.any(func(e: Dictionary) -> bool: return e["effect"] == "morale"), "...and the box gets a note: \"%s\"" % r.note)
	_check(not _choice_keys(r).has("TY_DLG_ASK_FEEL"), "a 'once' choice is gone after it was picked")
	var r2 := DialogueRun.new(s, m)
	r2.start(rng)
	r2.choose(_index_of(r2, "TY_DLG_ASK_FEEL"))
	_check(is_equal_approx(float(m["morale"]), before + 3.0) and r2.done.any(func(e: Dictionary) -> bool: return e["effect"] == "morale_capped"),
		"the same week, asking again does not raise morale (weekly cap)")
	s.weeks += 1
	var r3 := DialogueRun.new(s, m)
	r3.start(rng)
	r3.choose(_index_of(r3, "TY_DLG_ASK_FEEL"))
	_check(is_equal_approx(float(m["morale"]), before + 6.0), "the next week it works again (%.0f)" % float(m["morale"]))
	# conditions in a tree: the line fits the speaker
	m["napping"] = true
	var nap := DialogueRun.new(s, m)
	nap.start(rng)
	_check(String(nap.line["text_key"]) == "TY_DLG_HI_NAP", "a napping Cometling greets half asleep")
	m["napping"] = false
	m["morale"] = 20.0
	var low := DialogueRun.new(s, m)
	low.start(rng)
	low.choose(_index_of(low, "TY_DLG_ASK_FEEL"))
	_check(String(low.line["text_key"]).begins_with("TY_DLG_FEEL_LOW") or String(low.line["text_key"]) == "TY_DLG_FEEL_TIRED",
		"a low-morale Cometling says so (%s)" % low.line["text_key"])
	m["morale"] = 70.0
	m["assigned"] = ""
	var work := DialogueRun.new(s, m)
	work.start(rng)
	work.choose(_index_of(work, "TY_DLG_ASK_WORK"))
	_check(work.node_id == "work" and work.text() != "" and not "{" in work.text(), "what are you working on: \"%s\"" % work.text())
	# the mission tip goes into the Journal (a veteran's bet on the board's first briefing)
	BriefingDesk.ensure(s)
	m["level"] = 4
	var tip := DialogueRun.new(s, m)
	_check(tip.ctx["has_hint"] == true, "a veteran has a tip about the mission board (%s)" % tip.vars.get("hint", ""))
	tip.start(rng)
	var notes := (Discovery.d(s)["notes"] as Array).size()
	tip.choose(_index_of(tip, "TY_DLG_ASK_HINT"))
	_check(tip.node_id == "hint" and tip.text().contains(String(tip.vars["hint"])), "the tip is said in their voice: \"%s\"" % tip.text())
	_check((Discovery.d(s)["notes"] as Array).size() == notes + 1, "...and written into the Journal")
	var tip2 := DialogueRun.new(s, m)
	tip2.start(rng)
	tip2.choose(_index_of(tip2, "TY_DLG_ASK_HINT"))
	_check((Discovery.d(s)["notes"] as Array).size() == notes + 1, "the same tip is not written twice in a week")
	m["level"] = 1
	m["curiosity"] = 0.0
	m["profession"] = "pilot"
	var rookie := DialogueRun.new(s, m)
	rookie.start(rng)
	rookie.choose(_index_of(rookie, "TY_DLG_ASK_HINT"))
	_check(rookie.ctx["has_hint"] == false and String(rookie.line["text_key"]) == "TY_DLG_HINT_NONE", "a rookie without a tip says so")
	# the comet: "Conta mais!" brings another fact
	var c := DialogueRun.new(s, m)
	c.start(rng)
	c.choose(_index_of(c, "TY_DLG_ASK_COMET"))
	var first := String(c.line["text_key"])
	c.choose(_index_of(c, "TY_DLG_ASK_MORE"))
	_check(c.node_id == "comet" and String(c.line["text_key"]) != first, "'Conta mais!' tells another comet fact")
	_check(not c.choose(_index_of(c, "TY_DLG_BYE")) and c.is_over() and c.after.any(func(a: Dictionary) -> bool: return a.has("say")),
		"Tchau ends the talk and leaves a farewell bubble for the box")
	# a Lenda and Vovô
	var lg := {"id": "x_katia", "name": "Kátia", "legend": "katia", "profession": "flight_controller", "morale": 80.0}
	var lr := DialogueRun.new(s, lg)
	lr.start(rng)
	lr.choose(_index_of(lr, "TY_DLG_ASK_WHO"))
	_check(lr.text().contains(tr("TY_LEG_KATIA_REAL")), "a Lenda tells who inspired her: \"%s\"" % lr.text().left(60))
	_check("told_who" in lr.ctx["flags"], "...and remembers she told it (flag)")
	var h := DialogueRun.new(s, {}, "halleyzinho", "halleyzinho")
	h.start(rng)
	_check(h.node_id == "hello" and _choice_keys(h).has("TY_DLG_H_ASK_LESSON"), "Vovô has his own tree")
	h.choose(_index_of(h, "TY_DLG_H_ASK_LESSON"))
	h.choose(0)
	_check(h.after.any(func(a: Dictionary) -> bool: return String(a.get("lesson", "")) == "campus"), "asking Vovô to explain replays his campus lesson")
	# memory is saved with the campaign
	var back := TycoonState.from_dict(JSON.parse_string(JSON.stringify(TycoonSave.encode(s.to_dict()))) as Dictionary)
	var memo: Dictionary = back.story.get("talk", {})
	_check(memo.has("week") and memo["flags"].has("x_katia"), "the conversations' memory is saved with the campaign")


func _choice_keys(r: DialogueRun) -> Array[String]:
	var out: Array[String] = []
	var list := r._choice_list()
	for c in r.choices():
		out.append(String(list[int(c["index"])].get("text_key", "")))
	return out


func _index_of(r: DialogueRun, key: String) -> int:
	var list := r._choice_list()
	for c in r.choices():
		if String(list[int(c["index"])].get("text_key", "")) == key:
			return int(c["index"])
	return -1


# ------------------------------------------------------------ the campus
func _campus() -> void:
	print("campus: bubbles and the box")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(4)
	main.race_flow.autosave = false
	main.clock.set_speed(2)
	var chatter := main.chatter
	var talk := main.talk
	_check(chatter is CampusChatter and talk is CometlingDialogue, "the main screen has the bubbles and the box (CampusChatter, CometlingDialogue)")
	if chatter == null or talk == null:
		main.queue_free()
		return
	chatter.set_process(false)   # the test steps the bubbles itself
	chatter.rng.seed = 42
	chatter.force_enabled = 1
	chatter.force_rate = "many"
	chatter.max_distance = 600.0
	chatter.fade_start = 500.0
	var who: Array[Node3D] = main.campus.cometlings()
	_check(who.size() >= 4, "%d Cometlings walk the campus" % who.size())
	main.camera.follow(who[0])
	await _wait(2.0)
	# bubbles start by themselves and stay under the limit
	var mx := int(ChatterBook.rate_cfg("many")["max"])
	var most := 0
	var last_said := {}
	var too_soon := 0
	for i in 400:
		chatter.tick(0.1)
		most = maxi(most, chatter.active_count())
		for b in chatter._bubbles:
			if float(b["age"]) <= 0.0:
				var id: int = (b["who"] as Node).get_instance_id()
				if last_said.has(id) and i - int(last_said[id]) < 20 and String(b["key"]) != "":
					too_soon += 1
				last_said[id] = i
		await process_frame
	_check(chatter.said.size() >= 4, "the Cometlings talk by themselves (%d lines in 40 s)" % chatter.said.size())
	_check(most >= 1 and most <= mx, "never more than %d bubbles at once (most %d)" % [mx, most])
	_check(too_soon == 0, "a Cometling rests after talking (%d spoke again within 2 s)" % too_soon)
	var shown := 0
	for b in chatter._bubbles:
		var lbl := (b["node"] as Control).get_node("Panel/Text") as Label
		if lbl.text != "" and not "{" in lbl.text and not lbl.text.begins_with("TY_"):
			shown += 1
	_check(shown == chatter.active_count() or chatter.active_count() == 0, "bubbles show translated lines")
	# a two-Cometling exchange gets its answer
	chatter.clear()
	chatter._cool.clear()
	var a: Node3D = who[1]
	var b2: Node3D = who[2]
	var k := chatter.say_pair(a, b2)
	_check(k != "" and chatter.speaking().has(a), "an exchange starts (%s)" % k)
	for i in 25:
		chatter.tick(0.1)
	_check(chatter.speaking().has(b2), "...and the other Cometling answers")
	# a napping Cometling snores in its bubble
	chatter.clear()
	chatter._cool.clear()
	var napper: Node3D = who[3]
	napper.call("set_napping", true)
	var nk := chatter.say_line(napper)
	_check(nk.begins_with("TY_CHAT_NAP"), "a napping Cometling talks in its sleep (%s)" % nk)
	napper.call("set_napping", false)
	# an event makes a few react and colours the lines
	chatter.event("launch_success")
	_check("launch_success" in chatter.events(), "a launch is remembered for a while")
	for i in 30:
		chatter.tick(0.1)
	# a screen hides the bubbles, the setting too
	chatter.clear()
	chatter.say(who[0], "Oi!")
	main.hud.open_screen("crew")
	await _frames(2)
	for i in 5:
		chatter.tick(0.1)
	_check(chatter.active_count() == 0, "a screen hides the bubbles")
	for i in 60:
		chatter.tick(0.1)
	_check(chatter.active_count() == 0, "...and no new ones come while it is open")
	main.hud.close_screen()
	await _frames(2)
	chatter.force_enabled = -1
	ChatterBook.set_enabled(false)
	var cfg := ConfigFile.new()
	cfg.load(ChatterBook.SETTINGS_PATH)
	_check(cfg.get_value(ChatterBook.SETTINGS_SECTION, ChatterBook.KEY_ON, true) == false, "the setting is saved in user://settings.cfg")
	chatter.say(who[0], "Oi!")
	for i in 80:
		chatter.tick(0.1)
	_check(chatter.active_count() == 0, "with speech bubbles off, nobody talks")
	ChatterBook.set_enabled(true)
	ChatterBook.set_rate("few")
	chatter.force_rate = ""
	_check(ChatterBook.rate() == "few" and int(chatter.rate_cfg()["max"]) == 1, "the rate setting changes how many bubbles show")
	chatter.force_rate = "few"
	chatter.force_enabled = 1
	# the settings screen has the two rows
	main.hud.open_screen("settings")
	await _frames(3)
	var scr := main.hud.get_node("%Screens").get_child(0)
	(scr.find_child("ImageTab", true, false) as Button).pressed.emit()
	await _frames(3)
	var img := scr.find_child("OptionsImage", true, false)
	var on_btn := img.find_child("BubblesOn", true, false) as Button
	var few_btn := img.find_child("RateFew", true, false) as Button
	_check(on_btn != null and on_btn.is_visible_in_tree() and few_btn != null and few_btn.is_visible_in_tree(),
		"the settings' Image tab shows Balões de fala and the frequency")
	if on_btn and few_btn:
		_check(on_btn.button_pressed and few_btn.button_pressed, "...in the state of the settings")
		var off_btn := img.find_child("BubblesOff", true, false) as Button
		off_btn.pressed.emit()
		_check(not ChatterBook.enabled() and few_btn.disabled, "turning them off there works (and greys the frequency)")
		on_btn.pressed.emit()
		(img.find_child("RateMany", true, false) as Button).pressed.emit()
		_check(ChatterBook.enabled() and ChatterBook.rate() == "many", "...and back on, Muitos")
	main.hud.close_screen()
	await _frames(3)
	main.clock.set_speed(2)

	# the box
	var cl: Node3D = who[0]
	main.camera.follow(cl)
	await _frames(3)
	var tag_talk := main.hud.get_node("%TagTalk") as Button
	_check(tag_talk.visible, "the follow tag offers Conversar")
	tag_talk.pressed.emit()
	await _frames(2)
	_check(talk.is_open() and talk.speaker == cl, "Conversar opens the box on the followed Cometling")
	_check(bool(cl.call("is_held")), "the Cometling stops to talk")
	_check(main.clock.speed == 0, "the clock holds while they talk")
	_check(talk.box.visible and (talk.get_node("%Name") as Label).text == String(main.campus.cometling_member(cl).get("name", "")),
		"the box shows their name")
	var n_choices := 0
	for c in talk.get_node("%Choices").get_children():
		if c.visible and c != talk.get_node("%ChoiceTemplate") and not c.is_queued_for_deletion():
			n_choices += 1
	_check(n_choices == talk.shown_choices.size() and n_choices >= 4, "%d reply buttons" % n_choices)
	var start_node := talk.run.node_id
	_press(KEY_2)
	await _frames(2)
	_check(talk.run != null and talk.run.node_id != start_node, "a number key picks a choice (now '%s')" % (talk.run.node_id if talk.run else ""))
	chatter.clear()
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(not talk.is_open(), "Esc closes the box first")
	_check(main.camera.mode == CampusCamera.Mode.FOLLOW and main.hud.current_screen() == "", "...and only it (the camera still follows, no pause menu)")
	_check(not bool(cl.call("is_held")) and main.clock.speed == 2, "the Cometling walks on and the clock gets its speed back")
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(main.camera.mode != CampusCamera.Mode.FOLLOW, "the next Esc lets go of the Cometling")
	# farewell bubble after Tchau, a lesson closes the box
	_check(talk.open(cl), "the box opens with a call too")
	var bye := -1
	for i in talk.shown_choices.size():
		if bool(talk.shown_choices[i].get("end", false)):
			bye = i
	talk.choose(bye)
	await _frames(1)
	_check(not talk.is_open() and chatter.speaking().has(cl), "Tchau closes the box and the Cometling waves with a bubble")
	talk.open(cl)
	main.tutorial.start("lot", true)
	await _frames(2)
	_check(not talk.is_open(), "a lesson starting closes the box")
	main.tutorial.skip()
	await _frames(2)
	_check(main.clock.speed == 2, "...and the clock still gets its speed back (got %d)" % main.clock.speed)
	# Vovô on his bench
	var halley := main.get_node("Halley") as Node3D
	if halley.visible:
		_check(talk.open(halley) and talk.run.tree_id == "halleyzinho" and talk.halley_portrait.visible,
			"Vovô on his bench talks with his own tree and portrait")
		talk.close()
	main.queue_free()
	await _frames(3)


# ------------------------------------------------------------ the campaign stays the same
func _isolation() -> void:
	print("no randomness leaks into the campaign")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	main.campaign_seed = 4242
	get_root().add_child(main)
	await _frames(4)
	main.race_flow.autosave = false
	main.clock.set_speed(0)
	var s := main.state
	var rng_before := s.rng.state
	var dict_before := _canon(s.to_dict())
	var chatter := main.chatter
	chatter.force_enabled = 1
	chatter.force_rate = "many"
	chatter.max_distance = 600.0
	var who := main.campus.cometlings()
	main.camera.follow(who[0])
	for i in 300:
		chatter.tick(0.1)
		await process_frame
	chatter.event("launch_failure")
	for i in 50:
		chatter.tick(0.1)
	# a talk without effects (the comet and goodbye)
	main.talk.open(who[1])
	var r := main.talk.run
	r.choose(_index_of(r, "TY_DLG_ASK_COMET"))
	main.talk.close()
	_check(chatter.said.size() > 0, "the bubbles ran (%d lines)" % chatter.said.size())
	_check(s.rng.state == rng_before, "the campaign RNG did not move")
	var dict_after := _canon(s.to_dict())
	_check(dict_after == dict_before, "the campaign state is the same as before the bubbles and the talk")
	if dict_after != dict_before:
		var x := JSON.parse_string(dict_before) as Dictionary
		var y := JSON.parse_string(dict_after) as Dictionary
		for key in y:
			if JSON.stringify(x.get(key)) != JSON.stringify(y.get(key)):
				print("    differs: %s" % key)
	# a twin campaign without bubbles: the same weeks give the same campaign
	main.chatter.force_enabled = 1
	for i in 6:
		s.advance_week()
		for j in 20:
			chatter.tick(0.1)
	var twin := TycoonState.new_campaign(4242, TycoonMain._roster_staff(), "normal")
	for i in 6:
		twin.advance_week()
	var a := s.to_dict()
	var b := twin.to_dict()
	a.erase("story")
	b.erase("story")
	_check(_canon(a) == _canon(b), "six weeks with bubbles running equal six weeks of a campaign without them")
	main.queue_free()
	await _frames(3)


static func _canon(d: Dictionary) -> String:
	var j: Variant = JSON.parse_string(JSON.stringify(TycoonSave.encode(d), "", true, true))
	return JSON.stringify(j, "", true, true)


# ------------------------------------------------------------ helpers
func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
