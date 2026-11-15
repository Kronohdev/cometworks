@tool
extends LegendCometling
## Sali Carona (scenes/npc/legends/sali.tscn), homage to Sally Ride: fluffy feathered 1980s hair,
## a radio headset with a microphone, the light blue flight suit of the Space Shuttle crews (a
## plain round patch and a blank name tag) and the football she explains physics with.
## Habits (habit_names in the scene): juggle (keeps the ball up with her foot), explain (holds
## the ball up and points at it: any question gets an answer) and zero_g (floats as if in orbit,
## the ball drifting beside her).

var _ball_rest := Transform3D.IDENTITY

@onready var hand_l: Node3D = $Rig/Hips/ArmL/HandL
@onready var ball: Node3D = $Rig/Hips/ArmL/HandL/Ball


func _ready() -> void:
	_ball_rest = ball.transform
	super._ready()


func _pose_legend(p: Pose) -> void:
	p.arm_l = p.arm_l.lerp(Vector3(-0.35, 0.0, 0.32), 0.85)


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"juggle":
			var e := LegendProps.env(u, 0.12, 0.15)
			var k := _kick_phase()
			# the foot comes up to meet the ball, arms out for balance
			p.foot_l = p.foot_l.lerp(Vector3(0.0, 0.07 * k, 0.05 * k), e)
			p.foot_pitch.x -= 0.4 * k * e
			p.hips_roll -= 0.06 * e
			p.arm_l = p.arm_l.lerp(Vector3(-0.2, 0.0, 0.85), e)
			p.arm_r = p.arm_r.lerp(Vector3(-0.2, 0.0, 0.85), e)
			p.head.x += 0.28 * e
			p.eye_off = p.eye_off.lerp(Vector2(0.2, -0.8), e)
			p.mouth = 2 if e > 0.5 else p.mouth
		"explain":
			var e2 := LegendProps.env(u, 0.15, 0.18)
			p.arm_l = p.arm_l.lerp(Vector3(-1.6, 0.0, 0.05), e2)
			var tap := absf(sin(t * 4.0))
			p.arm_r = p.arm_r.lerp(Vector3(-1.45 - 0.1 * tap, 0.0, -0.25), e2)
			p.head.y += 0.12 * e2
			p.mouth = 1 if e2 > 0.4 and fmod(t, 0.34) < 0.19 else p.mouth
			if _h_emoted == 0 and u > 0.25:
				_h_emoted = 1
				show_emote("idea", 1.5)
		"zero_g":
			var e3 := LegendProps.env(u, 0.25, 0.25)
			p.rig_y += (0.08 + 0.02 * sin(t * 2.4)) * e3
			p.arm_l = p.arm_l.lerp(Vector3(-0.3 + 0.2 * sin(t * 1.7), 0.0, 1.0), e3)
			p.arm_r = p.arm_r.lerp(Vector3(-0.3 + 0.2 * sin(t * 1.7 + 1.0), 0.0, 1.0), e3)
			p.foot_l.y += 0.02 * e3
			p.foot_r.y += 0.035 * e3
			p.foot_pitch += Vector2(0.35, 0.2) * e3
			p.roll += sin(t * 1.3) * 0.06 * e3
			p.ear_lift += 0.5 * e3
			p.happy = e3 > 0.6
			p.tail_lift += 0.5 * e3


## 1 when the foot is up under the ball (two kicks a second)
func _kick_phase() -> float:
	return pow(maxf(0.0, cos(_h_t * TAU * 1.1)), 3.0)


func _place_props(_p: Pose) -> void:
	if _h == "juggle" and habit_progress() > 0.1 and habit_progress() < 0.9:
		# the ball flies up from the foot and falls back onto it
		var ph := fmod(_h_t * 1.1, 1.0)
		var h := 4.0 * ph * (1.0 - ph)
		var at := to_global(Vector3(0.085, 0.16 + 0.24 * h, 0.15))
		ball.global_transform = Transform3D(global_basis * Basis(Vector3.RIGHT, _h_t * 9.0), at)
	elif _h == "zero_g" and habit_progress() > 0.15 and habit_progress() < 0.85:
		var at2 := to_global(Vector3(0.26 + 0.03 * sin(_h_t * 1.2), 0.62 + 0.04 * sin(_h_t * 1.9), 0.18))
		ball.global_transform = Transform3D(global_basis * Basis(Vector3(0.3, 1, 0.2).normalized(), _h_t * 1.5), at2)
	else:
		LegendProps.hold_upright(ball, _ball_rest, hand_l, hips)
