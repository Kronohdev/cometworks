extends SceneTree
## The Conferência dos Cometinhos (src/tycoon/conference/, data/tycoon/conference.json):
##   - calendar: conference years every 3 years from year 3, the invitation due at its week,
##     answered once (go: reward and ticker line; no: nothing more this year)
##   - who comes: the host, the three rival leaders, the guests whose era has come; the Lenda
##     exchanges among them
##   - rival news: live race state (milestones, firsts, next goal, recent claims, failures,
##     cooldown, the Mother-Ice) in pt and en with no {placeholder} left, early and late
##   - the fair's trees: every Lenda's tree plus its fair choices; every goto exists and every line
##     and choice of every node fills in both languages
##   - save / load keeps TycoonState.conference
##   - in the tycoon scene: the invitation opens at the right week and holds the clock; going opens
##     the fair (campus asleep, HUD hidden, fair camera current, the Lendas there), talking to a
##     rival leader through the campus dialogue box gives its report and counts as heard, the
##     exchanges play as bubbles, leaving brings the campus back and the clock its speed
##   - the triennium (ConferenceTriennium): the rival leaders' and the mentor Lendas' reactions to
##     the player's own firsts, failures and reputation (pt and en, in their voices); Keplerino's
##     tip (a race briefing on the board, reachable only, one per conference, expiring); the
##     "Agência do triênio" winner (milestones, firsts, reputation), its reward and trophy once;
##     in the scene, the stage ceremony (host and winner on the stage, confetti)
## Run: godot --headless --path . --script res://tests/test_conference.gd

var _failures := 0


func _initialize() -> void:
	await process_frame
	_calendar()
	_attendees()
	_news()
	_trees()
	_save()
	_reactions()
	_tip()
	_award()
	await _scene()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)


func _campaign() -> TycoonState:
	return TycoonState.new_campaign(2026, TycoonMain._roster_staff(), "normal")


func _at(s: TycoonState, year: int, week: int) -> void:
	s.weeks = (year - 1) * s.weeks_per_year() + week - 1


func _filled(t: String) -> bool:
	return t != "" and not ("{" in t or "}" in t) and not t.begins_with("TY_")


func _calendar() -> void:
	print("calendar")
	var years: Array[int] = []
	for y in range(1, 26):
		if ConferenceBook.is_conference_year(y):
			years.append(y)
	_check(years == [3, 6, 9, 12, 15, 18, 21, 24], "conferences in years %s" % [years])
	var s := _campaign()
	_at(s, 3, 1)
	_check(not ConferenceBook.due(s), "not due before its week")
	_at(s, 3, int(ConferenceBook.cfg("week", 22)))
	_check(ConferenceBook.due(s), "due at its week of year 3")
	var rep := s.reputation
	ConferenceBook.answer(s, true)
	_check(not ConferenceBook.due(s), "answered: not due again this year")
	_check(s.reputation > rep and ConferenceBook.attended(s, 3), "going: reputation and attended")
	_check(String(s.news[0]["key"]) == "TY_CONF_NEWS_WENT", "going: a ticker line")
	_at(s, 4, 30)
	_check(not ConferenceBook.due(s), "not due in year 4")
	_at(s, 6, 40)
	_check(ConferenceBook.due(s), "due in year 6")
	ConferenceBook.answer(s, false)
	_check(not ConferenceBook.due(s) and 6 in (s.conference["skipped"] as Array), "skipped year 6")
	_check(ConferenceBook.next_year(s, 7) == 9 and ConferenceBook.next_year(s, 25) == 0, "next conference year")


func _attendees() -> void:
	print("attendees")
	var s := _campaign()
	_at(s, 3, 22)
	var a := ConferenceBook.attendees(s)
	var roles := {}
	for p in a:
		roles[String(p["role"])] = int(roles.get(String(p["role"]), 0)) + 1
	_check(String(a[0]["id"]) == "keplerino" and String(a[0]["role"]) == ConferenceBook.ROLE_HOST, "the host first")
	_check(int(roles.get(ConferenceBook.ROLE_RIVAL, 0)) == s.rivals.size(), "one leader per rival")
	var early := a.size()
	_at(s, 24, 22)
	var late := ConferenceBook.attendees(s)
	_check(late.size() > early, "more Lendas late in the campaign (%d > %d)" % [late.size(), early])
	var ids: Array = []
	for p in late:
		if String(p["role"]) == ConferenceBook.ROLE_GUEST:
			ids.append(String(p["id"]))
	var duos := ConferenceBook.duos(ids)
	_check(duos.size() >= 3, "Lenda exchanges at a late fair: %d" % duos.size())
	var seen := {}
	var once := true
	for d in duos:
		once = once and not seen.has(d["a"]) and not seen.has(d["b"])
		seen[d["a"]] = true
		seen[d["b"]] = true
	_check(once, "each Lenda in one exchange at most")


func _news() -> void:
	print("rival news")
	for lang in ["pt_BR", "en"]:
		TranslationServer.set_locale(lang)
		var s := _campaign()
		_at(s, 3, 22)
		var all_ok := true
		for r in s.rivals:
			var rp := ConferenceBook.report(s, String(r["id"]), "l")
			var gp := ConferenceBook.report(s, String(r["id"]), "g")
			for t in [rp["status"], rp["recent"], rp["comet"], gp["status"], gp["recent"], gp["comet"],
					ConferenceBook.board_text(s, String(r["id"]))]:
				all_ok = all_ok and _filled(String(t))
		_check(all_ok, "%s: early news filled" % lang)
		# a rival with history: milestones, a failure, a cooldown
		var rid := String(s.rivals[0]["id"])
		_at(s, 9, 10)
		s.race.claim("suborbital", rid)
		s.race.claim("first_satellite", rid)
		s.race.ai[rid]["next"] = 2
		_at(s, 9, 30)
		SpaceTracking.add_rival(s, rid, "long_signal", s.weeks - 8, true)
		s.race.ai[rid]["cooldown"] = 3
		_at(s, 10, 30)
		var f := ConferenceBook.rival_facts(s, rid)
		_check(int(f["count"]) == 2 and int(f["recent"]) == 2 and int(f["fails"]) == 1 and int(f["cooldown"]) == 3,
			"%s: facts follow the race (%s)" % [lang, f])
		var rp := ConferenceBook.report(s, rid, "l")
		print("    ", rp["status"], " | ", rp["recent"], " | ", rp["comet"])
		_check(_filled(rp["status"]) and _filled(rp["recent"]) and _filled(rp["comet"]), "%s: report filled" % lang)
		_check(String(f["fail_name"]) != "" and String(rp["recent"]).contains(String(f["fail_name"])), "%s: names the failed goal" % lang)
	TranslationServer.set_locale("pt_BR")


func _trees() -> void:
	print("trees")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for lang in ["pt_BR", "en"]:
		TranslationServer.set_locale(lang)
		var s := _campaign()
		_at(s, 24, 22)
		var bad: Array[String] = []
		for p in ConferenceBook.attendees(s):
			var id := String(p["id"])
			var r := ConferenceBook.make_run(s, id, String(p["role"]), String(p["rival"]))
			r.rng = rng
			var nodes: Dictionary = r.tree.get("nodes", {})
			for nid: String in nodes:
				r.ctx["has_hint"] = true
				if not r.goto(nid):
					bad.append("%s: node %s" % [id, nid])
					continue
				for l: Dictionary in (nodes[nid] as Dictionary).get("lines", []):
					r.line = l
					if not _filled(r.text()):
						bad.append("%s/%s: %s" % [id, nid, r.text()])
				for c: Dictionary in r._choice_list():
					var ct := ChatterBook.text(String(c.get("text_key", "")), r.vars)
					if not _filled(ct):
						bad.append("%s/%s choice: %s" % [id, nid, ct])
					var g := String(c.get("goto", ""))
					if g != "" and not nodes.has(g):
						bad.append("%s/%s: goto %s" % [id, nid, g])
		_check(bad.is_empty(), "%s: every fair line and choice fills %s" % [lang, bad.slice(0, 4)])
	TranslationServer.set_locale("pt_BR")
	var s2 := _campaign()
	var rid := String(s2.rivals[0]["id"])
	var r2 := ConferenceBook.make_run(s2, TycoonLegends.rival_leader_id(rid), ConferenceBook.ROLE_RIVAL, rid)
	r2.start(rng)
	var news := -1
	for c in r2.choices():
		if String(c["text"]) == TranslationServer.translate("TY_CONF_ASK_NEWS"):
			news = int(c["index"])
	_check(news >= 0 and r2.choose(news) and r2.node_id == "conf_news", "a rival leader offers the report")
	var dj := ChatterBook.dialogues()
	_check(not (dj["trees"] as Dictionary).has("conference_keplerino"), "dialogues.json's trees untouched")


func _save() -> void:
	print("save")
	var s := _campaign()
	_at(s, 3, 22)
	ConferenceBook.answer(s, true)
	var back := TycoonSave.state_from(TycoonSave.decode(JSON.parse_string(JSON.stringify(TycoonSave.encode(s.to_dict())))))
	_check(ConferenceBook.last_year(back) == 3 and ConferenceBook.attended(back, 3) and not ConferenceBook.due(back),
		"the conference survives save / load")


# ------------------------------------------------------------ the triennium
func _reactions() -> void:
	print("reactions")
	for lang in ["pt_BR", "en"]:
		TranslationServer.set_locale(lang)
		var s := _campaign()
		_at(s, 3, 22)
		var quiet := ConferenceTriennium.situations(ConferenceTriennium.player_facts(s))
		_check(quiet == ["NONE", "QUIET", "REP_FLAT"], "%s: a quiet triennium (%s)" % [lang, quiet])
		# the player's three years: a first a rival was after, a lost launch, a good name
		var rid := String(s.rivals[0]["id"])
		_at(s, 2, 10)
		s.race.claim("suborbital", RaceDirector.PLAYER)
		_at(s, 2, 30)
		s.race.claim("suborbital", rid)
		s.project_history.append({"id": "p_ok", "code": "CW-01", "week": s.weeks, "success": true, "type": "sounding", "target": "suborbital"})
		s.project_history.append({"id": "p_boom", "code": "CW-02", "week": s.weeks + 4, "success": false, "type": "demo_sat", "target": "leo"})
		_at(s, 3, 22)
		s.reputation = float((s.rules["start"] as Dictionary).get("reputation", 20)) + 6.0
		ConferenceBook.answer(s, true)   # the invitation marks the reputation before the visit's reward
		var f := ConferenceTriennium.player_facts(s, rid)
		_check((f["firsts"] as Array) == ["suborbital"] and int(f["launches"]) == 2 and int(f["fails"]) == 1
			and String(f["fail_code"]) == "CW-02" and absf(float(f["rep"]) - 6.0) < 0.01,
			"%s: the player's facts follow the race and the history (%s)" % [lang, f])
		_check(ConferenceTriennium.situations(f) == ["FIRST_STOLE", "FAIL_ONE", "REP_UP"], "%s: a first taken from the rival" % lang)
		var ms := TranslationServer.translate(String(s.race.milestone("suborbital")["short_key"]))
		var texts := {}
		for r in s.rivals:
			var lid := TycoonLegends.rival_leader_id(String(r["id"]))
			var t := ConferenceTriennium.reaction(s, lid, ConferenceBook.ROLE_RIVAL, String(r["id"]))
			texts[lid] = t
			_check(_filled(t) and t.contains("CW-02"), "%s: %s reacts: %s" % [lang, lid, t])
		_check(String(texts.values()[0]).contains(ms), "%s: the robbed rival names the milestone" % lang)
		_check(texts.values()[0] != texts.values()[1] and texts.values()[1] != texts.values()[2],
			"%s: each leader in its own voice" % lang)
		var lenda := ConferenceTriennium.reaction(s, "halleyzinho", ConferenceBook.ROLE_GUEST)
		_check(_filled(lenda), "%s: a mentor Lenda reacts too: %s" % [lang, lenda])
		_check(ConferenceTriennium.reaction(s, "katia", ConferenceBook.ROLE_GUEST) == "", "%s: not every Lenda has a word" % lang)
		# in the trees: the rival leader's "what do they say about us?"
		var run := ConferenceBook.make_run(s, TycoonLegends.rival_leader_id(rid), ConferenceBook.ROLE_RIVAL, rid)
		var rng := RandomNumberGenerator.new()
		run.start(rng)
		var us := -1
		for c in run.choices():
			if String(c["text"]) == TranslationServer.translate("TY_CONF_ASK_US"):
				us = int(c["index"])
		var parts := ConferenceTriennium.reaction_parts(s, TycoonLegends.rival_leader_id(rid), ConferenceBook.ROLE_RIVAL, rid)
		_check(us >= 0 and run.choose(us) and run.node_id == "conf_you" and run.text() == parts[0]
			and String(texts.values()[0]) == " ".join(parts), "%s: the rival leader offers its reaction" % lang)
		_check(run.choose(int(run.choices()[0]["index"])) and run.node_id == "conf_you_rep" and run.text() == parts[1],
			"%s: and then the word on the reputation" % lang)
		# many firsts, many losses, reputation down: other templates, still filled
		s.race.claim("first_satellite", RaceDirector.PLAYER)
		s.project_history.append({"id": "p_boom2", "code": "CW-03", "week": s.weeks - 2, "success": false})
		s.conference["rep_marks"][str(s.year())] = s.conference["rep_marks"][str(s.year())] - 12.0
		s.race.ai[String(s.rivals[2]["id"])]["next"] = s.race.milestone_index("probe_moon")
		var f2 := ConferenceTriennium.player_facts(s, String(s.rivals[2]["id"]))
		_check(ConferenceTriennium.situations(f2) == ["FIRST_MANY", "FAIL_MANY", "REP_DOWN"], "%s: many firsts, many losses (%s)" % [lang, ConferenceTriennium.situations(f2)])
		_check(_filled(ConferenceTriennium.reaction(s, "cifrinha", ConferenceBook.ROLE_RIVAL, "nimbo")), "%s: those fill too" % lang)
	TranslationServer.set_locale("pt_BR")


func _tip_state() -> TycoonState:
	var s := _campaign()
	_at(s, 3, 22)
	for t: Dictionary in TycoonResearch.techs():
		TycoonResearch.complete(s, String(t["id"]))
	s.cash = 5.0e8
	return s


func _tip() -> void:
	print("tip")
	var s := _tip_state()
	var aurora := String(s.rivals[0]["id"])
	var nimbo := String(s.rivals[1]["id"])
	_check(ConferenceTriennium.tip_pick(s).is_empty(), "no tip while every rival goes for the suborbital hop (no race briefing)")
	# aurora goes for the first satellite (race briefing first_beep), nimbo for the far side (era 3)
	s.race.claim("suborbital", aurora)
	s.race.ai[aurora]["next"] = s.race.milestone_index("first_satellite")
	s.race.ai[nimbo]["next"] = s.race.milestone_index("far_side")
	_check(ConferenceTriennium.tip_for(s, nimbo) == "", "out of reach in this era: no tip (far side in era %d)" % s.era())
	_check(ConferenceTriennium.tip_for(s, aurora) == "first_beep", "the rival's next goal opens its race briefing")
	var pick := ConferenceTriennium.tip_pick(s)
	_check(String(pick.get("rival", "")) == aurora, "the host tips off that rival")
	# the host's tree has the tip and every line fills
	var host := ConferenceBook.make_run(s, "keplerino", ConferenceBook.ROLE_HOST)
	_check((host.tree["nodes"] as Dictionary).has("g_tip") and _filled(ChatterBook.text("{g_tip}", host.vars)),
		"Keplerino's gossip carries the tip: %s" % ChatterBook.text("{g_tip}", host.vars))
	var has_choice := false
	for c: Dictionary in (host.tree["nodes"]["g_" + aurora]["choices"] as Array):
		has_choice = has_choice or String(c.get("goto", "")) == "g_tip"
	_check(has_choice, "the tip is a choice in that rival's gossip")
	var o := ConferenceTriennium.grant_tip(s, aurora)
	var board := BriefingDesk.offers(s)
	_check(not o.is_empty() and String(board[0]["id"]) == "first_beep" and String(board[0].get("tip", "")) == aurora,
		"hearing it puts the briefing at the top of the board")
	_check(int(o["expires_week"]) == s.weeks + int((ConferenceBook.cfg("tip", {}) as Dictionary).get("weeks", 24)), "the tip expires")
	_check(BriefingDesk.client_text(o) != "" and _filled(BriefingDesk.client_text(o)), "the card says it is a fair tip: %s" % BriefingDesk.client_text(o))
	_check(String(s.news[0]["key"]) == "TY_CONF_NEWS_TIP", "a ticker line for the tip")
	# capped: one per conference
	s.race.ai[nimbo]["next"] = s.race.milestone_index("first_satellite")
	_check(ConferenceTriennium.tip_for(s, nimbo) == "" and ConferenceTriennium.grant_tip(s, nimbo).is_empty()
		and ConferenceTriennium.tip_pick(s).is_empty(), "one tip per conference")
	var n := 0
	for b: Dictionary in BriefingDesk.offers(s):
		n += 1 if b.has("tip") else 0
	_check(n == 1, "one tip offer on the board")
	# it expires
	var exp := int(o["expires_week"])
	s.weeks = exp - 1
	BriefingDesk.week(s)
	_check(not BriefingDesk.offer(s, "first_beep").is_empty(), "still on the board the week before it expires")
	s.weeks = exp
	BriefingDesk.week(s)
	_check(BriefingDesk.offer(s, "first_beep").is_empty() or not BriefingDesk.offer(s, "first_beep").has("tip"), "gone when it expires")
	# the next conference may tip again; a milestone the player already holds gives none
	_at(s, 6, 22)
	_check(ConferenceTriennium.tips_given(s) == 0, "a new conference, a new tip")
	s.race.claim("first_satellite", RaceDirector.PLAYER)
	_check(ConferenceTriennium.tip_for(s, aurora) == "", "no tip for a milestone the player already holds")
	# saved with the campaign
	var back := TycoonSave.state_from(TycoonSave.decode(JSON.parse_string(JSON.stringify(TycoonSave.encode(s.to_dict())))))
	_check(String(ConferenceTriennium.tip_record(back).get("briefing", "")) == "first_beep", "the tip record survives save / load")


func _award() -> void:
	print("award")
	var s := _campaign()
	_at(s, 3, 22)
	_check(ConferenceTriennium.award_winner(s) == "", "nobody did anything: no winner")
	var aurora := String(s.rivals[0]["id"])
	_at(s, 2, 5)
	s.race.claim("suborbital", aurora)
	s.race.claim("first_satellite", aurora)
	_at(s, 3, 22)
	_check(ConferenceTriennium.award_winner(s) == aurora, "a rival with two firsts wins")
	var rep0 := s.reputation
	var rec := ConferenceTriennium.award(s)
	_check(String(rec["winner"]) == aurora and bool(rec["new"]) and absf(s.reputation - rep0) < 0.001 and ConferenceTriennium.trophies(s).is_empty(),
		"a rival's win: no prize, no trophy")
	# year 6: the player's triennium is the best
	_at(s, 4, 10)
	s.race.claim("long_signal", RaceDirector.PLAYER)
	s.race.claim("cometling_space", RaceDirector.PLAYER)
	s.race.claim("cometling_orbit", RaceDirector.PLAYER)
	s.race.claim("long_signal", aurora)
	_at(s, 6, 22)
	var scores := ConferenceTriennium.award_scores(s)
	_check(String(scores[0]["id"]) == RaceDirector.PLAYER and int(scores[0]["firsts"]) == 3 and int(scores[1]["milestones"]) == 1,
		"the triennium's scores (%s)" % [scores.slice(0, 2)])
	_check(ConferenceTriennium.award_winner(s) == RaceDirector.PLAYER, "the player's three firsts win")
	# a burst of failures costs points
	for i in 20:
		s.project_history.append({"id": "boom%d" % i, "code": "X", "week": s.weeks - 10, "success": false})
	_check(float(ConferenceTriennium.award_scores(s)[0]["score"]) < float(scores[0]["score"]), "lost launches cost points")
	s.project_history.clear()
	rep0 = s.reputation
	var hype0 := s.hype
	rec = ConferenceTriennium.award(s)
	var rw: Dictionary = (ConferenceBook.cfg("award", {}) as Dictionary).get("reward", {})
	_check(String(rec["winner"]) == RaceDirector.PLAYER and absf(s.reputation - rep0 - float(rw.get("reputation", 0))) < 0.01
		and s.hype > hype0 and ConferenceTriennium.trophies(s) == [6], "the player's win: reputation, hype and a trophy")
	var rep1 := s.reputation
	var again := ConferenceTriennium.award(s)
	_check(not bool(again["new"]) and absf(s.reputation - rep1) < 0.001 and ConferenceTriennium.trophies(s) == [6], "decided once: no second prize")
	_check(String(s.news[0]["key"]) == "TY_CONF_NEWS_AWARD", "a ticker line for the award")
	for lang in ["pt_BR", "en"]:
		TranslationServer.set_locale(lang)
		var r := ConferenceTriennium.ceremony_run(s, again)
		r.start(RandomNumberGenerator.new())
		var said: Array[String] = []
		var guard := 0
		while not r.is_over() and guard < 8:
			said.append(r.text())
			guard += 1
			if r.choices().is_empty() or not r.choose(int(r.choices()[0]["index"])):
				break
		var ok := said.size() == 4
		for t in said:
			ok = ok and _filled(t)
		_check(ok, "%s: the ceremony: %s" % [lang, " | ".join(said)])
	TranslationServer.set_locale("pt_BR")
	var back := TycoonSave.state_from(TycoonSave.decode(JSON.parse_string(JSON.stringify(TycoonSave.encode(s.to_dict())))))
	_check(ConferenceTriennium.trophies(back) == [6] and ConferenceTriennium.awarded(back), "the trophy survives save / load")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _scene() -> void:
	print("in the tycoon scene")
	TranslationServer.set_locale("pt_BR")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(6)
	main.race_flow.autosave = false
	if main.tutorial:
		main.tutorial.set_process(false)
	if main.hud.current_screen() != "":
		main.hud.close_screen()
	await _frames(2)
	main.state.tutorials = {"seen": {"campus": true}}
	main.state.race.pending_pages.clear()
	_check(main.conference != null, "TycoonMain keeps a ConferenceFlow")
	# the invitation
	_at(main.state, 3, int(ConferenceBook.cfg("week", 22)) - 1)
	main.clock.set_speed(2)
	main.state.advance_week()
	await _frames(3)
	if main.hud.current_screen() == "newspaper":   # a front page may come first
		main.hud.close_screen()
		await _frames(3)
	_check(main.hud.current_screen() == "conference", "the invitation opens at its week (%s)" % main.hud.current_screen())
	_check(main.clock.speed == 0, "the clock holds under the invitation")
	main.conference.answer(true)
	main.hud.close_screen()
	await _frames(4)
	_check(main.conference.is_open(), "going opens the fair")
	var fair := main.conference.fair
	_check(fair != null and fair.camera.current, "the fair's camera is current")
	_check(not main.campus.visible and not (main.get_node("UI") as CanvasLayer).visible, "campus and HUD hidden")
	_check(fair.npcs.size() == ConferenceBook.attendees(main.state).size(), "every attendee stands at the fair (%d)" % fair.npcs.size())
	_check(fair.get_node_or_null("Built/Stand_" + String(main.state.rivals[0]["id"])) != null, "a stand per rival")
	# walk: the player moves and stays out of the stands
	var p0 := fair.player.position
	fair.player.velocity = fair.player.forward() * 4.0
	fair.player.step(0.1)
	_check(fair.player.position.distance_to(p0) > 0.01, "the player steps")
	var inside := fair.collide(Vector2(0, 0), Vector2(0, -16.5))
	_check(Vector2(0, -16.5).distance_to(inside) > 0.5, "a stand blocks the way")
	# talk to a rival leader
	var leader: Dictionary = {}
	for e in fair.npcs:
		if String(e["role"]) == ConferenceBook.ROLE_RIVAL:
			leader = e
			break
	fair.player.position = (leader["node"] as Node3D).position + Vector3(0, 0, 0)
	_check(fair.talk_to(leader), "E on a rival leader opens the dialogue box")
	await _frames(2)
	_check(main.talk.is_open() and not fair.player.enabled, "talking: the box is up, the player holds still")
	var news := -1
	for i in main.talk.shown_choices.size():
		if String(main.talk.shown_choices[i]["text"]) == tr("TY_CONF_ASK_NEWS"):
			news = i
	main.talk.choose(news)
	await _frames(2)
	print("    ", main.talk.text_label.text)
	_check(main.talk.text_label.text.contains(tr("TY_CONF_L_WRAP").get_slice("{", 0).strip_edges()), "the report is on show")
	main.talk.close()
	await _frames(2)
	_check(String(leader["rival"]) in (ConferenceBook.store(main.state)["heard"] as Array), "the report counts as heard")
	_check(fair.player.enabled, "the player walks again")
	# the award ceremony on the stage
	var ap := fair.get_node("Ceremony/Approach") as Node3D
	fair.player.position = fair.to_local(ap.global_position)
	await _frames(2)
	_check(fair.near_stage() and fair.focus.has("stage"), "the stage shows its prompt at its foot")
	_check(fair.interact(), "E at the stage starts the ceremony")
	await _frames(2)
	_check(main.talk.is_open() and not fair.ceremony.is_empty() and fair.get_node_or_null("Ceremony/Stage_keplerino") != null,
		"the host is on the stage, announcing in the dialogue box")
	var host_entry: Dictionary = {}
	for e in fair.npcs:
		if String(e["role"]) == ConferenceBook.ROLE_HOST:
			host_entry = e
	_check(not (host_entry["node"] as Node3D).visible, "the host left his kiosk for the stage")
	var winner := String(fair.ceremony["rec"]["winner"])
	print("    winner: '%s' | %s" % [winner, main.talk.text_label.text])
	main.talk.choose(0)
	await _frames(3)
	_check(fair.run != null and fair.run.node_id == "aw_win", "the winner is named")
	if winner != "":
		_check(fair.ceremony["winner"] != null and (fair.get_node("Ceremony/Confetti") as GPUParticles3D).emitting,
			"the winner's leader on the podium, confetti falling")
	main.talk.close()
	await _frames(2)
	var stand_in := fair.get_node_or_null("Ceremony/Stage_keplerino")
	_check(fair.ceremony.is_empty() and (host_entry["node"] as Node3D).visible
		and (stand_in == null or stand_in.is_queued_for_deletion()), "after the ceremony everyone goes back")
	_check(ConferenceTriennium.awarded(main.state) and fair.player.enabled, "the award is decided and the player walks again")
	# an exchange plays when the player walks up (a late fair: more Lendas)
	fair.leave_requested.emit()
	await _frames(3)
	_at(main.state, 24, 30)
	main.conference.dev_open()
	await _frames(3)
	fair = main.conference.fair
	if not fair.duo_nodes.is_empty():
		main.chatter.force_enabled = 1
		var d: Dictionary = fair.duo_nodes[0]
		fair.player.position = (d["a"] as Node3D).position + Vector3(0, 0, 3)
		await _frames(3)
		_check(bool(d["said"]), "a Lenda exchange plays nearby")
	else:
		print("    (no exchange at this fair)")
	# leave
	fair.leave_requested.emit()
	await _frames(3)
	_check(not main.conference.is_open() and main.campus.visible and main.camera.current, "leaving brings the campus back")
	_check(main.clock.speed == 2, "the clock gets its speed back (%d)" % main.clock.speed)
	_check(main.chatter.camera == main.camera, "the bubbles get the campus camera back")
	# the dev shortcut
	main.conference.dev_open()
	await _frames(3)
	_check(main.conference.is_open(), "dev: straight to the fair")
	main.conference.leave()
	await _frames(2)
	main.queue_free()
	await _frames(2)
