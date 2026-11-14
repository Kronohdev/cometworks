class_name FlightManeuverNode
extends RefCounted
## A planned burn (KSP-style maneuver node): an absolute mission time and a Δv in the
## orbit frame of the trajectory at that time:
##   x = prograde (along the velocity), y = normal (along r x v), z = radial out
##   (prograde x normal: in the orbit plane, away from the body).
## The predictor (FlightTrajectory.predict) fills body / state / dv_world for the
## trajectory the node sits on; FlightWorld accumulates the Δv actually burned.

var time := 0.0
var dv := Vector3.ZERO
## filled by the predictor
var body := -1
var state := PackedFloat64Array()
var dv_world := PackedFloat64Array([0.0, 0.0, 0.0])
var valid := false
## Δv burned towards this node so far (PCI, m/s)
var burned := Vector3.ZERO
## set once the burn starts: dv_world stops following the local Δv
var locked := false
## specific orbital energy just before / after the planned impulse (J/kg, node.body):
## the executor ends energy-changing burns on the energy, which absorbs the losses of a
## long (non-impulsive) burn
var energy_before := 0.0
var energy_after := 0.0
## created by the orbit-insertion planner (FlightCapture): a new insertion plan replaces it
var auto_capture := false


func _init(t := 0.0, dv_local := Vector3.ZERO) -> void:
	time = t
	dv = dv_local


func dv_total() -> float:
	return dv.length()


## Unit prograde / normal / radial-out directions for a state [r, v] (PCI).
static func frame(s: PackedFloat64Array) -> Array[Vector3]:
	var r := Vector3(s[0], s[1], s[2])
	var v := Vector3(s[3], s[4], s[5])
	var pro := v.normalized()
	var nor := r.cross(v).normalized()
	if nor.length_squared() < 0.5:
		nor = pro.cross(Vector3.UP if absf(pro.y) < 0.9 else Vector3.RIGHT).normalized()
	var rad := pro.cross(nor).normalized()
	return [pro, nor, rad]


## World (PCI) Δv vector for a local (prograde, normal, radial) Δv at state s, in doubles.
static func to_world(s: PackedFloat64Array, local: Vector3) -> PackedFloat64Array:
	var rx := s[0]
	var ry := s[1]
	var rz := s[2]
	var vx := s[3]
	var vy := s[4]
	var vz := s[5]
	var vn := sqrt(vx * vx + vy * vy + vz * vz)
	var px := vx / vn
	var py := vy / vn
	var pz := vz / vn
	var hx := ry * vz - rz * vy
	var hy := rz * vx - rx * vz
	var hz := rx * vy - ry * vx
	var hn := sqrt(hx * hx + hy * hy + hz * hz)
	if hn < 1e-9:
		var f := frame(s)
		var o: Vector3 = f[0] * local.x + f[1] * local.y + f[2] * local.z
		return PackedFloat64Array([o.x, o.y, o.z])
	hx /= hn
	hy /= hn
	hz /= hn
	# radial out = prograde x normal
	var qx := py * hz - pz * hy
	var qy := pz * hx - px * hz
	var qz := px * hy - py * hx
	return PackedFloat64Array([px * local.x + hx * local.y + qx * local.z,
		py * local.x + hy * local.y + qy * local.z, pz * local.x + hz * local.y + qz * local.z])


## Δv still to burn (PCI) = planned vector - what was burned.
func remaining_world() -> Vector3:
	return Vector3(dv_world[0], dv_world[1], dv_world[2]) - burned
