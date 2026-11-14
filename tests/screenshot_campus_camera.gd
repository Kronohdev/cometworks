extends SceneTree
## Windowed screenshots of the campus camera (src/tycoon/campus_camera.gd) on the Cometworks
## main screen, driven through real input events where it matters:
##   cam_01_default            the start view
##   cam_02_zoom               after wheel notches over the plaza (zoom to the cursor)
##   cam_03_follow_a .. _f     a click on a walking Cometling, then the follow shot over time
##   cam_04_release_a / _b     Esc: easing back to the free view
##   cam_05_lot_a / _b         a click on the workshop lot: the camera frames the building
##   cam_06_tour_a / _b        the idle tour
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


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = at
		ev.global_position = at
		ev.pressed = pressed
		get_root().push_input(ev)


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
