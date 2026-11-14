extends SceneTree
## The demonstration saves (res://data/demo_saves/, made by tools/make_demo_saves.gd): one at
## week 1 of each era and a fair-mode start, all readable, each at the right era with an
## agency that grows from one to the next; they never show up as the player's own saves
## (Continue); each one opens in the campus (TycoonMain) with the right fair-mode clock and keeps
## running; and the main menu's Demonstração panel lists them and opens the one picked.
## Run: godot --headless --path . --script res://tests/test_demo_saves.gd

const TYCOON := "res://scenes/tycoon/tycoon_main.tscn"
const MENU := "res://scenes/menu/main_menu.tscn"

var _failures := 0


func _initialize() -> void:
	await process_frame
	_files()
	await _open_each()
	await _menu_panel()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _files() -> void:
	print("files")
	_check(TycoonSave.DEMOS.size() == 6, "six demonstration slots: a fair-mode start and the five eras")
	var prev_ms := -1
	var prev_staff := 0
	for slot in TycoonSave.DEMOS:
		_check(TycoonSave.is_demo(slot) and TycoonSave.path(slot).begins_with(TycoonSave.DEMO_DIR), "%s lives in res://data/demo_saves/" % slot)
		var d := TycoonSave.read(slot)
		_check(not d.is_empty() and int(d.get("version", 0)) == TycoonSave.VERSION, "%s is a readable save" % slot)
		if d.is_empty():
			continue
		var s := TycoonSave.load_state(slot)
		_check(s != null, "%s loads into a campaign" % slot)
		if s == null:
			continue
		var fair := bool(d.get("extra", {}).get("fair_mode", false))
		_check(fair == (slot == "demo_fair"), "%s: fair mode only on the fair start" % slot)
		_check(s.week() == 1, "%s starts on week 1 (year %d)" % [slot, s.year()])
		_check(not s.leader.is_empty() and TycoonLeader.member(s).size() > 0, "%s has its leader" % slot)
		_check(s.race.pending_pages.is_empty(), "%s has no old newspaper waiting" % slot)
		if slot.begins_with("demo_era"):
			var era := int(slot.trim_prefix("demo_era"))
			_check(s.era() == era and s.year() == (era - 1) * 5 + 1, "%s is at the start of era %d (year %d)" % [slot, era, s.year()])
			_check(int(d["summary"].get("era", 0)) == era, "%s: the menu summary says era %d" % [slot, era])
			_check(s.milestones >= prev_ms and s.staff.size() >= prev_staff, "%s: the agency grew (%d milestones, %d Cometlings)" % [slot, s.milestones, s.staff.size()])
			prev_ms = s.milestones
			prev_staff = s.staff.size()
			if era >= 2:
				_check(s.milestones >= era - 1 and not s.project_history.is_empty(), "%s: missions flown and milestones taken (%d)" % [slot, s.milestones])
				# the techs of the eras already over are done
				var behind := 0
				for t: Dictionary in TycoonResearch.techs():
					if int(t.get("era", 1)) < era and not TycoonResearch.is_done(s, String(t["id"])):
						behind += 1
				_check(behind == 0, "%s: the research of the eras before is done" % slot)
	for l: Dictionary in TycoonSave.list():
		_check(not TycoonSave.is_demo(String(l["slot"])), "a demonstration never counts as the player's save (%s)" % l["slot"])


func _open_each() -> void:
	for slot in TycoonSave.DEMOS:
		print("open %s" % slot)
		var ps := load(TYCOON) as PackedScene
		var main := ps.instantiate() as TycoonMain
		main.load_slot = slot
		main.fair_mode = bool(TycoonSave.read(slot).get("extra", {}).get("fair_mode", false))
		main.cutscenes = false
		root.add_child(main)
		await _frames(4)
		var want := TycoonSave.load_state(slot)
		_check(main.state != null and main.state.weeks == want.weeks and main.state.agency_name == want.agency_name,
			"%s opens in the campus on its own campaign (year %d)" % [slot, main.state.year() if main.state else 0])
		_check(main.clock.fair_mode == (slot == "demo_fair"), "%s: the clock runs in %s mode" % [slot, "fair" if slot == "demo_fair" else "normal"])
		var w0 := main.state.weeks
		for i in 6:
			main.state.advance_week()
		_check(main.state.weeks == w0 + 6 and not main.state.is_over(), "%s keeps running after loading" % slot)
		main.queue_free()
		await _frames(3)


func _menu_panel() -> void:
	print("main menu")
	change_scene_to_file(MENU)
	await _frames(6)
	var menu := current_scene as MainMenu
	_check(menu != null and not menu.demo.disabled, "the main menu has the Demonstração entry")
	if menu == null:
		return
	menu.demo.pressed.emit()
	await _frames(3)
	var panel := menu.demo_panel
	_check(panel.visible and panel.rows().size() == TycoonSave.DEMOS.size(), "it opens the panel with %d saves" % panel.rows().size())
	var era3 := panel.rows()[TycoonSave.DEMOS.find("demo_era3")]
	_check(era3.text == tr("MENU_DEMO_ERA") % [3, tr("TY_ERA_3")] and era3.hint_key.contains("11"),
		"rows say the era and the year (%s · %s)" % [era3.text, era3.hint_key])
	era3.pressed.emit()
	for i in 240:
		await process_frame
		if current_scene is TycoonMain:
			break
	var main := current_scene as TycoonMain
	_check(main != null and main.load_slot == "demo_era3" and main.state.era() == 3, "picking a row opens that campaign")
	_check(main != null and not main.clock.fair_mode, "an era save plays at the normal clock")


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
