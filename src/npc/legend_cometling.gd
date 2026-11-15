@tool
class_name LegendCometling
extends Cometling
## A Lenda in Cometling form: scenes/npc/legends/<id>.tscn (data/tycoon/legends.json `scene`),
## an inherited scene of creature.tscn with the Lenda's own outfit authored in the scene as
## voxel boxes (MeshInstance3D + BoxMesh with a material_override, cw_toon_solid). The rig,
## face and animation are the Cometling's; this script only adds what every Lenda shares:
##   - the parts keep the materials authored in the scene (the Cometling puts its shared skin
##     material on every mesh in _ready; meshes with a material_override of their own keep it
##     and get no skin tints)
##   - no profession gear (helmet, hard hat, vest...) unless show_role_gear: the outfit is theirs
##   - their own idle habits (habit_names / habit_lengths, picked in the inspector) instead of
##     the young fidgets, one every habit_interval seconds while standing idle (habits on);
##     play_habit(name) starts one now
##   - a held prop that stays level in the paw, an idle posture and the dialogue portrait
##     (talk(on))
##
## Habits any Lenda can pick (HABIT_LIBRARY; a name from Cometling.ONESHOTS plays that one-shot):
##   look_prop     raises the held prop and studies it            (node "Prop" in a hand)
##   show_prop     holds the prop out to whoever watches, proud    (node "Prop")
##   fly_prop      flies the prop in a loop over the head          (node "Prop")
##   twirl_prop    spins the prop in the paw                       (node "Prop")
##   notes         holds the prop and scribbles on it, ticks       (node "Prop", e.g. a pad)
##   hat_tip       lifts the hat with the free paw, a little bow   (node "Hat" under Neck)
##   hat_fix       straightens the hat                             (node "Hat")
##   glasses_push  pushes the glasses back up                      (node "Glasses" under Neck)
##   blow_fringe   blows the fringe up                             (node "Fringe" under Neck)
##   stargaze      looks up with a paw over the eyes
##   think         paw on the chin, eyes up... an idea
##   calc          counts on the paw and writes in the air, then a tick
##   proud         paws on the hips, chest out
##   hum           sways and hums with closed eyes
##   step          one slow, careful, giant step, arms out, then a proud nod
##   dance_bit     a little dance step
##   listen        a paw at the ear, listening (radio, heartbeat)
## Node names are looked up anywhere under the Lenda (all optional): "Prop" (the paw that holds
## it is the prop paw; the other is the free paw), "Hat", "Glasses", "Fringe". Outfit nodes must
## not reuse the names of the creature's gear (Helmet, HardHat, Goggles, Scarf, Belt, Backpack,
## Vest): the Cometling shows and hides nodes with those names by role.
##
## A Lenda with habits of its own extends this script (see Halleyzinho, src/npc/legends/*.gd):
## _apply calls, in order, _pose_legend(p) every frame (posture), _pose_habit(p) while a habit
## runs (_h is the habit, _h_t its time, habit_progress() 0..1; the shared habits are posed by
## the base: call super for them), the Cometling's own _apply, then _place_props(p) (props after
## the rig is posed). Scripts may also override _ready (store rest transforms, then
## super._ready()), _tick_timers and _habit_length.
##
## Public API on top of Cometling's: talk(on), play_habit(name), current_habit(),
## habit_progress(), knows_habit(name), all_habits(); exports legend_id, show_role_gear, habits
## (on/off), habit_names, habit_lengths, habit_interval, habit_emotes, young_fidgets and the
## posture exports. _own holds the outfit meshes (they keep their material and get no tints).

const HABIT_LIBRARY := {"look_prop": 3.2, "show_prop": 2.8, "fly_prop": 4.2, "twirl_prop": 2.4, "notes": 3.6,
	"hat_tip": 2.4, "hat_fix": 1.8, "glasses_push": 2.0, "blow_fringe": 2.2, "stargaze": 4.0, "think": 3.6,
	"calc": 3.8, "proud": 3.0, "hum": 4.0, "step": 4.4, "dance_bit": 3.0, "listen": 3.2}
## the emote a shared habit pops (habit_emotes overrides it; "" for none)
const HABIT_EMOTES := {"look_prop": "idea", "show_prop": "sparkle", "fly_prop": "rocket", "notes": "check",
	"stargaze": "star", "think": "idea", "calc": "check", "proud": "star", "hum": "note", "step": "planet",
	"dance_bit": "note", "listen": "heart", "blow_fringe": "", "hat_tip": "", "hat_fix": "",
	"glasses_push": "", "twirl_prop": ""}
## the creature's profession gear (the Cometling shows one set by role)
const _GEAR := ["Rig/Hips/Neck/Helmet", "Rig/Hips/Scarf", "Rig/Hips/Neck/HardHat", "Rig/Hips/Belt",
	"Rig/Hips/Neck/Goggles", "Rig/Hips/Backpack", "Rig/Hips/Vest"]

@export_group("Lenda")
## the Lenda's id in data/tycoon/legends.json (tools and tests)
@export var legend_id := ""
## keeps the profession gear (helmet, hard hat, vest...) of the role
@export var show_role_gear := false
## its own idle habits (off: they only play when asked, play_habit)
@export var habits := true
## the habits this Lenda plays by itself (HABIT_LIBRARY names, Cometling.ONESHOTS names or
## habits its own script poses) and how long each one lasts (seconds; missing: the library's)
@export var habit_names := PackedStringArray()
@export var habit_lengths := PackedFloat32Array()
## seconds between two habits
@export var habit_interval := Vector2(4.0, 8.0)
## the emote a habit pops, {name: emote} ("" for none; else HABIT_EMOTES)
@export var habit_emotes: Dictionary = {}
## keeps the young Cometling idle fidgets too (look around, hops, yawns...)
@export var young_fidgets := false

@export_group("Posture")
## forward lean of the whole body (radians, negative leans back: chest out)
@export_range(-0.3, 0.4, 0.01) var lean := 0.0
## arm pose of the paw that holds the "Prop" while idle and walking (pitch + back, twist,
## raise + outward); zero leaves the arm free
@export var prop_hold := Vector3(-0.55, 0.0, 0.1)
## the prop keeps its authored angle to the body instead of turning with the paw
@export var prop_level := true
## the free paw (not the prop's) rests behind the back while idle
@export var free_paw_behind := false
## the eyes a little bigger (+) or smaller (-)
@export_range(-0.3, 0.3, 0.01) var eye_size := 0.0

var _h := ""
var _h_t := 0.0
var _h_len := 1.0
var _h_next := 2.5
var _h_last := ""
var _h_emoted := 0
var _talking := false
## the outfit meshes and their own materials (no skin, no tints)
var _own := {}
var _prop: Node3D
var _hat: Node3D
var _glasses: Node3D
var _fringe: Node3D
## 1 when the prop is in the left paw, -1 in the right, 0 without a prop
var _prop_side := 0
## the prop's basis in the hips' frame as authored (scale included)
var _prop_basis := Basis.IDENTITY
var _prop_spin := 0.0
var _part_rest := {}


func _ready() -> void:
	_own.clear()
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.material_override != null:
			_own[m] = m.material_override
	if not young_fidgets:
		fidgets = false
	_prop = find_child("Prop", true, false) as Node3D
	_hat = find_child("Hat", true, false) as Node3D
	_glasses = find_child("Glasses", true, false) as Node3D
	_fringe = find_child("Fringe", true, false) as Node3D
	for n: Node3D in [_prop, _hat, _glasses, _fringe]:
		if n:
			_part_rest[n] = n.transform
	if _prop:
		_prop_side = 1 if arm_l.is_ancestor_of(_prop) else (-1 if arm_r.is_ancestor_of(_prop) else 0)
		# its angle to the body as authored (the rig is still at rest here)
		_prop_basis = hips.global_basis.inverse() * _prop.global_basis
	super._ready()
	_h_next = _rng.randf_range(1.5, 3.5)
	_apply_role()


## The parts keep the materials authored in the scene (the creature's own meshes have none and
## get the shared skin).
func _keeps_material(mesh: MeshInstance3D) -> bool:
	return _own.has(mesh) or mesh.material_override != null


## The outfit is not skin: it gets no Cometling tints (each tint is a per-instance shader
## uniform, and hundreds of outfit boxes would fill the global buffer).
func _apply_colors() -> void:
	for m: MeshInstance3D in _own:
		_meshes.erase(m)
		_bulb_meshes.erase(m)
	super._apply_colors()


## No profession gear (unless show_role_gear): the outfit authored in the scene is the Lenda's.
func _apply_role() -> void:
	super._apply_role()
	if not _ready_done or show_role_gear:
		return
	for n: String in _GEAR:
		var node := get_node_or_null(n) as Node3D
		if node:
			node.visible = false


## The dialogue portrait: talks (mouth and paws) while the text types.
func talk(on: bool) -> void:
	_talking = on
	if on:
		_h = ""
		play("talk")
	elif _loop == "talk":
		play("idle")


## Every habit this Lenda can play: its own list plus the shared library.
func all_habits() -> PackedStringArray:
	var out := habit_names.duplicate()
	for k: String in HABIT_LIBRARY:
		if not k in out:
			out.append(k)
	return out


func knows_habit(habit: String) -> bool:
	return habit in habit_names or HABIT_LIBRARY.has(habit) or ONESHOTS.has(habit)


## Starts a habit now; returns false when the name is unknown. A Cometling one-shot name plays
## that one-shot.
func play_habit(habit: String) -> bool:
	if not knows_habit(habit):
		return false
	_h_last = habit
	if ONESHOTS.has(habit) and not HABIT_LIBRARY.has(habit) and not _own_habit(habit):
		_h = ""
		play(habit)
		return true
	_h = habit
	_h_t = 0.0
	_h_len = maxf(_habit_length(habit), 0.3)
	_h_emoted = 0
	_fid = ""
	return true


func current_habit() -> String:
	return _h


## 0..1 progress of the running habit.
func habit_progress() -> float:
	return clampf(_h_t / maxf(_h_len, 0.01), 0.0, 1.0)


## Seconds habit `habit` lasts (habit_lengths, then the library; scripts override for theirs).
func _habit_length(habit: String) -> float:
	var i := habit_names.find(habit)
	if i >= 0 and i < habit_lengths.size() and habit_lengths[i] > 0.0:
		return habit_lengths[i]
	return float(HABIT_LIBRARY.get(habit, 3.0))


## True for a habit the scene's own script poses (a one-shot name it reuses, for instance).
func _own_habit(_habit: String) -> bool:
	return false


func _habit_emote(habit: String) -> String:
	return String(habit_emotes.get(habit, HABIT_EMOTES.get(habit, "")))


func _tick_timers(dt: float) -> void:
	super._tick_timers(dt)
	var idle := _loop == "idle" and _shot == "" and _queue.is_empty() and _speed < 0.05
	if _h != "":
		_h_t += dt
		_fid = ""
		if _h_t >= _h_len or not idle:
			_h = ""
			_prop_spin = 0.0
	elif habits and not habit_names.is_empty() and idle and _habits_ok and not Engine.is_editor_hint():
		_h_next -= dt
		if _h_next <= 0.0:
			_h_next = _rng.randf_range(habit_interval.x, maxf(habit_interval.y, habit_interval.x))
			var pick: String = habit_names[_rng.randi() % habit_names.size()]
			if pick == _h_last and habit_names.size() > 1:
				pick = habit_names[(habit_names.find(pick) + 1) % habit_names.size()]
			play_habit(pick)


func _apply(p: Pose, dt: float) -> void:
	_pose_legend(p)
	if _h != "":
		_pose_habit(p)
	super._apply(p, dt)
	_place_props(p)


# ------------------------------------------------------------------ posture
## The arm pose (Pose arm vector) of the paw on side s (1 left, -1 right).
func _arm(p: Pose, s: int) -> Vector3:
	return p.arm_l if s > 0 else p.arm_r


func _set_arm(p: Pose, s: int, v: Vector3) -> void:
	if s > 0:
		p.arm_l = v
	else:
		p.arm_r = v


## The paw that holds the prop (left when there is none) and the free one.
func _prop_paw() -> int:
	return _prop_side if _prop_side != 0 else 1


func _free_paw() -> int:
	return -_prop_paw() if _prop_side != 0 else -1


## Posture every frame, before the habit and the rig: lean, prop paw, free paw, eyes.
func _pose_legend(p: Pose) -> void:
	var walk := clampf(_speed_s / 0.5, 0.0, 1.0)
	var shot_w := 0.0
	if _shot != "":
		shot_w = _smooth(_shot_t / 0.12) * _smooth((_shot_len - _shot_t) / 0.2)
	var calm := (1.0 - shot_w) * (1.0 if _loop in ["idle", "talk"] else 0.0)
	p.lean += lean
	p.head.x -= lean * 0.6
	p.eye_scale *= 1.0 + eye_size
	if _prop_side != 0 and prop_hold != Vector3.ZERO:
		var s := _prop_side
		var sw := sin(_phase) * 0.12 * walk
		_set_arm(p, s, _arm(p, s).lerp(prop_hold + Vector3(sw, 0, 0), calm))
	if free_paw_behind and _loop == "idle":
		var f := _free_paw()
		_set_arm(p, f, _arm(p, f).lerp(Vector3(0.62, 0.0, 0.05), calm * (1.0 - walk * 0.6)))


# ------------------------------------------------------------------ shared habits
func _emote_once(habit: String, at: float, u: float) -> void:
	if u >= at and _h_emoted == 0:
		_h_emoted = 1
		var em := _habit_emote(habit)
		if em != "":
			show_emote(em, 1.8)


## Poses the running habit _h (habit_progress() 0..1, _h_t seconds in): the shared library.
## Scripts override it for their own habits and call super for the shared ones.
func _pose_habit(p: Pose) -> void:
	var habit := _h
	var u := habit_progress()
	var t := _h_t
	var e := _bump(u)
	var hold := _smooth(u / 0.18) * (1.0 - _smooth((u - 0.8) / 0.2))
	var ps := _prop_paw()
	var fs := _free_paw()
	match habit:
		"look_prop":
			# the prop comes up in front of the face; the head bends to study it
			_set_arm(p, ps, _arm(p, ps).lerp(Vector3(-1.45, 0.0, -0.25), hold))
			p.head.x += 0.18 * hold
			p.head.y += 0.12 * ps * hold
			p.eye_squash -= 0.12 * hold
			p.eye_off = p.eye_off.lerp(Vector2(0.3 * ps, -0.6), hold)
			p.mouth = 2 if hold > 0.5 and u < 0.6 else p.mouth
			p.mouth_size = 0.6 if hold > 0.5 else p.mouth_size
			if u > 0.65:
				p.happy = hold > 0.4
			_emote_once(habit, 0.62, u)
		"show_prop":
			# held out to whoever watches, chin up, proud
			_set_arm(p, ps, _arm(p, ps).lerp(Vector3(-1.75, 0.0, 0.05), hold))
			p.lean -= 0.06 * hold
			p.head.x -= 0.08 * hold
			p.happy = hold > 0.5
			p.squash += 0.02 * e
			p.tail_wag += sin(t * 9.0) * 0.4 * hold
			_emote_once(habit, 0.3, u)
		"fly_prop":
			# a loop in the air over the head, the eyes follow it
			var a := t * 3.2
			var up := hold
			_set_arm(p, ps, _arm(p, ps).lerp(Vector3(-2.5 + sin(a) * 0.35, 0.0, 0.35 + cos(a) * 0.3), up))
			p.head.x -= 0.32 * up
			p.head.y += sin(a) * 0.18 * up * ps
			p.eye_off = p.eye_off.lerp(Vector2(sin(a) * 0.4 * ps, 0.8), up)
			p.happy = up > 0.6 and sin(a * 0.5) > 0.0
			p.mouth = 1 if up > 0.5 else p.mouth
			p.rig_y += absf(sin(a)) * 0.01 * up
			p.ear_lift += 0.15 * up
			_prop_spin = sin(a) * 0.5 * up   # banks into the loop
			_emote_once(habit, 0.35, u)
		"twirl_prop":
			_set_arm(p, ps, _arm(p, ps).lerp(Vector3(-1.1, 0.0, -0.05), hold))
			p.head.x += 0.1 * hold
			p.eye_off = p.eye_off.lerp(Vector2(0.25 * ps, -0.5), hold)
			_prop_spin = _smooth(u / 0.2) * (1.0 - _smooth((u - 0.85) / 0.15)) * t * 9.0
			p.mouth = 0
			p.happy = u > 0.85
		"notes":
			# the pad comes up; the free paw scribbles on it, then a tick
			_set_arm(p, ps, _arm(p, ps).lerp(Vector3(-1.2, 0.0, -0.3), hold))
			var sc := sin(t * 18.0) * 0.06 * hold
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-1.15 + sc, 0.0, -0.42 + sc), hold))
			p.head.x += 0.2 * hold
			p.head.y += 0.1 * ps * hold
			p.eye_off = p.eye_off.lerp(Vector2(0.2 * ps, -0.7), hold)
			p.eye_squash -= 0.08 * hold
			_emote_once(habit, 0.78, u)
		"hat_tip":
			# the free paw lifts the hat, a small bow, the hat goes back
			var tip := _smooth(u / 0.25) * (1.0 - _smooth((u - 0.7) / 0.25))
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-2.55, 0.0, 0.42), tip))
			p.head.x += 0.18 * _bump((u - 0.2) / 0.55)
			p.lean += 0.06 * _bump((u - 0.2) / 0.55)
			p.happy = tip > 0.5
		"hat_fix":
			var fx := _smooth(u / 0.25) * (1.0 - _smooth((u - 0.75) / 0.25))
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-2.45, 0.0, 0.5), fx))
			p.head.z += sin(t * 10.0) * 0.05 * fx
			p.eye_squash -= 0.1 * fx
		"glasses_push":
			var gp := _smooth(u / 0.3) * (1.0 - _smooth((u - 0.7) / 0.3))
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-2.15, 0.0, 0.62), gp))
			p.head.x += 0.06 * gp
			p.eye_squash -= 0.1 * gp
			p.mouth = 0
		"blow_fringe":
			var bl := _bump((u - 0.15) / 0.5)
			p.mouth = 2 if bl > 0.2 else p.mouth
			p.mouth_size = 0.7
			p.head.x -= 0.12 * bl
			p.eye_off = p.eye_off.lerp(Vector2(0.0, 0.9), bl)
			p.squash += 0.025 * bl
			if u > 0.7:
				p.happy = true
		"stargaze":
			var up := hold
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-2.45, 0.0, 0.3), up))
			p.head.x -= 0.45 * up
			p.head.y += sin(t * 0.9) * 0.15 * up
			p.eye_off = p.eye_off.lerp(Vector2(0.0, 1.0), up)
			p.eye_scale += 0.08 * up
			p.mouth = 2 if up > 0.5 else p.mouth
			p.mouth_size = 0.6
			_emote_once(habit, 0.5, u)
		"think":
			var th := hold
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-1.9, 0.0, -0.65), th))
			p.head.x -= 0.12 * th
			p.head.z += 0.12 * th * fs
			p.eye_off = p.eye_off.lerp(Vector2(-0.5 * fs, 0.8), th)
			p.mouth = 3 if u < 0.6 and th > 0.5 else p.mouth
			if u > 0.65:
				p.happy = true
				p.eye_scale += 0.12 * _bump((u - 0.65) / 0.35)
			_emote_once(habit, 0.66, u)
		"calc":
			# counts on the paw, then writes the answer in the air with the other one
			var cnt := _smooth(u / 0.15) * (1.0 - _smooth((u - 0.5) / 0.1))
			var wr := _smooth((u - 0.45) / 0.1) * (1.0 - _smooth((u - 0.88) / 0.12))
			_set_arm(p, ps, _arm(p, ps).lerp(Vector3(-1.2, 0.0, -0.35), maxf(cnt, wr * 0.5)))
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-1.3 + sin(t * 14.0) * 0.08 * cnt, 0.0, -0.3), cnt))
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-1.75 + sin(t * 7.0) * 0.18, 0.0, 0.1 + cos(t * 11.0) * 0.12), wr))
			p.head.x += 0.12 * cnt - 0.05 * wr
			p.eye_off = p.eye_off.lerp(Vector2(-0.3 * fs, -0.5), cnt)
			p.eye_off = p.eye_off.lerp(Vector2(0.3 * fs, 0.4), wr)
			p.eye_squash -= 0.12 * cnt
			if u > 0.88:
				p.happy = true
			_emote_once(habit, 0.86, u)
		"proud":
			var pr := hold
			p.arm_l = p.arm_l.lerp(Vector3(0.35, 0.0, 0.75), pr)
			p.arm_r = p.arm_r.lerp(Vector3(0.35, 0.0, 0.75), pr)
			p.lean -= 0.1 * pr
			p.head.x -= 0.1 * pr
			p.squash += 0.03 * pr
			p.happy = pr > 0.5
			p.tail_lift += 0.4 * pr
			_emote_once(habit, 0.4, u)
		"hum":
			var hm := hold
			var sway := sin(t * 3.4)
			p.hips_roll += sway * 0.06 * hm
			p.head.z += sway * 0.12 * hm
			p.roll += sway * 0.03 * hm
			p.eye_close = maxf(p.eye_close, 0.85 * hm)
			p.mouth = 2 if sin(t * 6.8) > 0.0 else 0
			p.mouth_size = 0.55
			p.tail_wag += sway * 0.5 * hm
			if u > 0.25 and _h_emoted == 0:
				_h_emoted = 1
				show_emote(_habit_emote(habit) if _habit_emote(habit) != "" else "note", 1.6)
			elif u > 0.65 and _h_emoted == 1:
				_h_emoted = 2
				show_emote(_habit_emote(habit) if _habit_emote(habit) != "" else "note", 1.4)
		"step":
			# one slow giant step forward, arms out for balance, then a proud nod
			var lift := _smooth((u - 0.1) / 0.3) * (1.0 - _smooth((u - 0.55) / 0.2))
			var down := _smooth((u - 0.45) / 0.15) * (1.0 - _smooth((u - 0.85) / 0.15))
			p.foot_l += Vector3(0.0, 0.07 * lift, 0.09 * maxf(lift, down))
			p.foot_pitch.x -= 0.4 * lift
			p.arm_l = p.arm_l.lerp(Vector3(-0.2, 0.0, 1.15), lift)
			p.arm_r = p.arm_r.lerp(Vector3(-0.2, 0.0, 1.15), lift)
			p.lean -= 0.06 * lift
			p.rig_z += 0.04 * down
			p.eye_off = p.eye_off.lerp(Vector2(0.2, -0.8), lift)
			p.mouth = 2 if lift > 0.5 else p.mouth
			var nod := _bump((u - 0.62) / 0.25)
			p.head.x += 0.2 * nod
			if u > 0.62:
				p.happy = true
			_emote_once(habit, 0.65, u)
		"dance_bit":
			var dn := hold
			var b := sin(t * 7.0)
			p.hips_roll += b * 0.1 * dn
			p.hips_yaw += sin(t * 3.5) * 0.25 * dn
			p.rig_y += absf(b) * 0.02 * dn
			p.arm_l = p.arm_l.lerp(Vector3(-2.6, 0.0, 0.5 + b * 0.2), dn)
			p.arm_r = p.arm_r.lerp(Vector3(-2.6, 0.0, 0.5 - b * 0.2), dn)
			p.head.z -= b * 0.12 * dn
			p.happy = dn > 0.5
			p.tail_wag += b * 0.6 * dn
			_emote_once(habit, 0.3, u)
		"listen":
			var ls := hold
			_set_arm(p, fs, _arm(p, fs).lerp(Vector3(-2.3, 0.0, 0.95), ls))
			p.head.z -= 0.18 * ls * fs
			p.head.x += 0.05 * ls
			p.eye_close = maxf(p.eye_close, 0.6 * ls if u < 0.6 else 0.0)
			p.ear_lift += 0.25 * ls
			if u > 0.6:
				p.happy = ls > 0.3
			_emote_once(habit, 0.55, u)


## After the rig is posed: the prop stays level in the paw and the hat, glasses and fringe
## follow the shared habits.
func _place_props(_p: Pose) -> void:
	if _prop and _prop_side != 0 and prop_level and is_inside_tree():
		_prop.global_basis = hips.global_basis * _prop_basis * Basis(Vector3.UP, _prop_spin)
	var u := clampf(_h_t / _h_len, 0.0, 1.0) if _h != "" else 0.0
	if _hat:
		var r: Transform3D = _part_rest[_hat]
		var off := Vector3.ZERO
		var tilt := Vector3.ZERO
		if _h == "hat_tip":
			var up := _smooth((u - 0.15) / 0.2) * (1.0 - _smooth((u - 0.68) / 0.2))
			off = Vector3(0.0, 0.07, 0.03) * up
			tilt = Vector3(-0.35 * up, 0.0, 0.12 * up * _free_paw())
		elif _h == "hat_fix":
			var fx := _bump((u - 0.15) / 0.6)
			off = Vector3(0.0, 0.012, 0.0) * fx
			tilt = Vector3(0.0, sin(_h_t * 10.0) * 0.08 * fx, sin(_h_t * 10.0) * 0.06 * fx)
		_hat.transform = Transform3D(Basis.from_euler(tilt) * r.basis, r.origin + off)
	if _glasses:
		var g: Transform3D = _part_rest[_glasses]
		var gy := 0.0
		if _h == "glasses_push":
			gy = 0.012 * _bump((u - 0.3) / 0.4)
		_glasses.transform = Transform3D(g.basis, g.origin + Vector3(0, gy, 0))
	if _fringe:
		var fr: Transform3D = _part_rest[_fringe]
		var lift := 0.0
		if _h == "blow_fringe":
			lift = _bump((u - 0.2) / 0.5) + sin(_h_t * 30.0) * 0.1 * _bump((u - 0.2) / 0.5)
		_fringe.transform = Transform3D(Basis.from_euler(Vector3(-0.6 * lift, 0, 0)) * fr.basis,
			fr.origin + Vector3(0, 0.02 * lift, 0.01 * lift))
