@tool
extends LegendCometling
## Carolina Herschelinha (scenes/npc/legends/herschelinha.tscn), homage to Caroline Herschel and
## the face of the rival Instituto Quietude: a white frilled cap with a violet ribbon, dark curls
## under the frill, a violet dress with a white kerchief and a long brass telescope, nearly as tall
## as she is, resting on her shoulder.
## Habits (habit_names in the scene): sweep (the telescope at her eye, sweeping the sky slowly),
## measure (writes in her notebook and nods twice: measure twice, then again) and comet (she
## found one!).

var _tel_rest := Transform3D.IDENTITY

@onready var hand_l: Node3D = $Rig/Hips/ArmL/HandL
@onready var telescope: Node3D = $Rig/Hips/ArmL/HandL/Telescope
@onready var notebook: Node3D = $Rig/Hips/ArmR/HandR/Notebook


func _ready() -> void:
	_tel_rest = telescope.transform
	super._ready()


func _pose_legend(p: Pose) -> void:
	# the telescope over her shoulder
	p.arm_l = p.arm_l.lerp(Vector3(-0.75, 0.0, 0.12), 0.85)


func _gaze_w() -> float:
	if _h != "sweep":
		return 0.0
	return LegendProps.env(habit_progress(), 0.15, 0.12)


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"sweep":
			var e := _gaze_w()
			p.arm_l = p.arm_l.lerp(Vector3(-2.0, 0.1, -0.12), e)
			p.head.x -= 0.22 * e
			# a slow sweep from one side of the sky to the other
			p.head.y += sin(clampf((u - 0.15) / 0.75, 0.0, 1.0) * TAU * 0.75) * 0.35 * e
			p.eye_close = maxf(p.eye_close, 0.0)
			p.eye_squash -= 0.25 * e
			p.lean -= 0.05 * e
		"measure":
			var e2 := LegendProps.env(u, 0.15, 0.15)
			p.arm_r = p.arm_r.lerp(Vector3(-1.3, 0.0, -0.3), e2)
			p.head.x += 0.2 * e2
			p.eye_off = p.eye_off.lerp(Vector2(-0.3, -0.8), e2)
			# two nods: measured twice
			for k in 2:
				var n := clampf((u - 0.45 - k * 0.18) / 0.14, 0.0, 1.0)
				p.head.x += 0.16 * sin(n * PI) * e2
		"comet":
			var e3 := LegendProps.env(u, 0.1, 0.25)
			p.arm_r = p.arm_r.lerp(Vector3(-2.6, 0.0, 0.35), e3)
			p.head.x -= 0.22 * e3
			p.eye_scale += 0.18 * e3
			p.mouth = 1 if e3 > 0.4 else p.mouth
			p.rig_y += 0.04 * absf(sin(clampf(u / 0.5, 0.0, 1.0) * PI * 2.0)) * e3
			p.ear_lift += 0.4 * e3
			if _h_emoted == 0 and u > 0.12:
				_h_emoted = 1
				show_emote("star", 1.6)


func _place_props(_p: Pose) -> void:
	var g := _gaze_w()
	if g > 0.5 and telescope.is_inside_tree():
		# the eyepiece at her left eye, the tube along her gaze, up at the sky
		var look := Basis(Vector3.UP, 0.55) * Basis(Vector3.RIGHT, PI * 0.5 - 0.75)
		telescope.global_transform = neck.global_transform * Transform3D(look, Vector3(0.116, 0.232, 0.36) + look * Vector3(0, 0.075, 0))
	else:
		LegendProps.hold_upright(telescope, _tel_rest, hand_l, hips)
	notebook.visible = _h == "measure" and habit_progress() > 0.1 and habit_progress() < 0.9
