extends "res://tests/screenshot_tycoon_tracking.gd"
## The launch watch's card on the flight's map (M), the bottom-left corner the player sees while
## following a launch: the card (LaunchWatch) stacked over the map's column (%Corner: the map bar
## over the hint pill). Checks that the three panels lie inside the window and do not overlap
## and that the warp hint draws its "," and "." keys as key caps:
##   watch_map_ascent   a lunar launch climbing, seen on the map
##   watch_3d_ascent    the same in the 3D view (the card at its own place)
## Run: godot --path . --resolution 1548x871 --script res://tests/screenshot_watch_map.gd -- <out_dir> [en|pt_BR]

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
	_seed_missions(main.state)
	await _frames(10)
	_check(main.modes.open_watch("LUA1"), "the launch watch opens")
	await _frames(30)
	var w := main.modes.mode_node as FlightWorld
	var lw := main.modes.overlay as LaunchWatch
	if w == null or lw == null:
		_done()
		return
	w.warp = 10
	await _frames(240)
	w.warp = 1
	await _shot("watch_3d_ascent")
	_check_card(lw, "3d")
	w.set_map(true)
	await _frames(40)
	await _shot("watch_map_ascent")
	_check_card(lw, "map")
	var corner := w.map.get_node("%Corner") as Control
	var card := lw.get_node("%Card") as Control
	var rects := {"card": card.get_global_rect(), "map bar": (w.map.get_node("%MapBar") as Control).get_global_rect()}
	var pill := w.map.get_node("%Hint").get_parent() as Control
	if pill.is_visible_in_tree():
		rects["hint pill"] = pill.get_global_rect()
	var names := rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			_check(not a.grow(-1.0).intersects(b.grow(-1.0)), "map: %s clear of %s (%s / %s)" % [names[i], names[j], a, b])
	_check(card.get_global_rect().end.y <= corner.get_global_rect().position.y, "map: the card above the map's column")
	_done()


func _check_card(lw: LaunchWatch, tag: String) -> void:
	var view := get_root().get_visible_rect().grow(4.0)
	var card := (lw.get_node("%Card") as Control).get_global_rect()
	_check(view.encloses(card), "%s: card inside the window (%s in %s)" % [tag, card, view])
	var hint := lw.get_node("%Hint") as RichTextLabel
	_check(hint.text.contains("[bgcolor") and hint.get_parsed_text().contains(" , "), "%s: the warp keys as key caps (%s)" % [tag, hint.get_parsed_text()])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])


func _done() -> void:
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
