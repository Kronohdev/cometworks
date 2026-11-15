class_name RoverController
extends Node3D
## The rover on a planet surface (scenes/rover/rover.tscn): a custom kinematic controller made
## for the voxel terrain, simple and fun rather than a rigid body.
##   ground   surface(): the 1 m voxel tops (height_fn, the terrain's get_height) plus the half-block
##            step slabs the terrain draws in front of every rise of exactly one block
##            (VoxelGreedyMesher "steps"), so a 1 m step is two 0.5 m steps; each wheel rides the
##            highest surface under its patch, eased by distance (it rolls up a slab, never pops),
##            and ignores rises of 2+ blocks (walls); pitch and roll come from the four wheels, the
##            belly rides over anything that pokes up between them (never inside the blocks)
##   motion   throttle / steer accelerate along the heading; traction is limited by the body's
##            gravity (floaty on the Moon) and by the chassis' climb angle (judged on ground(), the
##            ground smoothed over 6 m): past it the wheels slip and the rover slides back; the move
##            is split in substeps of SUBSTEP m and the rover's footprint (wheels and body) may not
##            enter ground higher than its contact plane + the chassis' step (a wall): it slides
##            along the wall or stops at its face, turning into one is refused too, at any speed or
##            frame rate; drive off a crest faster than gravity pulls and it flies (low gravity
##            jumps), the hopper hops on purpose
##   power    battery Wh += (panels x sunlight + RTG - idle - instruments - drive) x game time
##            (rovers.json time_scale game seconds per real second); empty: it only crawls on what
##            the panels give
##   tools    use_tool(): photo, panorama, scan, drill, sample, weather, drone, hop; it acts on the
##            nearest SurfaceInteractable in reach (the world side's points of interest) or on the
##            ground, and reports to SurfaceSession.current; the message comes back after the
##            radio delay (flavour: a few seconds at most, Mars says "minutes")
## physics_step(dt) is the whole simulation (deterministic, no physics server), so tests drive it
## headless with a height function; _physics_process only reads the keyboard and calls it.

signal message(key: String, args: Array, tone: String)
signal tool_started(tool: StringName, seconds: float)
signal tool_done(tool: StringName, result: Dictionary)
signal landed(impact: float)
signal poi_reached(poi: Node)

## tool -> Wh it costs
const TOOL_WH := {&"photo": 0.2, &"panorama": 0.8, &"scan": 0.6, &"drill": 2.5, &"sample": 0.6, &"weather": 0.1,
	&"drone": 1.5}
## tool -> seconds the rover is busy (cannot drive)
const TOOL_BUSY := {&"photo": 0.6, &"panorama": 3.0, &"scan": 1.2, &"drill": 3.0, &"sample": 1.8, &"weather": 0.6,
	&"drone": 4.0}
## how far a tool reaches a point of interest (m); reach_radius of the POI counts too
const TOOL_RANGE := {&"photo": 30.0, &"panorama": 0.0, &"scan": 14.0, &"drill": 0.0, &"sample": 0.0, &"weather": 0.0,
	&"drone": 160.0}
const GROUND_CELL := 24.0
## height of the terrain's step slab in front of a rise of exactly one block (m)
const STEP_SLAB := 0.5
## a wheel feels the surface this far around its contact point (m), lower by distance x WHEEL_EASE
const WHEEL_REACH := 0.5
const WHEEL_EASE := 1.0
## the longest move checked against walls at once (m)
const SUBSTEP := 0.2
## a rise above this under a wheel is a wall, not something it rolls onto (m)
const WALL_RISE := 1.05
## the ground falling this far below the body's ballistic path lifts the wheels off (m)
const LIFT_OFF := 0.3

@export var model_path: NodePath = ^"Model"
## read the keyboard (off for tests and the automatic mode)
@export var player_input := true

var design: Dictionary = {}
var stats: Dictionary = {}
var chassis: Dictionary = {}
var body_id := "moon"
var gravity := 1.62
var has_air := false
## 0..1 light on the panels (sunlight of the body x sun height)
var sun_factor := 1.0
## Callable(x: float, z: float) -> float: the voxel top under (x, z)
var height_fn: Callable
var time_scale := 20.0
## seconds a tool's answer takes to come back (radio delay shown, capped for fun)
var reply_delay := 1.0
var interactables: Array[Node] = []

var throttle := 0.0
var steer := 0.0
var braking := false

var speed := 0.0
var yaw := 0.0
var vy := 0.0
var airborne := false
var battery_wh := 0.0
var distance := 0.0
var pitch := 0.0
var roll := 0.0
var slipping := false
## the ground's slope along the heading (radians, + uphill), over 6 m
var slope := 0.0
var blocked := false
var busy := 0.0
var busy_tool: StringName = &""
var samples_held := 0
var drone_flying := 0.0
var power_in := 0.0
var power_out := 0.0

var _model: Node3D
var _hcache := {}
var _queue: Array[Dictionary] = []
var _wheels: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _thrusters: Array[Node3D] = []
var _anim := {}
var _gait := 0.0
var _hop_flame := 0.0
var _low_warned := false


func _ready() -> void:
	_model = get_node_or_null(model_path) as Node3D


## Sets the rover up: its design, the body it drives on and the ground.
func setup(d: Dictionary, body: String, g: float, sun: float, heights: Callable, air := false) -> void:
	design = RoverDesign.normalize(d)
	body_id = body
	gravity = maxf(g, 0.05)
	sun_factor = clampf(sun, 0.0, 8.0)
	height_fn = heights
	has_air = air
	time_scale = RoverDesign.time_scale()
	chassis = RoverDesign.chassis(String(design["chassis"]))
	stats = RoverDesign.stats(design, body_id)
	battery_wh = float(stats["store"])
	_hcache.clear()
	if _model == null:
		_model = get_node_or_null(model_path) as Node3D
	if _model:
		RoverDesign.assemble(design, _model)
		_collect_anim_nodes()
	var b := RoverDesign.body(body_id)
	reply_delay = clampf(float(b.get("delay_s", 1.0)) * 2.0, 0.3, 3.0)


func has_tool(tool: StringName) -> bool:
	return RoverDesign.has_tool(design, String(tool))


## Puts the rover on the ground at (x, z) facing `heading` (radians, 0 = -Z).
func place(x: float, z: float, heading := 0.0) -> void:
	yaw = heading
	speed = 0.0
	vy = 0.0
	airborne = false
	var c := contact(Vector3(x, 0.0, z), heading)
	position = Vector3(x, c["center"], z)
	_pose_from(c)
	_orient(1.0)


func power_frac() -> float:
	var store := float(stats.get("store", 0.0))
	if store <= 0.0:
		return 1.0 if gen_now() >= float(stats.get("use", 0.0)) else 0.0
	return clampf(battery_wh / store, 0.0, 1.0)


## Watts the panels and the RTG give now.
func gen_now() -> float:
	var solar := float(stats.get("gen", 0.0)) - float(stats.get("rtg", 0.0))
	return solar * sun_factor + float(stats.get("rtg", 0.0))


func max_speed() -> float:
	return float(chassis.get("speed", 3.0))


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


# ------------------------------------------------------------ ground
func _voxel_top(ix: int, iz: int) -> float:
	var k := Vector2i(ix, iz)
	if _hcache.has(k):
		return _hcache[k]
	var h := float(height_fn.call(float(ix) + 0.5, float(iz) + 0.5)) if height_fn.is_valid() else 0.0
	if _hcache.size() > 40000:
		_hcache.clear()
	_hcache[k] = h
	return h


## Bilinear between voxel-top cell centres.
func ground_bilinear(x: float, z: float) -> float:
	var fx := x - 0.5
	var fz := z - 0.5
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(_voxel_top(ix, iz), _voxel_top(ix + 1, iz), tx)
	var b := lerpf(_voxel_top(ix, iz + 1), _voxel_top(ix + 1, iz + 1), tx)
	return lerpf(a, b, tz)


## The ground smoothed over a 1 m patch (bilinear between cell centres): slopes, the camera.
func ground(x: float, z: float) -> float:
	return 0.25 * (ground_bilinear(x - 0.5, z - 0.5) + ground_bilinear(x + 0.5, z - 0.5)
		+ ground_bilinear(x - 0.5, z + 0.5) + ground_bilinear(x + 0.5, z + 0.5))


## The solid surface at (x, z) exactly as the terrain draws it: the column's voxel top, or half
## a block higher on the half of the column next to a neighbour exactly one block higher (the
## step slab, see VoxelGreedyMesher "steps").
func surface(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var h := _voxel_top(ix, iz)
	var nx := _voxel_top(ix + (1 if x - ix >= 0.5 else -1), iz)
	var nz := _voxel_top(ix, iz + (1 if z - iz >= 0.5 else -1))
	if absf(nx - h - 1.0) < 0.05 or absf(nz - h - 1.0) < 0.05:
		return h + STEP_SLAB
	return h


## The height a wheel rides at on (x, z): the highest surface within WHEEL_REACH, eased by its
## distance (so the wheel rolls up a slab or a step instead of popping); rises taller than
## WALL_RISE are walls and do not lift it.
func wheel_ground(x: float, z: float) -> float:
	var base := surface(x, z)
	var best := base
	var st := WHEEL_REACH * 0.5
	for j in 5:
		for i in 5:
			if i == 2 and j == 2:
				continue
			var ox := (i - 2) * st
			var oz := (j - 2) * st
			var d := sqrt(ox * ox + oz * oz)
			if d > WHEEL_REACH + 0.001:
				continue
			var h := surface(x + ox, z + oz)
			if h - base > WALL_RISE:
				continue
			best = maxf(best, h - d * WHEEL_EASE)
	return best


## Belly height above the wheels' contact plane (m).
func clearance() -> float:
	return float(chassis.get("clearance", 0.44))


## Footprint half extents (along, across): the wheels and the body.
func footprint() -> Vector2:
	return Vector2(float(chassis.get("wheelbase", 2.0)) * 0.5 + 0.08, float(chassis.get("track", 1.6)) * 0.5 + 0.17)


## {"center", "front", "rear", "left", "right", "lift"} ground heights under the wheels at p with
## heading `heading` (default: the rover's): the wheels' heights, raised by "lift" where the
## ground under the body pokes above the belly.
func contact(p: Vector3, heading := NAN) -> Dictionary:
	var a := yaw if is_nan(heading) else heading
	var f := Vector3(-sin(a), 0.0, -cos(a))
	var r := Vector3(cos(a), 0.0, -sin(a))
	var wb := float(chassis.get("wheelbase", 2.0))
	var tw := float(chassis.get("track", 1.6))
	var hl := wb * 0.5
	var ht := tw * 0.5
	var fl := wheel_ground(p.x + f.x * hl - r.x * ht, p.z + f.z * hl - r.z * ht)
	var fr := wheel_ground(p.x + f.x * hl + r.x * ht, p.z + f.z * hl + r.z * ht)
	var rl := wheel_ground(p.x - f.x * hl - r.x * ht, p.z - f.z * hl - r.z * ht)
	var rr := wheel_ground(p.x - f.x * hl + r.x * ht, p.z - f.z * hl + r.z * ht)
	var c := {"center": (fl + fr + rl + rr) * 0.25, "front": (fl + fr) * 0.5, "rear": (rl + rr) * 0.5,
		"left": (fl + rl) * 0.5, "right": (fr + rr) * 0.5, "lift": 0.0}
	# the belly: what pokes up between the wheels lifts the whole rover (it rides on it)
	var kp: float = (c["front"] - c["rear"]) / wb
	var kr: float = (c["left"] - c["right"]) / tw
	var top: float = c["center"] + clearance()
	var lift := 0.0
	# the four wheels are not always on one plane: it rests on the highest ones (none sinks)
	for w in [[hl, -ht, fl], [hl, ht, fr], [-hl, -ht, rl], [-hl, ht, rr]]:
		lift = maxf(lift, float(w[2]) - (float(c["center"]) + float(w[0]) * kp - float(w[1]) * kr))
	var na := maxi(ceili(wb / 0.25), 2)
	var nb := maxi(ceili(tw * 0.75 / 0.25), 2)
	# between two samples the plane can dip by up to this under a block edge: keep that margin
	var margin := absf(kp) * wb / na + absf(kr) * tw * 0.75 / nb
	for j in na + 1:
		var al := -hl + wb * j / na
		for i in nb + 1:
			var bl := -tw * 0.375 + tw * 0.75 * i / nb
			var h := surface(p.x + f.x * al + r.x * bl, p.z + f.z * al + r.z * bl)
			lift = maxf(lift, h + margin - (top + al * kp - bl * kr))
	if lift > 0.0:
		for k in ["center", "front", "rear", "left", "right"]:
			c[k] = float(c[k]) + lift
		c["lift"] = lift
	return c


## True when the rover's footprint at (p, heading) enters ground higher than the plane
## y + along * kp - across * kr plus `rise` (a wall), sampled every 0.5 m around its outline
## and along its middle.
func hits_wall(p: Vector3, heading: float, y: float, kp: float, kr: float, rise: float) -> bool:
	var f := Vector3(-sin(heading), 0.0, -cos(heading))
	var r := Vector3(cos(heading), 0.0, -sin(heading))
	var fp := footprint()
	var na := maxi(ceili(fp.x * 2.0 / 0.5), 2)
	var nb := maxi(ceili(fp.y * 2.0 / 0.5), 2)
	for j in na + 1:
		var al := -fp.x + fp.x * 2.0 * j / na
		var edge_a := j == 0 or j == na
		for i in nb + 1:
			if not edge_a and i != 0 and i != nb and i * 2 != nb:
				continue
			var bl := -fp.y + fp.y * 2.0 * i / nb
			var h := surface(p.x + f.x * al + r.x * bl, p.z + f.z * al + r.z * bl)
			if h > y + al * kp - bl * kr + rise:
				return true
	return false


## The slope (radians, + uphill) along `fw` over 6 m centred on p, on the surface the wheels
## drive (walls taller than WALL_RISE, which stop the rover, do not count as a slope).
func drive_slope(p: Vector3, fw: Vector3) -> float:
	var prev := surface(p.x - fw.x * 3.0, p.z - fw.z * 3.0)
	var rise := 0.0
	for k in range(1, 13):
		var d := -3.0 + k * 0.5
		var h := surface(p.x + fw.x * d, p.z + fw.z * d)
		if absf(h - prev) <= WALL_RISE:
			rise += h - prev
		prev = h
	return atan2(rise, 6.0)


## The tallest rise the footprint drives onto (m), from the chassis' step.
func step_rise() -> float:
	return clampf(float(chassis.get("step", 0.9)) * 0.7, 0.6, 1.15)


# ------------------------------------------------------------ simulation
func _physics_process(delta: float) -> void:
	if player_input:
		_read_input()
	physics_step(delta)
	_animate(delta)


func _read_input() -> void:
	var t := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		t += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		t -= 1.0
	var s := 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		s += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		s -= 1.0
	throttle = t
	steer = s
	braking = Input.is_physical_key_pressed(KEY_SPACE) and not has_tool(&"hop")


## One step of the rover (dt in real seconds).
func physics_step(dt: float) -> void:
	if dt <= 0.0:
		return
	_tick_queue(dt)
	busy = maxf(busy - dt, 0.0)
	if busy <= 0.0:
		busy_tool = &""
	drone_flying = maxf(drone_flying - dt, 0.0)
	var p := position
	# power
	var vmax := max_speed()
	var drive_w := float(chassis.get("drive_power", 20.0)) * clampf(absf(speed) / maxf(vmax, 0.1), 0.0, 1.0)
	power_in = gen_now()
	power_out = float(stats.get("use", 0.0)) + drive_w
	var store := float(stats.get("store", 0.0))
	battery_wh = clampf(battery_wh + (power_in - power_out) * dt * time_scale / 3600.0, 0.0, store)
	var powered := battery_wh > 0.001 or power_in >= power_out
	var limit := vmax
	if not powered:
		# crawl on what the panels give
		limit = vmax * clampf(power_in / maxf(float(stats.get("use", 0.0)) + float(chassis.get("drive_power", 20.0)), 0.001), 0.0, 1.0) * 0.5
	if store > 0.0:
		var frac := battery_wh / store
		if frac < 0.15 and not _low_warned:
			_low_warned = true
			message.emit("RV_MSG_BATTERY_LOW", [], "warn")
		elif frac > 0.3:
			_low_warned = false
	# drive
	var grip := float(chassis.get("grip", 1.0))
	var g := gravity
	slipping = false
	blocked = false
	if not airborne:
		var target := 0.0
		if busy <= 0.0:
			target = throttle * (limit if throttle >= 0.0 else limit * 0.5)
		var traction := minf(2.6, 0.85 * g * grip + 0.4)
		var drive_acc := clampf((target - speed) * 3.0, -traction, traction)
		if (braking or throttle == 0.0) and busy <= 0.0:
			drive_acc = clampf(-speed * 4.0, -traction * 1.5, traction * 1.5)
		if busy > 0.0:
			drive_acc = clampf(-speed * 6.0, -traction * 2.0, traction * 2.0)
		# climbing: past the chassis' climb angle the wheels cannot hold the slope
		# the slope the climb is judged on: 6 m along the heading, so one voxel step is a bump
		var climb := deg_to_rad(float(chassis.get("climb", 25.0)))
		var along := drive_slope(p, forward())
		slope = along
		var grav_acc := -g * sin(along)
		if absf(along) > climb:
			slipping = true
			var hold := g * sin(climb)
			drive_acc = clampf(drive_acc, -hold, hold)
		elif throttle == 0.0 or braking:
			grav_acc = 0.0  # parked: the brakes hold
		speed += (drive_acc + grav_acc) * dt
		speed = clampf(speed, -vmax, vmax * 1.6)
		# steering: turns harder at speed, in place for legs
		var turn := 1.25 if String(design.get("chassis", "")) != "walker" else 0.9
		var sp := clampf(absf(speed) / 1.5, 0.3, 1.0)
		if busy <= 0.0 and steer != 0.0:
			var want := yaw - steer * turn * sp * dt * (1.0 if speed >= -0.05 else -1.0)
			# turning a corner of the rover into a wall is refused (unless it is already stuck in one)
			if not _hits_from(p, want) or _hits_from(p, yaw):
				yaw = want
	# move: substeps short enough that no wall is skipped, the footprint stops at a wall's face
	# or slides along it
	var np := p
	var total := speed * dt
	var n := clampi(ceili(absf(total) / SUBSTEP), 1, 64)
	var fw2 := forward()
	for i in n:
		var stepv := fw2 * (total / n)
		var q := np + stepv
		if not _hits_from(q, yaw):
			np = q
			continue
		if _hits_from(np, yaw):
			np = q  # already stuck in a wall (spawned in one): let it drive out
			continue
		# slide: keep the part of the step along the wall
		var qx := np + Vector3(stepv.x, 0.0, 0.0)
		var qz := np + Vector3(0.0, 0.0, stepv.z)
		var ox := absf(stepv.x) > 0.001 and not _hits_from(qx, yaw)
		var oz := absf(stepv.z) > 0.001 and not _hits_from(qz, yaw)
		if ox and (not oz or absf(stepv.x) >= absf(stepv.z)):
			np = qx
			speed *= 1.0 - minf(dt * 4.0, 0.5) / n
		elif oz:
			np = qz
			speed *= 1.0 - minf(dt * 4.0, 0.5) / n
		else:
			blocked = true
			speed = 0.0
			break
	var c2 := contact(np)
	var gy: float = c2["center"]
	if airborne:
		vy -= g * dt
		np.y = p.y + vy * dt
		if np.y <= gy:
			var impact := -vy
			np.y = gy
			vy = 0.0
			airborne = false
			landed.emit(impact)
	else:
		# the ground falls away faster than gravity can pull: the springs stretch a little (the
		# body glides over the dips between steps), past LIFT_OFF the wheels leave it: fly
		var vyb := vy - g * dt
		var yb := p.y + vyb * dt
		if yb > gy + LIFT_OFF and absf(speed) > 0.5:
			airborne = true
			vy = vyb
			np.y = yb
		elif yb > gy:
			vy = vyb
			np.y = yb
		else:
			# what carries on if the ground drops away: the climb of the slope driven (not the
			# jolt of a wheel rolling up a step, nor the belly riding onto a block)
			vy = clampf((gy - p.y) / dt, -20.0, maxf(speed * sin(slope), 0.0) + 0.2)
			np.y = gy
	if not airborne:
		_pose_from(c2)
	else:
		# in the air the body levels out to the ground below, fully once it is close (so a wheel
		# never dips into a step it flies over)
		var p0 := pitch
		var r0 := roll
		_pose_from(c2)
		var w := 1.0 if np.y - gy < 0.8 else clampf(dt * 3.0, 0.0, 1.0)
		pitch = lerpf(p0, pitch, w)
		roll = lerpf(r0, roll, w)
	distance += Vector2(np.x - p.x, np.z - p.z).length()
	position = np
	_orient(clampf(dt * 10.0, 0.0, 1.0))
	_check_reach()
	_check_drive_objectives()


## True when the footprint at (q, heading) runs into a wall, judged from the current pose: on the
## ground, the contact plane (pitch, roll) plus the chassis' step; in the air, the rover's height
## plus a slab.
func _hits_from(q: Vector3, heading: float) -> bool:
	if airborne:
		return hits_wall(q, heading, position.y, 0.0, 0.0, STEP_SLAB + 0.05)
	var kp := tan(pitch)
	var kr := tan(roll)
	var d := q - position
	var y := position.y + d.dot(forward()) * kp - d.dot(right()) * kr
	return hits_wall(q, heading, y, kp, kr, step_rise())


## pitch and roll from a contact() (roll + = the left side higher).
func _pose_from(c: Dictionary) -> void:
	pitch = atan2(float(c["front"]) - float(c["rear"]), float(chassis.get("wheelbase", 2.0)))
	roll = atan2(float(c["left"]) - float(c["right"]), float(chassis.get("track", 1.6)))


func _orient(w: float) -> void:
	# roll + raises the left side: a turn about the rover's back axis by -roll
	var target := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, -roll)
	var cur := transform.basis.orthonormalized()
	transform.basis = cur.slerp(target.orthonormalized(), w) if w < 1.0 else target


## The hopper's jump (low gravity only).
func hop() -> Dictionary:
	var h: Dictionary = stats.get("hop", {})
	if h.is_empty():
		return _fail(&"hop", "RV_MSG_NO_TOOL")
	if airborne:
		return _fail(&"hop", "")
	if gravity > float(h.get("max_gravity", 4.0)):
		return _fail(&"hop", "RV_MSG_NO_HOP")
	var wh := float(h.get("wh", 3.0))
	if battery_wh < wh and float(stats.get("store", 0.0)) > 0.0:
		return _fail(&"hop", "RV_MSG_BATTERY_EMPTY")
	battery_wh -= wh
	vy = sqrt(2.0 * gravity * float(h.get("height", 5.0)))
	speed = float(h.get("speed", 6.0)) * (1.0 if throttle >= 0.0 else -0.5)
	airborne = true
	_hop_flame = 0.6
	var res := {"ok": true, "message_key": "RV_MSG_HOP", "science": 0.0, "objective": ""}
	tool_done.emit(&"hop", res)
	return res


# ------------------------------------------------------------ points of interest
func refresh_interactables() -> void:
	if is_inside_tree():
		interactables.assign(get_tree().get_nodes_in_group(SurfaceSession.GROUP))


func _check_reach() -> void:
	for n in interactables:
		if not is_instance_valid(n) or bool(n.get("was_reached")):
			continue
		if n.call("in_reach", position):
			var res: Dictionary = n.call("reached", self)
			poi_reached.emit(n)
			if String(res.get("objective", "")) != "":
				_say_objective(StringName(res["objective"]))


func _check_drive_objectives() -> void:
	var s := SurfaceSession.current
	if s == null:
		return
	s.distance = distance
	for o in s.objectives:
		if not o["done"] and o["kind"] == &"drive" and distance >= float(o.get("amount", 100.0)):
			if s.report_objective(o["id"]):
				_say_objective(o["id"])


## The nearest point of interest a tool reaches that accepts it (null if none).
func nearest_for(tool: StringName) -> Node:
	# an open objective first, then a POI this tool has not used yet, then the nearest
	var best: Node = null
	var best_score := INF
	var extra := float(TOOL_RANGE.get(tool, 0.0))
	var s := SurfaceSession.current
	for n in interactables:
		if not is_instance_valid(n) or not n.call("accepts", tool):
			continue
		var d := _pos_of(n).distance_to(position)
		var reach := float(n.get("reach_radius")) + extra
		if d > reach:
			continue
		var score := d
		if s == null or s.objective_for(n, tool).is_empty():
			score += 1000.0
		if (n.get("used") as Dictionary).has(tool):
			score += 500.0
		if score < best_score:
			best = n
			best_score = score
	return best


# ------------------------------------------------------------ tools
## Uses a tool ("photo", "panorama", "scan", "drill", "sample", "weather", "drone", "hop").
## Returns {"ok", "message_key", "science", "objective"}; the message is emitted after the
## radio delay (tool_started says how long).
func use_tool(tool: StringName) -> Dictionary:
	if tool == &"hop":
		return hop()
	if busy > 0.0:
		return _fail(tool, "")
	var need := tool
	if tool == &"panorama":
		need = &"photo"
	if not has_tool(need):
		return _fail(tool, "RV_MSG_NO_TOOL")
	var wh := float(TOOL_WH.get(tool, 0.5))
	if float(stats.get("store", 0.0)) > 0.0 and battery_wh < wh and gen_now() < float(stats.get("use", 0.0)):
		return _fail(tool, "RV_MSG_BATTERY_EMPTY")
	if (tool == &"drill" or tool == &"sample") and absf(speed) > 0.4:
		return _fail(tool, "RV_MSG_NEED_STOP")
	if tool == &"drone" and not has_air:
		return _fail(tool, "RV_MSG_NO_AIR")
	if tool == &"sample" and int(stats.get("sample_capacity", 0)) > 0 and samples_held >= int(stats["sample_capacity"]):
		return _fail(tool, "RV_MSG_CACHE_FULL")
	battery_wh = maxf(battery_wh - wh, 0.0)
	busy = float(TOOL_BUSY.get(tool, 1.0))
	busy_tool = tool
	var s := SurfaceSession.current
	var res := {"ok": true, "message_key": "RV_MSG_" + String(tool).to_upper(), "science": 0.0, "objective": ""}
	var base := _tool_science(need)
	match tool:
		&"panorama", &"weather":
			var o := s.free_objective(tool) if s else {}
			if not o.is_empty() and s.report_objective(o["id"]):
				res["objective"] = String(o["id"])
			var mult := 2.0 if tool == &"weather" and has_air else 1.0
			res["science"] = s.credit_once(StringName("%s@%s" % [tool, _cell_id()]), tool, base * mult) if s else base * mult
		&"drone":
			drone_flying = 12.0
			var found := 0
			for n in interactables:
				if is_instance_valid(n) and _pos_of(n).distance_to(position) <= float(TOOL_RANGE[&"drone"]):
					n.set_meta("revealed", true)
					found += 1
					if s:
						var od := s.objective_for(n, &"drone")
						if not od.is_empty() and s.report_objective(od["id"]):
							res["objective"] = String(od["id"])
			var fo := s.free_objective(&"drone") if s else {}
			if not fo.is_empty() and s.report_objective(fo["id"]):
				res["objective"] = String(fo["id"])
			res["science"] = s.credit_once(StringName("drone@%s" % _cell_id()), tool, base) if s else base
			res["found"] = found
		_:
			var poi := nearest_for(tool)
			if poi:
				var r: Dictionary = poi.call("interact", self, tool)
				res["ok"] = bool(r.get("ok", false))
				res["science"] = float(r.get("science", 0.0))
				res["objective"] = String(r.get("objective", ""))
				if String(r.get("message_key", "")) != "":
					res["message_key"] = String(r["message_key"])
				res["poi"] = String(poi.call("get_interact_id"))
			else:
				# no point of interest: the plain ground still teaches a little, once per area
				var o2 := s.free_objective(tool) if s else {}
				if not o2.is_empty() and s.report_objective(o2["id"]):
					res["objective"] = String(o2["id"])
				res["science"] = s.credit_once(StringName("ground@%s" % _cell_id()), tool, base * 0.35) if s else base * 0.35
				res["message_key"] = "RV_MSG_%s_GROUND" % String(tool).to_upper()
			if tool == &"sample" and bool(res["ok"]):
				samples_held += 1
	if s:
		s.note_action(tool, res)
	tool_started.emit(tool, reply_delay)
	_queue.append({"t": reply_delay, "tool": tool, "res": res})
	return res


static func _pos_of(n: Node) -> Vector3:
	var n3 := n as Node3D
	return n3.global_position if n3.is_inside_tree() else n3.position


func _tool_science(tool: StringName) -> float:
	for id in design.get("parts", []):
		var p := RoverDesign.part(String(id))
		if StringName(p.get("tool", "")) == tool:
			return float(p.get("science", 5.0))
	return 5.0


func _cell_id() -> String:
	return "%d:%d" % [floori(position.x / GROUND_CELL), floori(position.z / GROUND_CELL)]


func _fail(tool: StringName, key: String) -> Dictionary:
	var res := {"ok": false, "message_key": key, "science": 0.0, "objective": ""}
	if key != "":
		message.emit(key, [], "bad")
	tool_done.emit(tool, res)
	return res


func _say_objective(id: StringName) -> void:
	var s := SurfaceSession.current
	var o := s.objective(id) if s else {}
	message.emit("RV_MSG_OBJECTIVE", [String(o.get("label_key", id))], "star")


func _tick_queue(dt: float) -> void:
	for q in _queue.duplicate():
		q["t"] = float(q["t"]) - dt
		if float(q["t"]) <= 0.0:
			_queue.erase(q)
			var res: Dictionary = q["res"]
			if String(res.get("message_key", "")) != "":
				message.emit(String(res["message_key"]), [], "good" if res.get("ok", false) else "bad")
			if float(res.get("science", 0.0)) > 0.0:
				message.emit("RV_MSG_SCIENCE", [roundi(float(res["science"]))], "science")
			if String(res.get("objective", "")) != "":
				_say_objective(StringName(res["objective"]))
			tool_done.emit(StringName(q["tool"]), res)


## Delivers every pending tool answer now (tests, leaving the surface).
func flush_replies() -> void:
	for q in _queue:
		q["t"] = 0.0
	_tick_queue(0.0)


# ------------------------------------------------------------ look
func _collect_anim_nodes() -> void:
	_wheels.clear()
	_legs.clear()
	_thrusters.clear()
	_anim.clear()
	for n in _model.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Wheel"):
			_wheels.append(n)
		elif nm.begins_with("Leg") and not nm.begins_with("LegStrut"):
			_legs.append(n)
			n.set_meta("rest", (n as Node3D).rotation)
		elif nm.begins_with("Thruster"):
			_thrusters.append(n)
		elif nm in ["Head", "Bit", "Spinner", "Rotor1", "Rotor2", "Craft", "Dish", "ArmUpper"]:
			_anim[nm] = n
			n.set_meta("rest_pos", (n as Node3D).position)
			n.set_meta("rest_rot", (n as Node3D).rotation)


func _animate(dt: float) -> void:
	if _model == null:
		return
	var spin := speed * dt / 0.38
	for w in _wheels:
		w.rotate_object_local(Vector3.RIGHT, -spin)
	_gait += absf(speed) * dt * 3.0 + absf(steer) * dt * 2.0
	for i in _legs.size():
		var rest: Vector3 = _legs[i].get_meta("rest", Vector3.ZERO)
		var ph := _gait + (PI if i % 2 == 0 else 0.0)
		_legs[i].rotation = rest + Vector3(sin(ph) * 0.35, 0.0, maxf(cos(ph), 0.0) * 0.12 * (1.0 if i % 2 == 0 else -1.0))
	_hop_flame = maxf(_hop_flame - dt, 0.0)
	for t in _thrusters:
		var fl := t.get_node_or_null("Flame") as Node3D
		if fl:
			fl.visible = _hop_flame > 0.0 or (airborne and vy > 0.0)
	var head := _anim.get("Head") as Node3D
	if head:
		var target_yaw := 0.0
		if busy_tool == &"panorama":
			target_yaw = (1.0 - busy / float(TOOL_BUSY[&"panorama"])) * TAU
			head.rotation.y = target_yaw
		else:
			head.rotation.y = lerp_angle(head.rotation.y, 0.0, clampf(dt * 4.0, 0.0, 1.0))
	var bit := _anim.get("Bit") as Node3D
	if bit:
		var rest_p: Vector3 = bit.get_meta("rest_pos", Vector3.ZERO)
		if busy_tool == &"drill":
			bit.rotate_object_local(Vector3.UP, dt * 18.0)
			bit.position = rest_p + Vector3(0.0, -0.35 * sin(minf(busy, 3.0) / 3.0 * PI), 0.0)
		else:
			bit.position = bit.position.lerp(rest_p, clampf(dt * 5.0, 0.0, 1.0))
	var spinner := _anim.get("Spinner") as Node3D
	if spinner:
		spinner.rotate_object_local(Vector3.UP, dt * (6.0 if has_air else 0.4))
	var craft := _anim.get("Craft") as Node3D
	if craft:
		var rest_c: Vector3 = craft.get_meta("rest_pos", Vector3.ZERO)
		var up := 0.0
		if drone_flying > 0.0:
			up = minf(12.0 - drone_flying, drone_flying) * 3.0
			up = clampf(up, 0.0, 9.0)
			var t := Time.get_ticks_msec() / 1000.0
			craft.position = rest_c + Vector3(sin(t * 0.8) * up * 0.5, up, cos(t * 0.8) * up * 0.5)
		else:
			craft.position = craft.position.lerp(rest_c, clampf(dt * 3.0, 0.0, 1.0))
		for rn in ["Rotor1", "Rotor2"]:
			var r := _anim.get(rn) as Node3D
			if r:
				r.rotate_object_local(Vector3.UP, dt * (40.0 if drone_flying > 0.0 else 0.0) * (1.0 if rn == "Rotor1" else -1.0))
	var arm := _anim.get("ArmUpper") as Node3D
	if arm:
		var rr: Vector3 = arm.get_meta("rest_rot", Vector3.ZERO)
		if busy_tool == &"sample" or busy_tool == &"scan":
			arm.rotation = rr + Vector3(-0.6 * sin(minf(busy, 1.8) / 1.8 * PI), 0.0, 0.0)
		else:
			arm.rotation = arm.rotation.lerp(rr, clampf(dt * 4.0, 0.0, 1.0))
