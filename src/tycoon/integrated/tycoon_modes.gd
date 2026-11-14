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
## Missions in space (SpaceTracking, src/tycoon/tracking/), the same flight scene in its
## spectator / map-only modes with an overlay scene of ours on its HUD:
##   open_watch      the review's "Acompanhar o lançamento": the project's rocket flies from the
##                   pad the outcome the simulation gave (LaunchWatch, launch_watch_overlay.tscn)
##   open_space_map  the campus' "Mapa do Sistema Solar" (M): the flight's map alone with every
##                   tracked mission (SpaceMapOverlay, space_map_overlay.tscn); the clock keeps
##                   running (a screen that opens meanwhile closes the map so it is seen)
##   open_follow     the map's "Acompanhar": that craft up close in the 3D flight, at its place
##                   and time; leaving it goes back to the map

signal opened(kind: String)
signal closed(kind: String)

const HANGAR_SCENE := "res://scenes/hangar.tscn"
const FLIGHT_SCENE := "res://scenes/flight/flight.tscn"
const WATCH_OVERLAY := "res://scenes/tycoon/tracking/launch_watch_overlay.tscn"
const MAP_OVERLAY := "res://scenes/tycoon/tracking/space_map_overlay.tscn"
## the example rocket a design without a hangar vessel flies as (up to low orbit / beyond)
const WATCH_SMALL := "res://scenes/examples/andorinha.tscn"
const WATCH_BIG := "res://scenes/examples/garca.tscn"
const SMALL_TARGETS: Array[String] = ["suborbital", "leo", "sso"]
const STATE_COLORS := {"green": CwPalette.AURORA_TEAL, "yellow": CwPalette.WARNING, "red": CwPalette.DANGER}

var main: TycoonMain
## "" (closed), "hangar", "flight" or "map" (the solar-system map)
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
## The rocket a launch flies as in the 3D flight: the hangar vessel of its design, else an example
## rocket of its size (Andorinha up to low orbit, Garça beyond).
static func watch_vessel(s: TycoonState, parts: Dictionary, target: String) -> PackedScene:
	var ps: PackedScene = HangarRocket.scene_for(s, parts) if not parts.is_empty() else null
	if ps == null:
		ps = load(WATCH_SMALL if target in SMALL_TARGETS else WATCH_BIG)
	return ps


static func _vessel_name(s: TycoonState, rocket: Dictionary) -> String:
	var fam := RocketFamilies.find(s, String(rocket.get("family", "")))
	return String(fam.get("name", rocket.get("name", "")))


## "Acompanhar o lançamento" (the review of a launched project): its rocket lifts off from the pad
## and flies the outcome the launch had (LaunchWatch drives it); the screen that asked stays
## underneath, so the review is still there when the player comes back.
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
	var entry := ProjectDesk.history_entry(s, String(tr.get("project_id", "")))
	var rocket: Dictionary = entry.get("rocket", {})
	var target := String(tr.get("target", "leo"))
	return open_flight({"vessel": watch_vessel(s, rocket.get("parts", {}), target), "name": _vessel_name(s, rocket),
		"spectator": true, "overlay": WATCH_OVERLAY,
		"overlay_args": {"mode": "launch", "track": tr, "entry": entry}})


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


## The map's "Acompanhar": the craft up close in the 3D flight, at its place now; leaving goes back
## to the map on it.
func open_follow(track_id: String) -> bool:
	if main == null:
		return false
	var s := main.state
	var tr := SpaceTracking.find(s, track_id)
	if tr.is_empty():
		return false
	var t := SpaceTracking.now(s, _map_frac())
	if not SpaceTracking.can_follow(tr, t):
		return false
	if kind == "map":
		close_mode()
	if is_open():
		return false
	var entry := ProjectDesk.history_entry(s, String(tr.get("project_id", "")))
	var rocket: Dictionary = entry.get("rocket", {})
	var st := SpaceTracking.state_at(tr, t)
	return open_flight({"vessel": watch_vessel(s, rocket.get("parts", {}), "lunar_orbit"),
		"name": String(tr.get("code", "")), "spectator": true, "time": t,
		"setup": func(f: FlightWorld) -> void: _place_follow(f, st),
		"overlay": WATCH_OVERLAY, "overlay_args": {"mode": "follow", "track": tr, "entry": entry},
		"on_close": func() -> void: open_space_map.call_deferred(track_id)})


## The fraction of the week the map shows (its overlay keeps it while the clock is paused).
func _map_frac() -> float:
	if overlay and overlay.has_method("week_fraction"):
		return float(overlay.call("week_fraction"))
	return main.clock.week_fraction() if main else 0.0


## Puts the followed craft where the track says, its spent stages gone (the spacecraft, not the
## whole rocket), engines off.
static func _place_follow(f: FlightWorld, st: Dictionary) -> void:
	var v := f.active
	for i in 8:
		if v.current_stage >= v.stage_count - 1:
			break
		for d in v.activate_next_stage():
			d.queue_free()
	v.throttle = 0.0
	f.launched = true
	f.set_orbit_state(int(st["body"]), st["pos"], st["vel"])
	v.set_sas(FlightVessel.Sas.PROGRADE)
	f.cam.set_view(2.4, 0.25, clampf(v.length * 2.5, 18.0, 120.0), true)


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
	for n in [main.campus, main.get_node_or_null("Audio"), main.get_node_or_null("DayCycle")]:
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
	if mode_node and is_instance_valid(mode_node):
		mode_node.process_mode = Node.PROCESS_MODE_DISABLED
		if mode_node is Node3D:
			(mode_node as Node3D).visible = false
		for c in mode_node.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		mode_node.queue_free()
	mode_node = null
	overlay = null


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
	if _ctx.has("time"):
		f.time = float(_ctx["time"])
	port.add_child(f)
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
