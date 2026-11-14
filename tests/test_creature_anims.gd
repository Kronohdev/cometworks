extends SceneTree
## Headless tests for the Cometling animation set (src/npc/creature.gd):
##   - the public API stays backwards compatible (old actions, exports, methods)
##   - every loop action and one-shot plays for a few seconds with finite transforms,
##     at 60 fps and with long LOD frames; one-shots finish and emit action_finished
##   - walking, running and turning; stationary loops keep walking legs
##   - expressions (timed and cleared), mood extremes with idle habits, react() events, poke()
##   - the sleep loop snores (zzz bubble)
##   - cost: 48 Cometlings stepped together, microseconds per Cometling per frame
## Run: godot --headless --path . --script res://tests/test_creature_anims.gd

const CREATURE := preload("res://scenes/npc/creature.tscn")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	await _test_api()
	await _test_actions()
	await _test_walk()
	await _test_faces_and_mood()
	await _test_reactions()
	await _test_cost()
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  FAIL: ", what)


func _spawn(seed_v := 7) -> Cometling:
	var c := CREATURE.instantiate() as Cometling
	c.listen_to_events = false
	c.personality_seed = seed_v
	get_root().add_child(c)
	c.paused = true
	return c


func _finite(c: Cometling) -> bool:
	for n in [c.rig, c.hips, c.neck, c.arm_l, c.arm_r, c.foot_l, c.foot_r, c.ear_l, c.ear_r, c.antenna,
			c.bulb, c.tail, c.eye_l, c.eye_r, c.lid_l, c.lid_r, c.mouth]:
		var t: Transform3D = (n as Node3D).transform
		if not (t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite()):
			return false
		if t.origin.length() > 3.0:
			return false
	return true


func _run(c: Cometling, seconds: float, dt := 1.0 / 60.0) -> bool:
	var ok := true
	var t := 0.0
	while t < seconds:
		c.advance(dt)
		t += dt
		if not _finite(c):
			ok = false
	return ok


# ------------------------------------------------------------------ API
func _test_api() -> void:
	print("api")
	for a in ["idle", "sit", "look_up", "work_hammer", "work_scan", "carry", "clipboard", "talk", "dance"]:
		_ok(a in Cometling.LOOP_ACTIONS, "old loop '%s' still there" % a)
	for a in ["wave", "cheer", "jump", "surprise", "nod", "spin"]:
		_ok(Cometling.ONESHOTS.has(a), "old one-shot '%s' still there" % a)
	for a in ["sleep", "think", "sad", "work_type", "work_wrench"]:
		_ok(a in Cometling.LOOP_ACTIONS, "new loop '%s'" % a)
	for a in ["hop", "clap", "celebrate", "startled", "point", "salute", "bow", "shrug", "laugh", "sigh",
			"shake_head", "yawn", "stretch"]:
		_ok(Cometling.ONESHOTS.has(a), "new one-shot '%s'" % a)
	_ok(Cometling.all_actions().size() == Cometling.LOOP_ACTIONS.size() + Cometling.ONESHOTS.size(), "all_actions lists all")
	_ok(Cometling.has_action("dance") and not Cometling.has_action("moonwalk"), "has_action")
	var c := _spawn()
	await process_frame
	for prop in ["role", "body_color", "spot_color", "glow_color", "body_material", "personality_seed",
			"start_action", "listen_to_events", "animate_in_editor", "cull_distance", "lod_distance",
			"mood", "fidgets", "walk_bounce", "detail_distance"]:
		_ok(prop in c, "export '%s'" % prop)
	for m in ["play", "play_sequence", "current_action", "is_busy", "look_at_point", "clear_look", "react",
			"show_emote", "set_colors", "effective_glow", "advance", "set_move_velocity", "set_expression",
			"clear_expression", "current_expression", "poke", "stop_shot"]:
		_ok(c.has_method(m), "method '%s'" % m)
	c.set_colors(Color.RED, Color.BLUE, Color.GREEN)
	_ok(c.effective_glow() == Color.GREEN, "set_colors glow")
	c.role = "engineer"
	_ok((c.find_child("HardHat", true, false) as Node3D).visible, "role accessory")
	c.queue_free()
	await process_frame


# ------------------------------------------------------------------ every action
func _test_actions() -> void:
	print("actions")
	var c := _spawn()
	await process_frame
	var finished: Array[String] = []
	c.action_finished.connect(func(a: String) -> void: finished.append(a))
	for a in Cometling.LOOP_ACTIONS:
		c.play("idle")
		c.play(a)
		_ok(c.current_action() == a, "loop %s is current" % a)
		_ok(_run(c, 3.0), "loop %s finite at 60 fps" % a)
		_ok(_run(c, 2.0, 0.1), "loop %s finite with long frames" % a)
	c.play("idle")
	for a in Cometling.ONESHOTS:
		finished.clear()
		c.play(a)
		_ok(c.is_busy(), "one-shot %s busy" % a)
		_ok(_run(c, float(Cometling.ONESHOTS[a]) + 0.3), "one-shot %s finite" % a)
		_ok(not c.is_busy() and a in finished, "one-shot %s finished and signalled" % a)
		# over every loop too (a one-shot is layered on top)
	var all_ok := true
	for loop in Cometling.LOOP_ACTIONS:
		c.play(loop)
		for a in Cometling.ONESHOTS:
			c.play(a)
			if not _run(c, 0.5, 1.0 / 30.0):
				all_ok = false
	_ok(all_ok, "every one-shot over every loop stays finite")
	# a custom duration and a sequence
	c.play("idle")
	c.play("clap", 4.0)
	_run(c, 3.0)
	_ok(c.current_action() == "clap", "clap with a long duration keeps clapping")
	_run(c, 1.2)
	_ok(c.current_action() == "idle", "clap ends after its duration")
	c.play_sequence(["hop", "laugh", "bow"])
	_run(c, 1.0)
	_ok(c.current_action() == "laugh", "sequence moves on")
	c.stop_shot()
	_ok(not c.is_busy(), "stop_shot clears the queue")
	c.queue_free()
	await process_frame


# ------------------------------------------------------------------ walking
func _test_walk() -> void:
	print("walk / run / turn")
	var holder := Node3D.new()
	get_root().add_child(holder)
	holder.scale = Vector3.ONE * 1.6
	var c := CREATURE.instantiate() as Cometling
	c.listen_to_events = false
	holder.add_child(c)
	c.paused = true
	await process_frame
	var ok := true
	for speed in [0.3, 1.2, 2.4, 4.0]:
		for i in 120:
			holder.rotation.y += 0.03
			c.set_move_velocity(holder.global_basis.z * speed)
			c.advance(1.0 / 60.0)
			if not _finite(c):
				ok = false
	_ok(ok, "walk / run / turn finite")
	# running leans forward more than walking
	c.set_move_velocity(holder.global_basis.z * 0.8)
	_run(c, 1.5)
	var lean_walk := c._sp_lean.x
	c.set_move_velocity(holder.global_basis.z * 4.0)
	_run(c, 1.5)
	var lean_run := c._sp_lean.x
	_ok(lean_run > lean_walk + 0.05, "running leans further (%.2f > %.2f)" % [lean_run, lean_walk])
	# stopping overshoots the lean (spring) before settling
	c.set_move_velocity(Vector3.ZERO)
	var min_lean := 9.0
	for i in 90:
		c.advance(1.0 / 60.0)
		min_lean = minf(min_lean, c._sp_lean.x)
	var max_lean := -9.0
	c.set_move_velocity(holder.global_basis.z * 1.5)
	_run(c, 1.5)
	c.set_move_velocity(Vector3.ZERO)
	for i in 90:
		c.advance(1.0 / 60.0)
		max_lean = maxf(max_lean, c._sp_lean.x)
		min_lean = minf(min_lean, c._sp_lean.x)
	_ok(max_lean > 0.15 and min_lean < -0.01, "stopping tips forward then rocks back (%.3f / %.3f)" % [max_lean, min_lean])
	# a stationary loop played while walking keeps the walking legs (sit does not drag)
	c.play("sit")
	c.set_move_velocity(holder.global_basis.z * 1.2)
	_run(c, 1.0)
	_ok(c.rig.position.y > -0.05, "sitting while walking keeps the walk height")
	holder.queue_free()
	await process_frame


# ------------------------------------------------------------------ faces, mood, habits
func _test_faces_and_mood() -> void:
	print("faces / mood / habits")
	var c := _spawn(11)
	await process_frame
	for e in Cometling.EXPRESSIONS:
		c.set_expression(e)
		_ok(_run(c, 0.6), "expression %s finite" % e)
		_ok(c.current_expression() == e, "expression %s current" % e)
	c.set_expression("sad")
	_run(c, 0.5)
	_ok(c.mouth_smile.visible and absf(c.mouth_smile.transform.basis.get_euler().z) > 3.0, "sad face frowns")
	_ok(c.lid_l.visible, "sad face shows the lids")
	c.set_expression("joy", 0.5)
	_run(c, 0.4)
	_ok(c.happy_l.visible and c.mouth_open.visible, "joy: happy eyes, open mouth")
	_run(c, 0.8)
	_ok(c.current_expression() == "neutral", "timed expression wears off")
	c.clear_expression()
	# mood extremes with habits: everything stays finite and habits do happen
	for m in [-1.0, 0.0, 1.0]:
		c.mood = m
		c.play("idle")
		var habits := {}
		var ok := true
		for i in 60 * 40:
			c.advance(1.0 / 60.0)
			if c._fid_last != "":
				habits[c._fid_last] = true
			if c.is_busy():
				habits[c.current_action()] = true
			if i % 10 == 0 and not _finite(c):
				ok = false
		_ok(ok, "mood %.0f idle finite" % m)
		_ok(habits.size() >= 3, "mood %.0f: idle habits play (%s)" % [m, ", ".join(habits.keys())])
	c.mood = 0.0
	# sleep snores
	c.play("sleep")
	var zzz := false
	for i in 60 * 5:
		c.advance(1.0 / 60.0)
		if c.emote_sprite.visible and c.emote_sprite.frame == Cometling.EMOTES.find("zzz"):
			zzz = true
	_ok(zzz, "sleep shows zzz")
	_ok(not c.eye_l.visible or c.eye_l.scale.y < 0.3, "sleep closes the eyes")
	c.queue_free()
	await process_frame


# ------------------------------------------------------------------ reactions
func _test_reactions() -> void:
	print("reactions")
	var c := _spawn(3)
	await process_frame
	var ok := true
	for ev in ["part_placed", "part_removed", "vessel_cleared", "launch", "success", "failure", "hello",
			"staged", "level_up", "hired", "good_news", "bad_news", "idea", "tired", "scared", "poke", "???"]:
		c.react(ev)
		if not _run(c, 4.0, 1.0 / 30.0):
			ok = false
	_ok(ok, "every reaction finite")
	for i in 12:
		c.poke()
		if not _run(c, 2.5, 1.0 / 30.0):
			ok = false
	_ok(ok, "poke finite")
	c.queue_free()
	await process_frame


# ------------------------------------------------------------------ cost
func _test_cost() -> void:
	print("cost")
	var crowd: Array[Cometling] = []
	for i in 48:
		var c := _spawn(100 + i)
		c.position = Vector3((i % 8) * 1.2, 0, (i / 8) * 1.2)
		crowd.append(c)
	await process_frame
	var loops := Cometling.LOOP_ACTIONS
	for i in crowd.size():
		crowd[i].play(String(loops[i % loops.size()]))
		if i % 3 == 0:
			crowd[i].set_move_velocity(Vector3(0, 0, 1.0))
	for c in crowd:
		c.advance(1.0 / 60.0)
	var frames := 240
	var t0 := Time.get_ticks_usec()
	for f in frames:
		for c in crowd:
			c.advance(1.0 / 60.0)
	var us := float(Time.get_ticks_usec() - t0) / float(frames * crowd.size())
	print("  %.1f us per Cometling per frame (%d Cometlings, %d frames)" % [us, crowd.size(), frames])
	_ok(us < 400.0, "animation cost stays small (%.1f us)" % us)
	for c in crowd:
		c.queue_free()
	await process_frame
