class_name FlightPlume
extends Node3D
## Engine plume (layout and materials in scenes/flight/engine_plume.tscn). FlightVessel
## parents one to every engine at its nozzle and calls set_state() each step; this script
## only scales the authored cones and fills the shader's instance uniforms.

## core / edge colours per propellant
const COLORS := {
	"kerolox": [Color(1.0, 0.86, 0.58), Color(1.0, 0.42, 0.1)],
	"hydrolox": [Color(0.86, 0.92, 1.0), Color(0.36, 0.55, 1.0)],
	"methalox": [Color(0.82, 0.86, 1.0), Color(0.5, 0.42, 1.0)],
	"solid": [Color(1.0, 0.96, 0.82), Color(1.0, 0.58, 0.22)],
	"hypergolic": [Color(1.0, 0.8, 0.6), Color(0.95, 0.42, 0.3)],
	"hydrazine": [Color(0.9, 0.92, 1.0), Color(0.6, 0.65, 0.9)],
	"xenon": [Color(0.75, 0.85, 1.0), Color(0.35, 0.5, 1.0)],
}
## plume length per nozzle radius at sea level, full throttle
@export var length_per_radius := 9.0
@export var light_energy := 6.0

var _radius := 0.5
var _length := 5.0
var _seed := 0.0
var _light_color := Color.WHITE

@onready var _scale: Node3D = $Scale
@onready var _flame: MeshInstance3D = $Scale/Flame
@onready var _core: MeshInstance3D = $Scale/Core
@onready var _light: OmniLight3D = $Light


func setup(engine_radius: float, propellant: String, thrust_vac_n: float) -> void:
	if not is_node_ready():
		await ready
	_radius = maxf(engine_radius * 0.62, 0.08)
	# bigger engines get proportionally longer jets (log scale keeps small ones visible)
	var k := clampf(0.75 + 0.12 * log(maxf(thrust_vac_n, 1000.0) / 1.0e5), 0.6, 1.4)
	_length = _radius * length_per_radius * k
	_seed = randf() * 100.0
	var cols: Array = COLORS.get(propellant, COLORS["kerolox"])
	for mi in [_flame, _core]:
		mi.set_instance_shader_parameter("core_color", cols[0])
		mi.set_instance_shader_parameter("edge_color", cols[1])
		mi.set_instance_shader_parameter("seed", _seed)
	_light_color = cols[1].lerp(Color.WHITE, 0.35)
	_light.light_color = _light_color
	_light.omni_range = clampf(_radius * 60.0, 12.0, 120.0)
	set_state(0.0, 1.0)


## throttle 0..1 (0 hides it), pressure = ambient / sea level
func set_state(throttle: float, pressure: float) -> void:
	if not is_node_ready():
		return
	var on := throttle > 0.001
	visible = on
	if not on:
		return
	var expansion := clampf(1.0 - pow(pressure, 0.35), 0.0, 1.0)
	var plume_len := _length * (0.55 + 0.45 * throttle) * (1.0 + expansion * 1.8)
	_scale.scale = Vector3(_radius, plume_len, _radius)
	for mi in [_flame, _core]:
		mi.set_instance_shader_parameter("throttle", throttle)
		mi.set_instance_shader_parameter("expansion", expansion)
	_light.position = Vector3(0, -plume_len * 0.25, 0)
	_light.light_energy = light_energy * throttle * (1.0 - 0.6 * expansion)
