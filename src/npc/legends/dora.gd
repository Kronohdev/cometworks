@tool
extends LegendCometling
## Dora Vonzinha (scenes/npc/legends/dora.tscn), homage to Dorothy Vaughan: short 1950s curls
## with a pencil tucked in them, a white blouse with a round collar and pearls, a lavender
## cardigan and a navy skirt; the manual of the new machine always under her paw.
## Habits (habit_names in the scene): read_manual (opens the manual and reads it first),
## teach (points at an imaginary blackboard and nods: everyone learns) and punch_card (holds a
## punched card up to the light and checks it).

var _book_rest := Transform3D.IDENTITY

@onready var hand_l: Node3D = $Rig/Hips/ArmL/HandL
@onready var book: Node3D = $Rig/Hips/ArmL/HandL/Manual
@onready var book_front: Node3D = $Rig/Hips/ArmL/HandL/Manual/Front
@onready var book_lines: Node3D = $Rig/Hips/ArmL/HandL/Manual/Lines
@onready var card: Node3D = $Rig/Hips/ArmR/HandR/PunchCard


func _ready() -> void:
	_book_rest = book.transform
	super._ready()


func _pose_legend(p: Pose) -> void:
	# the manual held against her side
	p.arm_l = p.arm_l.lerp(Vector3(-0.7, 0.1, 0.1), 0.85)


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"read_manual":
			var e := LegendProps.env(u, 0.15, 0.15)
			p.arm_l = p.arm_l.lerp(Vector3(-1.6, 0.0, -0.3), e)
			p.head.x += 0.16 * e
			p.head.y += 0.12 * e
			# the eyes run along the lines
			p.eye_off = p.eye_off.lerp(Vector2(0.3 + 0.6 * sin(t * 2.6), -0.6), e)
			p.eye_squash -= 0.08 * e
			if u > 0.8:
				p.happy = true
				if _h_emoted == 0:
					_h_emoted = 1
					show_emote("idea", 1.4)
		"teach":
			var e2 := LegendProps.env(u, 0.15, 0.2)
			var tap := absf(sin(t * 5.0)) * _smooth((u - 0.25) / 0.1) * (1.0 - _smooth((u - 0.7) / 0.1))
			p.arm_r = p.arm_r.lerp(Vector3(-1.9 + 0.15 * tap, 0.0, 0.3), e2)
			p.head.y -= 0.15 * e2
			p.head.x += 0.06 * tap
			p.mouth = 1 if e2 > 0.4 and fmod(t, 0.4) < 0.22 else p.mouth
			if u > 0.72:
				p.head.x += 0.1 * sin((u - 0.72) / 0.28 * TAU * 2.0) * e2
				p.happy = true
		"punch_card":
			var e3 := LegendProps.env(u, 0.15, 0.18)
			p.arm_r = p.arm_r.lerp(Vector3(-2.2, -0.1, 0.12), e3)
			p.head.x -= 0.3 * e3
			p.head.y -= 0.1 * e3
			p.eye_off = p.eye_off.lerp(Vector2(-0.3, 0.7), e3)
			if u < 0.6:
				p.eye_squash -= 0.25 * e3
				p.lid = maxf(p.lid, 0.25 * e3)
			else:
				p.happy = e3 > 0.5
				if _h_emoted == 0:
					_h_emoted = 1
					show_emote("star", 1.4)


func _place_props(_p: Pose) -> void:
	var lift := Basis.IDENTITY
	var open := 0.0
	if _h == "read_manual":
		var u := habit_progress()
		var e := LegendProps.env(u, 0.15, 0.15)
		lift = Basis(Vector3.UP, 0.5 * e) * Basis(Vector3.RIGHT, -0.35 * e)
		open = LegendProps.env(clampf((u - 0.1) / 0.85, 0.0, 1.0), 0.2, 0.2)
	LegendProps.hold_upright(book, _book_rest, hand_l, hips, lift)
	book_front.rotation.y = -2.6 * open
	book_lines.visible = open > 0.3
	card.visible = _h == "punch_card" and habit_progress() > 0.12 and habit_progress() < 0.9
