@tool
extends LegendCometling
## Joãozinho Keplerino (scenes/npc/legends/keplerino.tscn), homage to Johannes Kepler: dark
## shoulder-length hair parted in the middle, a little goatee, a white pleated ruff, a dark
## doublet with gold buttons and paned trunk hose. In his left paw, a brass orbit model: an
## ellipse with the Sun at one focus and a small planet that runs faster near the Sun (his
## second law, solved for real below).
## Habits (habit_names in the scene): orbit (raises the model and follows the planet), ellipse
## (draws one in the air with a paw), not_circle (somebody said "circle": a grumpy head shake).

## the ellipse authored in the scene (OrbitModel/Ring): semi-axes and the centre of the ring
const A := 0.11
const B := 0.07
const CENTRE := Vector3(0.0, 0.19, 0.0)

## seconds for one turn of the little planet (faster while he shows it)
@export var orbit_period := 7.0

var _mean := 0.0
var _model_rest := Transform3D.IDENTITY

@onready var hand_l: Node3D = $Rig/Hips/ArmL/HandL
@onready var orbit_model: Node3D = $Rig/Hips/ArmL/HandL/OrbitModel
@onready var planet: Node3D = $Rig/Hips/ArmL/HandL/OrbitModel/Planet


func _ready() -> void:
	_model_rest = orbit_model.transform
	super._ready()


func _pose_legend(p: Pose) -> void:
	# the model held up in front, at the chest
	var two := 1.0 if _shot in ["cheer", "celebrate", "clap", "stretch", "shrug", "spin"] else 0.0
	var w := 1.0 - two * 0.6
	p.arm_l = p.arm_l.lerp(Vector3(-0.95, 0.05, 0.16), w)
	p.eye_off.x += 0.15


func _pose_habit(p: Pose) -> void:
	var u := habit_progress()
	var t := _h_t
	match _h:
		"orbit":
			var up := LegendProps.env(u, 0.18, 0.18)
			p.arm_l = p.arm_l.lerp(Vector3(-1.75, 0.0, -0.12), up)
			p.head.y += 0.22 * up
			p.head.x -= 0.1 * up
			var pl := _planet_dir()
			p.eye_off = p.eye_off.lerp(Vector2(0.6 + pl.x * 0.5, pl.y * 0.6), up)
			p.eye_scale += 0.06 * up
			if u > 0.55:
				p.happy = up > 0.5
		"ellipse":
			var e := LegendProps.env(u, 0.12, 0.15)
			var a := t * TAU / (_h_len * 0.42)
			p.arm_r = p.arm_r.lerp(Vector3(-1.75 + 0.32 * sin(a), 0.0, 0.42 + 0.34 * cos(a)), e)
			p.head.y -= (0.22 + 0.12 * cos(a)) * e
			p.head.x -= (0.08 + 0.06 * sin(a)) * e
			p.eye_off = p.eye_off.lerp(Vector2(-0.6 - 0.3 * cos(a), 0.3 + 0.3 * sin(a)), e)
			if u > 0.85:
				p.happy = true
		"not_circle":
			var e2 := LegendProps.env(u, 0.1, 0.25)
			var shake := LegendProps.env(clampf((u - 0.15) / 0.45, 0.0, 1.0), 0.15, 0.3)
			p.head.y += sin(t * 15.0) * 0.22 * shake
			p.lid = maxf(p.lid, 0.35 * e2)
			p.lid_tilt -= 0.35 * e2
			p.mouth = 3 if e2 > 0.3 and u < 0.6 else p.mouth
			p.ear_lift -= 0.2 * e2
			# then he holds the model up: "an ELLIPSE"
			var show := LegendProps.env(clampf((u - 0.55) / 0.45, 0.0, 1.0), 0.25, 0.3)
			p.arm_l = p.arm_l.lerp(Vector3(-1.7, 0.0, -0.05), show)
			p.head.y += 0.25 * show
			if _h_emoted == 0 and u > 0.08:
				_h_emoted = 1
				show_emote("exclaim", 1.4)


func _tick_timers(dt: float) -> void:
	super._tick_timers(dt)
	var speed := 3.0 if _h == "orbit" else 1.0
	_mean = fmod(_mean + dt * TAU * speed / maxf(orbit_period, 0.5), TAU)


func _place_props(_p: Pose) -> void:
	LegendProps.hold_upright(orbit_model, _model_rest, hand_l, hips)
	var e := sqrt(1.0 - (B * B) / (A * A))
	# Kepler's equation M = E - e sin E (a few Newton steps)
	var ea := _mean
	for i in 4:
		ea -= (ea - e * sin(ea) - _mean) / (1.0 - e * cos(ea))
	planet.position = CENTRE + Vector3(A * cos(ea), B * sin(ea), 0.0)


## where the planet is on the ring (-1..1), for the eyes that follow it
func _planet_dir() -> Vector2:
	return Vector2(planet.position.x / A, (planet.position.y - CENTRE.y) / B)
