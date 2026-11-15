extends SceneTree
## "Simular até o fim" and the launch watch's speed button (FlightLog, LaunchWatch):
##   1. skipping a flight to its end (FlightLog.finish) ends it as watching it at 1x does: the same
##      outcome (lost / status / body) and the same story (the events' kinds, in order), for a few
##      seeded missions (low orbit, partial, failure, a hop, the Moon, a landing, GEO)
##   2. the speed-up (2x, 4x, 10x: bigger frame steps) changes neither the outcome nor the story
##   3. the event log is not empty, starts at the liftoff and is ordered by time; the failure's
##      break-up comes at the track's second
##   4. the comic and the report: FlightComic builds panels from the log and FlightReport names
##      why a mission went the way it did, with a tip
## "Watching" flies the ascent frame by frame (1/60 s of flight per frame at 1x, k/60 s at kx)
## until the flight rides its track, like the watch does; the coast after that is on exact
## conics at any speed.
## Run: godot --headless --path . --script res://tests/test_flight_skip.gd [-- --quick (no watching)]

## [code, type, target, outcome, the speeds it is also watched at]: every physics step costs about
## a millisecond whatever the speed, so the long ascents are watched at a few speeds only
const MISSIONS := [
	["ORB-01", "demo_sat", "leo", "full", [1]],
	["ORB-02", "demo_sat", "leo", "partial", [10]],
	["ORB-03", "demo_sat", "leo", "fail", [1, 2, 4, 10]],
	["SND-01", "sounding", "suborbital", "full", [1, 2, 4, 10]],
	["LUA-01", "orbiter", "lunar_orbit", "full", [4]],
	["POU-01", "lander", "lunar_surface", "full", []],
	["COM-01", "comms", "geo", "full", []],
]
## flight seconds a watched ascent may take before the test calls it stuck
const ASCENT_CAP := 2400.0

var _failures := 0
var state: TycoonState


func _initialize() -> void:
	state = TycoonState.new()
	state.weeks = 40
	var quick := OS.get_cmdline_user_args().has("--quick")
	for m: Array in MISSIONS:
		_test_mission(m, [] if quick else m[4])
	_test_comic_and_report()
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _track(m: Array) -> Dictionary:
	var id := "p:skip_" + String(m[0])
	var tr := SpaceTracking.find(state, id)
	if tr.is_empty():
		tr = SpaceTracking.build(SpaceTracking.PLAYER, id, String(m[0]), String(m[1]), String(m[2]), String(m[3]),
			float(state.weeks) * SpaceTracking.WEEK)
		tr["project_id"] = ""
		tr["orig"] = tr.duplicate(true)
		SpaceTracking.missions(state).append(tr)
	# every flight starts from the same track (a flight rebases it at its orbit)
	var orig: Dictionary = tr["orig"]
	for k in orig:
		tr[k] = orig[k].duplicate(true) if orig[k] is Array or orig[k] is Dictionary else orig[k]
	tr.erase("ins_t")
	return tr


func _run(m: Array) -> CareerFlight:
	var tr := _track(m)
	var ps := TycoonModes.watch_vessel(state, {}, String(m[2]))
	return CareerFlight.for_track(state, tr, ps, 0.0, "", "TY_RK_CAUSE_STAGE1" if m[3] == "fail" else "")


## Skipped: one call.
func _skip(m: Array) -> FlightLog:
	var lg := FlightLog.new(_run(m))
	var ok := lg.finish(60000.0)
	_check(ok, "%s skipped: it reached its end (%s)" % [m[0], lg.outcome()])
	return lg


## Watched at `speed`x: the ascent in frames of speed/60 s, the watch observing every frame.
func _watch(m: Array, speed: int) -> FlightLog:
	var run := _run(m)
	var lg := FlightLog.new(run)
	var h := float(speed) / 60.0
	var t_end := run.sim.t + ASCENT_CAP
	while not lg.done() and not run.settled() and run.sim.t < t_end:
		run.advance(h, 600)
		lg.observe()
	lg.finish(60000.0)
	return lg


func _test_mission(m: Array, speeds: Array) -> void:
	print("%s (%s → %s, %s)" % m.slice(0, 4))
	var skip := _skip(m)
	var ks := skip.kinds()
	var out := skip.outcome()
	print("    story: %s" % ", ".join(ks))
	print("    end:   %s" % out)
	_check(not skip.events.is_empty() and ks[0] == "liftoff", "the log starts at the liftoff")
	var ordered := true
	for i in range(1, skip.events.size()):
		ordered = ordered and float(skip.events[i]["t"]) >= float(skip.events[i - 1]["t"])
	_check(ordered, "the log is ordered by time")
	match String(m[3]):
		"fail":
			_check(bool(out["lost"]) and ks.has("crash"), "a failure is lost, with its break-up")
			var tr := SpaceTracking.find(state, "p:skip_" + String(m[0]))
			var crash: Dictionary = skip.events[ks.find("crash")] if ks.has("crash") else {}
			var want := float(tr["lost_t"]) - float(tr["launch_t"])
			_check(not crash.is_empty() and absf(float(crash["met"]) - want) < 0.1,
				"...at the track's second (%.2f / %.2f s)" % [float(crash.get("met", -1.0)), want])
		_:
			_check(not bool(out["lost"]), "it is not lost")
	match String(m[2]) if m[3] != "fail" else "":
		"leo", "geo":
			_check(ks.has("orbit") and String(out["status"]) == "orbit", "it ends in orbit")
		"lunar_orbit":
			_check(ks.has("burn") and ks.has("capture") and String(out["body"]) == "moon", "it burns for the Moon and is captured")
		"lunar_surface":
			_check(ks.has("burn") and ks.has("landing") and String(out["status"]) == "arrived", "it burns for the Moon and lands")
		"suborbital":
			_check(ks.has("apogee") and (ks.has("splashdown") or ks.has("landed")), "it tops out and comes down")
	if String(m[2]) == "geo" and m[3] != "fail":
		_check(ks.has("burn") and ks.has("high_orbit"), "the transfer burn and the high orbit")
	for sp: int in speeds:
		var w := _watch(m, sp)
		var same_out: bool = w.outcome()["lost"] == out["lost"] and w.outcome()["status"] == out["status"] \
			and w.outcome()["body"] == out["body"]
		_check(same_out, "watched at %dx: the same outcome (%s)" % [sp, w.outcome()])
		_check(w.kinds() == ks, "watched at %dx: the same story (%s)" % [sp, ", ".join(w.kinds())])


func _test_comic_and_report() -> void:
	print("the comic and the report")
	var lg := _skip(MISSIONS[4])
	var tl := FlightLog.from_track(SpaceTracking.find(state, "p:skip_LUA-01"))
	var tk: Array = (tl["events"] as Array).map(func(e: Dictionary) -> String: return String(e["kind"]))
	_check(tk == ["liftoff", "orbit", "burn", "capture"], "an unrecorded flight tells what its track keeps (%s)" % ", ".join(tk))
	var entry := {"id": "", "code": "LUA-01", "type": "orbiter", "target": "lunar_orbit", "outcome": "partial",
		"success": true, "grade": 4.8, "grade_project": 4.8, "p_success": 0.8, "risks": [], "rocket": {},
		"fit": {"instrument": 0.3, "power": 1.0, "data": 1.0, "team": 1.0}, "rewards": {"cash": 12000.0, "reputation": 1.0}}
	var panels := FlightComic.panels_of(lg.events, "lunar_orbit", "partial", "LUA-01")
	_check(panels.size() >= 4, "the comic has panels (%d)" % panels.size())
	_check(String(panels[0]["kind"]) == "liftoff", "...starting at the liftoff")
	var all_text := true
	for p: Dictionary in panels:
		all_text = all_text and String(p["caption"]) != "" and not String(p["caption"]).begins_with("TY_")
	_check(all_text, "...each with a caption in Vovô Edmundo's words")
	var rep := FlightReport.build(state, entry, lg.outcome())
	var keys: Array = (rep["reasons"] as Array).map(func(r: Dictionary) -> String: return String(r["key"]))
	_check(keys.has("TY_FC_WHY_INSTRUMENTS"), "a partial with the wrong instruments says so (%s)" % ", ".join(keys))
	_check(String((rep["tip"] as Dictionary).get("key", "")) != "", "...with a tip")
	if ResourceLoader.exists(FlightReport.CML_SCRIPT):
		_check(String((rep["cml"] as Dictionary).get("id", "")) == "instruments", "...linked to its CML item (%s)" % rep["cml"])
	var fail := {"id": "", "code": "ORB-03", "type": "demo_sat", "target": "leo", "outcome": "fail", "success": false,
		"p_success": 0.9, "cause_key": "TY_RK_CAUSE_STAGE1", "risks": [{"id": "stage1", "name_key": "TY_RK_RISK_STAGE1",
		"p": 0.05, "fixed": true}], "rocket": {}, "fit": {}}
	var rf := FlightReport.build(state, fail, {"lost": true})
	keys = (rf["reasons"] as Array).map(func(r: Dictionary) -> String: return String(r["key"]))
	_check(keys.has("TY_FC_WHY_CAUSE") and keys.has("TY_FC_WHY_RANDOM"), "a failure with its risks fixed was bad luck (%s)" % ", ".join(keys))


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
