extends SceneTree
## Headless checks for the Solar System map and the launch watch inside the campus (TycoonModes,
## SpaceMapOverlay, LaunchWatch, the flight's map-only / spectator modes):
##   - M on the campus opens the map: every tracked mission is listed, the clock keeps running
##   - selecting a mission focuses the map on it (and follows it); Esc lets go, Esc again leaves
##   - "Acompanhar" opens the craft up close (spectator flight at its place); leaving goes back to
##     the map
##   - the review's "Acompanhar o lançamento" opens the watch; a failed launch breaks up in it and
##     its track is perdida; the review is still there after
## Run: godot --headless --path . --script res://tests/test_space_map.gd

var _failures := 0
var main: TycoonMain


func _initialize() -> void:
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(5)
	main.race_flow.autosave = false
	main.clock.set_speed(0)
	var s := main.state
	s.weeks = 20
	_launch(s, "A1", "ORB-01", "demo_sat", "leo", "full", 12)
	_launch(s, "A2", "LUA-01", "orbiter", "lunar_orbit", "full", 19)
	_launch(s, "A3", "ORB-02", "demo_sat", "leo", "fail", 18)
	s.race.claim("first_satellite", "aurora")
	SpaceTracking.sync(s)
	var n := SpaceTracking.missions(s).size()
	_check(n == 4, "four tracks: three launches and a rival's (%d)" % n)

	# --- the map
	main.clock.set_speed(2)
	_press(KEY_M)
	await _frames(6)
	_check(main.modes.kind == "map", "M on the campus opens the Solar System map")
	var ov := main.modes.overlay as SpaceMapOverlay
	_check(ov != null and ov.get_script() == load("res://src/tycoon/tracking/space_map_overlay.gd"), "the map overlay is loaded")
	if ov == null:
		_end()
		return
	var fw := main.modes.mode_node as FlightWorld
	_check(fw.map_only and fw.map_view and not fw.map.show_vessel, "the flight runs map-only (map on, no rocket)")
	_check(main.clock.speed == 2, "the clock keeps running under the map")
	var rows := 0
	for c in ov.get_node("%RowTemplate").get_parent().get_children():
		if c.has_meta("from_template") and (c as Control).visible:
			rows += 1
	_check(rows == n, "the list shows every mission (%d rows)" % rows)
	var t0 := fw.time
	_check(absf(t0 - SpaceTracking.now(s, ov.week_fraction())) < 1.0, "the map's time is the campus calendar")
	main.clock.dev_turbo = 40.0
	await _frames(40)
	main.clock.dev_turbo = 1.0
	_check(fw.time > t0, "time flows on the map with the clock (%.0f s later)" % (fw.time - t0))
	ov.select("p:A2")
	await _frames(3)
	var trk := SpaceTracking.find(s, "p:A2")
	var st := ov.display_state(trk, fw.time)
	_check(fw.map.focus == -2 and fw.map.frame_body() == int(st["body"]), "selecting focuses the map on the craft")
	_check(fw.map.focus_name() == "LUA-01", "the map names the followed craft")
	_check((ov.get_node("%Detail") as Control).visible and (ov.get_node("%DCode") as Label).text == "LUA-01",
		"the selected mission's card")
	ov.select("p:A3")
	await _frames(3)
	_check(String((ov.get_node("%DStatus") as Label).text) == TranslationServer.translate("TY_TRK_ST_LOST"),
		"the failed launch shows as perdida")
	_check((ov.get_node("%Watch") as Button).disabled, "...and cannot be watched up close")
	_press(KEY_ESCAPE)
	await _frames(3)
	_check(ov.selected == "" and main.modes.kind == "map", "Esc lets go of the craft first")
	# up close
	main.clock.set_speed(0)
	ov.select("p:A1")
	await _frames(3)
	_check(not (ov.get_node("%Watch") as Button).disabled, "a craft in orbit can be watched up close")
	ov.watch_selected()
	await _frames(6)
	var ff := main.modes.mode_node as FlightWorld
	_check(main.modes.kind == "flight" and ff != null and ff.spectator, "Acompanhar opens the spectator flight")
	if ff:
		var want := SpaceTracking.state_at(SpaceTracking.find(s, "p:A1"), ff.time)
		var alt := ff.active.body.altitude()
		_check(alt > 250000.0 and alt < 560000.0, "the craft is in its orbit (%.0f km)" % (alt / 1000.0))
		_check(absf(FlightOrbit.length(want["pos"]) - FlightOrbit.length(ff.active.body.pos())) < 5000.0,
			"...where its track says")
		ff.revert_to_hangar()
	await _frames(6)
	_check(main.modes.kind == "map", "leaving the close view goes back to the map")
	ov = main.modes.overlay as SpaceMapOverlay
	_check(ov != null and ov.selected == "p:A1", "...on the same craft")
	_press(KEY_ESCAPE)
	await _frames(3)
	_press(KEY_ESCAPE)
	await _frames(4)
	_check(not main.modes.is_open(), "Esc leaves the map")
	_check(main.hud.current_screen() == "", "...without opening the pause menu")

	# --- the review's watch of a failed launch
	main.hud.open_screen("project_review", {"project_id": "A3"})
	await _frames(4)
	var rev := main.hud.get_node("%Screens").get_child(0)
	var watch := rev.get_node("%Watch") as Button
	_check(watch.visible, "the review offers Acompanhar o lançamento")
	watch.pressed.emit()
	await _frames(6)
	var w := main.modes.mode_node as FlightWorld
	var lw := main.modes.overlay as LaunchWatch
	_check(w != null and w.spectator and lw != null, "the launch watch opens (spectator flight + its overlay)")
	if w and lw:
		_check(not w.launched, "on the pad for the countdown")
		await _until(func() -> bool: return w.launched, 5000)
		_check(w.launched and w.autopilot != null, "it lifts off by itself")
		w._set_warp_value(50)
		await _until(func() -> bool: return w.active.crashed, 6000)
		var met := w.mission_time()
		var fail := float(SpaceTracking.find(s, "p:A3")["lost_t"]) - float(SpaceTracking.find(s, "p:A3")["launch_t"])
		_check(w.active.crashed and absf(met - fail) < 12.0, "it breaks up when its track says (%.0f s, track %.0f s)" % [met, fail])
		w._set_warp_value(1)
		await _until(func() -> bool: return lw.get_node("%Result").visible, 600)
		_check(lw.get_node("%Result").visible and lw.phase == "lost", "the result card: Lançamento perdido")
		lw.go_back()
	await _frames(6)
	_check(not main.modes.is_open() and main.hud.current_screen() == "project_review", "back to the review after the watch")
	main.hud.close_screen()
	await _frames(3)
	# --- the dev menu's keys
	var dev := get_root().get_node_or_null("CwDev")
	if dev:
		var before := SpaceTracking.missions(s).size()
		var msg := String(dev.call("_a_space_test", null))
		await _frames(4)
		_check(SpaceTracking.missions(s).size() == before + 1 and main.modes.overlay is LaunchWatch,
			"dev: a test mission in space and its watch (%s)" % msg)
		(main.modes.mode_node as FlightWorld).revert_to_hangar()
		await _frames(4)
		msg = String(dev.call("_a_space_map", null))
		await _frames(4)
		_check(main.modes.kind == "map", "dev: the Solar System map (%s)" % msg)
		(main.modes.mode_node as FlightWorld).revert_to_hangar()
		await _frames(4)
	_end()


func _launch(s: TycoonState, pid: String, code: String, type_id: String, target: String, outcome: String, week: int) -> void:
	var e := {"id": pid, "code": code, "type": type_id, "target": target, "outcome": outcome, "success": outcome != "fail",
		"week": week, "grade": 6.0, "grade_project": 6.0, "bars": [5.0, 5.0, 5.0, 5.0], "reviews": [], "rewards": {}, "rocket": {}}
	s.project_history.append(e)


func _end() -> void:
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _press(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func _until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
