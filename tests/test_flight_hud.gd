extends SceneTree
## The Cometworks flight HUD (scenes/flight/flight_hud.tscn, FlightHUD, FlightTips, the map style):
##   goal       the free test flight's goal card and a tycoon mission's (title, goal line, the
##              goal kind from the target), the goal gauge reaching "done" in orbit
##   coach      the "do this now" line on the pad, after ignition, with an empty stage, in orbit,
##              with the autopilot, after a breakup
##   gauges     delta-v left vs what the goal still needs (marker), stage stickers in their colours
##   tips       the first-flight tips: engine lever -> ignition on the pad, lifting off covers
##              both, the empty-stage tip, "Skip tips" ends them, nothing written when persist
##              is off, headless runs show none unless forced
##   end card   a mission flight's card names the hand-back to the campus; a test flight's not
##   map        the shared style resource feeds the conic colours and marker labels
## Run: godot --headless --path . --script res://tests/test_flight_hud.gd

var _failures := 0
var world: FlightWorld


func _initialize() -> void:
	TranslationServer.set_locale("en")
	FlightTips.persist = false
	await _test_goal_and_coach()
	await _test_tips()
	await _test_mission_card()
	_test_map_style()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _start(mission := {}, mission_mode := false) -> void:
	if world and is_instance_valid(world):
		world.queue_free()
		await process_frame
	FlightSession.clear()
	FlightSession.mission = mission
	FlightSession.set_vessel(load("res://scenes/examples/garca.tscn"), "Garça", 0.0)
	world = (load(FlightSession.FLIGHT_SCENE) as PackedScene).instantiate()
	world.embedded = mission_mode
	world.mission_mode = mission_mode
	get_root().add_child(world)
	await _frames(2)
	await _wait(0.25)


func _test_goal_and_coach() -> void:
	print("goal card and coach (test flight)")
	await _start()
	var hud := world.hud
	_check(hud.goal_kind == "orbit", "a test flight aims for orbit")
	_check((hud.get_node("%GoalCaption") as Label).text == tr("FL_CW_GOAL_TEST"), "the card reads TEST FLIGHT")
	_check((hud.get_node("%GoalTitle") as Label).text == "Garça", "...with the vessel's name")
	_check((hud.get_node("%Hint") as Label).text == tr("FL_CW_NOW_IGNITE"), "on the pad: press SPACE")
	_check((hud.get_node("%BtnStage") as Button).text == tr("FL_CW_STAGE_IGNITE"), "the staging key reads Ignition")
	_check(not (hud.get_node("%TeleBody") as Control).visible, "\"More data\" starts folded")
	var rows := hud.get_node("%StageList").get_children()
	_check(rows.size() == 2, "two stage stickers (%d)" % rows.size())
	if rows.size() == 2:
		var c0: Color = (rows[1].get_node("%Stripe") as ColorRect).color
		var c1: Color = (rows[0].get_node("%Stripe") as ColorRect).color
		_check(c0.is_equal_approx(hud.stage_colors[0]) and c1.is_equal_approx(hud.stage_colors[1]),
			"each sticker wears its stage colour")
	var bar := hud.get_node("%DvBar") as CwSegmentBar
	_check(bar.marker > 0.0 and bar.marker < bar.value, "the dv gauge marks what orbit still needs, under the tanks (%.2f < %.2f)" % [
		bar.marker, bar.value])
	world.stage()
	await _frames(8)
	var t := world._telemetry()
	_check(hud.now_key(t) in ["FL_CW_NOW_CLIMB", "FL_CW_NOW_TURN"], "after ignition: climb, then turn (%s)" % hud.now_key(t))
	_check((hud.get_node("%BtnStage") as Button).text == tr("FL_CW_STAGE_NEXT"), "the staging key reads Drop stage")
	world.set_autopilot(true)
	await _frames(3)
	_check(hud.now_key(world._telemetry()) == "FL_CW_NOW_AUTO", "with the autopilot: sit back")
	world.set_autopilot(false)
	# an empty stage: drain the first stage's tanks
	for pool in world.sim.craft.pools:
		if int(pool["stage"]) == world.sim.craft.current_stage:
			pool["prop"] = 0.0
	await _frames(12)
	t = world._telemetry()
	_check(FlightTips.stage_empty(t), "a drained first stage is empty")
	_check(hud.now_key(t) == "FL_CW_NOW_STAGE", "...and the coach says drop it (%s)" % hud.now_key(t))
	# in orbit
	var sys := world.sys
	var r := FlightOrbit.R + 200000.0
	var v := sqrt(FlightOrbit.MU / r)
	var e := FlightWorld.EAST.normalized()
	world.sim.set_orbit_state(sys.earth, PackedFloat64Array([0.0, r, 0.0]), PackedFloat64Array([e.x * v, e.y * v, e.z * v]))
	var evs: Array = []
	while world.sim.craft.current_stage < world.sim.craft.stage_count - 1:
		world.sim.craft.next_stage(evs)
	world.sim.craft.throttle = 0.0
	world.sim.in_orbit = true
	# the HUD refreshes on the world's 0.1 s telemetry tick, which counts frame time: wait in time
	# (up to 2 s) for it, not in frames (headless frames can be a millisecond each)
	var goal_bar := hud.get_node("%GoalBar") as CwSegmentBar
	var btn_stage := hud.get_node("%BtnStage") as Button
	var t_end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < t_end:
		await process_frame
		if is_equal_approx(goal_bar.value, 1.0) and btn_stage.disabled:
			break
	t = world._telemetry()
	_check(hud.now_key(t) == "FL_CW_NOW_ORBIT", "in orbit: open the map (%s)" % hud.now_key(t))
	_check(is_equal_approx((hud.get_node("%GoalBar") as CwSegmentBar).value, 1.0), "the goal gauge is full")
	_check((hud.get_node("%GoalProgress") as Label).text == tr("FL_CW_GOAL_DONE"), "...and says Goal reached")
	_check((hud.get_node("%BtnStage") as Button).disabled, "the last stage cannot be dropped")
	# toasts keep ink text; a white tint becomes lilac on the dot
	hud.toast("hi", Color.WHITE)
	_check((hud.get_node("%ToastDot") as Control).self_modulate.is_equal_approx(CwPalette.LILAC), "a white toast tint turns lilac")
	hud.toast("hi", CwPalette.MINT)
	_check((hud.get_node("%ToastDot") as Control).self_modulate.is_equal_approx(CwPalette.MINT), "a candy tint stays")
	world.sim.craft.crashed = true
	_check(hud.now_key(world._telemetry()) == "FL_CW_NOW_LOST", "after a breakup: the kind words")
	world.sim.craft.crashed = false


func _test_tips() -> void:
	print("first-flight tips")
	var before := FlightTips.load_done()
	FlightTips.force = false
	await _start()
	var tips: FlightTips = world.hud.get_node("%Tip")
	await _wait(0.3)
	_check(not tips.visible, "headless runs show no tips")
	FlightTips.force = true
	tips.restart()
	await _wait(0.3)
	_check(tips.visible and tips.current == "throttle", "first: the engine lever (%s)" % tips.current)
	var text := (tips.get_node("%TipText") as Label).text
	_check(text == tr("FL_CW_TIP_THROTTLE"), "its text comes from the strings")
	var anchor := world.hud.get_node("%ThrottleBox") as Control
	_check(tips.get_global_rect().end.y <= anchor.get_global_rect().position.y + 1.0, "it sits above the engine lever")
	tips.complete("throttle")
	await _wait(0.3)
	_check(tips.current == "ignite", "then: ignition (%s)" % tips.current)
	world.stage()
	await _wait(0.3)
	_check(tips.is_done("throttle") and tips.is_done("ignite") and tips.current != "ignite", "lifting off covers both pad tips")
	for pool in world.sim.craft.pools:
		if int(pool["stage"]) == world.sim.craft.current_stage:
			pool["prop"] = 0.0
	tips.complete("turn")
	await _wait(0.3)
	_check(tips.current == "stage", "an empty stage brings its tip (%s)" % tips.current)
	world.stage()
	await _wait(0.3)
	_check(tips.is_done("stage") and tips.current != "stage", "dropping the stage completes it")
	tips.skip_all()
	await _wait(0.3)
	_check(not tips.visible and tips.is_done("map"), "Skip tips ends them all")
	_check(FlightTips.load_done() == before, "persist off: the settings are left alone")
	FlightTips.force = false


func _test_mission_card() -> void:
	print("mission goal and end-of-flight card")
	var m := {"title": "SND-1 · Sounding rocket", "target": "Suborbital", "target_id": "suborbital",
		"dv_needed": 2500.0, "payload_kg": 50.0, "goal": "reach space (100 km)"}
	await _start(m, true)
	var hud := world.hud
	_check(hud.goal_kind == "space", "a suborbital mission aims for space")
	_check((hud.get_node("%GoalCaption") as Label).text == tr("FL_CW_GOAL_MISSION"), "the card reads MISSION")
	_check((hud.get_node("%GoalTitle") as Label).text == "SND-1 · Sounding rocket", "...with the mission's title")
	_check((hud.get_node("%GoalLine") as Label).text.contains("reach space"), "...and its goal")
	world.stage()
	await _frames(10)
	world.end_flight("abort")
	await _frames(4)
	_check((hud.get_node("%Report") as Control).visible, "the end card opens")
	_check((hud.get_node("%ReportNext") as Control).visible, "a mission card says the campus reviews the flight")
	_check((hud.get_node("%ReportTitle") as Label).text == tr("FL_CW_RP_TITLE_MISSION"), "...titled MISSION FLIGHT OVER")
	_check((hud.get_node("%BtnRHangar") as Button).text == tr("TY_HG_FL_CONCLUDE"), "its main key finishes the mission")
	_check(not (hud.get_node("%Tip") as Control).visible, "no tip over the end card")
	await _start()
	world.stage()
	await _frames(6)
	world.end_flight("abort")
	await _frames(4)
	_check(not (world.hud.get_node("%ReportNext") as Control).visible, "a test flight's card has no campus line")
	_check((world.hud.get_node("%ReportTitle") as Label).text == tr("FL_CW_RP_TITLE_TEST"), "...titled TEST FLIGHT OVER")
	world.queue_free()
	await process_frame


func _test_map_style() -> void:
	print("map style")
	var st := FlightMap.STYLE
	_check(st != null and st.soi_color("earth") == FlightMap.SOI_COLORS["earth"], "the conic colours come from map_style.tres")
	_check(st.soi_color("pluto") == st.soi_other, "other bodies take the spare colour")
	_check(FlightMap.NODE_COLOR == st.node_color, "the maneuver colour too")
	_check(FlightMapStyle.on_paper(st.soi_color("moon")).get_luminance() <= 0.42, "line colours deepen to read on paper labels")
	var marker := (load("res://scenes/flight/map_marker.tscn") as PackedScene).instantiate()
	_check((marker.get_node("Label") as Label).get_theme_stylebox("normal") is StyleBoxFlat, "marker labels sit on a paper pill")
	marker.free()


## The HUD refreshes ten times a second: wait in time, not frames (headless frames are quick).
func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
