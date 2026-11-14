extends SceneTree
## Headless checks for the mission project loop (E1, src/tycoon/project/), the acceptance of
## GDD section 20: a sounding project goes from start to grade; changing the sliders changes
## the grade predictably; the formulas of GDD 6.5 / 6.6 are covered; same seed, same result.
## Run: godot --headless --path . --script res://tests/test_tycoon_project.gd

var _failures := 0


func _initialize() -> void:
	_test_formulas()
	_test_sounding_project()
	_test_sliders_change_grade()
	_test_determinism_and_save()
	_test_expectation_rises()
	_test_orbital_launch()
	_test_contract_and_errors()
	await _test_outcome_grade()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


static func _team() -> Array[Dictionary]:
	return [
		{"id": "a", "name": "Ada", "profession": "systems_engineer", "skill": 0.6, "morale": 80.0, "level": 1},
		{"id": "b", "name": "Bel", "profession": "scientist", "skill": 0.5, "morale": 70.0, "level": 2},
		{"id": "c", "name": "Cid", "profession": "test_technician", "skill": 0.5, "morale": 70.0, "level": 1},
		{"id": "d", "name": "Duo", "profession": "flight_controller", "skill": 0.4, "morale": 60.0, "level": 1},
		{"id": "e", "name": "Eva", "profession": "pilot", "skill": 0.5, "morale": 20.0, "level": 1}]


static func _state(p_seed := 11) -> TycoonState:
	var s := TycoonState.new_campaign(p_seed, _team())
	# the research tree gates everything past the sounding rocket: open the era 1 orbit
	TycoonResearch.complete(s, TycoonResearch.tech_for_type("demo_sat"))
	TycoonResearch.complete(s, TycoonResearch.tech_for_target("leo"))
	return s


## Runs a sounding project to the end with the given sliders for each phase.
static func _run_sounding(s: TycoonState, phase_sliders: Array, staff_ids: Array = ["a", "b", "c", "d"]) -> Dictionary:
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", staff_ids)
	if p == null:
		return {}
	var id := p.id
	ProjectDesk.set_sliders(s, id, phase_sliders[0])
	var guard := 0
	while ProjectDesk.find(s, id) != null and guard < 20:
		s.advance_week()
		var q := ProjectDesk.find(s, id)
		if q and q.awaiting_sliders:
			ProjectDesk.set_sliders(s, id, phase_sliders[q.phase])
		guard += 1
	return ProjectDesk.history_entry(s, id)


# ------------------------------------------------------------ formulas
func _test_formulas() -> void:
	print("formulas")
	var s := _state()
	var eng: Dictionary = s.staff[0]  # systems engineer, skill 0.6, morale 80, level 1
	# phase 1 (concept), 100% architecture: focus eng 0.8, rel 0.2
	var mp := MissionProject.member_points(s, eng, 0, [100, 0, 0])
	var base := 10.0 * (0.4 + 0.6 * 0.6) * (0.6 + 0.4 * 0.8) * (1.0 + 0.08 * 1)
	_check(absf(mp[0] - base * 1.0 * 0.8) < 1e-4, "points: eng = 10*(0.4+0.6 skill)*(0.6+0.4 morale)*(1+0.08 lv)*aff 1.0*focus 0.8 (%.3f)" % mp[0])
	_check(absf(mp[3] - base * 0.4 * 0.2) < 1e-4, "points: rel uses the secondary affinity 0.4 * focus 0.2 (%.3f)" % mp[3])
	_check(mp[1] == 0.0 and mp[2] == 0.0, "points: bars with no focus get nothing")
	var mp2 := MissionProject.member_points(s, eng, 0, [0, 100, 0])
	_check(absf(mp2[1] - base * 0.15) < 1e-4, "points: other bars use affinity 0.15 (%.3f)" % mp2[1])
	_check(MissionProject.member_points(s, s.staff[4], 0, [34, 33, 33]) == [0.0, 0.0, 0.0, 0.0],
		"points: a Cometling below 30 morale naps")
	var f := ProjectRules.focus(1, [0.5, 0.25, 0.25])
	_check(absf(f[0] - 0.55) < 1e-6 and absf(f[1] - 0.2) < 1e-6 and absf(f[3] - 0.25) < 1e-6,
		"focus: build phase 50/25/25 -> eng 0.55, sci 0.2, rel 0.25")
	_check(absf(MissionProject.ratio_match([0.4, 0.2, 0.15, 0.25], [0.4, 0.2, 0.15, 0.25]) - 1.0) < 1e-6,
		"ratio match: the ideal balance gives m = 1")
	_check(absf(MissionProject.ratio_match([1.0, 0.0, 0.0, 0.0], [0.4, 0.2, 0.15, 0.25]) - 0.4) < 1e-6,
		"ratio match: all engineering on a sounding gives m = 1 - 0.5*1.2 = 0.4")
	# grade: 30 expected points, 30 points at the ideal ratio, good compat, no defects
	var ideal := [0.4, 0.2, 0.15, 0.25]
	var pts := [12.0, 6.0, 4.5, 7.5]
	var g := MissionProject.grade_of(pts, ideal, 30.0, 1.0, 0.0)
	_check(absf(g - 10.0 * (0.55 * 1.0 / 1.5 + 0.45)) < 1e-4, "grade: q=1, m=1 -> 10*(0.55/1.5+0.45) = %.2f" % g)
	_check(absf(MissionProject.grade_of(pts, ideal, 30.0, 1.15, 0.0) - g * 1.15) < 1e-4, "grade: great compat x1.15")
	_check(absf(MissionProject.grade_of(pts, ideal, 30.0, 1.0, 2.0) - (g - 0.6 * 2.0)) < 1e-4,
		"grade: defects cost 0.6 each below 100 points")
	_check(MissionProject.grade_of(pts, ideal, 10.0, 1.15, 0.0) == 10.0, "grade: clamped to 10")
	_check(MissionProject.grade_of(pts, ideal, 30.0, 0.0, 0.0) == 0.0, "grade: impossible compat gives 0")
	# defects of one week, by hand
	var p := MissionProject.new()
	p.type_id = "sounding"
	p.weeks_total = 3
	p.staff_ids.assign(["a"])
	p.sliders[0] = [100, 0, 0]
	p.work_week(s)
	var wk := base * 0.8 + base * 0.4 * 0.2
	var rel_frac := (base * 0.4 * 0.2) / wk
	var want := 0.04 * wk * (1.0 - 0.5 * rel_frac) - 0.10 * (base * 0.4 * 0.2) * 0.3
	_check(absf(p.defects - want) < 1e-4, "defects: +0.04*week*(1-0.5 rel) - 0.10*rel*0.3 without tests (%.4f)" % p.defects)
	# team size: a sounding (size 0.5) wants 2 Cometlings; extras give 40%
	var tp := MissionProject.new()
	tp.type_id = "sounding"
	tp.staff_ids.assign(["a", "b"])
	_check(tp.ideal_team(s) == 2 and tp.team_efficiency(s) == 1.0, "team: ideal team of a sounding is ceil(0.5*4) = 2")
	tp.staff_ids.assign(["a", "b", "c", "d"])
	_check(absf(tp.team_efficiency(s) - (2.0 + 2.0 * 0.4) / 4.0) < 1e-6, "team: 2 extra Cometlings work at 40%")
	# slider rebalance and phases
	_check(ProjectRules.rebalance([34, 33, 33], 0, 60) == [60, 20, 20], "sliders: moving one pulls the others")
	_check(ProjectRules.rebalance([50, 50, 0], 1, 70) == [30, 70, 0], "sliders: shares keep their proportion")
	_check(ProjectRules.rebalance([100, 0, 0], 0, 40) == [40, 30, 30], "sliders: empty partners split evenly")
	_check(ProjectRules.phase_end(3, 0) == 1 and ProjectRules.phase_end(3, 1) == 2 and ProjectRules.phase_end(3, 2) == 3,
		"phases: a 3-week sounding has 1 week per phase")
	_check(ProjectRules.phase_end(10, 0) == 3 and ProjectRules.phase_end(10, 1) == 7, "phases: thirds of 10 weeks are 3/4/3")
	_check(ProjectRules.compat_tier(1.15) == "great" and ProjectRules.compat_tier(0.75) == "poor"
		and ProjectRules.compat_tier(0.0) == "impossible", "compat tiers")


# ------------------------------------------------------------ a sounding project, start to grade
func _test_sounding_project() -> void:
	print("sounding project")
	var s := _state()
	var phases: Array[int] = []
	var launched: Array[Dictionary] = []
	var completed: Array[Dictionary] = []
	s.project_phase_started.connect(func(_id: String, k: int) -> void: phases.append(k))
	s.mission_launched.connect(func(r: Dictionary) -> void: launched.append(r))
	s.mission_completed.connect(func(r: Dictionary) -> void: completed.append(r))
	var cash0 := s.cash
	# the race pays its own milestone prizes (first sounding flight...): keep them apart
	var race := [0.0, 0.0]
	s.race.claimed.connect(func(id: String, by: String, order: int) -> void:
		if by == RaceDirector.PLAYER:
			var m := s.race.milestone(id)
			race[0] += float(m.get("prize", 0)) * (1.0 if order == 0 else 0.3)
			race[1] += float(m.get("rep", 0)) * (1.0 if order == 0 else 0.5))
	var est := ProjectDesk.estimate(s, "sounding")
	_check(int(est["weeks"]) == 3 and absf(float(est["week_cost"]) - 3000.0) < 0.01,
		"estimate: 3 weeks at 6k x size 0.5 x era 1")
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", ["a", "b", "c", "d"])
	_check(p != null and p.code == "SND-01", "project starts with code SND-01")
	_check(String(s.staff[0]["assigned"]) == "SND-01" and String(s.staff[4]["assigned"]) == "", "team marked assigned")
	_check(s.projects.size() == 1 and String(s.projects[0]["code"]).begins_with("SND-01")
		and s.projects[0]["color"] is Color, "bottom strip shows the project")
	_check(phases == [0], "phase 1 asks for sliders at the start")
	ProjectDesk.set_sliders(s, p.id, [40, 30, 30])
	s.advance_week()
	_check(p.phase == 1 and p.awaiting_sliders and phases == [0, 1], "week 1 done: phase 2 begins")
	_check(absf(float(s.projects[0]["progress"]) - 1.0 / 3.0) < 1e-4, "strip progress 1/3")
	ProjectDesk.set_sliders(s, p.id, [40, 20, 40])
	s.advance_week()
	_check(p.phase == 2 and phases == [0, 1, 2], "week 2 done: phase 3 begins")
	ProjectDesk.set_sliders(s, p.id, [30, 30, 40])
	s.advance_week()
	_check(ProjectDesk.find(s, "SND-01") == null and s.projects.is_empty(), "week 3 done: the project leaves the desk")
	_check(launched.size() == 1 and completed.size() == 1, "mission_launched and (suborbital) mission_completed emitted")
	var h := ProjectDesk.history_entry(s, "SND-01")
	var grade := float(h.get("grade", -1.0))
	print("    grade %.2f  outcome %s  p %.2f  reviews %s  avg %.1f" % [grade, h.get("outcome"), h.get("p_success"),
		str((h.get("reviews", []) as Array).map(func(r: Dictionary) -> int: return r["score"])), h.get("review_avg")])
	_check(grade > 0.0 and grade <= 10.0, "the project has a grade in 0..10 (%.2f)" % grade)
	_check((h["reviews"] as Array).size() == 4, "4 newspaper reviews")
	for r: Dictionary in h["reviews"]:
		_check(int(r["score"]) >= 0 and int(r["score"]) <= 10 and String(r["quote_key"]).begins_with("TY_PJ_Q_"),
			"review %s: %d" % [r["id"], r["score"]])
	_check(String(s.staff[0]["assigned"]) == "" and float(s.staff[0]["xp"]) > 0.0, "team released with XP")
	_check(s.active_missions.is_empty(), "suborbital missions do not go to active_missions")
	var spent := 3 * 3000.0 + 30000.0 + PayloadRules.cost(h["payload"])
	_check(absf((cash0 - s.cash + race[0]) - spent) < 0.01, "paid 3 weeks + the launch + the payload (%.0f)" % (cash0 - s.cash))
	if h["success"]:
		# the lab adds its own weekly points on top of the mission's science
		_check(s.research_points >= float(h["science"]) * 0.5 - 1e-4 and s.research_points > 0.0,
			"research points += science * 0.5 (%.1f)" % s.research_points)
	_check(ProjectDesk.compat_known(s, "sounding", "suborbital"), "compat discovered after flying it")
	_check(absf(s.reputation - race[1] - (20.0 + clampf(float(h["review_avg"]) - 5.0, -5.0, 5.0))) < 1e-4, "reputation += avg - 5")


# ------------------------------------------------------------ sliders change the grade predictably
func _test_sliders_change_grade() -> void:
	print("sliders vs grade")
	# ideal sounding ratio is eng 40 / sci 20 / ops 15 / rel 25
	var balanced := _run_sounding(_state(5), [[50, 20, 30], [45, 20, 35], [20, 10, 70]])
	var lopsided := _run_sounding(_state(5), [[0, 100, 0], [0, 100, 0], [0, 0, 100]])
	var no_tests := _run_sounding(_state(5), [[50, 20, 30], [60, 40, 0], [50, 50, 0]])
	var gb := ProjectDesk.project_grade(balanced)
	var gl := ProjectDesk.project_grade(lopsided)
	print("    balanced %.2f (m %.2f)  science-heavy %.2f  no tests %.2f (defects %.2f vs %.2f)" % [gb,
		MissionProject.ratio_match(MissionProject.fractions_of(balanced["pts"]), [0.4, 0.2, 0.15, 0.25]), gl,
		ProjectDesk.project_grade(no_tests), float(no_tests["defects"]), float(balanced["defects"])])
	_check(gb > gl + 1.0, "sliders near the ideal ratio grade higher than all-science (%.2f > %.2f)" % [gb, gl])
	var fb := MissionProject.fractions_of(balanced["pts"])
	var fl := MissionProject.fractions_of(lopsided["pts"])
	_check(fl[1] > fb[1], "more science slider -> larger science fraction")
	_check(float(no_tests["defects"]) > float(balanced["defects"]), "skipping the test sliders leaves more defects")
	_check(ProjectDesk.project_grade(no_tests) < gb, "and a lower grade")
	# monotonic: sweeping the payload (science) slider of phase 1 away from the ideal lowers the grade
	var last := 11.0
	var mono := true
	for sci: int in [20, 50, 80, 100]:
		var rest: int = 100 - sci
		var h := _run_sounding(_state(5), [[rest / 2, sci, rest - rest / 2], [45, 20, 35], [20, 10, 70]])
		mono = mono and ProjectDesk.project_grade(h) <= last + 1e-6
		last = ProjectDesk.project_grade(h)
	_check(mono, "grade falls steadily as the science slider moves past the ideal")
	# a bigger team does more work: q rises, grade does not fall
	var small := _run_sounding(_state(5), [[50, 20, 30], [45, 20, 35], [20, 10, 70]], ["a"])
	_check(ProjectDesk.project_grade(small) < gb, "one Cometling alone grades lower than the team (%.2f)" % ProjectDesk.project_grade(small))


# ------------------------------------------------------------ determinism, save / load
func _test_determinism_and_save() -> void:
	print("determinism")
	var sl := [[50, 20, 30], [45, 20, 35], [20, 10, 70]]
	var a := _run_sounding(_state(77), sl)
	var b := _run_sounding(_state(77), sl)
	_check(is_equal_approx(float(a["grade"]), float(b["grade"])) and a["outcome"] == b["outcome"]
		and str(a["reviews"]) == str(b["reviews"]), "same seed + same sliders -> same grade, outcome and reviews")
	# save in the middle of a project, load, finish: same as without saving
	var s := _state(78)
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", ["a", "b", "c", "d"])
	ProjectDesk.set_sliders(s, p.id, sl[0])
	s.advance_week()
	var s2 := TycoonState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check(s2.mission_projects.size() == 1 and s2.mission_projects[0].code == "SND-01"
		and s2.projects.size() == 1 and s2.projects[0]["color"] is Color, "save / load keeps the project and its strip")
	for st: TycoonState in [s, s2]:
		var q := ProjectDesk.find(st, "SND-01")
		ProjectDesk.set_sliders(st, q.id, sl[1])
		st.advance_week()
		ProjectDesk.set_sliders(st, q.id, sl[2])
		st.advance_week()
	var h1 := ProjectDesk.history_entry(s, "SND-01")
	var h2 := ProjectDesk.history_entry(s2, "SND-01")
	_check(not h1.is_empty() and absf(float(h1["grade"]) - float(h2["grade"])) < 1e-6 and h1["outcome"] == h2["outcome"]
		and str(h1["reviews"]) == str(h2["reviews"]), "a loaded game finishes the project the same way")
	var s3 := TycoonState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check(s3.project_history.size() == 1 and ProjectDesk.compat_known(s3, "sounding", "suborbital"),
		"history survives save / load")


# ------------------------------------------------------------ expectations
func _test_expectation_rises() -> void:
	print("expectation")
	var s := _state()
	var e0 := MissionProject.expected_points(s, "sounding", s.project_history)
	_check(absf(e0 - 60.0 * 0.5) < 1e-4, "era 1 sounding expects E_era 60 x size 0.5")
	s.project_history.append({"type": "sounding", "week": s.weeks, "grade": 5.0})
	var e1 := MissionProject.expected_points(s, "sounding", s.project_history)
	_check(absf(e1 - e0 * 1.1) < 1e-4, "a recent repeat raises it 10%")
	s.project_history.append({"type": "demo_sat", "week": s.weeks, "grade": 9.0})
	var e2 := MissionProject.expected_points(s, "sounding", s.project_history)
	_check(absf(e2 - e0 * 1.1 * (1.0 + 0.03 * 4.0)) < 1e-4, "the best recent grade raises it too")
	# a failed flight's mission grade is cut, but the expectation reads the project grade
	var t := _state()
	t.project_history.append({"type": "demo_sat", "week": t.weeks, "grade": 9.0 * 0.35, "grade_project": 9.0, "outcome": "fail"})
	_check(absf(MissionProject.expected_points(t, "sounding", t.project_history) - e0 * (1.0 + 0.03 * 4.0)) < 1e-4,
		"a rocket failure does not lower the expectation (it uses grade_project)")
	s.weeks = 5 * 52 + 200
	_check(MissionProject.expected_points(s, "sounding", s.project_history) > e2, "a later era expects more")
	_check(ProjectDesk.next_code(s, "sounding") == "SND-02", "codes count up per type")


# ------------------------------------------------------------ orbital launches feed mission ops
func _test_orbital_launch() -> void:
	print("orbital launch")
	var found := false
	for sd in range(1, 40):
		var s := _state(sd)
		var p := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b", "c", "d"])
		if p == null:
			_check(false, "demo satellite starts")
			return
		var completed := [0]
		s.mission_completed.connect(func(_r: Dictionary) -> void: completed[0] += 1)
		for i in 10:
			s.advance_week()
		var h := ProjectDesk.history_entry(s, p.id)
		if h.is_empty() or not h["success"]:
			continue
		found = true
		_check(s.active_missions.size() == 1, "a successful orbital mission goes to active_missions")
		var am: Dictionary = s.active_missions[0]
		for k in ["id", "code", "type", "target", "start_week", "weeks_total", "data_stored", "data_down", "science", "status"]:
			_check(am.has(k), "active mission has '%s'" % k)
		_check(am["status"] in ["cruise", "ops"] and completed[0] == 0, "mission ops flies it; not completed yet")
		break
	_check(found, "some seed launches the demo satellite successfully")


# ------------------------------------------------------------ contracts and start errors
func _test_contract_and_errors() -> void:
	print("contracts and errors")
	var s := _state()
	s.contracts.append({"id": "c1", "type": "sounding", "target": "suborbital", "status": "accepted", "reward": 50000,
		"min_bars": {"sci": 6.0}})
	s.contracts.append({"id": "c2", "type": "sounding", "target": "suborbital", "status": "offer"})
	_check(ProjectDesk.open_contracts(s).size() == 1, "accepted contracts are quick picks; offers are not")
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", ["a"], "c1")
	_check(p != null and p.contract_id == "c1" and ProjectDesk.open_contracts(s).is_empty(), "a contract in work leaves the picks")
	_check(ProjectDesk.start_error(s, "sounding", "suborbital", ["a"]) == "TY_PJ_ERR_BUSY", "busy Cometlings cannot join")
	_check(ProjectDesk.start_error(s, "sounding", "leo", ["b"]) == "TY_PJ_ERR_IMPOSSIBLE", "impossible combos are blocked")
	_check(ProjectDesk.start_error(s, "telescope", "geo", ["b"]) == "TY_PJ_ERR_TARGET", "locked targets are blocked")
	_check(ProjectDesk.start_error(s, "sounding", "suborbital", []) == "TY_PJ_ERR_TEAM", "a project needs a team")
	s.cash = 100.0
	_check(ProjectDesk.start_error(s, "sounding", "suborbital", ["b"]) == "TY_PJ_ERR_CASH", "and the money for it")


# ------------------------------------------------------------ the mission grade counts the flight
## A well-built sounding forced to fail keeps at most launch.outcome_grade.fail (0.35) of its
## project grade as the mission grade, and the review shows that; forced to succeed, the
## mission grade is the project grade. Old saves without grade_project are converted on load.
func _test_outcome_grade() -> void:
	print("mission grade")
	var sl := [[50, 20, 30], [45, 20, 35], [20, 10, 70]]
	ProjectDesk.dev_force_outcome = "fail"
	var sf := _state(5)
	var hf := _run_sounding(sf, sl)
	ProjectDesk.dev_force_outcome = "success"
	var ss := _state(5)
	var hs := _run_sounding(ss, sl)
	ProjectDesk.dev_force_outcome = ""
	var gpf := ProjectDesk.project_grade(hf)
	print("    failed: mission %.2f of project %.2f   success: mission %.2f of project %.2f" % [float(hf.get("grade", 0)), gpf,
		float(hs.get("grade", 0)), ProjectDesk.project_grade(hs)])
	_check(hf.get("outcome") == "fail" and not hf.get("success", true) and hs.get("success", false), "forced outcomes: a failure and a success")
	_check(hf.has("grade_project") and gpf >= 5.5, "the failed project was well built (project grade %.2f)" % gpf)
	_check(float(hf["grade"]) <= 0.35 * gpf + 1e-6, "a failed launch keeps at most 0.35 of the project grade (%.2f)" % float(hf["grade"]))
	_check(absf(ProjectDesk.project_grade(hs) - gpf) < 1e-6, "the launch roll does not change the project grade")
	_check(absf(float(hs["grade"]) - ProjectDesk.project_grade(hs)) < 1e-6, "a full success keeps the project grade as the mission grade")
	# the review: the big number is the mission grade, the project grade under it only when cut
	TranslationServer.set_locale("pt_BR")
	for i in 2:
		var failed := i == 0
		var h: Dictionary = hf if failed else hs
		var scr := (load("res://scenes/tycoon/ui/screens/project_review.tscn") as PackedScene).instantiate()
		get_root().add_child(scr)
		scr.bind(sf if failed else ss, null, null)
		scr.open_with({"project_id": String(h["id"])})
		await create_timer(1.2).timeout
		var shown := String((scr.get_node("%Grade") as Label).text)
		_check(shown == "%.1f" % float(h["grade"]), "review (%s): the big number is the mission grade (%s)" % ["fail" if failed else "success", shown])
		_check(String((scr.get_node("%GradeCaption") as Label).text) == "TY_PJ_GRADE_MISSION", "review: captioned as the mission grade")
		var gp := scr.get_node("%GradeProject") as Label
		if failed:
			_check(gp.visible and gp.text.contains("%.1f" % gpf), "review (fail): the project grade under it (%s)" % gp.text)
		else:
			_check(not gp.visible, "review (success): no project line when the grades agree")
		scr.queue_free()
		await process_frame
	# saves from before grade_project
	var so := _state()
	ProjectDesk.restore(so, {"project_history": [{"id": "OLD-1", "type": "sounding", "grade": 8.0, "outcome": "fail"},
		{"id": "OLD-2", "type": "sounding", "grade": 7.0, "outcome": "full"}]})
	var o1 := ProjectDesk.history_entry(so, "OLD-1")
	var o2 := ProjectDesk.history_entry(so, "OLD-2")
	_check(absf(ProjectDesk.project_grade(o1) - 8.0) < 1e-6 and absf(float(o1["grade"]) - 8.0 * 0.35) < 1e-6,
		"an old failed entry: project grade kept, mission grade cut on load")
	_check(absf(float(o2["grade"]) - 7.0) < 1e-6 and absf(ProjectDesk.project_grade(o2) - 7.0) < 1e-6, "an old success is unchanged")


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
