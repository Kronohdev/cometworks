extends SceneTree
## Headless checks for the missions in space (src/tycoon/tracking/space_tracking.gd):
##   - a launch becomes a track: in flight during the ascent, then in orbit, moving with the clock
##     on an exact two-body orbit (radius and energy kept, positions change week to week)
##   - a lunar mission's transfer arrives where the Moon is, then orbits the Moon
##   - a failed launch is lost (perdida) from its break-up on, and stays lost
##   - tracks survive save / load, and an old save (no tracking) gets them back from the history
##   - the rivals' milestones are tracked in their colours
## Run: godot --headless --path . --script res://tests/test_space_tracking.gd

const SLOT := "test_tracking"

var _failures := 0


func _initialize() -> void:
	_check(SpaceTracking != null and SpaceTracking.WEEK == 604800.0, "SpaceTracking script loaded")
	var s := TycoonState.new_campaign(777)
	s.mission_launched.emit({"project_id": "T1", "code": "ORB-01", "type": "demo_sat", "target": "leo",
		"success": true, "outcome": "full"})
	var tr := SpaceTracking.for_project(s, "T1")
	_check(not tr.is_empty(), "a launch becomes a track")
	var t0 := float(tr.get("launch_t", -1.0))
	_check(absf(t0 - SpaceTracking.now(s)) < 1.0, "launch date is the campaign week (%.0f s)" % t0)
	_check(SpaceTracking.status_at(tr, t0 + 60.0) == "flight", "in flight during the ascent")
	_check(SpaceTracking.status_at(tr, t0 + 3600.0) == "orbit", "in orbit after the ascent")
	var sys := FlightSolar.get_system()
	var a := SpaceTracking.state_at(tr, t0 + 3600.0)
	var b := SpaceTracking.state_at(tr, t0 + 3.0 * SpaceTracking.WEEK + 1234.0)
	var ra := FlightOrbit.length(a["pos"])
	var rb := FlightOrbit.length(b["pos"])
	_check(int(a["body"]) == sys.earth, "LEO track orbits the Earth")
	_check(ra > sys.radius[sys.earth] + 250000.0 and ra < sys.radius[sys.earth] + 560000.0,
		"LEO altitude %.0f km" % ((ra - sys.radius[sys.earth]) / 1000.0))
	_check(absf(ra - rb) < 2000.0, "circular orbit kept over three weeks (Kepler)")
	_check(FlightOrbit.length(_sub(a["pos"], b["pos"])) > 1000.0, "the craft moves with the clock")
	var pts := SpaceTracking.leg_points(tr, 0)
	_check(pts.size() >= 60 * 3, "the orbit has a path to draw (%d points)" % (pts.size() / 3))
	_check(SpaceTracking.can_follow(tr, t0 + 3600.0), "a craft in LEO can be followed in 3D")
	for i in 3:
		s.advance_week()
	_check(String(SpaceTracking.for_project(s, "T1")["status"]) == "orbit", "status advanced by the weeks: em órbita")

	# --- the Moon
	s.mission_launched.emit({"project_id": "T2", "code": "LUA-01", "type": "orbiter", "target": "lunar_orbit",
		"success": true, "outcome": "full"})
	var lt := SpaceTracking.for_project(s, "T2")
	var legs: Array = lt["legs"]
	_check(legs.size() >= 3, "lunar track: parking, transfer, lunar orbit (%d legs)" % legs.size())
	if legs.size() >= 3:
		var tli: Dictionary = legs[1]
		var t_arr := float(tli["t1"])
		var c := SpaceTracking.leg_conic(lt, 1)
		var at := c.position_at(t_arr)
		var moon := sys.pos_rel(sys.moon, sys.earth, t_arr)
		var miss := FlightOrbit.length(_sub(at, moon))
		_check(miss < 1000000.0, "the transfer meets the Moon (miss %.0f km)" % (miss / 1000.0))
		_check(SpaceTracking.status_at(lt, (float(tli["t0"]) + t_arr) * 0.5) == "flight", "em voo on the way")
		var st := SpaceTracking.state_at(lt, t_arr + 86400.0)
		_check(int(st["body"]) == sys.moon and String(st["status"]) == "orbit", "then in orbit around the Moon")
		var rl := FlightOrbit.length(st["pos"])
		_check(absf(rl - sys.radius[sys.moon] - 100000.0) < 5000.0, "lunar orbit at 100 km")
		_check(t_arr - float(lt["launch_t"]) < 30.0 * 86400.0, "arrives within a month of the launch")
	# landing
	s.mission_launched.emit({"project_id": "T5", "code": "POU-01", "type": "lander", "target": "lunar_surface",
		"success": true, "outcome": "full"})
	var land := SpaceTracking.for_project(s, "T5")
	var t_end := float(land["launch_t"]) + 40.0 * 86400.0
	_check(SpaceTracking.status_at(land, t_end) == "arrived", "a lander arrives (chegou)")
	_check(absf(FlightOrbit.length(SpaceTracking.state_at(land, t_end)["pos"]) - sys.radius[sys.moon]) < 10.0,
		"...on the Moon's surface")

	# --- a failed launch
	s.mission_launched.emit({"project_id": "T3", "code": "ORB-02", "type": "demo_sat", "target": "leo",
		"success": false, "outcome": "fail"})
	var ft := SpaceTracking.for_project(s, "T3")
	var fl := float(ft["lost_t"])
	_check(fl > float(ft["launch_t"]), "a failed launch has a break-up time")
	_check(SpaceTracking.status_at(ft, fl - 1.0) == "flight" and SpaceTracking.status_at(ft, fl + 1.0) == "lost",
		"it is lost (perdida) from the break-up on")
	s.advance_week()
	_check(String(SpaceTracking.for_project(s, "T3")["status"]) == "lost", "the weekly status says perdida")
	_check(not SpaceTracking.can_follow(ft, fl + 10.0), "a lost craft cannot be followed")

	# --- other targets
	for tg in ["suborbital", "sso", "geo", "lunar_flyby", "lunar_pole", "comet"]:
		s.mission_launched.emit({"project_id": "X_" + tg, "code": tg, "type": "orbiter", "target": tg,
			"success": true, "outcome": "full"})
		var xt := SpaceTracking.for_project(s, "X_" + tg)
		var ok := not xt.is_empty()
		var late := float(xt["launch_t"]) + 60.0 * 86400.0
		var stl := SpaceTracking.state_at(xt, late)
		var p: PackedFloat64Array = stl["pos"]
		ok = ok and is_finite(p[0]) and is_finite(p[1]) and is_finite(p[2])
		var want: String = {"suborbital": "arrived", "sso": "orbit", "geo": "orbit", "lunar_flyby": "arrived", "lunar_pole": "arrived",
			"comet": "arrived"}[tg]
		_check(ok and String(stl["status"]) == want, "%s: %s after two months (got %s)" % [tg, want, stl["status"]])
	var geo := SpaceTracking.for_project(s, "X_geo")
	var rg := FlightOrbit.length(SpaceTracking.state_at(geo, float(geo["launch_t"]) + 5.0 * 86400.0)["pos"])
	_check(absf(rg - 42157000.0) < 50000.0, "GEO at 35 786 km (%.0f km)" % ((rg - 6371000.0) / 1000.0))

	# --- rivals
	for i in 52 * 4:
		s.advance_week()
	var rivals := 0
	for t: Dictionary in SpaceTracking.missions(s):
		if String(t["owner"]) != SpaceTracking.PLAYER:
			rivals += 1
	var claims := 0
	for r in s.rivals:
		claims += s.race.claims_of(String(r["id"])).size()
	_check(claims == 0 or rivals >= claims, "rival milestones are tracked (%d claims, %d tracks)" % [claims, rivals])
	if rivals > 0:
		for t: Dictionary in SpaceTracking.missions(s):
			if String(t["owner"]) != SpaceTracking.PLAYER:
				_check(SpaceTracking.color_of(s, t) == s.race.agency_color(String(t["owner"])), "a rival track has its colour")
				break

	# --- save / load
	var n := SpaceTracking.missions(s).size()
	_check(TycoonSave.save(s, SLOT) == OK, "save")
	var l := TycoonSave.load_state(SLOT)
	_check(l != null and SpaceTracking.missions(l).size() == n, "tracks survive save / load (%d)" % n)
	if l:
		var a1 := SpaceTracking.state_at(SpaceTracking.for_project(s, "T2"), SpaceTracking.now(s))
		var a2 := SpaceTracking.state_at(SpaceTracking.for_project(l, "T2"), SpaceTracking.now(l))
		_check(FlightOrbit.length(_sub(a1["pos"], a2["pos"])) < 1.0, "the same place after loading")
		_check(String(SpaceTracking.for_project(l, "T3")["status"]) == "lost", "a lost craft stays perdida after loading")
		l.mission_launched.emit({"project_id": "T4", "code": "ORB-03", "type": "demo_sat", "target": "leo", "success": true,
			"outcome": "full"})
		_check(not SpaceTracking.for_project(l, "T4").is_empty(), "a loaded campaign keeps tracking launches")
	# an old save: no tracking, a launched project in the history
	var d := s.to_dict()
	d.erase("tracking")
	(d["project_history"] as Array).append({"id": "OLD1", "code": "OLD-01", "type": "demo_sat", "target": "leo",
		"week": 3, "success": true, "outcome": "full"})
	var old := TycoonState.from_dict(d)
	_check(SpaceTracking.missions(old).is_empty(), "an old save loads with no tracks")
	SpaceTracking.sync(old)
	var ot := SpaceTracking.for_project(old, "OLD1")
	_check(not ot.is_empty() and absf(float(ot["launch_t"]) - 3.0 * SpaceTracking.WEEK) < 1.0,
		"...and gets them back from the history")
	TycoonSave.delete(SLOT)
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
