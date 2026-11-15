class_name FlightWorld
extends Node3D
## The 3D view of a flight (scenes/flight/flight.tscn). It shows a FlightRun (simulation,
## autopilot and log, all node free) and advances it with the frame's time × the time warp:
## the run can be handed in by the host (a career launch that already lifted off on the campus,
## a craft followed from the map) or made here from FlightSession (the hangar's test flight,
## a piloted mission launch). Closing the view does not end the run: the host may keep it.
##
## What it draws:
##   the rocket     FlightModel: the hangar's own part tree and engine plumes; the groups the
##                  craft drops become falling pieces (debris), a break-up throws every piece
##   the island     the Cometlings' campus under the pad (FlightIsland; inside the tycoon it is
##                  the live campus itself, borrowed by TycoonModes), scaled so the rocket keeps
##                  its campus proportions; it falls away below until the planet takes over
##   the planet     FlightSky (the curved Earth, its air going from blue to black, sun and Moon)
##   effects        exhaust smoke in the toon look (FlightSmoke puffs: thick and white low down,
##                  thin up high, none in vacuum), separation puffs, ground clouds at liftoff
##   the camera     FlightCamera; for an automatic flight a small director picks the shots
##                  (tower cam at liftoff, the island below, the staging up close in slow
##                  motion, the curve of the Earth in space) until the player drags the view
##   HUD and map    FlightHUD (telemetry from _telemetry()) and FlightMap (patched conics,
##                  maneuver nodes for a piloted flight)
## Frames: the simulation's inertial frame centred on the body that holds the craft; the render
## frame is that frame moved by `origin` (the craft, extrapolated to the view's time), so the
## rocket always renders near (0, 0, 0).
##
## Modes (set before it enters the tree): `embedded` (inside the tycoon: signals instead of
## scene changes), `mission_mode` (a piloted mission launch: no reverts), `spectator` (the player
## only watches: camera, map and warp are free, "Voltar" leads out) and `map_only` (the solar
## system map alone, its time from `clock_source`).

signal flight_ended(report: Dictionary)
## Embedded only: "restart", "hangar", "done" (the flight is over or the player leaves; `report`
## is its last report) or "cancel" (left before liftoff).
signal exit_requested(what: String, report: Dictionary)
## Every simulation event as it is shown: key (EV_*), data
signal flight_event(key: String, data: Dictionary)

## Time warp levels ( , / . / the HUD arrows). Above RAILS_MIN the craft coasts on exact conics
## whenever it may; under thrust or in the air the physics runs at most PHYS_MAX times faster.
const WARPS := [1, 2, 4, 10, 50, 100, 1000, 10000, 100000, 1000000]
const PHYS_MAX := 100
const RAILS_MIN := 10
const NODE_LEAD := 20.0
## the launch direction from the pad (PCI)
const EAST := FlightRun.DOWNRANGE
const SITE_HIDE_ALT := 60000.0
const DEFAULT_VESSEL := "res://scenes/examples/garca.tscn"
const GRAPHICS_QUALITY := "res://src/core/graphics_quality.gd"
const EXPLOSION := preload("res://scenes/flight/explosion.tscn")
const DEBRIS_LIFE := 50.0
const DEBRIS_RANGE := 30000.0
const ORBIT_PE := FlightSim.ORBIT_PE

@export var auto_start_autopilot := false
@export var embedded := false
@export var mission_mode := false
@export var spectator := false
@export var map_only := false
## the island under the pad when the host lends none (scenes/flight/flight_island.tscn)
@export var island_scene: PackedScene
## the campus lot the rocket stands on
@export var pad_lot := "pad"
## the camera director's slow motion at a stage separation (0..1 of real time) and how long
@export_range(0.05, 1.0, 0.05) var separation_slowmo := 0.35
@export var separation_shot_s := 2.6
## launches around the Earth are lit by a fixed daytime sun (an artistic choice: the flight has
## no day and night of its own, so every launch is a daylight launch); elsewhere the real one
@export var cinematic_sun := true
@export var cinematic_sun_dir := Vector3(0.62, 0.55, 0.56)
## prints frame timings (debug)
@export var profile := false

var clock_source := Callable()
var run: FlightRun
var model: FlightModel
var island: FlightIsland
## the island the host lent (the live campus), given back by the host
var lent_island: Node3D = null
var origin := PackedFloat64Array([0.0, 6371000.0, 0.0])
## the time on show (flight seconds, FlightSolar's clock); the run is at or just past it
var time := 0.0
var warp := 1
var paused := false
var ended := false
var map_view := false
var debug_warp := 1.0
var vessel_name := ""
var predicted_dv := 0.0
var sys: FlightSolar
var plan := FlightManeuvers.new()
var traj: FlightTrajectory = null
var target_body := -1
var executor: FlightNodeExecutor = null
var plan_dragging := false
var _traj_dirty := true
var _traj_timer := 0.0
var _traj_version := -1
var _warp_to := -1.0
var _time_scale := 1.0
var _slowmo_left := 0.0
var _debris: Array = []
var _hud_timer := 0.0
var _dv_cache: Array = []
var _dv_time := 0
var _events: Array = []
var samples_t := PackedFloat32Array()
var samples_alt := PackedFloat32Array()
var samples_v := PackedFloat32Array()
var _sample_t := 0.0
var _last_report: Dictionary = {}
var _smoke_dist := 0.0
var _ground_cloud := 0.0
var _crash_shown := false
var _orbit_end_timer := -1.0
var _island_scale := 3.0
var _site_basis := Basis.IDENTITY
var _site_offset := Vector3.ZERO
## camera director: "" = the player's, else the shot ("pad", "tower", "climb", "stage", "space")
var shot := "pad"
var _shot_t := 0.0
var _tower_pci := PackedFloat64Array([0.0, 0.0, 0.0])
var _auto_camera := true
## the spent stage of the last separation (the stage shot keeps it in the frame)
var _sep_piece: Node3D = null
var _pole := Vector3(0, 0, -1)

@onready var sky: FlightSky = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var site: Node3D = $LaunchSite
@onready var vessels: Node3D = $Vessels
@onready var smoke: FlightSmoke = $Smoke
@onready var cam: FlightCamera = $CameraRig
@onready var map: FlightMap = $HUD/MapView
@onready var hud: FlightHUD = $HUD
@onready var effects: Node3D = $Effects


# ------------------------------------------------------------ setup
func _ready() -> void:
	if ResourceLoader.exists(GRAPHICS_QUALITY):
		var gq: Script = load(GRAPHICS_QUALITY)
		if gq and gq.has_method("apply"):
			gq.call("apply", self)
	if not TranslationServer.get_locale().begins_with("pt") and not TranslationServer.get_locale().begins_with("en"):
		TranslationServer.set_locale("pt" if OS.get_locale_language() == "pt" else "en")
	sys = FlightSolar.get_system()
	_pole = (sky.planet_to_tex().transposed() * Vector3.DOWN).normalized()
	if run == null:
		run = _run_from_session()
	vessel_name = run.vessel_name
	predicted_dv = FlightSession.predicted_dv if FlightSession.predicted_dv > 0.0 else run.sim.craft.total_dv()
	time = run.sim.t
	model = FlightModel.new()
	model.name = "Active"
	vessels.add_child(model)
	model.setup(run.vessel_scene, run.sim.craft)
	_catch_up_model()
	# what happened before the view opened goes in the log only (no shots, no sounds)
	if run.sim.launched:
		for e: Array in run.take_pending():
			_events.append({"t": float(e[2]), "key": String(e[0]), "data": e[1], "alt": run.sim.altitude()})
	_island_scale = FlightRun.island_scale(run.sim.craft.length)
	_setup_island()
	plan.changed.connect(func() -> void: _traj_dirty = true)
	hud.setup(self)
	map.setup(self, sky.planet_to_tex())
	hud.action.connect(_on_hud_action)
	cam.reference = EAST.cross(Vector3.UP).normalized() * -1.0
	# the tower camera: off to the side of the range, up over the trees, the pad in its frame
	var side := Vector3.UP.cross(EAST).normalized()
	var len := run.sim.craft.length
	_tower_pci = _pad_pci((side * 1.0 - EAST * 0.35).normalized() * maxf(len * 2.8, 70.0), maxf(len * 0.75, 25.0))
	if run.sim.launched:
		shot = "climb"
		cam.set_view(0.6, 0.45, clampf(run.sim.craft.length * 3.0, 30.0, 300.0), true)
	else:
		cam.set_view(2.6, 0.04, clampf(run.sim.craft.length * 1.35, 25.0, 160.0), true)
	if (auto_start_autopilot or FlightSession.auto_ascent) and run.guide == null:
		set_autopilot(true)
	_auto_camera = run.guide != null or spectator
	if embedded and mission_mode:
		_setup_mission_hud()
	if spectator:
		_setup_spectator_hud()
	if map_only:
		_setup_map_only()
	_place_world(0.0)
	var goal := String(FlightSession.mission.get("goal", ""))
	if mission_mode and goal != "":
		hud.toast.call_deferred(tr("TY_HG_CHOICE_PILOT_GOAL") % goal, MarginPalette.ACCENT)


## The handoff from the campus cinematic: the camera starts where the campus camera was, seen
## from the rocket (`offset` in campus axes and units), and the director carries on from there.
func start_from_campus_camera(offset: Vector3, fov := 55.0) -> void:
	var d := (_site_basis.orthonormalized() * offset)
	# the same framing with our wider lens: closer by the ratio of the lens widths
	var lens := tan(deg_to_rad(clampf(fov, 10.0, 90.0)) * 0.5) / tan(deg_to_rad(55.0) * 0.5)
	var dist := clampf(d.length() * _island_scale * lens, 15.0, 900.0)
	var up := run.sim.up()
	var dn := d.normalized()
	var ref := (cam.reference - up * cam.reference.dot(up)).normalized()
	var side := up.cross(ref).normalized()
	var h := dn - up * dn.dot(up)
	cam.set_view(atan2(h.dot(side), h.dot(ref)), asin(clampf(dn.dot(up), -1.0, 1.0)), dist, true)
	_auto_camera = true
	_set_shot("climb")
	_place_world(0.0)


## The test flight / piloted launch: the vessel FlightSession holds, on the pad.
func _run_from_session() -> FlightRun:
	var ps: PackedScene = FlightSession.vessel_scene
	var n := FlightSession.vessel_name
	if ps == null:
		ps = load(DEFAULT_VESSEL)
		n = ExampleVessels.display_name("garca")
		FlightSession.set_vessel(ps, n, 0.0)
	return FlightRun.on_pad(ps, float(FlightSession.mission.get("payload_kg", 0.0)), n)


## A run handed in mid-flight: the model drops what the craft already dropped.
func _catch_up_model() -> void:
	var c := run.sim.craft
	for gi in c.groups.size():
		if not c.groups[gi]["attached"]:
			var p := model.detach_group(gi)
			if p:
				p.free()
	for f: Dictionary in c.fairings:
		if not f["attached"]:
			var p := model.detach_part(int(f["part"]))
			if p:
				p.free()
	run.take_dropped()
	if run.sim.crashed:
		model.visible = false


func _setup_island() -> void:
	if lent_island:
		island = FlightIsland.lend(lent_island)
	elif island_scene:
		island = island_scene.instantiate() as FlightIsland
	if island == null:
		return
	site.add_child(island)
	island.prepare(pad_lot)
	# the pad deck sits under the rocket, the campus sea on the planet's sea
	# the pad's front (its lot's -Z turned by its "face") points down the range
	var face := island.pad_face(pad_lot)
	var yaw := atan2(EAST.x, EAST.z) - atan2(-sin(face), -cos(face))
	_site_basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _island_scale)
	_site_offset = -(_site_basis * island.pad_point(pad_lot))


## Piloted mission launch: no reverts, the hangar keys lead out of the flight.
func _setup_mission_hud() -> void:
	for n in ["%BtnRevertLaunch", "%BtnRLaunch"]:
		var b := hud.get_node_or_null(n) as Control
		if b:
			b.visible = false
	var abort := hud.get_node_or_null("%BtnRevertHangar") as Button
	if abort:
		abort.text = tr("TY_HG_FL_ABORT")
	var done := hud.get_node_or_null("%BtnRHangar") as Button
	if done:
		done.text = tr("TY_HG_FL_CONCLUDE")


func _setup_spectator_hud() -> void:
	for n in ["%BtnRevertLaunch", "%BtnRLaunch"]:
		var b := hud.get_node_or_null(n) as Control
		if b:
			b.visible = false
	var out := hud.get_node_or_null("%BtnRevertHangar") as Button
	if out:
		out.text = tr("TY_TRK_BACK_CAMPUS")
	var hint := hud.get_node_or_null("%Hint") as Label
	if hint:
		hint.text = tr("TY_TRK_PAD_HINT")
	# a watched flight is a film: the flight panels wait behind F2
	if hud.hud_visible:
		hud.toggle_hud()


func _setup_map_only() -> void:
	map.show_vessel = false
	set_map(true)
	if hud.hud_visible:
		hud.toggle_hud()


# ------------------------------------------------------------ shortcuts
var sim: FlightSim:
	get:
		return run.sim if run else null

var soi: int:
	get:
		return run.sim.body if run else 0

var launched: bool:
	get:
		return run.sim.launched if run else false

var stats: Dictionary:
	get:
		return run.sim.stats if run else {}


func up_now() -> Vector3:
	return run.sim.up() if run else Vector3.UP


func mission_time() -> float:
	return run.sim.met() if run else 0.0


func in_orbit() -> bool:
	return run != null and run.sim.in_orbit


func autopilot_on() -> bool:
	return run != null and run.guide != null and not (run.guide is FlightNodeExecutor)


# ------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if map_only:
		if map.handle_input(event):
			return
		var key := event as InputEventKey
		if key and key.pressed and not key.echo and key.keycode in [KEY_ESCAPE, KEY_BACKSPACE, KEY_M]:
			exit_requested.emit("done", {})
		return
	if ended and not (event is InputEventKey):
		return
	if not map_view and cam.handle_input(event):
		if event is InputEventMouseMotion or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
			_take_camera()
		return
	if map_view and not paused and map.handle_input(event):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if spectator and ended and k.keycode in [KEY_ESCAPE, KEY_BACKSPACE]:
		exit_requested.emit("done", _last_report)
		return
	match k.keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			toggle_pause()
		KEY_F2:
			hud.toggle_hud()
		KEY_F1:
			hud.toggle_help()
		KEY_C:
			_auto_camera = not _auto_camera
	if paused or ended:
		return
	if spectator and not k.keycode in [KEY_M, KEY_PERIOD, KEY_COMMA]:
		return
	var c := run.sim.craft
	match k.keycode:
		KEY_SPACE:
			stage()
		KEY_T:
			set_autopilot(false)
			c.sas = FlightCraft.Sas.OFF if c.sas != FlightCraft.Sas.OFF else FlightCraft.Sas.HOLD
			run.sim.command = run.sim.nose()
		KEY_G:
			set_autopilot(false)
			c.sas = FlightCraft.Sas.PROGRADE
		KEY_H:
			set_autopilot(false)
			c.sas = FlightCraft.Sas.RETROGRADE
		KEY_P:
			set_autopilot(not autopilot_on())
		KEY_M:
			set_map(not map_view)
		KEY_Z:
			c.throttle = 1.0
		KEY_X:
			c.throttle = 0.0
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
			if in_orbit():
				end_flight("orbit")


## The player moved the camera: the director lets go.
func _take_camera() -> void:
	if _auto_camera:
		_auto_camera = false
		shot = ""


func _read_flight_keys(delta: float) -> void:
	var s := run.sim
	if paused or ended or s.crashed or spectator or map_only or run.guide != null:
		s.input = Vector3.ZERO
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
	s.input = u
	if Input.is_physical_key_pressed(KEY_SHIFT):
		s.craft.throttle = minf(s.craft.throttle + delta * 0.7, 1.0)
	if Input.is_physical_key_pressed(KEY_CTRL):
		s.craft.throttle = maxf(s.craft.throttle - delta * 0.7, 0.0)


# ------------------------------------------------------------ actions
func stage() -> void:
	if run.sim.crashed or ended:
		return
	var was_pad := not run.sim.launched
	run.sim.stage()
	if was_pad:
		_log("EV_IGNITION_PAD", {})
	run._collect()


func set_autopilot(on: bool) -> void:
	if on and not autopilot_on():
		executor = null
		run.set_auto(true)
		hud.toast(tr("FL_AUTO_ON"), MarginPalette.ACCENT_2)
	elif not on and autopilot_on():
		run.set_auto(false)
		hud.toast(tr("FL_AUTO_OFF"), MarginPalette.TEXT_DIM)


## Starts / stops the "execute next node" autopilot (it flies as the run's guide meanwhile).
func set_executor(on: bool) -> void:
	if on and executor == null:
		var n := plan.first()
		if n == null or not launched:
			return
		run.set_auto(false)
		executor = FlightNodeExecutor.new(n)
		run.guide = executor
		hud.toast(tr("FL_EXEC_ON"), MarginPalette.DATA_1)
		warp_to_next_node()
	elif not on and executor != null:
		executor = null
		run.guide = null
		run.sim.craft.throttle = 0.0
		run.sim.craft.sas = FlightCraft.Sas.HOLD
		run.sim.command = run.sim.nose()
		hud.toast(tr("FL_EXEC_OFF"), MarginPalette.TEXT_DIM)


func warp_to_next_node() -> void:
	var n := plan.first()
	if n == null:
		return
	var t := n.time - node_burn_time(n) * 0.5 - NODE_LEAD
	if t > time + 1.0:
		warp_to(t)


func warp_to(t: float) -> void:
	_warp_to = t
	hud.toast(tr("FL_WARPING_TO") % FlightHUD.fmt_time(t - time), MarginPalette.ACCENT)


func capture_planner() -> FlightCapture:
	var keep: Array[FlightManeuverNode] = []
	for n in plan.nodes:
		if not n.auto_capture or n.locked:
			keep.append(n)
	var last: FlightManeuverNode = keep[-1] if not keep.is_empty() else null
	return FlightCapture.new(sys, soi, run.sim.pos(), run.sim.vel(), time, keep, node_burn_time(last) if last else 0.0)


func plan_capture(pe_alt: float, ap_alt: float, inc_deg: float) -> Dictionary:
	if not launched or run.sim.landed:
		return {"ok": false, "msg": "FL_CAPT_NO_ENCOUNTER"}
	var res := capture_planner().plan(pe_alt, ap_alt, inc_deg)
	if res["ok"]:
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


func node_burn_time(n: FlightManeuverNode) -> float:
	var bt := run.sim.craft.burn_time(n.remaining_world().length() if n.locked else n.dv_total())
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
	var idx := maxi(WARPS.find(warp), 0)
	warp = int(WARPS[clampi(idx + d, 0, WARPS.size() - 1)])
	if d > 0 and warp > current_warp():
		hud.toast(_warp_limit_text(), MarginPalette.WARNING)


## The warp the simulation runs at now: the picked one on rails, capped in the air or under thrust.
func current_warp() -> int:
	return warp if warp < RAILS_MIN or rails_allowed() else mini(warp, PHYS_MAX)


func rails_allowed() -> bool:
	return _rails_block() == ""


func _rails_block() -> String:
	var s := run.sim
	if not s.launched or s.landed or s.crashed:
		return "FL_WARP_WHY_GROUND"
	if s.altitude() <= s.rails_floor() and not s.rails_source.is_valid():
		return "FL_WARP_WHY_AIR"
	if s.thrust_n > 0.0:
		return "FL_WARP_WHY_THRUST"
	if run.guide != null and run.guide is FlightGuide and (run.guide as FlightGuide).phase in ["ascent", "burn"]:
		return "FL_WARP_WHY_AUTO"
	var n := plan.first()
	if executor != null and n != null and time > n.time - node_burn_time(n) * 0.5 - NODE_LEAD - 0.5:
		return "FL_WARP_WHY_BURN"
	return ""


func _warp_limit_text() -> String:
	var why := _rails_block()
	var t := tr("FL_WARP_LIMIT") % PHYS_MAX
	if why == "FL_WARP_WHY_AIR":
		return t + " · " + tr(why) % FlightHUD.fmt_dist(run.sim.rails_floor())
	return t + " · " + tr(why) if why != "" else t


func revert_to_launch() -> void:
	if embedded:
		if not mission_mode:
			exit_requested.emit("restart", {})
		return
	get_tree().reload_current_scene()


func revert_to_hangar() -> void:
	if embedded:
		if spectator or map_only:
			exit_requested.emit("done", _last_report)
		elif mission_mode:
			finish_mission()
		else:
			exit_requested.emit("hangar", _last_report)
		return
	FlightSession.return_to_hangar = true
	get_tree().change_scene_to_file(FlightSession.HANGAR_SCENE)


func finish_mission() -> void:
	if not launched:
		exit_requested.emit("cancel", {})
		return
	if not ended:
		end_flight("orbit" if in_orbit() else ("crash" if run.sim.crashed else "abort"))
	exit_requested.emit("done", _last_report)


func _on_hud_action(what: String) -> void:
	if spectator and what in ["stage", "sas", "prograde", "retrograde", "auto", "end", "revert_launch", "continue"]:
		return
	var c := run.sim.craft
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
			end_flight("orbit" if in_orbit() else "abort")
		"continue":
			hud.hide_report()
			ended = false
		"stage":
			stage()
		"sas":
			set_autopilot(false)
			c.sas = FlightCraft.Sas.OFF if c.sas != FlightCraft.Sas.OFF else FlightCraft.Sas.HOLD
			run.sim.command = run.sim.nose()
		"prograde":
			set_autopilot(false)
			c.sas = FlightCraft.Sas.PROGRADE
		"retrograde":
			set_autopilot(false)
			c.sas = FlightCraft.Sas.RETROGRADE
		"auto":
			set_autopilot(not autopilot_on())
		"map":
			set_map(not map_view)
		"warp_up":
			change_warp(1)
		"warp_down":
			change_warp(-1)


# ------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	if map_only:
		if clock_source.is_valid():
			time = float(clock_source.call())
		_place_world(delta)
		return
	_read_flight_keys(delta)
	if not paused and not ended:
		_update_warp_to(delta)
		_advance(delta)
		_update_nodes()
		_update_trajectory(delta)
	_place_world(delta)
	_update_effects(delta)
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.1
		hud.update_telemetry(_telemetry())
	if _orbit_end_timer > 0.0:
		_orbit_end_timer -= delta
		if _orbit_end_timer <= 0.0 and not ended and in_orbit():
			end_flight("orbit")


func _advance(delta: float) -> void:
	if _slowmo_left > 0.0:
		_slowmo_left -= delta
		_time_scale = separation_slowmo if _slowmo_left > 0.0 else 1.0
	var w := float(current_warp()) * debug_warp
	var dt := delta * w * _time_scale
	time += dt
	var steps := 600 if w > 1.0 else 60
	if time > run.sim.t:
		run.advance(time - run.sim.t, steps)
	if run.sim.t < time - 1.0:
		time = run.sim.t   # the physics could not keep up: the view waits for it
	if run.sim.crashed:
		time = maxf(time, run.sim.t)
	for e: Array in run.take_pending():
		_on_event(String(e[0]), e[1], float(e[2]))
	for d: Dictionary in run.take_dropped():
		_drop(d)
	# samples for the report
	_sample_t -= dt
	if launched and _sample_t <= 0.0:
		_sample_t = 1.0
		samples_t.append(mission_time())
		samples_alt.append(run.sim.altitude())
		samples_v.append(run.sim.speed())
	# rails warp: no debris, no smoke
	if run.sim.on_rails and warp >= RAILS_MIN:
		_clear_debris()


func _on_event(key: String, data: Dictionary, met: float) -> void:
	_log(key, data, met)
	match key:
		"EV_LIFTOFF":
			_sound(&"launch_ignition")
			if _auto_camera:
				_set_shot("tower")
		"EV_STAGE_SEP", "EV_BOOSTER_SEP", "EV_FAIRING":
			_sound(&"launch_fwoomp")
			if _auto_camera and key == "EV_STAGE_SEP" and warp <= 1:
				_set_shot("stage")
				_slowmo_left = separation_shot_s
		"EV_CRASH":
			_breakup()
		"EV_ORBIT":
			_sound(&"result_success")
			if not spectator:
				_orbit_end_timer = 5.0
			if _auto_camera:
				_set_shot("space")
		"EV_FLAMEOUT":
			_sound(&"launch_engine_cut")
		"EV_SOI":
			smoke.clear()
			_clear_debris()
	flight_event.emit(key, data)


func _log(key: String, data: Dictionary, met := -1.0) -> void:
	var t := met if met >= 0.0 else mission_time()
	if not _events.is_empty() and _events[-1]["key"] == key and absf(float(_events[-1]["t"]) - t) < 0.5:
		return
	_events.append({"t": t, "key": key, "data": data, "alt": run.sim.altitude()})
	hud.event(key, data)


## A sound hook: the game's sound library (CwAudio, assets/audio/cw_sound_library.tres).
func _sound(id: StringName) -> void:
	if not Engine.is_editor_hint():
		CwSfx.play(id)


func end_flight(result: String) -> void:
	if ended:
		return
	ended = true
	warp = 1
	var r := run.sim.report(result)
	r["vessel"] = vessel_name
	r["dv_predicted"] = predicted_dv
	r["events"] = _events.duplicate()
	r["samples_t"] = samples_t
	r["samples_alt"] = samples_alt
	r["samples_v"] = samples_v
	_last_report = r
	if not spectator:
		hud.show_report(r)
	flight_ended.emit(r)


func last_report() -> Dictionary:
	return _last_report


# ------------------------------------------------------------ pieces and break-up
func _drop(d: Dictionary) -> void:
	var s := run.sim
	var nose := s.nose()
	for gi: int in d.get("groups", []):
		var piece := model.detach_group(gi)
		_add_piece(piece, nose, String(s.craft.groups[gi]["kind"]) == "booster")
		if piece and String(s.craft.groups[gi]["kind"]) == "stack":
			_sep_piece = piece
	for pi: int in d.get("fairings", []):
		_add_piece(model.detach_part(pi), nose, true)
	_separation_puff()


func _add_piece(piece: Node3D, nose: Vector3, sideways: bool) -> void:
	if piece == null:
		return
	effects.add_child(piece)
	var xf: Transform3D = model.global_transform * (piece.get_meta("local_xf") as Transform3D)
	piece.global_transform = xf
	var s := run.sim
	var out := xf.origin - model.global_transform * model.center()
	out -= nose * out.dot(nose)
	var push := -nose * 3.0
	if sideways and out.length() > 0.01:
		push += out.normalized() * 4.0
	var p := PackedFloat64Array([origin[0] + xf.origin.x, origin[1] + xf.origin.y, origin[2] + xf.origin.z])
	_debris.append({"node": piece, "pci": p, "vel": s.velocity_v3() + push,
		"w": (out.normalized().cross(nose) if out.length() > 0.01 else Vector3.RIGHT) * (0.5 if sideways else 0.15),
		"age": 0.0})


func _clear_debris() -> void:
	for d: Dictionary in _debris:
		if is_instance_valid(d["node"]):
			(d["node"] as Node).queue_free()
	_debris.clear()


func _update_debris(dt: float) -> void:
	var mu := sys.mu[soi]
	for d: Dictionary in _debris.duplicate():
		var n := d["node"] as Node3D
		d["age"] = float(d["age"]) + dt
		var p: PackedFloat64Array = d["pci"]
		var r := sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])
		var g := Vector3(p[0], p[1], p[2]) * (-mu / (r * r * r))
		var v: Vector3 = d["vel"]
		v += g * dt
		var alt := r - sys.radius[soi]
		if soi == sys.earth and alt < 80000.0:
			# the air slows a tumbling piece far more than the streamlined rocket
			v *= exp(-dt * 0.08 * FlightOrbit.density(alt) / FlightOrbit.RHO0 * 6.0)
		d["vel"] = v
		p[0] += v.x * dt
		p[1] += v.y * dt
		p[2] += v.z * dt
		d["pci"] = p
		var rel := Vector3(p[0] - origin[0], p[1] - origin[1], p[2] - origin[2])
		if not is_instance_valid(n) or float(d["age"]) > DEBRIS_LIFE or rel.length() > DEBRIS_RANGE or alt < 0.0:
			if is_instance_valid(n):
				if alt < 0.0 and rel.length() < 8000.0:
					_spawn_explosion(rel, 0.6)
				n.queue_free()
			_debris.erase(d)
			continue
		var w: Vector3 = d["w"]
		var b := n.global_basis
		if w.length() > 1e-4:
			b = Basis(w.normalized(), w.length() * dt) * b
		n.global_transform = Transform3D(b, rel)


func _breakup() -> void:
	if _crash_shown:
		return
	_crash_shown = true
	var s := run.sim
	var c := s.craft
	var center := model.global_transform * model.center()
	_spawn_explosion(center, clampf(c.length / 8.0, 1.0, 8.0))
	var nose := s.nose()
	for gi in c.groups.size():
		var piece := model.detach_group(gi)
		_add_piece(piece, nose, true)
	for f: Dictionary in c.fairings:
		_add_piece(model.detach_part(int(f["part"])), nose, true)
	# whatever is left (the root group) tumbles too
	var root := model.detach_part(int(c.groups[0]["root"])) if not c.groups.is_empty() else null
	_add_piece(root, nose, true)
	for d: Dictionary in _debris:
		var off := (d["node"] as Node3D).global_position - center
		d["vel"] = (d["vel"] as Vector3) * 0.8 + (off.normalized() if off.length() > 0.01 else Vector3.UP) * randf_range(18.0, 40.0)
		d["w"] = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 4.0
	model.engines_off()
	var vacuum := s.pressure < 0.01
	for i in 26:
		var dir := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
		var pp := PackedFloat64Array([origin[0] + center.x, origin[1] + center.y, origin[2] + center.z])
		smoke.emit(pp, s.velocity_v3() * 0.7 + dir * randf_range(6.0, 20.0), randf_range(3.0, 6.0), c.radius * 2.0,
			c.radius * randf_range(9.0, 14.0), 0.9, 0.35, 0.0 if vacuum else 0.6)
	_sound(&"launch_debris")
	if not spectator:
		get_tree().create_timer(3.5).timeout.connect(func() -> void: end_flight("crash"))


func _spawn_explosion(pos: Vector3, scale_k: float) -> void:
	var ex: Node3D = EXPLOSION.instantiate()
	effects.add_child(ex)
	ex.global_position = pos
	ex.scale = Vector3.ONE * scale_k
	if cam.camera.global_position.distance_to(pos) < 600.0:
		cam.shake = 2.0 * scale_k


## The white puff of a separation, around the interstage.
func _separation_puff() -> void:
	var s := run.sim
	var center := model.global_transform * Vector3(0, model.bounds.position.y, 0)
	var b := Basis(s.q)
	var vacuum := s.pressure < 0.01
	for i in 14:
		var dir := (b * Vector3(randf() - 0.5, (randf() - 0.5) * 0.3, randf() - 0.5)).normalized()
		var p := PackedFloat64Array([origin[0] + center.x, origin[1] + center.y, origin[2] + center.z])
		smoke.emit(p, s.velocity_v3() + dir * randf_range(4.0, 12.0), randf_range(1.2, 2.4), s.craft.radius,
			s.craft.radius * randf_range(3.0, 5.0), 0.7, 0.05, 0.0 if vacuum else 0.8)


# ------------------------------------------------------------ rendering
## The craft's place at the view's time (the run may be a step ahead): doubles.
func _craft_pci() -> PackedFloat64Array:
	var s := run.sim
	var k := time - s.t if not s.crashed else 0.0
	return PackedFloat64Array([s.px + s.vx * k, s.py + s.vy * k, s.pz + s.vz * k])


## A point near the pad (PCI of the Earth frame): `off` horizontally, `h` m above the deck.
func _pad_pci(off: Vector3, h: float) -> PackedFloat64Array:
	var r := sys.radius[sys.earth] + run.sim.pad_alt + h
	return PackedFloat64Array([off.x, r, off.z])


func _place_world(delta: float) -> void:
	var s := run.sim
	if not (s.crashed and _crash_shown):
		origin = _craft_pci()
	var ox: float = origin[0]
	var oy: float = origin[1]
	var oz: float = origin[2]
	model.transform = Transform3D(Basis(s.q), Vector3.ZERO)
	model.set_engines(s.pressure)
	var alt := s.altitude()
	var home := soi == sys.earth
	if island:
		var on := home and alt < SITE_HIDE_ALT
		site.visible = on
		if on:
			island.set_far(alt + cam.camera.global_position.dot(up_now()) > _island_scale * 300.0)
			var pad := _pad_pci(Vector3.ZERO, 0.0)
			site.transform = Transform3D(_site_basis, Vector3(pad[0] - ox, pad[1] - oy, pad[2] - oz) + _site_offset)
	var up := s.up()
	var cam_render := cam.camera.global_position
	var cam_pci := PackedFloat64Array([ox + cam_render.x, oy + cam_render.y, oz + cam_render.z])
	if not home:
		var eo := sys.pos_rel(soi, sys.earth, time)
		cam_pci = PackedFloat64Array([cam_pci[0] + eo[0], cam_pci[1] + eo[1], cam_pci[2] + eo[2]])
	_update_sky_bodies(cam_pci)
	sky.update_camera(cam_pci, _pad_pci(Vector3.ZERO, 0.0) if home else cam_pci, map_view)
	_direct_camera(delta)
	var focus := model.global_transform * model.center() if not (s.crashed and _crash_shown) else _crash_focus()
	if shot == "stage" and is_instance_valid(_sep_piece) and _sep_piece.is_inside_tree():
		# the separation: between the stage going on and the one falling away
		focus = focus.lerp(_sep_piece.global_position, 0.4)
	cam.min_height = (s.pad_alt + 3.0 - alt) if home and alt < 3000.0 else -INF
	if shot == "tower" and home:
		_tower_camera(focus, up)
	else:
		cam.update_camera(delta, focus, up)
	cam.shake = maxf(cam.shake - delta * 1.5, 0.0)
	if launched and not s.crashed and s.thrust_n > 0.0 and alt < 3000.0 and home:
		cam.shake = maxf(cam.shake, 0.15 * (1.0 - alt / 3000.0))
	if map_view:
		map.update_map()


## The liftoff shot: a camera standing near the pad, watching the rocket go.
func _tower_camera(focus: Vector3, up: Vector3) -> void:
	var p := Vector3(_tower_pci[0] - origin[0], _tower_pci[1] - origin[1], _tower_pci[2] - origin[2])
	cam.global_position = p
	cam.camera.global_position = p
	var to := focus - p
	if to.length() > 0.1:
		cam.camera.look_at(focus, up if absf(to.normalized().dot(up)) < 0.98 else Vector3.RIGHT)
	cam.camera.fov = lerpf(cam.camera.fov, clampf(rad_to_deg(atan2(run.sim.craft.length * 2.2, to.length())) * 2.0, 18.0, 60.0),
		0.1)


func _set_shot(s: String) -> void:
	shot = s
	_shot_t = 0.0


## The director of an automatic flight: which shot, and the camera's place in it.
func _direct_camera(delta: float) -> void:
	_shot_t += delta
	if not _auto_camera:
		cam.smooth = 8.0
		cam.camera.fov = lerpf(cam.camera.fov, 55.0, clampf(delta * 3.0, 0.0, 1.0))
		return
	var s := run.sim
	var length := s.craft.length
	# slow, cinematic moves between shots; the stage shot is snappier
	cam.smooth = 3.0 if shot == "stage" else lerpf(0.7, 4.0, clampf(_shot_t / 10.0, 0.0, 1.0))
	match shot:
		"tower":
			if s.altitude() > s.pad_alt + length * 6.0 or _shot_t > 9.0:
				cam.camera.fov = 55.0
				# start the chase where the tower camera looked from
				var off := cam.global_position - model.global_transform * model.center()
				var up := s.up()
				cam.set_view(cam.yaw, asin(clampf(off.normalized().dot(up), -1.0, 1.0)), clampf(off.length(), 20.0, 600.0), true)
				_set_shot("climb")
		"climb":
			cam.camera.fov = lerpf(cam.camera.fov, 55.0, clampf(delta * 2.0, 0.0, 1.0))
			# looking back down its trail: the island (the pad) behind the rocket, smaller and
			# smaller, then the curve of the Earth
			var alt := s.altitude()
			var k := clampf((alt - 20000.0) / 30000.0, 0.0, 1.0)
			var trail := _trail_view()
			# off to the side of the trail, so the smoke does not hide the rocket
			cam.set_view(trail.x + lerpf(0.3, 0.6, clampf(alt / 4000.0, 0.0, 1.0)), lerpf(trail.y - 0.18, 0.35, k),
				clampf(length * 2.6 + minf(alt * 0.012, 140.0), 30.0, 400.0))
			if s.altitude() > 90000.0:
				_set_shot("space")
		"stage":
			# from the side, wide enough for the spent stage falling away
			cam.set_view(_downrange_yaw() + 1.75, 0.05, clampf(length * 2.6, 25.0, 260.0))
			if _shot_t > separation_shot_s + 0.4:
				_set_shot("climb" if s.altitude() < 90000.0 else "space")
		"space":
			# wide: the craft against the curve of the Earth
			cam.set_view(0.9 + _shot_t * 0.02, 0.28, clampf(length * 7.0, 60.0, 900.0))
		"pad":
			pass


## (yaw, pitch) of the line from the pad through the craft: a camera there sees the pad behind it.
func _trail_view() -> Vector2:
	var s := run.sim
	var pad := _pad_pci(Vector3.ZERO, 0.0)
	var d := Vector3(s.px - pad[0], s.py - pad[1], s.pz - pad[2])
	if d.length() < 1.0:
		return Vector2(_downrange_yaw(), 0.6)
	d = d.normalized()
	var up := s.up()
	var ref := (cam.reference - up * cam.reference.dot(up)).normalized()
	var side := up.cross(ref).normalized()
	var h := d - up * d.dot(up)
	return Vector2(atan2(h.dot(side), h.dot(ref)), clampf(asin(clampf(d.dot(up), -1.0, 1.0)), 0.25, 1.35))


## The camera yaw that puts it on the downrange side of the craft.
func _downrange_yaw() -> float:
	var up := run.sim.up()
	var ref := (cam.reference - up * cam.reference.dot(up)).normalized()
	var side := up.cross(ref).normalized()
	var d := EAST - up * EAST.dot(up)
	return atan2(d.dot(side), d.dot(ref))


func _crash_focus() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for d: Dictionary in _debris:
		if is_instance_valid(d["node"]):
			c += (d["node"] as Node3D).global_position
			n += 1
	return c / maxf(n, 1)


func _update_effects(delta: float) -> void:
	var w := float(current_warp()) * debug_warp * _time_scale
	var dt := 0.0 if paused or ended else delta * w
	if run.sim.on_rails and warp >= RAILS_MIN:
		smoke.update(dt, origin[0], origin[1], origin[2], run.sim.up())
		return
	_update_debris(dt)
	_emit_smoke(dt)
	smoke.update(dt, origin[0], origin[1], origin[2], run.sim.up())


## Exhaust smoke in puffs along the path: thick and white low down, thin in high air, none in
## vacuum; and the ground cloud rolling off the pad at liftoff.
func _emit_smoke(dt: float) -> void:
	var s := run.sim
	if s.crashed or s.thrust_n <= 0.0 or dt <= 0.0:
		return
	var air := s.pressure
	var vel := s.velocity_v3()
	var speed := vel.length()
	var b := model.global_basis
	if air > 0.004:
		_smoke_dist += speed * dt + 6.0 * dt
		var emitted := false
		for nz: Dictionary in model.burning_nozzles():
			var r := float(nz["r"])
			var solid: bool = nz["solid"]
			var spacing := maxf(r * 1.4, speed * 0.045)
			# puffs keep the rocket's girth (a fast climb spaces them out instead of blowing them up)
			var size0 := maxf(r * (3.2 if solid else 2.4), minf(spacing, r * 3.0) * 1.7) * (1.0 + (1.0 - air) * 0.8)
			var n := mini(int(_smoke_dist / spacing), 5)
			if n <= 0:
				continue
			emitted = true
			var p := model.global_transform * (nz["pos"] as Vector3)
			var down := -(b * Vector3.UP)
			var vdir := vel / maxf(speed, 1.0)
			for i in n:
				var back := float(i) / float(n) * speed * dt + r * 2.0
				var q := p - vdir * back + down * r * 2.5
				var pos := PackedFloat64Array([origin[0] + q.x, origin[1] + q.y, origin[2] + q.z])
				var jitter := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * r * 3.0
				var life := lerpf(6.0, 16.0, air) * (1.3 if solid else 1.0)
				var alpha := clampf(air * 3.0, 0.15, 0.95) * (0.95 if solid else 0.7)
				smoke.emit(pos, vel * 0.1 + down * randf_range(15.0, 40.0) + jitter, life, size0,
					size0 * lerpf(2.6, 6.0, air), alpha, 0.55 if solid else 0.12, 1.2)
		if emitted:
			_smoke_dist = 0.0
	var h := s.altitude() - s.pad_alt
	if h < 150.0 and soi == sys.earth:
		_ground_cloud += dt * 30.0 * (1.0 - h / 150.0)
		var padp := _pad_pci(Vector3.ZERO, 1.0)
		var k := clampf(s.craft.radius / 3.0, 0.6, 3.0)
		while _ground_cloud > 1.0:
			_ground_cloud -= 1.0
			var a := randf() * TAU
			var horiz := Vector3(cos(a), 0, sin(a))
			smoke.emit(padp, horiz * randf_range(14.0, 34.0) * k + Vector3.UP * randf_range(1.0, 6.0), randf_range(8.0, 13.0),
				randf_range(8.0, 12.0) * k, randf_range(34.0, 55.0) * k, 0.9, 0.05, 0.3)


# ------------------------------------------------------------ telemetry
func _elements() -> Dictionary:
	return run.sim.elements()


func _telemetry() -> Dictionary:
	var s := run.sim
	var el := _elements()
	var now := Time.get_ticks_msec()
	if _dv_cache.is_empty() or now - _dv_time > 1000:
		_dv_time = now
		_dv_cache = s.craft.remaining_dv(s.pressure)
	var dv_stage := 0.0
	var dv_total := 0.0
	for i in _dv_cache.size():
		var r: Dictionary = _dv_cache[i]
		if i == 0:
			dv_stage = r["dv"]
		dv_total += float(r["dv"])
	var up := s.up()
	var node := plan.first()
	var node_info := {}
	if node != null and node.valid:
		var rem := node.remaining_world()
		var bt := node_burn_time(node)
		node_info = {"dv": rem.length() if node.locked else node.dv_total(), "dir": rem.normalized(),
			"t_node": node.time - time, "burn": bt, "t_burn": node.time - bt * 0.5 - time, "exec": executor != null}
	return {"alt": s.altitude(), "vs": s.vertical_speed(), "hs": s.horizontal_speed(), "speed": s.speed(),
		"soi": soi, "soi_name": sys.display_name(soi), "node": node_info,
		"ap": el["ap_alt"], "pe": el["pe_alt"], "e": el["e"], "t_ap": s.time_to_apoapsis(),
		"g": s.g_load, "q": s.q_dyn, "max_q": s.stats["max_q"], "maxq_passed": s.max_q > 4000.0 and s.q_dyn < s.max_q * 0.97,
		"throttle": s.craft.throttle, "thrust": s.thrust_n, "mass": s.craft.mass(),
		"dv_stage": dv_stage, "dv_total": dv_total, "dv_rows": _dv_cache,
		"met": mission_time(), "launched": launched, "warp": current_warp(), "warp_set": warp, "rails": s.on_rails,
		"sas": s.craft.sas, "auto": autopilot_on(), "q_body": s.q, "up": up, "east": _pole.cross(up).normalized(),
		"vel": s.velocity_v3(), "nose": s.nose(), "stage": s.craft.current_stage, "stages": s.craft.stage_count,
		"vessel": s.craft, "mach": s.mach, "aoa": s.aoa, "orbit": in_orbit()}


# ------------------------------------------------------------ maneuver nodes
func _update_warp_to(delta: float) -> void:
	if _warp_to < 0.0:
		return
	var left := _warp_to - time
	if left <= 0.05:
		_warp_to = -1.0
		warp = 1
		return
	var cap: int = WARPS[-1] if rails_allowed() else PHYS_MAX
	var best := 1
	for w in WARPS:
		if int(w) <= cap and float(w) * delta * 4.0 < left:
			best = int(w)
	warp = best


func _update_nodes() -> void:
	var n := plan.first()
	if n == null or not n.valid:
		return
	var s := run.sim
	# thrust near the node counts as burned Δv
	if s.thrust_n > 0.0 and executor == null:
		var window := maxf(node_burn_time(n), 10.0) * 1.5 + 30.0
		if time >= n.time - window:
			n.locked = true
			n.burned += s.accel * get_process_delta_time() * float(current_warp())
	if executor != null:
		if executor.state == FlightNodeExecutor.DONE:
			_finish_node(true)
		elif executor.state == FlightNodeExecutor.ABORT:
			set_executor(false)
			hud.toast(tr("FL_EXEC_NO_FUEL"), MarginPalette.WARNING)
		return
	if not n.locked:
		return
	var rem := n.remaining_world()
	var full := Vector3(n.dv_world[0], n.dv_world[1], n.dv_world[2])
	if s.thrust_n <= 0.0 and (rem.length() < 0.2 or rem.dot(full) < 0.0):
		_finish_node(false)


func _finish_node(from_executor: bool) -> void:
	var n := plan.first()
	if n != null:
		plan.remove(n)
	if from_executor:
		executor = null
		run.guide = null
		run.sim.craft.throttle = 0.0
		run.sim.craft.sas = FlightCraft.Sas.HOLD
		run.sim.command = run.sim.nose()
	hud.toast(tr("FL_NODE_DONE"), MarginPalette.SUCCESS)
	_traj_dirty = true


func _update_trajectory(delta: float) -> void:
	var s := run.sim
	if s.landed or s.clamped or s.crashed:
		if traj != null:
			traj = null
			if map_view:
				map.trajectory_changed()
		return
	_traj_timer -= delta
	var need: bool = _traj_dirty or traj == null or plan.version != _traj_version or time > traj.valid_until
	if not need and not s.on_rails and _traj_timer <= 0.0:
		need = true
	if need:
		_predict(0.4 if plan_dragging else 1.0)
		var thrusting := s.thrust_n > 0.0 or s.q_dyn > 1.0
		_traj_timer = (0.2 if map_view else 1.0) if thrusting else (2.0 if map_view else 8.0)


func _predict(quality: float) -> void:
	var s := run.sim
	traj = FlightTrajectory.predict(sys, soi, s.pos(), s.vel(), time, plan.nodes, target_body, quality)
	_traj_dirty = false
	_traj_version = plan.version
	if map_view:
		map.trajectory_changed()


func _update_sky_bodies(cam_earth: PackedFloat64Array) -> void:
	var sun_p := sys.pos_rel(sys.sun, sys.earth, time)
	var sd := Vector3(sun_p[0] - cam_earth[0], sun_p[1] - cam_earth[1], sun_p[2] - cam_earth[2]).normalized()
	if cinematic_sun and soi == sys.earth:
		sd = cinematic_sun_dir.normalized()
	var sm := smoke.material_override as ShaderMaterial
	if sm:
		sm.set_shader_parameter("sun_dir", sd)
	var mp := sys.pos_rel(sys.moon, sys.earth, time)
	var md := Vector3(mp[0] - cam_earth[0], mp[1] - cam_earth[1], mp[2] - cam_earth[2])
	var dist := md.length()
	var mag := clampf(1.0 + 2.5 * (dist - 3.0e7) / 3.5e8, 1.0, 3.5)
	var ang := asin(clampf(sys.radius[sys.moon] / maxf(dist, sys.radius[sys.moon] * 1.0001), 0.0, 1.0)) * mag
	sky.set_bodies(sd, md / dist, minf(ang, 1.5))


## Camera height above the ground near the pad (tests: must stay positive).
func camera_clearance() -> float:
	var p := cam.camera.global_position
	var x: float = origin[0] + p.x
	var y: float = origin[1] + p.y
	var z: float = origin[2] + p.z
	var r := sqrt(x * x + y * y + z * z)
	return r - sys.radius[soi]
