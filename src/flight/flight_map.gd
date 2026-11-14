class_name FlightMap
extends Control
## Map view (M). The 3D content lives in scenes/flight/flight_map.tscn: its own world with
## the solar-system voxel Earth and Moon (assets/voxel/planets), atmosphere shell, sun
## light and a star sky. Scale: 1 unit = MAP_SCALE metres. The orbit, the vessel and the
## Ap / Pe markers are drawn on the 2D overlay (smooth antialiased lines), dimmed where
## the planet hides them.

const MAP_SCALE := 10000.0
## the voxel Earth is a unit sphere with exaggerated relief; scale it a bit under R so the
## mountains stay below low orbits
const EARTH_SCALE := 0.965

@export var orbit_color := Color(0.373, 0.69, 0.847)
@export var vessel_color := Color(0.961, 0.604, 0.212)

var yaw := 0.6
var pitch := 0.5
var distance := 2600.0
var _dragging := false
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _ship := Vector2.ZERO
var _ship_visible := false

@onready var camera: Camera3D = %MapCamera
@onready var earth: Node3D = %Earth
@onready var moon: Node3D = %Moon
@onready var sun: DirectionalLight3D = %MapSun
@onready var overlay: Control = %MapOverlay
@onready var ap_marker: Control = %ApMarker
@onready var pe_marker: Control = %PeMarker
@onready var ship_marker: Control = %ShipMarker
@onready var ap_label: Label = %ApLabel
@onready var pe_label: Label = %PeLabel


func _ready() -> void:
	overlay.draw.connect(_draw_overlay)


func setup(planet_to_tex: Basis, sun_dir: Vector3, moon_dir: Vector3) -> void:
	earth.basis = planet_to_tex.transposed().scaled(Vector3.ONE * FlightOrbit.R / MAP_SCALE * EARTH_SCALE)
	moon.position = moon_dir.normalized() * 384400000.0 / MAP_SCALE
	moon.scale = Vector3.ONE * 1737400.0 / MAP_SCALE
	sun.look_at_from_position(Vector3.ZERO, -sun_dir.normalized(), Vector3.UP)


func set_active(on: bool) -> void:
	visible = on
	%MapViewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(900.0, distance * 0.88)
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(80000.0, distance * 1.13)
			return true
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		pitch = clampf(pitch + mm.relative.y * 0.005, -1.5, 1.5)
		return true
	return false


func _to_map(p: PackedFloat64Array) -> Vector3:
	return Vector3(p[0] / MAP_SCALE, p[1] / MAP_SCALE, p[2] / MAP_SCALE)


func update_map(v: FlightVessel, _origin: PackedFloat64Array, _debris: Array) -> void:
	var cp := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
	camera.position = cp
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var r := v.body.pos()
	var vel := v.body.vel()
	var pts := FlightOrbit.orbit_points(r, vel, 240, 9.0e7)
	_pts = PackedVector2Array()
	_cols = PackedColorArray()
	var rp := FlightOrbit.R / MAP_SCALE
	for p in pts:
		var mp := _to_map(p)
		if camera.is_position_behind(mp):
			continue
		_pts.append(camera.unproject_position(mp))
		var hidden := _occluded(mp, rp) or mp.length() < rp
		_cols.append(orbit_color * Color(1, 1, 1, 0.18 if hidden else 0.95))
	var ship := _to_map(r)
	_ship_visible = not camera.is_position_behind(ship)
	_ship = camera.unproject_position(ship)
	ship_marker.visible = _ship_visible
	ship_marker.position = _ship - ship_marker.size * 0.5
	var aps := FlightOrbit.apsides(r, vel)
	_place_apsis(ap_marker, ap_label, aps.get("ap", PackedFloat64Array()), "Ap")
	_place_apsis(pe_marker, pe_label, aps.get("pe", PackedFloat64Array()), "Pe")
	overlay.queue_redraw()


func _place_apsis(m: Control, l: Label, p: PackedFloat64Array, tag: String) -> void:
	if p.is_empty():
		m.visible = false
		return
	var mp := _to_map(p)
	var alt := FlightOrbit.length(p) - FlightOrbit.R
	m.visible = not camera.is_position_behind(mp)
	m.position = camera.unproject_position(mp) - Vector2(m.size.x * 0.5, m.size.y)
	m.modulate.a = 0.35 if _occluded(mp, FlightOrbit.R / MAP_SCALE) else 1.0
	l.text = "%s  %s" % [tag, FlightHUD.fmt_dist(alt)]
	l.add_theme_color_override("font_color", MarginPalette.DANGER if alt < 0.0 else MarginPalette.TEXT)


func _occluded(p: Vector3, rp: float) -> bool:
	var o := camera.global_position
	var d := p - o
	var dl := d.length()
	d /= dl
	var b := o.dot(d)
	var c := o.dot(o) - rp * rp
	var disc := b * b - c
	if disc <= 0.0:
		return false
	var t := -b - sqrt(disc)
	return t > 0.0 and t < dl


func _draw_overlay() -> void:
	if _pts.size() >= 2:
		overlay.draw_polyline_colors(_pts, _cols, 2.5, true)
