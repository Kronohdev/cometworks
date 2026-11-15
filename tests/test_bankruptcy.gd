extends SceneTree
## Bankruptcy (src/tycoon/finance/bankruptcy.gd) and its screens:
##   rules     the line −X by difficulty and era; the warning once per descent (news, signal,
##             Vovô's lesson trigger); the first month past the line gives the one emergency
##             loan (covers the debt plus a cushion, instalments, deadline); past the line again
##             or the loan's default (months in a row in the red) ends the campaign, which then
##             stops; a loan paid off clears; the weekly driver (TycoonAgency) runs it
##   saves     the emergency loan and the bankruptcy survive save / load (JSON); an old save
##             (no "bk") starts with the loan unused
##   records   the final record is appended to the records file
##   scene     on the main screen: the HUD caption warns, the loan screen opens once, the game
##             over opens (and comes back when closed), both fit the view
## Run: godot --headless --path . --script res://tests/test_bankruptcy.gd

const RECORDS := "user://test_bankruptcy_records.json"

var _fails := 0
var _checks := 0


func _initialize() -> void:
	CwMotion.set_reduced(true)
	_check(load("res://src/tycoon/finance/bankruptcy.gd") != null and Bankruptcy.db().has("months"),
		"the bankruptcy rules and their data are loaded")
	_lines()
	_warnings()
	_loan_then_line()
	_default()
	_paid_off()
	_weekly_driver()
	_saves()
	_records()
	await _scene()
	print("%d checks" % _checks)
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _state(diff := "normal") -> TycoonState:
	var s := TycoonState.new_campaign(11, [{"name": "R", "profession": "researcher", "skill": 0.6}], diff)
	return s


# ------------------------------------------------------------ rules
func _lines() -> void:
	print("the line")
	var e := Bankruptcy.threshold(_state("easy"))
	var n := Bankruptcy.threshold(_state("normal"))
	var h := Bankruptcy.threshold(_state("hard"))
	_check(e > n and n > h, "the line is deeper on Fácil and shallower on Difícil (%d / %d / %d)" % [e, n, h])
	for l: Dictionary in TycoonDifficulty.levels():
		_check(float(l.get("bankrupt_line", 0.0)) > 0.0, "difficulty %s has its bankrupt_line" % l["id"])
	var s := _state()
	var x1 := Bankruptcy.threshold(s)
	s.weeks = 3 * 5 * 52
	_check(Bankruptcy.threshold(s) > x1 * 2.0, "the line grows with the eras (era 4: %d)" % Bankruptcy.threshold(s))
	s.weeks = 0
	s.cash = 10.0
	_check(Bankruptcy.danger_level(s) == Bankruptcy.SAFE, "positive cash is safe")
	s.cash = -10.0
	_check(Bankruptcy.danger_level(s) == Bankruptcy.RED, "a little red is only red")
	s.cash = Bankruptcy.warn_line(s) - 1.0
	_check(Bankruptcy.danger_level(s) == Bankruptcy.DANGER, "past the warning line is danger")
	s.cash = -x1 - 1.0
	_check(Bankruptcy.danger_level(s) == Bankruptcy.PAST, "past the line")


func _warnings() -> void:
	print("warnings")
	var s := _state()
	var got := [0]
	s.cash_warning.connect(func(l: int) -> void: got[0] += 1 if l == Bankruptcy.DANGER else 0)
	s.cash = -1000.0
	Bankruptcy.weekly(s)
	_check(got[0] == 0, "no warning in a shallow red")
	s.cash = Bankruptcy.warn_line(s) - 1000.0
	Bankruptcy.weekly(s)
	_check(got[0] == 1 and String(s.news[0]["key"]) == "BK_NEWS_WARN", "past the warning line: the Tail Radio warns and the signal fires")
	Bankruptcy.weekly(s)
	_check(got[0] == 1, "...only once while it stays down there")
	s.cash = 5000.0
	Bankruptcy.weekly(s)
	s.cash = Bankruptcy.warn_line(s) - 1000.0
	Bankruptcy.weekly(s)
	_check(got[0] == 2, "back in the black, the warning can come again")
	_check(not TutorialBook.triggered_by("signal", "cash_warning").is_empty(), "Vovô Halleyzinho has a lesson on the warning")


func _loan_then_line() -> void:
	print("the emergency loan, then the line again")
	var s := _state()
	var info := [{}]
	s.emergency_loan.connect(func(i: Dictionary) -> void: info[0] = i)
	var x := Bankruptcy.threshold(s)
	s.cash = -x - 50000.0
	Bankruptcy.month_end(s)
	_check(Bankruptcy.emergency_used(s) and Bankruptcy.has_emergency_loan(s), "the first month past the line gives the emergency loan")
	_check(not (info[0] as Dictionary).is_empty() and String(s.news[0]["key"]) == "BK_NEWS_LOAN", "...with its signal and its news")
	var cushion := float(Bankruptcy.db().get("cushion", 0.4)) * x
	_check(absf(s.cash - cushion) < 1.0, "it covers the debt and leaves a cushion (%d)" % s.cash)
	var l := Bankruptcy.loan_info(s)
	_check(float(l["payment"]) * int(l["months"]) > float(l["principal"]) and int(l["deadline_week"]) > s.weeks,
		"instalments with interest and a deadline (%d x %d)" % [l["payment"], l["months"]])
	_check(bool(Bankruptcy.bk(s)["show_loan"]), "the loan screen is due")
	_check(not Bankruptcy.is_bankrupt(s), "not bankrupt yet")
	var c0 := s.cash
	Bankruptcy.month_end(s)
	_check(absf(c0 - s.cash - float(l["payment"])) < 1.0, "a month later the instalment is paid")
	var over := [{}]
	s.bankrupt.connect(func(i: Dictionary) -> void: over[0] = i)
	s.cash = -x - 1.0
	Bankruptcy.month_end(s)
	_check(Bankruptcy.is_bankrupt(s) and String(Bankruptcy.bankrupt_info(s)["reason"]) == "line",
		"past the line a second time: bankrupt")
	_check(not (over[0] as Dictionary).is_empty() and String(s.news[0]["key"]) == "BK_NEWS_BANKRUPT", "...with its signal and its news")
	var w := s.weeks
	s.advance_week()
	_check(s.weeks == w, "a bankrupt campaign does not move on")


func _default() -> void:
	print("the loan's default")
	var s := _state()
	s.cash = -Bankruptcy.threshold(s) - 1.0
	Bankruptcy.month_end(s)
	var n := int(Bankruptcy.db().get("default_months", 6))
	for i in n:
		s.cash = -1000.0
		Bankruptcy.month_end(s)
	_check(not Bankruptcy.is_bankrupt(s), "a shallow red while repaying is all right (%d months)" % n)
	for i in n - 1:
		s.cash = Bankruptcy.warn_line(s) - 1000.0
		Bankruptcy.month_end(s)
	_check(not Bankruptcy.is_bankrupt(s), "%d months past the warning line is still all right" % (n - 1))
	s.cash = 1000.0
	Bankruptcy.month_end(s)
	for i in n - 1:
		s.cash = Bankruptcy.warn_line(s) - 1000.0
		Bankruptcy.month_end(s)
	_check(not Bankruptcy.is_bankrupt(s), "a month back above it starts the count again")
	s.cash = Bankruptcy.warn_line(s) - 1000.0
	Bankruptcy.month_end(s)
	_check(Bankruptcy.is_bankrupt(s) and String(Bankruptcy.bankrupt_info(s)["reason"]) == "default",
		"%d month-ends in a row past the warning line before paying: default, bankrupt" % n)


func _paid_off() -> void:
	print("paid off")
	var s := _state()
	s.cash = -Bankruptcy.threshold(s) - 1.0
	Bankruptcy.month_end(s)
	var months := int(Bankruptcy.loan_info(s)["months"])
	for i in months:
		s.cash += 200000.0
		Bankruptcy.month_end(s)
	_check(not Bankruptcy.has_emergency_loan(s) and not Bankruptcy.is_bankrupt(s), "after %d instalments the loan is paid off" % months)
	s.cash = -Bankruptcy.threshold(s) - 1.0
	Bankruptcy.month_end(s)
	_check(Bankruptcy.is_bankrupt(s), "the emergency loan is once per career: past the line again is the end")


func _weekly_driver() -> void:
	print("the weekly driver")
	var s := _state()
	s.cash = -Bankruptcy.threshold(s) * 1.3
	for i in 6:
		s.advance_week()
	_check(Bankruptcy.emergency_used(s), "advancing the weeks, a month end past the line grants the loan (TycoonAgency)")
	_check(s.cash > -Bankruptcy.threshold(s), "...and the cash is back above the line (%d)" % s.cash)


# ------------------------------------------------------------ saves
func _roundtrip(s: TycoonState) -> TycoonState:
	var txt := JSON.stringify(TycoonSave.encode(s.to_dict()))
	return TycoonSave.state_from(TycoonSave.decode(JSON.parse_string(txt)))


func _saves() -> void:
	print("saves")
	var s := _state()
	s.cash = -Bankruptcy.threshold(s) - 1.0
	Bankruptcy.month_end(s)
	var t := _roundtrip(s)
	_check(Bankruptcy.emergency_used(t) and Bankruptcy.has_emergency_loan(t), "the emergency loan survives save / load")
	_check(int(Bankruptcy.loan_info(t)["months_left"]) == int(Bankruptcy.loan_info(s)["months_left"]), "...with its instalments left")
	t.cash = -Bankruptcy.threshold(t) - 1.0
	Bankruptcy.month_end(t)
	_check(Bankruptcy.is_bankrupt(t), "a loaded campaign that used it goes bankrupt past the line")
	var u := _roundtrip(t)
	_check(Bankruptcy.is_bankrupt(u), "a bankrupt campaign stays bankrupt when loaded")
	# an old save: no "bk" in its finance
	var d := _state().to_dict()
	(d["finance"] as Dictionary).erase("bk")
	var old := TycoonState.from_dict(d)
	_check(not Bankruptcy.emergency_used(old) and not Bankruptcy.is_bankrupt(old), "an old save starts with no emergency loan used")
	old.cash = -Bankruptcy.threshold(old) - 1.0
	Bankruptcy.month_end(old)
	_check(Bankruptcy.emergency_used(old) and not Bankruptcy.is_bankrupt(old), "...and gets its one emergency loan")


func _records() -> void:
	print("records")
	if FileAccess.file_exists(RECORDS):
		DirAccess.remove_absolute(RECORDS)
	var s := _state()
	s.cash = -Bankruptcy.threshold(s) - 1.0
	Bankruptcy.month_end(s)
	s.cash = -Bankruptcy.threshold(s) - 1.0
	Bankruptcy.month_end(s)
	var e := Bankruptcy.save_record(s, RECORDS)
	Bankruptcy.save_record(s, RECORDS)
	var all := Bankruptcy.records(RECORDS)
	_check(all.size() == 2 and String(all[0]["end"]) == "bankrupt" and String(all[0]["reason"]) == "line"
		and String(all[0]["difficulty"]) == "normal", "the final record is saved (%s)" % str(e))
	DirAccess.remove_absolute(RECORDS)


# ------------------------------------------------------------ on the main screen
func _scene() -> void:
	print("scene")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(3)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	main.bankruptcy_flow.save_records = false
	var s := main.state
	var hud := main.hud
	var cap := (hud.get_node("%CashValue") as Control).get_parent().get_node("Caption") as Label
	s.cash = Bankruptcy.warn_line(s) - 1000.0
	s.changed.emit()
	await _frames(2)
	_check(cap.text == tr("BK_HUD_DANGER"), "the HUD's cash caption warns near the line (%s)" % cap.text)
	_check(((hud.get_node("%CashValue") as Control).get_parent().get_parent() as Control).tooltip_text != "",
		"...and its tooltip tells where the line is")
	s.cash = 1000.0
	s.changed.emit()
	await _frames(2)
	_check(cap.text == "TY_CASH" or cap.text == tr("TY_CASH"), "back in the black the caption is the cash again")
	# the loan screen
	s.cash = -Bankruptcy.threshold(s) * 1.2
	for i in 6:
		s.advance_week()
	await _frames(4)
	_check(hud.current_screen() == "emergency_loan", "the emergency loan's screen opens (%s)" % hud.current_screen())
	_check(main.clock.speed == 0, "...and holds the clock")
	var scr := hud.get_node("%Screens").get_child(0)
	_check(scr.get_node("%Amount").text == CwScreen.cr(float(Bankruptcy.loan_info(s)["principal"])), "it shows the loan's amount")
	await _fits(scr, "loan")
	hud.close_screen()
	await _frames(3)
	_check(hud.current_screen() == "", "the loan screen shows once")
	# the game over
	s.cash = -Bankruptcy.threshold(s) * 1.5
	for i in 6:
		s.advance_week()
	await _frames(4)
	_check(Bankruptcy.is_bankrupt(s) and hud.current_screen() == "bankrupt", "past the line again: the game over (%s)" % hud.current_screen())
	scr = hud.get_node("%Screens").get_child(0)
	_check(scr.get_node("%HalleyLine").text.begins_with(tr("BK_OVER_HALLEY_1").substr(0, 3)) or scr.get_node("%HalleyLine").text != "",
		"Vovô Halleyzinho consoles the player")
	_check(scr.get_node("%Reason").text != "" and scr.get_node("%Score").text != "", "what happened and the score")
	await _fits(scr, "game over")
	hud.close_screen()
	await _frames(4)
	_check(hud.current_screen() == "bankrupt", "closing it brings the game over back")
	main.queue_free()
	await _frames(2)


func _fits(scr: Node, tag: String) -> void:
	var fit := preload("res://tests/test_ui_fit.gd")
	for loc in ["pt_BR", "en"]:
		TranslationServer.set_locale(loc)
		for sz in [Vector2i(1600, 900), Vector2i(2133, 900), Vector2i(1600, 1200)]:
			get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
			get_root().content_scale_size = sz
			if scr.has_method("refresh"):
				scr.call("refresh")
			await create_timer(0.35).timeout
			var bad: Array = []
			for c in fit._visible_controls(scr):
				var r: Rect2 = fit._clipped_rect(c)
				if r.size.x > 0.5 and r.size.y > 0.5 and not Rect2(Vector2.ZERO, Vector2(sz)).grow(4.0).encloses(r):
					bad.append("%s %s" % [scr.get_path_to(c), r])
			_check(bad.is_empty(), "%s fits %dx%d (%s) %s" % [tag, sz.x, sz.y, loc, str(bad.slice(0, 3))])
	TranslationServer.set_locale("pt_BR")
	get_root().content_scale_size = Vector2i(1600, 900)
