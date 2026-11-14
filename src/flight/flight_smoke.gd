class_name FlightSmoke
extends MultiMeshInstance3D
## Exhaust smoke trail and launch clouds as a pool of billboard puffs (MultiMesh +
## shaders/flight_smoke.gdshader, authored in scenes/flight/flight.tscn). Puff positions
## live in the inertial frame in doubles and are re-projected around the floating origin
## every frame, so the trail stays fixed in the air while the world moves under the rocket
## (GPU particles in world space would be dragged along by the origin shifts).

@export var max_puffs := 480

var _px := PackedFloat64Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _s0 := PackedFloat32Array()
var _s1 := PackedFloat32Array()
var _alpha := PackedFloat32Array()
var _tint := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _next := 0
var _count := 0


func _ready() -> void:
	multimesh = multimesh.duplicate() as MultiMesh
	multimesh.instance_count = max_puffs
	multimesh.visible_instance_count = 0
	_px.resize(max_puffs * 3)
	_vel.resize(max_puffs)
	_age.resize(max_puffs)
	_life.resize(max_puffs)
	_s0.resize(max_puffs)
	_s1.resize(max_puffs)
	_alpha.resize(max_puffs)
	_tint.resize(max_puffs)
	_drag.resize(max_puffs)
	for i in max_puffs:
		_life[i] = 0.0


func clear() -> void:
	for i in max_puffs:
		_life[i] = 0.0
	_count = 0
	multimesh.visible_instance_count = 0


## pos: PCI (doubles); vel: m/s in PCI; sizes in metres; tint 0 = white steam, 1 = grey
## smoke; drag (1/s) slows the puff to the still air (0 in vacuum).
func emit(pos: PackedFloat64Array, vel: Vector3, life: float, size_start: float, size_end: float,
		alpha: float, tint := 0.5, drag_k := 1.4) -> void:
	var i := _next
	_next = (_next + 1) % max_puffs
	_px[i * 3] = pos[0]
	_px[i * 3 + 1] = pos[1]
	_px[i * 3 + 2] = pos[2]
	_vel[i] = vel
	_age[i] = 0.0
	_life[i] = life
	_s0[i] = size_start
	_s1[i] = size_end
	_alpha[i] = alpha
	_tint[i] = tint
	_drag[i] = drag_k
	_count = mini(_count + 1, max_puffs)


func update(dt: float, ox: float, oy: float, oz: float, up: Vector3) -> void:
	var n := 0
	var mm := multimesh
	for i in max_puffs:
		if _life[i] <= 0.0:
			continue
		_age[i] += dt
		if _age[i] >= _life[i]:
			_life[i] = 0.0
			continue
		var v := _vel[i] * exp(-_drag[i] * dt) + up * (0.6 * dt * minf(_drag[i], 1.0))
		_vel[i] = v
		_px[i * 3] += v.x * dt
		_px[i * 3 + 1] += v.y * dt
		_px[i * 3 + 2] += v.z * dt
		var f := _age[i] / _life[i]
		var s := lerpf(_s0[i], _s1[i], 1.0 - pow(1.0 - f, 2.2))
		var p := Vector3(_px[i * 3] - ox, _px[i * 3 + 1] - oy, _px[i * 3 + 2] - oz)
		mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * s), p))
		var a := _alpha[i] * smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.55, 1.0, f))
		mm.set_instance_custom_data(n, Color(a, f, _tint[i], float(i % 17) / 17.0))
		n += 1
	mm.visible_instance_count = n
