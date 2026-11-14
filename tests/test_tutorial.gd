extends SceneTree
## Vovô Edmundo's lessons (TutorialBook, TycoonTutorial, the library) and his model:
##   - data: every lesson has a title, a description and steps; every line is translated in
##     pt and en and short enough for the two-line bubble
##   - every step target exists in the scene it lights up (the HUD or the lesson's screen)
##   - on the main screen: the campus lesson starts by itself once, holds the clock, Esc skips
##     it (without opening the pause menu), a screen lesson fires the first time only, a click
##     step goes on when its button is pressed, the era lesson waits for era 2
##   - progress is saved with the campaign and old saves load (a campaign under way skips the
##     welcome); "Não mostrar mais" turns the lessons off; the library lists every lesson and
##     replays one on its screen
##   - Halleyzinho keeps his own materials, his habits play and the cane follows the paw
## The player's "tutorials" setting (user://settings.cfg) is put back as it was at the end.
## Run: godot --headless --path . --script res://tests/test_tutorial.gd

const SLOT := "test_tutorial"
const MAX_LINE := 125

var _failures := 0
var _setting := true


func _initialize() -> void:
	_setting = TutorialBook.enabled()
	TutorialBook.set_enabled(true)
	_data()
	_targets()
	await _halley()
	await _flow()
	_saves()
	TutorialBook.set_enabled(_setting)
	TycoonSave.delete(SLOT)
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


# ------------------------------------------------------------ data
func _data() -> void:
	var lessons := TutorialBook.lessons()
	_check(lessons.size() >= 20, "%d lessons loaded from %s" % [lessons.size(), TutorialBook.PATH])
	var ids := {}
	var need := ["campus", "lot", "crew", "briefings", "objective", "payload", "team", "rocket", "phases", "review",
		"pad", "results", "newspaper", "journal", "research", "contracts", "finance", "race", "map", "eras", "library"]
	for l: Dictionary in lessons:
		ids[String(l.get("id", ""))] = true
	for n in need:
		_check(ids.has(n), "lesson '%s' exists" % n)
	var bad := 0
	var long := 0
	for loc in ["pt_BR", "en"]:
		TranslationServer.set_locale(loc)
		for l: Dictionary in lessons:
			var keys: Array[String] = [String(l.get("title", "")), String(l.get("desc", ""))]
			for st: Dictionary in l.get("steps", []):
				keys.append(String(st.get("line", "")))
			for k in keys:
				var t := tr(k)
				if k == "" or t == k:
					bad += 1
					print("    untranslated (%s): %s" % [loc, k])
			for st: Dictionary in l.get("steps", []):
				if tr(String(st.get("line", ""))).length() > MAX_LINE:
					long += 1
					print("    too long (%s): %s" % [loc, st.get("line", "")])
			var pose := ""
			for st: Dictionary in l.get("steps", []):
				pose = String(st.get("pose", ""))
				if pose != "":
					_check(pose in Halleyzinho.HABITS or Cometling.ONESHOTS.has(pose), "pose '%s' is known" % pose)
	TranslationServer.set_locale("pt_BR")
	_check(bad == 0, "every lesson line is translated in pt and en (%d missing)" % bad)
	_check(long == 0, "every line fits the two-line bubble (%d too long)" % long)
	for k in ["TUT_NEXT", "TUT_DONE", "TUT_SKIP", "TUT_NEVER", "TUT_LIB_TITLE", "TY_SET_TUTORIALS", "TY_SET_LIBRARY"]:
		_check(tr(k) != k, "UI key %s is translated" % k)


## Every target path resolves in the scene it belongs to.
func _targets() -> void:
	var hud := (load("res://scenes/tycoon/ui/tycoon_hud.tscn") as PackedScene).instantiate()
	var screens := {}
	var checked := 0
	for l: Dictionary in TutorialBook.lessons():
		var t: Dictionary = l.get("trigger", {})
		var screen := String(t.get("screen", l.get("replay", "")))
		for st: Dictionary in l.get("steps", []):
			var sp := TutorialBook.target_of(l, st)
			if String(sp[1]) == "":
				continue
			var root: Node = hud
			if String(sp[0]) == "screen":
				if not screens.has(screen):
					var path := TycoonHUD.SCREENS % screen
					screens[screen] = (load(path) as PackedScene).instantiate() if ResourceLoader.exists(path) else null
				root = screens[screen]
			var n: Node = root.get_node_or_null(NodePath(String(sp[1]))) if root else null
			checked += 1
			_check(n is Control, "%s: target %s:%s is in its scene" % [l["id"], sp[0], sp[1]])
			var adv: Dictionary = st.get("advance", {})
			if String(adv.get("on", "")) == "click":
				_check(n is BaseButton, "%s: click step %s is a button" % [l["id"], sp[1]])
	_check(checked >= 40, "%d targets checked" % checked)
	hud.free()
	for k in screens:
		if screens[k]:
			(screens[k] as Node).free()


# ------------------------------------------------------------ the model
func _halley() -> void:
	var h := (load("res://scenes/npc/halleyzinho.tscn") as PackedScene).instantiate() as Halleyzinho
	h.listen_to_events = false
	get_root().add_child(h)
	await _frames(2)
	_check(h is Cometling, "Halleyzinho is a Cometling")
	for p in ["Rig/Hips/Neck/Wig", "Rig/Hips/Neck/BrowL", "Rig/Hips/Neck/BrowR", "Rig/Hips/Neck/Spectacles",
			"Rig/Hips/Coat", "Rig/Hips/Cravat", "Cane", "Rig/Hips/ArmL/HandL/Spyglass", "Rig/Hips/ArmR/Sleeve"]:
		_check(h.get_node_or_null(p) != null, "Halleyzinho has %s" % p)
	var lock := h.get_node("Rig/Hips/Neck/Wig").get_child(0) as MeshInstance3D
	var mat := lock.material_override as ShaderMaterial if lock else null
	_check(mat != null and mat.shader.resource_path == "res://shaders/cw_toon_solid.gdshader",
		"his wig keeps its own toon material")
	_check(not h._meshes.has(lock), "his parts are not tinted like Cometling skin")
	var head := h.get_node("Rig/Hips/Neck/Mesh").get_child(0) as MeshInstance3D if h.get_node("Rig/Hips/Neck/Mesh").get_child_count() > 0 else null
	if head:
		_check(head.material_override == h.body_material, "the head still wears the Cometling skin")
	_check(not h.get_node("Rig/Hips/Vest").visible and not h.get_node("Rig/Hips/Neck/HardHat").visible,
		"no profession gear on him")
	for habit in Halleyzinho.HABITS:
		_check(h.play_habit(habit) and h.current_habit() == habit, "habit %s plays" % habit)
	h.play_habit("forehead")
	h.paused = true
	var rest := h.spectacles.position
	for i in 30:
		h.advance(0.05)
	_check(h.spectacles.position.y > rest.y + 0.05, "the spectacles go up to his forehead")
	_check(h.cane.visible and h.cane.position.y >= Halleyzinho.CANE_LEN - 0.001, "the cane stands on the floor")
	h.talk(true)
	_check(h.current_action() == "talk", "he talks in the portrait")
	h.queue_free()
	await _frames(2)


# ------------------------------------------------------------ the flow
func _flow() -> void:
	TycoonTutorial.allow_in_scripts = true
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(3)
	main.race_flow.autosave = false
	var tut := main.tutorial
	var hud := main.hud
	_check(tut != null and tut.auto_start, "the main screen has the lessons, starting by themselves")
	main.clock.set_speed(2)
	await _wait(tut.campus_delay + 0.4)
	_check(tut.current_lesson() == "campus", "the campus lesson starts by itself (got '%s')" % tut.current_lesson())
	_check(main.clock.speed == 0, "the clock holds during a lesson")
	_check(tut.bubble.visible, "the bubble is on show")
	_check(TutorialBook.seen(main.state, "campus"), "the campus lesson is marked seen")
	# a step with a target lights it up
	if tut._typing:
		tut.next()
	tut.next()
	await _frames(2)
	_check(tut.current_target() != null and tut.spotlight.visible and tut.ring.visible, "step 2 lights up the comet clock")
	# Esc skips the bubble and nothing else
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(not tut.is_showing(), "Esc skips the lesson")
	_check(hud.current_screen() == "", "...without opening the pause menu")
	_check(main.clock.speed == 2, "the clock picks up its speed again (got %d)" % main.clock.speed)
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(hud.current_screen() == "settings", "the next Esc opens the pause menu as usual")
	_press(KEY_ESCAPE)
	await _frames(2)
	await _wait(tut.campus_delay + 0.3)
	_check(not tut.is_showing(), "the campus lesson does not come back")
	# a screen lesson fires the first time only
	hud.open_screen("crew")
	await _frames(3)
	_check(tut.current_lesson() == "crew", "opening the crew starts its lesson (got '%s')" % tut.current_lesson())
	_check(tut.current_target() != null, "the crew lesson lights up the roster")
	hud.screen_back()
	await _frames(3)
	_check(not tut.is_showing(), "closing the screen ends its lesson")
	hud.open_screen("crew")
	await _frames(3)
	_check(not tut.is_showing(), "the crew lesson does not fire twice")
	hud.close_screen()
	await _frames(3)
	# the lot lesson opens with the lot panel
	hud.show_lot(String(main.state.lot_ids()[0]))
	await _frames(3)
	_check(tut.current_lesson() == "lot", "the lot panel starts the lots lesson (got '%s')" % tut.current_lesson())
	tut.skip()
	hud.close_lot()
	await _frames(2)
	# a click step: the last campus step goes on when New project is pressed
	tut.start("campus", true)
	while tut.is_showing() and tut.current_step() < tut.steps().size() - 1:
		if tut._typing:
			tut.next()
		tut.next()
	_check(tut.current_target() == hud.get_node("%NewProject"), "the last campus step points at New project")
	(hud.get_node("%NewProject") as Button).pressed.emit()
	await _frames(4)
	_check(hud.current_screen() == "briefings", "New project opens the mission board")
	_check(tut.current_lesson() == "briefings", "...where the board's lesson starts (got '%s')" % tut.current_lesson())
	tut.skip()
	hud.close_screen()
	await _frames(3)
	# the era lesson waits for era 2
	main.state.era_changed.emit(1)
	await _frames(3)
	_check(not tut.is_showing(), "era 1 is not a new era")
	main.state.era_changed.emit(2)
	await _frames(3)
	_check(tut.current_lesson() == "eras", "a new era starts the eras lesson (got '%s')" % tut.current_lesson())
	tut.skip()
	await _frames(2)
	# a lesson that triggers while one is on show waits
	tut.start("finance", true)
	main.state.era_changed.emit(3)
	tut.start("lot")
	_check(tut.queued().has("lot"), "a lesson waits while another is on show")
	tut.skip()
	await _frames(3)
	_check(tut.current_lesson() == "lot", "...and starts after it (got '%s')" % tut.current_lesson())
	tut.skip()
	await _frames(2)
	# the library
	TutorialBook.mark_seen(main.state, "library")
	hud.open_screen("library")
	await _frames(3)
	var lib := hud.get_node("%Screens").get_child(0)
	_check(lib is LibraryScreen, "the library screen opens")
	var rows := 0
	for c in lib.get_node("%List").get_children():
		if c.has_meta("from_template"):
			rows += 1
	_check(rows == TutorialBook.lessons().size(), "the library lists every lesson (%d rows)" % rows)
	_check(main.clock.speed == 0, "the game holds still in the library")
	(lib as LibraryScreen).replay("research")
	await _frames(4)
	_check(hud.current_screen() == "research", "replaying a lesson opens its screen")
	_check(tut.current_lesson() == "research" and tut._replay, "...and Vovô tells it there")
	_check(not tut.get_node("%NeverAgain").visible, "a replay has no 'don't show again'")
	tut.skip()
	hud.close_screen()
	await _frames(3)
	# the settings: the switch and the library key
	hud.open_screen("settings")
	await _frames(2)
	var set := hud.get_node("%Screens").get_child(0)
	_check(set.get_node_or_null("%Tutorials") is CheckButton and set.get_node("%Tutorials").button_pressed,
		"the pause menu has the lessons switch, on")
	(set.get_node("%Library") as Button).pressed.emit()
	await _frames(3)
	_check(hud.current_screen() == "library", "the pause menu opens the library")
	hud.close_screen()
	await _frames(3)
	# "Não mostrar mais"
	tut.start("map", true)
	tut._replay = false
	tut.never_again()
	_check(not TutorialBook.enabled(), "'don't show again' turns the lessons off")
	hud.open_screen("contracts")
	await _frames(3)
	_check(not tut.is_showing(), "no lesson starts by itself when they are off")
	hud.close_screen()
	await _frames(2)
	TutorialBook.set_enabled(true)
	# progress goes with the campaign
	_check(TycoonSave.save(main.state, SLOT) == OK, "the campaign saves")
	var back := TycoonSave.load_state(SLOT)
	for id in ["campus", "crew", "lot", "briefings", "eras"]:
		_check(TutorialBook.seen(back, id), "the save remembers lesson '%s'" % id)
	_check(not TutorialBook.seen(back, "phases"), "...and not the ones not heard yet")
	main.queue_free()
	await _frames(3)
	TycoonTutorial.allow_in_scripts = false
	# a test script does not get lessons by itself
	var quiet := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	quiet.cutscenes = false
	get_root().add_child(quiet)
	await _frames(3)
	quiet.race_flow.autosave = false
	await _wait(quiet.tutorial.campus_delay + 0.3)
	_check(not quiet.tutorial.is_showing(), "scripts (tests, screenshot tools) get no lesson by themselves")
	quiet.queue_free()
	await _frames(3)


# ------------------------------------------------------------ old saves
func _saves() -> void:
	var fresh := TycoonState.new_campaign(7)
	var d := fresh.to_dict()
	d.erase("tutorials")
	var l := TycoonState.from_dict(d)
	_check(l != null and l.tutorials.is_empty(), "a new save without lessons loads with none seen")
	d["weeks"] = 60
	var old := TycoonState.from_dict(d)
	_check(TutorialBook.seen(old, "campus") and not TutorialBook.seen(old, "crew"),
		"an old campaign under way skips only the welcome")


# ------------------------------------------------------------ helpers
func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
