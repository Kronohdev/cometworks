class_name FlightNodeExecutor
extends RefCounted
## "Execute node" autopilot (key Y / the node panel): points the vessel along the remaining
## Δv of the next maneuver node, starts the burn half the estimated burn time before the
## node (half is burned before and half after), throttles down for the last metres per
## second and stops when the burn is done. Stages when the burning stage runs dry.
## FlightWorld tracks the burned Δv (node.burned) and removes the node when it is done.
##
## End of the burn: burns that change the orbital energy (e.g. a trans-lunar injection)
## end when the vessel's specific energy reaches the planned post-burn energy. A long
## burn is not an impulse: burning the planned vector exactly would leave the orbit short
## (gravity turns the velocity during a 7-minute burn and the Oberth gain is lower away
## from the node), while the energy target lands the apoapsis where the plan put it.
## Burns that keep the energy (plane changes, circular-to-circular tweaks) end on the
## remaining Δv vector.

## ABORT: nothing left that can burn (no propellant in any stage)
enum { CONTINUE, STAGE, DONE, ABORT }

## pointing error (deg) above which the engines stay off
const ALIGN_DEG := 3.0
## a burn never goes over the planned Δv by more than this fraction
const MAX_OVERBURN := 0.25

var node: FlightManeuverNode
var _cooldown := 0.0
var _no_thrust := 0.0
var _last_dir := Vector3.ZERO


func _init(n: FlightManeuverNode) -> void:
	node = n


## `soi`: index of the body the vessel orbits now (energy targets only apply in the
## node's own SOI).
func update(v: FlightVessel, now: float, dt: float, soi := -1) -> int:
	_cooldown -= dt
	if node == null or not node.valid:
		v.throttle = 0.0
		return DONE
	var rem := node.remaining_world()
	var full := Vector3(node.dv_world[0], node.dv_world[1], node.dv_world[2])
	var dv_plan := full.length()
	var left := rem.length()
	# energy mode
	var de_plan := node.energy_after - node.energy_before
	var energy_mode := soi == node.body and absf(de_plan) > 0.002 * maxf(absf(node.energy_before), 1.0)
	var progress := 0.0
	if energy_mode:
		var b := v.body
		var e_now := (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz) * 0.5 - b.mu / b.radius()
		progress = (e_now - node.energy_before) / de_plan
		if node.locked and progress >= 1.0:
			v.throttle = 0.0
			return DONE
		# Δv still to burn, estimated from the energy still to gain
		left = maxf(left, (1.0 - progress) * dv_plan)
	elif node.locked and (left < 0.05 or rem.dot(full) <= 0.0):
		v.throttle = 0.0
		return DONE
	if node.burned.length() > dv_plan * (1.0 + MAX_OVERBURN) + 1.0:
		v.throttle = 0.0
		return DONE
	var dir := rem / rem.length() if rem.length() > 0.5 else (_last_dir if _last_dir != Vector3.ZERO else full.normalized())
	if energy_mode and rem.dot(full) <= 0.0:
		dir = _last_dir if _last_dir != Vector3.ZERO else full.normalized()
	_last_dir = dir
	v.sas = FlightVessel.Sas.DIRECTION
	v.sas_dir = dir
	var be := v.burn_engines()
	var thrust: float = be["thrust"]
	var bt := v.burn_time(dv_plan if not node.locked else left)
	var t_start := node.time - (bt * 0.5 if bt < INF else 0.0)
	var err := rad_to_deg(v.nose_world().angle_to(dir))
	var thr := 0.0
	if (now >= t_start or node.locked) and err < ALIGN_DEG + (6.0 if node.locked else 0.0):
		var a_max := thrust / maxf(v.mass, 1.0)
		# the last ~1.5 s of burn: proportional, so the cut lands on the target
		thr = clampf(left / maxf(a_max * 1.5, 1e-3), 0.02, 1.0) if a_max > 0.0 else 1.0
		if err > ALIGN_DEG:
			thr *= 0.25
	v.throttle = thr
	# the burning stage ran dry: next stage
	if thr > 0.0 and v.thrust_n <= 0.0 and not v.clamped:
		_no_thrust += dt
	else:
		_no_thrust = 0.0
	if _no_thrust > 0.5 and _cooldown <= 0.0 and v.current_stage < v.stage_count - 1:
		_cooldown = 1.5
		_no_thrust = 0.0
		return STAGE
	if _no_thrust > 1.0 and be["thrust"] <= 0.0:
		v.throttle = 0.0
		return ABORT
	return CONTINUE
