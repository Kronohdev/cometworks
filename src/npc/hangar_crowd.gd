class_name NpcCrowd
extends Node3D
## The Cometlings that live in the assembly building (scenes/npc/hangar_crowd.tscn,
## instanced by scenes/environment/vab.tscn). Owns the points of interest (Points/*,
## Marker3D with metadata "kind"), hands out tasks to the NpcWalker brains, pairs
## them up for chats, and turns vessel changes into NpcEvents (part_placed,
## part_removed, vessel_cleared, success) so the crew reacts to what the player builds.
##
## Point kinds: work (around the pad), bench, look (look up at the rocket), rest (sit),
## door (look outside), crate_pickup, crate_drop, wave (greet the camera), dance.

## Hire-roster integration: dress the NPCs as the first members of the crew roster.
@export var use_roster := true
## Vessel to watch (auto-detected: the first Vessel in the current scene).
@export var vessel_path: NodePath
## Turn the whole crowd off (no processing, hidden): for low-end machines and FPS tests.
@export var crowd_enabled := true:
	set(v):
		crowd_enabled = v
		_apply_enabled()

const ROLE_WEIGHTS := {
	"engineer": {"work_hammer": 34, "bench": 18, "carry": 14, "look": 8, "chat": 12, "rest": 4, "wander": 6, "wave": 4},
	"scientist": {"work_scan": 36, "look": 18, "chat": 14, "door": 10, "rest": 6, "wander": 10, "wave": 6},
	"pilot": {"clipboard": 30, "look": 22, "chat": 16, "wave": 10, "door": 8, "rest": 6, "wander": 8},
	"ground": {"carry": 36, "chat": 14, "rest": 12, "dance": 6, "wander": 14, "look": 10, "wave": 8},
}

var npcs: Array[NpcWalker] = []
var vessel: Node = null
var _rng := RandomNumberGenerator.new()
var _claims: Dictionary = {}     # Marker3D -> NpcWalker
var _part_count := 0
var _pending := false
var _pending_from := 0
var _rocket := Vector3(0, 8, 0)
var _rocket_height := 0.0

@onready var points: Node3D = $Points
@onready var npc_root: Node3D = $NPCs


func _ready() -> void:
	_rng.randomize()
	for n in npc_root.get_children():
		if n is NpcWalker:
			var w := n as NpcWalker
			w.crowd = self
			npcs.append(w)
	if use_roster:
		_dress_from_roster()
	_apply_enabled()
	# the vessel lives in the hangar scene that instanced us: find it once everything is ready
	_find_vessel.call_deferred()


func _apply_enabled() -> void:
	if not is_inside_tree():
		return
	visible = crowd_enabled
	process_mode = Node.PROCESS_MODE_INHERIT if crowd_enabled else Node.PROCESS_MODE_DISABLED
	for n in npcs:
		n.agent.avoidance_enabled = crowd_enabled


func _dress_from_roster() -> void:
	var roster := CrewRoster.shared()
	var members := roster.members
	for i in mini(members.size(), npcs.size()):
		var m: CrewMember = members[i]
		var w := npcs[i]
		w.role = m.role
		w.variant = m.variant
		w.display_name = m.display_name
		if w.is_node_ready():
			CometlingLooks.apply(w.creature, m.variant, m.role)


func _find_vessel() -> void:
	if vessel_path != NodePath():
		vessel = get_node_or_null(vessel_path)
	if vessel == null:
		var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
		for n in root.find_children("*", "Node3D", true, false):
			if n is Vessel:
				vessel = n
				break
	if vessel and vessel.has_signal("changed"):
		vessel.connect("changed", _on_vessel_changed)
		_part_count = _count_parts()
		_update_rocket()


func _count_parts() -> int:
	if vessel and vessel.has_method("all_parts"):
		return (vessel.call("all_parts") as Array).size()
	return 0


func _on_vessel_changed() -> void:
	# debounce: undo / load clear the vessel and rebuild it in the same frame
	if not _pending:
		_pending = true
		_pending_from = _part_count
		get_tree().create_timer(0.25).timeout.connect(_flush_vessel_change)


func _flush_vessel_change() -> void:
	_pending = false
	var now := _count_parts()
	_part_count = now
	_update_rocket()
	var pos := _rocket
	if now > _pending_from:
		NpcEvents.emit("success" if now - _pending_from >= 6 else "part_placed", {"position": pos, "stagger": 0.45})
	elif now < _pending_from:
		NpcEvents.emit("vessel_cleared" if now == 0 else "part_removed", {"position": pos, "stagger": 0.45})


func _update_rocket() -> void:
	_rocket_height = 0.0
	var top := 0.0
	if vessel and vessel.has_method("all_parts"):
		for p in vessel.call("all_parts"):
			var pi := p as Node3D
			if pi == null:
				continue
			var aabb: AABB = pi.get("aabb") if pi.get("aabb") != null else AABB()
			top = maxf(top, pi.global_position.y + aabb.end.y)
	_rocket_height = top
	_rocket = Vector3(0, clampf(top * 0.55, 3.0, 60.0), 0)


## Where the crew looks when it admires the rocket (world space).
func rocket_focus() -> Vector3:
	return global_transform * _rocket


func rocket_top() -> Vector3:
	return global_transform * Vector3(0, maxf(_rocket_height, 6.0), 0)


# ------------------------------------------------------------------ task selection
func pick_task(npc: NpcWalker) -> Dictionary:
	var weights: Dictionary = ROLE_WEIGHTS.get(npc.role, ROLE_WEIGHTS["ground"])
	var cam := get_viewport().get_camera_3d()
	for attempt in 6:
		var kind := _weighted(weights)
		var t := _make_task(npc, kind, cam)
		if not t.is_empty():
			return t
	return _wander(npc)


func _weighted(w: Dictionary) -> String:
	var total := 0
	for k in w:
		total += int(w[k])
	var r := _rng.randi() % maxi(total, 1)
	for k in w:
		r -= int(w[k])
		if r < 0:
			return k
	return "wander"


func _make_task(npc: NpcWalker, kind: String, cam: Camera3D) -> Dictionary:
	var rocket := rocket_focus()
	match kind:
		"work_hammer", "work_scan", "clipboard":
			var p := _claim(npc, "work")
			if p == null:
				return {}
			var base := global_transform * Vector3(0, 1.0, 0)
			var emotes := {"work_hammer": ["wrench", "sparkle", "fire", "check"],
				"work_scan": ["idea", "check", "question", "planet"],
				"clipboard": ["check", "idea", "rocket", "note"]}
			return {"type": "act", "pos": p.global_position, "face": base, "action": kind,
				"duration": _rng.randf_range(7.0, 14.0), "emotes": emotes[kind], "poi": p}
		"bench":
			var p := _claim(npc, "bench")
			if p == null:
				return {}
			var face: Vector3 = global_transform * (p.get_meta("face", p.position + Vector3(0, 1, 1)) as Vector3)
			return {"type": "act", "pos": p.global_position, "face": face, "look": face,
				"action": "work_hammer", "duration": _rng.randf_range(6.0, 11.0), "emotes": ["wrench", "sparkle", "check"], "poi": p}
		"look":
			var p := _claim(npc, "look")
			if p == null:
				return {}
			return {"type": "act", "pos": p.global_position, "face": rocket, "action": "look_up",
				"look": rocket_top(), "duration": _rng.randf_range(4.0, 8.0), "emotes": ["sparkle", "rocket", "heart", "star"], "poi": p}
		"rest":
			var p := _claim(npc, "rest")
			if p == null:
				return {}
			return {"type": "act", "pos": p.global_position, "face": rocket, "action": "sit",
				"duration": _rng.randf_range(8.0, 15.0), "emotes": ["zzz", "note", "heart"], "poi": p}
		"door":
			var p := _claim(npc, "door")
			if p == null:
				return {}
			var outside := p.global_position + Vector3(0, 6, -60)
			return {"type": "act", "pos": p.global_position, "face": outside, "action": "look_up", "look": outside,
				"look_weight": 0.6, "duration": _rng.randf_range(4.0, 7.0), "emotes": ["planet", "sparkle", "question"], "poi": p}
		"dance":
			var p := _claim(npc, "dance")
			if p == null:
				return {}
			return {"type": "act", "pos": p.global_position, "face": cam.global_position if cam else rocket, "action": "dance",
				"duration": _rng.randf_range(4.0, 7.0), "emotes": ["note", "note", "happy"], "poi": p}
		"carry":
			var a := _claim(npc, "crate_pickup")
			if a == null:
				return {}
			var b := _random_point("crate_drop")
			if b == null:
				release(npc)
				return {}
			return {"type": "carry", "pickup": a.global_position, "drop": b.global_position, "poi": a}
		"wave":
			if cam == null:
				return {}
			var p := _nearest_free(npc, "wave", cam.global_position)
			if p == null or p.global_position.distance_to(cam.global_position) > 90.0:
				return {}
			_claims[p] = npc
			return {"type": "wave", "pos": p.global_position, "poi": p}
		"chat":
			return _chat(npc)
		"wander":
			return _wander(npc)
	return {}


func _wander(npc: NpcWalker) -> Dictionary:
	var map := get_world_3d().navigation_map
	var p := npc.global_position + Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12))
	p = NavigationServer3D.map_get_closest_point(map, p)
	return {"type": "act", "pos": p, "action": "idle", "duration": _rng.randf_range(1.0, 3.0)}


func _chat(npc: NpcWalker) -> Dictionary:
	var best: NpcWalker = null
	var best_d := 1e9
	for o in npcs:
		if o == npc or not o.is_interruptible() or o.partner != null:
			continue
		var d := o.global_position.distance_to(npc.global_position)
		if d < best_d and d < 40.0:
			best = o
			best_d = d
	if best == null:
		return {}
	var mid := (npc.global_position + best.global_position) * 0.5
	var dir := (best.global_position - npc.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	var map := get_world_3d().navigation_map
	var gap := 0.62 * npc.creature.scale.x
	var pa := NavigationServer3D.map_get_closest_point(map, mid - dir * gap)
	var pb := NavigationServer3D.map_get_closest_point(map, mid + dir * gap)
	release(best)
	best.assign_task({"type": "chat", "partner": npc, "pos": pb})
	return {"type": "chat", "partner": best, "pos": pa}


func _points(kind: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for p in points.get_children():
		if p is Marker3D and String(p.get_meta("kind", "")) == kind:
			out.append(p)
	return out


func _claim(npc: NpcWalker, kind: String) -> Marker3D:
	var free: Array[Marker3D] = []
	for p in _points(kind):
		if not _claims.has(p):
			free.append(p)
	if free.is_empty():
		return null
	var p := free[_rng.randi() % free.size()]
	_claims[p] = npc
	return p


func _nearest_free(npc: NpcWalker, kind: String, to: Vector3) -> Marker3D:
	var best: Marker3D = null
	var bd := 1e9
	for p in _points(kind):
		if _claims.has(p):
			continue
		var d := p.global_position.distance_to(to)
		if d < bd:
			bd = d
			best = p
	return best


func _random_point(kind: String) -> Marker3D:
	var ps := _points(kind)
	return null if ps.is_empty() else ps[_rng.randi() % ps.size()]


func release(npc: NpcWalker) -> void:
	for k in _claims.keys():
		if _claims[k] == npc:
			_claims.erase(k)
