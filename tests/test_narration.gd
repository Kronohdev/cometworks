extends SceneTree
## Headless checks for Vovô Edmundo's narration of the story cutscenes (data/story/narration.json,
## src/story/narrator_box.gd, src/cutscene/cutscene.gd):
##   - every storybook line of every cutscene (in the animation its cutscene plays) has his
##     version, and every version belongs to a line the shots say; his lines exist in pt and en,
##     poses are his habits or Cometling gestures and faces are Cometling expressions
##   - timing: each of his lines types out and leaves time to read it before the shot's next
##     line (or its end), in both languages, with the leader's and the agency's names filled in
##   - playing: the line comes up in his box (portrait live) instead of the caption, a tap
##     finishes the typing, the next tap jumps on as before, holding the key skips everything,
##     and the shots keep their length (the animation timing is not touched)
##   - with narration off in the settings the plain storybook caption comes back
## Run: godot --headless --path . --script res://tests/test_narration.gd

## seconds left to read a line after it has typed out
const READ_MIN := 1.5
## long names, so the timing holds for real players
const LONG_LEADER := {"name": "Estrelinha Cintilante"}
const LONG_AGENCY := "Cauda Brilhante do Norte"

var _failures := 0
var _setting := true
var _narration := true


func _initialize() -> void:
	await process_frame
	_setting = Cutscenes.enabled()
	_narration = Cutscenes.narration_enabled()
	Cutscenes.set_enabled(true)
	Cutscenes.set_narration_enabled(true)
	_data()
	_timing()
	await _playing()
	await _off()
	Cutscenes.set_enabled(_setting)
	Cutscenes.set_narration_enabled(_narration)
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)


func _cutscene(id: String) -> Cutscene:
	return (load(Cutscenes.path(id)) as PackedScene).instantiate() as Cutscene


## [{"cutscene", "shot", "key", "at", "until"}] for every storybook line the cutscenes say.
func _cues() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in Cutscenes.ALL:
		var c := _cutscene(id)
		for path: String in c.shots:
			var shot := (load(path) as PackedScene).instantiate() as CutsceneShot
			var anim := shot.animation_player.get_animation(c.shot_animation)
			var says: Array = []
			for i in anim.get_track_count():
				if anim.track_get_type(i) != Animation.TYPE_METHOD or anim.track_get_path(i) != NodePath("."):
					continue
				for k in anim.track_get_key_count(i):
					if anim.method_track_get_name(i, k) == &"say":
						says.append([anim.track_get_key_time(i, k), String(anim.method_track_get_params(i, k)[0])])
			says.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
			for j in says.size():
				var until := anim.length if j + 1 >= says.size() else float(says[j + 1][0])
				out.append({"cutscene": id, "shot": path.get_file(), "key": says[j][1], "at": float(says[j][0]), "until": until})
			shot.free()
		c.free()
	return out


# ------------------------------------------------------------ data
func _data() -> void:
	print("data")
	var lines := Cutscenes.narration()
	_check(lines.size() >= 25, "his lines load (%d)" % lines.size())
	var said := {}
	var missing: Array[String] = []
	for cue in _cues():
		said[cue["key"]] = true
		if Cutscenes.narration_line(cue["key"]).is_empty():
			missing.append("%s/%s" % [cue["shot"], cue["key"]])
	_check(missing.is_empty(), "every storybook line of every cutscene has his version %s" % (str(missing) if not missing.is_empty() else ""))
	var orphan: Array[String] = []
	for k: String in lines:
		if not said.has(k):
			orphan.append(k)
	_check(orphan.is_empty(), "every version belongs to a line the shots say %s" % (str(orphan) if not orphan.is_empty() else ""))
	var bad: Array[String] = []
	for k: String in lines:
		var n: Dictionary = lines[k]
		for lang in ["pt", "en"]:
			TranslationServer.set_locale(lang)
			if TranslationServer.translate(String(n.get("key", ""))) == String(n.get("key", "")):
				bad.append("%s:%s" % [lang, n.get("key", "")])
		var pose := String(n.get("pose", ""))
		if pose != "" and not (pose in Halleyzinho.HABITS or Cometling.ONESHOTS.has(pose)):
			bad.append("pose " + pose)
		var face := String(n.get("face", ""))
		if face != "" and not face in Cometling.EXPRESSIONS:
			bad.append("face " + face)
	TranslationServer.set_locale("pt")
	_check(bad.is_empty(), "his lines exist in pt and en, poses and faces are real %s" % (str(bad) if not bad.is_empty() else ""))
	for k in ["TY_SET_NARRATION", "TY_SET_NARRATION_TIP", "TUT_HALLEY_NAME"]:
		_check(tr(k) != k, "%s exists" % k)


# ------------------------------------------------------------ timing
func _timing() -> void:
	print("timing")
	var box := (load("res://scenes/story/narrator_box.tscn") as PackedScene).instantiate() as NarratorBox
	var speed := box.type_speed
	box.free()
	var f := _cutscene(Cutscenes.OPENING)
	f.leader = LONG_LEADER
	f.agency = LONG_AGENCY
	var late: Array[String] = []
	var n := 0
	for lang in ["pt", "en"]:
		TranslationServer.set_locale(lang)
		for cue in _cues():
			var nl := Cutscenes.narration_line(cue["key"])
			if nl.is_empty():
				continue
			n += 1
			var text := f.fill(tr(String(nl["key"])))
			var need := float(text.length()) / speed + READ_MIN
			var room := float(cue["until"]) - float(cue["at"])
			if need > room:
				late.append("%s %s %.1fs > %.1fs" % [lang, nl["key"], need, room])
	TranslationServer.set_locale("pt")
	f.free()
	_check(n > 40 and late.is_empty(), "%d lines type out and leave %.1f s to read before the next cue %s" % [n, READ_MIN, str(late) if not late.is_empty() else ""])


# ------------------------------------------------------------ playing
func _playing() -> void:
	print("playing")
	var host := Node.new()
	root.add_child(host)
	var c := Cutscenes.play(host, Cutscenes.OPENING, null, true)
	_check(c != null and c.narrator != null, "the opening plays with the narrator box in its frame")
	var heard: Array[String] = []
	c.narrated.connect(func(k: String) -> void: heard.append(k))
	var done := [false, false]
	c.finished.connect(func(skipped: bool) -> void:
		done[0] = true
		done[1] = skipped)
	await _until(func() -> bool: return c.shot != null and c.shot.time > 0.2, 5.0)
	var length := c.shot.duration
	_check(is_equal_approx(length, c.shot.animation_player.get_animation(c.shot_animation).length),
		"the shot keeps its animation's length (%.1f s)" % length)
	_check(not c.narrator.is_showing(), "no bubble over the title card")
	await _tap(KEY_SPACE)
	await _until(func() -> bool: return c.current_line() == "CS_OPEN_1", 2.0)
	_check(c.narrator.is_showing() and heard == ["NARR_OPEN_1"], "the first line comes up in Vovô's box (%s)" % str(heard))
	_check(c.narrator.current_text() == c.fill(tr("NARR_OPEN_1")) and c.line_label.text == "",
		"his words, not the caption")
	var vp := c.narrator.portrait.get_node("Viewport") as SubViewport
	_check(vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "his portrait is live while he talks")
	_check(c.narrator.is_typing() and c._typing, "the line types out")
	await _tap(KEY_SPACE)
	_check(not c.narrator.is_typing() and not c._typing, "a tap shows the whole line")
	_check(c.narrator.current_text() == c.fill(tr("NARR_OPEN_1")), "the line stays up")
	await _tap(KEY_SPACE)
	await _until(func() -> bool: return c.index == 1 and c.current_line() != "", 4.0)
	_check(c.index == 1 and c.current_line() == "CS_OPEN_2" and heard.back() == "NARR_OPEN_2",
		"the next tap cuts to the next shot, his next line (%s)" % str(heard))
	# typing finishes by itself within the time the timing check allowed
	await _until(func() -> bool: return not c.narrator.is_typing(), 4.0)
	await _frames(2)
	_check(not c._typing, "the line finished typing by itself")
	# hold Esc: everything goes
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.pressed = true
	root.push_input(down)
	await _until(func() -> bool: return done[0], c.hold_to_skip + 4.0)
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.pressed = false
	root.push_input(up)
	_check(done[0] and done[1], "holding the key skips the narrated cutscene")
	await _frames(2)
	_check(not Cutscenes.is_playing(), "nothing is left playing")
	host.queue_free()
	await _frames(2)


func _off() -> void:
	print("narration off")
	Cutscenes.set_narration_enabled(false)
	var host := Node.new()
	root.add_child(host)
	var c := Cutscenes.play(host, Cutscenes.OPENING_SHORT, null, true)
	await _until(func() -> bool: return c.current_line() == "CS_SHORT_1", 6.0)
	_check(c.current_line() == "CS_SHORT_1" and not c.narrator.is_showing() and c.line_label.text == c.fill(tr("CS_SHORT_1")),
		"with narration off the storybook caption shows")
	Cutscenes.set_narration_enabled(true)
	c.skip_all()
	await _until(func() -> bool: return not Cutscenes.is_playing(), 4.0)
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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()) and Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		await process_frame
