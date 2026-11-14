extends SceneTree
## Headless checks for the E3 agency systems (src/tycoon/research, contracts, finance, agency):
## researching unlocks a mission type and parts; the contract board renews monthly, pays,
## bonuses and penalises; the ledger adds up; government budget, loan and licences; save /
## load; determinism by seed; and 25 automatic years at default without bankruptcy, played by
## a simple auto-player that funds research, builds the lab, accepts contracts, pays project
## costs and completes them with a mid grade.
## Run: godot --headless --path . --script res://tests/test_tycoon_agency.gd

var _failures := 0


func _staff() -> Array[Dictionary]:
	return [{"name": "A", "profession": "systems_engineer", "skill": 0.6},
		{"name": "B", "profession": "scientist", "skill": 0.6},
		{"name": "C", "profession": "test_technician", "skill": 0.5},
		{"name": "D", "profession": "flight_controller", "skill": 0.5},
		{"name": "E", "profession": "researcher", "skill": 0.7}]


func _initialize() -> void:
	_test_research()
	_test_contracts()
	_test_finance()
	_test_save_and_determinism()
	_test_autoplay()
	await _test_screens()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


# ------------------------------------------------------------ research
func _test_research() -> void:
	print("research")
	var s := TycoonState.new_campaign(11, _staff())
	_check(s.mission_type_available("sounding") and s.mission_target_available("suborbital"),
		"sounding rocket and suborbital need no research")
	_check(not s.mission_type_available("demo_sat") and not s.mission_target_available("leo"),
		"demo satellite and low orbit start locked")
	_check(not TycoonResearch.fund(s, "upper_stage"), "a tech whose prerequisites are not done cannot be funded")
	_check(not TycoonResearch.can_research(s, "lunar_stage"), "era 3 techs are out of reach in era 1")
	var pp := TycoonResearch.pp_per_week(s)
	_check(pp > 0.0, "the researcher makes PP at a workshop bench before the lab exists (%.2f PP/week)" % pp)
	_check(TycoonResearch.seated(s).size() == 1, "no lab: one seat")
	_check(TycoonResearch.fund(s, "small_sat_bus") and TycoonResearch.active(s) == "small_sat_bus", "fund small satellite bus")
	_check(TycoonResearch.fund(s, "orbital_rocketry") and TycoonResearch.queue(s) == ["orbital_rocketry"],
		"a second funded tech waits in the queue")
	var n := 0
	while not TycoonResearch.is_done(s, "small_sat_bus") and n < 200:
		s.advance_week()
		n += 1
	_check(TycoonResearch.is_done(s, "small_sat_bus"), "small satellite bus researched in %d weeks" % n)
	_check(n >= int(TycoonResearch.tech("small_sat_bus")["weeks"]), "research takes at least its minimum weeks")
	_check(s.mission_type_available("demo_sat"), "researching unlocks a mission type (demo satellite)")
	_check(bool(s.unlocked.get("part:bus_small", false)) and bool(s.unlocked.get("option:bus_cubesat", false)),
		"researching unlocks parts and ship options")
	_check(String(s.news[0]["key"]) == "TY_NEWS_TECH" or _has_news(s, "TY_NEWS_TECH"), "news line for the new tech")
	_check(TycoonResearch.active(s) == "orbital_rocketry", "the queue moves on")
	# the lab adds seats and output
	var before := TycoonResearch.pp_per_week(s)
	s.buildings["lab"] = {"kind": "lab", "level": 1, "target": 1, "weeks_left": 0}
	_check(TycoonResearch.lab_seats(s) == 2 and TycoonResearch.pp_per_week(s) > before * 1.5,
		"lab level 1: 2 seats, scientists help (%.1f -> %.1f PP/week)" % [before, TycoonResearch.pp_per_week(s)])
	# mission science feeds the pool (other systems add to research_points)
	s.research_points += 500.0
	for i in 12:
		s.advance_week()
	_check(s.mission_target_available("leo"), "orbital rocketry done with mission science: low orbit open")
	# licensing
	var c0 := s.cash
	_check(TycoonResearch.license(s, "small_sat_bus") and s.cash > c0, "licensing a tech pays %.0f cr" % (s.cash - c0))
	_check(not TycoonResearch.can_license(s, "small_sat_bus"), "a tech is licensed once")
	# every tech's data is sound
	var ids := {}
	for t: Dictionary in TycoonResearch.techs():
		ids[String(t["id"])] = int(t["era"])
	var ok := ids.size() == 30
	for t: Dictionary in TycoonResearch.techs():
		for p: String in t.get("prereq", []):
			ok = ok and ids.has(p) and ids[p] < int(t["era"])
		for ty in t.get("unlocks", {}).get("types", []):
			ok = ok and not s.mission_type(String(ty)).is_empty()
		for tg in t.get("unlocks", {}).get("targets", []):
			ok = ok and not s.mission_target(String(tg)).is_empty()
		for p in t.get("unlocks", {}).get("parts", []):
			ok = ok and not PartDB.get_part(String(p)).is_empty()
	_check(ok, "30 techs, prerequisites from earlier eras, unlocks name real types, targets and parts")
	var all_types := true
	for ty: Dictionary in s.mdata["types"]:
		var by := TycoonResearch.tech_for_type(String(ty["id"]))
		all_types = all_types and (by != "" or int(ty["era"]) == 1)
	_check(all_types, "every mission type after the sounding rocket comes from a tech")


func _has_news(s: TycoonState, key: String) -> bool:
	for n in s.news:
		if String(n["key"]) == key:
			return true
	return false


# ------------------------------------------------------------ contracts
func _test_contracts() -> void:
	print("contracts")
	var s := TycoonState.new_campaign(5, _staff())
	s.advance_week()
	var o1 := TycoonContracts.offers(s)
	_check(o1.size() >= 3 and o1.size() <= 6, "board shows 3..6 offers (%d)" % o1.size())
	var all_ok := true
	for c in o1:
		all_ok = all_ok and s.mission_type_available(String(c["type"])) and s.mission_target_available(String(c["target"])) \
			and float(c["reward"]) > 0.0 and not (c["min_bars"] as Dictionary).is_empty()
	_check(all_ok, "offers only use available types / targets and carry reward and minimum bars")
	var ids1 := o1.map(func(c: Dictionary) -> String: return String(c["id"]))
	# accept one, keep it through the month change
	var cid := String(o1[0]["id"])
	_check(TycoonContracts.accept(s, cid), "accept an offer")
	var c := TycoonContracts.find(s, cid)
	_check(int(c["deadline_week"]) == s.weeks + int(c["weeks_allowed"]), "deadline set when signing")
	var renewals := 0
	var m0 := TycoonFinance.month_key(s)
	for i in 5:
		s.advance_week()
	_check(TycoonFinance.month_key(s) != m0, "a month passed")
	var o2 := TycoonContracts.offers(s)
	var fresh := true
	for x in o2:
		fresh = fresh and not String(x["id"]) in ids1
	_check(o2.size() >= 3 and fresh, "the board renewed with %d new offers" % o2.size())
	_check(String(TycoonContracts.find(s, cid).get("status", "")) == "accepted", "the signed contract stays")
	# success with bonus
	var cash0 := s.cash
	var rep0 := s.reputation
	s.complete_contract(cid, 8.5, true)
	var paid := float(c["reward"]) + float(c["bonus"])
	_check(absf(s.cash - cash0 - paid) < 0.5 and String(c["status"]) == "done", "success with grade 8.5 pays reward + bonus (%.0f)" % paid)
	_check(s.reputation > rep0, "reputation up (%.1f -> %.1f)" % [rep0, s.reputation])
	s.complete_contract(cid, 9.0, true)
	_check(absf(s.cash - cash0 - paid) < 0.5, "completing twice pays once")
	# mid grade: no bonus
	var o3 := TycoonContracts.offers(s)
	var c2 := String(o3[0]["id"])
	TycoonContracts.accept(s, c2)
	cash0 = s.cash
	s.complete_contract(c2, 6.0, true)
	_check(absf(s.cash - cash0 - float(TycoonContracts.find(s, c2)["reward"])) < 0.5, "grade 6: reward without bonus")
	# failure: penalty
	var c3 := String(TycoonContracts.offers(s)[0]["id"])
	TycoonContracts.accept(s, c3)
	cash0 = s.cash
	rep0 = s.reputation
	s.complete_contract(c3, 3.0, false)
	var cc3 := TycoonContracts.find(s, c3)
	_check(String(cc3["status"]) == "failed" and absf(cash0 - s.cash - float(cc3["penalty"])) < 0.5 and s.reputation < rep0,
		"failure costs the penalty (%.0f) and reputation" % float(cc3["penalty"]))
	# deadline expiry
	var c4 := String(TycoonContracts.offers(s)[0]["id"])
	TycoonContracts.accept(s, c4)
	var cc4 := TycoonContracts.find(s, c4)
	var n := 0
	while String(cc4["status"]) == "accepted" and n < 200:
		s.advance_week()
		n += 1
	_check(String(cc4["status"]) == "failed" and bool(cc4["late"]) and s.weeks == int(cc4["deadline_week"]) + 1,
		"an unfinished contract fails the week after its deadline (late penalty)")
	# capacity
	var cap := TycoonContracts.max_active(s)
	var signed := TycoonContracts.accepted(s).size()
	for x in TycoonContracts.offers(s):
		TycoonContracts.accept(s, String(x["id"]))
	_check(TycoonContracts.accepted(s).size() <= cap and cap == 2, "HQ level 1: at most %d contracts at once (had %d)" % [cap, signed])
	# decline
	var left := TycoonContracts.offers(s)
	if not left.is_empty():
		var did := String(left[0]["id"])
		_check(TycoonContracts.decline(s, did) and TycoonContracts.find(s, did).is_empty(), "decline removes the offer")
	# rivals take commercial offers; Space Apps contracts appear once Earth observation is open
	var r := TycoonState.new_campaign(9, _staff())
	for id in ["orbital_rocketry", "small_sat_bus", "sun_sync_orbits", "basic_instruments", "multispectral_imaging",
			"radio_tracking", "high_gain_antenna", "upper_stage", "cometling_selection", "space_physics"]:
		TycoonResearch.complete(r, id)
	var taken := 0
	var space_apps := {}
	var kinds := {}
	for w in 52 * 2:
		r.advance_week()
		for x in TycoonContracts.offers(r):
			kinds[String(x["kind"])] = true
			if String(x["kind"]) == "space_apps":
				space_apps[String(x["sponsor"])] = true
		for nw in r.news:
			pass
	for nw in r.news:
		if String(nw["key"]) == "TY_NEWS_RIVAL_CONTRACT":
			taken += 1
	_check(taken > 0, "rivals took %d commercial offers in 2 years" % taken)
	_check(kinds.has("government") and kinds.has("commercial") and kinds.has("space_apps"),
		"government, commercial and Space Apps offers")
	_check(space_apps.size() >= 3, "Space Apps contracts seen: %s" % ", ".join(space_apps.keys()))


# ------------------------------------------------------------ finance
func _test_finance() -> void:
	print("finance")
	var s := TycoonState.new_campaign(3, _staff())
	for i in 52:
		s.advance_week()
	_check(_has_news(s, "TY_NEWS_GRANT"), "year 2 starts with the government budget")
	var g: Array = TycoonFinance.db()["gov_budget"]
	var gr := float((TycoonFinance.open_month(s)["in"] as Dictionary).get("grant", 0.0))
	_check(gr > 0.0 and absf(gr - float(g[0]) * (0.5 + s.reputation / 100.0)) < 1.0,
		"grant = G_era x (0.5 + reputation/100) (%.0f)" % gr)
	for i in 52 * 2:
		s.advance_week()
	var ledger: Array = TycoonFinance.fs(s)["ledger"]
	_check(ledger.size() == 24, "ledger keeps 24 closed months (%d)" % ledger.size())
	var adds_up := true
	for mo: Dictionary in ledger:
		var net := TycoonFinance.total(mo["in"]) - TycoonFinance.total(mo["out"])
		adds_up = adds_up and absf(float(mo["cash_end"]) - float(mo["cash_start"]) - net) < 1.0
	_check(adds_up, "every ledger month adds up (cash end - start = income - expenses)")
	var last: Dictionary = ledger[-1]
	_check(absf(float(last["out"].get("salaries", 0.0)) - s.monthly_salaries()) < 0.5, "salaries booked every month")
	_check(float(last["in"].get("donations", 0.0)) >= 0.0, "donations booked")
	# unbooked spending (a project paying directly) is reconciled into "projects"
	s.cash -= 12345.0
	for i in 5:
		s.advance_week()
	var lm: Dictionary = (TycoonFinance.fs(s)["ledger"] as Array)[-1]
	_check(float(lm["out"].get("projects", 0.0)) >= 12345.0 - 1.0, "unbooked spending shows up as projects")
	var pr := TycoonFinance.projection(s)
	_check(pr.size() == 12, "12-month balance projection")
	# government intervention and loan
	s.cash = -50000.0
	s.hype = 0.0
	var k := 0
	while not bool(TycoonFinance.fs(s)["intervention"]) and k < 30:
		s.cash = minf(s.cash, -50000.0)
		s.advance_week()
		k += 1
	_check(bool(TycoonFinance.fs(s)["intervention"]) and _has_news(s, "TY_NEWS_INTERVENTION"),
		"three month-ends in the red: the government steps in")
	var c0 := s.cash
	_check(TycoonFinance.take_loan(s) and absf(s.cash - c0 - TycoonFinance.loan_amount(s)) < 0.5, "loan taken")
	_check(not TycoonFinance.can_take_loan(s), "one loan at a time")
	var pay := float(TycoonFinance.fs(s)["loan"]["payment"])
	_check(pay * 24.0 > TycoonFinance.loan_amount(s), "the loan costs interest (24 x %.0f)" % pay)
	for i in 5:
		s.advance_week()
	_check(int(TycoonFinance.fs(s)["loan"]["months_left"]) == 23, "first instalment paid")


# ------------------------------------------------------------ save / determinism
func _test_save_and_determinism() -> void:
	print("save and determinism")
	var a := _autoplay(77, 3)
	var b := _autoplay(77, 3)
	_check(JSON.stringify(a["state"].to_dict()) == JSON.stringify(b["state"].to_dict()), "same seed, same 3 years")
	var c := _autoplay(78, 3)
	_check(JSON.stringify(a["state"].to_dict()) != JSON.stringify(c["state"].to_dict()), "another seed, another campaign")
	var s: TycoonState = a["state"]
	# (in memory: a 64-bit rng state does not survive a trip through JSON numbers)
	var s2 := TycoonState.from_dict(s.to_dict().duplicate(true))
	for i in 20:
		s.advance_week()
		s2.advance_week()
	# through JSON both ways (numbers come back as floats after a load)
	var j1 := JSON.stringify(JSON.parse_string(JSON.stringify(s.to_dict())), "", true)
	var j2 := JSON.stringify(JSON.parse_string(JSON.stringify(s2.to_dict())), "", true)
	if j1 != j2:
		for i in mini(j1.length(), j2.length()):
			if j1[i] != j2[i]:
				print("    first difference: ...%s... vs ...%s..." % [j1.substr(maxi(i - 80, 0), 160), j2.substr(maxi(i - 80, 0), 160)])
				break
	_check(j1 == j2, "save / load mid-campaign, then 20 weeks: same state")


# ------------------------------------------------------------ 25 years
func _test_autoplay() -> void:
	print("25 automatic years")
	var r := _autoplay(2026, 25)
	var s: TycoonState = r["state"]
	_check(s.is_over(), "campaign over (year %d)" % s.year())
	_check(float(r["min_cash"]) >= 0.0, "never ended a month in the red (lowest month-end %.0f cr)" % float(r["min_cash"]))
	_check(not bool(r["intervened"]), "the government never had to step in")
	_check(int(r["done"]) > 40, "contracts completed: %d (failed %d)" % [int(r["done"]), int(r["failed"])])
	var techs := 0
	for t: Dictionary in TycoonResearch.techs():
		techs += 1 if TycoonResearch.is_done(s, String(t["id"])) else 0
	_check(techs >= 24, "techs researched: %d / 30" % techs)
	_check(s.mission_type_available("comet_mission"), "the comet mission is reachable by the end")


# ------------------------------------------------------------ screens (smoke)
func _test_screens() -> void:
	print("screens")
	var s := TycoonState.new_campaign(4, _staff())
	var clock := TycoonClock.new(s.rules)
	for screen_name in ["research", "contracts", "finance"]:
		var ps := load("res://scenes/tycoon/ui/screens/%s.tscn" % screen_name) as PackedScene
		_check(ps != null, "%s.tscn loads" % screen_name)
		if ps == null:
			continue
		var scr := ps.instantiate() as CwScreen
		get_root().add_child(scr)
		await process_frame  # the root becomes ready on the first frame: then the screen's _ready runs
		scr.bind(s, clock, null)
		match screen_name:
			"research":
				var nodes := 0
				for c in scr.get_node("%NodeTemplate").get_parent().get_children():
					nodes += 1 if c.has_meta("from_template") else 0
				_check(nodes == 30, "research: 30 tech nodes on the grid (%d)" % nodes)
				scr.call("select", "small_sat_bus")
				(scr.get_node("%Fund") as Button).pressed.emit()
				_check(TycoonResearch.active(s) == "small_sat_bus", "research: the Fund button funds the selected tech")
			"contracts":
				var n := TycoonContracts.offers(s).size()
				var cards := 0
				for c in scr.get_node("%OfferTemplate").get_parent().get_children():
					cards += 1 if c.has_meta("from_template") else 0
				_check(n >= 3 and cards == n, "contracts: one card per offer at week 0 (%d)" % cards)
			"finance":
				_check((scr.get_node("%Chart") as CwCashChart).cash.size() >= 1, "finance: chart filled at week 0")
		s.advance_week()
		scr.queue_free()


## Simple auto-player: funds the cheapest open tech, builds the lab, signs every offer it can,
## pays dev weeks and the launch, completes contracts with a mid grade (1 in 10 fails).
func _autoplay(p_seed: int, years: int) -> Dictionary:
	var s := TycoonState.new_campaign(p_seed, _staff())
	var dice := RandomNumberGenerator.new()
	dice.seed = p_seed * 31 + 7
	var era_cost := [1.0, 1.6, 2.4, 3.4, 4.5]
	var jobs := {}  # contract id -> week it ends
	var min_cash := INF
	var ledger_n := 0
	var intervened := false
	var done := 0
	var failed := 0
	for w in years * 52:
		s.advance_week()
		var ledger: Array = TycoonFinance.fs(s)["ledger"]
		var closed := ledger.size() != ledger_n or ledger_n == 24
		ledger_n = ledger.size()
		if closed and not ledger.is_empty():
			min_cash = minf(min_cash, float(ledger[-1]["cash_end"]))
		intervened = intervened or bool(TycoonFinance.fs(s)["intervention"])
		# research
		if TycoonResearch.active(s) == "" and TycoonResearch.queue(s).is_empty():
			var best := ""
			var best_cost := INF
			for t: Dictionary in TycoonResearch.techs():
				var id := String(t["id"])
				if TycoonResearch.can_research(s, id) and float(t["cost"]) < best_cost:
					best = id
					best_cost = float(t["cost"])
			if best != "":
				TycoonResearch.fund(s, best)
		# campus: the lab and its upgrades when there is spare cash
		var nx := s.next_level("lab")
		if not nx.is_empty() and s.cash > float(nx["cost"]) * 3.0:
			s.build("lab")
		# contracts
		for c in TycoonContracts.offers(s):
			if TycoonContracts.accept(s, String(c["id"])):
				jobs[String(c["id"])] = s.weeks + int(s.mission_type(String(c["type"]))["weeks"]) + 2
		var ef := float(era_cost[s.era() - 1])
		for id: String in jobs.keys():
			var c := TycoonContracts.find(s, id)
			if c.is_empty() or String(c["status"]) != "accepted":
				jobs.erase(id)
				continue
			var size := float(s.mission_type(String(c["type"]))["size"])
			if s.weeks < int(jobs[id]) - 2:
				s.cash -= 6000.0 * size * ef  # a week of development
			elif s.weeks == int(jobs[id]) - 2:
				s.cash -= 60000.0 * size * ef  # launch
			elif s.weeks >= int(jobs[id]):
				var ok := dice.randf() > 0.1
				s.complete_contract(id, 6.5, ok)
				if ok:
					done += 1
					s.research_points += 15.0 * size * s.era()  # science downlinked
				else:
					failed += 1
				jobs.erase(id)
	return {"state": s, "min_cash": min_cash, "intervened": intervened, "done": done, "failed": failed}


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
