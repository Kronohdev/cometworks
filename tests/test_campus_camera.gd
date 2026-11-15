extends SceneTree
## The campus camera (src/tycoon/campus_camera.gd), driven by real input events:
##   middle drag orbits (turns around the ground point under the cursor, tilts within limits),
##   right drag grabs the ground and pans, Shift swaps them, the orbit button can be swapped
##   WASD pans relative to the view, Shift is faster; + / - and the wheel zoom within the limits
##   the soft bounds pull the view back onto the plateau; flung drags settle (springs, momentum)
##   follow: middle drag orbits around the Cometling without letting go; F re-frames, Home resets
##   the camera keeps above the ground and over building footprints
##   cinematics take the view over (input ignored) and give it back
##   input_gate (a screen open) switches the camera's input off
##   campus: a HUD panel (mouse_filter STOP) eats the wheel, an open screen stops WASD, a
##   double-click on the ground glides there
## The bare camera is stepped by hand (fixed 1/60 s frames) so the numbers are repeatable.
## Run: godot --headless --path . --script res://tests/test_campus_camera.gd

const DT := 1.0 / 60.0

var _failures := 0
var cam: CampusCamera
var world: Node3D


func _initialize() -> void:
	await _bare()
	await _robust()
	await _campus()
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


# ------------------------------------------------------------ bare camera
func _new_cam() -> void:
	if world:
		world.queue_free()
		await process_frame
	world = Node3D.new()
	get_root().add_child(world)
	cam = CampusCamera.new()
	cam.use_saved_settings = false
	cam.tour_enabled = false
	cam.tilt_shift = false
	world.add_child(cam)
	cam.current = true
	cam.set_process(false)   # stepped by hand
	await process_frame
	_step(0.1)


func _bare() -> void:
	await _new_cam()
	var centre := _centre()

	# --- middle drag orbits: the yaw turns, the ground point under the cursor stays put
	var grab := centre + Vector2(160, 60)
	var under: Vector3 = cam._ground_hit(grab)
	var yaw0 := cam.view_yaw()
	_drag(MOUSE_BUTTON_MIDDLE, grab, Vector2(120, 0), 12)
	_check(absf(cam.view_yaw() - yaw0 + 36.0) < 1.0, "middle drag turns the view (yaw %.1f -> %.1f, want -36)" % [yaw0, cam.view_yaw()])
	cam._apply(cam._free_pose(), Vector3.ZERO)
	var pivot_px := cam.unproject_position(under)
	_check(pivot_px.distance_to(grab) < 3.0, "...around the ground point under the cursor (moved %.1f px)" % pivot_px.distance_to(grab))
	var p0 := cam.view_pitch()
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(0, -60), 6)
	_check(cam.view_pitch() < p0 - 8.0, "dragging up tilts towards the horizon (%.1f -> %.1f)" % [p0, cam.view_pitch()])
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(0, -2000), 20)
	_check(cam.view_pitch() >= cam.pitch_min_deg - 0.01, "...but never under pitch_min_deg (%.1f)" % cam.view_pitch())
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(0, 4000), 20)
	_check(cam.view_pitch() <= cam.pitch_max_deg + 0.01, "...nor over pitch_max_deg (%.1f)" % cam.view_pitch())
	cam.invert_rotate = true
	var y1 := cam.view_yaw()
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(50, 0), 5)
	_check(cam.view_yaw() > y1 + 10.0, "invert_rotate turns the other way")
	cam.invert_rotate = false
	cam.rotate_sensitivity = 2.0
	y1 = cam.view_yaw()
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(50, 0), 5)
	_check(absf((y1 - cam.view_yaw()) - 30.0) < 1.0, "rotate_sensitivity 2 doubles the turn (%.1f)" % (y1 - cam.view_yaw()))
	cam.rotate_sensitivity = 1.0
	_step(3.0)

	# --- right drag pans: the ground under the cursor follows it, the yaw stays
	await _new_cam()
	var at := centre + Vector2(-100, 40)
	var ground: Vector3 = cam._ground_hit(at)
	var f0 := cam.view_focus()
	yaw0 = cam.view_yaw()
	_drag(MOUSE_BUTTON_RIGHT, at, Vector2(140, 70), 10)
	cam._apply(cam._free_pose(), Vector3.ZERO)
	_check(cam.view_focus().distance_to(f0) > 5.0, "right drag pans (moved %.1f m)" % cam.view_focus().distance_to(f0))
	_check(cam.unproject_position(ground).distance_to(at + Vector2(140, 70)) < 4.0,
		"...grabbing the ground under the cursor (off by %.1f px)" % cam.unproject_position(ground).distance_to(at + Vector2(140, 70)))
	_check(absf(cam.view_yaw() - yaw0) < 0.01, "...without turning")
	# Shift + right drag orbits instead, and swapping the buttons makes right orbit
	yaw0 = cam.view_yaw()
	_drag(MOUSE_BUTTON_RIGHT, centre, Vector2(60, 0), 6, false, true)
	_check(cam.view_yaw() < yaw0 - 10.0, "Shift + right drag turns the view")
	cam.apply_settings({"orbit_button": "right"})
	yaw0 = cam.view_yaw()
	f0 = cam.view_focus()
	_drag(MOUSE_BUTTON_RIGHT, centre, Vector2(60, 0), 6)
	_check(cam.view_yaw() < yaw0 - 10.0, "orbit_button = right: right drag turns")
	f0 = cam.view_focus()
	yaw0 = cam.view_yaw()
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(80, 30), 6)
	_check(cam.view_focus().distance_to(f0) > 3.0 and absf(cam.view_yaw() - yaw0) < 0.01, "...and middle drag pans")
	cam.apply_settings({"orbit_button": "middle"})

	# --- inertia: a flung drag keeps going for a moment, then settles completely
	await _new_cam()
	f0 = cam.view_focus()
	_drag(MOUSE_BUTTON_RIGHT, centre, Vector2(300, 0), 10, true)
	var at_release := cam.view_focus()
	_step(0.3)
	var drift := cam.view_focus().distance_to(at_release)
	_check(drift > 1.0, "a flung pan keeps its momentum (%.1f m after letting go)" % drift)
	_step(5.0)
	var settled := cam.view_focus()
	_step(1.0)
	_check(cam.view_focus().distance_to(settled) < 0.01 and cam._pan_vel.length() < 0.01,
		"...and settles (still moving %.4f m/s)" % (cam.view_focus().distance_to(settled)))
	yaw0 = cam.view_yaw()
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(200, 0), 10, true)
	var yaw_release := cam.view_yaw()
	_step(0.3)
	_check(absf(cam.view_yaw() - yaw_release) > 2.0, "a flung orbit keeps turning (%.1f deg)" % absf(cam.view_yaw() - yaw_release))
	_step(4.0)
	var yaw_settled := cam.view_yaw()
	_step(1.0)
	_check(absf(cam.view_yaw() - yaw_settled) < 0.01, "...and settles")
	# a drag held still before letting go does not fling
	f0 = cam.view_focus()
	_press(MOUSE_BUTTON_RIGHT, centre, true)
	_motion(centre + Vector2(80, 0))
	_step(DT)
	_step(0.2)
	_press(MOUSE_BUTTON_RIGHT, centre + Vector2(80, 0), false)
	var held := cam.view_focus()
	_step(1.0)
	_check(cam.view_focus().distance_to(held) < 0.3, "a drag held still lands where it is (%.2f m)" % cam.view_focus().distance_to(held))

	# --- springs: Q turns by a step, eased, without overshoot
	await _new_cam()
	yaw0 = cam.view_yaw()
	_key(KEY_Q)
	var over := false
	var last := yaw0
	for i in 180:
		_step(DT)
		if cam.view_yaw() < yaw0 - cam.rotate_step_deg - 0.01:
			over = true
		last = cam.view_yaw()
	_check(absf(last - (yaw0 - cam.rotate_step_deg)) < 0.05 and not over, "Q turns one step, eased, no overshoot (%.2f)" % last)

	# --- WASD pans relative to the view, Shift is faster
	await _new_cam()
	for yaw in [0.0, 90.0, 215.0]:
		cam._goal_yaw = yaw
		cam._cur_yaw = yaw
		_step(0.1)
		f0 = cam.view_focus()
		await _hold(KEY_W, 0.5)
		var moved := cam.view_focus() - f0
		var fwd := Vector3(-sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
		_check(moved.length() > 5.0 and moved.normalized().dot(fwd) > 0.98,
			"W moves forward at yaw %d (dot %.3f, %.1f m)" % [yaw, moved.normalized().dot(fwd), moved.length()])
		cam._goal_focus = Vector3.ZERO
		cam._cur_focus = Vector3.ZERO
		cam._focus_vel = Vector3.ZERO
		_step(0.1)
	cam._goal_yaw = 30.0
	cam._cur_yaw = 30.0
	f0 = cam.view_focus()
	await _hold(KEY_D, 0.5)
	var right := Vector3(cos(deg_to_rad(30.0)), 0, -sin(deg_to_rad(30.0)))
	_check((cam.view_focus() - f0).normalized().dot(right) > 0.98, "D moves right of the view")
	cam._goal_focus = Vector3.ZERO
	cam._cur_focus = Vector3.ZERO
	_step(0.1)
	f0 = cam.view_focus()
	await _hold(KEY_S, 0.5)
	var slow := cam.view_focus().distance_to(f0)
	cam._goal_focus = Vector3.ZERO
	cam._cur_focus = Vector3.ZERO
	_step(0.1)
	f0 = cam.view_focus()
	await _hold(KEY_S, 0.5, true)
	var quick := cam.view_focus().distance_to(f0)
	_check(quick > slow * 1.8, "Shift pans faster (%.1f m vs %.1f m)" % [quick, slow])

	# --- zoom: the wheel zooms to the cursor and the distance stays within the limits
	await _new_cam()
	var spot := centre + Vector2(120, 80)
	var spot_ground: Vector3 = cam._ground_hit(spot)
	for i in 4:
		_wheel(spot, true)
		_step(0.05)
	_step(2.0)
	cam._apply(cam._free_pose(), Vector3.ZERO)
	_check(cam.unproject_position(spot_ground).distance_to(spot) < 4.0, "the wheel zooms towards the cursor (drift %.1f px)" % cam.unproject_position(spot_ground).distance_to(spot))
	var p_mid := cam.view_pitch()
	for i in 60:
		_wheel(centre, true)
		_step(0.02)
	_step(3.0)
	_check(cam.view_distance() >= cam.min_distance * 0.98, "zoom in stops at min_distance (%.2f)" % cam.view_distance())
	var p_close := cam.view_pitch()
	for i in 80:
		_wheel(centre, false)
		_step(0.02)
	_step(3.0)
	_check(cam.view_distance() <= cam.max_distance * 1.02, "zoom out stops at max_distance (%.1f)" % cam.view_distance())
	var p_far := cam.view_pitch()
	_check(p_close < p_mid and p_mid < p_far, "the view tilts down when zoomed out, flatter close in (%.1f < %.1f < %.1f)" % [p_close, p_mid, p_far])
	cam._goal_logd = log(60.0)
	cam._cur_logd = cam._goal_logd
	cam.invert_zoom = true
	var d0 := cam.view_distance()
	for i in 3:
		_wheel(centre, true)
	_step(2.0)
	_check(cam._goal_logd > log(d0) + 0.05, "invert_zoom: wheel up zooms out")
	cam.invert_zoom = false
	var d1 := cam.view_distance()
	await _hold(KEY_EQUAL, 0.5)
	_step(1.5)
	_check(cam.view_distance() < d1 * 0.8, "+ zooms in (%.1f -> %.1f)" % [d1, cam.view_distance()])

	# --- soft bounds
	await _new_cam()
	cam._goal_focus = Vector3(cam.bounds.end.x + 60.0, 0, cam.bounds.position.y - 40.0)
	_step(4.0)
	var f := cam.view_focus()
	_check(f.x <= cam.bounds.end.x + 0.5 and f.z >= cam.bounds.position.y - 0.5, "the soft bounds pull the view back in (%.1f, %.1f)" % [f.x, f.z])
	await _hold(KEY_D, 3.0, true)
	var pushed := cam.view_focus().x - cam.bounds.end.x
	_check(pushed < cam.bounds_softness * 1.5, "holding a pan against the edge only stretches a little (%.1f m past)" % pushed)
	_step(4.0)
	_check(cam.view_focus().x <= cam.bounds.end.x + 0.5, "...and springs back when let go")

	# --- clearance: never under the ground or into a roof
	await _new_cam()
	cam.pitch_min_deg = 3.0
	for i in 60:
		_wheel(centre, true)
	_step(3.0)
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(0, -3000), 10)
	_step(1.0)
	_check(cam.global_position.y >= cam.min_height - 0.05, "the camera keeps over min_height (y %.2f)" % cam.global_position.y)
	var c := cam.global_position
	cam.obstacles = [Rect2(Vector2(c.x, c.z) - Vector2(6, 6), Vector2(12, 12))]
	cam.obstacle_heights = PackedFloat32Array([7.0])
	_step(3.0)
	_check(cam.global_position.y >= 7.5, "...and over a building's roof (y %.2f)" % cam.global_position.y)
	cam.obstacles = []
	cam.obstacle_heights = PackedFloat32Array()

	# --- Home goes back to the start view
	await _new_cam()
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(150, 40), 8)
	_drag(MOUSE_BUTTON_RIGHT, centre, Vector2(-200, 100), 8)
	_key(KEY_HOME)
	_step(2.0)
	_check(cam.view_focus().distance_to(Vector3(cam.focus.x, 0, cam.focus.z)) < 0.1
		and absf(angle_difference(deg_to_rad(cam.view_yaw()), deg_to_rad(cam.yaw_deg))) < 0.01
		and absf(cam.view_distance() - cam.distance) < 0.1, "Home resets the view")

	# --- follow: middle drag orbits around the Cometling, F re-frames
	await _new_cam()
	var walker := Node3D.new()
	world.add_child(walker)
	walker.global_position = Vector3(6, 0, -4)
	cam.tour_source = func() -> Array: return [{"node": walker}]
	_key(KEY_F)
	_check(cam.followed() == walker, "F follows the Cometling nearest the centre when nobody is followed")
	_step(3.0)
	var fy0: float = cam._fpose.yaw
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(-100, 30), 8)
	_check(cam.is_following(), "a middle drag keeps following")
	_check(absf(cam._fpose.yaw - fy0 - 30.0) < 4.0, "...and orbits around the Cometling (%.1f deg)" % (cam._fpose.yaw - fy0))
	_step(2.0)
	var head := walker.global_position + Vector3(0, cam.follow_height, 0)
	_check(cam.unproject_position(head).distance_to(centre) < 60.0, "...keeping it in the middle of the shot (%.0f px)" % cam.unproject_position(head).distance_to(centre))
	for i in 5:
		_wheel(centre, false)
	_step(2.0)
	_check(cam._follow_zoom > 1.5, "the wheel pulls back from the Cometling")
	_key(KEY_F)
	_step(2.0)
	_check(is_equal_approx(cam._follow_zoom, 1.0) and cam._user_yaw == 0.0, "F re-frames the followed Cometling")
	# a walking Cometling: the shot leads it smoothly
	for i in 240:
		walker.global_position += Vector3(2.0 * DT, 0, 0)
		_step(DT)
	_check(cam._fpose.focus.x > walker.global_position.x + 0.3, "the follow shot leads the walk (focus %.2f ahead)" % (cam._fpose.focus.x - walker.global_position.x))
	_drag(MOUSE_BUTTON_RIGHT, centre, Vector2(80, 0), 8)
	_check(cam.mode == CampusCamera.Mode.FREE, "a right drag lets go and pans")

	# --- cinematics take over and give back
	await _new_cam()
	var rig := Camera3D.new()
	world.add_child(rig)
	rig.global_transform = Transform3D(Basis.looking_at(Vector3(-1, -0.3, 0.2)), Vector3(30, 12, -20))
	rig.fov = 50.0
	var before_d := cam.view_distance()
	var before_f := cam.view_focus()
	cam.begin_cinematic(rig, 0.5)
	_check(cam.is_cinematic(), "begin_cinematic takes the view")
	_step(1.0)
	_check(cam.global_position.distance_to(rig.global_position) < 0.01 and is_equal_approx(cam.fov, 50.0), "...and sits on the rig")
	_wheel(centre, true)
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(100, 0), 5)
	await _hold(KEY_W, 0.3)
	_key(KEY_HOME)
	_step(0.2)
	_check(cam.global_position.distance_to(rig.global_position) < 0.01, "player input does not move a cinematic")
	rig.global_position += Vector3(5, 0, 0)
	_step(DT)
	_check(cam.global_position.distance_to(rig.global_position) < 0.01, "...which follows the rig as it moves")
	cam.end_cinematic(0.6)
	_check(cam.mode == CampusCamera.Mode.FREE, "end_cinematic gives the view back")
	_step(1.5)
	_check(absf(cam.view_distance() - before_d) < 0.5 and cam.view_focus().distance_to(before_f) < 0.5,
		"...to the free view as the player left it")
	cam._apply(cam._free_pose(), Vector3.ZERO)
	var free_pos := cam.global_position
	_step(DT)
	_check(cam.global_position.distance_to(free_pos) < 0.05, "...once the blend is over")

	# --- input gate: no input while a screen is open
	await _new_cam()
	cam.input_gate = func() -> bool: return false
	f0 = cam.view_focus()
	var g0: float = cam._goal_logd
	_wheel(centre, true)
	_drag(MOUSE_BUTTON_MIDDLE, centre, Vector2(80, 0), 4)
	await _hold(KEY_W, 0.3)
	_step(0.5)
	_check(is_equal_approx(cam._goal_logd, g0) and cam.view_focus().distance_to(f0) < 0.01, "input_gate off: wheel, drags and keys do nothing")
	world.queue_free()
	world = null
	await process_frame


# ------------------------------------------------------------ robustness
## Stress cases: the pivot never leaves the island's soft bounds, the zoom stays in its range
## and the view never jumps, whatever the mouse does and however uneven the frames are.
func _robust() -> void:
	# --- a pan drag from near the horizon (low pitch, cursor at the top of the screen): the
	# ground rays there span hundreds of metres per pixel
	await _new_cam()
	var vs := _view_size()
	_drag(MOUSE_BUTTON_MIDDLE, _centre(), Vector2(0, -3000), 10)   # tilt down to pitch_min
	_step(2.0)
	var worst := 0.0
	var outside := false
	# just under the horizon line: the first screen row whose ray meets the ground
	var top := Vector2(vs.x * 0.5, 0.0)
	cam._apply(cam._free_pose(), Vector3.ZERO)
	while top.y < vs.y and cam._ground_hit(top) == null:
		top.y += 1.0
	top.y += 1.0
	var start := cam.view_focus()
	_press(MOUSE_BUTTON_RIGHT, top, true)
	for i in 40:
		var f0 := cam.view_focus()
		_motion(top + Vector2(0, 2.0 * (i + 1)))
		_step(DT)
		worst = maxf(worst, cam.view_focus().distance_to(f0) / cam.view_distance())
		outside = outside or not _in_soft(cam.view_focus())
	var moved := cam.view_focus().distance_to(start)
	_press(MOUSE_BUTTON_RIGHT, top + Vector2(0, 80), false)
	_step(2.0)
	_check(not outside and worst <= 1.0, "a pan drag near the horizon stays on the island (biggest step %.3f distances)" % worst)
	_check(moved > 0.5, "...and still pans (%.1f m)" % moved)

	# --- a pointer warp in the middle of a drag (focus regained) does not throw the view
	await _new_cam()
	var c := _centre()
	_press(MOUSE_BUTTON_RIGHT, c, true)
	_motion(c + Vector2(10, 0))
	_step(DT)
	var f1 := cam.view_focus()
	_motion(c + Vector2(vs.x * 0.9, vs.y * 0.6))
	_step(DT)
	_check(cam.view_focus().distance_to(f1) < 0.5, "a pointer warp mid-drag is ignored (moved %.2f m)" % cam.view_focus().distance_to(f1))
	# the button came up outside the window: the next motion (no button held) ends the drag
	_step(0.3)   # held still: no fling
	_hover(c + Vector2(-300, 0))
	_step(DT)
	_check(not cam.is_dragging(), "a motion without the drag button ends a drag whose release was missed")
	var f2 := cam.view_focus()
	_motion(c + Vector2(-200, 0))
	_step(0.5)
	_check(cam.view_focus().distance_to(f2) < 0.05, "...and nothing pans after it (%.2f m)" % cam.view_focus().distance_to(f2))

	# --- zoom at the screen corners, at several pitches and headings
	await _new_cam()
	var corners := [Vector2(1, 1), Vector2(vs.x - 2, 1), Vector2(1, vs.y - 2), Vector2(vs.x - 2, vs.y - 2)]
	var corner_bad := 0
	var corner_jump := 0.0
	var tilt := [0.0, -3000.0, -150.0, 3000.0]
	for t in tilt.size():
		for k in 2:
			await _new_cam()
			cam._goal_yaw = 38.0 + 97.0 * k
			cam._cur_yaw = cam._goal_yaw
			_step(0.1)
			if tilt[t] != 0.0:
				_drag(MOUSE_BUTTON_MIDDLE, _centre(), Vector2(0, tilt[t]), 10)
			for corner: Vector2 in corners:
				for dir in [true, false, true]:
					for n in 25:
						var p0 := cam.global_position
						_wheel(corner, dir)
						cam._process(DT)
						corner_jump = maxf(corner_jump, cam.global_position.distance_to(p0) / cam.view_distance())
						if not _in_soft(cam.view_focus()) or not _zoom_ok():
							corner_bad += 1
					for n in 30:
						var p1 := cam.global_position
						cam._process(DT)
						corner_jump = maxf(corner_jump, cam.global_position.distance_to(p1) / cam.view_distance())
						if not _in_soft(cam.view_focus()) or not _zoom_ok():
							corner_bad += 1
	_check(corner_bad == 0, "zooming at the screen corners keeps the view on the island (%d bad frames)" % corner_bad)
	_check(corner_jump < 0.3, "...without a jump (biggest %.2f distances per frame)" % corner_jump)
	# a bottom corner at the normal pitch still zooms towards the cursor
	await _new_cam()
	var bc := Vector2(vs.x * 0.12, vs.y * 0.88)
	var bground: Vector3 = cam._ground_hit(bc)
	for i in 3:
		_wheel(bc, true)
		_step(0.05)
	_step(2.0)
	cam._apply(cam._free_pose(), Vector3.ZERO)
	_check(cam.unproject_position(bground).distance_to(bc) < 6.0, "...and still zooms towards a corner on the ground (drift %.1f px)" % cam.unproject_position(bground).distance_to(bc))

	# --- many thousands of random drags, zooms and turns at uneven frame times
	await _new_cam()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	var dts := [DT, DT, DT, DT, 1.0 / 144.0, 1.0 / 30.0, 0.0005, 0.1, 0.25]
	var bad_bounds := 0
	var bad_zoom := 0
	var bad_num := 0
	var max_idle_jump := 0.0
	var max_jump := 0.0
	var held := MOUSE_BUTTON_NONE
	var m := _centre()
	var steps := 12000
	for i in steps:
		var p0 := cam.global_position
		var acted := false
		var r := rng.randf()
		if held == MOUSE_BUTTON_NONE and r < 0.06:
			held = MOUSE_BUTTON_RIGHT if rng.randf() < 0.6 else MOUSE_BUTTON_MIDDLE
			m = _rand_point(rng, vs)
			_press(held, m, true, rng.randf() < 0.15)
			acted = true
		elif held != MOUSE_BUTTON_NONE and r < 0.04:
			_press(held, m, false)
			held = MOUSE_BUTTON_NONE
			acted = true
		elif held != MOUSE_BUTTON_NONE and r < 0.75:
			var step := Vector2(rng.randfn(0.0, 25.0), rng.randfn(0.0, 25.0))
			if rng.randf() < 0.01:
				# the pointer warps to the far corner (the window got the mouse back)
				step = Vector2(0.0 if m.x > vs.x * 0.5 else vs.x - 1.0, 0.0 if m.y > vs.y * 0.5 else vs.y - 1.0) - m
			elif rng.randf() < 0.02:
				step *= 8.0   # a fast flick, or a slow frame's motion arriving at once
			m = (m + step).clamp(Vector2(-200, -200), vs + Vector2(200, 200))
			_motion(m, held)
			acted = true
		if rng.randf() < 0.08:
			var at := _rand_point(rng, vs) if held == MOUSE_BUTTON_NONE else m
			for n in rng.randi_range(1, 4):
				_wheel(at, rng.randf() < 0.5)
			acted = true
		if rng.randf() < 0.004:
			_key(KEY_Q if rng.randf() < 0.5 else KEY_E)
			acted = true
		var dt: float = dts[rng.randi() % dts.size()]
		cam._process(dt)
		var jump := cam.global_position.distance_to(p0) / cam.view_distance()
		max_jump = maxf(max_jump, jump)
		if not acted:
			max_idle_jump = maxf(max_idle_jump, jump)
		if not _in_soft(cam.view_focus()) or not _in_soft(cam._goal_focus):
			bad_bounds += 1
		if not _zoom_ok():
			bad_zoom += 1
		if not cam.global_transform.origin.is_finite() or not cam.global_basis.x.is_finite() or cam.global_position.y < 0.3:
			bad_num += 1
	if held != MOUSE_BUTTON_NONE:
		_press(held, m, false)
	_step(1.0)
	_check(bad_bounds == 0, "%d random steps: the pivot never leaves the island's soft bounds (%d bad)" % [steps, bad_bounds])
	_check(bad_zoom == 0, "...the zoom stays within its range (%d bad)" % bad_zoom)
	_check(bad_num == 0, "...the camera stays valid and above the ground (%d bad)" % bad_num)
	# a frame without input moves at most what the fastest fling covers in the longest step
	var idle_limit := CampusCamera.MAX_DT * (deg_to_rad(CampusCamera.MAX_ORBIT_SPEED) + CampusCamera.MAX_PAN_SPEED) + 0.03
	_check(max_idle_jump < idle_limit, "...frames without input never jump, even after 0.25 s hitches (biggest %.3f distances, limit %.2f)" % [max_idle_jump, idle_limit])
	# a pan event moves the pivot one camera distance at most (a 300 px flick can do that)
	_check(max_jump < 1.25, "...and no input throws the view (biggest %.3f distances per frame)" % max_jump)
	_step(5.0)
	var fs := cam.view_focus()
	_check(cam.bounds.grow(0.5).has_point(Vector2(fs.x, fs.z)), "...and springs back inside the bounds when let go (%.1f, %.1f)" % [fs.x, fs.z])

	# --- a hitch right after a fling: no leap
	await _new_cam()
	_drag(MOUSE_BUTTON_RIGHT, _centre(), Vector2(400, 0), 6, true)
	var before := cam.view_focus()
	cam._process(0.25)
	_check(cam.view_focus().distance_to(before) < cam.view_distance() * 0.2,
		"a 0.25 s hitch after a fling moves the view only a frame's worth (%.1f m)" % cam.view_focus().distance_to(before))
	for i in 600:
		cam._process(DT)
	var b0 := cam.view_focus()
	await _new_cam()
	_drag(MOUSE_BUTTON_RIGHT, _centre(), Vector2(400, 0), 6, true)
	for i in 300:
		cam._process(DT * 2.0)
	_check(cam.view_focus().distance_to(b0) < 1.5, "a fling lands at the same place at 30 and 60 fps (%.2f m apart)" % cam.view_focus().distance_to(b0))

	# --- drag during follow: a pan takes over smoothly (no lag then catch-up), an orbit keeps
	# following; a wheel while following only changes the follow zoom
	await _new_cam()
	var walker := Node3D.new()
	world.add_child(walker)
	walker.global_position = Vector3(20, 0, 12)
	cam.follow(walker)
	_step(0.5)   # still gliding in
	var grab := _centre() + Vector2(-40, 30)
	var prev := cam.global_position
	var flick := 0.0
	_press(MOUSE_BUTTON_RIGHT, grab, true)
	for i in 30:
		_motion(grab + Vector2(6.0 * (i + 1), 0))
		cam._process(DT if i % 7 else 0.25)
		flick = maxf(flick, cam.global_position.distance_to(prev))
		prev = cam.global_position
	_press(MOUSE_BUTTON_RIGHT, grab + Vector2(180, 0), false)
	for i in 120:
		cam._process(DT)
		flick = maxf(flick, cam.global_position.distance_to(prev))
		prev = cam.global_position
	_check(cam.mode == CampusCamera.Mode.FREE, "a pan drag during follow lets go")
	_check(flick < 3.0, "...without a flick (biggest move %.2f m per frame)" % flick)
	_check(_in_soft(cam.view_focus()), "...and the view stays on the island")
	cam.follow(walker)
	_step(2.5)
	var fy: float = cam._fpose.yaw
	_press(MOUSE_BUTTON_MIDDLE, _centre(), true)
	for i in 10:
		_motion(_centre() + Vector2(-10.0 * (i + 1), 0), MOUSE_BUTTON_MIDDLE)
		_wheel(_centre(), false)
		cam._process(DT)
	_press(MOUSE_BUTTON_MIDDLE, _centre() + Vector2(-100, 0), false)
	_step(0.5)
	_check(cam.is_following() and cam._fpose.yaw > fy + 15.0 and cam._follow_zoom > 1.2,
		"an orbit drag with the wheel during follow keeps following, turns and zooms")
	world.queue_free()
	world = null
	await process_frame


func _in_soft(f: Vector3) -> bool:
	return cam.bounds.grow(cam.bounds_softness + 0.6).has_point(Vector2(f.x, f.z))


func _zoom_ok() -> bool:
	var d := cam.view_distance()
	return d >= cam.min_distance * exp(-0.31) and d <= cam.max_distance * exp(0.31)


## A random screen point: often a corner or an edge, sometimes over the horizon band at the top.
func _rand_point(rng: RandomNumberGenerator, vs: Vector2) -> Vector2:
	var r := rng.randf()
	if r < 0.2:
		return Vector2(rng.randi_range(0, 1) * (vs.x - 1), rng.randi_range(0, 1) * (vs.y - 1))
	if r < 0.35:
		return Vector2(rng.randf() * vs.x, rng.randf() * 8.0)
	return Vector2(rng.randf() * vs.x, rng.randf() * vs.y)


# ------------------------------------------------------------ campus
func _campus() -> void:
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(4)
	main.race_flow.autosave = false
	main.clock.set_speed(0)
	cam = main.camera
	cam.tour_enabled = false
	cam.apply_settings(MenuSettings.CAMERA_DEFAULTS)
	await _wait(0.5)

	# a HUD panel that stops the mouse also stops the wheel
	var panel := _stop_panel(main.hud)
	if panel:
		var g0: float = cam._goal_logd
		_hover(panel.get_global_rect().get_center())
		await _frames(1)
		_wheel(panel.get_global_rect().get_center(), true)
		await _frames(2)
		_check(is_equal_approx(cam._goal_logd, g0), "the wheel over a HUD panel (%s) does not zoom" % panel.name)
	else:
		_check(false, "found a HUD panel that stops the mouse")
	var g1: float = cam._goal_logd
	_hover(_centre())
	await _frames(1)
	_wheel(_centre(), true)
	await _frames(2)
	_check(cam._goal_logd < g1, "the wheel over the campus zooms")

	# a drag that starts over a HUD panel is not the camera's
	if panel:
		await _wait(1.5)
		var pc := panel.get_global_rect().get_center()
		var fp := cam.view_focus()
		var yp := cam.view_yaw()
		_hover(pc)
		await _frames(1)
		for b: MouseButton in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_press(b, pc, true)
			for i in 8:
				_motion(pc + Vector2(-25.0 * (i + 1), 15.0 * (i + 1)), b)
				await _frames(1)
			_press(b, pc + Vector2(-200, 120), false)
			await _frames(2)
		_check(not cam.is_dragging() and cam.view_focus().distance_to(fp) < 0.05 and absf(cam.view_yaw() - yp) < 0.05,
			"a drag that starts over a HUD panel moves nothing")

	# an open screen keeps the keys from the camera
	await _wait(1.5)   # the zoom settles first
	main.hud.open_screen("crew")
	await _frames(2)
	var f0 := cam.view_focus()
	var yaw0 := cam.view_yaw()
	await _hold(KEY_W, 0.4)
	_key(KEY_Q)
	await _wait(0.5)
	_check(cam.view_focus().distance_to(f0) < 0.05 and absf(cam.view_yaw() - yaw0) < 0.05, "an open screen keeps WASD / Q from the camera")
	main.hud.close_screen()
	await _frames(3)
	await _hold(KEY_W, 0.4)
	_check(cam.view_focus().distance_to(f0) > 1.0, "WASD pans again once the screen closes")

	# a double-click on empty ground glides there
	await _wait(1.0)
	var spot := _empty_ground(main)
	if spot.x >= 0.0:
		var target: Vector3 = cam._ground_hit(spot)
		_click(spot, false)
		_click(spot, true)
		await _wait(1.6)
		var aim: Vector3 = cam._ground_hit(_centre())
		var d := Vector2(aim.x, aim.z).distance_to(Vector2(target.x, target.z))
		_check(d < 1.0, "a double-click on the ground glides there (%.2f m off)" % d)
	else:
		_check(false, "found a spot of empty ground")
	main.queue_free()
	await _frames(3)


## The first visible HUD Control of some size that stops the mouse.
func _stop_panel(n: Node) -> Control:
	for c in n.get_children():
		var ctl := c as Control
		if ctl and ctl.is_visible_in_tree() and ctl.mouse_filter == Control.MOUSE_FILTER_STOP and ctl is PanelContainer \
				and ctl.size.x > 60.0 and ctl.size.y > 30.0:
			return ctl
		var deeper := _stop_panel(c)
		if deeper:
			return deeper
	return null


## A screen point over the ground with no Cometling, lot or HUD under it.
func _empty_ground(main: TycoonMain) -> Vector2:
	var vs := _view_size()
	for y in range(5, 9):
		for x in range(3, 9):
			var p := Vector2(vs.x * x / 12.0, vs.y * y / 12.0)
			if cam.pick(p, main.campus.cometlings()) == null and main.campus.lot_at(cam, p) == "" \
					and _gui_at(p) == null:
				return p
	return Vector2(-1, -1)


func _gui_at(p: Vector2) -> Control:
	var hit: Control = null
	var stack: Array[Node] = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var c := n as Control
		if c and c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_global_rect().has_point(p):
			hit = c
		stack.append_array(n.get_children())
	return hit


# ------------------------------------------------------------ input helpers
func _view_size() -> Vector2:
	return get_root().get_visible_rect().size


func _centre() -> Vector2:
	return _view_size() * 0.5


func _step(sec: float) -> void:
	var n := maxi(1, roundi(sec / DT))
	for i in n:
		cam._process(DT)


## A drag of `by` pixels in `steps` motion events, one frame each; `fling`: let go while moving.
func _drag(button: MouseButton, from: Vector2, by: Vector2, steps: int, fling := false, shift := false) -> void:
	_press(button, from, true, shift)
	for i in steps:
		_motion(from + by * float(i + 1) / steps, button)
		_step(DT)
	if not fling:
		_step(0.15)
	_press(button, from + by, false, shift)
	_step(DT)


func _press(button: MouseButton, at: Vector2, down: bool, shift := false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = at
	ev.global_position = at
	ev.pressed = down
	ev.shift_pressed = shift
	get_root().push_input(ev, true)


func _motion(at: Vector2, button := MOUSE_BUTTON_RIGHT) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.button_mask = 1 << (button - 1)
	get_root().push_input(ev, true)


func _hover(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	get_root().push_input(ev, true)


func _wheel(at: Vector2, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.position = at
	ev.global_position = at
	ev.pressed = true
	ev.factor = 1.0
	get_root().push_input(ev, true)


func _click(at: Vector2, double: bool) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = at
		ev.global_position = at
		ev.pressed = down
		ev.double_click = double and down
		get_root().push_input(ev, true)


func _key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		get_root().push_input(ev, true)


## Holds a key (polled through Input) for `sec`: stepped by hand on the bare camera, real
## frames on the campus.
func _hold(code: Key, sec: float, shift := false) -> void:
	if shift:
		_input_key(KEY_SHIFT, true)
	_input_key(code, true)
	if cam.is_processing():
		await _wait(sec)
	else:
		_step(sec)
	_input_key(code, false)
	if shift:
		_input_key(KEY_SHIFT, false)
	if not cam.is_processing():
		_step(0.6)   # the keyboard pan ramps down


func _input_key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
