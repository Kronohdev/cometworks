class_name ConferenceBook
extends RefCounted
## A Conferência dos Cometinhos (data/tycoon/conference.json): every few campaign years the
## agency is invited to a fair where the Lendas and the rival agencies show up. Pure data + rules
## on a TycoonState, no scene access (tests run it headless):
##   - the calendar: which years have a conference, when the invitation is due, the answer
##   - who comes (attendees) and which Lendas stand together to trade their campus exchange
##     (duos, chatter.json pairs between two Lendas)
##   - the rival news: live race state (RaceDirector claims and AI, SpaceTracking failures) told
##     through the TY_CONF_* templates of i18n/conference_strings.csv, in the first person (the
##     rival's own leader at its stand, "l") or as gossip (the host and the guests, "g")
##   - the fair's dialogue trees: each Lenda keeps its own tree of dialogues.json (copied, never
##     changed) with a few fair choices added (the report, the gossip, the host's rival menu);
##     the composed sentences live in the run's vars and a fair line's text_key is the bare
##     placeholder ("{conf_status}"), which TranslationServer leaves as it is and the run fills
## State: TycoonState.conference = {"last_year", "attended": [years], "skipped": [years],
## "heard": [rival ids], "talked": [Lenda ids]} (the last two for the conference under way), plus
## what ConferenceTriennium keeps ("rep_marks", "tip", "awards", "trophies").
## The player's own three years (the rivals' and the Lendas' reactions, the host's tip, the
## award) are ConferenceTriennium's; tree_for / vars_for add their choices and lines.

const DATA_PATH := "res://data/tycoon/conference.json"
const ROLE_HOST := "host"
const ROLE_RIVAL := "rival"
const ROLE_GUEST := "guest"
## the host's lines between two reports: Keplerino's gossip one-liners (dialogues.json's
## lenda_keplerino tree has the rest of them in its own "gossip" node)
const HOST_MORE: Array[String] = ["TY_LT_KEPLERINO_GOSSIP_5", "TY_LT_KEPLERINO_GOSSIP_7", "TY_LT_KEPLERINO_GOSSIP_8",
	"TY_LT_KEPLERINO_GOSSIP_11"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(DATA_PATH)
	return _data


static func cfg(key: String, default: Variant = null) -> Variant:
	return data().get(key, default)


static func player_cfg(key: String, default: float) -> float:
	return float((data().get("player", {}) as Dictionary).get(key, default))


# ------------------------------------------------------------ state
static func store(s: TycoonState) -> Dictionary:
	for k in ["attended", "skipped"]:
		var years: Array = []
		for y: Variant in (s.conference.get(k, []) if s.conference.get(k) is Array else []):
			years.append(int(y))   # a loaded save has them as floats
		s.conference[k] = years
	if not s.conference.get("heard") is Array:
		s.conference["heard"] = []
	if not s.conference.get("talked") is Array:
		s.conference["talked"] = []
	if not s.conference.has("last_year"):
		s.conference["last_year"] = 0
	return s.conference


static func last_year(s: TycoonState) -> int:
	return int(s.conference.get("last_year", 0))


# ------------------------------------------------------------ calendar
static func is_conference_year(year: int) -> bool:
	var first := int(cfg("first_year", 3))
	var every := maxi(int(cfg("every_years", 3)), 1)
	return year >= first and (year - first) % every == 0


## The first conference year from `year` on (0 when none is left before the comet).
static func next_year(s: TycoonState, year := -1) -> int:
	var y := maxi(year if year > 0 else s.year(), 1)
	var last := int(s.rules.get("campaign_years", 25))
	while y <= last:
		if is_conference_year(y):
			return y
		y += 1
	return 0


## Is this year's invitation waiting for an answer?
static func due(s: TycoonState) -> bool:
	if s.is_over() or Bankruptcy.is_bankrupt(s):
		return false
	return is_conference_year(s.year()) and s.week() >= int(cfg("week", 22)) and last_year(s) < s.year()


## The player answered this year's invitation: going (the reward, a line in the ticker) or not.
static func answer(s: TycoonState, go: bool) -> void:
	var st := store(s)
	st["last_year"] = s.year()
	(st["heard"] as Array).clear()
	(st["talked"] as Array).clear()
	var list: Array = st["attended" if go else "skipped"]
	if not s.year() in list:
		list.append(s.year())
	ConferenceTriennium.mark(s)   # the triennium's reputation, before the visit's reward
	if go:
		var rw: Dictionary = cfg("reward", {})
		s.reputation = clampf(s.reputation + float(rw.get("reputation", 0.0)), 0.0, 100.0)
		s.hype = clampf(s.hype + float(rw.get("hype", 0.0)), 0.0, 100.0)
		s.news.push_front({"key": "TY_CONF_NEWS_WENT", "args": [s.year()]})
	else:
		s.news.push_front({"key": "TY_CONF_NEWS_SKIPPED", "args": [s.year()]})
	s.changed.emit()


static func attended(s: TycoonState, year: int) -> bool:
	return year in (store(s)["attended"] as Array)


## Heard rival `rid`'s report at the conference under way: a little hype, once each.
static func heard(s: TycoonState, rid: String) -> bool:
	var h: Array = store(s)["heard"]
	if rid in h:
		return false
	h.append(rid)
	s.hype = clampf(s.hype + float((cfg("rival_reward", {}) as Dictionary).get("hype", 0.0)), 0.0, 100.0)
	s.changed.emit()
	return true


static func talked(s: TycoonState, legend_id: String) -> void:
	var t: Array = store(s)["talked"]
	if not legend_id in t:
		t.append(legend_id)


# ------------------------------------------------------------ who comes
## The Lendas at the fair: [{"id", "role", "rival"}], the host first, then the rival leaders (in
## the rivals' order), then the guests whose era has come.
static func attendees(s: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var skip: Array = cfg("skip", [])
	var host := String(cfg("host", ""))
	if host != "" and _talks(host):
		out.append({"id": host, "role": ROLE_HOST, "rival": ""})
	for r: Dictionary in s.rivals:
		var lid := TycoonLegends.rival_leader_id(String(r["id"]))
		if lid != "" and _talks(lid):
			out.append({"id": lid, "role": ROLE_RIVAL, "rival": String(r["id"])})
	for l: Dictionary in TycoonLegends.all():
		var id := String(l["id"])
		if id == host or id in skip or String(l.get("kind", "")) == "rival_leader" or not _talks(id):
			continue
		if int(l.get("era", 1)) <= s.era():
			out.append({"id": id, "role": ROLE_GUEST, "rival": ""})
	return out


static func _talks(id: String) -> bool:
	if TycoonLegends.legend(id).is_empty():
		return false
	var d := ChatterBook.dialogues()
	var tree := String((d.get("by_legend", {}) as Dictionary).get(id, d.get("legend", "legend")))
	return DialogueRun.has_tree(tree)


## The Lenda-to-Lenda exchanges of chatter.json among `ids`: [{"a", "b", "a_key", "b_key"}], each
## Lenda in one at most (the first pair that names it wins).
static func duos(ids: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used := {}
	for p: Dictionary in ChatterBook.chatter().get("pairs", []):
		var a: Variant = (p.get("if", {}) as Dictionary).get("legend", null)
		var b: Variant = (p.get("b_if", {}) as Dictionary).get("legend", null)
		if not (a is String and b is String):
			continue
		if not (a in ids and b in ids) or used.has(a) or used.has(b):
			continue
		used[a] = true
		used[b] = true
		out.append({"a": String(a), "b": String(b), "a_key": String(p.get("a_key", "")), "b_key": String(p.get("b_key", ""))})
	return out


# ------------------------------------------------------------ the rival news
## The race week from which "since the last conference" counts.
static func since_week(s: TycoonState) -> int:
	return maxi(s.weeks - int(cfg("news_since_years", 3)) * s.weeks_per_year(), 0)


## What there is to know about rival `rid` now: {"rival" (name), "leader" (Lenda id), "count",
## "total", "firsts", "next" (milestone index, total when all are done), "next_name", "era",
## "era_name", "recent" (milestones taken since the last conference), "last_name", "last_week",
## "fails" (failed launches since then), "fail_name", "cooldown" (months), "left" (milestones to
## go up to the Mother-Ice), "comet_next" (the next one is the Mother-Ice), "met" (met her),
## "vs" ("ahead" | "behind" | "even": the rival against the player)}
static func rival_facts(s: TycoonState, rid: String) -> Dictionary:
	var race := s.race
	var ms: Array = race.milestones
	var total := ms.size()
	var claims := race.claims_of(rid)
	var since := since_week(s)
	var st := race.rival_state(rid)
	var nx := clampi(int(st.get("next", race.next_of(rid))), 0, total)
	while nx < total and race.has_claimed(String(ms[nx]["id"]), rid):
		nx += 1   # already theirs (taken out of turn): the next one still open
	var f := {"rival": TranslationServer.translate(race.agency_name(rid)), "leader": TycoonLegends.rival_leader_id(rid),
		"count": claims.size(), "total": total, "firsts": race.firsts_of(rid), "next": nx,
		"cooldown": int(st.get("cooldown", 0)), "met": race.met_comet(rid)}
	var era := 5
	if nx < total:
		era = int(ms[nx].get("era", s.era()))
		f["next_name"] = _ms_name(ms[nx])
		f["comet_next"] = bool(ms[nx].get("victory", false))
	else:
		f["next_name"] = ""
		f["comet_next"] = false
	f["era"] = era
	f["era_name"] = TranslationServer.translate("TY_ERA_%d" % era)
	# milestones taken since the last conference, the latest first
	var recent := 0
	var last_week := -1
	var last_id := ""
	for c in claims:
		if int(c["week"]) >= since:
			recent += 1
		if int(c["week"]) >= last_week:
			last_week = int(c["week"])
			last_id = String(c["milestone"])
	f["recent"] = recent
	f["last_week"] = last_week
	f["last_name"] = _ms_name(race.milestone(last_id)) if last_id != "" else ""
	f["last_recent"] = last_week >= since
	# failed launches since then (SpaceTracking keeps one track per failure: "rf:<rival>:<ms>:<week>")
	var fails := 0
	var fail_week := -1
	var fail_id := ""
	for t: Dictionary in SpaceTracking.missions(s):
		if String(t.get("owner", "")) != rid or String(t.get("outcome", "")) != "fail":
			continue
		var w := int(float(t.get("launch_t", 0.0)) / SpaceTracking.WEEK)
		if w < since:
			continue
		fails += 1
		if w >= fail_week:
			fail_week = w
			var parts := String(t.get("id", "")).split(":")
			fail_id = parts[2] if parts.size() > 2 else ""
	f["fails"] = fails
	f["fail_name"] = _ms_name(race.milestone(fail_id)) if fail_id != "" else ""
	# the Mother-Ice: milestones still to go, the rendezvous included
	var comet_i := total - 1
	for i in total:
		if bool(ms[i].get("victory", false)):
			comet_i = i
	var left := 0
	for i in range(0, comet_i + 1):
		if not race.has_claimed(String(ms[i]["id"]), rid) and not String(ms[i]["id"]) in (st.get("dropped", []) as Array):
			left += 1
	f["left"] = left
	var mine := race.race_points(RaceDirector.PLAYER) + (1.0 if race.met_comet(RaceDirector.PLAYER) else 0.0)
	var theirs := race.race_points(rid) + (1.0 if race.met_comet(rid) else 0.0)
	f["vs"] = "even" if absf(mine - theirs) < 0.05 else ("ahead" if theirs > mine else "behind")
	return f


static func _ms_name(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	return TranslationServer.translate(String(m.get("short_key", m.get("name_key", ""))))


static func _t(key: String, v: Dictionary) -> String:
	return TranslationServer.translate(key).format(v)


## "há 3 meses", "agorinha mesmo"... from a race week.
static func ago(s: TycoonState, week: int) -> String:
	var months := int(floor(float(s.weeks - week) / (float(s.weeks_per_year()) / 12.0)))
	if months < 1:
		return TranslationServer.translate("TY_CONF_AGO_NOW")
	if months < 12:
		return _t("TY_CONF_AGO_MONTH" if months == 1 else "TY_CONF_AGO_MONTHS", {"n": months})
	var years := months / 12
	return _t("TY_CONF_AGO_YEAR" if years == 1 else "TY_CONF_AGO_YEARS", {"n": years})


## The report on rival `rid` as three short paragraphs: {"status", "recent", "comet"}, in the
## first person of its leader (person "l") or as gossip (person "g").
static func report(s: TycoonState, rid: String, person := "g") -> Dictionary:
	var f := rival_facts(s, rid)
	var p := "TY_CONF_%s_" % person.to_upper()
	var v := {"rival": f["rival"], "count": f["count"], "total": f["total"], "firsts": f["firsts"],
		"era_n": f["era"], "era": f["era_name"], "next": f["next_name"], "n": f["recent"], "last": f["last_name"],
		"ago": ago(s, int(f["last_week"])) if int(f["last_week"]) >= 0 else "", "fails": f["fails"],
		"fail": f["fail_name"], "months": f["cooldown"], "left": f["left"]}
	var status: Array[String] = []
	var sk := "STATUS_NONE" if int(f["count"]) == 0 else ("STATUS_NOFIRST" if int(f["firsts"]) == 0 else "STATUS")
	status.append(_t(p + sk, v))
	status.append(_t(p + ("ALL_DONE" if String(f["next_name"]) == "" else "NEXT"), v))
	var recent: Array[String] = []
	if int(f["recent"]) == 0:
		recent.append(_t(p + "RECENT_NONE", v))
	else:
		recent.append(_t(p + ("RECENT_ONE" if int(f["recent"]) == 1 else "RECENT_MANY"), v))
	if int(f["fails"]) == 0:
		recent.append(_t(p + "FAILS_NONE", v))
	else:
		recent.append(_t(p + ("FAILS_ONE" if int(f["fails"]) == 1 else "FAILS_MANY"), v))
	if int(f["cooldown"]) > 0:
		recent.append(_t(p + ("COOLDOWN_ONE" if int(f["cooldown"]) == 1 else "COOLDOWN"), v))
	var comet: Array[String] = []
	if bool(f["met"]):
		comet.append(_t(p + "COMET_MET", v))
	elif bool(f["comet_next"]):
		comet.append(_t(p + "COMET_NEXT", v))
	else:
		comet.append(_t(p + "COMET_LEFT", v))
	comet.append(_t(p + "VS_" + String(f["vs"]).to_upper(), v))
	return {"status": " ".join(status), "recent": " ".join(recent), "comet": " ".join(comet)}


## The text on a rival's stand board (its live standing).
static func board_text(s: TycoonState, rid: String) -> String:
	var f := rival_facts(s, rid)
	var v := {"count": f["count"], "total": f["total"], "firsts": f["firsts"], "era_n": f["era"], "era": f["era_name"],
		"next": f["next_name"], "left": f["left"]}
	return _t("TY_CONF_BOARD_DONE" if String(f["next_name"]) == "" else "TY_CONF_BOARD", v)


## A rival's motto (rivals.json motto_key), "" when it has none.
static func motto(s: TycoonState, rid: String) -> String:
	var k := String(s.race.rival(rid).get("motto_key", ""))
	return TranslationServer.translate(k) if k != "" else ""


# ------------------------------------------------------------ the fair's conversations
## A conversation with Lenda `id` at the fair (its role from attendees()): DialogueRun.for_legend
## at "fair" with the fair tree and the composed news in its vars.
static func make_run(s: TycoonState, id: String, role: String, rival := "", world := {}) -> DialogueRun:
	var r := DialogueRun.for_legend(s, id, "fair", world)
	r.tree = tree_for(id, role, s)
	r.tree_id = "conference_" + id
	r.vars.merge(vars_for(s, id, role, rival), true)
	return r


## The composed lines of a fair conversation (placeholders of tree_for's lines).
static func vars_for(s: TycoonState, id: String, role: String, rival := "") -> Dictionary:
	var v := {}
	match role:
		ROLE_RIVAL:
			var rp := report(s, rival, "l")
			v["conf_status"] = _t("TY_CONF_L_WRAP", {"text": rp["status"]})
			v["conf_recent"] = rp["recent"]
			v["conf_comet"] = rp["comet"]
			var you := ConferenceTriennium.reaction_parts(s, id, role, rival)
			v["conf_you"] = you[0]
			v["conf_you_rep"] = you[1]
		ROLE_HOST:
			for r: Dictionary in s.rivals:
				var rid := String(r["id"])
				var gp := report(s, rid, "g")
				var name := TranslationServer.translate(s.race.agency_name(rid))
				v["q_" + rid] = _t("TY_CONF_ASK_RIVAL", {"rival": name})
				v["g_%s_status" % rid] = _t("TY_CONF_HOST_WRAP", {"rival": name, "text": gp["status"]})
				v["g_%s_recent" % rid] = gp["recent"]
				v["g_%s_comet" % rid] = gp["comet"]
			var tip := ConferenceTriennium.tip_pick(s)
			if not tip.is_empty():
				v["tip_rival"] = String(tip["rival"])
				v["g_tip"] = ConferenceTriennium.tip_line(s, String(tip["rival"]), String(tip["briefing"]))
		_:
			if not s.rivals.is_empty():
				var i := posmod(hash(id) + s.year(), s.rivals.size())
				var rid := String(s.rivals[i]["id"])
				var gp := report(s, rid, "g")
				var extra := String(gp["recent"]) if posmod(hash(id), 2) == 0 else String(gp["comet"])
				v["conf_gossip"] = _t("TY_CONF_GUEST_WRAP", {"rival": TranslationServer.translate(s.race.agency_name(rid)),
					"text": String(gp["status"]) + " " + extra})
			var you := ConferenceTriennium.reaction_parts(s, id, role)
			if not you.is_empty():
				v["conf_you"] = you[0]
				v["conf_you_rep"] = you[1]
	return v


## The Lenda's own tree (dialogues.json, copied) with the fair's choices put before its farewell.
static func tree_for(id: String, role: String, s: TycoonState = null) -> Dictionary:
	var d := ChatterBook.dialogues()
	var trees: Dictionary = d.get("trees", {})
	var tid := String((d.get("by_legend", {}) as Dictionary).get(id, d.get("legend", "legend")))
	var tree: Dictionary = (trees.get(tid, {}) as Dictionary).duplicate(true)
	if tree.is_empty():
		return tree
	if not tree.get("nodes") is Dictionary:
		tree["nodes"] = {}
	if not tree.get("menus") is Dictionary:
		tree["menus"] = {}
	var nodes: Dictionary = tree["nodes"]
	# the menu the start node offers (the Lendas' trees all use "main")
	var start_choices: Variant = (nodes.get(String(tree.get("start", "hello")), {}) as Dictionary).get("choices", "main")
	var menu_id := String(start_choices) if start_choices is String else "main"
	if not tree["menus"].get(menu_id) is Array:
		tree["menus"][menu_id] = []
	var menu: Array = tree["menus"][menu_id]
	var add: Array = []
	match role:
		ROLE_RIVAL:
			add.append({"text_key": "TY_CONF_ASK_NEWS", "goto": "conf_news"})
			add.append({"text_key": "TY_CONF_ASK_US", "goto": "conf_you"})
			nodes["conf_you"] = {"lines": [{"text_key": "{conf_you}", "face": "content", "pose": "shrug"}],
				"choices": [{"text_key": "TY_CONF_ASK_REP", "goto": "conf_you_rep"},
					{"text_key": "TY_CONF_ASK_ELSE", "goto": "conf_menu"}]}
			nodes["conf_you_rep"] = {"lines": [{"text_key": "{conf_you_rep}", "face": "happy", "pose": "nod"}],
				"choices": [{"text_key": "TY_CONF_ASK_NEWS", "goto": "conf_news"},
					{"text_key": "TY_CONF_ASK_ELSE", "goto": "conf_menu"}]}
			nodes["conf_news"] = {"lines": [{"text_key": "{conf_status}", "face": "content", "pose": "point"}],
				"choices": [{"text_key": "TY_CONF_ASK_RECENT", "goto": "conf_recent"},
					{"text_key": "TY_CONF_ASK_COMET", "goto": "conf_comet"},
					{"text_key": "TY_CONF_ASK_ELSE", "goto": "conf_menu"}]}
			nodes["conf_recent"] = {"lines": [{"text_key": "{conf_recent}", "face": "content", "pose": "nod"}],
				"choices": [{"text_key": "TY_CONF_ASK_COMET", "goto": "conf_comet"},
					{"text_key": "TY_CONF_ASK_ELSE", "goto": "conf_menu"}]}
			nodes["conf_comet"] = {"lines": [{"text_key": "{conf_comet}", "face": "happy", "pose": "salute"}],
				"choices": [{"text_key": "TY_CONF_ASK_RECENT", "goto": "conf_recent"},
					{"text_key": "TY_CONF_ASK_ELSE", "goto": "conf_menu"}]}
			nodes["conf_menu"] = {"lines": [{"text_key": "TY_CONF_RIVAL_MORE_1", "face": "happy", "pose": "nod"},
				{"text_key": "TY_CONF_RIVAL_MORE_2", "face": "joy", "pose": "laugh"}], "choices": menu_id}
		ROLE_HOST:
			var hello: Dictionary = nodes.get(String(tree.get("start", "hello")), {})
			var hl: Array = hello.get("lines", [])
			for i in 3:
				hl.push_front({"text_key": "TY_CONF_HOST_HI_%d" % (3 - i), "if": {"where": "fair"}, "face": "joy",
					"pose": ["wave", "point", "laugh"][i]})
			hello["lines"] = hl
			var rivals: Array = s.rivals if s else []
			# Keplerino's tip: one rival's next goal, a race briefing the agency can take now
			var tip := ConferenceTriennium.tip_pick(s) if s else {}
			var tip_choice := {"text_key": "TY_CONF_ASK_TIP_RACE", "goto": "g_tip", "once": true}
			if not tip.is_empty():
				nodes["g_tip"] = {"lines": [{"text_key": "{g_tip}", "face": "surprised", "pose": "point"}],
					"choices": [{"text_key": "TY_CONF_ASK_OTHERS", "goto": "conf_menu"}]}
			for r: Dictionary in rivals:
				var rid := String(r["id"])
				add.append({"text_key": "{q_%s}" % rid, "goto": "g_" + rid})
				nodes["g_" + rid] = {"lines": [{"text_key": "{g_%s_status}" % rid, "face": "content", "pose": "point"}],
					"choices": [{"text_key": "TY_CONF_ASK_MORE", "goto": "g_%s_2" % rid},
						{"text_key": "TY_CONF_ASK_OTHERS", "goto": "conf_menu"}]}
				nodes["g_%s_2" % rid] = {"lines": [{"text_key": "{g_%s_recent}" % rid, "face": "surprised", "pose": "shrug"}],
					"choices": [{"text_key": "TY_CONF_ASK_MORE", "goto": "g_%s_3" % rid},
						{"text_key": "TY_CONF_ASK_OTHERS", "goto": "conf_menu"}]}
				nodes["g_%s_3" % rid] = {"lines": [{"text_key": "{g_%s_comet}" % rid, "face": "happy", "pose": "nod"}],
					"choices": [{"text_key": "TY_CONF_ASK_OTHERS", "goto": "conf_menu"}]}
				if not tip.is_empty() and String(tip["rival"]) == rid:
					for nid in ["g_" + rid, "g_%s_2" % rid, "g_%s_3" % rid]:
						(nodes[nid]["choices"] as Array).push_front(tip_choice.duplicate())
			add.append({"text_key": "TY_CONF_ASK_TIP", "goto": "conf_tip", "if": {"has_hint": true}, "once": true})
			nodes["conf_tip"] = {"lines": [{"text_key": "TY_CONF_HOST_TIP", "face": "content", "pose": "point"}],
				"effects": [{"hint": true}], "choices": menu_id}
			# "anything else?": the host's own gossip one-liners (lenda_talk_strings.csv)
			var more: Array = []
			for k: String in HOST_MORE:
				if TranslationServer.translate(k) != k:
					more.append({"text_key": k, "face": "happy", "pose": "laugh"})
			if more.is_empty():
				more.append({"text_key": "TY_CONF_HOST_HI_2", "face": "happy", "pose": "nod"})
			nodes["conf_menu"] = {"lines": more, "choices": menu_id}
		_:
			add.append({"text_key": "TY_CONF_ASK_GOSSIP", "goto": "conf_gossip"})
			nodes["conf_gossip"] = {"lines": [{"text_key": "{conf_gossip}", "face": "happy", "pose": "talk"}],
				"choices": menu_id}
			if ConferenceTriennium.voice(id, role) != "":   # a mentor Lenda with a word on the agency's three years
				add.append({"text_key": "TY_CONF_ASK_US", "goto": "conf_you"})
				nodes["conf_you"] = {"lines": [{"text_key": "{conf_you}", "face": "content", "pose": "nod"}],
					"choices": [{"text_key": "TY_CONF_ASK_REP", "goto": "conf_you_rep"}]}
				nodes["conf_you_rep"] = {"lines": [{"text_key": "{conf_you_rep}", "face": "happy", "pose": "nod"}],
					"choices": menu_id}
	var at := menu.size()
	for i in menu.size():
		if bool((menu[i] as Dictionary).get("end", false)):
			at = i
			break
	for i in add.size():
		menu.insert(at + i, add[i])
	return tree
