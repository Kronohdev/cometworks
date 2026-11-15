@tool
extends LegendCometling
## Comandante Iúri Gagarinho (scenes/npc/legends/gagarinho.tscn), homage to Yuri Gagarin and the
## face of the rival agency Aurora Rubra: the white helmet with its visor raised and the band in
## the Aurora's red (a little golden flame instead of letters), the orange flight suit with its
## harness, and the biggest smile on the hill.
## Habits (habit_names in the scene): poyekhali ("let's go!": a crouch and a fist up), wave_big
## (both paws waving, a proud and friendly rival) and thumbs_up (a paw forward and a grin).

## how often the big open grin shows while idle (0..1)
@export_range(0.0, 1.0, 0.05) var grin := 0.75


func _pose_legend(p: Pose) -> void:
	# the big smile: an open grin most of the time
	if p.mouth == 0 and _loop == "idle" and sin(_t * 0.6) > 1.0 - grin * 2.0:
		p.mouth = 1
		p.mouth_size *= 1.12
	p.eye_squash -= 0.05
	p.head.x -= 0.04


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"poyekhali":
			# a little crouch... and up!
			var crouch := LegendProps.env(clampf(u / 0.3, 0.0, 1.0), 0.4, 0.4)
			p.squash -= 0.1 * crouch
			p.rig_y -= 0.02 * crouch
			var up := LegendProps.env(clampf((u - 0.25) / 0.75, 0.0, 1.0), 0.12, 0.25)
			p.rig_y += 0.05 * up * absf(sin(clampf((u - 0.25) / 0.2, 0.0, 1.0) * PI))
			p.arm_r = p.arm_r.lerp(Vector3(-2.9, 0.0, 0.15), up)
			p.arm_l = p.arm_l.lerp(Vector3(-0.3, 0.0, 0.6), up)
			p.head.x -= 0.15 * up
			p.mouth = 1 if up > 0.3 else p.mouth
			p.mouth_size *= 1.0 + 0.3 * up
			p.eye_scale += 0.1 * up
			p.ear_lift += 0.4 * up
			p.tail_lift += 0.6 * up
			if _h_emoted == 0 and u > 0.3:
				_h_emoted = 1
				show_emote("rocket", 1.6)
		"wave_big":
			var e := LegendProps.env(u, 0.12, 0.18)
			var w := sin(t * 9.0)
			p.arm_r = p.arm_r.lerp(Vector3(-2.6, 0.0, 0.55 + 0.35 * w), e)
			p.arm_l = p.arm_l.lerp(Vector3(-2.6, 0.0, 0.55 - 0.35 * w), e)
			p.roll += 0.05 * w * e
			p.mouth = 1
			p.happy = e > 0.5
			p.tail_wag += sin(t * 12.0) * 0.5 * e
		"thumbs_up":
			var e2 := LegendProps.env(u, 0.15, 0.2)
			p.arm_r = p.arm_r.lerp(Vector3(-1.5, -0.4, 0.05), e2)
			p.head.z += 0.12 * e2
			p.head.y -= 0.08 * e2
			p.mouth = 1
			p.happy = e2 > 0.5
			if _h_emoted == 0 and u > 0.35:
				_h_emoted = 1
				show_emote("star", 1.3)
