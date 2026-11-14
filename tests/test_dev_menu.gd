extends SceneTree
## The dev menu (autoload "CwDev": src/dev/cw_dev.gd, scenes/dev/dev_menu.tscn):
##   it is up, F1 / F12 open and close it (not while typing; in the hangar F1 stays the help
##   key), every action runs on a fresh campus without engine errors and does what it says
##   (cash, calendar, era, research, crew, contracts, race, projects, the forced launch outcome,
##   cutscenes, HUD screens, Cometlings), and it follows the scene: main menu and hangar.
## The player's user://dev.cfg and user://settings.cfg are put back afterwards.
## Run: godot --headless --path . --script res://tests/test_dev_menu.gd

const KEEP := ["user://dev.cfg", "user://settings.cfg"]

var _failures := 0
var dev: CwDevMenu
var _kept := {}


func _initialize() -> void:
	for p in KEEP:
		_kept[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null
	await _frames(2)
	dev = root.get_node_or_null("CwDev") as CwDevMenu
	_check(dev != null, "the CwDev autoload is up")
	if dev == null:
		_finish()
		return
	await _toggle()
	await _campus()
	await _menu()
	await _hangar()
	await _release()
	_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	paused = false
	for p: String in _kept:
		if _kept[p] == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_buffer(_kept[p])
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


# ------------------------------------------------------------------ open / close
func _toggle() -> void:
	print("toggle")
	dev.set_open(false)
	_press(KEY_F1)
	await _frames(1)
	_check(dev.is_open and dev.panel.visible, "F1 opens the menu")
	_press(KEY_F1)
	await _frames(1)
	_check(not dev.is_open and not dev.panel.visible, "F1 closes it")
	_press(KEY_F12)
	await _frames(1)
	_check(dev.is_open, "F12 opens it too")
	var quote := InputEventKey.new()
	quote.physical_keycode = KEY_QUOTELEFT
	quote.pressed = true
	_check(dev.is_toggle_key(quote), "the key under Esc (' on ABNT2) toggles it")
	var edit := LineEdit.new()
	root.add_child(edit)
	edit.grab_focus()
	await _frames(1)
	_press(KEY_F1)
	await _frames(1)
	_check(dev.is_open, "F1 does nothing while a text field has the keyboard")
	edit.queue_free()
	await _frames(1)
	dev.tabs.current_tab = dev.tabs.get_tab_idx_from_control(dev.tabs.get_node("Log"))
	dev.panel.position = Vector2(222, 111)
	dev.set_collapsed(false)
	var cfg := ConfigFile.new()
	_check(cfg.load(CwDevMenu.CFG_PATH) == OK and String(cfg.get_value("menu", "tab", "")) == "Log"
		and cfg.get_value("menu", "position", Vector2.ZERO) == Vector2(222, 111),
		"its tab and place are kept in user://dev.cfg")
	dev.tabs.current_tab = 0
	dev.set_collapsed(true)
	_check(not dev.get_node("%Body").visible, "it collapses to its header")
	dev.set_collapsed(false)
	_check(dev.layer >= 100 and dev.process_mode == Node.PROCESS_MODE_ALWAYS,
		"it sits on a high layer and keeps working while the game is paused")


# ------------------------------------------------------------------ campus
func _campus() -> void:
	print("campus")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	root.add_child(main)
	await _frames(3)
	main.race_flow.autosave = false
	var s := main.state
	dev._refresh_context(true)
	_check(dev.context_tags().has("tycoon") and not _tab_hidden("Campanha") and not _tab_hidden("Projetos"),
		"on the campus the campaign and project tabs show")

	var cash := s.cash
	_run("cash", 100000)
	_check(is_equal_approx(s.cash, cash + 100000.0), "+100 mil adds 100 000 cr")
	_run("cash", 1000000)
	_check(is_equal_approx(s.cash, cash + 1100000.0), "+1 mi adds a million")
	var rep := s.reputation
	_run("reputation", 5)
	_check(is_equal_approx(s.reputation, minf(rep + 5.0, 100.0)), "reputation +5")
	_run("hype", -5)
	var w := s.weeks
	_run("skip", "week")
	_check(s.weeks == w + 1, "+1 week advances the state one week")
	w = s.weeks
	_run("skip", "month")
	_check(s.weeks > w and s._month_of(s.weeks) != s._month_of(w), "+1 month reaches the next month")
	await _close_all(main)
	_run("turbo", 4.0)
	_check(is_equal_approx(main.clock.dev_turbo, 4.0) and main.clock.seconds_per_week() < 3.0,
		"turbo x4 makes weeks shorter (%.2f s)" % main.clock.seconds_per_week())
	_run("turbo", 1.0)
	_run("speed", 0)
	_check(main.clock.speed == 0, "the speed keys drive the clock")
	_run("era", 3)
	_check(s.era() == 3, "era 3 jumps the calendar (year %d)" % s.year())
	_run("research_all")
	var all_done := true
	for t: Dictionary in TycoonResearch.techs():
		all_done = all_done and TycoonResearch.is_done(s, String(t["id"]))
	_check(all_done, "every research is unlocked")
	_run("rocket_parts")
	var parts := true
	for slot_id in RocketDesigner.slot_ids():
		for c in RocketDesigner.components(slot_id):
			parts = parts and RocketDesigner.available(s, String(c["id"]))
	_check(parts, "every rocket part is available")
	_run("build_all")
	var top := true
	for lot_id: String in s.lot_ids():
		var levels: Array = s.building_type(s.lot_kind(lot_id)).get("levels", [])
		top = top and int(s.building(lot_id).get("level", 0)) == levels.size()
	_check(top, "every lot is built to its top level")
	var staff := s.staff.size()
	_run("hire")
	_check(s.staff.size() == staff + 1, "a random Cometling is hired")
	_run("morale")
	_check(s.staff.all(func(m: Dictionary) -> bool: return float(m["morale"]) >= 100.0), "everyone's morale is maxed")
	var levels0 := s.staff.map(func(m: Dictionary) -> int: return int(m["level"]))
	_run("level_up")
	var up := true
	for i in s.staff.size():
		up = up and (int(s.staff[i]["level"]) == int(levels0[i]) + 1 or int(levels0[i]) >= TycoonCrew.max_level())
	_check(up, "everyone levels up")
	var accepted := TycoonContracts.accepted(s).size()
	_run("contract")
	_check(TycoonContracts.accepted(s).size() == accepted + 1, "a contract is accepted")
	var ms := s.milestones
	_run("milestone")
	_check(s.milestones == ms + 1, "the next milestone is claimed")
	await _close_all(main)
	_run("day", 0.45)
	var dc := main.get_node("DayCycle") as CampusDayCycle
	_check(is_equal_approx(dc.force_phase, 0.45), "the time of day is set")
	_run("day", -1.0)
	_check(dc.force_phase < 0.0, "...and follows the clock again")
	_run("save", "devtest")
	_check(TycoonSave.exists("devtest"), "the campaign is saved to a slot")
	TycoonSave.delete("devtest")

	# projects and launches
	await _close_all(main)
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", [String(ProjectDesk.free_staff(s)[0]["id"])])
	_check(p != null, "a test project starts")
	if p:
		await _close_all(main)
		var phase := p.phase
		_run("finish_phase")
		_check(p.phase == phase + 1 or p.review_state == "waiting", "finish phase moves the project on (phase %d)" % (p.phase + 1))
		await _close_all(main)
		_run("open_review")
		await _frames(2)
		_check(p.review_state == "waiting" and main.hud.current_screen() == "design_review",
			"open review finishes development and opens its Design Review (%s)" % main.hud.current_screen())
		await _close_all(main)
		ProjectDesk.scrub(s, p.id)
	for kind: String in ["fail", "success", "partial"]:
		await _close_all(main)
		_run("force", kind)
		_check(ProjectDesk.dev_force_outcome == kind, "the next outcome is forced to %s" % kind)
		var n := s.project_history.size()
		_run("quick_launch")
		await _frames(2)
		var e: Dictionary = s.project_history[-1] if s.project_history.size() > n else {}
		var want_ok: bool = kind != "fail"
		_check(not e.is_empty() and bool(e["success"]) == want_ok
			and (String(e["outcome"]) == "partial") == (kind == "partial"),
			"a quick launch honours the forced %s (got %s)" % [kind, e.get("outcome", "nothing")])
		_check(ProjectDesk.dev_force_outcome == "", "...and the force is used up")
		_check(main.hud.current_screen() == "launch", "...and the launch sequence plays (%s)" % main.hud.current_screen())
	await _close_all(main)
	_run("replay", "partial")
	await _frames(2)
	var seq := main.hud.get_node("%Screens").get_child(0) as LaunchSequence if main.hud.current_screen() == "launch" else null
	_check(seq != null and seq.kind == "partial", "the launch cinematic replays a partial launch")
	await _close_all(main)

	# mission studies (FocusStudy)
	var st_type := dev._study_type(s)
	_check(st_type != "", "a type to study (%s)" % st_type)
	var st_tier := FocusStudy.tier(s, st_type)
	_run("study_tier")
	_check(FocusStudy.tier(s, st_type) == st_tier + 1, "study +1 level (%s: %d)" % [st_type, FocusStudy.tier(s, st_type)])
	s.cash = maxf(s.cash, 1.0e6)
	FocusStudy.start(s, st_type)
	_run("study_finish")
	_check(FocusStudy.tier(s, st_type) == mini(st_tier + 2, 3) and FocusStudy.active(s) == "", "finish the study under way")
	_run("study_reveal")
	_check(FocusStudy.tier(s, "comet_mission") == 3 and FocusStudy.tier(s, "sounding") == 3, "reveal every study")
	_run("study_screen")
	await _frames(3)
	_check(main.hud.current_screen() == "research", "the studies page opens (%s)" % main.hud.current_screen())
	await _close_all(main)
	_run("study_reset")
	_check(FocusStudy.studied(s, "comet_mission") == 0, "forget the studies")

	# cutscenes
	_run("cutscene", "opening_short")
	await _frames(2)
	_check(Cutscenes.is_playing(), "a cutscene plays on request")
	_run("cutscene_skip")
	await _wait(2.5)
	if Cutscenes.is_playing():
		Cutscenes.current.queue_free()
		await _frames(2)
	_check(not Cutscenes.is_playing() and not paused, "...and skipping it gives the game back")
	s.story["opening"] = true
	_run("cutscene_reset")
	_check(s.story.is_empty(), "the seen flags reset")

	# screens
	_run("screen", "crew")
	await _frames(2)
	_check(main.hud.current_screen() == "crew", "a HUD screen opens by name")
	for item: Array in dev._items_screens():
		await _close_all(main)
		_run("screen", item[2])
		await _frames(3)
	await _close_all(main)
	for ev in ["newspaper", "finale", "final_score"]:
		_run(ev)
		await _frames(2)
		_check(main.hud.current_screen() == ev, "the %s opens" % ev)
		await _close_all(main)

	# Cometlings
	_check(not _tab_hidden("Cometinhos"), "the Cometling tab shows on the campus")
	_run("creature_target", "all")
	var crowd := main.campus.cometlings().size()
	var msg := _run("creature_action", "wave")
	_check(msg.ends_with("× %d" % crowd), "an action plays on every Cometling (%s)" % msg)
	_run("creature_emote", "heart")
	_run("creature_expression", "joy")
	_run("creature_react", "success")
	_run("creature_target", "followed")
	main.camera.follow(main.campus.cometlings()[0])
	await _frames(1)
	msg = _run("creature_react", "hello")
	_check(msg.ends_with("× 1"), "...or on the followed one (%s)" % msg)
	main.camera.release()
	(dev.get_node("%SpawnCount") as SpinBox).value = 3
	_run("spawn")
	await _frames(2)
	_check(main.campus.cometlings().size() == crowd + 3, "3 extra walkers spawn")
	s.changed.emit()   # a crowd sync keeps them
	await _frames(1)
	_check(main.campus.cometlings().size() == crowd + 3, "...and stay through a crowd sync")
	_run("spawn_clear")
	await _frames(2)
	_check(main.campus.cometlings().size() == crowd, "...and leave on request")
	_run("nav_debug", true)
	_check(main.campus.dev_nav_shown(), "the walk grid shows")
	_run("nav_debug", false)

	# general
	_run("time_scale", 2.0)
	_check(is_equal_approx(Engine.time_scale, 2.0), "time scale 2x")
	_run("time_scale", 1.0)
	var toon := CwLook.toon()
	_run("toon", not toon)
	_check(CwLook.toon() != toon, "the toon style toggles")
	_run("toon", toon)
	_run("outlines", CwLook.outlines())
	_run("reduce_motion", CwMotion.reduced())
	_run("mute", true)
	_check(AudioServer.is_bus_mute(0), "mute")
	_run("mute", false)
	_run("collisions", false)
	_run("draw", 0)
	_run("comet", 2)
	_check(s.comet_weeks_left() == 2, "the comet countdown is set near the end")
	_run("log_clear")
	main.queue_free()
	await _frames(3)


# ------------------------------------------------------------------ main menu, hangar
func _menu() -> void:
	print("main menu")
	change_scene_to_file("res://scenes/menu/main_menu.tscn")
	await _frames(6)
	dev._refresh_context(true)
	_check(dev.context_tags().has("menu"), "the menu knows it is on the main menu")
	_check(_tab_hidden("Campanha") and _tab_hidden("Telas") and not _tab_hidden("Geral"),
		"campaign tabs hide outside the campus")
	_check(_run("cash", 100000) == CwDevMenu.NO_CAMPAIGN, "campaign actions say so outside a campaign")
	_run("time_scale", 1.0)
	_run("creature_action", "wave")
	_run("goto", "hangar")
	await _frames(8)
	_check(current_scene != null and current_scene.scene_file_path == CwDevMenu.HANGAR, "go to: hangar")


func _hangar() -> void:
	print("hangar")
	if current_scene == null or current_scene.scene_file_path != CwDevMenu.HANGAR:
		change_scene_to_file(CwDevMenu.HANGAR)
		await _frames(8)
	dev._refresh_context(true)
	_check(dev.context_tags().has("hangar") and dev.f1_taken(), "in the hangar F1 stays the hangar's help key")
	var open := dev.is_open
	_press(KEY_F1)
	await _frames(1)
	_check(dev.is_open == open, "...so F1 leaves the menu alone there")
	_press(KEY_F12)
	await _frames(1)
	_check(dev.is_open != open, "F12 still toggles it")
	_check(String(dev.get_node("%Keys").text).begins_with("F12"), "the header shows the keys that work here")
	_run("screenshot")
	await _frames(3)
	_run("goto", "menu")
	await _frames(6)
	_check(current_scene != null and current_scene is MainMenu, "go to: main menu")


# ------------------------------------------------------------------ release export
## A release export has no dev menu: OS.is_debug_build() is false there (simulated here), so a
## fresh menu stays hidden, disabled and deaf to F1 / F12 / ', unless cometworks/dev/enabled.
func _release() -> void:
	print("release build")
	_check(not CwDevMenu.allowed(false, false) and CwDevMenu.allowed(true, false) and CwDevMenu.allowed(false, true),
		"only debug builds, the editor or the project setting have the menu")
	_check(not bool(ProjectSettings.get_setting(CwDevMenu.SETTING, false)), "the project ships with cometworks/dev/enabled off")
	dev.set_open(false)
	CwDevMenu.simulate_release = true
	var rel := (load("res://scenes/dev/dev_menu.tscn") as PackedScene).instantiate() as CwDevMenu
	root.add_child(rel)
	await _frames(1)
	_check(not CwDevMenu.enabled(), "a release build says the menu is off")
	_check(not rel.visible and not rel.panel.visible and rel.process_mode == Node.PROCESS_MODE_DISABLED,
		"in a release build the menu is hidden and disabled")
	dev.process_mode = Node.PROCESS_MODE_DISABLED   # only the release copy listens now
	for key: Key in [KEY_F12, KEY_F1]:
		_press(key)
		await _frames(1)
	_check(not rel.is_open and not rel.panel.visible, "F12 and F1 do not open it in a release build")
	CwDevMenu.simulate_release = false
	dev.process_mode = Node.PROCESS_MODE_ALWAYS
	rel.queue_free()
	await _frames(1)


# ------------------------------------------------------------------ helpers
## Runs an action and fails the test when it printed an engine error.
func _run(action: String, arg: Variant = null) -> String:
	dev._drain_log()
	var errors := _errors()
	var msg := dev.run(action, arg)
	dev._drain_log()
	var new_errors := _errors() - errors
	if new_errors > 0:
		_check(false, "%s(%s) printed %d error(s): %s" % [action, arg, new_errors, dev.log_lines[-1].get("text", "")])
	return msg


func _errors() -> int:
	return dev.log_lines.filter(func(l: Dictionary) -> bool: return l["kind"] == "error").size()


func _tab_hidden(tab_name: String) -> bool:
	var c := dev.tabs.get_node_or_null(tab_name) as Control
	return c == null or dev.tabs.is_tab_hidden(dev.tabs.get_tab_idx_from_control(c))


func _close_all(main: TycoonMain) -> void:
	for i in 12:
		await _frames(1)
		if main.hud.current_screen() == "":
			await _frames(1)
			if main.hud.current_screen() == "":
				return
		main.hud.close_screen()


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
