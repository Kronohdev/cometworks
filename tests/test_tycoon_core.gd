extends SceneTree
## Headless checks for the Cometworks core (src/tycoon/): calendar, clock speeds, monthly
## salaries, the comet countdown, determinism and save / load.
## Run: godot --headless --path . --script res://tests/test_tycoon_core.gd

var _failures := 0


func _initialize() -> void:
	var staff: Array[Dictionary] = [
		{"name": "A", "role": "engineer", "level": 1}, {"name": "B", "role": "scientist", "level": 1},
		{"name": "C", "role": "pilot", "level": 2}, {"name": "D", "role": "controller", "level": 1}]
	var s := TycoonState.new_campaign(42, staff)
	_check(s.year() == 1 and s.week() == 1, "starts at year 1, week 1")
	_check(s.cash == 300000.0, "start cash from data/tycoon/rules.json (%.0f)" % s.cash)
	_check(s.rivals.size() == 3, "3 rivals loaded")
	var months := [0]
	s.month_passed.connect(func(_y: int, _m: int) -> void: months[0] += 1)
	var bill := s.monthly_salaries()
	# 4000 + 4000 + 4000*1.25*1.3 + 4000
	_check(absf(bill - 18500.0) < 0.01, "monthly salaries %.0f (want 18500)" % bill)
	for i in 52:
		s.advance_week()
	_check(s.year() == 2 and s.week() == 1, "52 weeks later: year 2, week 1 (got %d/%d)" % [s.year(), s.week()])
	_check(months[0] == 12, "12 month changes in a year (got %d)" % months[0])
	_check(absf(s.cash - (300000.0 - 12.0 * bill)) < 0.01, "salaries paid 12 times (cash %.0f)" % s.cash)
	_check(s.comet_weeks_left() == 24 * 52, "comet countdown: 24 years left")
	# save / load round trip
	var d := s.to_dict()
	var s2 := TycoonState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_check(s2.weeks == s.weeks and absf(s2.cash - s.cash) < 0.01 and s2.staff.size() == 4, "save / load round trip")
	_check(s2.rng.randi() == s.rng.randi(), "rng state survives save / load")
	# determinism
	var a := TycoonState.new_campaign(7)
	var b := TycoonState.new_campaign(7)
	_check(a.rng.randi() == b.rng.randi(), "same seed, same draws")
	# end of campaign
	for i in 25 * 52:
		a.advance_week()
	_check(a.is_over() and a.comet_weeks_left() == 0, "campaign ends when the comet passes (year %d)" % a.year())
	# clock
	var c := TycoonClock.new(s.rules)
	_check(c.tick(5.9) == 0 and c.tick(0.2) == 1, "speed 1: one week every 6 s")
	c.set_speed(3)
	_check(c.tick(2.05) == 2, "speed 3: one week per second")
	c.set_speed(0)
	_check(c.tick(100.0) == 0, "paused: no weeks")
	c.set_speed(3)
	_check(c.tick(100.0) == 4, "a long hitch advances at most 4 weeks")
	c.fair_mode = true
	c.set_speed(1)
	_check(is_equal_approx(c.seconds_per_week(), 1.0), "fair mode: 1 s per week at any speed")
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
