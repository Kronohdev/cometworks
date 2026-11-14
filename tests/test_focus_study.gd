extends SceneTree
## Headless checks for the mission studies (FocusStudy, src/tycoon/project/focus_study.gd):
## the tiers reveal the right bars (tier 1 the most / least important, tier 2 the levels and the
## lever arrows, tier 3 the exact ideal of MissionFit / MissionProject), a study draws PP from
## the lab's pool before the tech and costs money once, flying teaches tier 1 and the journal's
## reveal is tier 3, the screens' marks follow, and it all survives save -> load.
## Run: godot --headless --path . --script res://tests/test_focus_study.gd

var _failures := 0


func _initialize() -> void:
	_test_tiers_reveal_bars()
	_test_study_runs_in_lab()
	_test_flights_and_journal()
	_test_save_load()
	_test_all_types_sane()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


static func _team() -> Array[Dictionary]:
	return [
		{"id": "a", "name": "Ada", "profession": "systems_engineer", "skill": 0.6, "morale": 80.0, "level": 1},
		{"id": "b", "name": "Bel", "profession": "scientist", "skill": 0.5, "morale": 70.0, "level": 2},
		{"id": "c", "name": "Cid", "profession": "test_technician", "skill": 0.5, "morale": 70.0, "level": 1},
		{"id": "r", "name": "Rui", "profession": "researcher", "skill": 0.8, "morale": 80.0, "level": 2}]


static func _state(p_seed := 5) -> TycoonState:
	var s := TycoonState.new_campaign(p_seed, _team())
	TycoonResearch.complete(s, TycoonResearch.tech_for_type("demo_sat"))
	TycoonResearch.complete(s, TycoonResearch.tech_for_target("leo"))
	return s


func _test_tiers_reveal_bars() -> void:
	print("tiers reveal the right bars")
	var s := _state()
	var ty := "demo_sat"  # ratio [0.40, 0.10, 0.25, 0.25]
	_check(FocusStudy.tier(s, ty) == 0, "nothing known at the start")
	for m in FocusStudy.bar_marks(s, ty):
		_check(m["mark"] == "" and float(m["ideal"]) < 0.0, "tier 0: bar %d unknown" % int(m["bar"]))
	_check(FocusStudy.best_split(s, ty, 0).is_empty() and FocusStudy.focus_lever(s, ty, 0) == -1, "tier 0: no lever advice")
	FocusStudy.complete_tier(s, ty)
	_check(FocusStudy.tier(s, ty) == 1, "tier 1 after one study")
	var marks := FocusStudy.bar_marks(s, ty)
	_check(marks[ProjectRules.ENG]["mark"] == "top", "tier 1: Engineering matters most (%s)" % marks[0]["mark"])
	_check(marks[ProjectRules.SCI]["mark"] == "bottom", "tier 1: Science matters least")
	_check(marks[ProjectRules.OPS]["mark"] == "" and marks[ProjectRules.REL]["mark"] == "", "tier 1: the others stay unknown")
	_check(not Discovery.ratio_known(s, ty), "tier 1 does not reveal the balance in the journal")
	# phase 1: architecture feeds Engineering most; phase 2: structure
	_check(FocusStudy.focus_lever(s, ty, 0) == 0 and FocusStudy.focus_lever(s, ty, 1) == 0, "tier 1: the lever to focus on in each phase")
	FocusStudy.complete_tier(s, ty)
	marks = FocusStudy.bar_marks(s, ty)
	_check(marks[0]["mark"] == "high" and marks[1]["mark"] == "low" and marks[2]["mark"] == "mid" and marks[3]["mark"] == "mid",
		"tier 2: levels high / low / mid / mid (%s %s %s %s)" % [marks[0]["mark"], marks[1]["mark"], marks[2]["mark"], marks[3]["mark"]])
	for k in 3:
		var arrows := FocusStudy.lever_arrows(s, ty, k)
		_check(arrows.size() == 3, "tier 2: three lever arrows in phase %d (%s)" % [k + 1, arrows])
	_check(FocusStudy.lever_arrows(s, ty, 0)[1] == -1, "tier 2: phase 1 wants less science payload time")
	_check(FocusStudy.lever_arrows(s, ty, 0)[0] == 1, "tier 2: phase 1 wants more architecture time")
	_check(float(marks[0]["ideal"]) < 0.0, "tier 2: still no exact marker")
	FocusStudy.complete_tier(s, ty)
	_check(FocusStudy.tier(s, ty) == 3 and Discovery.ratio_known(s, ty), "tier 3 reveals the balance in the journal too")
	marks = FocusStudy.bar_marks(s, ty)
	var p := MissionProject.new()
	p.type_id = ty
	var idl := p.ideal(s)
	var ctx := MissionFit.ctx_of(s, p)
	for b in 4:
		_check(is_equal_approx(float(marks[b]["ideal"]), idl[b]) and is_equal_approx(float(marks[b]["ideal"]), float(ctx["ideal"][b])),
			"tier 3: bar %d marker %.2f = the project / MissionFit ideal %.2f" % [b, float(marks[b]["ideal"]), idl[b]])
	var best := FocusStudy.best_split(s, ty, 1)
	var ranges := Discovery.lever_ranges(idl)
	_check(best == [int(ranges[1][0][2]), int(ranges[1][1][2]), int(ranges[1][2][2])], "tier 3: the best split is the journal's (%s)" % [best])
	FocusStudy.complete_tier(s, ty)
	_check(FocusStudy.tier(s, ty) == 3, "no tier past 3")
	_check(Discovery.notes(s).size() >= 3 and String(Discovery.notes(s)[0]["key"]) == "TY_JN_NOTE_STUDY_3", "the journal writes each tier down")


func _test_study_runs_in_lab() -> void:
	print("a study runs in the lab")
	var s := _state()
	var ty := "sounding"
	var c1 := FocusStudy.cost(s, ty, 1)
	_check(float(c1["pp"]) > 0.0 and float(c1["cash"]) > 0.0 and int(c1["weeks"]) >= 1, "tier 1 has a cost (%s)" % c1)
	_check(float(FocusStudy.cost(s, "telescope", 1)["pp"]) > float(c1["pp"]), "later-era types cost more to study")
	var cash0 := s.cash
	_check(FocusStudy.start(s, ty), "the study starts")
	_check(is_equal_approx(s.cash, cash0 - float(c1["cash"])), "its money is paid at the start")
	_check(FocusStudy.active(s) == ty, "it is the active study")
	FocusStudy.stop(s)
	FocusStudy.start(s, ty)
	_check(is_equal_approx(s.cash, cash0 - float(c1["cash"])), "resuming does not pay twice")
	# a tech funded at the same time: the study draws first
	var tech := "lab_methods"
	TycoonResearch.fund(s, tech)
	var ppw := TycoonResearch.pp_per_week(s)
	_check(ppw > 0.0, "the researcher makes PP (%.1f / week)" % ppw)
	var weeks := 0
	while FocusStudy.tier(s, ty) < 1 and weeks < 60:
		s.advance_week()
		weeks += 1
	_check(FocusStudy.tier(s, ty) == 1, "tier 1 learned in %d weeks" % weeks)
	_check(weeks >= int(c1["weeks"]), "it takes at least its weeks (%d >= %d)" % [weeks, int(c1["weeks"])])
	_check(FocusStudy.active(s) == "", "the study stops at its tier")
	_check(TycoonResearch.progress(s, tech) < float(TycoonResearch.tech(tech)["cost"]), "the tech shared the pool (not done yet)")
	_check(FocusStudy.weeks_left(s, ty) > 0, "the next tier has an ETA")
	# a poorer lab is slower: no researcher, only scientists
	var s2 := TycoonState.new_campaign(5, _team().slice(0, 3))
	FocusStudy.start(s2, ty)
	var w2 := 0
	while FocusStudy.tier(s2, ty) < 1 and w2 < 200:
		s2.advance_week()
		w2 += 1
	_check(w2 > weeks, "without a researcher it takes longer (%d > %d weeks)" % [w2, weeks])
	# no money, no study
	var s3 := _state()
	s3.cash = 10.0
	_check(FocusStudy.start_error(s3, ty) == "TY_ST_ERR_CASH" and not FocusStudy.start(s3, ty), "no money: it cannot start")
	_check(FocusStudy.start_error(s3, "comet_mission") == "TY_ST_ERR_LOCKED", "a type the agency cannot fly cannot be studied")


func _test_flights_and_journal() -> void:
	print("flying teaches too")
	var s := _state()
	(Discovery.d(s)["attempts"] as Dictionary)["sounding"] = 1
	_check(FocusStudy.tier(s, "sounding") == 1, "one launch gives tier 1")
	(Discovery.d(s)["attempts"] as Dictionary)["sounding"] = 2
	_check(FocusStudy.tier(s, "sounding") == 3, "two launches give tier 3 (the journal's reveal)")
	_check(FocusStudy.start_error(s, "sounding") == "TY_ST_ERR_KNOWN", "nothing left to study")
	TycoonResearch.complete(s, "lab_complex")
	_check(FocusStudy.tier(s, "orbiter") == 3, "a reveal tech (payload.json reveal_by_tech) gives tier 3")
	var s2 := _state()
	_check(FocusStudy.reveal_all(s2) > 0 and FocusStudy.tier(s2, "demo_sat") == 3, "dev: reveal every type the agency can fly")
	_check(FocusStudy.tier(s2, "comet_mission") == 0, "dev reveal keeps types the agency cannot fly")
	FocusStudy.reveal_all(s2, true)
	_check(FocusStudy.tier(s2, "comet_mission") == 3, "dev reveal with all types")
	# the journal writes the first flight's lesson down
	var s3 := _state()
	var p := MissionProject.new()
	p.type_id = "demo_sat"
	p.target_id = "leo"
	var added := Discovery.record(s3, p, {}, 5.0, true)
	var keys: Array = added.map(func(a: Dictionary) -> String: return String(a["key"]))
	_check("TY_JN_NOTE_FOCUS_FLIGHT" in keys and FocusStudy.tier(s3, "demo_sat") == 1, "the first flight's note: tier 1 (%s)" % [keys])
	added = Discovery.record(s3, p, {}, 5.0, true)
	keys = added.map(func(a: Dictionary) -> String: return String(a["key"]))
	_check("TY_JN_NOTE_RATIO" in keys and not "TY_JN_NOTE_FOCUS_FLIGHT" in keys, "the second flight reveals the balance (%s)" % [keys])


func _test_save_load() -> void:
	print("save / load")
	var s := _state()
	FocusStudy.complete_tier(s, "demo_sat")
	FocusStudy.complete_tier(s, "demo_sat")
	FocusStudy.start(s, "sounding")
	s.advance_week()
	var prog := FocusStudy.progress(s, "sounding")
	var l := TycoonState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check(FocusStudy.tier(l, "demo_sat") == 2, "the studied tier survives save -> load")
	_check(FocusStudy.active(l) == "sounding" and is_equal_approx(FocusStudy.progress(l, "sounding"), prog) and prog > 0.0,
		"the active study and its progress survive (%.2f)" % prog)
	_check(FocusStudy.paid(l, "sounding"), "its payment is remembered")
	var old := TycoonState.from_dict({})
	_check(FocusStudy.tier(old, "sounding") == 0 and FocusStudy.active(old) == "", "an old save without studies loads")


func _test_all_types_sane() -> void:
	print("every type")
	var s := _state()
	for t: Dictionary in s.mdata.get("types", []):
		var id := String(t["id"])
		_check(not FocusStudy.top_bars(s, id).is_empty() and not FocusStudy.bottom_bars(s, id).is_empty(), "%s: top and bottom bars" % id)
		var lv: Array[String] = []
		for b in 4:
			lv.append(FocusStudy.level(s, id, b))
		_check("high" in lv, "%s: at least one bar is high at tier 2 (%s)" % [id, lv])
		for k in 3:
			var fl := FocusStudy.focus_lever(s, id, k)
			(Discovery.d(s)["study"] as Dictionary)[id] = 1
			fl = FocusStudy.focus_lever(s, id, k)
			var feeds_top := false
			for row: Array in ProjectRules.feed_matrix(k):
				for b in FocusStudy.top_bars(s, id):
					feeds_top = feeds_top or float(row[b]) > 0.0
			_check((fl >= 0 and fl < 3) if feeds_top else fl == -1, "%s phase %d: a lever to focus on (%d)" % [id, k + 1, fl])
		(Discovery.d(s)["study"] as Dictionary).erase(id)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
