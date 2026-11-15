class_name TycoonModes
extends CanvasLayer
## The hangar and the flight inside the main mode (scenes/tycoon/integrated/tycoon_modes.tscn,
## the "Modes" node of tycoon_main.tscn). While a mode is open the campus is hidden and asleep,
## the HUD layer is hidden (the screen that opened the mode stays underneath, so ProjectFlow
## keeps the clock still), the clock is held (when nothing else holds it) and TycoonState lives
## on: no scene change, no save round trip. The hangar (scenes/hangar.tscn) and the flight
## (scenes/flight/flight.tscn) run in their own 3D world inside %Port (a SubViewport), in their
## "embedded" mode: they report through signals instead of changing scenes.
##
## Flows (TycoonModes picks the mission, HangarRocket turns things into tycoon numbers):
##   open_designer_hangar  the rocket designer's "Montar no hangar": the vessel the player
##                         accepts ("Usar na missão" on the hangar HUD's goal card) goes back to the designer's bench
##   open_project_hangar   the campus workshop / the dev menu: for the project waiting in its
##                         Design Review (the designer opens in "change" mode), for a project in
##                         development (its rocket is swapped, ProjectDesk.swap_rocket), else a
##                         free workshop (no mission)
##   open_project_flight   the launch choice's "Pilotar o lançamento": the mission vessel flies,
##                         its report becomes the launch outcome (HangarRocket.flight_verdict)
## The hangar's own Launch is a test flight: the flight opens in place of the hangar and
## "Revert to hangar" brings it back. Esc always goes back: the hangar's Esc / Menu leave it,
## the flight's Esc pauses and its pause menu leads out. FlightSession is saved on entry and
## given back on exit (the free workshop of the main menu keeps its own vessel);
## FlightSession.mission holds the mission while the hangar is open and is cleared on exit.
##
## The live launch (one continuous flight, CareerFlight):
##   start_launch        LaunchSequence at T-0: the project's real rocket (its hangar vessel, or
##                       one LaunchVessels builds from the design) lifts off from the campus pad;
##                       the run flies the outcome the career gave and is kept in `launch_run`
##   open_launch_flight  the handoff: the same run in the 3D flight, the live campus lent as the
##                       island under the pad (given back when the flight closes); "Voltar ao
##                       campus" closes the view and the run goes on with the calendar
##                       (_tick_launch), on the Solar System map, until it rides its track
## Missions in space (SpaceTracking, src/tycoon/tracking/), the same flight scene in its
## spectator / map-only modes with an overlay scene of ours on its HUD:
##   open_watch      the review's "Acompanhar o lançamento": the live run if it still flies, else
##                   that launch again from the pad as it went (LaunchWatch, a replay)
##   open_space_map  the campus' "Mapa do Sistema Solar" (M): the flight's map alone with every
##                   tracked mission (SpaceMapOverlay, space_map_overlay.tscn); the clock keeps
##                   running (a screen that opens meanwhile closes the map so it is seen)
##   open_follow     the map's "Acompanhar": the live run while it flies, else that craft up
##                   close where its track has it now; leaving it goes back to the map
##
## Rovers on a planet surface (src/rover/): open_surface runs scenes/surface/rover_drive.tscn in its
## embedded mode for a SurfaceSession (a mission's "Controlar o rover", the workshop's test drive);
## its "Voltar à Terra" closes the mode and hands the session's result to the caller.

signal opened(kind: String)
signal closed(kind: String)

const HANGAR_SCENE := "res://scenes/hangar.tscn"
const FLIGHT_SCENE := "res://scenes/flight/flight.tscn"
const WATCH_OVERLAY := "res://scenes/tycoon/tracking/launch_watch_overlay.tscn"
const MAP_OVERLAY := "res://scenes/tycoon/tracking/space_map_overlay.tscn"
const SURFACE_SCENE := "res://scenes/surface/rover_drive.tscn"
## the example rocket a design without a hangar vessel flies as (up to low orbit / beyond)
const WATCH_SMALL := "res://scenes/examples/andorinha.tscn"
const WATCH_BIG := "res://scenes/examples/garca.tscn"
const SMALL_TARGETS: Array[String] = ["suborbital", "leo", "sso"]
const STATE_COLORS := {"green": CwPalette.AURORA_TEAL, "yellow": CwPalette.WARNING, "red": CwPalette.DANGER}

var main: TycoonMain
## "" (closed), "hangar", "flight", "map" (the solar-system map) or "surface" (a rover drive)
var kind := ""
## the overlay scene of ours on the flight's HUD (LaunchWatch / SpaceMapOverlay), or null
var overlay: Node = null
## the hangar or the flight on show (in %Port)
var mode_node: Node = null
## the flight on show is the hangar's test flight (it goes back to the hangar)
var test_flight := false
var _ctx: Dictionary = {}
var _held_speed := 0
var _session: Dictionary = {}
var _card_dirty := true
var _card_timer := 0.0
var _hidden: Array[Node] = []
var _closed_frame := -1
## the career launch flying now (CareerFlight): kept while the player is elsewhere
var launch_run: CareerFlight = null
## > 0 while something else advances the live launch (the campus cinematic before the handoff)
var launch_hold := 0
## the campus lent to the flight as its island (given back when the flight closes)
var _lent_campus: Node3D = null
var _lent_index := 0

@onready var view: SubViewportContainer = %View
@onready var port: SubViewport = %Port
@onready var card: Control = %Card


func _ready() -> void:
	visible = false
	card.visible = false
	%Use.pressed.connect(accept_vessel)
	%Back.pressed.connect(close_mode)


func bind(m: TycoonMain) -> void:
	main = m
	# the map lets the clock run: a screen that opens meanwhile (a decision) closes it
	if main.hud:
		main.hud.screen_opened.connect(func(_n: String) -> void:
			if kind == "map":
				close_mode())


func is_open() -> bool:
	return kind != ""


## Closed during this frame: the key that closed it (Esc) must not reach the campus too.
func just_closed() -> bool:
	return _closed_frame == Engine.get_process_frames()


# ------------------------------------------------------------ flows
## The rocket designer's "Montar no hangar": a hangar for the designer's mission; the vessel the
## player uses comes back to `screen.use_hangar(def)`.
func open_designer_hangar(screen: Node) -> bool:
	var s := main.state
	var type_id := String(screen.get("type_id"))
	var target_id := String(screen.get("target_id"))
	var code := ""
	var budget := 0.0
	if String(screen.get("mode")) == "change":
		var p := ProjectDesk.find(s, String(screen.get("project_id")))
		if p == null:
			return false
		code = p.code
		budget = HangarRocket.budget_for(s, type_id, target_id, p.payload, float(p.briefing_terms.get("budget", 0.0)),
			p.cost_spent)
	else:
		code = ProjectDesk.next_code(s, type_id)
		var bt := BriefingDesk.briefing(String(screen.get("briefing_id")))
		budget = HangarRocket.budget_for(s, type_id, target_id, screen.get("payload"), float(bt.get("budget", 0.0)))
	var parts: Dictionary = screen.get("parts")
	return open_hangar({"mission": HangarRocket.mission_for(s, type_id, target_id, budget, code),
		"vessel": HangarRocket.scene_for(s, parts),
		"name": String(screen.get_node("%FamilyName").text) if screen.has_node("%FamilyName") else "",
		"on_accept": func(d: Dictionary) -> void: screen.call("use_hangar", d)})


## The campus workshop (and the dev menu): the hangar for the project that needs a rocket now.
## `project_id` "" picks it: the one waiting in its Design Review, else the first in development.
func open_project_hangar(project_id := "") -> bool:
	var s := main.state
	var p := ProjectDesk.find(s, project_id) if project_id != "" else _workshop_project()
	if p == null:
		return open_hangar({})
	if p.review_state == "waiting":
		# the Design Review's "change rocket": the designer holds the bench, the hangar opens on it
		if not main.hud.open_screen("rocket_designer", {"project_id": p.id}):
			return false
		var scr := main.hud.get_node("%Screens").get_child(main.hud.get_node("%Screens").get_child_count() - 1)
		return open_designer_hangar(scr)
	if p.review_state != "":
		return open_hangar({})
	var budget := HangarRocket.budget_for(s, p.type_id, p.target_id, p.payload, float(p.briefing_terms.get("budget", 0.0)),
		p.cost_spent)
	var pid := p.id
	return open_hangar({"mission": HangarRocket.mission_for(s, p.type_id, p.target_id, budget, p.code),
		"vessel": HangarRocket.scene_for(s, p.rocket.get("parts", {})),
		"name": String(RocketFamilies.find(s, String(p.rocket.get("family", ""))).get("name", "")),
		"on_accept": func(d: Dictionary) -> void:
			var parts := HangarRocket.adopt(s, d)
			if not ProjectDesk.swap_rocket(s, pid, {"parts": parts, "name": String(d.get("name", ""))}):
				main.hud.flash_hint(tr("TY_PJ_ERR_ROCKET"))})


func _workshop_project() -> MissionProject:
	var waiting := ProjectDesk.waiting_review(main.state)
	if not waiting.is_empty():
		return waiting[0]
	for p: MissionProject in main.state.mission_projects:
		if p.review_state == "":
			return p
	return null


## The launch choice's "Pilotar o lançamento": the project's hangar rocket flies; `on_done`
## gets HangarRocket.flight_verdict() of the flight, `on_cancel` runs when the player leaves
## before liftoff.
func open_project_flight(project_id: String, on_done: Callable, on_cancel := Callable()) -> bool:
	var s := main.state
	var p := ProjectDesk.find(s, project_id)
	if p == null:
		return false
	var ps := HangarRocket.scene_for(s, p.rocket.get("parts", {}))
	if ps == null:
		return false
	var d := HangarRocket.definition_of(s, p.rocket.get("parts", {}))
	var mission := HangarRocket.mission_for(s, p.type_id, p.target_id, 0.0, p.code)
	mission["goal"] = HangarRocket.goal_text(mission)
	var fam := RocketFamilies.find(s, String(p.rocket.get("family", "")))
	return open_flight({"vessel": ps, "name": String(fam.get("name", "")), "mission": mission, "mission_flight": true,
		"dv": float(d.get("dv", 0.0)) * 1000.0,
		"on_done": func(report: Dictionary) -> void: on_done.call(HangarRocket.flight_verdict(report, mission)),
		"on_cancel": on_cancel})


# ------------------------------------------------------------ missions in space
## The rocket a launch flies as: LaunchVessels.scene_for (the project's hangar vessel, else the
## one built from the design with hangar parts: stages, tanks, boosters, fairing and the
## mission's rover), the very scene the launch cutscene shows; else an example rocket.
static func watch_vessel(s: TycoonState, parts: Dictionary, target: String, payload: Array = []) -> PackedScene:
	var ps: PackedScene = LaunchVessels.scene_for(parts, target, payload, s) if not parts.is_empty() else null
	if ps == null:
		ps = load(WATCH_SMALL if target in SMALL_TARGETS else WATCH_BIG)
	return ps


static func _vessel_name(s: TycoonState, rocket: Dictionary) -> String:
	var fam := RocketFamilies.find(s, String(rocket.get("family", "")))
	return String(fam.get("name", rocket.get("name", "")))


## The mission payload (kg) a track's launch carries.
static func _payload_of(s: TycoonState, tr: Dictionary) -> float:
	var m := HangarRocket.mission_for(s, String(tr.get("type", "")), String(tr.get("target", "leo")), 0.0, "")
	return float(m.get("payload_kg", 0.0))


## A career launch lifts off (LaunchSequence at T-0): its flight starts now and goes on, watched
## or not (the campus advances it with the calendar). Returns the run.
func start_launch(result: Dictionary) -> CareerFlight:
	if main == null:
		return null
	var s := main.state
	SpaceTracking.sync(s)
	var pid := String(result.get("project_id", ""))
	var tr := SpaceTracking.for_project(s, pid)
	if tr.is_empty():
		tr = SpaceTracking.add_player(s, result, s.weeks)
	if launch_run and launch_run.track_id == String(tr["id"]):
		return launch_run
	# the track starts at this very moment of the calendar (the launch screen holds the clock),
	# so the flight's clock is the campus clock
	SpaceTracking.retime(tr, SpaceTracking.now(s, main.clock.week_fraction()))
	var rocket: Dictionary = result.get("rocket", {})
	var target := String(tr.get("target", "leo"))
	launch_run = CareerFlight.for_track(s, tr, watch_vessel(s, rocket.get("parts", {}), target,
		LaunchSequence.payload_of(s, result)), _payload_of(s, tr),
		_vessel_name(s, rocket), String(result.get("cause_key", "")))
	launch_run.mission = {"code": String(result.get("code", "")), "pad": String(result.get("pad", "pad"))}
	return launch_run


## The live launch in the 3D view (LaunchSequence's handoff, or "Acompanhar" while it flies).
## `cam_offset`: where the campus camera was, from the rocket (campus axes, campus units), so
## the view starts on the same shot. Closing it lets the flight go on in the background.
func open_launch_flight(cam_offset := Vector3.ZERO, on_close := Callable(), back_to_map := false, cam_fov := 55.0) -> bool:
	if is_open() or main == null or launch_run == null:
		return false
	var tr := launch_run.track()
	var entry := ProjectDesk.history_entry(main.state, String(tr.get("project_id", "")))
	return open_flight({"run": launch_run, "vessel": launch_run.vessel_scene, "name": launch_run.vessel_name,
		"spectator": true, "pad": String(launch_run.mission.get("pad", "pad")), "cam_offset": cam_offset, "cam_fov": cam_fov,
		"overlay": WATCH_OVERLAY, "overlay_args": {"mode": "live", "track": tr, "entry": entry, "run": launch_run,
			"back_to_map": back_to_map},
		"on_close": on_close})


## "Acompanhar o lançamento" (the review of a launched project): the live flight if it is the one
## still flying, else its launch again from the pad as it went (the track is not touched).
func open_watch(project_id: String) -> bool:
	if is_open() or main == null:
		return false
	SpaceTracking.sync(main.state)
	if ProjectDesk.history_entry(main.state, project_id).is_empty():
		return false
	return open_watch_track("p:" + project_id)


## The launch watch of any track (a project's, or one with no project behind it: the dev menu's).
func open_watch_track(track_id: String) -> bool:
	if is_open() or main == null:
		return false
	var s := main.state
	var tr := SpaceTracking.find(s, track_id)
	if tr.is_empty():
		return false
	if launch_run and launch_run.track_id == track_id and not launch_run.settled():
		return open_launch_flight()
	var entry := ProjectDesk.history_entry(s, String(tr.get("project_id", "")))
	var rocket: Dictionary = entry.get("rocket", {})
	var target := String(tr.get("target", "leo"))
	var run := CareerFlight.for_track(s, tr, watch_vessel(s, rocket.get("parts", {}), target,
		LaunchSequence.payload_of(s, entry)), _payload_of(s, tr),
		_vessel_name(s, rocket), String(entry.get("cause_key", "")))
	run.replay = true
	return open_flight({"run": run, "vessel": run.vessel_scene, "name": run.vessel_name, "spectator": true,
		"pad": String(entry.get("pad", "pad")), "overlay": WATCH_OVERLAY,
		"overlay_args": {"mode": "launch", "track": tr, "entry": entry, "run": run}})


## The campus' solar-system map: every tracked mission on the flight's map, the clock running.
## `focus_id` selects a track at once.
func open_space_map(focus_id := "") -> bool:
	if is_open() or main == null:
		return false
	_ctx = {"map_only": true, "overlay": MAP_OVERLAY, "overlay_args": {"focus": focus_id}}
	_enter(false)
	FlightSession.clear()
	kind = "map"
	test_flight = false
	_show_flight(false)
	opened.emit(kind)
	return true


## The map's "Acompanhar": the craft up close in the 3D flight, where its track has it now (the
## live launch itself while it still flies); leaving goes back to the map on it.
func open_follow(track_id: String) -> bool:
	if main == null:
		return false
	var s := main.state
	var tr := SpaceTracking.find(s, track_id)
	if tr.is_empty():
		return false
	var t := SpaceTracking.now(s, _map_frac())
	var live := launch_run != null and launch_run.track_id == track_id and not launch_run.sim.crashed \
		and not launch_run.settled()
	if not live and not SpaceTracking.can_follow(tr, t):
		return false
	if kind == "map":
		close_mode()
	if is_open():
		return false
	var back := func() -> void: open_space_map.call_deferred(track_id)
	if live:
		launch_run.advance_to(t, 60.0)
		launch_run.take_pending()
		launch_run.take_dropped()
		return open_launch_flight(Vector3.ZERO, back, true)
	var entry := ProjectDesk.history_entry(s, String(tr.get("project_id", "")))
	var rocket: Dictionary = entry.get("rocket", {})
	var run := CareerFlight.following(s, tr, t, watch_vessel(s, rocket.get("parts", {}), "lunar_orbit",
		LaunchSequence.payload_of(s, entry)),
		String(tr.get("code", "")))
	if run == null:
		return false
	return open_flight({"run": run, "vessel": run.vessel_scene, "name": String(tr.get("code", "")), "spectator": true,
		"overlay": WATCH_OVERLAY, "overlay_args": {"mode": "follow", "track": tr, "entry": entry, "run": run},
		"on_close": back})


## The fraction of the week the map shows (its overlay keeps it while the clock is paused).
func _map_frac() -> float:
	if overlay and overlay.has_method("week_fraction"):
		return float(overlay.call("week_fraction"))
	return main.clock.week_fraction() if main else 0.0


## The live launch flies on while the player is on the campus: it follows the calendar (a few
## milliseconds a frame) until it rides its track or ends.
func _tick_launch() -> void:
	if launch_run == null or main == null or launch_hold > 0:
		return
	if kind == "flight" and mode_node is FlightWorld and (mode_node as FlightWorld).run == launch_run:
		return
	var t := SpaceTracking.now(main.state, main.clock.week_fraction())
	if launch_run.sim.t < t and not launch_run.settled():
		launch_run.advance_to(t, 3.0)
		launch_run.take_pending()
		launch_run.take_dropped()


# ------------------------------------------------------------ open / close
## Opens the hangar. ctx: {"mission": FlightSession.mission ({} = free workshop), "vessel":
## PackedScene to start from (null = empty), "name": the family name, "on_accept":
## Callable(definition), "on_close": Callable()}.
func open_hangar(ctx: Dictionary) -> bool:
	if is_open() or main == null:
		return false
	_ctx = ctx
	_enter()
	FlightSession.clear()
	FlightSession.mission = (ctx.get("mission", {}) as Dictionary).duplicate()
	var ps: PackedScene = ctx.get("vessel")
	if ps:
		FlightSession.set_vessel(ps, String(ctx.get("name", "")), 0.0)
	kind = "hangar"
	_show_hangar()
	opened.emit(kind)
	return true


## Opens the flight. ctx: {"vessel": PackedScene, "name", "mission", "mission_flight": true for a
## piloted launch (no reverts, the end goes back to the campus), "dv": predicted ascent delta-v,
## "on_done": Callable(report), "on_cancel": Callable(), "on_close": Callable(); the missions in
## space add "spectator" (bool), "time" (the flight's start time, s), "setup" (Callable(world)
## after it is ready) and "overlay" / "overlay_args" (a scene of ours bound on its HUD)}.
func open_flight(ctx: Dictionary) -> bool:
	if is_open() or main == null or ctx.get("vessel") == null:
		return false
	_ctx = ctx
	_enter()
	FlightSession.clear()
	FlightSession.mission = (ctx.get("mission", {}) as Dictionary).duplicate()
	FlightSession.set_vessel(ctx["vessel"], String(ctx.get("name", "")), float(ctx.get("dv", 0.0)))
	kind = "flight"
	test_flight = false
	_show_flight(bool(ctx.get("mission_flight", false)))
	opened.emit(kind)
	return true


## Leaves the mode: back to the campus (or the screen that opened it) with the clock restored.
func close_mode() -> void:
	if not is_open():
		return
	var was := kind
	var on_close: Callable = _ctx.get("on_close", Callable())
	_clear_port()
	kind = ""
	test_flight = false
	_closed_frame = Engine.get_process_frames()
	_leave()
	if on_close.is_valid():
		on_close.call()
	closed.emit(was)


## "Usar na missão": the vessel on the hangar's bench becomes a definition for the mission.
func accept_vessel() -> void:
	if kind != "hangar" or mode_node == null:
		return
	var v: Vessel = mode_node.get("vessel")
	if v == null or v.root == null:
		return
	var d := HangarRocket.from_vessel(v, FlightSession.mission, String(_ctx.get("name", "")))
	var cb: Callable = _ctx.get("on_accept", Callable())
	_ctx.erase("on_close")
	close_mode()
	if cb.is_valid() and not d.is_empty():
		cb.call(d)


func _enter(hold_clock := true) -> void:
	_session = {"scene": FlightSession.vessel_scene, "name": FlightSession.vessel_name, "dv": FlightSession.predicted_dv,
		"loose": FlightSession.hangar_loose, "auto": FlightSession.auto_ascent, "mission": FlightSession.mission}
	_held_speed = main.clock.speed if hold_clock else 0
	if _held_speed > 0:
		main.clock.set_speed(0)
	_hidden.clear()
	for n in [main.campus, main.get_node_or_null("Audio"), main.get_node_or_null("DayCycle"), main.get_node_or_null("Effects")]:
		if n:
			_hidden.append(n)
			n.process_mode = Node.PROCESS_MODE_DISABLED
	main.campus.visible = false
	var ui := main.get_node_or_null("UI") as CanvasLayer
	if ui:
		ui.visible = false
	main.get_viewport().disable_3d = true
	main.camera.release()
	visible = true


func _leave() -> void:
	for n in _hidden:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT
	_hidden.clear()
	main.campus.visible = true
	var ui := main.get_node_or_null("UI") as CanvasLayer
	if ui:
		ui.visible = true
	main.get_viewport().disable_3d = false
	visible = false
	card.visible = false
	FlightSession.vessel_scene = _session.get("scene")
	FlightSession.vessel_name = String(_session.get("name", ""))
	FlightSession.predicted_dv = float(_session.get("dv", 0.0))
	FlightSession.hangar_loose = _session.get("loose", [])
	FlightSession.auto_ascent = bool(_session.get("auto", false))
	FlightSession.return_to_hangar = false
	FlightSession.mission = {}
	if _held_speed > 0 and main.clock.speed == 0:
		main.clock.set_speed(_held_speed)
	_held_speed = 0


## Lets go of the mode on show. It may be the one asking (its Esc, its button), so it only
## stops and hides now and is freed at the end of the frame.
func _clear_port() -> void:
	_return_campus()
	if mode_node and is_instance_valid(mode_node):
		mode_node.process_mode = Node.PROCESS_MODE_DISABLED
		if mode_node is Node3D:
			(mode_node as Node3D).visible = false
		for c in mode_node.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		mode_node.queue_free()
	mode_node = null
	overlay = null


## The campus lent to a flight comes home (its sky, lights and pad rocket as they were).
func _return_campus() -> void:
	if _lent_campus == null:
		return
	var c := _lent_campus
	_lent_campus = null
	if mode_node is FlightWorld and is_instance_valid(mode_node) and (mode_node as FlightWorld).island:
		var back := (mode_node as FlightWorld).island.give_back()
		if back:
			c = back
	if c.get_parent():
		c.get_parent().remove_child(c)
	main.add_child(c)
	main.move_child(c, clampi(_lent_index, 0, main.get_child_count() - 1))
	c.transform = Transform3D.IDENTITY
	FlightIsland.restore_env(c)
	c.visible = not visible


func _show_hangar() -> void:
	_clear_port()
	var h := (load(HANGAR_SCENE) as PackedScene).instantiate()
	h.set("embedded", true)
	port.add_child(h)
	mode_node = h
	h.connect("exit_requested", close_mode)
	h.connect("launch_requested", _start_test_flight)
	if h.has_signal("use_requested"):
		h.connect("use_requested", accept_vessel)
	var v: Vessel = h.get("vessel")
	if v:
		v.changed.connect(func() -> void: _card_dirty = true)
	_fill_card_static()
	# the hangar HUD's goal card shows the mission (title, Δv with the payload, budget) and its
	# Back / "Usar na missão" buttons, so this card stays hidden: one goal display. Its nodes
	# keep the same wiring (accept_vessel / close_mode) and refresh_card() still fills them.
	card.visible = false
	_card_dirty = true


func _show_flight(mission_flight: bool) -> void:
	_clear_port()
	card.visible = false
	var f := (load(FLIGHT_SCENE) as PackedScene).instantiate() as FlightWorld
	f.embedded = true
	f.mission_mode = mission_flight
	f.spectator = bool(_ctx.get("spectator", false))
	f.map_only = bool(_ctx.get("map_only", false))
	if _ctx.get("run") is FlightRun:
		f.run = _ctx["run"]
	f.pad_lot = String(_ctx.get("pad", "pad"))
	if not f.map_only and main and main.campus and main.campus.is_inside_tree():
		# the live campus is the island under the flight (given back in _clear_port)
		_lent_campus = main.campus
		_lent_index = _lent_campus.get_index()
		_lent_campus.get_parent().remove_child(_lent_campus)
		_lent_campus.visible = true
		f.lent_island = _lent_campus
	port.add_child(f)
	if (_ctx.get("cam_offset", Vector3.ZERO) as Vector3) != Vector3.ZERO:
		f.start_from_campus_camera(_ctx["cam_offset"], float(_ctx.get("cam_fov", 55.0)))
	mode_node = f
	f.exit_requested.connect(_on_flight_exit)
	var setup: Callable = _ctx.get("setup", Callable())
	if setup.is_valid():
		setup.call(f)
	if String(_ctx.get("overlay", "")) != "":
		overlay = (load(String(_ctx["overlay"])) as PackedScene).instantiate()
		f.hud.add_child(overlay)
		if overlay.has_method("bind"):
			overlay.call("bind", self, f, _ctx.get("overlay_args", {}))


## The hangar's Launch (it filled FlightSession): a test flight in place of the hangar.
func _start_test_flight() -> void:
	test_flight = true
	_show_flight(false)


func _on_flight_exit(what: String, report: Dictionary) -> void:
	match what:
		"restart":
			_show_flight(not test_flight and bool(_ctx.get("mission_flight", false)))
		"hangar":
			if test_flight and kind == "hangar":
				test_flight = false
				_show_hangar()
			else:
				_finish_flight(report)
		"done":
			if test_flight and kind == "hangar":
				test_flight = false
				_show_hangar()
			else:
				_finish_flight(report)
		"cancel":
			if test_flight and kind == "hangar":
				test_flight = false
				_show_hangar()
				return
			var cb: Callable = _ctx.get("on_cancel", Callable())
			close_mode()
			if cb.is_valid():
				cb.call()


func _finish_flight(report: Dictionary) -> void:
	var cb: Callable = _ctx.get("on_done", Callable())
	close_mode()
	if cb.is_valid():
		cb.call(report)


# ------------------------------------------------------------ the mission card
func _fill_card_static() -> void:
	var m: Dictionary = FlightSession.mission
	var free := m.is_empty()
	%Caption.text = tr("TY_HG_CARD_FREE") if free else tr("TY_HG_CARD_CAPTION")
	%Title.text = tr("TY_HG_CARD_FREE_HINT") if free else String(m.get("title", ""))
	%Target.visible = not free
	%Target.text = tr("TY_HG_CARD_TARGET") % String(m.get("target", ""))
	%Meters.visible = not free
	%Use.visible = not free
	%Verdict.get_parent().visible = not free
	%Back.text = tr("TY_HG_CARD_TO_CAMPUS") if free else tr("TY_HG_CARD_BACK")
	%PayloadValue.text = _mass_text(float(m.get("payload_kg", 0.0)))


func _process(delta: float) -> void:
	_tick_launch()
	if kind != "hangar" or not card.visible:
		return
	_card_timer -= delta
	if _card_dirty and _card_timer <= 0.0:
		_card_dirty = false
		_card_timer = 0.25
		refresh_card()


## The mission card's live numbers: delta-v with the mission payload against the need, the
## cost against the budget, the verdict ("pode chegar / não chega").
func refresh_card() -> void:
	var m: Dictionary = FlightSession.mission
	if mode_node == null or m.is_empty():
		return
	var v: Vessel = mode_node.get("vessel")
	var empty := v == null or v.root == null
	%Use.disabled = empty
	var need := float(m.get("dv_needed", 0.0))
	var dv := 0.0
	var cost := 0.0
	if not empty:
		var st := v.compute_stages()
		dv = float(VesselMath.analyze(st["stages"], float(m.get("payload_kg", 0.0)), st["fairing_kg"], 2)["ascent_dv"])
		cost = v.cost_musd() * float(HangarRocket.cfg().get("cr_per_musd", 10000.0))
	var margin := dv / maxf(need, 1.0) - 1.0
	var state := RocketDesigner.meter_state(margin, float((RocketDesigner.section("margins").get("dv", {}) as Dictionary).get("green", 0.1)))
	var bar := %DvBar as CwSegmentBar
	bar.value = clampf(dv / maxf(need * 2.0, 1.0), 0.0, 1.0)
	bar.marker = 0.5
	bar.color = STATE_COLORS[state]
	%DvValue.text = "%s / %s m/s" % [TycoonHUD.fmt_int(dv), TycoonHUD.fmt_int(need)]
	var budget := float(m.get("budget_musd", 0.0)) * float(HangarRocket.cfg().get("cr_per_musd", 10000.0))
	%CostValue.text = tr("TY_HG_CARD_COST_VALUE") % [CwScreen.short_cr(cost), CwScreen.short_cr(budget)] if budget > 0.0 \
		else tr("TY_HG_CARD_NO_BUDGET") % CwScreen.short_cr(cost)
	%CostValue.add_theme_color_override("font_color", CwPalette.DANGER if budget > 0.0 and cost > budget else CwPalette.TEXT)
	var verdict := %Verdict as Label
	if empty:
		verdict.text = tr("TY_HG_CARD_EMPTY")
		verdict.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
	else:
		verdict.text = tr("TY_RK_NOT_REACH") if state == "red" else (tr("TY_RK_REACHES_THIN") if state == "yellow" else tr("TY_RK_REACHES"))
		verdict.add_theme_color_override("font_color", STATE_COLORS[state])


static func _mass_text(kg: float) -> String:
	return ("%.2f t" if kg < 1000.0 else "%.1f t") % (kg / 1000.0)


# ------------------------------------------------------------ rovers (src/rover/)
## A rover on a planet surface for `session` (SurfaceSession, already started); "Voltar à Terra"
## closes the mode and calls on_done(result). The map, if open, closes first.
func open_surface(session: SurfaceSession, on_done := Callable()) -> bool:
	if main == null or session == null:
		return false
	if kind == "map":
		close_mode()
	if is_open():
		return false
	SurfaceSession.current = session
	_ctx = {"on_done": on_done}
	_enter()
	kind = "surface"
	test_flight = false
	_clear_port()
	card.visible = false
	var d := (load(SURFACE_SCENE) as PackedScene).instantiate()
	d.set("embedded", true)
	port.add_child(d)
	mode_node = d
	d.connect("exit_requested", _on_surface_exit)
	opened.emit(kind)
	return true


func _on_surface_exit(result: Dictionary) -> void:
	var cb: Callable = _ctx.get("on_done", Callable())
	close_mode()
	if cb.is_valid():
		cb.call(result)
