class_name CampusCometling
extends Node3D
## A Cometling walking around the campus (scenes/tycoon/campus_cometling.tscn; the campus
## scene holds a Crowd of instances, editable in the editor): claims a free spot (a desk in a
## building, the bench, the pad), walks there along a path from the campus' walk grid
## (src/tycoon/campus_nav.gd: around buildings, furniture, trees, lamps and props, preferring
## the roads), plays the spot's action for a while, then picks another.
##
## Two rules keep it out of things: its centre never steps into a blocked cell of the walk
## grid, and it never steps closer than two body radii to another Cometling. It sidesteps
## Cometlings coming the other way, waits for ones in its way, plans around them when the wait
## grows long, and gives up on a spot it cannot reach.

## colour variant and role shown until the crew roster assigns one
@export_range(0, 8) var variant := 0
@export_enum("ground", "pilot", "engineer", "scientist") var role: String = "ground"
@export_group("Walking")
@export var speed := 2.4
## body radius on the ground (m); two Cometlings keep twice this apart. The Creature model is
## 1 m wide at scale 1 and stands at the Creature node's scale.
@export var body_radius := 0.8
## Cometlings closer than this ahead make it steer aside (m)
@export var avoid_range := 3.2
## seconds of standing blocked before it plans a new path around the others
@export var replan_after := 0.8
## seconds of standing blocked before it gives up on the spot
@export var give_up_after := 7.0
## idle time at a spot (s)
@export var stay_time := Vector2(5.0, 12.0)
## the leader's speech bubbles pop beside the gold star (LeaderMark), not over it: the
## Emote sprite's offset in pixels (billboarded, so always to the right on screen)
@export var leader_emote_offset := Vector2(30, 6)

var campus: Node3D
var creature: Node3D
## id of the staff member this Cometling stands for ("" = nobody, hidden)
var member_id := ""
## napping members (morale below 30) sit down where they are and snore
var napping := false
## walking statistics (tests): spots reached and metres walked
var arrivals := 0
var walked := 0.0
var give_ups := 0
var replans := 0
var _path: Array[Vector3] = []
var _target := {}
var _timer := 0.0
var _zzz := 0.0
var _blocked := 0.0
var _replanned := false
var _side := 1.0
var _rng := RandomNumberGenerator.new()
var _roles := ["ground", "pilot", "engineer", "scientist"]
var _leader_key := ""
## held still by a conversation with the player (hold())
var _held := false
## spot actions that count as working (activity())
const _WORK_ACTIONS := ["work_hammer", "work_scan", "work_type", "work_wrench", "clipboard", "carry", "think", "look_up"]


func _ready() -> void:
	creature = $Creature
	CometlingLooks.apply(creature as Cometling, variant, role)


## Called by the campus when this Cometling starts walking (starts where it was placed).
func setup(c: Node3D, rng_seed: int, p_variant: int, p_role: String) -> void:
	campus = c
	_rng.seed = rng_seed
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	creature = $Creature
	variant = p_variant
	role = p_role
	if not role in _roles:
		role = "engineer" if role in ["systems", "propulsion", "tester"] else ("scientist" if role == "researcher" else "ground")
	CometlingLooks.apply(creature as Cometling, variant, role)
	_timer = _rng.randf_range(0.2, 2.0)


## The staff member shown and the antenna light in their profession colour.
func set_member(id: String, glow: Color) -> void:
	member_id = id
	(creature as Cometling).glow_color = glow


## The player's leader (TycoonLeader, m = their staff entry): own colours and hat, and the
## gold star (LeaderMark) floating over the head. {} turns a reused Cometling back to normal.
func set_leader(m: Dictionary) -> void:
	var key := "" if m.is_empty() else "%s|%s|%s|%s|%s" % [member_id, m.get("body"), m.get("spot"),
		m.get("hat"), m.get("profession")]
	if key == _leader_key:
		return
	var was := _leader_key != ""
	_leader_key = key
	var mark := get_node_or_null("LeaderMark") as Node3D
	if mark:   # the star is the leader's only (a Lenda wears its own look without it)
		mark.visible = key != "" and TycoonLeader.is_leader(m)
	var bubble := creature.get_node_or_null("Emote") as Sprite3D
	if bubble:
		bubble.offset = leader_emote_offset if key != "" else Vector2.ZERO
	if key != "":
		TycoonLeader.apply_look(creature as Cometling, m)
	elif was:
		LeaderHat.wear(creature as Cometling, "role")


## What it is up to (the speech bubbles and the dialogue read it, ChatterBook):
## {"doing": "walking" | "working" | "idle" | "napping", "place": the building kind of the spot it
## walks to or stands at ("lab", "pad"...) or the campus spot ("bench", "plaza"...), "" if none,
## "action": the spot's action}
func activity() -> Dictionary:
	var place := ""
	var key := String(_target.get("key", ""))
	if key != "":
		var lot := key.get_slice("/", 0)
		if lot == "campus":
			place = key.get_slice("/", 1).to_lower()
		elif campus and campus.get("state") != null:
			place = (campus.get("state") as TycoonState).lot_kind(lot)
	var action := String(_target.get("action", ""))
	var doing := "idle"
	if napping:
		doing = "napping"
	elif not _path.is_empty():
		doing = "walking"
	elif action in _WORK_ACTIONS:
		doing = "working"
	return {"doing": doing, "place": place, "action": action}


## Holds it where it is (on: the player talks to it) or lets it walk on.
func hold(on: bool) -> void:
	_held = on
	if on and creature:
		creature.call("set_move_velocity", Vector3.ZERO)


func is_held() -> bool:
	return _held


func set_napping(on: bool) -> void:
	if on == napping:
		return
	napping = on
	if on:
		_stop()
		creature.call("play", "sit")
		creature.call("show_emote", "zzz", 2.4)
		_zzz = 3.0
	else:
		creature.call("play", "idle")
		creature.call("play_sequence", ["surprise", "nod"])
		_timer = _rng.randf_range(1.0, 2.5)


## A new hire: appears at the campus gate (the nearest free place) and walks in.
func walk_in(from: Vector3) -> void:
	position = from
	rotation.y = PI
	_stop()
	_timer = 0.0
	place_free()
	creature.call("show_emote", "happy", 2.2)


## Moves to the nearest place where it stands in nothing and on nobody (after the campus
## changed under it, or when it appears).
func place_free() -> void:
	if campus == null:
		return
	var p: Vector2 = campus.call("free_point", Vector2(position.x, position.z), self)
	position = Vector3(p.x, position.y, p.y)


## The campus changed (a building went up): walk on along a new path to the same spot.
func replan() -> void:
	if _target.is_empty() or _path.is_empty():
		return
	_plan_to(_target["pos"])


func _process(delta: float) -> void:
	step(delta)


## One simulation step (the campus runs it every frame; tests call it directly).
func step(delta: float) -> void:
	if creature == null or campus == null:
		return
	if _held:
		creature.call("set_move_velocity", Vector3.ZERO)
		return
	if napping:
		_zzz -= delta
		if _zzz <= 0.0:
			creature.call("show_emote", "zzz", 2.4)
			_zzz = 3.0
		return
	if _path.is_empty():
		creature.call("set_move_velocity", Vector3.ZERO)
		_timer -= delta
		if _timer <= 0.0:
			_pick()
		return
	_walk(delta)


func _walk(delta: float) -> void:
	var nav: CampusNav = campus.get("nav")
	var p := Vector2(position.x, position.z)
	var w := Vector2(_path[0].x, _path[0].z)
	var to := w - p
	var d := to.length()
	if d < 0.12:
		_path.pop_front()
		if _path.is_empty():
			_arrive()
		return
	var dir := to / d
	var step_len := minf(speed * delta, d)
	var others: Array[Vector2] = campus.call("walker_positions", self)
	# steer away from Cometlings ahead, within a body or two of the walking line
	var right := Vector2(-dir.y, dir.x)
	var steer := 0.0
	for o in others:
		var rel := o - p
		var dist := rel.length()
		if dist > avoid_range or dist < 1e-4:
			continue
		var ahead := rel.dot(dir)
		if ahead <= 0.0:
			continue
		var lateral := rel.dot(right)
		if absf(lateral) < body_radius * 2.4:
			var s := -signf(lateral) if absf(lateral) > 0.15 else _side
			steer += s * (1.0 - dist / avoid_range)
	var cands: Array[Vector2] = []
	if absf(steer) > 0.01:
		cands.append((dir + right * clampf(steer, -1.5, 1.5)).normalized())
	cands.append(dir)
	var first := signf(steer) if absf(steer) > 0.01 else _side
	for a in [0.6, 1.2]:
		cands.append(dir.rotated(a * first))
		cands.append(dir.rotated(-a * first))
	for c in cands:
		var np := p + c * step_len
		if _can_stand(np, p, others, nav):
			_move(np, c, delta)
			_blocked = 0.0
			return
	creature.call("set_move_velocity", Vector3.ZERO)
	_blocked += delta
	if _blocked > replan_after and not _replanned:
		# plan around the Cometlings standing near
		_replanned = true
		replans += 1
		var near: Array = []
		for o in others:
			if o.distance_to(p) < 8.0:
				near.append(o)
		_plan_to(_target["pos"], near)
	elif _blocked > give_up_after:
		give_ups += 1
		_stop()
		_timer = _rng.randf_range(0.5, 1.5)


func _can_stand(np: Vector2, p: Vector2, others: Array[Vector2], nav: CampusNav) -> bool:
	if nav != null and not nav.is_free(np):
		return false
	var keep := body_radius * 2.0
	for o in others:
		var dn := np.distance_to(o)
		if dn < keep and dn < p.distance_to(o):
			return false
	return true


func _move(np: Vector2, dir: Vector2, delta: float) -> void:
	walked += np.distance_to(Vector2(position.x, position.z))
	position = Vector3(np.x, position.y, np.y)
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.y), 1.0 - exp(-delta * 10.0))
	creature.call("set_move_velocity", Vector3(dir.x, 0, dir.y) * speed)


func _pick() -> void:
	var t: Dictionary = campus.call("claim_spot", self, _rng)
	if t.is_empty():
		_timer = _rng.randf_range(1.0, 2.5)
		return
	_target = t
	if not _plan_to(t["pos"]):
		_stop()
		_timer = _rng.randf_range(1.0, 2.5)
		return
	creature.call("play", "idle")


## Plans a path to `pos`; false when there is none.
func _plan_to(pos: Vector3, avoid: Array = []) -> bool:
	var nav: CampusNav = campus.get("nav")
	_path.clear()
	if nav == null:
		return false
	var pts := nav.find_path(Vector2(position.x, position.z), Vector2(pos.x, pos.z), avoid, body_radius * 2.0)
	if pts.size() < 2:
		return false
	for i in range(1, pts.size()):
		_path.append(Vector3(pts[i].x, 0.0, pts[i].y))
	_blocked = 0.0
	_replanned = false
	return true


func _stop() -> void:
	_path.clear()
	_blocked = 0.0
	_replanned = false
	if creature:
		creature.call("set_move_velocity", Vector3.ZERO)
	if campus and not _target.is_empty():
		campus.call("release_spot", self)
	_target = {}


func _arrive() -> void:
	arrivals += 1
	creature.call("set_move_velocity", Vector3.ZERO)
	rotation.y = float(_target.get("yaw", rotation.y))
	creature.call("play", String(_target.get("action", "idle")))
	if _rng.randf() < 0.35:
		var em := ["wrench", "star", "note", "rocket", "heart", "exclaim"]
		creature.call("show_emote", em[_rng.randi() % em.size()], 1.8)
	_timer = _rng.randf_range(stay_time.x, stay_time.y)
