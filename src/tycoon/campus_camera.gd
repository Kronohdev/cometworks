class_name CampusCamera
extends Camera3D
## Diorama camera over the campus, tuned to feel like a polished management game.
##
## Free view   wheel zooms towards the mouse cursor (the ground under the cursor stays put)
##             with eased inertia; the pitch, lens and look height follow the zoom (high and
##             top-down far away, low "tilt-shift" diorama close in). Right / middle drag grabs
##             the ground and keeps some momentum, Shift / Ctrl + drag turns the view, WASD /
##             arrows pan, Q / E turn by a step, optional screen-edge pan. Limits are soft
##             (rubber band), never hard stops.
## Follow      follow(cometling) glides in on an eased arc and frames the Cometling from a low,
##             close 3/4 angle with lead room in its walking direction, a soft lag and a little
##             handheld drift; when it stops to work the shot swings round to a clear angle and
##             sways slowly. Wheel / Q / E still work. Esc (release()), a right drag, WASD or a
##             click on empty ground (handled by TycoonMain) leave and the camera eases back.
## Framing     frame_area(centre, size) glides onto a building lot (the lot panel is on the
##             right, so the building sits a bit left of centre).
## Idle tour   after tour_idle_seconds without input the camera drifts between shots given by
##             tour_source (Cometlings at work, the pad, buildings) until any input.
## Cinematic   begin_cinematic(rig) hands the view to a Camera3D rig animated elsewhere (the
##             launch sequence, src/tycoon/launch/launch_sequence.gd): the camera eases from
##             where it is onto the rig, then copies its transform and lens every frame (cuts
##             in the rig's animation stay cuts), plus `cinematic_shake`. Player input does not
##             move it meanwhile. end_cinematic() eases back to the free view as it was.
## Input comes through _unhandled_input, so anything over a HUD panel (mouse_filter STOP)
## never moves the camera; drags are polled so they keep working when the cursor crosses a panel.

signal follow_changed(target: Node3D)   ## null when the camera lets go
signal tour_changed(active: bool)
signal cinematic_changed(active: bool)

enum Mode { FREE, FOLLOW, TOUR, CINEMATIC }

@export_group("Start view")
## ground point the free view orbits at the start
@export var focus := Vector3(4, 0, 2)
@export var yaw_deg := 38.0
@export var distance := 100.0

@export_group("Zoom")
@export var min_distance := 9.0
@export var max_distance := 230.0
## log-distance per wheel notch (0.15 = about 16 % closer)
@export_range(0.02, 0.6, 0.01) var zoom_step := 0.15
## first easing stage: how fast the wheel's goal is picked up (lower = more inertia)
@export_range(1.0, 40.0, 0.5) var zoom_inertia := 12.0
## second easing stage: how fast the view settles on the goal
@export_range(1.0, 40.0, 0.5) var zoom_sharpness := 8.0
## keep the ground point under the cursor while zooming
@export var zoom_to_cursor := true
## how much a notch past min / max distance still moves (0 = hard, 1 = no resistance)
@export_range(0.0, 1.0, 0.05) var zoom_overshoot := 0.3
## how fast an overshoot springs back (1/s)
@export_range(0.5, 20.0, 0.5) var soft_return := 5.0

@export_group("Zoom look")
## pitch (degrees above the horizon) at min_distance: low, diorama eye level
@export_range(3.0, 89.0, 0.5) var pitch_close_deg := 17.0
## pitch at max_distance: high, almost a map
@export_range(3.0, 89.0, 0.5) var pitch_far_deg := 52.0
## shape of the pitch change along the zoom (1 = linear in log distance)
@export_range(0.2, 4.0, 0.05) var pitch_curve := 1.25
@export_range(10.0, 90.0, 0.5) var fov_close := 40.0
@export_range(10.0, 90.0, 0.5) var fov_far := 29.0
## the view aims this high above the ground when fully zoomed in (frames Cometlings, not feet)
@export var look_height_close := 0.9
## drive the camera's CameraAttributesPractical depth of field for a tilt-shift look up close
@export var tilt_shift := true
## blur amount at min_distance (fades to none at tilt_shift_fade_distance)
@export_range(0.0, 0.3, 0.005) var tilt_shift_amount := 0.06
@export var tilt_shift_fade_distance := 70.0
## also blur what is much closer than the subject (can fringe on hard depth edges)
@export var tilt_shift_near := false

@export_group("Pan")
## soft pan limits (the plateau): x, z, width, depth
@export var bounds := Rect2(-70, -55, 150, 110)
## how far (m) a drag can pull past the bounds before it gets very stiff
@export var bounds_softness := 10.0
## easing of keyboard / momentum / framing moves (1/s)
@export_range(1.0, 40.0, 0.5) var pan_smoothing := 10.0
@export var drag_momentum := true
## how quickly a flung drag slows down (1/s)
@export_range(0.5, 20.0, 0.5) var momentum_friction := 3.5
## keyboard pan speed as a fraction of the camera distance per second
@export_range(0.1, 3.0, 0.05) var keyboard_pan_speed := 0.85
## how fast keyboard panning ramps up and down (1/s)
@export_range(1.0, 30.0, 0.5) var keyboard_accel := 7.0
@export var edge_pan := false
@export var edge_pan_margin := 14.0
@export_range(0.1, 3.0, 0.05) var edge_pan_speed := 0.7

@export_group("Rotate")
@export var rotate_step_deg := 45.0
@export_range(1.0, 30.0, 0.5) var rotate_sharpness := 6.0
## Shift / Ctrl + drag: degrees per pixel
@export var drag_rotate_speed := 0.3

@export_group("Follow")
@export var follow_distance := 10.0
@export_range(3.0, 60.0, 0.5) var follow_pitch_deg := 14.0
@export_range(10.0, 90.0, 0.5) var follow_fov := 36.0
## height on the Cometling the shot aims at (the scaled creature is about 1.2 m tall)
@export var follow_height := 0.8
## angle between the walking direction and the camera (0 = in front, 90 = side on)
@export_range(0.0, 180.0, 1.0) var follow_angle_deg := 60.0
## metres of lead room in the walking direction
@export var look_ahead := 1.8
## position lag (1/s, lower = softer)
@export_range(0.5, 20.0, 0.1) var follow_lag := 3.0
## heading lag (1/s)
@export_range(0.1, 10.0, 0.05) var follow_yaw_lag := 0.9
## framing changes when the Cometling stops: a bit closer and higher
@export var idle_distance_factor := 0.85
@export var idle_pitch_add_deg := 7.0
## slow sway around the working Cometling: amplitude (deg) and period (s)
@export var idle_orbit_deg := 28.0
@export var idle_orbit_period := 26.0
## glide in (ease in / out with a slight arc)
@export var glide_seconds := 1.7
## how much the glide pulls back and rises half way (0 = straight)
@export_range(0.0, 1.0, 0.01) var glide_arc := 0.3
@export var glide_arc_pitch_deg := 9.0
## glide back to the free view after letting go
@export var release_seconds := 1.4
## wheel range while following (multiplies follow_distance)
@export var follow_zoom_range := Vector2(0.6, 3.0)

@export_group("Handheld")
## gentle drift (degrees) in follow / tour shots
@export_range(0.0, 3.0, 0.01) var handheld_deg := 0.4
@export_range(0.02, 2.0, 0.01) var handheld_frequency := 0.2
## share of the drift in the free view (0 = rock steady)
@export_range(0.0, 1.0, 0.05) var handheld_free := 0.0

@export_group("Lot framing")
## camera distance per metre of the lot's longest side
@export var lot_frame_factor := 2.3
@export var lot_frame_min := 28.0
## where the building lands on screen, as a fraction of the screen (x < 0: left of centre)
@export var lot_frame_screen_offset := Vector2(-0.09, 0.06)
@export var lot_glide_seconds := 1.4

@export_group("Idle tour")
@export var tour_enabled := true
## seconds without input before the tour starts
@export var tour_idle_seconds := 25.0
@export var tour_shot_seconds := 11.0
@export var tour_glide_seconds := 3.5
## slow orbit (deg/s) and dolly-in (fraction over a shot) on place shots
@export var tour_orbit_deg_per_sec := 2.5
@export_range(0.0, 0.6, 0.01) var tour_dolly := 0.14
@export_range(3.0, 89.0, 0.5) var tour_pitch_deg := 27.0
@export var tour_distance_factor := 4.2

@export_group("Picking")
## minimum click radius around a Cometling's head (pixels)
@export var pick_radius_px := 24.0
## head height of a campus Cometling (m)
@export var cometling_head_height := 0.9

@export_group("Cinematic")
## seconds to ease from the current view onto the cinematic rig
@export var cinematic_blend_in := 1.3
## seconds to ease back to the free view after end_cinematic()
@export var cinematic_blend_out := 1.6
## strongest shake (degrees of jitter at cinematic_shake = 1)
@export_range(0.0, 5.0, 0.05) var cinematic_shake_deg := 1.1
## shake frequency (Hz)
@export var cinematic_shake_frequency := 17.0

## 0..1, set by whoever drives the cinematic (an engine roar shakes the view)
var cinematic_shake := 0.0
var _rig: Camera3D = null
var _cine_t := 1.0
var _cine_len := 1.0
var _cine_from := Transform3D()
var _cine_from_fov := 32.0

## areas the follow shots keep out of and see past (building footprints, x/z), set by the owner
var obstacles: Array[Rect2] = []
## returns the idle tour's shots: [{"node": Node3D}] to follow, or {"pos": Vector3, "radius": float}
var tour_source := Callable()

var mode := Mode.FREE

# free view state: goals and eased values
var _goal_focus := Vector3.ZERO
var _cur_focus := Vector3.ZERO
var _goal_yaw := 0.0
var _cur_yaw := 0.0
var _goal_logd := 0.0
var _mid_logd := 0.0
var _cur_logd := 0.0
var _pan_vel := Vector3.ZERO
var _key_vel := Vector2.ZERO
var _anchor_on := false
var _anchor_screen := Vector2.ZERO
var _anchor_world := Vector3.ZERO
var _drag_button := MOUSE_BUTTON_NONE
var _drag_rotate := false
var _drag_last := Vector2.ZERO
var _drag_moved := 0.0
var _drag_still := 0.0

# what is on screen
var _pose := Pose.new()
var _glide_from: Pose = null
var _glide_t := 1.0
var _glide_len := 1.0
var _glide_arc := 0.0
var _hand_w := 0.0
var _time := 0.0
var _idle := 0.0

# follow
var _target: Node3D = null
var _fpose := Pose.new()
var _tprev := Vector3.ZERO
var _tvel := Vector3.ZERO
var _moving := 0.0
var _heading := 0.0
var _side := 1.0
var _side_check := 0.0
var _idle_center := 0.0
var _idle_phase := 0.0
var _was_moving := false
var _follow_zoom := 1.0
var _user_yaw := 0.0

# tour
var _shot := {}
var _shot_t := 0.0
var _shot_yaw := 0.0
var _last_shot_key := ""
var _rng := RandomNumberGenerator.new()


## One camera placement: aims at `focus` from `dist` metres away, `yaw` / `pitch` in degrees.
class Pose:
	var focus := Vector3.ZERO
	var yaw := 0.0
	var dist := 10.0
	var pitch := 30.0
	var fov := 32.0

	func copy() -> Pose:
		var p := Pose.new()
		p.focus = focus
		p.yaw = yaw
		p.dist = dist
		p.pitch = pitch
		p.fov = fov
		return p


func _ready() -> void:
	_rng.randomize()
	_goal_focus = Vector3(focus.x, 0, focus.z)
	_cur_focus = _goal_focus
	_goal_yaw = yaw_deg
	_cur_yaw = yaw_deg
	_goal_logd = log(maxf(distance, 0.5))
	_mid_logd = _goal_logd
	_cur_logd = _goal_logd
	_pose = _free_pose()
	_apply(_pose, Vector3.ZERO)


# ------------------------------------------------------------ public API
## Eases the free view onto a ground point (keeps the zoom).
func look_at_point(p: Vector3) -> void:
	if mode != Mode.FREE:
		_leave_to_free(release_seconds)
	_goal_focus = Vector3(p.x, 0, p.z)
	_pan_vel = Vector3.ZERO


## Glides the free view to frame an area (a building lot): centre on the ground, size in x / z.
func frame_area(center: Vector3, size: Vector2) -> void:
	if mode != Mode.FREE:
		_set_mode(Mode.FREE)
	var d := maxf(lot_frame_min, maxf(size.x, size.y) * lot_frame_factor)
	var t := _zoom_t(d)
	var vfov := deg_to_rad(lerpf(fov_close, fov_far, t))
	var half_h := d * tan(vfov * 0.5)
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	var half_w := half_h * vp.x / maxf(vp.y, 1.0)
	var y := deg_to_rad(_goal_yaw)
	var right := Vector3(cos(y), 0, -sin(y))
	var fwd := Vector3(-sin(y), 0, -cos(y))
	# the building lands at the screen offset: move the aim point the other way
	var aim := Vector3(center.x, 0, center.z) - right * lot_frame_screen_offset.x * 2.0 * half_w \
		+ fwd * lot_frame_screen_offset.y * 2.0 * half_h
	_start_glide(lot_glide_seconds, 0.0)
	_goal_focus = aim
	_cur_focus = aim
	_goal_logd = log(d)
	_mid_logd = _goal_logd
	_cur_logd = _goal_logd
	_cur_yaw = _goal_yaw
	_pan_vel = Vector3.ZERO
	_anchor_on = false


## Starts following a Cometling (any Node3D that walks around).
func follow(target: Node3D) -> void:
	if target == null:
		release()
		return
	var same := mode == Mode.FOLLOW and _target == target
	_set_mode(Mode.FOLLOW)
	_begin_target(target)
	_start_glide(glide_seconds, glide_arc)
	if not same:
		follow_changed.emit(target)


## Lets go of the followed Cometling (or ends the tour) and eases back to the free view.
func release() -> void:
	if mode != Mode.FREE:
		_leave_to_free(release_seconds)


func is_following() -> bool:
	return mode == Mode.FOLLOW and _target != null


func followed() -> Node3D:
	return _target if mode == Mode.FOLLOW else null


func is_touring() -> bool:
	return mode == Mode.TOUR


## Hands the view to a Camera3D rig (not current itself) until end_cinematic(): eases onto it
## over `blend` seconds (-1 = cinematic_blend_in), then follows it exactly.
func begin_cinematic(rig: Camera3D, blend := -1.0) -> void:
	if rig == null:
		return
	var was := mode == Mode.CINEMATIC
	_set_mode(Mode.CINEMATIC)
	if not was:
		cinematic_changed.emit(true)
	_rig = rig
	_cine_from = global_transform
	_cine_from_fov = fov
	_cine_len = cinematic_blend_in if blend < 0.0 else blend
	_cine_t = 0.0 if _cine_len > 0.0 else 1.0
	_drag_button = MOUSE_BUTTON_NONE
	_pan_vel = Vector3.ZERO
	_anchor_on = false
	var attr := attributes as CameraAttributesPractical
	if attr:
		attr.dof_blur_far_enabled = false
		attr.dof_blur_near_enabled = false


## Leaves the cinematic: eases from the shot on screen back to the free view the player left.
func end_cinematic(blend := -1.0) -> void:
	if mode != Mode.CINEMATIC:
		return
	_set_mode(Mode.FREE)
	_start_glide(cinematic_blend_out if blend < 0.0 else blend, 0.0)


func is_cinematic() -> bool:
	return mode == Mode.CINEMATIC


## The Cometling under a screen point (nearest head within the click radius), or null.
func pick(screen: Vector2, candidates: Array) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var right := global_basis.x
	for c in candidates:
		var n := c as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var head := n.global_position + Vector3(0, cometling_head_height, 0)
		if is_position_behind(head):
			continue
		var sp := unproject_position(head)
		var r := maxf(pick_radius_px, sp.distance_to(unproject_position(head + right * 0.75)))
		# the body counts too: test against the segment from the feet to the head
		var feet := unproject_position(n.global_position)
		var d := _dist_to_segment(screen, feet, sp)
		if d < r and d < best_d:
			best_d = d
			best = n
	return best


## Seconds without input (the idle tour starts at tour_idle_seconds).
func idle_seconds() -> float:
	return _idle


## Starts the idle tour now (also used by tests).
func start_tour() -> void:
	if mode == Mode.TOUR or not tour_source.is_valid():
		return
	_set_mode(Mode.TOUR)
	tour_changed.emit(true)
	_next_shot()


# ------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	# any activity (also over the HUD) counts as "not idle" and ends the tour
	var active := event is InputEventKey or event is InputEventMouseButton \
		or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0)
	if not active:
		return
	_idle = 0.0
	if mode == Mode.TOUR:
		_leave_to_free(release_seconds)


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.CINEMATIC:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var f := mb.factor if mb.factor > 0.0 else 1.0
					_zoom(-zoom_step * f if mb.button_index == MOUSE_BUTTON_WHEEL_UP else zoom_step * f, mb.position)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed and _drag_button == MOUSE_BUTTON_NONE:
					_drag_button = mb.button_index
					_drag_rotate = mb.shift_pressed or mb.ctrl_pressed
					_drag_last = mb.position
					_drag_moved = 0.0
					_drag_still = 0.0
					_pan_vel = Vector3.ZERO
					_anchor_on = false
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom(-log(maxf(mg.factor, 0.01)), mg.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_Q:
				_rotate(-rotate_step_deg)
			KEY_E:
				_rotate(rotate_step_deg)


func _zoom(step_log: float, screen: Vector2) -> void:
	if mode == Mode.FOLLOW:
		_follow_zoom = clampf(_follow_zoom * exp(step_log), follow_zoom_range.x, follow_zoom_range.y)
		return
	if mode == Mode.TOUR:
		return
	# past the limits each notch moves less (rubber band); soft_return pulls it back
	var lo := log(min_distance)
	var hi := log(max_distance)
	var g := _goal_logd + step_log
	if (g < lo and step_log < 0.0) or (g > hi and step_log > 0.0):
		var over := (lo - g) if g < lo else (g - hi)
		step_log *= zoom_overshoot / (1.0 + over * 6.0)
	_goal_logd += step_log
	if zoom_to_cursor:
		_apply(_free_pose(), Vector3.ZERO)
		var hit: Variant = _ground_hit(screen)
		_anchor_on = hit != null
		if _anchor_on:
			_anchor_world = hit
			_anchor_screen = screen


func _rotate(deg: float) -> void:
	if mode == Mode.FOLLOW:
		_user_yaw += deg
		_idle_center += deg
		return
	_goal_yaw += deg


# ------------------------------------------------------------ frame
func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	_time += dt
	if mode == Mode.CINEMATIC:
		_update_cinematic(dt)
		return
	_update_drag(dt)
	_update_keys(dt)
	_update_free(dt)
	var hand_target := handheld_free
	match mode:
		Mode.FOLLOW:
			if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
				_leave_to_free(release_seconds)
			else:
				_update_follow(dt)
				hand_target = 1.0
		Mode.TOUR:
			_update_tour(dt)
			hand_target = 1.0
		Mode.FREE:
			if tour_enabled and tour_idle_seconds > 0.0 and _drag_button == MOUSE_BUTTON_NONE:
				_idle += dt
				if _idle >= tour_idle_seconds and _glide_t >= 1.0:
					start_tour()
	var desired := _desired_pose()
	if _glide_t < 1.0:
		_glide_t = minf(_glide_t + dt / maxf(_glide_len, 0.01), 1.0)
		_pose = _blend(_glide_from, desired, _glide_t, _glide_arc)
	else:
		_pose = desired
	_hand_w = lerpf(_hand_w, hand_target, 1.0 - exp(-dt * 1.5))
	_apply(_pose, _handheld() * _hand_w)
	_update_dof(_pose)


func _desired_pose() -> Pose:
	match mode:
		Mode.FOLLOW:
			return _fpose
		Mode.TOUR:
			return _fpose if _shot.has("node") else _tour_place_pose()
	return _free_pose()


## Right / middle drag, polled so it keeps going over HUD panels and ends wherever it is let go.
func _update_drag(dt: float) -> void:
	if _drag_button == MOUSE_BUTTON_NONE:
		return
	var vp := get_viewport()
	var m := vp.get_mouse_position()
	if not Input.is_mouse_button_pressed(_drag_button):
		_drag_button = MOUSE_BUTTON_NONE
		# a fling keeps going only if the mouse was still moving when let go
		if not drag_momentum or _drag_still > 0.06:
			_pan_vel = Vector3.ZERO
		return
	var rel := m - _drag_last
	_drag_last = m
	_drag_moved += rel.length()
	_drag_still = _drag_still + dt if rel.length() < 0.5 else 0.0
	if rel == Vector2.ZERO:
		return
	if mode != Mode.FREE:
		if _drag_moved < 4.0:
			return
		_take_over_from_follow()
	if _drag_rotate:
		_goal_yaw -= rel.x * drag_rotate_speed
		_cur_yaw = _goal_yaw
		return
	_apply(_free_pose(), Vector3.ZERO)
	var a: Variant = _ground_hit(m - rel)
	var b: Variant = _ground_hit(m)
	if a == null or b == null:
		return
	var shift: Vector3 = a - b
	shift.y = 0.0
	shift = _resist(shift)
	_goal_focus += shift
	_cur_focus = _goal_focus
	if dt > 0.0:
		_pan_vel = _pan_vel.lerp(shift / dt, 0.35)


func _update_keys(dt: float) -> void:
	var want := Vector2.ZERO
	if not _typing():
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			want.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			want.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			want.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			want.y += 1
	want = want.limit_length(1.0) * keyboard_pan_speed
	if edge_pan and want == Vector2.ZERO and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var vs := vp.get_visible_rect().size
		if Rect2(Vector2.ZERO, vs).has_point(m):
			if m.x < edge_pan_margin:
				want.x -= edge_pan_speed
			elif m.x > vs.x - edge_pan_margin:
				want.x += edge_pan_speed
			if m.y < edge_pan_margin:
				want.y -= edge_pan_speed
			elif m.y > vs.y - edge_pan_margin:
				want.y += edge_pan_speed
	if want != Vector2.ZERO and mode != Mode.FREE:
		_take_over_from_follow()
	_key_vel = _key_vel.lerp(want, 1.0 - exp(-dt * keyboard_accel))
	if _key_vel.length() > 0.001:
		var y := deg_to_rad(_cur_yaw)
		var right := Vector3(cos(y), 0, -sin(y))
		var fwd := Vector3(sin(y), 0, cos(y))
		_goal_focus += _resist((right * _key_vel.x + fwd * _key_vel.y) * exp(_cur_logd) * dt)
		_anchor_on = false


func _update_free(dt: float) -> void:
	# momentum, then the soft bounds pull the goal back in
	if _drag_button == MOUSE_BUTTON_NONE:
		if _pan_vel.length() > 0.01:
			_goal_focus += _resist(_pan_vel * dt)
			_pan_vel *= exp(-dt * momentum_friction)
		var inside := _clamp_focus(_goal_focus)
		_goal_focus = _goal_focus.lerp(inside, 1.0 - exp(-dt * soft_return))
		_cur_focus = _cur_focus.lerp(_goal_focus, 1.0 - exp(-dt * pan_smoothing))
	var lo := log(min_distance)
	var hi := log(max_distance)
	_goal_logd = lerpf(_goal_logd, clampf(_goal_logd, lo, hi), 1.0 - exp(-dt * soft_return))
	_mid_logd = lerpf(_mid_logd, _goal_logd, 1.0 - exp(-dt * zoom_inertia))
	_cur_logd = lerpf(_cur_logd, _mid_logd, 1.0 - exp(-dt * zoom_sharpness))
	if _drag_button == MOUSE_BUTTON_NONE or not _drag_rotate:
		_cur_yaw = lerpf(_cur_yaw, _goal_yaw, 1.0 - exp(-dt * rotate_sharpness))
	if _anchor_on:
		if absf(_cur_logd - _goal_logd) < 0.002:
			_anchor_on = false
		# keep the ground point that was under the cursor under the cursor
		_apply(_free_pose(), Vector3.ZERO)
		var hit: Variant = _ground_hit(_anchor_screen)
		if hit != null:
			var shift: Vector3 = _anchor_world - hit
			shift.y = 0.0
			_cur_focus += shift
			_goal_focus += shift


## The free view as a pose: pitch, lens and aim height follow the zoom.
func _free_pose() -> Pose:
	var p := Pose.new()
	var d := exp(_cur_logd)
	var t := _zoom_t(d)
	p.focus = _cur_focus + Vector3(0, lerpf(look_height_close, 0.0, smoothstep(0.0, 0.6, t)), 0)
	p.yaw = _cur_yaw
	p.dist = d
	p.pitch = lerpf(pitch_close_deg, pitch_far_deg, pow(t, pitch_curve))
	p.fov = lerpf(fov_close, fov_far, t)
	return p


## 0 at min_distance, 1 at max_distance (log scale).
func _zoom_t(d: float) -> float:
	return clampf((log(maxf(d, 0.01)) - log(min_distance)) / maxf(log(max_distance) - log(min_distance), 0.01), 0.0, 1.0)


# ------------------------------------------------------------ follow
func _begin_target(target: Node3D) -> void:
	_target = target
	_tprev = target.global_position
	_tvel = Vector3.ZERO
	_follow_zoom = 1.0
	_user_yaw = 0.0
	_idle_phase = 0.0
	_heading = target.global_rotation.y
	# start from the current heading, on the side nearest to where the camera looks from
	_side = 1.0 if absf(angle_difference(deg_to_rad(_pose.yaw), _heading + deg_to_rad(follow_angle_deg))) \
		< absf(angle_difference(deg_to_rad(_pose.yaw), _heading - deg_to_rad(follow_angle_deg))) else -1.0
	_idle_center = _pick_idle_yaw(target.global_position, rad_to_deg(target.global_rotation.y))
	# already walking? (the creature knows its stride speed) then start on the walking framing
	var cr := target.get_node_or_null("Creature")
	var spd: Variant = cr.get("_speed") if cr != null else null
	var walking := spd != null and float(spd) > 0.1
	_moving = 1.0 if walking else 0.0
	_was_moving = walking
	if walking:
		_tvel = Vector3(sin(_heading), 0, cos(_heading)) * 2.0
		_choose_side(target.global_position)
	_fpose = Pose.new()
	_fpose.focus = target.global_position + Vector3(0, follow_height, 0) + _tvel.normalized() * look_ahead * _moving
	_fpose.yaw = rad_to_deg(_heading) + _side * follow_angle_deg if walking else _idle_center
	_fpose.dist = follow_distance * (1.0 if walking else idle_distance_factor)
	_fpose.pitch = follow_pitch_deg + (0.0 if walking else idle_pitch_add_deg)
	_fpose.fov = follow_fov


func _update_follow(dt: float) -> void:
	var p := _target.global_position
	var v := (p - _tprev) / maxf(dt, 0.0001)
	_tprev = p
	v.y = 0.0
	if v.length() > 20.0:   # teleported
		v = Vector3.ZERO
	_tvel = _tvel.lerp(v, 1.0 - exp(-dt * 5.0))
	var speed := _tvel.length()
	_moving = lerpf(_moving, smoothstep(0.4, 1.6, speed), 1.0 - exp(-dt * 2.5))
	var moving_now := speed > 0.6
	if moving_now:
		_heading = atan2(_tvel.x, _tvel.z)
	_side_check -= dt
	if moving_now and _side_check <= 0.0:
		_side_check = 0.5
		_choose_side(p)
	if _was_moving and not moving_now and speed < 0.2:
		# it stopped to work: swing round to a clear angle that shows its face
		_idle_center = _pick_idle_yaw(p, rad_to_deg(_target.global_rotation.y))
		_idle_phase = 0.0
	if speed < 0.2:
		_was_moving = false
	elif moving_now:
		_was_moving = true
	_idle_phase += dt
	var move_yaw := rad_to_deg(_heading) + _side * follow_angle_deg + _user_yaw
	var idle_yaw := _idle_center + idle_orbit_deg * sin(TAU * _idle_phase / maxf(idle_orbit_period, 1.0))
	var want_yaw := rad_to_deg(lerp_angle(deg_to_rad(idle_yaw), deg_to_rad(move_yaw), _moving))
	_fpose.yaw = rad_to_deg(lerp_angle(deg_to_rad(_fpose.yaw), deg_to_rad(want_yaw), 1.0 - exp(-dt * follow_yaw_lag)))
	var lead := _tvel.normalized() * look_ahead * _moving if speed > 0.05 else Vector3.ZERO
	var aim := p + Vector3(0, follow_height, 0) + lead
	_fpose.focus = _fpose.focus.lerp(aim, 1.0 - exp(-dt * follow_lag))
	var want_d := follow_distance * _follow_zoom * lerpf(idle_distance_factor, 1.0, _moving)
	_fpose.dist = lerpf(_fpose.dist, want_d, 1.0 - exp(-dt * 2.0))
	var want_p := follow_pitch_deg + idle_pitch_add_deg * (1.0 - _moving) + _blocked_pitch(_fpose)
	_fpose.pitch = lerpf(_fpose.pitch, want_p, 1.0 - exp(-dt * 1.5))
	_fpose.fov = lerpf(_fpose.fov, follow_fov, 1.0 - exp(-dt * 2.0))


## Walking: keep the camera on the side it is on unless a building is in the way.
func _choose_side(p: Vector3) -> void:
	var d := follow_distance * _follow_zoom
	var mine := rad_to_deg(_heading) + _side * follow_angle_deg + _user_yaw
	if _view_clear(p, mine, d):
		return
	var other := rad_to_deg(_heading) - _side * follow_angle_deg + _user_yaw
	if _view_clear(p, other, d):
		_side = -_side


## A yaw for a Cometling at work: in front of it (3/4), else any clear angle near the current one.
func _pick_idle_yaw(p: Vector3, facing_deg: float) -> float:
	var d := follow_distance * _follow_zoom * idle_distance_factor
	var cur := _pose.yaw
	var tries := [35.0, -35.0, 70.0, -70.0, 0.0, 110.0, -110.0, 150.0, -150.0, 180.0]
	tries.sort_custom(func(a: float, b: float) -> bool:
		# prefer showing the face, then staying close to the current angle
		return absf(a) * 0.6 + absf(angle_difference(deg_to_rad(cur), deg_to_rad(facing_deg + a))) * 20.0 \
			< absf(b) * 0.6 + absf(angle_difference(deg_to_rad(cur), deg_to_rad(facing_deg + b))) * 20.0)
	for a: float in tries:
		if _view_clear(p, facing_deg + a, d):
			return _nearest_equivalent(facing_deg + a, cur)
	return cur


## True when the ground line from the Cometling to the camera crosses no obstacle.
func _view_clear(p: Vector3, yaw: float, d: float) -> bool:
	var y := deg_to_rad(yaw)
	var dir := Vector2(sin(y), cos(y))
	var from := Vector2(p.x, p.z)
	for i in range(1, 7):
		var q := from + dir * (d * (0.25 + 0.75 * i / 6.0)) * cos(deg_to_rad(follow_pitch_deg))
		for r in obstacles:
			if r.grow(0.6).has_point(q):
				return false
	return true


## Extra pitch when the camera would sit inside or behind a building anyway.
func _blocked_pitch(p: Pose) -> float:
	if _target == null:
		return 0.0
	return 0.0 if _view_clear(_target.global_position, p.yaw, p.dist) else 16.0


func _take_over_from_follow() -> void:
	# continue in the free view from where the shot is now
	_start_glide(0.6, 0.0)
	_cur_focus = Vector3(_pose.focus.x, 0, _pose.focus.z)
	_goal_focus = _cur_focus
	_cur_logd = log(maxf(_pose.dist, min_distance))
	_mid_logd = _cur_logd
	_goal_logd = _cur_logd
	_cur_yaw = _pose.yaw
	_goal_yaw = _pose.yaw
	_set_mode(Mode.FREE)


func _leave_to_free(seconds: float) -> void:
	if mode == Mode.FREE:
		return
	_set_mode(Mode.FREE)
	_start_glide(seconds, glide_arc * 0.5)


## Switches mode and tells the HUD (follow_changed / tour_changed) what ended.
func _set_mode(m: Mode) -> void:
	var old := mode
	mode = m
	if old == Mode.CINEMATIC and m != Mode.CINEMATIC:
		# whatever ends the cinematic glides on from the shot on screen
		_pose = _pose_from_transform(global_transform, fov)
		_rig = null
		cinematic_shake = 0.0
		cinematic_changed.emit(false)
	if m == Mode.FREE:
		_target = null
	if m != Mode.TOUR:
		_shot = {}
	_idle = 0.0
	if old == Mode.FOLLOW and m != Mode.FOLLOW:
		follow_changed.emit(null)
	if old == Mode.TOUR and m != Mode.TOUR:
		tour_changed.emit(false)


# ------------------------------------------------------------ cinematic
func _update_cinematic(dt: float) -> void:
	if _rig == null or not is_instance_valid(_rig):
		end_cinematic()
		return
	var to := _rig.global_transform.orthonormalized()
	var to_fov := _rig.fov
	if _cine_t < 1.0:
		_cine_t = minf(_cine_t + dt / maxf(_cine_len, 0.01), 1.0)
		var k := _ease(_cine_t)
		to = _cine_from.interpolate_with(to, k)
		to_fov = lerpf(_cine_from_fov, to_fov, k)
	if cinematic_shake > 0.001 and cinematic_shake_deg > 0.0:
		var t := _time * cinematic_shake_frequency
		var a := deg_to_rad(cinematic_shake_deg) * cinematic_shake
		to.basis = to.basis * Basis.from_euler(Vector3(
			(sin(t * 1.0) * 0.6 + sin(t * 2.31 + 0.7) * 0.4) * a,
			(sin(t * 0.87 + 2.1) * 0.6 + sin(t * 1.93 + 1.3) * 0.4) * a,
			sin(t * 0.71 + 4.2) * a * 0.4))
	global_transform = to
	fov = to_fov
	near = clampf(_rig.near, 0.05, 2.0)
	far = maxf(_rig.far, 1600.0)
	# keep a pose for when the cinematic ends
	_hand_w = 0.0


## The orbit pose (focus, yaw, pitch, distance) that reproduces a camera transform, aiming at
## the ground when the camera looks down at it, else at a point ahead.
func _pose_from_transform(t: Transform3D, lens: float) -> Pose:
	var p := Pose.new()
	var fwd := -t.basis.z.normalized()
	var d := 40.0
	if fwd.y < -0.08:
		d = clampf(-t.origin.y / fwd.y, 4.0, 400.0)
	p.focus = t.origin + fwd * d
	var off := -fwd
	p.dist = d
	p.pitch = rad_to_deg(asin(clampf(off.y, -0.99, 0.99)))
	p.yaw = rad_to_deg(atan2(off.x, off.z))
	p.fov = lens
	return p


# ------------------------------------------------------------ tour
func _update_tour(dt: float) -> void:
	_shot_t += dt
	if _shot.has("node"):
		var n := _shot["node"] as Node3D
		if n == null or not is_instance_valid(n) or not n.is_visible_in_tree():
			_next_shot()
			return
		_update_follow(dt)
	if _shot_t >= tour_shot_seconds:
		_next_shot()


func _next_shot() -> void:
	var shots: Array = tour_source.call() if tour_source.is_valid() else []
	if shots.is_empty():
		_leave_to_free(release_seconds)
		return
	# a different kind of shot each time when possible
	var pick: Dictionary = shots[_rng.randi() % shots.size()]
	for i in 6:
		var key := "node" if pick.has("node") else str(pick.get("pos", ""))
		if key != _last_shot_key:
			break
		pick = shots[_rng.randi() % shots.size()]
	_last_shot_key = "node" if pick.has("node") else str(pick.get("pos", ""))
	_shot = pick
	_shot_t = 0.0
	_shot_yaw = _pose.yaw + _rng.randf_range(-50.0, 50.0)
	if pick.has("node"):
		_begin_target(pick["node"] as Node3D)
	_start_glide(tour_glide_seconds, glide_arc)


func _tour_place_pose() -> Pose:
	var p := Pose.new()
	var r := float(_shot.get("radius", 10.0))
	var k := clampf(_shot_t / maxf(tour_shot_seconds, 1.0), 0.0, 1.0)
	p.focus = (_shot.get("pos", Vector3.ZERO) as Vector3) + Vector3(0, r * 0.18, 0)
	p.yaw = _shot_yaw + tour_orbit_deg_per_sec * _shot_t
	p.dist = r * tour_distance_factor * (1.0 - tour_dolly * k)
	p.pitch = tour_pitch_deg
	p.fov = lerpf(fov_close, fov_far, 0.35)
	return p


# ------------------------------------------------------------ glide
func _start_glide(seconds: float, arc: float) -> void:
	_glide_from = _pose.copy()
	_glide_t = 0.0 if seconds > 0.0 else 1.0
	_glide_len = seconds
	_glide_arc = arc


## Ease in / out between two poses: aim first when closing in, pull back first when leaving,
## distance in log space, and a slight rise (arc) half way.
func _blend(a: Pose, b: Pose, t: float, arc: float) -> Pose:
	var closing := b.dist < a.dist
	var tf := _ease(clampf(t * 1.35, 0.0, 1.0)) if closing else _ease(clampf((t - 0.2) / 0.8, 0.0, 1.0))
	var td := _ease(clampf((t - 0.15) / 0.85, 0.0, 1.0)) if closing else _ease(clampf(t * 1.3, 0.0, 1.0))
	var te := _ease(t)
	var p := Pose.new()
	p.focus = a.focus.lerp(b.focus, tf)
	p.yaw = rad_to_deg(lerp_angle(deg_to_rad(a.yaw), deg_to_rad(b.yaw), te))
	var ratio := absf(log(maxf(b.dist, 0.01) / maxf(a.dist, 0.01)))
	var bump := sin(PI * t) * arc / (1.0 + ratio)
	p.dist = exp(lerpf(log(maxf(a.dist, 0.01)), log(maxf(b.dist, 0.01)), td)) * (1.0 + bump)
	var arc_k := clampf(arc / glide_arc, 0.0, 1.0) if glide_arc > 0.0 else 0.0
	p.pitch = lerpf(a.pitch, b.pitch, te) + glide_arc_pitch_deg * sin(PI * t) * arc_k
	p.fov = lerpf(a.fov, b.fov, te)
	return p


static func _ease(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


# ------------------------------------------------------------ helpers
func _apply(p: Pose, hand: Vector3) -> void:
	var y := deg_to_rad(p.yaw)
	var pt := deg_to_rad(p.pitch)
	var pos := p.focus + Vector3(sin(y) * cos(pt), sin(pt), cos(y) * cos(pt)) * p.dist
	pos.y = maxf(pos.y, 0.4)
	var b := Basis.looking_at(p.focus - pos, Vector3.UP)
	if hand != Vector3.ZERO:
		b = b * Basis.from_euler(hand)
	global_transform = Transform3D(b, pos)
	fov = p.fov
	near = clampf(p.dist * 0.012, 0.05, 2.0)
	far = 1600.0


## Gentle handheld drift: layered slow sines (radians).
func _handheld() -> Vector3:
	if handheld_deg <= 0.0:
		return Vector3.ZERO
	var t := _time * handheld_frequency * TAU
	var a := deg_to_rad(handheld_deg)
	return Vector3(
		(sin(t * 1.0 + 0.3) * 0.6 + sin(t * 2.37 + 1.1) * 0.4) * a,
		(sin(t * 0.83 + 2.0) * 0.6 + sin(t * 1.91 + 0.4) * 0.4) * a,
		(sin(t * 0.61 + 4.0) * 0.5 + sin(t * 1.53 + 2.2) * 0.3) * a * 0.5)


## Depth of field from the shot distance: blur in front and behind, fading out when far.
func _update_dof(p: Pose) -> void:
	var attr := attributes as CameraAttributesPractical
	if attr == null or not tilt_shift:
		return
	var w := 1.0 - smoothstep(min_distance, tilt_shift_fade_distance, p.dist)
	var on := w > 0.02 and tilt_shift_amount > 0.0
	attr.dof_blur_far_enabled = on
	attr.dof_blur_near_enabled = on and tilt_shift_near
	if not on:
		return
	attr.dof_blur_amount = tilt_shift_amount * w
	attr.dof_blur_far_distance = p.dist * 1.25
	attr.dof_blur_far_transition = p.dist * 1.6
	attr.dof_blur_near_distance = p.dist * 0.55
	attr.dof_blur_near_transition = p.dist * 0.35


## Ground (y = 0) point under a screen position with the camera as it is now, or null.
func _ground_hit(screen: Vector2) -> Variant:
	var from := project_ray_origin(screen)
	var dir := project_ray_normal(screen)
	if dir.y > -1e-3:
		return null
	return from + dir * (-from.y / dir.y)


func _clamp_focus(f: Vector3) -> Vector3:
	return Vector3(clampf(f.x, bounds.position.x, bounds.end.x), f.y, clampf(f.z, bounds.position.y, bounds.end.y))


## A pan step, damped when it goes further past the soft bounds.
func _resist(step: Vector3) -> Vector3:
	var f := _goal_focus
	var c := _clamp_focus(f)
	var over := Vector3(f.x - c.x, 0, f.z - c.z)
	var out := step
	if over.x * step.x > 0.0:
		out.x *= 1.0 / pow(1.0 + absf(over.x) / maxf(bounds_softness, 0.1), 2.0)
	if over.z * step.z > 0.0:
		out.z *= 1.0 / pow(1.0 + absf(over.z) / maxf(bounds_softness, 0.1), 2.0)
	return out


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


static func _nearest_equivalent(deg: float, ref: float) -> float:
	return ref + rad_to_deg(angle_difference(deg_to_rad(ref), deg_to_rad(deg)))


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
