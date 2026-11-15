extends SceneTree
## Headless checks for the launch sequence (src/tycoon/launch/launch_sequence.gd,
## scenes/tycoon/launch/launch_sequence.tscn) on the Cometworks main screen: a project that
## launches opens the "launch" screen before the review, the clock stays paused, the campus
## camera is handed to the shot camera and given back, skipping goes to the result card and
## then out, the review (and the newspaper) still follow, and the setting turns it off.
## Run: godot --headless --path . --script res://tests/test_tycoon_launch.gd

var _failures := 0
var main: TycoonMain
var flow: ProjectFlow


func _initialize() -> void:
	var was_enabled := LaunchSequence.enabled()
	LaunchSequence.set_enabled(true)
	# outcome looks
	_check(LaunchSequence.kind_of({"success": true, "outcome": "full"}) == "success", "full -> success look")
	_check(LaunchSequence.kind_of({"success": true, "outcome": "exceptional"}) == "success", "exceptional -> success look")
	_check(LaunchSequence.kind_of({"success": true, "outcome": "partial"}) == "partial", "partial -> partial look")
	_check(LaunchSequence.kind_of({"success": false, "outcome": "fail"}) == "fail", "fail -> fail look")
	# the scene itself
	var ps := load("res://scenes/tycoon/launch/launch_sequence.tscn") as PackedScene
	_check(ps != null, "launch_sequence.tscn loads")
	var probe := ps.instantiate() as LaunchSequence
	var anims := probe.get_node("AnimationPlayer") as AnimationPlayer
	for a in ["countdown", "flight_success", "flight_partial", "flight_fail", "result", "outro", "RESET"]:
		_check(anims.has_animation(a), "animation %s authored" % a)
	_check(probe.rocket_models.size() == 5, "one rocket model per era")
	probe.free()
	_pad_rules()
	_check(ResourceLoader.exists("res://scenes/tycoon/ui/screens/launch.tscn"), "HUD screen 'launch' exists")

	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	get_root().add_child(main)
	await _frames(3)
	main.race_flow.autosave = false
	for c in main.get_children():
		if c is ProjectFlow:
			flow = c
	_check(flow != null and flow.launch_cinematic, "ProjectFlow plays the launch")
	main.clock.set_speed(2)

	# a sounding that launches: the launch screen first
	var s := main.state
	var p := _launch_project(s)
	_check(main.hud.current_screen() == "launch", "launch opens the launch screen (got '%s')" % main.hud.current_screen())
	_check(main.clock.speed == 0, "the clock is paused during the launch")
	await _frames(5)
	var seq := main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	_check(seq != null and seq.anim.current_animation == "countdown", "the countdown plays")
	_check(main.camera.is_cinematic(), "the campus camera follows the shot camera")
	_check(main.hud.modulate.a < 1.0, "the HUD chrome fades out")
	if seq:
		_check(String(seq.result.get("project_id", "")) == p.id, "the sequence shows the launched project")
		_check(seq.kind == LaunchSequence.kind_of(ProjectDesk.history_entry(s, p.id)), "the look matches the outcome")
		var stage := seq.get_node("Stage") as Node3D
		_check(String(seq.result.get("pad", "")) == "pad" and seq.pad_lot == "pad", "the first launch leaves from the first pad")
		_check(stage.global_position.distance_to(main.campus.lot_position("pad")) < 0.1, "the stage sits on the launch pad")
		var pb := main.campus.building_node("pad")
		_check(pb != null and pb.rocket_held and not _pad_rocket(pb).visible, "the pad's own rocket is off while the sequence flies")
	# Space skips to the card, a second press leaves
	_press(KEY_SPACE)
	await _frames(3)
	_check(seq != null and seq.anim.current_animation == "result", "a first skip shows the result card")
	_check(seq != null and seq.get_node("%Card" + seq.kind.capitalize()).visible, "the card for the outcome is on")
	_check(main.clock.speed == 0, "space did not unpause the clock")
	_press(KEY_SPACE)
	await _frames(3)
	_check(not main.camera.is_cinematic(), "the camera is given back")
	await _wait_closed("launch", 3.0)
	_check(main.hud.current_screen() != "launch", "the launch screen closes after the outro")
	await _frames(3)
	_check(main.hud.current_screen() == "project_review", "the review follows, before any newspaper (got '%s')" % main.hud.current_screen())
	_check(main.clock.speed == 0, "still paused for the review")
	# close the follow-ups: the clock comes back
	for i in 6:
		if main.hud.current_screen() == "":
			break
		main.hud.close_screen()
		await _frames(3)
	await _frames(20)
	_check(main.hud.modulate.a > 0.99, "the HUD chrome is back")
	_check(main.clock.speed == 2, "the clock resumes at its old speed (got %d)" % main.clock.speed)
	var pad1 := main.campus.building_node("pad")
	_check(pad1 != null and not pad1.rocket_held and pad1.rocket_progress < 1.0 and not _pad_rocket(pad1).visible,
		"after the launch the pad stands empty (the next rocket is being assembled)")
	_check(LaunchPads.pick(s, "light") == "pad", "with one pad, that pad still launches")
	# the next rocket rolls out over the weeks, then stands on the pad
	for k in LaunchPads.rollout_weeks() / 2:
		s.advance_week()
	await _frames(2)
	_check(pad1.rocket_progress > 0.3 and pad1.rocket_progress < 1.0, "half way: rolling out (%.2f)" % pad1.rocket_progress)
	for k in LaunchPads.rollout_weeks():
		s.advance_week()
	await create_timer(pad1.rollout_glide + 0.3).timeout
	_check(is_equal_approx(pad1.rocket_progress, 1.0) and _pad_rocket(pad1).visible
		and _pad_rocket(pad1).position.distance_to(Vector3(0, 1.15, 0)) < 0.01, "then a rocket stands on the pad again")
	await _close_all()
	# a second pad: launches alternate
	s.buildings["pad2"] = {"kind": "pad", "level": 1, "target": 1, "weeks_left": 0}
	s.changed.emit()
	await _frames(2)
	var pads_used: Array[String] = []

	# turned off in the settings: straight to the review
	LaunchSequence.set_enabled(false)
	_check(not LaunchSequence.enabled(), "the setting is stored")
	pads_used.append(_pad_of(s, _launch_project(s)))
	_check(main.hud.current_screen() != "launch", "no launch screen when turned off")
	_check(main.hud.current_screen() in ["project_review", "newspaper"], "the review opens directly")
	main.hud.close_screen()
	await _frames(3)
	main.hud.close_screen()
	await _frames(3)

	# Esc during the show also skips
	LaunchSequence.set_enabled(true)
	pads_used.append(_pad_of(s, _launch_project(s)))
	await _frames(3)
	seq = main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	_check(seq.pad_lot == pads_used[-1] and (seq.get_node("Stage") as Node3D).global_position.distance_to(
		main.campus.lot_position(seq.pad_lot)) < 0.1, "the stage moves to the pad the rocket leaves from (%s)" % seq.pad_lot)
	_check(main.campus.building_node(seq.pad_lot).rocket_held, "that pad's rocket is the one held off")
	_press(KEY_ESCAPE)
	await _frames(3)
	_check(main.hud.current_screen() == "launch" and seq.anim.current_animation == "result", "Esc skips to the card, the screen stays")
	# a screen closed from outside still restores everything
	main.hud.close_screen()
	await _frames(3)
	_check(not main.camera.is_cinematic(), "closing the screen gives the camera back")
	_check(main.hud.current_screen() != "launch", "the launch left the Screens layer")
	for i in 6:
		if main.hud.current_screen() == "":
			break
		main.hud.close_screen()
		await _frames(3)
	await _frames(10)
	# the card's Continue key leaves too; the review still follows (screens with transitions)
	pads_used.append(_pad_of(s, _launch_project(s)))
	_check(pads_used == ["pad2", "pad", "pad2"], "with two pads the launches alternate (%s)" % [pads_used])
	await _frames(3)
	seq = main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	_press(KEY_SPACE)
	await _frames(3)
	var card := seq.get_node("%Card" + seq.kind.capitalize()) as Control
	var cont := card.find_child("Continue", true, false) as Button
	_check(cont != null and cont.is_visible_in_tree(), "the card has a Continue key")
	_check(seq.camera.is_cinematic() and seq.camera.global_position.distance_to(seq.crew_cam.global_position) < 0.05,
		"the result shot is the crew camera")
	if cont:
		cont.pressed.emit()
	await _wait_closed("launch", 3.0)
	await _frames(3)
	_check(main.hud.current_screen() in ["project_review", "newspaper"], "Continue -> the review (or the newspaper) (got '%s')" % main.hud.current_screen())
	await _close_all()

	# big rockets: the crew shot keeps its size, the smoke grows in cubes, not in cube size;
	# a shot rig whose key shots are blocked gives way to the next one
	await _shot_rigs(s)

	# a launch while another decision is on screen: it waits, then comes before the newspaper
	await _queue_order(s, p.id)
	LaunchSequence.set_enabled(was_enabled)
	main.queue_free()
	await _frames(2)
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


## Starts a sounding with two free Cometlings and runs it to its launch.
func _launch_project(s: TycoonState) -> MissionProject:
	s.cash = maxf(s.cash, 5.0e6)
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = [String(free[0]["id"]), String(free[1]["id"])]
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", team)
	main.hud.close_screen()
	for k in 30:
		if ProjectDesk.find(s, p.id) == null:
			break
		ProjectDesk.set_sliders(s, p.id, [40, 30, 30])
		if main.hud.current_screen() == "project_phase":
			main.hud.close_screen()
		ProjectDesk.advance_week(s)
		_pass_review(s, p)
	return p


## The game holds a project for its Design Review (ProjectFlow turns the gate on): close the
## review screen and launch without fixes.
func _pass_review(s: TycoonState, p: MissionProject) -> void:
	if p.review_state != "waiting":
		return
	if main.hud.current_screen() == "design_review":
		main.hud.close_screen()
	ProjectDesk.confirm_review(s, p.id, [])


func _shot_rigs(s: TycoonState) -> void:
	var weeks0 := s.weeks
	s.weeks = 4 * 5 * 52 + 10  # era 5
	s.changed.emit()
	await _frames(3)
	# a big designed rocket (the cutscene shows the vessel that flies, at the flight's campus size)
	var r := {"project_id": "", "code": "T", "type": "lander", "target": "lunar_surface", "grade": 7.0,
		"success": true, "outcome": "full", "p_success": 0.8, "pad": "pad",
		"rocket": {"family": "", "name": "Grande", "parts": {"core": "core_hidra", "upper": "upper_hidra_5", "tank": "tank_l",
			"boosters": "boost_liquid2", "fairing": "fairing_l"}}}
	main.hud.open_screen("launch", {"result": r})
	await _frames(2)
	var seq := main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	_check(seq.shot_rig != "" and seq.shot_report.has("Front"), "a shot rig is chosen (%s %s)" % [seq.shot_rig, seq.shot_reasons])
	seq.anim.seek(3.6, true)
	await _frames(1)
	var crew_scale := seq.cam_rig.scale.x
	seq.anim.seek(1.0, true)
	await _frames(1)
	# a real vessel is slim: the rig grows with the square root of its height (vessel_rig_power)
	_check(seq._rig_size > 1.2 and absf(crew_scale - 1.0) < 0.01 and seq.cam_rig.scale.x > 1.2,
		"era 5: the establishing shot grows with the rocket (%.2f), the crew shot does not (%.2f)" % [seq.cam_rig.scale.x, crew_scale])
	var smoke := seq.get_node("Stage/Rocket/Engine/TrailSmoke") as GPUParticles3D
	var authored := (load("res://scenes/tycoon/launch/launch_sequence.tscn") as PackedScene).instantiate() as LaunchSequence
	var a_smoke := authored.get_node("Stage/Rocket/Engine/TrailSmoke") as GPUParticles3D
	var pm := smoke.process_material as ParticleProcessMaterial
	var a_pm := a_smoke.process_material as ParticleProcessMaterial
	var grow := pm.emission_sphere_radius / a_pm.emission_sphere_radius
	var cube := pm.scale_max / a_pm.scale_max
	_check(grow > 1.3 and cube < grow and smoke.amount > a_smoke.amount,
		"big rocket smoke: a %.2fx cloud of %.2fx cubes, %d of them (authored %d)" % [grow, cube, smoke.amount, a_smoke.amount])
	# the target shows: a lunar landing's trail takes the moon ramp and the stage lets go (keyed)
	var glow := seq.get_node("Stage/Rocket/Engine/TrailGlow") as GPUParticles3D
	_check((glow.process_material as ParticleProcessMaterial).color_ramp == seq.trail_ramps.get("lunar_surface")
		and seq.trail_ramps.has("leo") and seq.trail_ramps.has("geo") and seq.trail_ramps.has("comet"),
		"the trail takes the target's colour ramp (LEO, GEO, Moon, comet authored)")
	var keyed := false
	for an_name in ["flight_success", "flight_partial"]:
		var an := seq.anim.get_animation(an_name)
		for t in an.get_track_count():
			if an.track_get_type(t) == Animation.TYPE_METHOD:
				for k in an.track_get_key_count(t):
					keyed = keyed or an.method_track_get_name(t, k) == &"_stage_separation"
	var sep := seq.get_node("Stage/Rocket/Separation") as GPUParticles3D
	seq._stage_separation()
	_check(keyed and sep.emitting, "the stage separation is keyed in the climb and puffs")
	var warm_ramp := ((authored.get_node("Stage/Rocket/Engine/TrailGlow") as GPUParticles3D).process_material \
		as ParticleProcessMaterial).color_ramp
	authored.free()
	main.hud.close_screen()
	await _frames(3)
	var hop := r.duplicate()
	hop["target"] = "suborbital"
	main.hud.open_screen("launch", {"result": hop})
	await _frames(2)
	seq = main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	glow = seq.get_node("Stage/Rocket/Engine/TrailGlow") as GPUParticles3D
	sep = seq.get_node("Stage/Rocket/Separation") as GPUParticles3D
	seq._stage_separation()
	_check(not sep.emitting and (glow.process_material as ParticleProcessMaterial).color_ramp.resource_path
		== warm_ramp.resource_path and (glow.process_material as ParticleProcessMaterial).color_ramp != seq.trail_ramps["leo"],
		"a suborbital hop keeps the warm trail and drops no stage")
	main.hud.close_screen()
	await _frames(3)
	# a wall where the Front rig's crew shot stands
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(16, 12, 16)
	wall.mesh = box
	main.campus.get_node("Props").add_child(wall)
	wall.global_position = main.campus.lot_position("pad") + Vector3(18, 6, 22)
	main.hud.open_screen("launch", {"result": r})
	await _frames(2)
	seq = main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	_check(int(seq.shot_report.get("Front", 0)) > 0 and seq.shot_rig != "Front"
		and int(seq.shot_report.get(seq.shot_rig, 99)) < int(seq.shot_report.get("Front", 0)),
		"a blocked Front rig gives way to %s (%s)" % [seq.shot_rig, seq.shot_report])
	var rig := seq.get_node_or_null("ShotRigs/" + seq.shot_rig) as Node3D
	_check(rig != null and (seq.get_node("Stage") as Node3D).global_transform.is_equal_approx(seq.pad_frame * rig.transform),
		"the stage stands where that marker says")
	main.hud.close_screen()
	await _frames(3)
	wall.queue_free()
	s.weeks = weeks0
	s.changed.emit()
	await _close_all()


## LaunchPads on a bare state: which pad, alternation, the data's launch classes, rollout.
func _pad_rules() -> void:
	var s := TycoonState.new_campaign(7)
	_check(LaunchPads.pads(s) == ["pad"] and LaunchPads.pick(s, "sounding") == "pad", "one pad: it is the pad")
	s.buildings["pad2"] = {"kind": "pad", "level": 1, "target": 1, "weeks_left": 0}
	_check(LaunchPads.pick(s, "sounding") == "pad", "two fresh pads: the first one")
	LaunchPads.launched(s, "pad")
	_check(LaunchPads.rocket_progress(s, "pad") == 0.0, "a pad that launched stands empty")
	_check(LaunchPads.pick(s, "sounding") == "pad2", "the next launch takes the pad with a rocket on it")
	LaunchPads.launched(s, "pad2")
	_check(LaunchPads.pick(s, "sounding") == "pad", "both rolling out: the one that launched longest ago")
	s.weeks += 1
	LaunchPads.advance_week(s)
	var half := LaunchPads.rocket_progress(s, "pad")
	_check(half > 0.0 and half < 1.0, "the rollout advances by the week (%.2f)" % half)
	for k in LaunchPads.rollout_weeks():
		LaunchPads.advance_week(s)
	_check(LaunchPads.rocket_progress(s, "pad") == 1.0 and LaunchPads.rocket_progress(s, "pad2") == 1.0, "rolled out")
	# the data may give a pad to launch classes
	s.bdata["lots"]["pad2"]["launch_classes"] = ["heavy", "lunar"]
	LaunchPads.launched(s, "pad2")
	_check(LaunchPads.pick(s, "lunar") == "pad2", "a class the data gives to a pad goes there (even while rolling out)")
	_check(LaunchPads.pick(s, "sounding") == "pad", "other classes take the pad open to any class")
	s.bdata["lots"]["pad2"].erase("launch_classes")
	s.buildings["pad2"]["level"] = 0
	_check(LaunchPads.pick(s, "lunar") == "pad", "an unbuilt pad is never picked")


func _pad_of(s: TycoonState, p: MissionProject) -> String:
	return String(ProjectDesk.history_entry(s, p.id).get("pad", ""))


func _pad_rocket(b: CampusBuilding) -> Node3D:
	return b.get_node("Era%d/Level1/Rocket" % b.era) as Node3D


## A review is up when a project launches and the race prints a front page: the launch waits
## first in the queue, the paper waits for it, and closing the review opens the launch, then
## the new review, then the paper.
func _queue_order(s: TycoonState, old_id: String) -> void:
	main.hud.open_screen("project_review", {"project_id": old_id})
	await _frames(2)
	s.cash = maxf(s.cash, 5.0e6)
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = [String(free[0]["id"]), String(free[1]["id"])]
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", team)
	for k in 30:
		if ProjectDesk.find(s, p.id) == null:
			break
		ProjectDesk.set_sliders(s, p.id, [40, 30, 30])
		ProjectDesk.advance_week(s)
		if p.review_state == "waiting":
			ProjectDesk.confirm_review(s, p.id, [])  # the review screen waits in the queue behind the open review
	_check(main.hud.current_screen() == "project_review", "the open review stays while the project launches")
	var q := flow.queued()
	_check(q.size() >= 2 and q[0] == "launch" and q[1] == "project_review",
		"the launch and its review lead the queue, ahead of the waiting phase screens (%s)" % [q])
	_check(flow.has_waiting_launch(), "the flow says a launch waits")
	s.race.pending_pages.append({"kind": "fail", "milestone": "crewed_flyby", "by": "aurora", "months": 5, "week": s.weeks, "issue": 99})
	main.race_flow._next_page()
	_check(main.hud.current_screen() == "project_review", "the paper does not jump in while the launch waits")
	main.hud.close_screen()
	await _frames(4)
	_check(main.hud.current_screen() == "launch", "closing the review opens the launch, not the paper (got '%s')" % main.hud.current_screen())
	_press(KEY_SPACE)
	await _frames(3)
	_press(KEY_SPACE)
	await _wait_closed("launch", 3.0)
	await _frames(4)
	_check(main.hud.current_screen() == "project_review", "then the new review (got '%s')" % main.hud.current_screen())
	main.hud.close_screen()
	await _frames(4)
	_check(main.hud.current_screen() == "newspaper", "then the paper (got '%s')" % main.hud.current_screen())
	await _close_all()


func _close_all() -> void:
	for i in 8:
		if main.hud.current_screen() == "":
			break
		main.hud.close_screen()
		await _frames(3)
	await _frames(10)


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _wait_closed(screen: String, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while main.hud.current_screen() == screen and Time.get_ticks_msec() < end:
		await process_frame


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
