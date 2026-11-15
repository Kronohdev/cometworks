extends "res://tests/screenshot_tycoon_tracking.gd"
## Windowed screenshots of the launch watch's speed key and "Simular até o fim", and of the comic
## recap told by Vovô Edmundo (FlightComic) with its report page:
##   comic_01_watch_speed    a live lunar landing launch in the 3D view at 4x (the speed key, the skip key)
##   comic_02_page1          the comic after the skip: page 1 (liftoff, max-Q, boosters...)
##   comic_03_page2          page 2 (the Moon, the landing, the rover, the ending)
##   comic_04_report         the last page: outcome, rewards, "Por que foi assim?", the tip
##   comic_05_fail_page      a failed launch's comic (the break-up)
##   comic_06_fail_report    its report (what broke, bad luck or an open risk)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_flight_comic.gd -- <out_dir> [en|pt_BR]

var _fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		TranslationServer.set_locale(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	main.state.weeks = 40
	# a lander for the Moon with a rover, launched now
	var r := _result("CMX1", "POU-07", "lander", "lunar_surface", "partial", {"instrument": 0.42, "power": 1.0,
		"data": 0.95, "team": 1.0})
	var run := main.modes.start_launch(r)
	_check(run != null, "the launch has its flight")
	for i in 120:
		run.advance(0.02)
	_check(main.modes.open_launch_flight(Vector3(14.0, 6.0, 9.0)), "the watch opens")
	await _frames(20)
	var lw := main.modes.overlay as LaunchWatch
	var w := main.modes.mode_node as FlightWorld
	if lw == null or w == null:
		_done()
		return
	lw.cycle_speed()
	lw.cycle_speed()
	await _frames(90)
	_check(w.warp == 4 and (lw.get_node("%Speed") as Button).text == "4×", "the speed key reads 4× (%s)" % (lw.get_node("%Speed") as Button).text)
	await _shot("comic_01_watch_speed")
	lw.skip_to_end()
	await _until(func() -> bool: return lw.comic != null, 4000)
	_check(lw.comic != null and lw.skipped, "the skip ends with the comic")
	if lw.comic == null:
		_done()
		return
	var comic := lw.comic as FlightComic
	_check(comic.panels.size() >= 5, "the comic has %d panels" % comic.panels.size())
	await _reveal(comic)
	await _shot("comic_02_page1")
	_check_fit(comic, "page 1")
	if comic.page_count() > 1:
		comic.advance()
		await _frames(5)
		await _reveal(comic)
		await _shot("comic_03_page2")
		_check_fit(comic, "page 2")
	comic.show_report()
	await _frames(30)
	await _shot("comic_04_report")
	_check_fit(comic, "report")
	comic.finish("done")
	await _frames(10)
	_check((lw.get_node("%Result") as Control).visible, "after the comic the result card")
	w.revert_to_hangar()
	await _frames(20)
	# a failure
	var rf := _result("CMX2", "ORB-13", "demo_sat", "leo", "fail", {"instrument": 1.0, "power": 1.0, "data": 1.0, "team": 1.0})
	rf["cause_key"] = "TY_RK_CAUSE_STAGE1"
	main.modes.launch_run = null
	var runf := main.modes.start_launch(rf)
	if runf:
		for i in 60:
			runf.advance(0.02)
	_check(main.modes.open_launch_flight(), "the failed launch's watch opens")
	await _frames(20)
	lw = main.modes.overlay as LaunchWatch
	if lw:
		lw.skip_to_end()
		await _until(func() -> bool: return lw.comic != null, 3000)
		comic = lw.comic as FlightComic
		if comic:
			await _reveal(comic)
			await _shot("comic_05_fail_page")
			comic.show_report()
			await _frames(30)
			await _shot("comic_06_fail_report")
			_check_fit(comic, "fail report")
	_done()


func _result(pid: String, code: String, type_id: String, target: String, outcome: String, fit: Dictionary) -> Dictionary:
	var e := {"id": pid, "project_id": pid, "code": code, "type": type_id, "target": target, "outcome": outcome,
		"success": outcome != "fail", "week": main.state.weeks, "grade": 4.6, "grade_project": 4.6, "p_success": 0.82,
		"bars": [5.0, 5.0, 5.0, 5.0], "reviews": [], "rocket": {}, "pad": "pad", "fit": fit,
		"risks": [{"id": "stage1", "kind": "rocket", "name_key": "TY_RK_RISK_STAGE1", "p": 0.06, "fixed": true}],
		"rewards": {"cash": 18500.0 if outcome != "fail" else -4200.0, "reputation": 1.4 if outcome != "fail" else -2.0,
			"hype": 3.2}, "cause_key": ""}
	main.state.project_history.append(e)
	SpaceTracking.sync(main.state)
	return e


## Every panel of the page in at once (the pop takes a moment each).
func _reveal(comic: FlightComic) -> void:
	for i in FlightComic.PER_PAGE:
		if comic._revealed < comic._visible_panels().size():
			comic.advance()
	await _frames(40)


## The page inside the window and its panels inside the page.
func _check_fit(comic: FlightComic, tag: String) -> void:
	var view := get_root().get_visible_rect().grow(2.0)
	var page := (comic.get_node("%Page") as Control).get_global_rect()
	_check(view.encloses(page), "%s: the page inside the window (%s)" % [tag, page])
	for c in comic.get_node("%Grid").get_children():
		if c.visible and bool(c.get_meta("used", false)) and c.is_visible_in_tree():
			_check(page.grow(2.0).encloses((c as Control).get_global_rect()), "%s: a panel inside the page" % tag)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _done() -> void:
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
