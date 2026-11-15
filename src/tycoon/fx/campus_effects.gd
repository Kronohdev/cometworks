class_name CampusEffects
extends Node3D
## The campus' visual life (scenes/tycoon/fx/campus_effects.tscn, the Effects node of
## scenes/tycoon/tycoon_main.tscn). Every look lives in its own scene under scenes/tycoon/fx/;
## this script only puts them where they belong and turns them up and down. Purely visual:
## it never touches the campaign state or its random numbers.
##   Buildings     each building gets its BuildingFx (`building_fx`, one scene per kind: smoke
##                 from the factory stack, sparks, bubbling beakers, blinking screens, signal
##                 rings, a crane, the HQ flag and weather vane...). Its activity follows the
##                 staff: `busy_activity` while the agency has someone on a project, plus
##                 `per_worker` for each Cometling standing on the lot; nobody around = idle.
##                 A lot being built gets `construction_fx` (dust, sparks, a beacon), and a
##                 finished building or level pops `level_up_fx`.
##   Weather       the Weather child (CampusWeather): rain, clouds, wind, fireflies, shooting
##                 stars and the comet growing era after era. Weather vanes (group
##                 cw_wind_vane) turn with its wind.
##   Celebrations  a first in the space race taken by the agency: every Cometling cheers and
##                 jumps, and `fireworks` go up over the plaza; a mission that succeeds sets off
##                 fireworks over its pad. They wait until no screen covers the campus.
##   Cometlings    a little puff of dust (`foot_dust`) under the feet of the ones walking near
##                 the camera (not in the rain).
##   Birds         the RoofBirds children fly off when the camera comes close.

const VANE_GROUP := &"cw_wind_vane"

@export var building_fx: Dictionary[String, PackedScene] = {}
@export var construction_fx: PackedScene
@export var level_up_fx: PackedScene
@export var fireworks: PackedScene
@export var foot_dust: PackedScene
@export_group("Activity")
## activity of every building while someone works on a project (nobody on the lot)
@export_range(0.0, 1.0, 0.01) var busy_activity := 0.35
## extra activity per Cometling standing on the lot
@export_range(0.0, 1.0, 0.01) var per_worker := 0.5
## seconds between activity updates
@export var activity_interval := 0.5
@export_group("Celebrations")
## height (m) over the plaza / the pad the fireworks start from
@export var fireworks_height := 0.0
## where the big celebration's fireworks go up (campus Spots marker)
@export var celebration_spot := "Plaza"
@export_group("Cometlings")
## walking faster than this (m/s) kicks up dust
@export var dust_speed := 0.6
## no dust for Cometlings further than this from the camera (m)
@export var dust_distance := 50.0

var main: Node
var campus: Campus
var state: TycoonState
@onready var weather: CampusWeather = $Weather

var _fx := {}            # lot id -> BuildingFx
var _works := {}         # lot id -> construction BuildingFx
var _queue: Array[Dictionary] = []   # celebrations waiting for the screens to close
var _tick := 0.0
var _dust_tick := 0.0
var _last_pos := {}      # Cometling -> its position at the last dust check
var _t := 0.0


func _ready() -> void:
	main = owner if owner else get_parent()
	_bind.call_deferred()


func _bind() -> void:
	if main == null:
		return
	campus = main.get("campus") as Campus
	if weather and campus:
		weather.setup(campus, main.get_node_or_null("DayCycle"))
	bind(main.get("state") as TycoonState)


## Follows a campaign state (called once the main screen has created it).
func bind(s: TycoonState) -> void:
	if s == null or s == state:
		return
	state = s
	state.changed.connect(sync)
	state.building_finished.connect(_on_building_finished)
	state.milestone_claimed.connect(_on_milestone)
	state.mission_completed.connect(_on_mission_completed)
	if campus:
		campus.era_changed.connect(func(e: int) -> void:
			if weather:
				weather.set_era(e))
	sync()


## Puts the building effects on the buildings standing now and shows the construction sites.
func sync() -> void:
	if campus == null or state == null:
		return
	for lot in campus.lots.get_children():
		var id := String(lot.name)
		var b := campus.building_node(id)
		var fx: BuildingFx = _fx.get(id)
		if b == null:
			if fx and is_instance_valid(fx):
				fx.queue_free()
			_fx.erase(id)
		else:
			if (fx == null or not is_instance_valid(fx)) and building_fx.has(b.kind):
				fx = building_fx[b.kind].instantiate() as BuildingFx
				fx.name = "Fx"
				b.add_child(fx)
				_fx[id] = fx
			if fx:
				fx.set_look(b.era, b.level)
				fx.visible = b.level > 0
		_sync_works(id, b)
	if campus.era != (weather.era if weather else 0) and weather:
		weather.set_era(campus.era)
	_update_activity()


func _sync_works(id: String, b: CampusBuilding) -> void:
	var on := b != null and b.building
	var w: BuildingFx = _works.get(id)
	if on and (w == null or not is_instance_valid(w)) and construction_fx:
		w = construction_fx.instantiate() as BuildingFx
		w.name = "Works"
		b.add_child(w)
		_works[id] = w
		w.set_activity(1.0)
		w.snap()
	elif not on and w:
		if is_instance_valid(w):
			w.queue_free()
		_works.erase(id)


## Activity of every building from the staff: on a project and standing on the lot.
func _update_activity() -> void:
	if state == null or campus == null:
		return
	var busy := false
	for m in state.staff:
		if TycoonCrew.status(m) == "busy":
			busy = true
			break
	var walkers := campus.cometlings()
	for id: String in _fx:
		var fx: BuildingFx = _fx[id]
		if not is_instance_valid(fx):
			continue
		fx.set_activity(activity_for(id, busy, walkers))


## How busy a lot looks: `busy_activity` while the agency works on a project, plus
## `per_worker` per Cometling on the lot.
func activity_for(lot_id: String, busy: bool, walkers: Array[Node3D]) -> float:
	var lot := campus.lots.get_node_or_null(lot_id) as Node3D
	if lot == null:
		return 0.0
	var sz: Vector2 = lot.get_meta("size", Vector2(16, 12))
	var c := lot.global_position
	var n := 0
	for w in walkers:
		var p := w.global_position
		if absf(p.x - c.x) <= sz.x * 0.5 and absf(p.z - c.z) <= sz.y * 0.5:
			n += 1
	return clampf((busy_activity if busy else 0.0) + per_worker * n, 0.0, 1.0)


## The effect on a lot's building (null when the lot is empty or the kind has none).
func fx_of(lot_id: String) -> BuildingFx:
	var fx: BuildingFx = _fx.get(lot_id)
	return fx if fx and is_instance_valid(fx) else null


func works_of(lot_id: String) -> BuildingFx:
	var w: BuildingFx = _works.get(lot_id)
	return w if w and is_instance_valid(w) else null


func _process(delta: float) -> void:
	_t += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = activity_interval
		_update_activity()
	_turn_vanes(delta)
	_dust_tick -= delta
	if _dust_tick <= 0.0:
		_update_dust(0.2 - _dust_tick)
		_dust_tick = 0.2
	if not _queue.is_empty() and _screens_clear():
		var c: Dictionary = _queue.pop_front()
		_celebrate_now(c)


# ------------------------------------------------------------ celebrations
func _on_building_finished(lot_id: String, _level: int) -> void:
	pop_level_up(lot_id)


## The level-up flourish over a lot's building.
func pop_level_up(lot_id: String) -> FxOneShot:
	if level_up_fx == null or campus == null:
		return null
	var b := campus.building_node(lot_id)
	if b == null:
		return null
	var fx := level_up_fx.instantiate() as FxOneShot
	add_child(fx)
	fx.global_position = b.global_position
	fx.play()
	return fx


func _on_milestone(milestone_id: String, by: String) -> void:
	if by != RaceDirector.PLAYER or not _is_first(milestone_id):
		return
	celebrate(true)


func _is_first(milestone_id: String) -> bool:
	var race := state.race if state else null
	if race == null:
		return true
	var list: Array = race.claims.get(milestone_id, [])
	return list.size() <= 1


func _on_mission_completed(result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		return
	# a mission finished in space has no pad any more: its fireworks go up over the first pad
	var pad := String(result.get("pad", ""))
	_queue.append({"big": false, "lot": pad if pad != "" else "pad"})


## A campus celebration: `big` = every Cometling cheers and fireworks go up over the plaza;
## otherwise fireworks over `lot` (a pad). Waits until no screen covers the campus.
func celebrate(big: bool, lot := "") -> void:
	_queue.append({"big": big, "lot": lot})


func _screens_clear() -> bool:
	var hud = main.get("hud") if main else null
	if hud and hud.has_method("current_screen") and String(hud.call("current_screen")) != "":
		return false
	var modes = main.get("modes") if main else null
	if modes and modes.has_method("is_open") and bool(modes.call("is_open")):
		return false
	return true


func _celebrate_now(c: Dictionary) -> void:
	var where := Vector3.ZERO
	if bool(c.get("big", false)):
		var spot := campus.get_node_or_null("Spots/" + celebration_spot) as Node3D if campus else null
		where = spot.global_position if spot else Vector3.ZERO
		cheer_all()
	else:
		var lot := String(c.get("lot", ""))
		if campus == null or lot == "" or campus.lots.get_node_or_null(lot) == null:
			return
		where = campus.lot_position(lot)
	launch_fireworks(where)


## Every Cometling on the campus cheers and jumps.
func cheer_all() -> int:
	var n := 0
	if campus == null:
		return n
	for w in campus.cometlings():
		var cr := w.get("creature") as Cometling
		if cr:
			cr.react("success")
			n += 1
	return n


func launch_fireworks(where: Vector3) -> FxOneShot:
	if fireworks == null:
		return null
	var fw := fireworks.instantiate() as FxOneShot
	add_child(fw)
	fw.global_position = where + Vector3(0, fireworks_height, 0)
	fw.play()
	return fw


# ------------------------------------------------------------ wind and dust
func _turn_vanes(delta: float) -> void:
	if weather == null:
		return
	var w := weather.wind_dir.normalized()
	var yaw := atan2(-w.y, w.x) + sin(_t * 0.7) * 0.25 * (0.3 + weather.wind) + sin(_t * 2.3) * 0.06 * weather.wind
	for v in get_tree().get_nodes_in_group(VANE_GROUP):
		var n := v as Node3D
		if n and n.is_visible_in_tree():
			var r := n.global_rotation
			r.y = lerp_angle(r.y, yaw, clampf(delta * 2.0, 0.0, 1.0))
			n.global_rotation = r


func _update_dust(dt: float) -> void:
	if campus == null or foot_dust == null:
		return
	var cam := get_viewport().get_camera_3d()
	var wet := weather != null and weather.rain_amount > 0.3
	for w in campus.cometlings():
		var d := w.get_node_or_null("FootDust") as GPUParticles3D
		if d == null:
			d = foot_dust.instantiate() as GPUParticles3D
			d.name = "FootDust"
			w.add_child(d)
		var last: Vector3 = _last_pos.get(w, w.global_position)
		_last_pos[w] = w.global_position
		var speed := Vector2(w.global_position.x - last.x, w.global_position.z - last.z).length() / maxf(dt, 0.001)
		var near := cam == null or cam.global_position.distance_to(w.global_position) < dust_distance
		var on := speed > dust_speed and near and not wet
		if d.emitting != on:
			d.emitting = on
