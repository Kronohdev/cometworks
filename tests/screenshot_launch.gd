extends SceneTree
## Windowed screenshots of the launch sequence (scenes/tycoon/launch/launch_sequence.tscn) on
## the Cometworks main screen, through the real HUD screen "launch":
##   launch_<kind>_e<era>_<moment>   moments: count1 (establishing), count2 (the crew),
##       count3 (low pad view), ignite, lift, climb, arc, high, card; for fail: cough, poof, card
##   launch_rollout_e<era>_<pct>   kind "rollout": the pad after a launch, the next rocket rolling out
## Every lot is built, so the campus has two pads; [pad] picks the one the rocket leaves from
## (default: the one LaunchPads picks).
## Prints the average frame time during the flight.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_launch.gd -- <out_dir> [kinds] [eras] [en|pt] [pad]
##   e.g. -- out success,partial,fail 1,3 pt pad2   (kind "perf": frame times of a launch, no shots)

## [shot, animation, seconds into it]
const MOMENTS := {
	"success": [["count1", "countdown", 1.0], ["count2", "countdown", 3.6], ["count3", "countdown", 5.6],
		["ignite", "countdown", 6.6], ["lift", "flight_success", 0.9], ["climb", "flight_success", 1.9],
		["arc", "flight_success", 3.6], ["high", "flight_success", 6.6], ["card", "result", 2.0]],
	"partial": [["lift", "flight_partial", 1.0], ["sputter", "flight_partial", 2.9], ["arc", "flight_partial", 5.0],
		["card", "result", 2.0]],
	"fail": [["ignite", "countdown", 6.7], ["climb", "flight_fail", 1.5], ["cough", "flight_fail", 2.7],
		["poof", "flight_fail", 3.85], ["after", "flight_fail", 5.0], ["card", "result", 2.0]],
}

var out_dir := "user://"
var main: TycoonMain
var pad := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var kinds := ["success", "fail"]
	if args.size() > 1:
		kinds = Array(args[1].split(","))
	var eras := [1]
	if args.size() > 2:
		eras = Array(args[2].split(",")).map(func(x: String) -> int: return int(x))
	if args.size() > 3:
		TranslationServer.set_locale(args[3])
	if args.size() > 4:
		pad = args[4]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	var s := main.state
	var cycle := main.get_node_or_null("DayCycle") as CampusDayCycle
	if cycle:
		cycle.force_phase = 0.12
	for era: int in eras:
		s.weeks = (era - 1) * 5 * 52 + 10
		var lv := {1: 1, 2: 2, 3: 3, 4: 3, 5: 3}[era] as int
		for lot: String in s.lot_ids():
			s.buildings[lot] = {"kind": s.lot_kind(lot), "level": lv, "target": lv, "weeks_left": 0}
		s.changed.emit()
		await _frames(30)
		for kind: String in kinds:
			if kind == "perf":
				await _perf(era)
			elif kind == "rollout":
				await _rollout(era)
			elif kind == "targets":
				await _targets(era)
			elif kind == "blocked":
				# a wall of trees where the Front rig's crew shot stands: another ShotRigs marker takes over
				var wall := _tree_wall(pad if pad != "" else "pad")
				await _run("success", era, "launch_blocked")
				wall.queue_free()
			elif kind == "settings":
				main.hud.open_screen("settings")
				await _frames(20)
				await _shot("launch_settings_toggle")
				main.hud.close_screen()
			else:
				await _run(kind, era)
	print("LAUNCH SCREENSHOTS DONE")
	quit()


func _run(kind: String, era: int, prefix := "launch") -> void:
	var outcome := {"success": "full", "partial": "partial", "fail": "fail"}[kind] as String
	var r := {"project_id": "", "code": "SND-0%d" % era, "type": "sounding" if era < 3 else "orbiter",
		"target": "suborbital" if era < 3 else "lunar_orbit", "grade": 7.4 if kind != "fail" else 4.1,
		"success": kind != "fail", "outcome": outcome, "p_success": 0.82}
	if pad != "":
		r["pad"] = pad
	main.hud.open_screen("launch", {"result": r})
	var seq := main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	print("%s e%d: pad %s, shot rig %s %s" % [kind, era, seq.pad_lot, seq.shot_rig, seq.shot_reasons])
	var t0 := Time.get_ticks_msec() / 1000.0
	var frames0 := Engine.get_frames_drawn()
	for m: Array in MOMENTS[kind]:
		while not (seq.anim.current_animation == m[1] and seq.anim.current_animation_position >= float(m[2])):
			await process_frame
		await _shot("%s_%s_e%d_%s" % [prefix, kind, era, m[0]])
	var dt := Time.get_ticks_msec() / 1000.0 - t0
	print("%s e%d: %.1f fps average" % [kind, era, (Engine.get_frames_drawn() - frames0) / dt])
	# leave through the card (a click), then wait for the HUD to come back
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(1.6).timeout
	await _shot("%s_%s_e%d_back" % [prefix, kind, era])
	if main.hud.current_screen() != "":
		main.hud.close_screen()
	await _frames(20)


## The pad after a launch: empty, then the next rocket rolled out on its crawler.
func _rollout(era: int) -> void:
	var lot := pad if pad != "" else "pad"
	var b := main.campus.building_node(lot)
	b.rollout_glide = 0.0
	main.camera.frame_area(main.campus.lot_position(lot), Vector2(26, 26))
	for p: float in [0.1, 0.5, 0.75, 1.0]:
		b.set_rocket_progress(p)
		await _frames(40)
		await _shot("launch_rollout_e%d_%d" % [era, int(p * 100)])


## The target on the way up: the trail's colour and the stage separation, one launch per target
## (launch_target_e<era>_<target>, just after the stage lets go).
func _targets(era: int) -> void:
	for target: String in ["suborbital", "leo", "geo", "lunar_orbit", "comet"]:
		var r := {"project_id": "", "code": "TGT", "type": "orbiter", "target": target, "grade": 7.0,
			"success": true, "outcome": "full", "p_success": 0.8}
		if pad != "":
			r["pad"] = pad
		main.hud.open_screen("launch", {"result": r})
		var seq := main.hud.get_node("%Screens").get_child(0) as LaunchSequence
		seq.anim.play("flight_success")
		seq.anim.seek(4.6, true)
		while not (seq.anim.current_animation == "flight_success" and seq.anim.current_animation_position >= 5.7):
			await process_frame
		await _shot("launch_target_e%d_%s" % [era, target])
		main.hud.close_screen()
		await _frames(20)


## A grove of big trees (the campus' own tree mesh) right where the Front rig puts the crew shot.
func _tree_wall(lot: String) -> Node3D:
	var grove := Node3D.new()
	main.campus.get_node("Props").add_child(grove)
	var tree := main.campus.get_node("Nature/Trees/RoundA") as MultiMeshInstance3D
	var base := main.campus.lot_position(lot)
	for i in 7:
		var mi := MeshInstance3D.new()
		mi.mesh = tree.multimesh.mesh
		grove.add_child(mi)
		mi.global_position = base + Vector3(11.0 + i * 1.6, 0, 22.0 - i * 1.4)
		mi.scale = Vector3.ONE * 2.4
	return grove


## A whole success launch without screenshots: average and worst frame (the "perf" kind).
func _perf(era: int) -> void:
	var r := {"project_id": "", "code": "PERF", "type": "sounding", "target": "suborbital", "grade": 7.0,
		"success": true, "outcome": "full", "p_success": 0.8}
	if pad != "":
		r["pad"] = pad
	main.hud.open_screen("launch", {"result": r})
	var seq := main.hud.get_node("%Screens").get_child(0) as LaunchSequence
	print("perf e%d: pad %s, shot rig %s %s" % [era, seq.pad_lot, seq.shot_rig, seq.shot_reasons])
	var worst := 0.0
	var total := 0.0
	var n := 0
	var last := Time.get_ticks_usec()
	while seq.anim.current_animation != "result":
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		if n > 5:
			worst = maxf(worst, dt)
			total += dt
		n += 1
	print("perf e%d: %.2f ms average, %.2f ms worst over %d frames" % [era, total / maxf(n - 6, 1), worst, n])
	main.hud.close_screen()
	await _frames(20)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
