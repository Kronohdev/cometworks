@tool
extends LegendCometling
## Carlito Sagão (scenes/npc/legends/sagao.tscn), homage to Carl Sagan: thick hair swept from a
## side parting, big warm eyebrows, a maroon turtleneck under a brown corduroy jacket with elbow
## patches, and the Voyager golden record in his left paw.
## Habits (habit_names in the scene): billions (a slow sweep of the paw across the sky, talking),
## point_stars (points straight up, in awe), pale_blue_dot (a tiny blue speck on his paw, misty
## eyes: the Earth from Voyager 1) and record (turns the golden record so it catches the light).

var _record_rest := Transform3D.IDENTITY

@onready var hand_l: Node3D = $Rig/Hips/ArmL/HandL
@onready var record: Node3D = $Rig/Hips/ArmL/HandL/Record
@onready var dot: Node3D = $Rig/Hips/ArmR/HandR/PaleBlueDot


func _ready() -> void:
	_record_rest = record.transform
	super._ready()


func _pose_legend(p: Pose) -> void:
	# the record held at his side, a little forward
	p.arm_l = p.arm_l.lerp(Vector3(-0.55, 0.0, 0.2), 0.8)


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"billions":
			var e := LegendProps.env(u, 0.15, 0.2)
			# the paw sweeps from low on one side to high on the other
			var s := _smooth((u - 0.1) / 0.75)
			p.arm_r = p.arm_r.lerp(Vector3(-1.2 - 1.2 * s, 0.0, 0.25 + 0.9 * s), e)
			p.head.y -= (0.1 + 0.35 * s) * e
			p.head.x -= 0.25 * s * e
			p.eye_off = p.eye_off.lerp(Vector2(-0.5, 0.6), e)
			p.mouth = 1 if e > 0.3 and fmod(t, 0.36) < 0.2 else p.mouth
			if _h_emoted == 0 and u > 0.7:
				_h_emoted = 1
				show_emote("star", 1.6)
		"point_stars":
			var e2 := LegendProps.env(u, 0.18, 0.2)
			p.arm_r = p.arm_r.lerp(Vector3(-2.75, 0.0, 0.2), e2)
			p.head.x -= 0.28 * e2
			p.head.y -= 0.1 * e2
			p.eye_scale += 0.12 * e2
			p.mouth = 2 if e2 > 0.5 else p.mouth
			p.ear_lift += 0.2 * e2
			p.lean -= 0.05 * e2
		"pale_blue_dot":
			var e3 := LegendProps.env(u, 0.15, 0.15)
			p.arm_r = p.arm_r.lerp(Vector3(-1.85, -0.2, 0.05), e3)
			p.head.y -= 0.18 * e3
			p.head.x += 0.06 * e3
			p.eye_off = p.eye_off.lerp(Vector2(-0.4, 0.2), e3)
			# misty eyes: soft lids, sad-happy brows, a small smile
			p.lid = maxf(p.lid, 0.15 * e3)
			p.lid_tilt += 0.15 * e3
			p.eye_scale += 0.08 * e3
			p.mouth_size *= 1.0 - 0.25 * e3
			if _h_emoted == 0 and u > 0.6:
				_h_emoted = 1
				show_emote("heart", 1.6)
		"record":
			var e4 := LegendProps.env(u, 0.2, 0.2)
			p.arm_l = p.arm_l.lerp(Vector3(-1.45, 0.3, 0.1), e4)
			p.head.y += 0.25 * e4
			p.head.x += 0.05 * e4
			p.eye_off = p.eye_off.lerp(Vector2(0.6, -0.1), e4)
			if u > 0.5:
				p.happy = e4 > 0.6


func _place_props(_p: Pose) -> void:
	var turn := Basis.IDENTITY
	if _h == "record":
		var u := habit_progress()
		turn = Basis(Vector3.UP, sin(u * TAU) * 0.6 * LegendProps.env(u, 0.25, 0.25))
	LegendProps.hold_upright(record, _record_rest, hand_l, hips, turn)
	var show := _h == "pale_blue_dot" and habit_progress() > 0.15 and habit_progress() < 0.88
	dot.visible = show
	if show:
		dot.scale = Vector3.ONE * (1.0 + 0.15 * sin(_h_t * 6.0))
