@tool
extends LegendCometling
## Dona Cifrinha (scenes/npc/legends/cifrinha.tscn), an original character, the face of the rival
## Consórcio Nimbo: a gold coin on her antenna instead of the glowing bulb, neat silver hair in a
## bun, a light blue blazer with shoulder pads, coin buttons, pearls and a pink pocket square, and
## a calculator always at hand. No villain: she just likes a tidy spreadsheet.
## Habits (habit_names in the scene): calculate (taps the calculator, a satisfied nod),
## coin_flip (flips a coin and catches it, a smug little smile) and polite_bow (the politest bow).

var _calc_rest := Transform3D.IDENTITY

@onready var hand_l: Node3D = $Rig/Hips/ArmL/HandL
@onready var calculator: Node3D = $Rig/Hips/ArmL/HandL/Calculator
@onready var display: Node3D = $Rig/Hips/ArmL/HandL/Calculator/Display
@onready var hand_r: Node3D = $Rig/Hips/ArmR/HandR
@onready var flip_coin: Node3D = $Rig/Hips/ArmR/HandR/FlipCoin


func _ready() -> void:
	_calc_rest = calculator.transform
	super._ready()


func _pose_legend(p: Pose) -> void:
	p.arm_l = p.arm_l.lerp(Vector3(-0.85, 0.1, 0.06), 0.85)
	p.mouth_size *= 0.9


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"calculate":
			var e := LegendProps.env(u, 0.15, 0.18)
			p.arm_l = p.arm_l.lerp(Vector3(-1.3, 0.0, -0.2), e)
			var tap := absf(sin(t * 11.0)) * (1.0 - _smooth((u - 0.65) / 0.1))
			p.arm_r = p.arm_r.lerp(Vector3(-1.15 - 0.12 * tap, 0.0, -0.38), e)
			p.head.x += 0.22 * e
			p.head.y += 0.08 * e
			p.eye_off = p.eye_off.lerp(Vector2(0.3, -0.8), e)
			if u > 0.7:
				p.head.x += 0.1 * sin((u - 0.7) / 0.3 * TAU * 2.0) * e
				p.happy = true
				if _h_emoted == 0:
					_h_emoted = 1
					show_emote("check", 1.3)
		"coin_flip":
			var e2 := LegendProps.env(u, 0.15, 0.2)
			var h := _flip_height()
			p.arm_r = p.arm_r.lerp(Vector3(-1.25 - 0.25 * float(h <= 0.0), 0.0, -0.05), e2)
			# the eyes follow the coin up and down
			p.head.x -= 0.35 * h * e2
			p.eye_off = p.eye_off.lerp(Vector2(-0.3, h * 2.0), e2)
			if u > 0.7:
				p.happy = true
				p.head.z += 0.08 * e2
				if _h_emoted == 0:
					_h_emoted = 1
					show_emote("sparkle", 1.3)
		"polite_bow":
			var e3 := LegendProps.env(u, 0.3, 0.35)
			p.lean += 0.3 * e3
			p.head.x += 0.18 * e3
			p.arm_r = p.arm_r.lerp(Vector3(-0.6, 0.0, -0.3), e3)
			p.happy = e3 > 0.4
			p.tail_lift += 0.2 * e3


func _place_props(_p: Pose) -> void:
	LegendProps.hold_upright(calculator, _calc_rest, hand_l, hips)
	# the display flickers while she types
	if _h == "calculate" and habit_progress() < 0.68:
		display.visible = fmod(_h_t, 0.3) > 0.06
	else:
		display.visible = true
	# the flipped coin: up from the paw, spinning, and back into it
	var flying := _h == "coin_flip" and habit_progress() > 0.12 and habit_progress() < 0.92
	flip_coin.visible = flying
	if flying:
		var h := _flip_height()
		var spin := Basis(Vector3.RIGHT, _h_t * 22.0 * float(h > 0.0))
		flip_coin.global_transform = Transform3D(global_basis * spin,
			hand_r.global_position + global_basis * Vector3(0.0, 0.05 + 0.32 * h, 0.03))


## height of the flipped coin above her paw (0..1, a parabola between 25% and 65% of the habit)
func _flip_height() -> float:
	var a := clampf((habit_progress() - 0.25) / 0.4, 0.0, 1.0)
	return 4.0 * a * (1.0 - a)
