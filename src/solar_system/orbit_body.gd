@tool
class_name SolarBody
extends Node3D
## One body of the solar-system map (Sun, planet, dwarf planet or moon). All visuals are
## authored in scenes/solar_system/solar_system.tscn; this script only animates them.
##
## Node layout under this node (the node itself is the ORBIT PLANE: its basis holds the
## orbital inclination around the line of nodes):
##   OrbitLine        MeshInstance3D, 2x2 plane scaled to orbit_radius (solar_orbit shader)
##   Pivot            rotates about +Y = orbital motion (angle = mean longitude)
##     Anchor         sits at (orbit_radius, 0, 0). Counter-rotated by -angle so the spin
##                    axis keeps a fixed direction in space (seasons!). Tidally locked
##                    bodies skip the counter-rotation, so their -X side always faces the parent.
##       Tilt         axial tilt (rotation about X)
##         Spin       rotation about the body's own axis -> LOD0 / LOD1 / LOD2 meshes
##         CloudSpin  (optional) cloud shell, spins a little faster than the surface
##         Rings / Atmosphere (optional, do not spin)
##       Label        Label3D name tag (text set by SolarSystem from translation keys)
##       <moons>      child SolarBody nodes, orbiting this body
##
## Animation: angular speeds come from the real periods times `time_scale` (simulated days
## per real second). Fast spinners/orbiters are soft-clamped (tanh) to max_*_speed so the
## map never strobes at high time scales; slow motion stays exact.

@export var body_id := ""
## Translation key of the display name (i18n/solar_system_strings.csv).
@export var name_key := ""
@export_group("Orbit")
## Visual orbit radius (scene units) around the parent; 0 for the Sun.
@export var orbit_radius := 0.0
@export var orbital_period_days := 0.0
## Mean longitude at J2000 (degrees): with sim_days it gives the real heliocentric angle.
@export var phase_deg := 0.0
@export var tidally_locked := false
@export_group("Body")
@export var visual_radius := 1.0
## Sidereal rotation period in hours (sign ignored: retrograde spin comes from tilt > 90 deg).
@export var rotation_period_hours := 24.0
@export var cloud_speed := 1.18
@export_group("Animation")
## Simulated days per real second (the SolarSystem controller overwrites it at runtime).
@export var time_scale := 8.0
@export var max_orbit_speed := 2.5  # rad/s
@export var max_spin_speed := 1.1  # rad/s
@export var preview_in_editor := false:
	set(v):
		preview_in_editor = v
		if is_inside_tree():
			set_process(_should_process())
			if not v:
				reset_to_days(EDITOR_DAYS)

## Days after J2000 shown in the editor and on load (2026-10-28, the build date of the map).
const EDITOR_DAYS := 9797.0

var orbit_angle := 0.0
var spin_angle := 0.0

var _pivot: Node3D
var _anchor: Node3D
var _spin: Node3D
var _clouds: Node3D
var _orbit_line: GeometryInstance3D


func _ready() -> void:
	_pivot = get_node_or_null("Pivot") as Node3D
	_anchor = get_node_or_null("Pivot/Anchor") as Node3D
	_spin = get_node_or_null("Pivot/Anchor/Tilt/Spin") as Node3D
	_clouds = get_node_or_null("Pivot/Anchor/Tilt/CloudSpin") as Node3D
	_orbit_line = get_node_or_null("OrbitLine") as GeometryInstance3D
	set_process(_should_process())
	reset_to_days(EDITOR_DAYS)


func _should_process() -> bool:
	return preview_in_editor if Engine.is_editor_hint() else true


func _process(delta: float) -> void:
	advance(delta)


## Places the body exactly where it is `days` after J2000 (orbit); spin restarts at 0.
func reset_to_days(days: float) -> void:
	orbit_angle = deg_to_rad(phase_deg)
	if orbital_period_days > 0.0:
		orbit_angle += TAU * fposmod(days / orbital_period_days, 1.0)
	spin_angle = 0.0
	_apply()


func advance(delta: float) -> void:
	if delta <= 0.0 or time_scale == 0.0:
		return
	if orbital_period_days > 0.0:
		orbit_angle = fposmod(orbit_angle + _soft(TAU / orbital_period_days * time_scale, max_orbit_speed) * delta, TAU)
	if not tidally_locked and absf(rotation_period_hours) > 0.0:
		var w := TAU / (absf(rotation_period_hours) / 24.0) * time_scale
		spin_angle = fposmod(spin_angle + _soft(w, max_spin_speed) * delta, TAU)
	_apply()


## Angular speed actually shown for a real speed w (rad/s): ~w when slow, -> limit when fast.
static func _soft(w: float, limit: float) -> float:
	if limit <= 0.0:
		return w
	return limit * tanh(w / limit)


func _apply() -> void:
	if _pivot:
		_pivot.rotation.y = orbit_angle
	if _anchor:
		_anchor.rotation.y = 0.0 if tidally_locked else -orbit_angle
	if _spin:
		_spin.rotation.y = spin_angle
	if _clouds:
		_clouds.rotation.y = spin_angle * cloud_speed
	if _orbit_line:
		_orbit_line.set_instance_shader_parameter(&"head_angle", orbit_angle)


## World position of the body's center.
func body_position() -> Vector3:
	return _anchor.global_position if _anchor else global_position


func label() -> Label3D:
	return get_node_or_null("Pivot/Anchor/Label") as Label3D
