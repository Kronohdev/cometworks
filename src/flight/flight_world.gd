class_name FlightWorld
extends Node3D
## Flight test scene controller (scenes/flight/flight.tscn): builds the rocket from
## FlightSession, runs the fixed-step simulation with time warp, keeps the floating origin
## on the active vessel, drives the camera, sky, smoke, map view and HUD, and writes the
## flight-test report.
##
## Frames: the simulation runs in the planet-centred inertial frame (PCI, doubles) with
## +Y = up at the launch pad. The render frame is the PCI frame translated by `origin`
## (= the active vessel, interpolated), so the rocket is always rendered near (0, 0, 0)
## and the launch site / planet / smoke / debris are placed at (PCI - origin).

signal flight_ended(report: Dictionary)

const DT := 0.02
const MAX_STEPS_PER_FRAME := 400
const PHYS_WARPS := [1, 2, 4]
const RAILS_WARPS := [1, 10, 50, 100, 1000]
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
var warp_index := 0
var on_rails := false
var _rails_t0 := 0.0
var _rails_state := PackedFloat64Array()
var _acc := 0.0
var _alpha := 1.0
var paused := false
var ended := false
var map_view := false
var autopilot: FlightAutopilot = null
## extra physics warp for scripted runs (screenshots); players use PHYS_WARPS
var debug_warp := 1.0
## steering input injected by test scripts (pitch, roll, yaw); zero = keyboard
var scripted_input := Vector3.ZERO
var predicted_dv := 0.0
var vessel_name := ""
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
	hud.setup(self)
	map.setup(sky.planet_to_tex(), sky.sun_direction, sky.moon_direction)
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
	if map_view and map.handle_input(event):
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
			change_warp(1)
		KEY_COMMA:
			change_warp(-1)
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
	var rails_ok := _rails_allowed()
	var levels: Array = RAILS_WARPS if rails_ok else PHYS_WARPS
	var cur: int = current_warp()
	var idx := levels.find(cur)
	if idx < 0:
		idx = 0
	idx = clampi(idx + d, 0, levels.size() - 1)
	_set_warp_value(int(levels[idx]))
	if d > 0 and idx == levels.size() - 1 and not rails_ok and active.body.altitude() < FlightOrbit.ATMO_TOP:
		hud.toast(tr("FL_WARP_ATMO"), MarginPalette.WARNING)


func current_warp() -> int:
	if on_rails:
		return int(RAILS_WARPS[warp_index])
	return int(PHYS_WARPS[warp_index]) if warp_index < PHYS_WARPS.size() else 1


func _set_warp_value(w: int) -> void:
	if w >= 10:
		if not on_rails:
			_enter_rails()
		warp_index = RAILS_WARPS.find(w)
	else:
		if on_rails:
			_exit_rails()
		warp_index = maxi(PHYS_WARPS.find(w), 0)


func _rails_allowed() -> bool:
	return launched and not active.landed and active.body.altitude() > FlightOrbit.ATMO_TOP \
		and active.thrust_n <= 0.0 and not active.crashed and (autopilot == null or autopilot.done)


func _enter_rails() -> void:
	on_rails = true
	_rails_t0 = time
	_rails_state = PackedFloat64Array([active.body.px, active.body.py, active.body.pz,
		active.body.vx, active.body.vy, active.body.vz])
	active.body.w = Vector3.ZERO
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
		_simulate(delta)
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
		if not _rails_allowed() or active.body.altitude() < FlightOrbit.ATMO_TOP:
			_set_warp_value(1)
		else:
			var w := float(RAILS_WARPS[warp_index])
			time += delta * w
			var s := FlightOrbit.propagate(FlightOrbit.vec(_rails_state[0], _rails_state[1], _rails_state[2]),
				FlightOrbit.vec(_rails_state[3], _rails_state[4], _rails_state[5]), time - _rails_t0)
			active.body.set_from_array(s)
			active.prev.copy_from(active.body)
			_alpha = 1.0
			_track_stats(0.0)
			return
	var w := float(PHYS_WARPS[warp_index]) * debug_warp
	_acc += delta * w
	var steps := 0
	while _acc >= DT and steps < MAX_STEPS_PER_FRAME:
		_acc -= DT
		steps += 1
		_step(DT)
		if ended:
			break
	if steps >= MAX_STEPS_PER_FRAME:
		_acc = 0.0
	_alpha = clampf(_acc / DT, 0.0, 1.0)


func _step(dt: float) -> void:
	time += dt
	if autopilot:
		if autopilot.update(active, dt):
			stage()
	var dropped := active.physics_step(dt)
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
	if not _orbit_announced and alt > FlightOrbit.ATMO_TOP and active.thrust_n <= 0.0:
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
	var el := FlightOrbit.elements(active.body.pos(), active.body.vel())
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
	for m in _site_materials:
		m.set_shader_parameter("site_origin", site.position)
	var alt := active.body.altitude()
	site.visible = alt < SITE_HIDE_ALT
	# above a few km the sky shader draws the site's coast itself (no plane edge in view)
	if _ground_plane:
		var cam_alt := alt + cam.camera.global_position.dot(active.body.up())
		_ground_plane.visible = cam_alt < GROUND_PLANE_ALT
	var up := active.body.up()
	var cam_render := cam.camera.global_position
	var cam_pci := PackedFloat64Array([ox + cam_render.x, oy + cam_render.y, oz + cam_render.z])
	sky.update_camera(cam_pci, PackedFloat64Array(SITE_ORIGIN), map_view)
	var focus := Vector3.ZERO if not active.crashed else _crash_focus()
	cam.min_height = _ground_floor(focus) - _alt_of_render(focus)
	cam.update_camera(get_process_delta_time(), focus, up)
	cam.shake = maxf(cam.shake - get_process_delta_time() * 1.5, 0.0)
	if launched and not active.crashed and active.thrust_n > 0.0 and alt < 3000.0:
		cam.shake = maxf(cam.shake, 0.12 * (1.0 - alt / 3000.0))
	if map_view:
		map.update_map(active, origin, debris)


## Altitude (m) of a render-space point (doubles via the floating origin).
func _alt_of_render(p: Vector3) -> float:
	var x: float = origin[0] + p.x
	var y: float = origin[1] + p.y
	var z: float = origin[2] + p.z
	return sqrt(x * x + y * y + z * z) - FlightOrbit.R


## Lowest allowed camera altitude near a render-space point: the launcher top around the
## pad, sea level (= the planet surface) elsewhere, plus a margin.
func _ground_floor(p: Vector3) -> float:
	var x: float = origin[0] + p.x
	var y: float = origin[1] + p.y
	var z: float = origin[2] + p.z
	var r := sqrt(x * x + y * y + z * z)
	var horiz := Vector3(x / r, y / r, z / r).distance_to(_pad_up) * FlightOrbit.R
	var ground := PAD_TOP if horiz < 450.0 else 0.0
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
	if not paused and not on_rails:
		_emit_smoke(delta * float(PHYS_WARPS[warp_index]) * debug_warp)
	smoke.update(delta * (1.0 if paused else float(PHYS_WARPS[warp_index]) * debug_warp) * (0.0 if paused else 1.0),
		ox, oy, oz, active.body.up())


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
func _telemetry() -> Dictionary:
	var b := active.body
	var el := FlightOrbit.elements(b.pos(), b.vel())
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
	return {"alt": b.altitude(), "vs": b.vertical_speed(), "hs": b.horizontal_speed(), "speed": b.speed(),
		"ap": el["ap_alt"], "pe": el["pe_alt"], "e": el["e"], "t_ap": FlightOrbit.time_to_apoapsis(b.pos(), b.vel()),
		"g": active.g_load, "q": active.q_dyn, "max_q": stats["max_q"], "maxq_passed": _maxq_announced,
		"throttle": active.throttle, "thrust": active.thrust_n, "mass": active.mass,
		"dv_stage": dv_stage, "dv_total": dv_total, "dv_rows": _dv_cache,
		"met": mission_time(), "launched": launched, "warp": current_warp(), "rails": on_rails,
		"sas": active.sas, "auto": autopilot != null, "q_body": active.body.q, "up": up, "east": east_now,
		"vel": b.velocity_v3(), "nose": nose, "stage": active.current_stage, "stages": active.stage_count,
		"vessel": active, "mach": active.mach, "aoa": active.aoa, "orbit": _orbit_announced}
