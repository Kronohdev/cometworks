@tool
class_name Halleyzinho
extends LegendCometling
## Vovô Edmundo Halleyzinho (scenes/npc/halleyzinho.tscn), the old astronomer of the hill who
## tells the tutorials. An inherited scene of the Cometling: the same rig and face, with his
## own parts authored in the scene as voxel boxes (periwig, bushy brows, a few wrinkles, small
## brass spectacles, the long coat with waistcoat and cravat, cuffed sleeves, a wooden cane and
## a pocket spyglass). Their materials are the scene's own (cw_toon_solid), so the Cometling's
## shared skin material is not put on them.
## This script only adds age on top of the Cometling animation:
##   - posture: a hunched back, droopy lids, one paw behind the back, the other on the cane
##   - a slow shuffle (gait exports are set in the scene) and a cane that stays upright and
##     plants its tip on the ground (it slides in the paw when he sits or stretches)
##   - his own idle habits instead of the young ones: adjusting the spectacles, a dozing nod
##     that jerks awake, losing the spectacles on his forehead (he looks for them, finds them),
##     a look at the sky through the spyglass and a rest on the cane
##   - waves with the free paw
## Public API on top of LegendCometling's: HABITS.

## his own habits (the scene lists them in `habit_names`)
const HABITS := ["specs", "doze", "forehead", "stargaze", "cane_rest"]
const _HABIT_LEN := {"specs": 2.4, "doze": 4.2, "forehead": 5.6, "stargaze": 4.6, "cane_rest": 3.2}
## one-shots that use the right arm in the Cometling: he does them with the left (cane hand busy)
const _MIRROR_SHOTS := ["wave", "point", "salute"]
## rest height of the cane: from the paw to the floor (the Shaft mesh in the scene)
const CANE_LEN := 0.27

@export_group("Old age")
## forward lean of the whole body (radians)
@export_range(0.0, 0.4, 0.01) var hunch := 0.17
## how far the eyelids hang (0 open .. 1 shut)
@export_range(0.0, 0.8, 0.01) var lid_droop := 0.55
## the right paw rests on the cane (off: the arm moves like any Cometling's)
@export var cane_hold := true
## the left paw stays behind the back while idle
@export var paw_behind_back := true

var _spec_rest := Transform3D.IDENTITY
var _brow_rest := {}

@onready var cane: Node3D = $Cane
@onready var hand_r_node: Node3D = $Rig/Hips/ArmR/HandR
@onready var spectacles: Node3D = $Rig/Hips/Neck/Spectacles
@onready var brow_l: Node3D = $Rig/Hips/Neck/BrowL
@onready var brow_r: Node3D = $Rig/Hips/Neck/BrowR
@onready var spyglass: Node3D = $Rig/Hips/ArmL/HandL/Spyglass
@onready var spyglass_pocket: Node3D = $Rig/Hips/SpyglassPocket


func _ready() -> void:
	_spec_rest = spectacles.transform
	_brow_rest = {brow_l: brow_l.transform, brow_r: brow_r.transform}
	super._ready()


func _habit_length(habit: String) -> float:
	return float(_HABIT_LEN[habit]) if _HABIT_LEN.has(habit) else super._habit_length(habit)


## "stargaze" is a shared habit name too: his is the spyglass one.
func _own_habit(habit: String) -> bool:
	return habit in HABITS


func _pose_legend(p: Pose) -> void:
	super._pose_legend(p)
	var walk := clampf(_speed_s / 0.5, 0.0, 1.0)
	var shot_w := 0.0
	if _shot != "":
		shot_w = _smooth(_shot_t / 0.12) * _smooth((_shot_len - _shot_t) / 0.2)
	# the free paw does what the right arm would (the right one holds the cane)
	if _shot in _MIRROR_SHOTS:
		p.arm_l = p.arm_l.lerp(p.arm_r, shot_w)
	elif paw_behind_back and _loop == "idle":
		p.arm_l = p.arm_l.lerp(Vector3(0.62, 0.0, 0.05), (1.0 - shot_w) * (1.0 - walk * 0.6))
	if cane_hold:
		var sw := sin(_phase) * 0.18 * walk
		p.arm_r = Vector3(-0.85 + sw, 0.0, 0.14)
	# hunched: the body leans over, the head looks up again
	p.lean += hunch
	p.head.x -= hunch * 0.7
	p.head.x += 0.04
	# old eyes: a bit smaller, heavy lids, outer corners down
	p.eye_scale *= 0.9
	if p.eye_close < 0.5:
		p.lid = maxf(p.lid, lid_droop)
	p.lid_tilt += 0.12
	p.ear_lift -= 0.12


func _pose_habit(p: Pose) -> void:
	var habit := _h
	if not habit in HABITS:
		super._pose_habit(p)
		return
	var u := habit_progress()
	var t := _h_t
	var e := _bump(u)
	match habit:
		"specs":
			# the paw goes up and nudges the spectacles back up the face
			var up := _smooth(u / 0.3) * (1.0 - _smooth((u - 0.75) / 0.25))
			p.arm_l = p.arm_l.lerp(Vector3(-2.15, 0.0, 0.62), up)
			p.head.x += 0.07 * up
			p.eye_squash -= 0.1 * up
		"doze":
			# the head drops slowly as the eyes close... and he jerks awake
			var drop := _smooth(u / 0.7)
			var wake := _smooth((u - 0.7) / 0.06)
			var nod := drop * (1.0 - wake)
			p.head.x += 0.32 * nod
			p.eye_close = maxf(p.eye_close, nod)
			p.lid = maxf(p.lid, 0.6 * nod)
			var startle := _bump((u - 0.7) / 0.3) * wake
			p.eye_scale += 0.2 * startle
			p.lid *= 1.0 - startle
			p.head.x -= 0.1 * startle
			p.ear_lift += 0.25 * startle
			if wake > 0.0 and _h_emoted == 0:
				_h_emoted = 1
				_kick = 0.35
		"forehead":
			# spectacles up on the forehead, a puzzled look around, then he finds them
			var look := _smooth((u - 0.16) / 0.1) * (1.0 - _smooth((u - 0.7) / 0.08))
			p.head.y += sin(t * 1.6) * 0.45 * look
			p.head.z += sin(t * 1.1) * 0.08 * look
			p.eye_scale += 0.06 * look
			var push := _bump(u / 0.18)
			var pat := _bump((u - 0.72) / 0.22)
			p.arm_l = p.arm_l.lerp(Vector3(-2.3, 0.0, 0.55), maxf(push, pat))
			if pat > 0.4:
				p.happy = true
			if u > 0.18 and _h_emoted == 0:
				_h_emoted = 1
				show_emote("question", 2.4)
			elif u > 0.74 and _h_emoted == 1:
				_h_emoted = 2
				show_emote("idea", 1.4)
		"stargaze":
			# the spyglass to the eye, up at the sky
			var up := _smooth(u / 0.22) * (1.0 - _smooth((u - 0.82) / 0.18))
			p.arm_l = p.arm_l.lerp(Vector3(-2.05, 0.15, 0.32), up)
			p.head.x -= 0.42 * up
			p.head.y += 0.12 * up
			p.lean -= hunch * 0.5 * up
			p.eye_squash -= 0.2 * up
		"cane_rest":
			# leans on the cane with a long breath
			p.hips_roll -= 0.07 * e
			p.roll -= 0.04 * e
			p.head.z -= 0.08 * e
			p.eye_close = maxf(p.eye_close, 0.55 * e)
			p.squash -= 0.03 * e
			if e > 0.5:
				p.mouth = 2
				p.mouth_size = 0.7


func _place_props(p: Pose) -> void:
	super._place_props(p)
	# the cane: upright beside the paw, its tip on the floor (or hanging from a raised paw)
	if cane:
		cane.visible = cane_hold
		if cane_hold and is_inside_tree():
			var hand := to_local(hand_r_node.global_position)
			var y := maxf(hand.y, CANE_LEN)
			cane.transform = Transform3D(Basis.from_euler(Vector3(-0.08, 0.0, -0.07)), Vector3(hand.x, y, hand.z + 0.01))
	# spectacles: up on the forehead during "forehead", a nudge during "specs"
	var off := Vector3.ZERO
	var tilt := 0.0
	if _h == "forehead":
		var u := _h_t / _h_len
		var up := _smooth(u / 0.16) * (1.0 - _smooth((u - 0.86) / 0.12))
		off = Vector3(0.0, 0.165, -0.035) * up
		tilt = -0.35 * up
	elif _h == "specs":
		var u2 := _h_t / _h_len
		off.y = 0.01 * sin(u2 * PI * 3.0) * _bump(u2)
	spectacles.transform = Transform3D(Basis.from_euler(Vector3(tilt, 0, 0)), _spec_rest.origin + off) * \
		Transform3D(_spec_rest.basis, Vector3.ZERO)
	# brows lift with wide eyes, frown a little with the droopy lids
	var lift := clampf((p.eye_scale - 0.93) * 0.12, -0.01, 0.03)
	if _h == "forehead" or _h == "doze":
		lift += 0.008
	for b: Node3D in [brow_l, brow_r]:
		var r: Transform3D = _brow_rest[b]
		var s := 1.0 if b == brow_l else -1.0
		b.transform = Transform3D(Basis.from_euler(Vector3(0, 0, -s * p.lid_tilt * 0.25)) * r.basis, r.origin + Vector3(0, lift, 0))
	# the spyglass: at the left eye, pointing up the way the head looks (the paw holds it there)
	var gaze := _h == "stargaze" and _h_t / _h_len > 0.12 and _h_t / _h_len < 0.9
	spyglass.visible = gaze
	spyglass_pocket.visible = not gaze
	if gaze:
		spyglass.global_transform = neck.global_transform * Transform3D(Basis.from_euler(Vector3(-0.35, 0.05, 0)),
			Vector3(0.11, 0.235, 0.31))
