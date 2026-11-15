@tool
extends LegendCometling
## Dulinha da Estrela (scenes/npc/legends/dulinha.tscn), homage to Duília de Mello: long dark wavy
## hair with curtain bangs, an indigo blazer over a pink top, a navy scarf sprinkled with stars
## and a tablet showing a spiral galaxy (she studies galaxies in Hubble images).
## Habits (habit_names in the scene): point_sky (points at the sky in the middle of a sentence...
## and forgets what she was saying), show_galaxy (holds the tablet up so you can see) and nickname
## (hugs the tablet: she has a nickname for every galaxy).

var _tab_rest := Transform3D.IDENTITY

@onready var hand_l: Node3D = $Rig/Hips/ArmL/HandL
@onready var tablet: Node3D = $Rig/Hips/ArmL/HandL/Tablet


func _ready() -> void:
	_tab_rest = tablet.transform
	super._ready()


func _pose_legend(p: Pose) -> void:
	p.arm_l = p.arm_l.lerp(Vector3(-0.8, 0.1, 0.08), 0.85)


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"point_sky":
			# talking... points up... freezes... forgets
			var talk_w := 1.0 - _smooth((u - 0.3) / 0.1)
			p.mouth = 1 if talk_w > 0.5 and fmod(t, 0.36) < 0.2 else p.mouth
			var up := LegendProps.env(clampf((u - 0.2) / 0.62, 0.0, 1.0), 0.15, 0.25)
			p.arm_r = p.arm_r.lerp(Vector3(-2.7, 0.0, 0.3), up)
			p.head.x -= 0.3 * up
			p.head.y -= 0.12 * up
			p.eye_scale += 0.1 * up
			p.ear_lift += 0.15 * up
			if u > 0.5:
				p.mouth = 2
			# then scratches her head, a little lost
			var lost := LegendProps.env(clampf((u - 0.78) / 0.22, 0.0, 1.0), 0.3, 0.2)
			p.arm_r = p.arm_r.lerp(Vector3(-2.6, 0.2, 0.85), lost)
			p.head.z += 0.12 * lost
			if _h_emoted == 0 and u > 0.6:
				_h_emoted = 1
				show_emote("question", 1.6)
		"show_galaxy":
			var e := LegendProps.env(u, 0.18, 0.2)
			p.arm_l = p.arm_l.lerp(Vector3(-1.65, 0.0, -0.18), e)
			p.head.y += 0.2 * e
			p.eye_off = p.eye_off.lerp(Vector2(0.5, -0.2), e)
			p.happy = e > 0.6 and u > 0.4
			if _h_emoted == 0 and u > 0.45:
				_h_emoted = 1
				show_emote("sparkle", 1.4)
		"nickname":
			var e2 := LegendProps.env(u, 0.2, 0.2)
			p.arm_l = p.arm_l.lerp(Vector3(-1.2, 0.0, -0.55), e2)
			p.arm_r = p.arm_r.lerp(Vector3(-1.1, 0.0, -0.45), e2)
			p.roll += sin(t * 3.2) * 0.07 * e2
			p.head.z += sin(t * 3.2) * 0.1 * e2
			p.happy = e2 > 0.5
			if _h_emoted == 0 and u > 0.3:
				_h_emoted = 1
				show_emote("heart", 1.6)


func _place_props(_p: Pose) -> void:
	var turn := Basis.IDENTITY
	if _h == "nickname":
		var e := LegendProps.env(habit_progress(), 0.2, 0.2)
		turn = Basis(Vector3.UP, 0.6 * e) * Basis(Vector3.RIGHT, 0.4 * e)
	LegendProps.hold_upright(tablet, _tab_rest, hand_l, hips, turn)
