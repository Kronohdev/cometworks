extends SceneTree
## Windowed screenshots of the campus camera (src/tycoon/campus_camera.gd) on the Cometworks
## main screen, driven through real input events where it matters:
##   cam_01_default            the start view
##   cam_02_zoom               after wheel notches over the plaza (zoom to the cursor)
##   cam_03_follow_a .. _f     a click on a walking Cometling, then the follow shot over time
##   cam_04_release_a / _b     Esc: easing back to the free view
##   cam_05_lot_a / _b         a click on the workshop lot: the camera frames the building
##   cam_06_tour_a / _b        the idle tour
##   cam_07_home               Home: back to the start view
##   cam_08_orbit / 09_tilt    middle drag: turn around the cursor, then tilt
##   cam_10_pan / 11_shift_w   right drag pans, Shift + W pans fast
##   cam_12_close_low          zoomed in and tilted low (kept clear of the ground)
##   cam_13_follow_*           a followed Cometling, then a middle-drag orbit around it
##   cam_14_double_click_*     a double-click on the ground glides there
##   cam_15_options_camera     the Camera page of the options (pause menu)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_campus_camera.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain
var cam: CampusCamera


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(10)
	cam = main.camera
	cam.tour_enabled = false
	main.clock.set_speed(0)
	await _wait(2.0)
	await _shot("cam_01_default")

	# zoom towards the plaza with the wheel; the ground under the cursor must stay put
	var plaza := cam.unproject_position(Vector3(2.5, 0, 4.2))
	var before: Vector3 = cam._ground_hit(plaza)
	for i in 9:
		_wheel(plaza, true)
		await _wait(0.07)
	await _wait(1.6)
	var after: Vector3 = cam._ground_hit(plaza)
	print("zoom anchor drift: %.3f m (dist %.1f)" % [before.distance_to(after), exp(cam._cur_logd)])
	await _shot("cam_02_zoom")

	# follow a Cometling that is walking
	var who := await _walking_cometling()
	var head := who.global_position + Vector3(0, cam.cometling_head_height, 0)
	_click(cam.unproject_position(head))
	await _frames(2)
	print("following: %s" % [cam.followed()])
	await _wait(0.5)
	await _shot("cam_03_follow_a")
	await _wait(1.0)
	await _shot("cam_03_follow_b")
	for k in ["c", "d", "e", "f", "g", "h"]:
		await _wait(2.5)
		await _shot("cam_03_follow_" + k)

	# Esc lets go and eases back
	_key(KEY_ESCAPE)
	await _wait(0.6)
	await _shot("cam_04_release_a")
	await _wait(1.6)
	await _shot("cam_04_release_b")

	# click the workshop lot
	_click(cam.unproject_position(main.campus.lot_position("workshop")))
	await _wait(0.6)
	await _shot("cam_05_lot_a")
	await _wait(1.6)
	await _shot("cam_05_lot_b")
	_click(cam.unproject_position(main.campus.lot_position("pad")))
	await _wait(2.0)
	await _shot("cam_05_lot_c")

	# idle tour
	_key(KEY_ESCAPE)
	cam.tour_shot_seconds = 6.0
	cam.start_tour()
	await _wait(4.5)
	await _shot("cam_06_tour_a")
	await _wait(6.0)
	await _shot("cam_06_tour_b")
	await _wait(6.0)
	await _shot("cam_06_tour_c")

	# the newer controls: Home, middle-drag orbit and tilt, right-drag pan, Shift + W, a close
	# low view, orbiting a followed Cometling, a double-click glide, the options' Camera page
	var centre := get_root().get_visible_rect().size * 0.5
	_key(KEY_HOME)
	await _wait(1.8)
	await _shot("cam_07_home")
	await _drag(MOUSE_BUTTON_MIDDLE, centre + Vector2(160, 60), Vector2(300, 0), 24)
	await _wait(1.2)
	await _shot("cam_08_orbit")
	await _drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(0, -110), 14)
	await _wait(0.8)
	await _shot("cam_09_tilt")
	await _drag(MOUSE_BUTTON_RIGHT, centre, Vector2(-260, -140), 16)
	await _wait(1.0)
	await _shot("cam_10_pan")
	_hold(KEY_SHIFT, true)
	_hold(KEY_W, true)
	await _wait(0.5)
	_hold(KEY_W, false)
	_hold(KEY_SHIFT, false)
	await _wait(1.0)
	await _shot("cam_11_shift_w")
	_key(KEY_HOME)
	await _wait(1.5)
	for i in 14:
		_wheel(cam.unproject_position(Vector3(2.5, 0, 4.2)), true)
		await _wait(0.05)
	await _wait(1.6)
	await _drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(0, -200), 14)
	await _wait(1.0)
	print("close view: dist %.1f pitch %.1f cam y %.2f" % [cam.view_distance(), cam.view_pitch(), cam.global_position.y])
	await _shot("cam_12_close_low")
	_key(KEY_HOME)
	await _wait(1.5)
	_key(KEY_F)   # follows the Cometling nearest the centre
	await _wait(2.5)
	await _shot("cam_13_follow_a")
	await _drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(-320, 40), 24)
	await _wait(0.6)
	print("follow orbit: following %s" % [cam.followed()])
	await _shot("cam_13_follow_orbit")
	_key(KEY_ESCAPE)
	await _wait(1.8)
	var spot := centre + Vector2(-300, 140)
	_click(spot)
	await _frames(2)
	_click(spot, true)
	await _wait(0.45)
	await _shot("cam_14_double_click_a")
	await _wait(1.2)
	await _shot("cam_14_double_click_b")
	main.hud.open_screen("settings")
	await _wait(0.8)
	var tab := main.hud.find_child("PageCamera", true, false) as Button
	if tab:
		tab.pressed.emit()
	await _wait(0.6)
	await _shot("cam_15_options_camera")
	main.hud.close_screen()
	print("CAMERA SCREENSHOTS DONE")
	quit()


func _walking_cometling() -> Node3D:
	for tries in 200:
		var best: Node3D = null
		var best_d := INF
		for w in main.campus.cometlings():
			var cr := w.get_node("Creature")
			if float(cr.get("_speed")) > 0.1:
				var d := w.global_position.distance_to(Vector3(2.5, 0, 4.2))
				if d < best_d:
					best_d = d
					best = w
		if best:
			return best
		await _wait(0.1)
	return main.campus.cometlings()[0]


func _wheel(at: Vector2, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.position = at
	ev.global_position = at
	ev.pressed = true
	ev.factor = 1.0
	get_root().push_input(ev)


func _click(at: Vector2, double := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = at
		ev.global_position = at
		ev.pressed = pressed
		ev.double_click = double and pressed
		get_root().push_input(ev)


## A mouse drag with `button` over `steps` frames, then let go.
func _drag(button: MouseButton, from: Vector2, by: Vector2, steps: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = from
	ev.global_position = from
	ev.pressed = true
	get_root().push_input(ev)
	for i in steps:
		var mm := InputEventMouseMotion.new()
		mm.position = from + by * float(i + 1) / steps
		mm.global_position = mm.position
		mm.button_mask = 1 << (button - 1)
		get_root().push_input(mm)
		await process_frame
	await _wait(0.15)
	var up := ev.duplicate() as InputEventMouseButton
	up.position = from + by
	up.global_position = up.position
	up.pressed = false
	get_root().push_input(up)


## A key held down / let go (the camera polls WASD and Shift through Input).
func _hold(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		get_root().push_input(ev)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved %s" % path)
