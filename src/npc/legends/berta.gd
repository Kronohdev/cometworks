@tool
extends LegendCometling
## Berta Luzinha (scenes/npc/legends/berta.tscn), homage to Bertha Lutz: a dark 1930s bob with
## finger waves and a flower pinned over the parting, a teal suit with wide lapels and a white
## blouse bow, the notebook where she writes everything down and, on her shoulder, a little frog
## (she was a biologist and a specialist in amphibians).
## Habits (habit_names in the scene): notes (writes in the notebook), frog (the frog hops on her
## shoulder and she smiles at it) and speak_up (a raised paw, firm and calm: nobody is left out).

var _book_rest := Transform3D.IDENTITY
var _frog_rest := Transform3D.IDENTITY

@onready var hand_l: Node3D = $Rig/Hips/ArmL/HandL
@onready var notebook: Node3D = $Rig/Hips/ArmL/HandL/Notebook
@onready var pencil: Node3D = $Rig/Hips/ArmR/HandR/Pencil
@onready var frog: Node3D = $Rig/Hips/Frog


func _ready() -> void:
	_book_rest = notebook.transform
	_frog_rest = frog.transform
	super._ready()


func _pose_legend(p: Pose) -> void:
	p.arm_l = p.arm_l.lerp(Vector3(-0.75, 0.1, 0.08), 0.85)


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"notes":
			var e := LegendProps.env(u, 0.15, 0.15)
			p.arm_l = p.arm_l.lerp(Vector3(-1.35, 0.0, -0.22), e)
			var scrib := sin(t * 18.0) * 0.05 + sin(t * 3.0) * 0.08
			p.arm_r = p.arm_r.lerp(Vector3(-1.25 + scrib, 0.0, -0.32), e)
			p.head.x += 0.22 * e
			p.head.y += 0.06 * e
			p.eye_off = p.eye_off.lerp(Vector2(0.2 + sin(t * 3.0) * 0.4, -0.7), e)
			p.eye_squash -= 0.1 * e
		"frog":
			var e2 := LegendProps.env(u, 0.15, 0.2)
			p.head.y -= 0.42 * e2
			p.head.z -= 0.08 * e2
			p.eye_off = p.eye_off.lerp(Vector2(-0.8, -0.2), e2)
			if u > 0.35:
				p.happy = e2 > 0.5
			if _h_emoted == 0 and u > 0.6:
				_h_emoted = 1
				show_emote("heart", 1.5)
		"speak_up":
			var e3 := LegendProps.env(u, 0.12, 0.2)
			p.arm_r = p.arm_r.lerp(Vector3(-2.7, 0.0, 0.25), e3)
			p.head.x -= 0.06 * e3
			p.lid = maxf(p.lid, 0.12 * e3)
			p.lid_tilt -= 0.12 * e3
			p.mouth = 1 if e3 > 0.5 and u > 0.4 and fmod(t, 0.38) < 0.2 else p.mouth
			if _h_emoted == 0 and u > 0.2:
				_h_emoted = 1
				show_emote("exclaim", 1.3)


func _place_props(_p: Pose) -> void:
	LegendProps.hold_upright(notebook, _book_rest, hand_l, hips)
	pencil.visible = _h == "notes" and habit_progress() > 0.1 and habit_progress() < 0.9
	# the frog: two hops on the shoulder during its habit, otherwise a slow breath
	var hop := 0.0
	var squash := 1.0 + sin(_t * 2.2) * 0.04
	if _h == "frog":
		var u := habit_progress()
		for k in 2:
			var a := clampf((u - 0.2 - k * 0.25) / 0.16, 0.0, 1.0)
			hop = maxf(hop, sin(a * PI))
		squash = 1.0 - 0.2 * (1.0 - hop) * float(u > 0.18 and u < 0.7) + 0.1 * hop
	frog.transform = Transform3D(_frog_rest.basis * Basis.from_scale(Vector3(1.0, squash, 1.0)),
		_frog_rest.origin + Vector3(0, 0.05 * hop, 0))
