class_name FlightNodeExecutor
extends RefCounted
## "Execute node" autopilot (key Y / the node panel), flown as the run's guide (FlightSim calls
## update() before every physics step, next_event() for where rails must stop): points the
## craft along the remaining Δv of the next maneuver node, starts the burn half the estimated
## burn time before the node, throttles down for the last metres per second and stops when the
## burn is done; stages when the burning stage runs dry. The burned Δv goes into node.burned.
##
## End of the burn: burns that change the orbital energy (a trans-lunar injection) end when the
## craft's specific energy reaches the planned post-burn energy (a long burn is not an impulse:
## the energy target lands the apoapsis where the plan put it); burns that keep the energy
## (plane changes) end on the remaining Δv vector.
## `state`: CONTINUE while working, DONE when the node is burned, ABORT when nothing can burn.

enum { CONTINUE, STAGE, DONE, ABORT }

const ALIGN_DEG := 3.0
const MAX_OVERBURN := 0.25
const LEAD := 20.0

var node: FlightManeuverNode
var state := CONTINUE
var _cooldown := 0.0
var _no_thrust := 0.0
var _last_dir := Vector3.ZERO


func _init(n: FlightManeuverNode) -> void:
	node = n


func next_event(sim: FlightSim) -> float:
	if node == null or state != CONTINUE:
		return INF
	var bt := sim.craft.burn_time(node.dv_total())
	return node.time - (bt * 0.5 if bt < INF else 0.0) - LEAD


func update(sim: FlightSim, dt: float) -> void:
	var c := sim.craft
	if state != CONTINUE:
		c.throttle = 0.0
		return
	_cooldown -= dt
	if node == null or not node.valid:
		c.throttle = 0.0
		state = DONE
		return
	if dt > 0.0 and sim.thrust_n > 0.0:
		node.locked = true
		node.burned += sim.accel * dt
	var rem := node.remaining_world()
	var full := Vector3(node.dv_world[0], node.dv_world[1], node.dv_world[2])
	var dv_plan := full.length()
	var left := rem.length()
	var de_plan := node.energy_after - node.energy_before
	var energy_mode := sim.body == node.body and absf(de_plan) > 0.002 * maxf(absf(node.energy_before), 1.0)
	if energy_mode:
		var e_now := (sim.vx * sim.vx + sim.vy * sim.vy + sim.vz * sim.vz) * 0.5 - sim.mu() / sim.radius()
		var progress := (e_now - node.energy_before) / de_plan
		if node.locked and progress >= 1.0:
			c.throttle = 0.0
			state = DONE
			return
		left = maxf(left, (1.0 - progress) * dv_plan)
	elif node.locked and (left < 0.05 or rem.dot(full) <= 0.0):
		c.throttle = 0.0
		state = DONE
		return
	if node.burned.length() > dv_plan * (1.0 + MAX_OVERBURN) + 1.0:
		c.throttle = 0.0
		state = DONE
		return
	var dir := rem / rem.length() if rem.length() > 0.5 else (_last_dir if _last_dir != Vector3.ZERO else full.normalized())
	if energy_mode and rem.dot(full) <= 0.0:
		dir = _last_dir if _last_dir != Vector3.ZERO else full.normalized()
	_last_dir = dir
	c.sas = FlightCraft.Sas.DIRECTION
	sim.command = dir
	var be := c.burn_engines()
	var bt := c.burn_time(dv_plan if not node.locked else left)
	var t_start := node.time - (bt * 0.5 if bt < INF else 0.0)
	var err := rad_to_deg(sim.nose().angle_to(dir))
	var thr := 0.0
	if (sim.t >= t_start or node.locked) and err < ALIGN_DEG + (6.0 if node.locked else 0.0):
		var a_max := float(be["thrust"]) / maxf(c.mass(), 1.0)
		thr = clampf(left / maxf(a_max * 1.5, 1e-3), 0.02, 1.0) if a_max > 0.0 else 1.0
		if err > ALIGN_DEG:
			thr *= 0.25
	c.throttle = thr
	if dt <= 0.0:
		return
	if thr > 0.0 and sim.thrust_n <= 0.0 and not sim.clamped:
		_no_thrust += dt
	else:
		_no_thrust = 0.0
	if _no_thrust > 0.5 and _cooldown <= 0.0 and c.current_stage < c.stage_count - 1:
		_cooldown = 1.5
		_no_thrust = 0.0
		sim.stage()
	elif _no_thrust > 1.0 and float(be["thrust"]) <= 0.0:
		c.throttle = 0.0
		state = ABORT
