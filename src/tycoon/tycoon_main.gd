class_name TycoonMain
extends Node3D
## Root of the Cometworks main screen (scenes/tycoon/tycoon_main.tscn): the campus, its
## camera and the HUD are authored in the scene; this script creates the campaign state and
## the clock, advances weeks, and routes input (speed keys, clicks on Cometlings and lots,
## building). The camera (src/tycoon/campus_camera.gd) does its own zoom / pan / turn.
##   Space pause · 1 / 2 / 3 speed · click a Cometling to follow it · click a lot to see it
##   (the camera frames it) · click empty ground or Esc to let go / close the panel
## The crew comes from the existing crew roster (src/crew/), so the hangar's Cometlings are
## the agency's first employees.
## The hangar and the flight open inside this scene (Modes, TycoonModes): the campus sleeps,
## the clock holds and input goes to them until they close.

@export var campaign_seed := 2026
## hackathon "modo feira": 1 s per week at any speed (GDD section 17)
@export var fair_mode := false
## TycoonSave slot to continue ("" = new campaign); set before the scene enters the tree
@export var load_slot := ""
## the player's leader from the leader creator (TycoonLeader); set before the scene enters
## the tree, used by a new campaign only
@export var leader: Dictionary = {}
## the story cutscene that opens a new campaign (Cutscenes: "opening" after the leader
## creator, "opening_short" in fair mode; "" = none); set before the scene enters the tree
@export var intro_cutscene := ""
## story cutscenes (the opening and the ending, src/cutscene/); screenshot tools turn them off
@export var cutscenes := true

var state: TycoonState
var clock: TycoonClock
## newspaper pages, finale and monthly autosave (src/tycoon/race/race_flow.gd)
var race_flow: TycoonRaceFlow

@onready var campus: Campus = $Campus
@onready var camera: CampusCamera = $Camera
@onready var hud: TycoonHUD = $UI/HUD
## the hangar and the flight inside the main mode (scenes/tycoon/integrated/tycoon_modes.tscn)
@onready var modes: TycoonModes = get_node_or_null("Modes")


func _ready() -> void:
	state = TycoonSave.load_state(load_slot) if load_slot != "" else null
	if state == null:
		state = TycoonState.new_campaign(campaign_seed, _roster_staff())
		if not leader.is_empty():
			TycoonLeader.found(state, leader)
	clock = TycoonClock.new(state.rules)
	clock.fair_mode = fair_mode
	campus.bind(state)
	hud.bind(state, clock)
	race_flow = TycoonRaceFlow.new(state, clock, hud)
	race_flow.before_finale = _play_ending
	hud.build_requested.connect(_on_build)
	if modes:
		modes.bind(self)
		hud.hangar_requested.connect(func(_lot: String) -> void:
			hud.close_lot()
			modes.open_project_hangar())
	var flow := ProjectFlow.new()  # mission projects: phase and review screens (E1)
	add_child(flow)
	flow.bind(state, clock, hud)
	camera.tour_source = _tour_shots
	# no camera input under a screen or while the hangar / the flight is open
	camera.input_gate = func() -> bool: return hud.current_screen() == "" and not (modes and modes.is_open())
	camera.follow_changed.connect(_on_follow_changed)
	camera.tour_changed.connect(func(on: bool) -> void:
		if on:
			hud.show_camera_tag(tr("TY_CAM_TOUR"), tr("TY_CAM_TOUR_TITLE"), tr("TY_CAM_TOUR_HINT"))
		else:
			hud.hide_camera_tag())
	state.changed.connect(_update_obstacles)
	_update_obstacles()
	state.building_finished.connect(func(lot_id: String, _lv: int) -> void:
		hud.flash_hint(tr("TY_BUILT_HINT") % tr(String(state.building_type(state.lot_kind(lot_id)).get("name_key", "")))))
	if cutscenes and intro_cutscene != "" and load_slot == "":
		_play_intro.call_deferred()


func _play_intro() -> void:
	Cutscenes.play(self, intro_cutscene, state)


## The comet passed: the ending cutscene plays before the finale screen (`done` opens it).
func _play_ending(done: Callable) -> bool:
	if not cutscenes:
		return false
	var c := Cutscenes.play(self, Cutscenes.ending_for(state), state)
	if c == null:
		return false
	c.finished.connect(func(_skipped: bool) -> void: done.call(), CONNECT_ONE_SHOT)
	return true


## The agency's first employees: the crew roster (pilots, engineers, scientists).
static func _roster_staff() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var roster := CrewRoster.shared()
	for m in roster.members:
		out.append({"id": m.id, "name": m.display_name, "role": m.role, "variant": m.variant,
			"level": int(m.experience / 100.0) + 1, "xp": m.experience, "skill": m.skill,
			"curiosity": m.curiosity, "courage": m.courage})
	return out


func _process(delta: float) -> void:
	for i in clock.tick(delta):
		state.advance_week()
		if clock.speed == 0:  # a decision paused the game mid-tick
			break


func _unhandled_input(event: InputEvent) -> void:
	if modes and (modes.is_open() or modes.just_closed()):
		return  # the hangar / the flight handle their own keys (Esc leaves them)
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				clock.toggle_pause()
			KEY_1:
				clock.set_speed(1)
			KEY_2:
				clock.set_speed(2)
			KEY_3:
				clock.set_speed(3)
			KEY_ESCAPE:
				# Esc steps back one layer: the open screen's page (a Cometling's sheet back
				# to the roster), the screen, the lot panel, the followed Cometling or the
				# tour; with nothing open it brings up the pause menu
				if hud.current_screen() != "":
					hud.screen_back()
				elif hud.lot_id != "":
					hud.close_lot()
				elif camera.mode != CampusCamera.Mode.FREE:
					camera.release()
				else:
					hud.open_screen("settings")
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			click(mb.position, mb.double_click)


## A left click on the campus: a Cometling first (follow it), then a lot (show it and frame
## it), else empty ground (let go of the Cometling, close the panel; a double-click glides
## the camera there).
func click(screen: Vector2, double := false) -> void:
	var who := camera.pick(screen, campus.cometlings())
	if who:
		hud.close_lot()
		camera.follow(who)
		return
	var lot := campus.lot_at(camera, screen)
	if lot != "":
		hud.show_lot(lot)
		camera.frame_area(campus.lot_position(lot), _lot_size(lot))
	else:
		hud.close_lot()
		camera.release()
		if double:
			camera.glide_to_screen(screen)


func _lot_size(lot_id: String) -> Vector2:
	var n := campus.lots.get_node_or_null(lot_id)
	return n.get_meta("size", Vector2(16, 16)) if n else Vector2(16, 16)


func _on_follow_changed(who: Node3D) -> void:
	if who == null:
		hud.hide_camera_tag()
		return
	var m := campus.cometling_member(who)
	var title := String(m.get("name", tr("TY_CAM_COMETLING")))
	if TycoonLeader.is_leader(m):
		title = tr("TY_LEADER_TAG") % title
	var role := String(who.get("role")) if who.get("role") != null else ""
	var prof_key := String(state.profession(String(m.get("profession", ""))).get("name_key", ""))
	if prof_key != "":
		title += " · " + tr(prof_key)
	elif role != "":
		title += " · " + tr("ROLE_" + role.to_upper())
	hud.show_camera_tag(tr("TY_CAM_FOLLOWING"), title, tr("TY_CAM_FOLLOW_HINT"))


## Footprints of the lots with something on them: follow shots keep the camera out of them.
func _update_obstacles() -> void:
	var rects: Array[Rect2] = []
	for lot in campus.lots.get_children():
		var b := state.building(String(lot.name))
		if int(b.get("level", 0)) <= 0 and int(b.get("weeks_left", 0)) <= 0:
			continue
		var sz: Vector2 = lot.get_meta("size", Vector2.ZERO)
		var c := (lot as Node3D).global_position
		rects.append(Rect2(Vector2(c.x, c.z) - sz * 0.5, sz))
	camera.obstacles = rects


## Shots for the camera's idle tour: Cometlings at work (or walking), the pads, the buildings.
func _tour_shots() -> Array:
	var shots: Array = []
	for w in campus.cometlings():
		shots.append({"node": w})
	for lot in campus.lots.get_children():
		var b := state.building(String(lot.name))
		if int(b.get("level", 0)) <= 0 and int(b.get("weeks_left", 0)) <= 0:
			continue
		var sz: Vector2 = lot.get_meta("size", Vector2(16, 16))
		shots.append({"pos": (lot as Node3D).global_position, "radius": maxf(sz.x, sz.y) * 0.6})
	return shots


func _on_build(lot_id: String) -> void:
	if state.build(lot_id):
		hud.flash_hint(tr("TY_BUILD_STARTED") % tr(String(state.building_type(state.lot_kind(lot_id)).get("name_key", ""))))
		hud.show_lot(lot_id)
