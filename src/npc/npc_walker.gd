@tool
class_name NpcWalker
extends Node3D
## Brain of one hangar Cometling (scenes/npc/hangar_npc.tscn): asks the crowd
## (NpcCrowd) for a task, walks there on the navigation mesh with RVO avoidance
## (NavigationAgent3D), performs the activity (Cometling actions), chats with a
## partner, carries crates, and reacts to hangar events (NpcEvents).
##
## Task dictionaries (built by NpcCrowd.pick_task):
##   {type = "act",   pos, face, action, duration, look (Vector3, optional), emotes (Array)}
##   {type = "carry", pickup, drop}
##   {type = "chat",  partner (NpcWalker), pos}
##   {type = "wave",  pos}         wave at the camera
##   {type = "wander", pos}

signal task_finished(npc: NpcWalker)

@export_enum("ground", "pilot", "engineer", "scientist") var role: String = "ground":
	set(v):
		role = v
		_preview_look()
@export_range(0, 8) var variant := 0:
	set(v):
		variant = v
		_preview_look()
@export var personality_seed := 1
## Shown nowhere yet: filled from the crew roster when NpcCrowd.use_roster is on.
@export var display_name := ""
## Walking speed in m/s (world units).
@export var walk_speed := 1.35
@export var carry_speed := 0.95

var crowd: Node = null    # NpcCrowd
var state := "think"      # think, walk, act, react, wait_partner
var task: Dictionary = {}
var partner: NpcWalker = null

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _vel := Vector3.ZERO
var _yaw_target := 0.0
var _dt := 1.0 / 60.0
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var _carrying := false
var _carry_leg := 0           # 0 going to pickup, 1 going to drop
var _emote_timer := 0.0
var _react_timer := 0.0
var _state_before_react := ""

@onready var creature: Cometling = $Creature
@onready var agent: NavigationAgent3D = $Agent


## In the editor the role / colour exports update the creature right away.
func _preview_look() -> void:
	if is_node_ready() and creature:
		CometlingLooks.apply(creature, variant, role)


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview_look()
		set_physics_process(false)
		return
	_rng.seed = personality_seed * 7919 + 13
	creature.listen_to_events = false
	creature.personality_seed = personality_seed
	CometlingLooks.apply(creature, variant, role)
	agent.velocity_computed.connect(_on_safe_velocity)
	agent.max_speed = walk_speed * 1.2
	_timer = _rng.randf_range(0.3, 2.5)
	_yaw_target = rotation.y
	NpcEvents.bus().event.connect(_on_event)


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and NpcEvents.bus().event.is_connected(_on_event):
		NpcEvents.bus().event.disconnect(_on_event)


## Gives this NPC a task right away (used by the crowd for chats and by tests).
func assign_task(t: Dictionary) -> void:
	_carrying = false
	creature.clear_look()
	creature.play("idle")
	task = t
	match String(t.get("type", "")):
		"carry":
			_carry_leg = 0
			_go(t["pickup"])
		"chat":
			partner = t.get("partner")
			_go(t["pos"])
		_:
			_go(t.get("pos", global_position))


func is_interruptible() -> bool:
	if state == "think":
		return true
	if state == "act" and String(task.get("type", "")) in ["act", "wander"] and String(task.get("action", "")) in ["idle", "sit", "look_up"]:
		return true
	return false


func _go(p: Vector3) -> void:
	state = "walk"
	agent.target_position = p
	_stuck = 0.0
	_last_pos = global_position


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	_dt = delta
	if _react_timer > 0.0:
		_react_timer -= delta
		agent.velocity = Vector3.ZERO
		if crowd:
			_face(crowd.rocket_focus(), delta, 6.0)
		if _react_timer <= 0.0:
			state = _state_before_react
		return
	match state:
		"think":
			agent.velocity = Vector3.ZERO
			_timer -= delta
			if _timer <= 0.0 and crowd:
				var t: Dictionary = crowd.pick_task(self)
				if t.is_empty():
					_timer = 1.0
				else:
					assign_task(t)
		"walk":
			_walk(delta)
		"act":
			agent.velocity = Vector3.ZERO
			_act(delta)
		"wait_partner":
			agent.velocity = Vector3.ZERO
			if partner and is_instance_valid(partner):
				_face(partner.global_position, delta, 5.0)
				if partner.state == "wait_partner" or partner.state == "act":
					_start_chat()
			_timer -= delta
			if _timer <= 0.0:
				_end_task(true)


func _walk(delta: float) -> void:
	if agent.is_navigation_finished():
		agent.velocity = Vector3.ZERO
		_arrive()
		return
	var next := agent.get_next_path_position()
	var to := next - global_position
	to.y = 0.0
	var dist_goal := global_position.distance_to(agent.target_position)
	var speed := carry_speed if _carrying else walk_speed
	speed *= clampf(dist_goal / 1.2, 0.35, 1.0)
	agent.velocity = to.normalized() * speed if to.length() > 0.01 else Vector3.ZERO
	# stuck detection: give up and think again after a few seconds without progress
	_stuck += delta
	if _stuck > 1.5:
		if global_position.distance_to(_last_pos) < 0.4:
			_end_task(true)
		_stuck = 0.0
		_last_pos = global_position


func _on_safe_velocity(v: Vector3) -> void:
	if state != "walk" or _react_timer > 0.0:
		v = Vector3.ZERO
	v.y = 0.0
	_vel = _vel.lerp(v, 1.0 - exp(-10.0 * _dt))
	var p := global_position + _vel * _dt
	p.y = 0.0
	global_position = p
	creature.set_move_velocity(_vel)
	if _vel.length() > 0.2:
		_yaw_target = atan2(_vel.x, _vel.z)
	rotation.y = lerp_angle(rotation.y, _yaw_target, 1.0 - exp(-9.0 * _dt))


func _face(p: Vector3, delta: float, rate := 6.0) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	_yaw_target = atan2(d.x, d.z)
	rotation.y = lerp_angle(rotation.y, _yaw_target, 1.0 - exp(-rate * delta))


# ------------------------------------------------------------------ tasks
func _arrive() -> void:
	var kind := String(task.get("type", "wander"))
	match kind:
		"carry":
			if _carry_leg == 0:
				_carry_leg = 1
				_carrying = true
				creature.play("nod")
				creature.play("carry")
				if _rng.randf() < 0.35:
					creature.show_emote("sweat" if _rng.randf() < 0.5 else "wrench")
				_go(task["drop"])
			else:
				_carrying = false
				creature.play("idle")
				creature.play("nod")
				if _rng.randf() < 0.5:
					creature.show_emote("check")
				state = "act"
				_timer = 1.2
				task["action"] = "idle"
		"chat":
			state = "wait_partner"
			_timer = 10.0
		"wave":
			state = "act"
			_timer = 2.4
			creature.play("wave")
			creature.show_emote("happy")
		_:
			state = "act"
			_timer = float(task.get("duration", _rng.randf_range(2.0, 5.0)))
			creature.play(String(task.get("action", "idle")))
			_emote_timer = _rng.randf_range(1.0, 3.0)


func _act(delta: float) -> void:
	_timer -= delta
	if task.has("face"):
		_face(task["face"], delta, 5.0)
	var kind := String(task.get("type", ""))
	if kind == "wave" and crowd:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_face(cam.global_position, delta, 7.0)
			creature.look_at_point(cam.global_position, 1.0)
	elif task.has("look"):
		creature.look_at_point(task["look"], float(task.get("look_weight", 1.0)))
	elif kind == "chat" and partner and is_instance_valid(partner):
		_face(partner.global_position, delta, 6.0)
		creature.look_at_point(partner.creature.global_position + Vector3(0, 1.0, 0), 0.8)
	# occasional emotes while working / chatting
	_emote_timer -= delta
	if _emote_timer <= 0.0:
		var em: Array = task.get("emotes", [])
		if not em.is_empty() and _rng.randf() < 0.7:
			creature.show_emote(String(em[_rng.randi() % em.size()]), 1.6)
		_emote_timer = _rng.randf_range(2.0, 4.5) if kind != "chat" else _rng.randf_range(1.4, 2.6)
	if _timer <= 0.0:
		if kind == "chat" and _rng.randf() < 0.4:
			creature.play(["jump", "cheer", "nod", "spin", "laugh", "clap"][_rng.randi() % 6])
		_end_task(true)


func _start_chat() -> void:
	state = "act"
	task["action"] = "talk"
	task["emotes"] = ["chat", "heart", "note", "rocket", "idea", "question", "happy", "star", "planet", "sparkle"]
	_timer = _rng.randf_range(6.0, 10.0)
	_emote_timer = _rng.randf_range(0.2, 1.2)
	creature.play("talk")


func _end_task(think: bool) -> void:
	if crowd and not task.is_empty():
		crowd.release(self)
	if partner and is_instance_valid(partner) and partner.partner == self:
		var p := partner
		partner = null
		p.partner = null
		if p.state in ["wait_partner", "act"] and String(p.task.get("type", "")) == "chat":
			p._end_task(true)
	partner = null
	_carrying = false
	creature.clear_look()
	var woke := creature.current_action() == "sleep"
	creature.play("idle")
	if woke:
		creature.play(["yawn", "stretch"][_rng.randi() % 2])
	task = {}
	state = "think"
	_timer = _rng.randf_range(0.6, 2.5) if think else 0.0
	task_finished.emit(self)


# ------------------------------------------------------------------ hangar events
func _on_event(event: String, data: Dictionary) -> void:
	if not is_inside_tree():
		return
	if data.has("position") and data.has("radius"):
		if (data["position"] as Vector3).distance_to(global_position) > float(data["radius"]):
			return
	var delay := _rng.randf_range(0.0, float(data.get("stagger", 0.35)))
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		if _react_timer <= 0.0:
			_state_before_react = state
		_react_timer = 2.2 if event in ["launch", "success"] else 1.6
		var keep_carry := _carrying
		creature.react(event)
		if keep_carry:
			creature.play("carry")
		if crowd:
			creature.look_at_point(crowd.rocket_focus(), 0.8))
