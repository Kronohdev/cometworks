extends SceneTree
## Headless checks for the race to the Moon (src/tycoon/race/race_director.gd, GDD section 13
## and the E4 acceptance of section 20): rivals take milestones in plausible years across
## several seeds, the player takes a milestone from a synthetic mission result (with the
## first / later prizes), requirements hold, the newspaper prints, the comet ends the
## campaign with a score, and the same seed gives the same race.
## Run: godot --headless --path . --script res://tests/test_tycoon_race.gd

const SEEDS := [1, 7, 42, 2026, 31337, 90210, 5150, 777]

var _failures := 0


func _initialize() -> void:
	_rivals_plausible()
	_player_claims()
	_second_place()
	_determinism()
	_finale()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _run(seed_value: int, years: int) -> TycoonState:
	var s := TycoonState.new_campaign(seed_value)
	for i in years * s.weeks_per_year():
		s.advance_week()
	return s


func _year_of(s: TycoonState, w: int) -> int:
	return w / s.weeks_per_year() + 1


func _rivals_plausible() -> void:
	print("rivals over 25 years, %d seeds" % SEEDS.size())
	var outside := 0
	var total := 0
	var firsts_by_rivals: Array[int] = []
	var first_years := {}   # milestone id -> [years of the first claim]
	var fails := {"aurora": 0, "nimbo": 0, "quietude": 0}
	var counts := {"aurora": 0, "nimbo": 0, "quietude": 0}
	var grace := 0
	var s: TycoonState
	for sd: int in SEEDS:
		s = _run(sd, 25)
		var r := s.race
		grace = int(r.mdata.get("grace_years", 1))
		var line := "  seed %6d:" % sd
		var nf := 0
		for m: Dictionary in r.milestones:
			var yrs: Array = m["years"]
			var f := r.first_of(m["id"])
			line += " %s" % ("--" if f.is_empty() else "%02d" % _year_of(s, int(f["week"])))
			if not f.is_empty():
				nf += 1
				if not first_years.has(m["id"]):
					first_years[m["id"]] = []
				first_years[m["id"]].append(_year_of(s, int(f["week"])))
			for c: Dictionary in r.claims[m["id"]]:
				var y := _year_of(s, int(c["week"]))
				total += 1
				if y < int(yrs[0]) or y > int(yrs[1]) + grace:
					outside += 1
					print("    outside: %s by %s in year %d (plausible %d-%d)" % [m["id"], c["by"], y, yrs[0], yrs[1]])
		for id: String in fails:
			fails[id] += int(r.ai[id]["fails"])
			counts[id] += r.claims_of(id).size()
		firsts_by_rivals.append(nf)
		print(line)
	_check(outside == 0, "every rival claim falls in the milestone's plausible years (%d claims)" % total)
	var min_firsts := 99
	for n in firsts_by_rivals:
		min_firsts = mini(min_firsts, n)
	_check(min_firsts >= 11, "without a player, rivals take at least 11 of 15 firsts in every seed (min %d)" % min_firsts)
	var median_ok := true
	for m: Dictionary in s.race.milestones:
		var ys: Array = first_years.get(m["id"], [])
		if ys.size() < SEEDS.size() / 2:
			if int(m["years"][0]) < 22:
				median_ok = false
				print("    %s: taken in only %d seeds" % [m["id"], ys.size()])
			continue
		ys.sort()
		var med := int(ys[ys.size() / 2])
		if med < int(m["years"][0]) or med > int(m["years"][1]):
			median_ok = false
			print("    %s: median first year %d outside %s" % [m["id"], med, m["years"]])
	_check(median_ok, "median first-claim year of each milestone sits in its plausible window")
	for id: String in counts:
		_check(counts[id] >= 7 * SEEDS.size(), "%s takes milestones (%.1f per campaign)" % [id, float(counts[id]) / SEEDS.size()])
	_check(fails["aurora"] > fails["quietude"] * 2, "bold Aurora Rubra fails more than careful Quietude (%d vs %d)" % [fails["aurora"], fails["quietude"]])
	var board := s.race_board()
	_check(board.size() == 4 and absf(float(board[1]["progress"]) - s.race.claims_of("aurora").size() / 15.0) < 0.001,
		"race_board() progress follows the director")


func _player_claims() -> void:
	print("player milestones")
	var s := TycoonState.new_campaign(11)
	var got: Array = []
	s.milestone_claimed.connect(func(mid: String, by: String) -> void: got.append([mid, by]))
	var cash0 := s.cash
	var rep0 := s.reputation
	s.mission_launched.emit({"project_id": "p1", "code": "SND-01", "type": "sounding", "target": "suborbital", "grade": 7.0,
		"success": false, "outcome": "fail", "contract_id": ""})
	_check(s.milestones == 0, "a failed launch takes nothing")
	s.mission_launched.emit({"project_id": "p2", "code": "SND-02", "type": "sounding", "target": "suborbital", "grade": 8.0,
		"success": true, "outcome": "full", "contract_id": ""})
	_check(s.milestones == 1 and s.race.has_claimed("suborbital", "player"), "a successful sounding launch takes the first suborbital flight")
	_check(got.size() == 1 and got[0] == ["suborbital", "player"], "milestone_claimed emitted (%s)" % [got])
	_check(absf(s.cash - cash0 - 50000.0) < 0.01 and absf(s.reputation - rep0 - 3.0) < 0.01, "first prize: +50k cr, +3 reputation")
	_check(s.race.pending_pages.size() == 1 and String(s.race.pending_pages[0]["milestone"]) == "suborbital", "front page printed")
	_check(String(s.news[0]["key"]) == "TY_RACE_NEWS_FIRST", "Tail Radio line")
	s.mission_launched.emit({"type": "sounding", "target": "suborbital", "success": true, "outcome": "exceptional"})
	_check(s.milestones == 1, "the same milestone is not taken twice")
	s.mission_completed.emit({"project_id": "p3", "code": "ORB-01", "type": "orbiter", "target": "lunar_orbit", "grade": 6.0,
		"success": true, "outcome": "partial", "contract_id": "", "science": 120.0})
	_check(s.race.has_claimed("far_side", "player"), "a completed lunar orbiter photographs the far side")
	_check(absf(s.race.science_total - 120.0) < 0.01, "downlinked science counted for the score")
	s.mission_completed.emit({"type": "base_module", "target": "lunar_pole", "success": true, "outcome": "full"})
	_check(not s.race.has_claimed("launch_base", "player"), "launch base needs the base module and lunar propellant first")
	s.mission_launched.emit({"type": "base_module", "target": "lunar_pole", "success": true, "outcome": "full"})
	s.mission_completed.emit({"type": "isru", "target": "lunar_pole", "success": true, "outcome": "full"})
	s.mission_completed.emit({"type": "isru", "target": "lunar_pole", "success": true, "outcome": "full"})
	_check(s.race.has_claimed("base_module", "player") and s.race.has_claimed("lunar_propellant", "player")
		and s.race.has_claimed("launch_base", "player"), "base module, propellant, then the launch base")
	s.mission_completed.emit({"type": "comet_mission", "target": "comet", "success": true, "outcome": "partial"})
	_check(s.race.met_comet("player"), "a completed comet mission meets the Mother-Ice")


func _second_place() -> void:
	var s := TycoonState.new_campaign(12)
	s.race.claim("first_satellite", "aurora")
	var cap_before := float(s.race.rival("aurora")["capacity"])
	_check(cap_before > 1.1, "a rival's first grows its capacity (%.3f)" % cap_before)
	var cash0 := s.cash
	s.mission_launched.emit({"type": "demo_sat", "target": "leo", "success": true, "outcome": "full"})
	_check(absf(s.cash - cash0 - 60000.0) < 0.01, "second place gets 30%% of the prize (%.0f)" % (s.cash - cash0))
	_check(s.race.first_of("first_satellite")["by"] == "aurora" and s.race.firsts_of("player") == 0, "the first stays Aurora's")
	_check(String(s.news[0]["key"]) == "TY_RACE_NEWS_LATER", "radio line for a later claim")


func _determinism() -> void:
	var a := _run(2026, 12)
	var b := _run(2026, 12)
	_check(JSON.stringify(a.race.to_dict()) == JSON.stringify(b.race.to_dict()), "same seed, same race after 12 years")
	var c := _run(2027, 12)
	_check(JSON.stringify(a.race.claims) != JSON.stringify(c.race.claims), "another seed, another race")


func _finale() -> void:
	var s := TycoonState.new_campaign(5)
	var done: Array = []
	s.race.campaign_finished.connect(func(r: Dictionary) -> void: done.append(r))
	for i in s.campaign_weeks():
		s.advance_week()
	_check(s.is_over() and s.race.finished and done.size() == 1, "the comet passes at the end of year 25: campaign finished once")
	var sc: Dictionary = done[0] if not done.is_empty() else {}
	_check(sc.get("rows", []).size() == 6 and int(sc.get("max", 0)) == 1000, "score: 6 rows out of 1000")
	_check(int(sc.get("total", -1)) >= 0 and int(sc.get("total", 2000)) <= 1200, "score in range (%d)" % int(sc.get("total", -1)))
	_check(sc.get("standings", []).size() == 4, "standings of the 4 agencies")
	s.advance_week()
	_check(done.size() == 1, "nothing happens after the end")


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
