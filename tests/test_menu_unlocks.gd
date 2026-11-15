extends SceneTree
## The HUD menus a new career unlocks while it plays (MenuUnlocks, HudUnlocker,
## data/tycoon/menu_unlocks.json):
##   - data: every item has nodes that exist in the HUD, a translated name, known condition keys
##     and a lesson (trigger "unlock") with translated lines; the essentials open from the start
##   - progression: a new career opens only the essentials; the conditions (projects, launches,
##     weeks, money, milestones, era...) open the rest in order; a screen opened by another way
##     opens its item; fair mode opens everything by its fair_week; unknown condition keys never hold
##   - saves: progress goes with the career (save / load), old saves and the demonstration saves
##     have every menu open
##   - on the main screen: locked menus are hidden and their key (M) only hints; an item pops in
##     when the campus is free, with the badge and Vovô's lesson; a quiet item (opened by its
##     screen) pops in without it; a loaded career shows what it had; "Já sei jogar" in the
##     library opens everything; test scripts get every menu open by themselves
## The player's settings (lessons, menus one at a time) are put back as they were.
## Run: godot --headless --path . --script res://tests/test_menu_unlocks.gd

const SLOT := "test_menu_unlocks"
const KNOWN := ["projects", "launches", "research_points", "cash_below", "reputation", "era", "weeks", "building",
	"milestones", "contracts", "item", "lesson", "screen"]

var _failures := 0
var _lessons_setting := true
var _menus_setting := true


func _initialize() -> void:
	_lessons_setting = TutorialBook.enabled()
	_menus_setting = MenuUnlocks.enabled_for_new()
	TutorialBook.set_enabled(true)
	MenuUnlocks.set_enabled_for_new(true)
	_check(load("res://src/tycoon/tutorial/menu_unlocks.gd") != null and MenuUnlocks.PATH.ends_with("menu_unlocks.json"),
		"MenuUnlocks loaded from src/tycoon/tutorial/menu_unlocks.gd")
	_data()
	_progression()
	_saves()
	await _in_game()
	await _scripts_default()
	TutorialBook.set_enabled(_lessons_setting)
	MenuUnlocks.set_enabled_for_new(_menus_setting)
	TycoonSave.delete(SLOT)
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


# ------------------------------------------------------------ data
func _data() -> void:
	var items := MenuUnlocks.items()
	_check(items.size() >= 10, "%d menu items in %s" % [items.size(), MenuUnlocks.PATH])
	var hud := (load("res://scenes/tycoon/ui/tycoon_hud.tscn") as PackedScene).instantiate() as TycoonHUD
	get_root().add_child(hud)
	var starts := []
	var listed := {}
	for it: Dictionary in items:
		var id := String(it.get("id", ""))
		_check(id != "" and not listed.has(id), "item '%s' has a unique id" % id)
		listed[id] = true
		if bool(it.get("start", false)):
			starts.append(id)
		for ref in it.get("nodes", []):
			_check(hud.hud_node(String(ref)) != null, "%s: HUD node '%s' exists" % [id, ref])
		for loc in ["pt_BR", "en"]:
			TranslationServer.set_locale(loc)
			var k := String(it.get("name_key", ""))
			_check(k != "" and tr(k) != k, "%s: name %s translated (%s)" % [id, k, loc])
		TranslationServer.set_locale("pt_BR")
		for c in it.get("when", []):
			for k: String in c:
				_check(k in KNOWN, "%s: condition key '%s' is known" % [id, k])
		var lid := String(it.get("lesson", ""))
		if lid != "":
			var l := TutorialBook.lesson(lid)
			_check(not l.is_empty() and String(l.get("trigger", {}).get("on", "")) == "unlock"
				and String(l["trigger"].get("item", "")) == id, "%s: lesson '%s' plays when it unlocks" % [id, lid])
		if not bool(it.get("start", false)):
			_check(not it.get("when", []).is_empty() and it.has("fair_week"), "%s: has conditions and a fair-mode week" % id)
	for need in ["new_project", "settings"]:
		_check(need in starts, "'%s' is open from the start" % need)
	for need in ["crew", "research", "contracts", "finance", "race", "journal", "map", "hangar", "book"]:
		_check(listed.has(need), "the table unlocks '%s'" % need)
	for k in ["TY_UNL_NEW", "TY_UNL_NEW_TAG", "TY_UNL_LOCKED_HINT", "TY_UNL_ALL", "TY_SET_MENUS_GRADUAL"]:
		_check(tr(k) != k, "UI key %s is translated" % k)
	# a reference to a button nobody added yet is tolerated
	_check(hud.hud_node("Rovers_not_there_yet") == null and hud.hud_node("%NoSuchNode") == null, "a missing node resolves to null")
	hud.lock_node("NoSuchButton", true)
	_check(hud.is_locked("NoSuchButton"), "...and can be locked without errors")
	hud.queue_free()


# ------------------------------------------------------------ progression
func _new() -> TycoonState:
	var s := TycoonState.new_campaign(11)
	MenuUnlocks.begin(s)
	return s


func _progression() -> void:
	var s := _new()
	_check(MenuUnlocks.gradual(s), "a new career unlocks its menus gradually")
	_check(MenuUnlocks.is_open(s, "new_project") and MenuUnlocks.is_shown(s, "new_project"), "the mission board is there from the start")
	for id in ["crew", "research", "contracts", "finance", "race", "journal", "map", "book", "hangar"]:
		_check(not MenuUnlocks.is_open(s, id), "'%s' is closed at the start" % id)
	_check(MenuUnlocks.check(s).is_empty(), "nothing opens in week 0")
	# the first project opens the crew, then the hangar
	s.mission_projects.append(MissionProject.new())
	var got := MenuUnlocks.check(s)
	_check(_same(got, ["crew", "hangar"]), "the first project opens the crew and the hangar (%s)" % [got])
	_check(_same(MenuUnlocks.pending(s), ["crew", "hangar"]), "...waiting to be revealed in order")
	# the first launch opens the maps, the journal, research and contracts
	s.project_history.append({"id": "p1"})
	got = MenuUnlocks.check(s)
	_check(_same(got, ["map", "journal", "research", "contracts"]), "the first launch opens the map, journal, research, contracts (%s)" % [got])
	_check(not MenuUnlocks.is_open(s, "finance") and not MenuUnlocks.is_open(s, "race"), "...not yet the finances nor the race")
	# money trouble opens the finances
	s.cash = 90000.0
	_check(_same(MenuUnlocks.check(s), ["finance"]), "money trouble opens the finances")
	# a rival's milestone opens the race
	s.rivals[0]["milestones"] = 1
	_check(_same(MenuUnlocks.check(s), ["race"]), "a milestone taken opens the race")
	s.weeks = 5 * s.weeks_per_year()
	_check(_same(MenuUnlocks.check(s), ["book"]), "era 2 opens the archive")
	_check(MenuUnlocks.open_count(s) == MenuUnlocks.items().size(), "every menu is open now")
	# the weeks fallback alone, in order
	var w := _new()
	w.weeks = 12
	_check(_same(MenuUnlocks.check(w), ["crew"]), "week 12 opens the crew even without a project")
	# a screen opened by another way opens its item
	var sc := _new()
	_check(MenuUnlocks.note_screen(sc, "journal") == "journal" and MenuUnlocks.is_open(sc, "journal"), "opening the journal from a project opens its key")
	_check(MenuUnlocks.note_screen(sc, "journal") == "", "...once")
	_check(MenuUnlocks.met(sc, {"screen": "journal"}) and not MenuUnlocks.met(sc, {"screen": "race"}), "the screens opened are remembered")
	_check(not MenuUnlocks.met(sc, {"no_such_key": 1}), "an unknown condition key never holds")
	# fair mode: the fast version
	var f := _new()
	f.weeks = 3
	_check(MenuUnlocks.check(f, false).is_empty(), "week 3 opens nothing in the normal mode")
	_check(_same(MenuUnlocks.check(f, true), ["crew"]), "fair mode opens the crew by week 3")
	f.weeks = 30
	MenuUnlocks.check(f, true)
	_check(MenuUnlocks.open_count(f) == MenuUnlocks.items().size(), "fair mode has every menu open by week 30")
	# Já sei jogar
	var a := _new()
	MenuUnlocks.unlock_all(a)
	_check(not MenuUnlocks.gradual(a) and MenuUnlocks.is_shown(a, "finance") and MenuUnlocks.pending(a).is_empty(), "'Já sei jogar' opens every menu")


# ------------------------------------------------------------ saves
func _saves() -> void:
	var s := _new()
	s.mission_projects.append(MissionProject.new())
	MenuUnlocks.check(s)
	MenuUnlocks.mark_shown(s, "crew")
	MenuUnlocks.note_screen(s, "briefings")
	_check(TycoonSave.save(s, SLOT) == OK, "the career saves")
	var back := TycoonSave.load_state(SLOT)
	_check(back != null and MenuUnlocks.gradual(back), "a loaded career still unlocks gradually")
	if back:
		_check(MenuUnlocks.is_shown(back, "crew") and MenuUnlocks.is_open(back, "hangar") and not MenuUnlocks.is_shown(back, "hangar"),
			"the save keeps what was revealed and what waits")
		_check(not MenuUnlocks.is_open(back, "finance"), "...and what is still closed")
		_check(MenuUnlocks.met(back, {"screen": "briefings"}), "...and the screens opened")
	# saves from before the unlocks
	var d := s.to_dict()
	(d["tutorials"] as Dictionary).erase("menus")
	var old := TycoonState.from_dict(d)
	_check(not MenuUnlocks.gradual(old) and MenuUnlocks.is_shown(old, "race"), "an old save has every menu open")
	d.erase("tutorials")
	var older := TycoonState.from_dict(d)
	_check(not MenuUnlocks.gradual(older) and MenuUnlocks.is_shown(older, "finance"), "a save from before the lessons too")
	for slot in TycoonSave.DEMOS:
		var ds := TycoonSave.load_state(slot)
		if ds:
			_check(not MenuUnlocks.gradual(ds), "demonstration %s has every menu open" % slot)


# ------------------------------------------------------------ on the main screen
func _main(slot := "") -> TycoonMain:
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	main.load_slot = slot
	get_root().add_child(main)
	await _frames(3)
	main.race_flow.autosave = false
	return main


func _in_game() -> void:
	HudUnlocker.allow_in_scripts = true
	TycoonTutorial.allow_in_scripts = true
	CwMotion.set_reduced(false)
	var main: TycoonMain = await _main()
	var hud := main.hud
	var unl := main.unlocks
	var tut := main.tutorial
	_check(unl != null and unl.get_script() == load("res://src/tycoon/tutorial/hud_unlocker.gd"), "the main screen has its HudUnlocker")
	_check(MenuUnlocks.gradual(main.state), "a new career on the main screen unlocks gradually")
	_check(hud.hud_node("%NewProject").visible and hud.hud_node("Settings").visible, "the mission board and the settings are on the HUD")
	for ref in ["Crew", "Research", "Contracts", "Finance", "Race", "Journal", "Map", "Book", "Side/Race", "%SolarMap"]:
		_check(not hud.hud_node(ref).visible and hud.is_locked(ref), "%s is hidden at the start" % ref)
	# the campus lesson first (it holds the reveals)
	await _wait(tut.campus_delay + 0.4)
	_check(tut.current_lesson() == "campus", "the campus lesson opens a new career (got '%s')" % tut.current_lesson())
	tut.skip()
	await _frames(2)
	var rail := hud.get_node("Rail") as Control
	_check(rail.size.y < 260.0, "the rail is short with only its first keys (%.0f px)" % rail.size.y)
	_check(not (hud.get_node("%VBox/Sep2") as Control).visible, "...and no empty group shows its separator")
	# M does nothing but hint while the map is locked
	_press(KEY_M)
	await _frames(3)
	_check(not main.modes.is_open(), "M does not open the locked Solar System map")
	_check(String(hud.get_node("%Hint").text) == tr("TY_UNL_LOCKED_HINT"), "...it hints instead ('%s')" % hud.get_node("%Hint").text)
	# a lot panel: the workshop hides its hangar key while locked
	hud.show_lot("workshop")
	await _frames(2)
	_check(not hud.get_node("%HangarButton").visible, "the workshop's hangar key is hidden while locked")
	tut.skip()
	hud.close_lot()
	await _frames(2)
	# the crew opens (a project) and pops in when the campus is free, with the badge and the lesson
	var shown: Array[String] = []
	unl.revealed.connect(func(id: String) -> void: shown.append(id))
	main.state.mission_projects.append(MissionProject.new())
	main.state.changed.emit()
	hud.open_screen("settings")
	await _frames(10)
	_check(shown.is_empty(), "nothing pops in while a screen is open")
	hud.close_screen()
	await _frames(4)
	_check(_same(shown, ["crew"]), "the crew pops in once the campus is free (%s)" % [shown])
	_check(hud.hud_node("Crew").visible and not hud.is_locked("Crew"), "the crew key is on the rail")
	var badges := 0
	for c in unl.get_children():
		if c != unl.template and c.visible:
			badges += 1
	_check(badges >= 1, "the unlock badge plays over it (%d)" % badges)
	_check(String(hud.get_node("%Hint").text) == tr("TY_UNL_NEW") % tr("TY_MENU_CREW"), "the hint names the new menu")
	await _wait(unl.lesson_delay + 0.2)
	_check(tut.current_lesson() == "unlock_crew", "Vovô tells the crew's lesson (got '%s')" % tut.current_lesson())
	_check(tut.current_target() == hud.hud_node("Crew"), "...pointing at the new key")
	var hidden_by := []
	var crew_btn := hud.hud_node("Crew")
	if crew_btn.has_meta(CwMotion.META):
		var chans: Dictionary = (crew_btn.get_meta(CwMotion.META) as CwMotion.Vis).channels
		for k in chans:
			if float(chans[k][3]) < 1.0:
				hidden_by.append(k)
	_check(hidden_by.is_empty(), "the new key ends fully drawn (no motion channel left fading it: %s)" % [hidden_by])
	(hud.hud_node("Crew") as Button).pressed.emit()
	await _frames(4)
	_check(hud.current_screen() == "crew", "clicking the new key opens the crew")
	_check(tut.current_lesson() == "crew", "...where the crew's own lesson goes on (got '%s')" % tut.current_lesson())
	tut.skip()
	hud.close_screen()
	await _frames(3)
	# the hangar comes next, after its gap, opening the workshop's panel
	await _wait(unl.reveal_gap + unl.lesson_delay + 0.3)
	_check(shown.has("hangar") and hud.lot_id == "workshop" and hud.get_node("%HangarButton").visible,
		"the hangar pops in next, in the workshop's panel (%s)" % [shown])
	await _wait(unl.lesson_delay + 0.2)
	_check(tut.current_lesson() == "unlock_hangar", "...with its lesson (got '%s')" % tut.current_lesson())
	tut.skip()
	hud.close_lot()
	await _frames(2)
	# a screen opened by another way: its key pops in later without the lesson
	hud.open_screen("journal")
	await _frames(3)
	_check(MenuUnlocks.is_open(main.state, "journal") and not hud.hud_node("Journal").visible, "opening the journal opens its key, still hidden under the screen")
	tut.skip()
	hud.close_screen()
	await _wait(unl.reveal_gap + unl.lesson_delay + 0.4)
	_check(hud.hud_node("Journal").visible, "the journal key pops in after the screen closes")
	_check(tut.current_lesson() != "unlock_journal" and not TutorialBook.seen(main.state, "unlock_journal"), "...without its lesson (the screen had its own)")
	# save and load the career on the main screen
	_check(TycoonSave.save(main.state, SLOT) == OK, "the career saves from the main screen")
	main.queue_free()
	await _frames(3)
	var back: TycoonMain = await _main(SLOT)
	var bh := back.hud
	_check(MenuUnlocks.gradual(back.state), "the loaded career still unlocks gradually")
	_check(bh.hud_node("Crew").visible and bh.hud_node("Journal").visible and not bh.hud_node("Finance").visible
		and not bh.hud_node("Side/Race").visible, "the loaded HUD shows what the career had unlocked")
	# Já sei jogar
	TutorialBook.mark_seen(back.state, "library")
	bh.open_screen("library")
	await _frames(3)
	var lib := bh.get_node("%Screens").get_child(0) as LibraryScreen
	_check(lib != null and not (lib.get_node("%KnowHow") as Button).disabled, "the library has 'Já sei jogar'")
	if lib:
		(lib.get_node("%KnowHow") as Button).pressed.emit()
		await _frames(2)
		_check(not MenuUnlocks.gradual(back.state), "'Já sei jogar' opens every menu of the career")
		_check((lib.get_node("%KnowHow") as Button).disabled, "...and the key greys out")
	bh.close_screen()
	await _frames(3)
	var all_visible := true
	for ref in ["Crew", "Research", "Contracts", "Finance", "Race", "Journal", "Map", "Book", "Side/Race", "%SolarMap"]:
		if not bh.hud_node(ref).visible:
			all_visible = false
			print("    still hidden: ", ref)
	_check(all_visible, "every menu is on the HUD")
	var full_rail := bh.get_node("Rail") as Control
	_check(full_rail.size.y > 500.0 and (bh.get_node("%VBox/Sep2") as Control).visible,
		"the rail grew to hold every key, separators back (%.0f px)" % full_rail.size.y)
	back.queue_free()
	await _frames(3)
	# the global switch: off, a new career has every menu
	MenuUnlocks.set_enabled_for_new(false)
	var plain: TycoonMain = await _main()
	_check(not MenuUnlocks.gradual(plain.state) and plain.hud.hud_node("Finance").visible, "with 'menus one at a time' off a new career shows every menu")
	plain.queue_free()
	await _frames(3)
	MenuUnlocks.set_enabled_for_new(true)
	HudUnlocker.allow_in_scripts = false
	TycoonTutorial.allow_in_scripts = false


func _scripts_default() -> void:
	var quiet: TycoonMain = await _main()
	_check(not MenuUnlocks.gradual(quiet.state), "test scripts get careers with every menu open")
	_check(quiet.hud.hud_node("Crew").visible and quiet.hud.hud_node("Side/Race").visible, "...so every menu is on their HUD")
	quiet.queue_free()
	await _frames(3)


# ------------------------------------------------------------ helpers
func _same(a: Array, b: Array) -> bool:
	return str(a) == str(b)


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
