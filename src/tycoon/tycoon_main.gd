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

@export var campaign_seed := 2026
## hackathon "modo feira": 1 s per week at any speed (GDD section 17)
@export var fair_mode := false

var state: TycoonState
var clock: TycoonClock

@onready var campus: Campus = $Campus
@onready var camera: CampusCamera = $Camera
@onready var hud: TycoonHUD = $UI/HUD


func _ready() -> void:
	state = TycoonState.new_campaign(campaign_seed, _roster_staff())
	clock = TycoonClock.new(state.rules)
	clock.fair_mode = fair_mode
	campus.bind(state)
	hud.bind(state, clock)
	hud.build_requested.connect(_on_build)
	camera.tour_source = _tour_shots
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


func _unhandled_input(event: InputEvent) -> void:
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
				if hud.current_screen() != "":
					hud.close_screen()
					return
				camera.release()
				hud.close_lot()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			click(mb.position)


## A left click on the campus: a Cometling first (follow it), then a lot (show it and frame
## it), else empty ground (let go of the Cometling, close the panel).
func click(screen: Vector2) -> void:
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


func _lot_size(lot_id: String) -> Vector2:
	var n := campus.lots.get_node_or_null(lot_id)
	return n.get_meta("size", Vector2(16, 16)) if n else Vector2(16, 16)


func _on_follow_changed(who: Node3D) -> void:
	if who == null:
		hud.hide_camera_tag()
		return
	var m := campus.cometling_member(who)
	var title := String(m.get("name", tr("TY_CAM_COMETLING")))
	var role := String(who.get("role")) if who.get("role") != null else ""
	if role != "":
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
