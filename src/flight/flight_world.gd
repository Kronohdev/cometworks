class_name FlightWorld
extends Node3D
## Flight test scene controller (scenes/flight/flight.tscn): builds the rocket from
## FlightSession, runs the fixed-step simulation with time warp, keeps the floating origin
## on the active vessel, drives the camera, sky, smoke, map view and HUD, and writes the
## flight-test report.
##
## Frames: the simulation runs in an inertial frame centred on the body whose sphere of
## influence holds the vessel (`soi`: Earth at launch, the Moon, the Sun...; patched
## conics, FlightSolar) with the PCI axes (+Y = up at the launch pad). The render frame is
## that frame translated by `origin` (= the active vessel, interpolated), so the rocket is
## always rendered near (0, 0, 0) and the launch site / planet / smoke / debris are placed
## at (position - origin). The sky always gets the camera relative to the Earth.
##
## Maneuver planning: `plan` (FlightManeuvers) holds the nodes; `traj` (FlightTrajectory)
## is the cached patched-conic prediction, recomputed only when its inputs change (node
## edits, thrust, SOI change, staging, horizon reached), never every frame. On-rails warp
## follows the predicted conics exactly, crossing SOI boundaries at their computed times.

signal flight_ended(report: Dictionary)

const DT := 0.02
const MAX_STEPS_PER_FRAME := 400
## wall-clock budget of the physics steps per frame (ms): high physics warp slows down
## instead of dropping the frame rate
const STEP_BUDGET_MS := 10.0
## Time warp levels the player picks from ( , / . / the HUD arrows). A level runs on rails
## (exact conics, any speed) whenever the vessel coasts above the air; otherwise the
## physics runs at the same level capped to PHYS_MAX (same fixed step, only more steps
## per frame), and switches to rails by itself once coasting in space again.
const WARPS := [1, 2, 4, 10, 50, 100, 1000, 10000, 100000, 1000000]
const PHYS_MAX := 100
const RAILS_MIN := 10
## rails warp stops this long before a node's burn start (s, mission time)
const NODE_LEAD := 20.0
## Launch-site scene origin in the PCI frame: pad A of the site (local -125, -745) sits
## exactly on the +Y axis. Must match src/flight/gen/make_flight_textures.py.
const SITE_ORIGIN := [125.0, 6371000.0, 745.0]
const PAD_TOP := 12.7
## Render direction of the sea at the pad (launch direction, "east")
const EAST := Vector3(0.894, 0, -0.447)
const SITE_HIDE_ALT := 32000.0
const GROUND_PLANE_ALT := 1500.0
const CAMERA_MARGIN := 3.0
const ORBIT_PE := 140000.0
const DEFAULT_VESSEL := "res://scenes/examples/garca.tscn"
const GRAPHICS_QUALITY := "res://src/core/graphics_quality.gd"
const EXPLOSION := preload("res://scenes/flight/explosion.tscn")
const CHUNK := preload("res://scenes/flight/debris_chunk.tscn")
const MAX_CHUNKS := 380
const DEBRIS_RANGE := 40000.0

@export var auto_start_autopilot := false
## prints per-frame timings of the main loop (debug)
@export var profile := false
var _prof := [0, 0, 0, 0, 0]

var active: FlightVessel
var debris: Array[FlightVessel] = []
var origin := PackedFloat64Array([0.0, 6371000.0, 0.0])
var time := 0.0
var launched := false
var liftoff_time := -1.0
## time warp the player picked (one of WARPS); the effective rate is current_warp()
var warp := 1
var on_rails := false
var _acc := 0.0
var _alpha := 1.0
var paused := false
var ended := false
var map_view := false
var autopilot: FlightAutopilot = null
## extra physics warp for scripted runs (screenshots); players use WARPS
var debug_warp := 1.0
## steering input injected by test scripts (pitch, roll, yaw); zero = keyboard
var scripted_input := Vector3.ZERO
var predicted_dv := 0.0
var vessel_name := ""
# patched conics / maneuvers
var sys: FlightSolar
## index (FlightSolar) of the body whose SOI holds the active vessel
var soi := 0
var plan := FlightManeuvers.new()
var traj: FlightTrajectory = null
## body the map has targeted (closest approach, AN / DN), -1 = none
var target_body := -1
var executor: FlightNodeExecutor = null
var _traj_dirty := true
var _traj_timer := 0.0
var _traj_version := -1
## warp-to target (mission time), < 0 = none
var _warp_to := -1.0
## lower prediction quality while a node is being dragged
var plan_dragging := false
var _east := EAST.normalized()
## planet rotation axis (texture north pole) in the render frame, for navball headings
var _pole := Vector3(0, 0, -1)
var _pad_up := Vector3.UP
var _smoke_dist := 0.0
var _ground_cloud_t := 0.0
var _hud_timer := 0.0
var _dv_cache: Array = []
var _dv_time := 0
var _crash_time := -1.0
var _orbit_announced := false
var _chunks: Array[Node3D] = []
## launch-site materials whose patterns are computed in site coordinates
var _site_materials: Array[ShaderMaterial] = []
var _ground_plane: Node3D
## SSAO as set by GraphicsQuality (turned off while the launch site is out of view)
var _ssao_quality := false
# report
var stats := {}
var events: Array = []
var samples_t := PackedFloat32Array()
var samples_alt := PackedFloat32Array()
var samples_v := PackedFloat32Array()
var _sample_timer := 0.0
var _q_peak := 0.0
var _maxq_announced := false
var _space_announced := false

@onready var sky: FlightSky = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var site: Node3D = $LaunchSite
@onready var vessels: Node3D = $Vessels
@onready var smoke: FlightSmoke = $Smoke
@onready var cam: FlightCamera = $CameraRig
@onready var map: FlightMap = $HUD/MapView
@onready var hud: FlightHUD = $HUD
@onready var effects: Node3D = $Effects


func _ready() -> void:
	# shared quality presets (src/core/graphics_quality.gd on the kaua branch), if present
	if ResourceLoader.exists(GRAPHICS_QUALITY):
		var gq: Script = load(GRAPHICS_QUALITY)
		if gq and gq.has_method("apply"):
			gq.call("apply", self)
	_ssao_quality = $WorldEnvironment.environment.ssao_enabled
	var lang := OS.get_locale_language()
	if not TranslationServer.get_locale().begins_with("pt") and not TranslationServer.get_locale().begins_with("en"):
		TranslationServer.set_locale("pt" if lang == "pt" else "en")
	var ps: PackedScene = FlightSession.vessel_scene
	vessel_name = FlightSession.vessel_name
	if ps == null:
		ps = load(DEFAULT_VESSEL)
		vessel_name = ExampleVessels.display_name("garca")
		FlightSession.set_vessel(ps, vessel_name, 0.0)
	# the texture's lon-increasing direction is our "east", so its -Y pole is "north"
	_pole = (sky.planet_to_tex().transposed() * Vector3.DOWN).normalized()
	predicted_dv = FlightSession.predicted_dv
	if predicted_dv <= 0.0:
		var hv := Vessel.new()
		add_child(hv)
		hv.load_scene(ps)
		predicted_dv = hv.analyze()["ascent_dv"]
		hv.free()
	active = FlightVessel.new()
	active.name = "Active"
	vessels.add_child(active)
	active.setup_from_scene(ps)
	active.place_on_pad(PAD_TOP, _pad_up, -_east)
	active.flight_event.connect(_on_vessel_event)
	cam.reference = _east.cross(_pad_up).normalized() * -1.0
	# start south-east of the pad, sea and tower in view, sun behind the camera
	cam.set_view(2.6, 0.04, clampf(active.length * 1.35, 25.0, 160.0), true)
	_ground_plane = site.get_node_or_null("Ground/GroundPlane")
	for path in ["Ground/GroundPlane", "Ground/ApronFront", "LaunchComplexA/PadDeck"]:
		var mi := site.get_node_or_null(path) as MeshInstance3D
		if mi and mi.get_surface_override_material(0) is ShaderMaterial:
			var m := mi.get_surface_override_material(0) as ShaderMaterial
			if not _site_materials.has(m):
				_site_materials.append(m)
	_reset_stats()
	sys = FlightSolar.get_system()
	soi = sys.earth
	plan.changed.connect(func() -> void: _traj_dirty = true)
	hud.setup(self)
	map.setup(self, sky.planet_to_tex())
	hud.action.connect(_on_hud_action)
	if auto_start_autopilot or FlightSession.auto_ascent:
		set_autopilot(true)
	_place_world()


func _reset_stats() -> void:
	stats = {"max_alt": 0.0, "max_speed": 0.0, "max_q": 0.0, "max_q_t": 0.0, "max_q_alt": 0.0, "max_g": 0.0,
		"result": "", "reason": ""}
	events.clear()


# ------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if ended and not (event is InputEventKey):
		return
	if not map_view and cam.handle_input(event):
		return
	if map_view and not paused and map.handle_input(event):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			toggle_pause()
		KEY_F2:
			hud.toggle_hud()
		KEY_F1:
			hud.toggle_help()
	if paused or ended:
		return
	match k.keycode:
		KEY_SPACE:
			stage()
		KEY_T:
			active.set_sas(FlightVessel.Sas.OFF if active.sas != FlightVessel.Sas.OFF else FlightVessel.Sas.HOLD)
			set_autopilot(false)
		KEY_G:
			active.set_sas(FlightVessel.Sas.PROGRADE)
			set_autopilot(false)
		KEY_H:
			active.set_sas(FlightVessel.Sas.RETROGRADE)
			set_autopilot(false)
		KEY_P:
			set_autopilot(autopilot == null)
		KEY_M:
			set_map(not map_view)
		KEY_Z:
			active.throttle = 1.0
		KEY_X:
			active.throttle = 0.0
		KEY_PERIOD:
			_warp_to = -1.0
			change_warp(1)
		KEY_COMMA:
			_warp_to = -1.0
			change_warp(-1)
		KEY_B:
			warp_to_next_node()
		KEY_Y:
			set_executor(executor == null)
		KEY_ENTER, KEY_KP_ENTER:
			if _orbit_announced:
				end_flight("orbit")


func _read_flight_keys(delta: float) -> void:
	if paused or ended or active.crashed:
		active.input = Vector3.ZERO
		return
	if scripted_input != Vector3.ZERO:
		active.input = scripted_input
		return
	var u := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		u.x -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		u.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		u.z += 1.0
	if Input.is_physical_key_pressed(KEY_D):
		u.z -= 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		u.y -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		u.y += 1.0
	if u != Vector3.ZERO and autopilot:
		set_autopilot(false)
	active.input = u
	if autopilot == null:
		if Input.is_physical_key_pressed(KEY_SHIFT):
			active.throttle = minf(active.throttle + delta * 0.7, 1.0)
		if Input.is_physical_key_pressed(KEY_CTRL):
			active.throttle = maxf(active.throttle - delta * 0.7, 0.0)


# ------------------------------------------------------------ actions
func stage() -> void:
	if active.crashed or ended:
		return
	var was_pad := active.current_stage < 0
	var pieces := active.activate_next_stage()
	for p in pieces:
		_add_debris(p)
	if was_pad:
		launched = true
		_log("EV_IGNITION_PAD", {})


func set_autopilot(on: bool) -> void:
	if on and autopilot == null:
		autopilot = FlightAutopilot.new(_pad_up, _east, 200000.0)
		hud.toast(tr("FL_AUTO_ON"), MarginPalette.ACCENT_2)
	elif not on and autopilot != null:
		autopilot = null
		active.set_sas(FlightVessel.Sas.HOLD)
		hud.toast(tr("FL_AUTO_OFF"), MarginPalette.TEXT_DIM)


## Starts / stops the "execute next node" autopilot (points along the remaining Δv,
## burns half before and half after the node, cuts at zero).
func set_executor(on: bool) -> void:
	if on and executor == null:
		var n := plan.first()
		if n == null or not launched:
			return
		set_autopilot(false)
		executor = FlightNodeExecutor.new(n)
		hud.toast(tr("FL_EXEC_ON"), MarginPalette.DATA_1)
		warp_to_next_node()
	elif not on and executor != null:
		executor = null
		active.throttle = 0.0
		active.set_sas(FlightVessel.Sas.HOLD)
		hud.toast(tr("FL_EXEC_OFF"), MarginPalette.TEXT_DIM)


## Warps (rails when allowed, physics otherwise) to NODE_LEAD seconds before the next
## node's burn start.
func warp_to_next_node() -> void:
	var n := plan.first()
	if n == null:
		return
	var t := n.time - node_burn_time(n) * 0.5 - NODE_LEAD
	if t <= time + 1.0:
		return
	warp_to(t)


func warp_to(t: float) -> void:
	_warp_to = t
	hud.toast(tr("FL_WARPING_TO") % FlightHUD.fmt_time(t - time), MarginPalette.ACCENT)


## Orbit insertion planner on the current state and plan (see FlightCapture).
func capture_planner() -> FlightCapture:
	var b := active.body
	var keep: Array[FlightManeuverNode] = []
	for n in plan.nodes:
		if not n.auto_capture or n.locked:
			keep.append(n)
	var last: FlightManeuverNode = keep[-1] if not keep.is_empty() else null
	return FlightCapture.new(sys, soi, b.pos(), b.vel(), time, keep, node_burn_time(last) if last else 0.0)


## Plans an orbit insertion (altitudes in m, inclination in degrees or NAN = keep the
## arrival plane) and adds its nodes to the plan. Returns FlightCapture.plan()'s result.
func plan_capture(pe_alt: float, ap_alt: float, inc_deg: float) -> Dictionary:
	if not launched or active.landed:
		return {"ok": false, "msg": "FL_CAPT_NO_ENCOUNTER"}
	var res := capture_planner().plan(pe_alt, ap_alt, inc_deg)
	if res["ok"]:
		# a new insertion replaces the previous one (nodes not yet burning)
		for n in plan.nodes.duplicate():
			if n.auto_capture and not n.locked:
				if executor != null and executor.node == n:
					set_executor(false)
				plan.remove(n)
		var first: FlightManeuverNode = null
		for nd: Dictionary in res["nodes"]:
			var n := plan.add(float(nd["t"]), nd["dv"])
			n.auto_capture = true
			if first == null:
				first = n
		res["first"] = first
		_traj_dirty = true
	return res


## Estimated burn time of a node with the engines that would burn now.
func node_burn_time(n: FlightManeuverNode) -> float:
	var bt := active.burn_time(n.remaining_world().length() if n.locked else n.dv_total())
	return bt if bt < INF else 0.0


func set_map(on: bool) -> void:
	map_view = on
	map.set_active(on)
	cam.camera.current = not on
	hud.set_map_mode(on)


func toggle_pause() -> void:
	if ended:
		return
	paused = not paused
	hud.show_pause(paused)


func change_warp(d: int) -> void:
	var idx := WARPS.find(warp)
	if idx < 0:
		idx = 0
	idx = clampi(idx + d, 0, WARPS.size() - 1)
	_set_warp_value(int(WARPS[idx]))
	if d > 0 and warp > current_warp():
		hud.toast(_warp_limit_text(), MarginPalette.WARNING)


## Effective time warp (what the simulation runs at now).
func current_warp() -> int:
	return warp if on_rails else mini(warp, PHYS_MAX)


func _phys_warp() -> float:
	return float(mini(warp, PHYS_MAX)) * debug_warp


func _set_warp_value(w: int) -> void:
	warp = w
	_apply_warp_mode()


## Rails when the picked warp asks for it and the vessel may coast on rails, else physics.
func _apply_warp_mode() -> void:
	var want := warp >= RAILS_MIN and _rails_allowed()
	if want and not on_rails:
		_enter_rails()
	elif not want and on_rails:
		_exit_rails()


## Lowest altitude for on-rails warp around the current body: the top of the air, or a
## safety margin above an airless surface.
func _rails_floor() -> float:
	return sys.atmo_top[soi] if sys.atmo_top[soi] > 0.0 else maxf(5000.0, sys.radius[soi] * 0.005)


func _rails_allowed() -> bool:
	return _rails_block() == ""


## Why on-rails warp is not possible now ("" = it is): a translation key.
func _rails_block() -> String:
	if not launched or active.landed or active.crashed:
		return "FL_WARP_WHY_GROUND"
	if active.body.altitude() <= _rails_floor():
		return "FL_WARP_WHY_AIR"
	if active.thrust_n > 0.0 or _engines_lit():
		return "FL_WARP_WHY_THRUST"
	if autopilot != null and not autopilot.done and active.burn_engines()["thrust"] > 0.0:
		return "FL_WARP_WHY_AUTO"
	# the node executor is about to burn (or burning): rails would skip the burn
	var n := plan.first()
	if executor != null and n != null and time > n.time - node_burn_time(n) * 0.5 - NODE_LEAD - 0.5:
		return "FL_WARP_WHY_BURN"
	return ""


## Throttle up with an engine of the active stage that still has propellant.
func _engines_lit() -> bool:
	return active.throttle > 0.0 and active.current_stage >= 0 and active.burn_engines()["stage"] == active.current_stage


func _warp_limit_text() -> String:
	var why := _rails_block()
	var t := tr("FL_WARP_LIMIT") % PHYS_MAX
	if why == "FL_WARP_WHY_AIR":
		return t + " · " + tr(why) % FlightHUD.fmt_dist(_rails_floor())
	return t + " · " + tr(why) if why != "" else t


func _enter_rails() -> void:
	on_rails = true
	active.body.w = Vector3.ZERO
	_predict(1.0)
	for d in debris:
		d.queue_free()
	debris.clear()
	smoke.clear()


func _exit_rails() -> void:
	on_rails = false
	active.prev.copy_from(active.body)


func revert_to_launch() -> void:
	get_tree().reload_current_scene()


func revert_to_hangar() -> void:
	FlightSession.return_to_hangar = true
	get_tree().change_scene_to_file(FlightSession.HANGAR_SCENE)


func _on_hud_action(what: String) -> void:
	match what:
		"resume":
			if paused:
				toggle_pause()
		"revert_launch":
			revert_to_launch()
		"revert_hangar":
			revert_to_hangar()
		"end":
			if paused:
				toggle_pause()
			end_flight("abort" if not _orbit_announced else "orbit")
		"continue":
			hud.hide_report()
			ended = false
		"stage":
			stage()
		"sas":
			active.set_sas(FlightVessel.Sas.OFF if active.sas != FlightVessel.Sas.OFF else FlightVessel.Sas.HOLD)
			set_autopilot(false)
		"prograde":
			active.set_sas(FlightVessel.Sas.PROGRADE)
			set_autopilot(false)
		"retrograde":
			active.set_sas(FlightVessel.Sas.RETROGRADE)
			set_autopilot(false)
		"auto":
			set_autopilot(autopilot == null)
		"map":
			set_map(not map_view)
		"warp_up":
			change_warp(1)
		"warp_down":
			change_warp(-1)


# ------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	var t0 := Time.get_ticks_usec()
	_read_flight_keys(delta)
	if not paused and not ended:
		_update_warp_to(delta)
		_simulate(delta)
		_update_nodes()
		_update_trajectory(delta)
	var t1 := Time.get_ticks_usec()
	_place_world()
	var t2 := Time.get_ticks_usec()
	_update_effects(delta)
	var t3 := Time.get_ticks_usec()
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.1
		hud.update_telemetry(_telemetry())
	if profile:
		_prof[0] += t1 - t0
		_prof[1] += t2 - t1
		_prof[2] += t3 - t2
		_prof[3] += Time.get_ticks_usec() - t3
		_prof[4] += 1
		if _prof[4] >= 60:
			print("profile ms/frame: sim %.2f  place %.2f  effects %.2f  hud %.2f" % [
				_prof[0] / 60000.0, _prof[1] / 60000.0, _prof[2] / 60000.0, _prof[3] / 60000.0])
			_prof = [0, 0, 0, 0, 0]


func _simulate(delta: float) -> void:
	if on_rails:
		if not _rails_allowed():
			# something changed under rails warp (throttle up, air below): stop
			_set_warp_value(1)
		else:
			_simulate_rails(delta * float(warp))
			return
	elif warp >= RAILS_MIN and _rails_allowed():
		# high warp picked while the physics had to run (air, thrust): coasting in space
		# again, switch to rails
		_enter_rails()
		_simulate_rails(delta * float(warp))
		return
	var w := _phys_warp()
	_acc += delta * w
	var steps := 0
	var t_end := Time.get_ticks_usec() + int(STEP_BUDGET_MS * 1000.0)
	var over := false
	while _acc >= DT and steps < MAX_STEPS_PER_FRAME:
		_acc -= DT
		steps += 1
		_step(DT)
		if ended:
			break
		if steps % 8 == 0 and Time.get_ticks_usec() > t_end:
			over = true
			break
	if steps >= MAX_STEPS_PER_FRAME or over:
		_acc = minf(_acc, DT)
	_alpha = clampf(_acc / DT, 0.0, 1.0)


func _step(dt: float) -> void:
	time += dt
	if autopilot:
		if autopilot.update(active, dt):
			stage()
	if executor:
		match executor.update(active, time, dt, soi):
			FlightNodeExecutor.STAGE:
				stage()
			FlightNodeExecutor.DONE:
				_finish_node(true)
			FlightNodeExecutor.ABORT:
				executor = null
				active.throttle = 0.0
				active.set_sas(FlightVessel.Sas.HOLD)
				hud.toast(tr("FL_EXEC_NO_FUEL"), MarginPalette.WARNING)
	var dropped := active.physics_step(dt)
	_accumulate_burn(dt)
	_check_soi()
	for p in dropped:
		_add_debris(p)
	for d in debris.duplicate():
		d.physics_step(dt)
		if d.body.altitude() < 0.0 or d.landed or d.age > 400.0:
			_remove_debris(d, d.landed or d.body.altitude() < 0.0)
	_track_stats(dt)
	if active.crashed and _crash_time < 0.0:
		_on_crash()


func _add_debris(d: FlightVessel) -> void:
	if d.get_parent() != vessels:
		d.reparent(vessels)
	debris.append(d)
	# decoupling puff at the separation point
	var sep := active.local_to_pci(d.com)
	var b := Basis(active.body.q)
	var vacuum := active.pressure < 0.01
	for i in 10:
		var dir := (b * Vector3(randf() - 0.5, (randf() - 0.5) * 0.3, randf() - 0.5)).normalized()
		var v := active.body.velocity_v3() + dir * randf_range(4.0, 12.0)
		smoke.emit(sep, v, randf_range(1.2, 2.2), 1.0, randf_range(4.0, 7.0), 0.55, 0.05, 0.0 if vacuum else 0.8)


func _remove_debris(d: FlightVessel, impact: bool) -> void:
	debris.erase(d)
	if impact:
		var p := d.render_pci(1.0)
		var dist := Vector3(p[0] - origin[0], p[1] - origin[1], p[2] - origin[2]).length()
		if dist < 6000.0:
			_spawn_explosion(Vector3(p[0] - origin[0], p[1] - origin[1], p[2] - origin[2]), 0.6)
	d.queue_free()


# ------------------------------------------------------------ stats / events
func _track_stats(dt: float) -> void:
	var b := active.body
	var alt := b.altitude()
	stats["max_alt"] = maxf(stats["max_alt"], alt)
	stats["max_speed"] = maxf(stats["max_speed"], b.speed())
	if active.q_dyn > stats["max_q"]:
		stats["max_q"] = active.q_dyn
		stats["max_q_t"] = mission_time()
		stats["max_q_alt"] = alt
	if launched and mission_time() > 1.0:
		stats["max_g"] = maxf(stats["max_g"], active.g_load)
	if launched and liftoff_time < 0.0 and not active.clamped and alt - (PAD_TOP + 0.0) > 2.0 + active.length * 0.0 \
			and b.vertical_speed() > 0.5:
		liftoff_time = time
		_log("EV_LIFTOFF", {})
	# max-Q: the dynamic pressure has peaked
	_q_peak = maxf(_q_peak, active.q_dyn)
	if not _maxq_announced and _q_peak > 4000.0 and active.q_dyn < _q_peak * 0.97:
		_maxq_announced = true
		_log("EV_MAXQ", {"q": _q_peak})
	if not _space_announced and alt > 100000.0:
		_space_announced = true
		_log("EV_SPACE", {})
	if not _orbit_announced and soi == sys.earth and alt > FlightOrbit.ATMO_TOP and active.thrust_n <= 0.0:
		var el := FlightOrbit.elements(b.pos(), b.vel())
		if float(el["pe_alt"]) > ORBIT_PE:
			_orbit_announced = true
			_log("EV_ORBIT", {"ap": el["ap_alt"], "pe": el["pe_alt"]})
			get_tree().create_timer(5.0).timeout.connect(func() -> void:
				if not ended and _orbit_announced:
					end_flight("orbit"))
	_sample_timer -= dt if dt > 0.0 else 0.5
	if launched and _sample_timer <= 0.0:
		_sample_timer = 1.0
		samples_t.append(mission_time())
		samples_alt.append(alt)
		samples_v.append(b.speed())


func mission_time() -> float:
	return time - liftoff_time if liftoff_time >= 0.0 else 0.0


func _on_vessel_event(key: String, data: Dictionary) -> void:
	_log(key, data)


func _log(key: String, data: Dictionary) -> void:
	var t := mission_time() if liftoff_time >= 0.0 else 0.0
	# symmetric boosters separate in the same step: one entry is enough
	if not events.is_empty() and events[-1]["key"] == key and absf(float(events[-1]["t"]) - t) < 0.5:
		return
	events.append({"t": t, "key": key, "data": data, "alt": active.body.altitude()})
	hud.event(key, data)


func _on_crash() -> void:
	_crash_time = time
	stats["reason"] = active.crash_reason
	_breakup(active)
	get_tree().create_timer(3.5).timeout.connect(func() -> void: end_flight("crash"))


func end_flight(result: String) -> void:
	if ended:
		return
	ended = true
	_set_warp_value(1)
	var el := _elements()
	stats["result"] = result
	var report := stats.duplicate()
	report["vessel"] = vessel_name
	report["time"] = mission_time()
	report["ap"] = el["ap_alt"]
	report["pe"] = el["pe_alt"]
	report["orbit"] = float(el["pe_alt"]) > ORBIT_PE and not active.crashed
	report["dv_used"] = active.dv_used
	report["dv_predicted"] = predicted_dv
	report["events"] = events.duplicate()
	report["samples_t"] = samples_t
	report["samples_alt"] = samples_alt
	report["samples_v"] = samples_v
	hud.show_report(report)
	flight_ended.emit(report)


# ------------------------------------------------------------ crash / breakup
func _breakup(v: FlightVessel) -> void:
	var center := v.global_transform * v.com
	_spawn_explosion(center, 1.0)
	var up := v.body.up()
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, -up)
	var vel := v.body.velocity_v3() * 0.12
	var parts := v.parts.duplicate()
	parts.reverse()
	var per_part := maxi(1, (MAX_CHUNKS - parts.size()) / maxi(parts.size(), 1))
	for p: PartInstance in parts:
		if _chunks.size() >= MAX_CHUNKS:
			break
		var gx := p.global_transform
		for c in p.get_children():
			if c is FlightPlume:
				c.visible = false
		var chunk: RigidBody3D = CHUNK.instantiate()
		effects.add_child(chunk)
		chunk.global_transform = Transform3D(gx.basis, gx * p.aabb.get_center())
		(chunk.get_node("Mesh") as Node3D).visible = false
		var shape := (chunk.get_node("Shape") as CollisionShape3D)
		var box := BoxShape3D.new()
		box.size = p.aabb.size.max(Vector3.ONE * 0.3)
		shape.shape = box
		p.get_parent().remove_child(p)
		chunk.add_child(p)
		p.transform = Transform3D(Basis(), -p.aabb.get_center())
		chunk.mass = maxf(p.dry_mass(), 10.0)
		var out := (gx * p.aabb.get_center() - center).normalized()
		chunk.linear_velocity = vel + out * randf_range(6.0, 18.0) + up * randf_range(2.0, 10.0)
		chunk.angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 4.0
		_chunks.append(chunk)
		# voxel fragments
		for i in per_part:
			if _chunks.size() >= MAX_CHUNKS:
				break
			var f: RigidBody3D = CHUNK.instantiate()
			effects.add_child(f)
			var s := randf_range(0.25, 0.7) * clampf(p.radius(), 0.4, 2.0)
			f.global_position = gx * (p.aabb.get_center() + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * p.aabb.size)
			(f.get_node("Mesh") as Node3D).scale = Vector3.ONE * s
			var bs := BoxShape3D.new()
			bs.size = Vector3.ONE * s
			(f.get_node("Shape") as CollisionShape3D).shape = bs
			f.mass = 5.0 * s
			var dir := (f.global_position - center).normalized()
			f.linear_velocity = vel + dir * randf_range(10.0, 35.0) + up * randf_range(0.0, 15.0)
			f.angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 10.0
			var mi := f.get_node("Mesh") as MeshInstance3D
			mi.set_instance_shader_parameter("tint", [MarginPalette.STRUCTURE, MarginPalette.METAL, MarginPalette.GUNMETAL,
				MarginPalette.ACCENT, Color(0.15, 0.13, 0.12)][randi() % 5])
			_chunks.append(f)
	v.visible = false


func _spawn_explosion(pos: Vector3, scale_k: float) -> void:
	var ex: Node3D = EXPLOSION.instantiate()
	effects.add_child(ex)
	ex.global_position = pos
	ex.scale = Vector3.ONE * scale_k
	if cam.camera.global_position.distance_to(pos) < 400.0:
		cam.shake = 2.0 * scale_k


# ------------------------------------------------------------ rendering
func _place_world() -> void:
	if not (active.crashed and _crash_time >= 0.0):
		origin = active.render_pci(_alpha)
	var ox: float = origin[0]
	var oy: float = origin[1]
	var oz: float = origin[2]
	if not active.crashed:
		active.update_render(_alpha, ox, oy, oz)
	for d in debris:
		d.update_render(_alpha, ox, oy, oz)
		var dp := d.render_pci(_alpha)
		var dist := Vector3(dp[0] - ox, dp[1] - oy, dp[2] - oz).length()
		if dist > DEBRIS_RANGE:
			debris.erase(d)
			d.queue_free()
			break
	var sx: float = SITE_ORIGIN[0] - ox
	var sy: float = SITE_ORIGIN[1] - oy
	var sz: float = SITE_ORIGIN[2] - oz
	site.position = Vector3(sx, sy, sz)
	var alt := active.body.altitude()
	var site_on := alt < SITE_HIDE_ALT and soi == sys.earth
	if site_on != site.visible:
		site.visible = site_on
		# ambient occlusion only matters around the launch site (~2 ms on an iGPU)
		sky.environment.ssao_enabled = site_on and _ssao_quality
	if site.visible:
		for m in _site_materials:
			m.set_shader_parameter("site_origin", site.position)
	# above a few km the sky shader draws the site's coast itself (no plane edge in view)
	if _ground_plane:
		var cam_alt := alt + cam.camera.global_position.dot(active.body.up())
		_ground_plane.visible = cam_alt < GROUND_PLANE_ALT
	var up := active.body.up()
	var cam_render := cam.camera.global_position
	var cam_pci := PackedFloat64Array([ox + cam_render.x, oy + cam_render.y, oz + cam_render.z])
	if soi != sys.earth:
		# the sky always works relative to the Earth
		var eo := sys.pos_rel(soi, sys.earth, time)
		cam_pci = PackedFloat64Array([cam_pci[0] + eo[0], cam_pci[1] + eo[1], cam_pci[2] + eo[2]])
	_update_sky_bodies(cam_pci)
	sky.update_camera(cam_pci, PackedFloat64Array(SITE_ORIGIN), map_view)
	var focus := Vector3.ZERO if not active.crashed else _crash_focus()
	cam.min_height = _ground_floor(focus) - _alt_of_render(focus)
	cam.update_camera(get_process_delta_time(), focus, up)
	cam.shake = maxf(cam.shake - get_process_delta_time() * 1.5, 0.0)
	if launched and not active.crashed and active.thrust_n > 0.0 and alt < 3000.0:
		cam.shake = maxf(cam.shake, 0.12 * (1.0 - alt / 3000.0))
	if map_view:
		map.update_map()


## Altitude (m) of a render-space point (doubles via the floating origin).
func _alt_of_render(p: Vector3) -> float:
	var x: float = origin[0] + p.x
	var y: float = origin[1] + p.y
	var z: float = origin[2] + p.z
	return sqrt(x * x + y * y + z * z) - sys.radius[soi]


## Lowest allowed camera altitude near a render-space point: the launcher top around the
## pad, sea level (= the planet surface) elsewhere, plus a margin.
func _ground_floor(p: Vector3) -> float:
	var x: float = origin[0] + p.x
	var y: float = origin[1] + p.y
	var z: float = origin[2] + p.z
	var r := sqrt(x * x + y * y + z * z)
	var horiz := Vector3(x / r, y / r, z / r).distance_to(_pad_up) * FlightOrbit.R
	var ground := PAD_TOP if horiz < 450.0 and soi == sys.earth else 0.0
	return ground + CAMERA_MARGIN


## Camera height above the ground floor (tests: must stay positive).
func camera_clearance() -> float:
	return _alt_of_render(cam.camera.global_position) - (_ground_floor(cam.camera.global_position) - CAMERA_MARGIN)


func _crash_focus() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for ch in _chunks:
		if is_instance_valid(ch):
			c += ch.global_position
			n += 1
			if n > 20:
				break
	return c / maxf(n, 1)


func _update_effects(delta: float) -> void:
	var ox: float = origin[0]
	var oy: float = origin[1]
	var oz: float = origin[2]
	if on_rails:
		return
	var w := _phys_warp()
	if not paused:
		_emit_smoke(delta * w)
	smoke.update(0.0 if paused else delta * w, ox, oy, oz, active.body.up())


func _emit_smoke(dt: float) -> void:
	if active.crashed or active.thrust_n <= 0.0:
		return
	var alt := active.body.altitude()
	var air := active.pressure
	if air < 0.004:
		return
	var b := Basis(active.body.q)
	var vel := active.body.velocity_v3()
	var speed := vel.length()
	# trail: puffs spaced along the path, bigger in thin air and at speed
	_smoke_dist += speed * dt + 6.0 * dt
	var emitted := false
	for e in active.engines:
		if float(e["thrust"]) <= 0.0:
			continue
		var p: PartInstance = e["part"]
		var r := p.radius()
		var solid: bool = e["solid"]
		var spacing := maxf(r * 1.4, speed * 0.045)
		var size0 := maxf(r * (3.2 if solid else 2.4), spacing * 1.7) * (1.0 + (1.0 - air) * 1.5)
		var n := mini(int(_smoke_dist / spacing), 5)
		if n <= 0:
			continue
		emitted = true
		var nozzle := active.local_to_pci(e["pos"])
		var down := -(b * (e["dir"] as Vector3))
		var vdir := vel / maxf(speed, 1.0)
		for i in n:
			var back := float(i) / float(n) * speed * dt + r * 2.0
			var pos := PackedFloat64Array([nozzle[0] - vdir.x * back + down.x * r * 2.5,
				nozzle[1] - vdir.y * back + down.y * r * 2.5, nozzle[2] - vdir.z * back + down.z * r * 2.5])
			var jitter := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * r * 3.0
			var v := vel * 0.1 + down * randf_range(15.0, 40.0) + jitter
			var life := lerpf(6.0, 16.0, air) * (1.3 if solid else 1.0)
			var alpha := clampf(air * 3.0, 0.15, 0.9) * (0.95 if solid else 0.6)
			smoke.emit(pos, v, life, size0, size0 * lerpf(4.0, 7.0, air), alpha, 0.55 if solid else 0.12, 1.2)
	if emitted:
		_smoke_dist = 0.0
	# ground cloud while the rocket is low over the pad
	var h_pad := alt - PAD_TOP
	if h_pad < 120.0 and launched:
		_ground_cloud_t += dt * 26.0 * (1.0 - h_pad / 120.0)
		var padp := PackedFloat64Array([0.0, FlightOrbit.R + PAD_TOP - 2.0, 0.0])
		while _ground_cloud_t > 1.0:
			_ground_cloud_t -= 1.0
			var a := randf() * TAU
			var horiz := (Vector3(cos(a), 0, sin(a)) + _east.cross(Vector3.UP) * 0.6).normalized()
			var v := horiz * randf_range(14.0, 34.0) + Vector3.UP * randf_range(1.0, 6.0)
			smoke.emit(padp, v, randf_range(8.0, 13.0), randf_range(8.0, 12.0), randf_range(34.0, 55.0), 0.85, 0.05, 0.3)


# ------------------------------------------------------------ telemetry for the HUD
func _elements() -> Dictionary:
	return FlightOrbit.elements(active.body.pos(), active.body.vel(), sys.mu[soi], sys.radius[soi])


func _telemetry() -> Dictionary:
	var b := active.body
	var el := _elements()
	var now := Time.get_ticks_msec()
	if _dv_cache.is_empty() or now - _dv_time > 1000:
		_dv_time = now
		_dv_cache = active.remaining_dv()
	var dv_stage := 0.0
	var dv_total := 0.0
	for i in _dv_cache.size():
		var r: Dictionary = _dv_cache[i]
		if i == 0:
			dv_stage = r["dv"]
		dv_total += float(r["dv"])
	var nose := active.nose_world()
	var up := b.up()
	var east_now := _pole.cross(up).normalized()
	var node := plan.first()
	var node_info := {}
	if node != null and node.valid:
		var rem := node.remaining_world()
		var bt := node_burn_time(node)
		node_info = {"dv": rem.length() if node.locked else node.dv_total(), "dir": rem.normalized(),
			"t_node": node.time - time, "burn": bt, "t_burn": node.time - bt * 0.5 - time, "exec": executor != null}
	return {"alt": b.altitude(), "vs": b.vertical_speed(), "hs": b.horizontal_speed(), "speed": b.speed(),
		"soi": soi, "soi_name": sys.display_name(soi), "node": node_info,
		"ap": el["ap_alt"], "pe": el["pe_alt"], "e": el["e"], "t_ap": FlightOrbit.time_to_apoapsis(b.pos(), b.vel(), sys.mu[soi]),
		"g": active.g_load, "q": active.q_dyn, "max_q": stats["max_q"], "maxq_passed": _maxq_announced,
		"throttle": active.throttle, "thrust": active.thrust_n, "mass": active.mass,
		"dv_stage": dv_stage, "dv_total": dv_total, "dv_rows": _dv_cache,
		"met": mission_time(), "launched": launched, "warp": current_warp(), "warp_set": warp, "rails": on_rails,
		"sas": active.sas, "auto": autopilot != null, "q_body": active.body.q, "up": up, "east": east_now,
		"vel": b.velocity_v3(), "nose": nose, "stage": active.current_stage, "stages": active.stage_count,
		"vessel": active, "mach": active.mach, "aoa": active.aoa, "orbit": _orbit_announced}


# ------------------------------------------------------------ patched conics
## Re-centres the simulation on another body (SOI change): the vessel state is offset by
## the old body's state relative to the new one; debris and smoke (old frame) go away.
func _switch_soi(new_body: int) -> void:
	if new_body == soi:
		return
	var off := sys.state_rel(soi, new_body, time)
	var air := sys.atmo_top[new_body] > 0.0
	var home := new_body == sys.earth
	active.body.rebase(off, sys.mu[new_body], sys.radius[new_body], air, home)
	active.prev.rebase(off, sys.mu[new_body], sys.radius[new_body], air, home)
	var entering := sys.parent[new_body] == soi
	soi = new_body
	for d in debris:
		d.queue_free()
	debris.clear()
	smoke.clear()
	_traj_dirty = true
	_log("EV_SOI", {"body": sys.display_name(new_body), "enter": entering})


## Physics steps: did the vessel cross an SOI boundary?
func _check_soi() -> void:
	var b := active.body
	var r2 := b.px * b.px + b.py * b.py + b.pz * b.pz
	if sys.parent[soi] >= 0 and r2 > sys.soi[soi] * sys.soi[soi]:
		_switch_soi(sys.parent[soi])
		return
	for k in sys.children[soi]:
		var q := sys.pos_rel_parent(k, time)
		var dx := b.px - q[0]
		var dy := b.py - q[1]
		var dz := b.pz - q[2]
		if dx * dx + dy * dy + dz * dz < sys.soi[k] * sys.soi[k]:
			_switch_soi(k)
			return


## On-rails warp: follow the predicted conics exactly; SOI changes happen at their computed
## times, the warp stops before the air / the surface, a node or the warp-to target.
func _simulate_rails(dt_game: float) -> void:
	var t_target := time + dt_game
	var stop := INF
	if _warp_to > 0.0:
		stop = minf(stop, _warp_to)
	var n := plan.first()
	if n != null:
		var t_lead := n.time - node_burn_time(n) * 0.5 - NODE_LEAD
		if t_lead > time + 0.5:
			stop = minf(stop, t_lead)
	for guard in 8:
		if traj == null or traj.current_segment_at(time) < 0:
			_predict(1.0)
		var si := traj.current_segment_at(time) if traj else -1
		if si < 0:
			_set_warp_value(1)
			return
		var seg: FlightTrajectory.Segment = traj.segments[si]
		var c := seg.conic
		# never warp into the air or the ground
		var floor_r := sys.radius[soi] + _rails_floor()
		if c.rp < floor_r:
			var t_floor := c.time_to_radius(floor_r, time, false)
			if t_floor < INF:
				stop = minf(stop, t_floor)
		var t_end := minf(t_target, stop)
		if (seg.end == FlightTrajectory.End.ESCAPE or seg.end == FlightTrajectory.End.ENCOUNTER) and t_end >= seg.t1:
			active.body.set_from_array(c.state_at(seg.t1))
			time = seg.t1
			_switch_soi(seg.next_body)
			_predict(1.0)
			continue
		if t_end > seg.t1 and seg.end == FlightTrajectory.End.HORIZON:
			# past the prediction horizon (one revolution): same conic, refresh the plan later
			_traj_dirty = true
		time = t_end
		active.body.set_from_array(c.state_at(time))
		break
	active.prev.copy_from(active.body)
	_alpha = 1.0
	_track_stats(0.0)
	if t_target >= stop:
		_set_warp_value(1)
		if _warp_to > 0.0 and time >= _warp_to - 0.01:
			_warp_to = -1.0


## Warp-to: picks the warp level that reaches the target smoothly (rails if allowed).
func _update_warp_to(delta: float) -> void:
	if _warp_to < 0.0:
		return
	var left := _warp_to - time
	if left <= 0.05:
		_warp_to = -1.0
		_set_warp_value(1)
		return
	var cap: int = WARPS[-1] if _rails_allowed() else PHYS_MAX
	var best := 1
	for w in WARPS:
		if int(w) <= cap and float(w) * delta * 4.0 < left:
			best = int(w)
	if best != warp:
		_set_warp_value(best)


## Thrust towards the next node counts as burned Δv (KSP-style remaining-Δv tracking).
func _accumulate_burn(dt: float) -> void:
	var n := plan.first()
	if n == null or active.thrust_n <= 0.0 or not n.valid:
		return
	var window := maxf(node_burn_time(n), 10.0) * 1.5 + 30.0
	if time < n.time - window:
		return
	n.locked = true
	n.burned += active.accel_ng * dt


## Node bookkeeping each frame: completion (remaining Δv ~ 0 or overshoot).
func _update_nodes() -> void:
	var n := plan.first()
	if n == null or not n.locked or not n.valid or executor != null:
		return
	var rem := n.remaining_world()
	var full := Vector3(n.dv_world[0], n.dv_world[1], n.dv_world[2])
	if active.thrust_n <= 0.0 and (rem.length() < 0.2 or rem.dot(full) < 0.0):
		_finish_node(executor != null)


func _finish_node(from_executor: bool) -> void:
	var n := plan.first()
	if n != null:
		plan.remove(n)
	if from_executor:
		executor = null
		active.throttle = 0.0
		active.set_sas(FlightVessel.Sas.HOLD)
	hud.toast(tr("FL_NODE_DONE"), MarginPalette.SUCCESS)
	_traj_dirty = true


## Recomputes the cached prediction when needed (see the class notes).
func _update_trajectory(delta: float) -> void:
	if active.landed or active.clamped or active.crashed:
		if traj != null:
			traj = null
			if map_view:
				map.trajectory_changed()
		return
	_traj_timer -= delta
	var need: bool = _traj_dirty or traj == null or plan.version != _traj_version or time > traj.valid_until
	# periodic refresh: the state drifts from the cached conic under thrust / drag (and,
	# very slowly, numerically in physics warp); on rails it follows the conic exactly
	if not need and not on_rails and _traj_timer <= 0.0:
		need = true
	if need:
		_predict(0.4 if plan_dragging else 1.0)
		var thrusting := active.thrust_n > 0.0 or active.q_dyn > 1.0
		_traj_timer = (0.2 if map_view else 1.0) if thrusting else (2.0 if map_view else 8.0)


func _predict(quality: float) -> void:
	var b := active.body
	traj = FlightTrajectory.predict(sys, soi, b.pos(), b.vel(), time, plan.nodes, target_body, quality)
	_traj_dirty = false
	_traj_version = plan.version
	if map_view:
		map.trajectory_changed()


## Sun and Moon for the sky shader, from the real geometry at the current time.
func _update_sky_bodies(cam_earth: PackedFloat64Array) -> void:
	var sun_p := sys.pos_rel(sys.sun, sys.earth, time)
	var sd := Vector3(sun_p[0] - cam_earth[0], sun_p[1] - cam_earth[1], sun_p[2] - cam_earth[2]).normalized()
	var mp := sys.pos_rel(sys.moon, sys.earth, time)
	var md := Vector3(mp[0] - cam_earth[0], mp[1] - cam_earth[1], mp[2] - cam_earth[2])
	var dist := md.length()
	# drawn larger than life when far (an artistic choice, fades to the real size up close)
	var mag := clampf(1.0 + 2.5 * (dist - 3.0e7) / 3.5e8, 1.0, 3.5)
	var ang := asin(clampf(sys.radius[sys.moon] / maxf(dist, sys.radius[sys.moon] * 1.0001), 0.0, 1.0)) * mag
	sky.set_bodies(sd, md / dist, minf(ang, 1.5))


## Test / tool hook: puts the active vessel on a given state around a body (no launch).
func set_orbit_state(body: int, r: PackedFloat64Array, v: PackedFloat64Array) -> void:
	launched = true
	if liftoff_time < 0.0:
		liftoff_time = time
	active.clamped = false
	active.landed = false
	if body != soi:
		var air := sys.atmo_top[body] > 0.0
		active.body.rebase(PackedFloat64Array([0, 0, 0, 0, 0, 0]), sys.mu[body], sys.radius[body], air, body == sys.earth)
		soi = body
	active.body.set_state(r, v)
	active.prev.copy_from(active.body)
	for d in debris:
		d.queue_free()
	debris.clear()
	_traj_dirty = true
