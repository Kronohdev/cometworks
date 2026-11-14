extends SceneTree
## Page navigation of the in-game screens (src/tycoon/ui/nav/): every screen with pages has a
## CwPageStack and a breadcrumb; opening a detail goes one level down, Esc on the campus
## (TycoonMain -> TycoonHUD.screen_back) goes up one level before it closes the screen.
##   crew: roster -> click a card -> the Cometling's sheet -> Esc back to the roster -> Esc closes;
##         hire tab -> a candidate's card -> their sheet -> Esc back to the market
##   and the same walk on the other screens (research, contracts, finance, race, book, map,
##   settings, final score)
## Run: godot --headless --path . --script res://tests/test_ui_nav.gd

## the other screens with pages (each has open_detail(): the first item's detail page)
const PAGED: Array[String] = ["contracts", "research", "finance", "settings", "final_score", "book", "race", "map"]

var _fails := 0
var main: TycoonMain
var hud: TycoonHUD


func _initialize() -> void:
	CwMotion.set_reduced(true)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(3)
	hud = main.hud
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	TycoonCrew.ensure(main.state)
	# a few finished missions, so the book's archive has entries to open
	preload("res://tests/test_ui_fit.gd")._archive(main.state)
	# and two in space, for the map's mission page
	for m in [["DEM-04", "demo_sat", "leo"], ["ORB-01", "orbiter", "lunar_orbit"]]:
		main.state.active_missions.append({"id": m[0], "code": m[0], "type": m[1], "target": m[2],
			"start_week": main.state.weeks, "weeks_total": 0, "data_stored": 0.0, "data_down": 0.0, "science": 0.0,
			"status": "cruise", "grade": 7.0, "outcome": "full"})
	await _crew()
	await _screens()
	main.queue_free()
	await _frames(2)
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await _frames(3)


func _screen() -> Control:
	var layer := hud.get_node("%Screens")
	return layer.get_child(0) as Control if layer.get_child_count() > 0 else null


func _stack(scr: Node) -> CwPageStack:
	for n in get_nodes_in_group(&"cw_page_stack"):
		if scr.is_ancestor_of(n) and (n as CwPageStack).is_visible_in_tree():
			return n
	return null


## The first visible copy of `template` (a card made from a hidden template).
static func _first_copy(template: Node) -> Button:
	for c in template.get_parent().get_children():
		if c != template and c.has_meta("from_template") and (c as Control).visible:
			return c as Button
	return null


func _crew() -> void:
	print("crew")
	hud.open_screen("crew")
	await _frames(3)
	var scr := _screen() as CrewScreen
	_check(scr != null, "crew opens")
	if scr == null:
		return
	var pages := scr.get_node("%Pages") as CwPageStack
	var nav := scr.get_node("%NavBar") as CwNavBar
	_check(pages.current() == &"Roster" and pages.depth() == 0, "crew starts on the roster")
	var card := _first_copy(scr.get_node("%CardTemplate"))
	_check(card != null and card.get_node("Box/Name").text != "", "the roster shows Cometling cards")
	var cards := 0
	for c in scr.get_node("%Grid").get_children():
		cards += 1 if c.has_meta("from_template") and (c as Control).visible else 0
	_check(cards == main.state.staff.size(), "one card per Cometling (%d / %d)" % [cards, main.state.staff.size()])
	# filters
	var prof := String(main.state.staff[0]["profession"])
	scr.set_filter(prof, "")
	await _frames(2)
	var shown := 0
	var right := true
	for c in scr.get_node("%Grid").get_children():
		if c.has_meta("from_template") and (c as Control).visible:
			shown += 1
			right = right and String((c.get_meta("member") as Dictionary)["profession"]) == prof
	_check(shown > 0 and right, "a profession chip keeps only that profession (%d)" % shown)
	scr.set_filter("", "")
	await _frames(2)
	# a card opens the sheet
	card = _first_copy(scr.get_node("%CardTemplate"))
	var who := String(card.get_meta("id"))
	card.pressed.emit()
	await _frames(3)
	_check(pages.current() == &"Sheet" and pages.depth() == 1, "a card opens the Cometling's sheet")
	_check(scr.selected == who and scr.get_node("%CardName").text == String(TycoonCrew.find(main.state, who)["name"]),
		"the sheet is that Cometling's")
	_check(nav.get_node("%Back").visible and nav.get_node("%Crumbs").visible, "the sheet shows the back key and the breadcrumb")
	_check(nav.get_node("%Title").text == String(TycoonCrew.find(main.state, who)["name"]), "the title is the Cometling's name")
	await _esc()
	_check(hud.current_screen() == "crew" and pages.current() == &"Roster", "Esc goes back to the roster")
	_check(not nav.get_node("%Back").visible, "the roster has no back key")
	# hiring
	scr.get_node("%HireTab").pressed.emit()
	await _frames(3)
	_check(pages.current() == &"Hire" and pages.depth() == 0, "the hire tab opens the market")
	var cand := _first_copy(scr.get_node("%CandTemplate"))
	if cand:
		cand.pressed.emit()
		await _frames(3)
		_check(pages.current() == &"Sheet" and scr.sheet_kind == "cand" and scr.get_node("%HireButton").visible,
			"a candidate card opens the candidate's sheet with the hire key")
		await _esc()
		_check(pages.current() == &"Hire", "Esc goes back to the market")
	# the sheet straight from open_with (the leader / dev menu path)
	hud.open_screen("crew", {"staff_id": String(main.state.staff[0]["id"])})
	await _frames(3)
	scr = _screen() as CrewScreen
	pages = scr.get_node("%Pages") as CwPageStack
	_check(pages.current() == &"Sheet" and pages.depth() == 1, "open_with staff_id opens the sheet over the roster")
	await _esc()
	_check(pages.current() == &"Roster", "Esc: sheet -> roster")
	await _esc()
	_check(hud.current_screen() == "", "Esc on the roster closes the crew screen")
	await _wait(0.4)


## Every other screen with pages: a stack, and Esc at its top level closes it.
func _screens() -> void:
	print("other screens")
	for n: String in PAGED:
		if not hud.open_screen(n):
			_check(false, "%s opens" % n)
			continue
		await _frames(3)
		var scr := _screen()
		var st := _stack(scr)
		_check(st != null and st.depth() == 0, "%s has a page stack at its top level" % n)
		if st != null and scr.has_method("open_detail"):
			scr.call("open_detail")
			await _frames(3)
			var d := st.depth()
			var nav := scr.get_node_or_null("%NavBar") as CwNavBar
			_check(d >= 1, "%s opens a detail page (depth %d)" % [n, d])
			_check(nav == null or (nav.get_node("%Back").visible and nav.get_node("%Crumbs").visible),
				"%s: the detail page shows the back key and the breadcrumb" % n)
			# Esc climbs one level at a time, the screen stays open until its top level
			for k in d:
				await _esc()
				_check(hud.current_screen() == n and st.depth() == d - k - 1,
					"%s: Esc goes up one level (depth %d)" % [n, st.depth()])
		await _esc()
		_check(hud.current_screen() == "" if n != "final_score" else true, "%s: Esc at the top closes it" % n)
		hud.close_screen()
		await _wait(0.3)
