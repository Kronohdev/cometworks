extends SceneTree
## Headless checks for Cometworks saves (src/tycoon/tycoon_save.gd, E0 acceptance of GDD
## section 20): save -> load gives the same state, and 52 weeks after loading equal 52 weeks
## without saving (rivals, RNG, money, news, milestones). Uses slot "test" in user://saves/.
## Run: godot --headless --path . --script res://tests/test_tycoon_save.gd

const SLOT := "test"

var _failures := 0


func _initialize() -> void:
	var staff: Array[Dictionary] = [
		{"name": "A", "role": "engineer", "level": 1}, {"name": "B", "role": "scientist", "level": 2},
		{"name": "C", "role": "pilot", "level": 3}]
	var s := TycoonState.new_campaign(4242, staff)
	TycoonLeader.found(s, {"name": "Jujuba", "profession": "researcher", "hat": "beanie", "agency_color": "#3fe0c5"})
	s.cash = 9.0e6
	s.build("lab")
	for i in 7 * 52 + 13:   # mid-year, mid-month, with rival claims and a building in progress
		s.advance_week()
	s.mission_launched.emit({"type": "sounding", "target": "suborbital", "success": true, "outcome": "full"})
	s.mission_launched.emit({"type": "demo_sat", "target": "leo", "success": true, "outcome": "full"})
	s.mission_completed.emit({"type": "demo_sat", "target": "leo", "success": true, "outcome": "full", "science": 33.3})
	s.rng.randf()   # move the shared RNG off its seed position
	# a rocket family with flight heritage (E2)
	var fam := RocketFamilies.ensure(s, {"core": "core_kestrel"}, "Sabiá")
	RocketFamilies.record_flight(s, String(fam["id"]), true)
	_check(s.race.claims_of("aurora").size() > 0, "rivals already hold milestones before saving")
	_check(TycoonSave.save(s, SLOT, {"fair_mode": true}) == OK, "save to user://saves/")
	_check(TycoonSave.exists(SLOT), "slot file exists")
	var file := TycoonSave.read(SLOT)
	_check(int(file.get("version", 0)) == TycoonSave.VERSION and file.has("saved_at"), "file has version and time")
	_check(bool(file.get("extra", {}).get("fair_mode", false)), "extra data (fair mode) kept")
	_check(int(file.get("summary", {}).get("year", 0)) == s.year(), "summary for the menus")
	var l: TycoonState = TycoonSave.load_state(SLOT)
	_check(l != null, "load_state returns a campaign")
	if l == null:
		_end()
		return
	_check(_canon(l.to_dict()) == _canon(s.to_dict()), "save -> load gives the same state")
	_check(l.rng.state == s.rng.state and l.race.rng.state == s.race.rng.state, "RNG states are exact (64-bit)")
	_check(l.race.claims_of("player").size() == 2 and l.milestones == 2, "player milestones survive")
	_check(absf(l.race.science_total - 33.3) < 1e-9, "science total survives")
	_check(l.leader == s.leader and TycoonLeader.member(l).get("hat") == "beanie", "the leader Cometling survives")
	var lf := RocketFamilies.find(l, String(fam["id"]))
	_check(String(lf.get("name", "")) == "Sabiá" and RocketFamilies.flights(lf) == 1
		and absf(RocketFamilies.trust(lf) - RocketFamilies.trust(fam)) < 1e-9, "rocket families and their heritage survive")
	# the same future with and without the save
	for i in 52:
		s.advance_week()
		l.advance_week()
	var a := _canon(s.to_dict())
	var b := _canon(l.to_dict())
	_check(a == b, "52 weeks after loading equal 52 weeks without saving")
	if a != b:
		_diff(JSON.parse_string(a), JSON.parse_string(b), "")
	_check(l.race.claims_of("aurora").size() == s.race.claims_of("aurora").size(), "rivals advance the same way")
	# Continue: the tycoon scene opens on the saved campaign (what the main menu does)
	TycoonSave.save(s, SLOT, {"fair_mode": true})
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.set("load_slot", SLOT)
	main.set("fair_mode", true)
	get_root().add_child(main)
	await process_frame
	var tm := main as TycoonMain
	if tm.state == null:
		_check(false, "the tycoon scene did not start")
		_end()
		return
	_check(tm.state != null and tm.state.weeks == s.weeks and tm.state.race.claims_of("player").size() == 2,
		"the tycoon scene continues the saved campaign (week %d)" % (tm.state.weeks if tm.state else -1))
	_check(tm.clock.fair_mode and tm.race_flow != null, "fair mode and the race flow come along")
	tm.race_flow.autosave = false
	main.queue_free()
	_check(load("res://src/menu/main_menu.gd") != null, "main menu script loads (Continue wiring)")
	# a finished campaign stays finished
	for i in l.campaign_weeks():
		l.advance_week()
	TycoonSave.save(l, SLOT)
	var f := TycoonSave.load_state(SLOT)
	_check(f.is_over() and f.race.finished and not f.race.final_result.is_empty(), "a finished campaign loads finished, with its score")
	# listing and the newest slot
	_check(TycoonSave.list().size() >= 1 and TycoonSave.has_any(), "list() sees the save")
	_check(TycoonSave.latest_slot() != "", "latest_slot() for Continue")
	_check(TycoonSave.load_state("nope") == null, "a missing slot loads null")
	_difficulty()
	_end()


## The career's difficulty (TycoonDifficulty): saved, loaded, and Normal for saves without it.
func _difficulty() -> void:
	var staff: Array[Dictionary] = [{"name": "A", "role": "engineer", "level": 1}]
	var n := TycoonState.new_campaign(7, staff)
	var h := TycoonState.new_campaign(7, staff, "hard")
	var e := TycoonState.new_campaign(7, staff, "easy")
	_check(n.difficulty == "normal" and h.difficulty == "hard" and e.difficulty == "easy", "a campaign keeps its difficulty")
	_check(h.cash < n.cash and e.cash > n.cash, "the difficulty scales the starting cash (%d / %d / %d)" % [e.cash, n.cash, h.cash])
	TycoonSave.save(h, SLOT)
	var l := TycoonSave.load_state(SLOT)
	_check(l != null and l.difficulty == "hard", "the difficulty survives save and load")
	var old := n.to_dict()
	old.erase("difficulty")
	_check(TycoonState.from_dict(old).difficulty == "normal", "an old save without a difficulty plays on Normal")
	var odd := n.to_dict()
	odd["difficulty"] = "impossible"
	_check(TycoonState.from_dict(odd).difficulty == "normal", "an unknown difficulty falls back to Normal")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	_check("difficulty" in main, "the tycoon scene takes the difficulty from the leader creator")
	main.free()


func _end() -> void:
	TycoonSave.delete(SLOT)
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


## State dict -> canonical text (JSON numbers, sorted keys, big ints tagged), for equality.
static func _canon(d: Dictionary) -> String:
	var j: Variant = JSON.parse_string(JSON.stringify(TycoonSave.encode(d), "", true, true))
	return JSON.stringify(j, "", true, true)


func _diff(a: Variant, b: Variant, p: String) -> void:
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		for k in a:
			_diff(a[k], b.get(k), p + "/" + str(k))
	elif typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY and a.size() == b.size():
		for i in a.size():
			_diff(a[i], b[i], p + "[%d]" % i)
	elif JSON.stringify(a, "", true, true) != JSON.stringify(b, "", true, true):
		print("    differs at %s: %s vs %s" % [p, JSON.stringify(a, "", true, true).left(160),
			JSON.stringify(b, "", true, true).left(160)])


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
