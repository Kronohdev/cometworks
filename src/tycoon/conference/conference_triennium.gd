class_name ConferenceTriennium
extends RefCounted
## The player's own three years at the Conferência dos Cometinhos (data/tycoon/conference.json
## "reactions", "tip", "award"). Pure data + rules on a TycoonState, no scene access:
##   - player_facts: what the agency did since the last conference, from real state: its race
##     claims (RaceDirector, firsts and later ones), its launches (ProjectDesk's project_history:
##     the failures), its missions lost in operation (SpaceTracking) and the reputation gained
##     since the last invitation (TycoonState.conference "rep_marks")
##   - reaction: a rival leader's (or a mentor Lenda's) take on it in their own voice, through
##     the TY_CONF_YOU_<VOICE>_<SITUATION> templates of i18n/conference_strings.csv
##   - the tip: Keplerino's gossip on one rival's next goal turns into a time-limited race
##     briefing on the mission board (BriefingDesk), once per conference, only when the agency
##     can take it now
##   - the "Agência do triênio" award: the triennium's milestones, firsts and reputation; the
##     winner is decided once per conference and, if it is the player, pays a little and keeps a
##     trophy (TycoonState.conference "awards", "trophies")

const VOICE_LENDA := "LENDA"


static func _cfg(part: String) -> Dictionary:
	var v: Variant = ConferenceBook.cfg(part, {})
	return v if v is Dictionary else {}


static func _t(key: String, v: Dictionary) -> String:
	return TranslationServer.translate(key).format(v)


static func _start_rep(s: TycoonState) -> float:
	return float((s.rules.get("start", {}) as Dictionary).get("reputation", 20))


# ------------------------------------------------------------ reputation marks
## Notes the reputation when this year's invitation is answered (ConferenceBook.answer calls it
## before the visit's reward), the base of the next triennium's "reputation gained".
static func mark(s: TycoonState) -> void:
	var st := ConferenceBook.store(s)
	if not st.get("rep_marks") is Dictionary:
		st["rep_marks"] = {}
	var marks: Dictionary = st["rep_marks"]
	if not marks.has(str(s.year())):
		marks[str(s.year())] = s.reputation


## The reputation gained in the triennium: from the last invitation answered before this year
## (else the campaign's start) to this year's invitation (or now, when it is not answered yet).
static func rep_gain(s: TycoonState) -> float:
	var marks: Variant = s.conference.get("rep_marks", {})
	var m: Dictionary = marks if marks is Dictionary else {}
	var y := s.year()
	var now := float(m[str(y)]) if m.has(str(y)) else s.reputation
	var base := _start_rep(s)
	var best := -1
	for k: Variant in m:
		var ky := int(str(k))
		if ky < y and ky > best:
			best = ky
			base = float(m[k])
	return now - base


# ------------------------------------------------------------ the player's three years
## What the player's agency did since the last conference: {"firsts" [milestone ids, oldest
## first], "later" [ids], "first_name" / "last_name" (the latest of each), "stole" (a first that
## rival `rid` was after, by name, "" if none), "launches", "fails" (launches lost), "lost"
## (missions lost in operation), "fail_code" (the latest failure's code), "rep" (gained)}.
static func player_facts(s: TycoonState, rid := "") -> Dictionary:
	var since := ConferenceBook.since_week(s)
	var race := s.race
	var firsts: Array[String] = []
	var later: Array[String] = []
	for c in race.claims_of(RaceDirector.PLAYER):
		if int(c["week"]) < since:
			continue
		if int(c["order"]) == 0:
			firsts.append(String(c["milestone"]))
		else:
			later.append(String(c["milestone"]))
	var by_week := func(a: String, b: String) -> bool:
		return int(race.first_of(a).get("week", 0)) < int(race.first_of(b).get("week", 0))
	firsts.sort_custom(by_week)
	# a first the rival was after: it claimed it later, or it is still its next goal
	var stole := ""
	if rid != "":
		var nx := int(ConferenceBook.rival_facts(s, rid)["next"])
		var nx_id := String(race.milestones[nx]["id"]) if nx >= 0 and nx < race.milestones.size() else ""
		for id in firsts:
			if race.has_claimed(id, rid) or id == nx_id:
				stole = ConferenceBook._ms_name(race.milestone(id))
	var launches := 0
	var fails := 0
	var fail_code := ""
	for h: Dictionary in s.project_history:
		if int(h.get("week", -1)) < since:
			continue
		launches += 1
		if not bool(h.get("success", true)):
			fails += 1
			fail_code = String(h.get("code", ""))
	var lost := 0
	for t: Dictionary in SpaceTracking.missions(s):
		if String(t.get("owner", "")) != SpaceTracking.PLAYER or String(t.get("outcome", "")) == "fail":
			continue
		var lt := float(t.get("lost_t", -1.0))
		if lt >= 0.0 and lt >= float(since) * SpaceTracking.WEEK:
			lost += 1
	return {"firsts": firsts, "later": later,
		"first_name": ConferenceBook._ms_name(race.milestone(firsts[-1])) if not firsts.is_empty() else "",
		"last_name": ConferenceBook._ms_name(race.milestone(later[-1])) if not later.is_empty() else "",
		"stole": stole, "launches": launches, "fails": fails, "lost": lost, "fail_code": fail_code,
		"rep": rep_gain(s)}


## The voice a Lenda speaks the reactions in ("" when it has none: it does not react).
static func voice(id: String, role: String) -> String:
	var voices: Dictionary = _cfg("reactions").get("voices", {})
	if voices.has(id):
		return String(voices[id])
	if role == ConferenceBook.ROLE_RIVAL:
		return VOICE_LENDA
	return VOICE_LENDA if id in (_cfg("reactions").get("lendas", []) as Array) else ""


## The situations of the player's triennium, one per sentence: milestones, launches, reputation.
static func situations(f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var nf := (f["firsts"] as Array).size()
	if String(f["stole"]) != "":
		out.append("FIRST_STOLE")
	elif nf == 1:
		out.append("FIRST_ONE")
	elif nf > 1:
		out.append("FIRST_MANY")
	elif not (f["later"] as Array).is_empty():
		out.append("LATER")
	else:
		out.append("NONE")
	var bad := int(f["fails"]) + int(f["lost"])
	if bad == 1:
		out.append("FAIL_ONE")
	elif bad > 1:
		out.append("FAIL_MANY")
	elif int(f["launches"]) > 0:
		out.append("CLEAN")
	else:
		out.append("QUIET")
	var flat := float(_cfg("reactions").get("rep_flat", 1.5))
	out.append("REP_UP" if float(f["rep"]) >= flat else ("REP_DOWN" if float(f["rep"]) <= -flat else "REP_FLAT"))
	return out


## Lenda `id`'s take on the player's three years ("" when it does not react): three sentences
## in its voice. `rid` is the rival it leads (for the "you took it from us" first).
static func reaction(s: TycoonState, id: String, role: String, rid := "") -> String:
	return " ".join(reaction_parts(s, id, role, rid))


## The reaction in two lines for the dialogue box: [the milestones and the launches, the
## reputation]; [] when the Lenda does not react.
static func reaction_parts(s: TycoonState, id: String, role: String, rid := "") -> Array[String]:
	var vc := voice(id, role)
	if vc == "":
		return []
	var f := player_facts(s, rid)
	var v := {"agency": s.agency_name, "first": f["first_name"], "stole": f["stole"],
		"n": (f["firsts"] as Array).size() if not (f["firsts"] as Array).is_empty() else (f["later"] as Array).size(),
		"last": f["last_name"], "fails": int(f["fails"]) + int(f["lost"]), "code": f["fail_code"],
		"launches": f["launches"], "rep": int(round(absf(float(f["rep"]))))}
	if String(v["code"]) == "":
		v["code"] = s.agency_name
	var parts: Array[String] = []
	for sit in situations(f):
		var key := "TY_CONF_YOU_%s_%s" % [vc, sit]
		if TranslationServer.translate(key) == key:
			key = "TY_CONF_YOU_%s_%s" % [VOICE_LENDA, sit]
		parts.append(_t(key, v))
	return [parts[0] + " " + parts[1], parts[2]]


# ------------------------------------------------------------ the tip
static func tip_record(s: TycoonState) -> Dictionary:
	var t: Variant = s.conference.get("tip", {})
	return t if t is Dictionary else {}


## Tips already given at this year's conference.
static func tips_given(s: TycoonState) -> int:
	var t := tip_record(s)
	return int(t.get("count", 1)) if int(t.get("year", 0)) == s.year() else 0


## The race briefing rival `rid`'s next goal could hand the player now ("" when none): its
## next milestone has a briefing in "tip.briefings", the player does not hold that milestone,
## the agency can take the briefing (BriefingDesk.eligible) and no tip was given yet here.
static func tip_for(s: TycoonState, rid: String) -> String:
	var cfg := _cfg("tip")
	if tips_given(s) >= int(cfg.get("per_conference", 1)):
		return ""
	var race := s.race
	var nx := int(ConferenceBook.rival_facts(s, rid)["next"])
	if nx < 0 or nx >= race.milestones.size():
		return ""
	var ms_id := String(race.milestones[nx]["id"])
	if race.has_claimed(ms_id, RaceDirector.PLAYER):
		return ""
	var bid := String((cfg.get("briefings", {}) as Dictionary).get(ms_id, ""))
	var b := BriefingDesk.briefing(bid)
	if b.is_empty() or String(b.get("kind", "")) != "race" or not BriefingDesk.eligible(s, b):
		return ""
	return bid


## The one rival whose goal the host can tip off at this conference: the first, in the rivals'
## order, with a tip_for. {"rival", "briefing"} or {}.
static func tip_pick(s: TycoonState) -> Dictionary:
	for r: Dictionary in s.rivals:
		var bid := tip_for(s, String(r["id"]))
		if bid != "":
			return {"rival": String(r["id"]), "briefing": bid}
	return {}


## The tip is heard: rival `rid`'s next goal becomes an offer on the board (at the top, for
## "tip.weeks" weeks, the reward a little higher). Returns the offer, {} when there is no tip
## to give (capped, out of reach, already the player's).
static func grant_tip(s: TycoonState, rid: String) -> Dictionary:
	var bid := tip_for(s, rid)
	if bid == "":
		return {}
	var cfg := _cfg("tip")
	var dd := Discovery.d(s)
	var board: Array = dd["board"]
	for o: Dictionary in board.duplicate():
		if String(o.get("id", "")) == bid:
			board.erase(o)
	var o := BriefingDesk.make_offer(s, BriefingDesk.briefing(bid))
	var step := float(BriefingDesk.data().get("round_to", 5000))
	o["reward"] = maxf(roundf(float(o["reward"]) * float(cfg.get("reward_mult", 1.0)) / step) * step, step)
	o["expires_week"] = s.weeks + int(cfg.get("weeks", 24))
	o["tip"] = rid
	o["tip_name"] = s.race.agency_name(rid)
	board.push_front(o)
	var nx := int(ConferenceBook.rival_facts(s, rid)["next"])
	s.conference["tip"] = {"year": s.year(), "count": tips_given(s) + 1, "rival": rid, "briefing": bid,
		"milestone": String(s.race.milestones[nx]["id"]), "expires_week": int(o["expires_week"])}
	s.news.push_front({"key": "TY_CONF_NEWS_TIP", "args": [BriefingDesk.title_key(bid), s.race.agency_name(rid)]})
	s.changed.emit()
	return o


## The host's line for the tip on rival `rid` (its next goal and the briefing it opens).
static func tip_line(s: TycoonState, rid: String, bid: String) -> String:
	var f := ConferenceBook.rival_facts(s, rid)
	return _t("TY_CONF_HOST_TIP_RACE", {"rival": f["rival"], "next": f["next_name"],
		"mission": TranslationServer.translate(BriefingDesk.title_key(bid)), "weeks": int(_cfg("tip").get("weeks", 24))})


# ------------------------------------------------------------ the award
## The triennium of every agency: [{"id" ("player" or a rival id), "firsts", "milestones",
## "rep", "fails", "score"}], the player first, then the rivals in their order.
static func award_scores(s: TycoonState) -> Array[Dictionary]:
	var cfg := _cfg("award")
	var since := ConferenceBook.since_week(s)
	var out: Array[Dictionary] = []
	var ids: Array[String] = [RaceDirector.PLAYER]
	for r: Dictionary in s.rivals:
		ids.append(String(r["id"]))
	for id in ids:
		var firsts := 0
		var ms := 0
		var rep := 0.0
		for c in s.race.claims_of(id):
			if int(c["week"]) < since:
				continue
			ms += 1
			if int(c["order"]) == 0:
				firsts += 1
			if id != RaceDirector.PLAYER:
				rep += float(s.race.milestone(String(c["milestone"])).get("rep", 0)) * (1.0 if int(c["order"]) == 0 else 0.5)
		var fails := 0
		if id == RaceDirector.PLAYER:
			var pf := player_facts(s)
			rep = float(pf["rep"])
			fails = int(pf["fails"])
		else:
			fails = int(ConferenceBook.rival_facts(s, id)["fails"])
		var score := firsts * float(cfg.get("first", 3.0)) + ms * float(cfg.get("milestone", 1.5)) \
			+ rep * float(cfg.get("rep", 0.25)) - fails * float(cfg.get("fail", 0.75))
		out.append({"id": id, "firsts": firsts, "milestones": ms, "rep": rep, "fails": fails, "score": score})
	return out


## Who wins the "Agência do triênio" now: the best score (ties: the player, then the rivals'
## order), "" when nobody scored above zero.
static func award_winner(s: TycoonState) -> String:
	var best := ""
	var bv := 0.0
	for e in award_scores(s):
		if float(e["score"]) > bv + 0.0001:
			bv = float(e["score"])
			best = String(e["id"])
	return best


static func _awards(s: TycoonState) -> Dictionary:
	if not s.conference.get("awards") is Dictionary:
		s.conference["awards"] = {}
	return s.conference["awards"]


static func trophies(s: TycoonState) -> Array[int]:
	var out: Array[int] = []
	for y: Variant in (s.conference.get("trophies", []) if s.conference.get("trophies") is Array else []):
		out.append(int(y))
	return out


## Has this year's award been decided?
static func awarded(s: TycoonState) -> bool:
	return _awards(s).has(str(s.year()))


## This year's award: decided the first time (the ceremony, else leaving the fair) and kept;
## a player's win pays "award.reward" once and keeps a trophy. Returns {"winner", "year",
## "scores", "new" (decided just now), "reward" {"reputation", "hype"} (what the player got now)}.
static func award(s: TycoonState) -> Dictionary:
	var aw := _awards(s)
	var key := str(s.year())
	var scores := award_scores(s)
	if aw.has(key):
		return {"winner": String(aw[key]), "year": s.year(), "scores": scores, "new": false, "reward": {}}
	var winner := award_winner(s)
	aw[key] = winner
	var got := {}
	if winner == RaceDirector.PLAYER:
		var rw: Dictionary = _cfg("award").get("reward", {})
		got = {"reputation": float(rw.get("reputation", 0.0)), "hype": float(rw.get("hype", 0.0))}
		s.reputation = clampf(s.reputation + float(got["reputation"]), 0.0, 100.0)
		s.hype = clampf(s.hype + float(got["hype"]), 0.0, 100.0)
		var t := trophies(s)
		if not s.year() in t:
			t.append(s.year())
		s.conference["trophies"] = t
	if winner != "":
		s.news.push_front({"key": "TY_CONF_NEWS_AWARD",
			"args": [s.race.agency_name(winner) if winner != RaceDirector.PLAYER else s.agency_name, s.year()]})
	s.changed.emit()
	return {"winner": winner, "year": s.year(), "scores": scores, "new": true, "reward": got}


## The winner's entry of award_scores ({} for none).
static func score_of(rec: Dictionary) -> Dictionary:
	for e: Dictionary in rec.get("scores", []):
		if String(e["id"]) == String(rec.get("winner", "")):
			return e
	return {}


## The ceremony as a dialogue with the host: the opening, the winner, why, and (for the
## player) the prize. A DialogueRun of the host's own look with a tree of its own.
static func ceremony_run(s: TycoonState, rec: Dictionary, world := {}) -> DialogueRun:
	var host := String(ConferenceBook.cfg("host", "keplerino"))
	var r := DialogueRun.for_legend(s, host, "fair", world)
	var winner := String(rec.get("winner", ""))
	var e := score_of(rec)
	var agency: String = s.agency_name if winner == RaceDirector.PLAYER else TranslationServer.translate(s.race.agency_name(winner))
	var v := {"agency": agency, "year": int(rec.get("year", s.year())), "firsts": int(e.get("firsts", 0)),
		"n": int(e.get("milestones", 0)), "rep": int(round(absf(float(e.get("rep", 0.0)))))}
	var rw: Dictionary = _cfg("award").get("reward", {})
	v["prize_rep"] = int(rw.get("reputation", 0))
	v["prize_hype"] = int(rw.get("hype", 0))
	var nodes := {}
	nodes["aw_open"] = {"lines": [{"text_key": "{aw_open}", "face": "joy", "pose": "wave"}],
		"choices": [{"text_key": "TY_CONF_AWARD_DRUMROLL", "goto": "aw_win"}]}
	if winner == "":
		r.vars["aw_win"] = _t("TY_CONF_AWARD_NOBODY", v)
		nodes["aw_win"] = {"lines": [{"text_key": "{aw_win}", "face": "content", "pose": "shrug"}],
			"choices": [{"text_key": "TY_CONF_AWARD_CLAP", "end": true}]}
	else:
		r.vars["aw_win"] = _t("TY_CONF_AWARD_WIN_YOU" if winner == RaceDirector.PLAYER else "TY_CONF_AWARD_WIN", v)
		var why := "TY_CONF_AWARD_WHY" if int(v["firsts"]) > 0 else ("TY_CONF_AWARD_WHY_NOFIRST" if int(v["n"]) > 0 else "TY_CONF_AWARD_WHY_REP")
		r.vars["aw_why"] = _t(why, v)
		nodes["aw_win"] = {"lines": [{"text_key": "{aw_win}", "face": "joy", "pose": "laugh"}],
			"choices": [{"text_key": "TY_CONF_AWARD_CLAP", "goto": "aw_why"}]}
		if winner == RaceDirector.PLAYER:
			r.vars["aw_prize"] = _t("TY_CONF_AWARD_PRIZE", v)
			nodes["aw_why"] = {"lines": [{"text_key": "{aw_why}", "face": "happy", "pose": "point"}],
				"choices": [{"text_key": "TY_CONF_AWARD_THANKS", "goto": "aw_prize"}]}
			nodes["aw_prize"] = {"lines": [{"text_key": "{aw_prize}", "face": "joy", "pose": "salute"}],
				"choices": [{"text_key": "TY_CONF_AWARD_BYE", "end": true}]}
		else:
			nodes["aw_why"] = {"lines": [{"text_key": "{aw_why}", "face": "happy", "pose": "point"}],
				"choices": [{"text_key": "TY_CONF_AWARD_BYE", "end": true}]}
	r.vars["aw_open"] = _t("TY_CONF_AWARD_OPEN", v)
	r.tree = {"start": "aw_open", "nodes": nodes, "menus": {}}
	r.tree_id = "conference_award"
	return r
