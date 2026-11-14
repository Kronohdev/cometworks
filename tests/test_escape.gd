extends SceneTree
## Esc always takes you back one step:
##   campus (src/tycoon/tycoon_main.gd): an open screen closes, then the lot panel, then the
##   followed Cometling is let go; with nothing open Esc brings up the pause menu (the
##   settings screen), which holds the clock still and gives its speed back when it closes
##   a conversation with a Cometling (src/tycoon/talk/cometling_dialogue.gd): Esc closes the
##   box first, and only it (the camera keeps following the Cometling)
##   a lesson bubble of Vovô Edmundo (src/tycoon/tutorial/tycoon_tutorial.gd) on show: Esc
##   skips it first, and only it (on the campus and over a screen); the chain goes on after
##   hangar (src/hangar/hangar.gd): Esc with empty hands, or the Menu button, goes back to
##   the main menu
## Run: godot --headless --path . --script res://tests/test_escape.gd

const MENU := "res://scenes/menu/main_menu.tscn"

var _failures := 0


func _initialize() -> void:
	await _campus()
	await _hangar()
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _campus() -> void:
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	get_root().add_child(main)
	await _frames(3)
	main.race_flow.autosave = false
	main.clock.set_speed(2)

	# a lesson bubble takes the first Esc, and only that one
	main.tutorial.start("campus", true)
	await _frames(2)
	_check(main.tutorial.is_showing(), "a lesson bubble is on show")
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(not main.tutorial.is_showing(), "Esc skips the lesson bubble")
	_check(main.hud.current_screen() == "", "...without opening the pause menu")
	_check(main.clock.speed == 2, "...and the clock gets its speed back (got %d)" % main.clock.speed)
	main.hud.open_screen("crew")
	await _frames(2)
	main.tutorial.start("crew", true)
	await _frames(2)
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(not main.tutorial.is_showing() and main.hud.current_screen() == "crew",
		"over a screen, Esc skips the bubble and leaves the screen open")
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(main.hud.current_screen() == "", "the next Esc closes the screen")

	_press(KEY_ESCAPE)
	await _frames(2)
	_check(main.hud.current_screen() == "settings", "Esc on the bare campus opens the pause menu (got '%s')" % main.hud.current_screen())
	_check(main.clock.speed == 0, "the pause menu holds the clock")
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(main.hud.current_screen() == "", "Esc closes the pause menu")
	_check(main.clock.speed == 2, "the clock picks up its speed again (got %d)" % main.clock.speed)

	main.hud.open_screen("crew")
	await _frames(2)
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(main.hud.current_screen() == "", "Esc closes an open screen first")

	var lot: String = main.state.lot_ids()[0]
	main.hud.show_lot(lot)
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(main.hud.lot_id == "", "Esc closes the lot panel")
	_check(main.hud.current_screen() == "", "...without opening the pause menu")

	var who: Array = main.campus.cometlings()
	if not who.is_empty() and main.talk:
		# a conversation takes the first Esc, and only that one
		main.camera.follow(who[0])
		await _frames(2)
		_check(main.talk.open(who[0]), "a conversation opens on a Cometling")
		_press(KEY_ESCAPE)
		await _frames(2)
		_check(not main.talk.is_open(), "Esc closes the conversation")
		_check(main.camera.mode == CampusCamera.Mode.FOLLOW and main.hud.current_screen() == "",
			"...and only it (the camera still follows, no pause menu)")
	if not who.is_empty():
		main.camera.follow(who[0])
		await _frames(2)
		_press(KEY_ESCAPE)
		await _frames(2)
		_check(main.camera.mode != CampusCamera.Mode.FOLLOW, "Esc lets go of the followed Cometling")
		_check(main.hud.current_screen() == "", "...without opening the pause menu")
	main.queue_free()
	await _frames(2)


func _hangar() -> void:
	change_scene_to_file("res://scenes/hangar.tscn")
	await _frames(6)
	var hangar := current_scene
	_check(hangar != null and hangar.scene_file_path == "res://scenes/hangar.tscn", "the hangar opens")
	_check(hangar.get_node_or_null("%BtnMenu") != null or hangar.find_child("BtnMenu", true, false) != null, "the hangar has a Menu button")
	_press(KEY_ESCAPE)
	await _frames(6)
	_check(current_scene != null and current_scene.scene_file_path == MENU,
		"Esc with empty hands goes back to the main menu (now '%s')" % (current_scene.scene_file_path if current_scene else "none"))


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
