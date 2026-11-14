class_name FlightBody
extends RefCounted
## Rigid-body state in double precision and the fixed-step integrator.
##
## Translation: kick-drift-kick leapfrog (velocity Verlet) for gravity, which is
## symplectic, so circular orbits keep their radius for many revolutions; thrust, drag
## and contact forces are applied as one full kick per step (evaluated at the start).
## Rotation: body-frame angular velocity, Euler's equations with a diagonal inertia
## tensor, quaternion update by the exact rotation of ω·dt.
## Position / velocity are separate float members (64-bit); orientation and angular
## velocity use Godot types (32-bit is plenty for directions).

var px := 0.0
var py := 0.0
var pz := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
## gravity at the current position (cached between steps for the leapfrog)
var gx := 0.0
var gy := 0.0
var gz := 0.0
var _g_valid := false
## local -> PCI rotation
var q := Quaternion.IDENTITY
## angular velocity in body axes (rad/s)
var w := Vector3.ZERO
## when false gravity is skipped (tests)
var gravity_on := true
## central body of the current sphere of influence (patched conics): gravitational
## parameter, radius, whether its air is modelled and whether it is the launch planet
## (pad contact). Position / velocity are relative to this body.
var mu := FlightOrbit.MU
var body_r := FlightOrbit.R
var atmosphere := true
var home := true


func set_state(pos: PackedFloat64Array, vel: PackedFloat64Array) -> void:
	px = pos[0]
	py = pos[1]
	pz = pos[2]
	vx = vel[0]
	vy = vel[1]
	vz = vel[2]
	_g_valid = false


func pos() -> PackedFloat64Array:
	return PackedFloat64Array([px, py, pz])


func vel() -> PackedFloat64Array:
	return PackedFloat64Array([vx, vy, vz])


func copy_from(o: FlightBody) -> void:
	px = o.px
	py = o.py
	pz = o.pz
	vx = o.vx
	vy = o.vy
	vz = o.vz
	q = o.q
	w = o.w
	mu = o.mu
	body_r = o.body_r
	atmosphere = o.atmosphere
	home = o.home
	_g_valid = false


## Moves the state into another body's frame: offset = [x, y, z, vx, vy, vz] of the old
## central body relative to the new one.
func rebase(offset: PackedFloat64Array, gm: float, r_body: float, air: bool, is_home: bool) -> void:
	px += offset[0]
	py += offset[1]
	pz += offset[2]
	vx += offset[3]
	vy += offset[4]
	vz += offset[5]
	mu = gm
	body_r = r_body
	atmosphere = air
	home = is_home
	_g_valid = false


func radius() -> float:
	return sqrt(px * px + py * py + pz * pz)


func altitude() -> float:
	return radius() - body_r


func speed() -> float:
	return sqrt(vx * vx + vy * vy + vz * vz)


## Unit radial direction (local "up") as a 32-bit vector.
func up() -> Vector3:
	var r := radius()
	return Vector3(px / r, py / r, pz / r)


func velocity_v3() -> Vector3:
	return Vector3(vx, vy, vz)


func vertical_speed() -> float:
	return (px * vx + py * vy + pz * vz) / radius()


func horizontal_speed() -> float:
	var vs := vertical_speed()
	return sqrt(maxf(vx * vx + vy * vy + vz * vz - vs * vs, 0.0))


func _update_gravity() -> void:
	if not gravity_on:
		gx = 0.0
		gy = 0.0
		gz = 0.0
	else:
		var r2 := px * px + py * py + pz * pz
		var k := -mu / (r2 * sqrt(r2))
		gx = px * k
		gy = py * k
		gz = pz * k
	_g_valid = true


## One fixed step. (ax, ay, az): non-gravitational acceleration in PCI (thrust + aero +
## contact) / mass. torque: body frame (N·m). inertia: diagonal, body frame (kg·m²).
func step(dt: float, ax: float, ay: float, az: float, torque := Vector3.ZERO, inertia := Vector3.ONE) -> void:
	if not _g_valid:
		_update_gravity()
	var h := dt * 0.5
	vx += h * gx + dt * ax
	vy += h * gy + dt * ay
	vz += h * gz + dt * az
	px += dt * vx
	py += dt * vy
	pz += dt * vz
	_update_gravity()
	vx += h * gx
	vy += h * gy
	vz += h * gz
	# rotation: I ω' = τ - ω × (I ω)
	var iw := Vector3(inertia.x * w.x, inertia.y * w.y, inertia.z * w.z)
	var rhs := torque - w.cross(iw)
	w += Vector3(rhs.x / inertia.x, rhs.y / inertia.y, rhs.z / inertia.z) * dt
	var ang := w.length() * dt
	if ang > 1e-12:
		q = (q * Quaternion(w.normalized(), ang)).normalized()


## Sets position/velocity from an analytic propagation (on-rails warp).
func set_from_array(s: PackedFloat64Array) -> void:
	px = s[0]
	py = s[1]
	pz = s[2]
	vx = s[3]
	vy = s[4]
	vz = s[5]
	_g_valid = false
