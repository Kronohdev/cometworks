extends SceneTree
## Conquistas and Estatísticas (src/tycoon/achievements/achievements.gd, data/tycoon/achievements.json):
##   - the data: 30 to 40 achievements, unique ids, icons on disk, texts in both languages, every
##     condition reads a stat that exists
##   - unlocking from real state and events: a launch, a race milestone, photos (with progress),
##     "Simular até o fim", a first after the fair's tip, the emergency loan paid off, a flawless
##     decade, every Lenda hired; the campaign keeps its own notes, the profile its own (a file,
##     reloaded), the event tells first-time unlocks only once
##   - saves: the notes survive a save and load; a save from before loads with none
##   - campaign_stats: launches by era, monthly reputation / hype samples, money in and out
##   - the screens and the toast: the badge grid (locked greyed out, secret as "?"), the stats page,
##     the toast pops
## Run: godot --headless --path . --script res://tests/test_achievements.gd

var _failures := 0
var _profile := ""


func _initialize() -> void:
	_profile = OS.get_user_data_dir().path_join("test_achievements_profile.cfg")
	if FileAccess.file_exists(_profile):
		DirAccess.remove_absolute(_profile)
	Achievements.profile_path = _profile
	_data()
	_unlocks()
	_saves()
	_stats()
	await _screens()
	if FileAccess.file_exists(_profile):
		DirAccess.remove_absolute(_profile)
	Achievements.profile_path = ""
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL  " + what)
	else:
		print("  ok    " + what)


# ------------------------------------------------------------ data
func _data() -> void:
	print("data")
	var list := Achievements.all()
	_check(list.size() >= 30 and list.size() <= 40, "30 to 40 achievements (%d)" % list.size())
	var s := TycoonState.new_campaign(11)
	var st := Achievements.stats(s)
	var ids := {}
	var bad: PackedStringArray = []
	for a: Dictionary in list:
		var id := String(a.get("id", ""))
		if id == "" or ids.has(id):
			bad.append("id " + id)
		ids[id] = true
		if not ResourceLoader.exists(Achievements.ICONS % String(a.get("icon", ""))):
			bad.append("icon " + id)
		for k in ["name_key", "desc_key"]:
			for loc in ["en", "pt"]:
				TranslationServer.set_locale(loc)
				if tr(String(a.get(k, ""))) == String(a.get(k, "")):
					bad.append("%s %s %s" % [k, loc, id])
		var w: Dictionary = a.get("when", {})
		if w.has("stat") and not st.has(String(w["stat"])):
			bad.append("stat " + id)
		if w.get("min") is String and not st.has(String(w["min"])):
			bad.append("min " + id)
		if w.has("milestone"):
			for m in (w["milestone"] if w["milestone"] is Array else [w["milestone"]]):
				if s.race.milestone(String(m)).is_empty():
					bad.append("milestone " + id)
	TranslationServer.set_locale("pt")
	_check(bad.is_empty(), "ids, icons, texts and conditions are sound %s" % str(bad))
	var flags := 0
	for a: Dictionary in list:
		if bool(a.get("secret", false)) or bool(a.get("hidden", false)):
			flags += 1
	_check(flags >= 3, "some are hidden or secret (%d)" % flags)


# ------------------------------------------------------------ unlocks
func _launch(s: TycoonState, ok := true, outcome := "full", extra := {}) -> void:
	var e := {"id": "p%d" % s.project_history.size(), "code": "T-%02d" % s.project_history.size(), "type": "sounding",
		"target": "suborbital", "week": s.weeks, "success": ok, "outcome": outcome if ok else "fail", "cml": 3}
	e.merge(extra, true)
	s.project_history.append(e)
	s.changed.emit()


func _unlocks() -> void:
	print("unlocks")
	Achievements.reset_profile()
	var events: Array = []
	var on_unlock := func(id: String, first: bool) -> void: events.append([id, first])
	Achievements.events.unlocked.connect(on_unlock)
	var s := TycoonState.new_campaign(21)
	s.changed.emit()
	_check(not Achievements.is_unlocked("first_launch"), "a new campaign has not launched yet")
	_launch(s)
	_check(Achievements.campaign_unlocked(s).has("first_launch") and Achievements.is_unlocked("first_launch"),
		"the first launch unlocks 'first_launch' in the campaign and the profile")
	_check(events.any(func(e: Array) -> bool: return e[0] == "first_launch" and e[1]), "the unlock event says it is a first time")
	var rec := Achievements.profile_record("first_launch")
	_check(int(rec.get("t", 0)) > 0 and String(rec.get("agency", "")) == s.agency_name and int(rec.get("year", 0)) == 1,
		"the profile keeps when, the agency and the campaign year (%s)" % rec)
	# the profile is a file, read again from disk
	_check(FileAccess.file_exists(_profile), "the profile is written to its file")
	var cfg := ConfigFile.new()
	cfg.load(_profile)
	_check(cfg.has_section_key(Achievements.SECTION, "first_launch"), "the file holds the unlock")
	# a race milestone
	s.race.claim("first_satellite", RaceDirector.PLAYER)
	_check(Achievements.campaign_unlocked(s).has("first_orbit"), "the first satellite milestone unlocks 'first_orbit'")
	_check(not Achievements.campaign_unlocked(s).has("moon_landing"), "the Moon landing is still locked")
	s.race.claim("robotic_landing", RaceDirector.PLAYER)
	_check(Achievements.campaign_unlocked(s).has("moon_landing"), "a robotic landing unlocks 'moon_landing' (any of two milestones)")
	# progress: photos
	for k in 7:
		s.photos.append({"id": "ph%d" % k, "week": s.weeks})
	s.changed.emit()
	var pg := Achievements.progress(Achievements.find("photos_10"), Achievements.stats(s))
	_check(pg == [7.0, 10.0] and not Achievements.campaign_unlocked(s).has("photos_10"), "7 photos: 'photos_10' at 7 / 10 (%s)" % str(pg))
	_check(is_equal_approx(Achievements.profile_best("photos_10"), 7.0), "the profile keeps the best progress")
	for k in 3:
		s.photos.append({"id": "pq%d" % k, "week": s.weeks})
	s.changed.emit()
	_check(Achievements.campaign_unlocked(s).has("photos_10"), "10 photos unlock 'photos_10'")
	# events no state remembers
	Achievements.note(s, "sim_to_end")
	_check(Achievements.campaign_unlocked(s).has("sim_to_end"), "'Simular até o fim' unlocks 'sim_to_end'")
	# a first after the fair's tip
	s.conference["tip"] = {"year": s.year(), "count": 1, "rival": String(s.rivals[0]["id"]), "briefing": "x",
		"milestone": "cometling_space", "expires_week": s.weeks + 20}
	s.race.claim("cometling_space", RaceDirector.PLAYER)
	_check(Achievements.campaign_unlocked(s).has("tip_payoff"), "a first on the tipped milestone unlocks 'tip_payoff'")
	# a rival first on a tipped milestone does not count
	var t := TycoonState.new_campaign(22)
	t.conference["tip"] = {"year": 1, "milestone": "suborbital"}
	t.race.claim("suborbital", String(t.rivals[0]["id"]))
	t.race.claim("suborbital", RaceDirector.PLAYER)
	_check(not Achievements.campaign_unlocked(t).has("tip_payoff"), "second behind the rival is no tip payoff")
	# the emergency loan paid off
	var bk := Bankruptcy.bk(s)
	bk["used"] = true
	bk["loan"] = {"principal": 1.0, "payment": 1.0, "months_left": 2}
	s.changed.emit()
	_check(not Achievements.campaign_unlocked(s).has("survived_bankruptcy"), "the loan still open: not survived yet")
	bk["loan"] = {}
	s.changed.emit()
	_check(Achievements.campaign_unlocked(s).has("survived_bankruptcy"), "the loan paid off unlocks 'survived_bankruptcy'")
	# CML 6, a flawless decade, every Lenda
	_launch(s, true, "exceptional", {"cml": 6})
	_check(Achievements.campaign_unlocked(s).has("cml6") and Achievements.campaign_unlocked(s).has("exceptional"),
		"a CML 6 exceptional launch unlocks 'cml6' and 'exceptional'")
	s.weeks = 11 * s.weeks_per_year()
	s.changed.emit()
	_check(Achievements.campaign_unlocked(s).has("flawless_decade"), "ten whole years without a failure unlock 'flawless_decade' (%d)"
		% int(Achievements.stats(s)["flawless_years"]))
	var u := TycoonState.new_campaign(23)
	_launch(u)
	u.weeks = 5 * u.weeks_per_year()
	_launch(u, false)
	u.weeks = 12 * u.weeks_per_year()
	u.changed.emit()
	_check(int(Achievements.stats(u)["flawless_years"]) == 6, "a failure in year 6 breaks the run (%d)" % int(Achievements.stats(u)["flawless_years"]))
	var lg := TycoonLegends.st(s)
	for l in TycoonLegends.of_kind("hire"):
		(lg["hired"] as Dictionary)[String(l["id"])] = "x"
	s.changed.emit()
	_check(Achievements.campaign_unlocked(s).has("all_legends") and Achievements.campaign_unlocked(s).has("first_legend"),
		"every Lenda hired unlocks 'all_legends'")
	# phoenix: a success right after three failures
	var v := TycoonState.new_campaign(24)
	for k in 3:
		_launch(v, false)
	_check(not Achievements.campaign_unlocked(v).has("phoenix") and Achievements.campaign_unlocked(v).has("first_failure"),
		"three failures: 'first_failure' but no phoenix yet")
	_launch(v)
	_check(Achievements.campaign_unlocked(v).has("phoenix"), "the success after them unlocks 'phoenix'")
	# a second campaign earns it again for itself, but the profile's first time was before
	events.clear()
	var w := TycoonState.new_campaign(25)
	_launch(w)
	_check(Achievements.campaign_unlocked(w).has("first_launch"), "another campaign notes 'first_launch' for itself")
	_check(events.any(func(e: Array) -> bool: return e[0] == "first_launch" and not e[1]), "...and it is not a first time for the profile")
	Achievements.events.unlocked.disconnect(on_unlock)


# ------------------------------------------------------------ saves
func _saves() -> void:
	print("saves")
	var s := TycoonState.new_campaign(31)
	_launch(s)
	Achievements.note(s, "sim_to_end")
	var d := TycoonSave.decode(JSON.parse_string(JSON.stringify(TycoonSave.encode(s.to_dict())))) as Dictionary
	var l := TycoonState.from_dict(d)
	_check(Achievements.campaign_unlocked(l).has("first_launch") and Achievements.flag(l, "sim_to_end") == 1,
		"the campaign's notes and flags survive a save and load")
	d.erase("achievements")
	var old := TycoonState.from_dict(d)
	_check(old.achievements is Dictionary and Achievements.campaign_unlocked(old).has("first_launch"),
		"a save from before loads and earns what its state already shows")


# ------------------------------------------------------------ the Estatísticas page
func _stats() -> void:
	print("stats")
	var s := TycoonState.new_campaign(41)
	_launch(s)
	_launch(s, true, "partial")
	_launch(s, false)
	s.weeks = 6 * s.weeks_per_year()
	_launch(s)
	for k in 3:   # salaries to pay
		s.staff.append(s.normalize_staff({"id": "t%d" % k, "name": "Teste", "role": "pilot"}, k))
	for i in 14:
		s.advance_week()
	var st := Achievements.campaign_stats(s)
	_check(int(st["launches"]) == 4 and int(st["full"]) == 2 and int(st["partials"]) == 1 and int(st["failures"]) == 1,
		"launches by outcome (%d / %d / %d / %d)" % [st["launches"], st["full"], st["partials"], st["failures"]])
	var eras: Array = st["by_era"]
	_check(eras.size() == 5 and int(eras[0]["launches"]) == 3 and is_equal_approx(float(eras[0]["rate"]), 2.0 / 3.0)
		and int(eras[1]["launches"]) == 1 and float(eras[2]["rate"]) < 0.0, "the success rate of each era")
	_check(float(st["dv_kms"]) > 0.0, "Δv flown adds up the targets reached (%.1f km/s)" % float(st["dv_kms"]))
	_check((st["samples"] as Array).size() >= 3, "a reputation / hype sample a month (%d)" % (st["samples"] as Array).size())
	_check(float(st["spent"]) > 0.0 and float(st["earned"]) >= 0.0, "money in and out (%.0f / %.0f)" % [st["earned"], st["spent"]])
	s.race.claim("suborbital", String(s.rivals[0]["id"]))
	s.race.claim("first_satellite", RaceDirector.PLAYER)
	st = Achievements.campaign_stats(s)
	_check(int(st["firsts_won"]) == 1 and int(st["firsts_lost"]) == 1, "firsts won and lost to the rivals")


# ------------------------------------------------------------ screens
func _screens() -> void:
	print("screens")
	TranslationServer.set_locale("pt")
	Achievements.reset_profile()
	Achievements.unlock(null, "first_launch")
	# the badge book from the main menu (no campaign)
	var scr := (load("res://scenes/tycoon/ui/screens/achievements.tscn") as PackedScene).instantiate() as AchievementsScreen
	root.add_child(scr)
	await process_frame
	await process_frame
	var grid := scr.get_node("%Grid")
	var cards: Array = grid.get_children().filter(func(c: Node) -> bool: return c.has_meta("from_template"))
	_check(cards.size() == Achievements.all().size(), "a badge for every achievement (%d)" % cards.size())
	var secret_ok := false
	var locked_grey := false
	var got_colour := false
	for c: Control in cards:
		var a := Achievements.find(String(c.get_meta("id")))
		if bool(a.get("secret", false)):
			secret_ok = (c.get_node("VBox/Medal/Secret") as Control).visible and (c.get_node("VBox/Name") as Label).text == tr("ACH_SECRET_NAME")
		if String(a["id"]) == "first_orbit":
			locked_grey = (c.get_node("VBox/Medal/Icon") as Control).modulate.a < 0.9
		if String(a["id"]) == "first_launch":
			got_colour = is_equal_approx((c.get_node("VBox/Medal/Icon") as Control).modulate.a, 1.0)
	_check(secret_ok, "a locked secret badge shows as '?'")
	_check(locked_grey and got_colour, "locked badges are greyed out, earned ones in colour")
	_check(not (scr.get_node("%Stats") as Control).visible, "no Estatísticas key without a campaign")
	_check(scr.get_node("%Count").text == "1 / %d" % Achievements.all().size(), "the count (%s)" % scr.get_node("%Count").text)
	scr.open_with({"id": "photos_10"})
	_check(scr.get_node("%DName").text == tr("ACH_PHOTOS_10"), "the detail tells the chosen badge")
	scr.queue_free()
	# the stats page on a campaign
	var s := TycoonState.new_campaign(51)
	_launch(s)
	var stp := (load("res://scenes/tycoon/ui/screens/stats.tscn") as PackedScene).instantiate() as StatsScreen
	root.add_child(stp)
	stp.bind(s, null, null)
	await process_frame
	_check(stp.get_node("%LaunchesN").text == "1", "the stats page shows the launches")
	var eras: Array = stp.get_node("%EraTemplate").get_parent().get_children().filter(func(c: Node) -> bool: return c.has_meta("from_template"))
	_check(eras.size() == 5, "a row for each era")
	stp.queue_free()
	# the toast
	var toast := (load("res://scenes/tycoon/ui/achievement_toast.tscn") as PackedScene).instantiate() as AchievementToast
	root.add_child(toast)
	await process_frame
	Achievements.unlock(null, "first_orbit")
	await process_frame
	await process_frame
	_check(toast.is_showing() and (toast.get_node("%Card") as Control).visible and toast.get_node("%Name").text == tr("ACH_FIRST_ORBIT"),
		"a first-time unlock pops the toast")
	toast.queue_free()
	await process_frame
