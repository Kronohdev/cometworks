extends SceneTree
## Headless checks for the story cutscenes (src/cutscene/, scenes/cutscenes/):
##   - every cutscene and shot scene loads, every shot has the animation its cutscene plays,
##     the opening runs 60-90 s in 5-8 shots and the fair-mode version about 15 s
##   - every line, card and kicker key (and the frame's own keys) exists in pt and en
##   - a tap finishes the line, then jumps to the next line (or shot); holding the key or the
##     Skip button skips the whole cutscene
##   - the game is paused while it plays and picks up again afterwards (the campaign clock
##     does not move), and the 3D behind comes back
##   - it plays once per campaign (TycoonState.story, saved with the campaign), the pause
##     menu can replay it, and the setting turns the story scenes off
##   - the tycoon opens with the opening when the leader creator asks for it, and only then
##   - when the comet passes, the ending plays before the finale screen: the rendezvous if the
##     player's comet mission met the Mother-Ice, the bittersweet one if not
## Run: godot --headless --path . --script res://tests/test_cutscenes.gd

const TYCOON := "res://scenes/tycoon/tycoon_main.tscn"
const LEADER := {"name": "Estrela", "body": "#ffa3a3", "spot": "#ffcc55", "hat": "crown",
	"profession": "pilot", "agency_name": "Cauda Brilhante"}

var _failures := 0
var _setting_before := true


func _initialize() -> void:
	await process_frame
	_setting_before = Cutscenes.enabled()
	Cutscenes.set_enabled(true)
	_scenes()
	_keys()
	await _skipping()
	await _pause_and_once()
	await _setting()
	await _tycoon_opening()
	await _ending(true)
	await _ending(false)
	Cutscenes.set_enabled(_setting_before)
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)


func _wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _cutscene(id: String) -> Cutscene:
	return (load(Cutscenes.path(id)) as PackedScene).instantiate() as Cutscene


# ------------------------------------------------------------ scenes
func _scenes() -> void:
	print("scenes")
	for id: String in Cutscenes.ALL:
		var c := _cutscene(id)
		_check(c != null and not c.shots.is_empty(), "%s loads with its shots" % id)
		if c == null:
			continue
		var total := 0.0
		for path: String in c.shots:
			var shot := (load(path) as PackedScene).instantiate() as CutsceneShot
			var ok := shot != null and shot.animation_player != null and shot.animation_player.has_animation(c.shot_animation) \
				and shot.camera != null and not shot.path.is_empty()
			_check(ok, "  %s: a CutsceneShot with a camera path and the \"%s\" animation" % [path.get_file(), c.shot_animation])
			if ok:
				total += shot.animation_player.get_animation(c.shot_animation).length
			if shot:
				shot.free()
		print("    %s: %d shots, %.1f s" % [id, c.shots.size(), total])
		if id == Cutscenes.OPENING:
			_check(c.shots.size() >= 5 and c.shots.size() <= 8 and total >= 60.0 and total <= 90.0,
				"the opening runs 60-90 s in 5-8 shots (%.1f s, %d shots)" % [total, c.shots.size()])
		elif id == Cutscenes.OPENING_SHORT:
			_check(total >= 10.0 and total <= 18.0, "the fair-mode opening runs about 15 s (%.1f s)" % total)
		c.free()


# ------------------------------------------------------------ translations
func _keys() -> void:
	print("keys")
	var keys := {"CS_SKIP": true, "CS_HINT": true, "CS_LEADER_FALLBACK": true, "TY_SET_CUTSCENES": true,
		"TY_SET_CUTSCENES_TIP": true, "TY_SET_REPLAY_OPENING": true, "TY_SET_REPLAY_OPENING_TIP": true}
	for id: String in Cutscenes.ALL:
		var c := _cutscene(id)
		for path: String in c.shots:
			var shot := (load(path) as PackedScene).instantiate() as CutsceneShot
			var lib := shot.animation_player
			for an: StringName in lib.get_animation_list():
				var anim := lib.get_animation(an)
				for i in anim.get_track_count():
					if anim.track_get_type(i) != Animation.TYPE_METHOD:
						continue
					for k in anim.track_get_key_count(i):
						var m := anim.method_track_get_name(i, k)
						if m in [&"say", &"card"]:
							for a: Variant in anim.method_track_get_params(i, k):
								if a is String and String(a) != "" and not String(a).begins_with("{"):
									keys[String(a)] = true
			shot.free()
		c.free()
	var missing: Array[String] = []
	for lang in ["pt", "en"]:
		TranslationServer.set_locale(lang)
		for key: String in keys:
			if tr(key) == key:
				missing.append("%s:%s" % [lang, key])
	_check(missing.is_empty(), "%d keys exist in pt and en %s" % [keys.size(), str(missing) if not missing.is_empty() else ""])
	TranslationServer.set_locale("pt")
	var f := _cutscene(Cutscenes.OPENING_SHORT)
	f.leader = {"name": "Estrela"}
	f.agency = "Cauda Brilhante"
	_check(f.fill(tr("CS_OPEN_13")) == "Estrela, a Cauda Brilhante é sua. Vamos levar todo mundo para casa!",
		"lines take the leader's and the agency's names")
	f.leader = {}
	_check(f.fill("{leader}").begins_with(tr("CS_LEADER_FALLBACK")), "without a leader the line says \"Chefe\"")
	f.free()


# ------------------------------------------------------------ skipping
func _skipping() -> void:
	print("skipping")
	var host := Node.new()
	root.add_child(host)
	var c := Cutscenes.play(host, Cutscenes.OPENING, null, true)
	_check(c != null and Cutscenes.is_playing(), "the opening plays (replay, no campaign)")
	var done := [false, false]
	c.finished.connect(func(skipped: bool) -> void:
		done[0] = true
		done[1] = skipped)
	await _until(func() -> bool: return c.shot != null and c.shot.time > 0.2, 5.0)
	_check(c.index == 0 and c.current_line() == "", "the first shot opens on its title card")
	await _tap(KEY_SPACE)
	await _until(func() -> bool: return c.current_line() == "CS_OPEN_1", 2.0)
	_check(c.current_line() == "CS_OPEN_1" and c.index == 0, "a tap jumps to the next line (%s)" % c.current_line())
	await _tap(KEY_SPACE)   # the line is still typing: the tap shows it whole
	_check(not c._typing and c.line_label.visible_characters == -1, "a tap finishes the typing")
	await _tap(KEY_SPACE)   # no more lines in this shot: the next shot
	await _until(func() -> bool: return c.index == 1 and c.current_line() != "", 4.0)
	_check(c.index == 1 and c.current_line() == "CS_OPEN_2", "after the last line a tap cuts to the next shot (%d, %s)" % [c.index, c.current_line()])
	# hold Esc: the whole cutscene goes
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.pressed = true
	root.push_input(down)
	await _wait(c.hold_to_skip * 0.5)
	_check(not done[0] and c.hold_fill.scale.x > 0.0, "holding the key fills the skip ring")
	await _until(func() -> bool: return done[0], c.hold_to_skip + 4.0)
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.pressed = false
	root.push_input(up)
	_check(done[0] and done[1], "holding the key skips the whole cutscene")
	await _frames(2)
	_check(not is_instance_valid(c) and not Cutscenes.is_playing(), "the cutscene is gone afterwards")
	# the Skip button
	var c2 := Cutscenes.play(host, Cutscenes.ENDING_MISSED, null, true)
	var done2 := [false]
	c2.finished.connect(func(_s: bool) -> void: done2[0] = true)
	await _until(func() -> bool: return c2.shot != null, 5.0)
	c2.skip_button.pressed.emit()
	await _until(func() -> bool: return done2[0], 4.0)
	_check(done2[0], "the Skip button skips it")
	host.queue_free()
	await _frames(2)


func _tap(key: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = key
	down.pressed = true
	root.push_input(down)
	await _frames(2)
	var up := InputEventKey.new()
	up.keycode = key
	up.pressed = false
	root.push_input(up)
	await _frames(3)


## Waits until `node` is freed (at most 4 s).
func _gone(node: Object) -> void:
	var wr: WeakRef = weakref(node)
	node = null
	await _until(func() -> bool: return wr.get_ref() == null, 4.0)


func _until(cond: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()) and Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		await process_frame


# ------------------------------------------------------------ pause, once per campaign
func _pause_and_once() -> void:
	print("pause and once per campaign")
	var host := Node3D.new()
	root.add_child(host)
	var s := TycoonState.new_campaign(11)
	TycoonLeader.found(s, LEADER)
	_check(not Cutscenes.seen(s, Cutscenes.OPENING), "a new campaign has not seen the opening")
	var c := Cutscenes.play(host, Cutscenes.OPENING, s)
	_check(c != null and paused, "the game is paused while it plays")
	_check(Cutscenes.seen(s, Cutscenes.OPENING) and Cutscenes.seen(s, Cutscenes.OPENING_SHORT), "the campaign marks the opening as seen")
	_check(Cutscenes.play(host, Cutscenes.OPENING_SHORT, s, true) == null, "only one cutscene plays at a time")
	await _until(func() -> bool: return c.shot != null, 5.0)
	_check(host.get_viewport().disable_3d, "the 3D behind is off while it plays")
	_check(c.leader.get("name", "") == "Estrela" and c.agency == "Cauda Brilhante", "it is about the campaign's leader and agency")
	c.skip_all()
	await _gone(c)
	_check(not paused, "the game goes on afterwards")
	_check(not host.get_viewport().disable_3d, "the 3D behind is back")
	_check(Cutscenes.play(host, Cutscenes.OPENING, s) == null, "it does not play twice in a campaign")
	_check(Cutscenes.play(host, Cutscenes.OPENING_SHORT, s) == null, "nor its short version")
	var loaded := TycoonState.from_dict(JSON.parse_string(JSON.stringify(TycoonSave.encode(s.to_dict()))))
	_check(Cutscenes.seen(loaded, Cutscenes.OPENING), "the story beats are saved with the campaign")
	var r := Cutscenes.play(host, Cutscenes.OPENING, s, true)
	_check(r != null, "the pause menu can replay it")
	if r:
		r.skip_all()
		await _gone(r)
	# the replay button of the pause menu
	var settings := (load("res://scenes/tycoon/ui/screens/settings.tscn") as PackedScene).instantiate()
	_check(settings.has_node("%Cutscenes") and settings.has_node("%ReplayOpening"),
		"the settings hold the story toggle and the replay button")
	_check((settings.get_node("%Cutscenes") as Node).get_parent() == (settings.get_node("%LaunchCinematic") as Node).get_parent(),
		"next to the launch cinematic")
	settings.free()
	host.queue_free()
	await _frames(2)


func _setting() -> void:
	print("setting")
	var host := Node.new()
	root.add_child(host)
	Cutscenes.set_enabled(false)
	_check(not Cutscenes.enabled(), "the setting turns the story scenes off")
	var s := TycoonState.new_campaign(12)
	_check(Cutscenes.play(host, Cutscenes.OPENING, s) == null and not paused, "nothing plays while it is off")
	_check(not Cutscenes.seen(s, Cutscenes.OPENING), "and the campaign has not seen it")
	Cutscenes.set_enabled(true)
	_check(Cutscenes.enabled(), "and back on")
	host.queue_free()
	await _frames(2)


# ------------------------------------------------------------ the tycoon flow
func _main(intro: String) -> TycoonMain:
	var main := (load(TYCOON) as PackedScene).instantiate() as TycoonMain
	main.leader = LEADER.duplicate()
	main.intro_cutscene = intro
	root.add_child(main)
	return main


func _tycoon_opening() -> void:
	print("the tycoon opens with the story")
	var plain := _main("")
	await _frames(4)
	plain.race_flow.autosave = false
	_check(not Cutscenes.is_playing() and not paused, "a tycoon scene without intro_cutscene plays nothing")
	plain.queue_free()
	await _frames(3)
	var main := _main(Cutscenes.OPENING)
	await _frames(4)
	main.race_flow.autosave = false
	_check(Cutscenes.is_playing() and Cutscenes.current.id == Cutscenes.OPENING, "the leader creator's campaign opens with the opening")
	_check(paused, "the campus waits while it plays")
	var weeks := main.state.weeks
	await _wait(1.5)
	_check(main.state.weeks == weeks, "the campaign clock does not move during the story")
	var c := Cutscenes.current
	c.skip_all()
	await _gone(c)
	_check(not paused and main.clock.speed > 0, "then the campus runs")
	_check(Cutscenes.seen(main.state, Cutscenes.OPENING), "the campaign remembers it")
	var src := FileAccess.get_file_as_string("res://src/tycoon/ui/leader_creator.gd")
	_check(src.contains("\"intro_cutscene\", Cutscenes.OPENING"), "the leader creator asks for the opening")
	_check(FileAccess.get_file_as_string("res://src/menu/main_menu.gd").contains("Cutscenes.OPENING_SHORT"), "fair mode asks for the short one")
	main.queue_free()
	await _frames(3)


func _ending(met: bool) -> void:
	print("the ending (%s)" % ("met the comet" if met else "missed it"))
	var main := _main("")
	await _frames(4)
	main.race_flow.autosave = false
	main.clock.set_speed(0)
	var s := main.state
	if met:
		s.mission_completed.emit({"type": "comet_mission", "target": "comet", "success": true, "outcome": "full"})
		_check(s.race.met_comet(RaceDirector.PLAYER), "the comet mission met the Mother-Ice")
	await _frames(2)
	main.hud.close_screen()
	s.weeks = s.campaign_weeks() - 1
	s.advance_week()
	await _frames(3)
	var want := Cutscenes.ENDING_COMET if met else Cutscenes.ENDING_MISSED
	_check(s.race.finished, "the comet passed")
	_check(Cutscenes.is_playing() and Cutscenes.current.id == want, "the %s cutscene plays (%s)" % [want, Cutscenes.current.id if Cutscenes.current else "none"])
	_check(main.hud.current_screen() != "finale", "the finale waits for it")
	var c := Cutscenes.current
	if c:
		await _until(func() -> bool: return c.shot != null, 5.0)
		c.skip_all()
		await _gone(c)
	await _frames(3)
	_check(main.hud.current_screen() == "finale", "then the finale screen (%s)" % main.hud.current_screen())
	_check(Cutscenes.seen(s, want), "the ending is marked as seen")
	main.race_flow.show_finale()
	await _frames(2)
	_check(not Cutscenes.is_playing(), "and it does not play again")
	main.queue_free()
	await _frames(3)
