class_name FlightMap
extends Control
## Solar-system map view (M) with patched-conic trajectories and KSP-style maneuver
## nodes. Visuals live in scenes/flight/flight_map.tscn (first written by
## src/flight/gen/make_flight_map.py; its overlay, sky and line widths are now tuned in the
## editor), the colours of conics, markers and labels in scenes/flight/map_style.tres
## (FlightMapStyle, shared by any map view) and the marker / label look in
## scenes/flight/map_marker.tscn and map_body_label.tscn; this script places things and
## handles input.
##
## Map space: 1 unit = 1 km at real scale, with the focus (the vessel or a body) at the
## origin, so floats stay precise wherever the camera is: every position is computed in
## doubles relative to the focus (FlightSolar.pos_rel) and only then converted. The camera
## orbits the origin with a logarithmic zoom (0.4 km .. 170 AU); near / far follow it.
## Bodies are the voxel planets with visibility-range LODs (authored); far away they are
## 2D icons. Lines (orbits, trajectory segments, SOI rings) are strip meshes drawn with a
## constant pixel width by shaders/flight_map_line.gdshader: built once (orbits) or when
## the prediction changes (trajectory), never per frame; per frame only transforms and a
## few instance uniforms are touched.
##
## Drawing convention (as KSP): a segment around a body the camera frame belongs to (the
## focus body, or one of its parents) is drawn around that body's current position; a
## segment around another body (an encounter) is drawn around a "ghost" of that body at
## the encounter's periapsis time, marked on the map.
##
## Real orbits (FlightSolar on the Ephemeris): each orbit line is the body's osculating ellipse
## now, every body stands on its IAU spin axis (tidally locked moons face their parent). Two size
## modes: true scale, or `readable` (the campaign map and the solar-system view): every body is
## drawn at least READABLE_PX pixels across, never so big that a moon leaves its orbit. The
## asteroid belt and Jupiter's Trojans are dot clouds (MultiMesh, filled here from a fixed seed:
## real distances, eccentricities and inclinations, the Kirkwood gaps); the comet Mae-Gelo grows
## a coma and two tails away from the Sun as it comes in (ion: straight, dust: curved back along
## its path), with a real length (activity ~ 1 / r^2).
##
## Extra tracked objects (the tycoon's missions in space, SpaceTracking): a host can hide the
## vessel (`show_vessel`), focus a point it provides (focus -2 with `tracked_focus`), turn its
## own positions into map space (map_position) and add lines with the map's look (new_line).

const K := 0.001
const MARKER := preload("res://scenes/flight/map_marker.tscn")
const BODY_LABEL := preload("res://scenes/flight/map_body_label.tscn")
const ICON_APSIS := preload("res://scenes/flight/ui/marker_apsis.svg")
const ICON_NODE := preload("res://scenes/flight/ui/map_node.svg")
const ICON_SOI := preload("res://scenes/flight/ui/map_soi.svg")
const ICON_IMPACT := preload("res://scenes/flight/ui/map_impact.svg")
const ICON_CLOSEST := preload("res://scenes/flight/ui/map_closest.svg")
const ICON_LINE := preload("res://scenes/flight/ui/map_node_line.svg")
const ICON_BODY := preload("res://scenes/flight/ui/map_body.svg")
const MIN_VESSEL_DIST := 0.4
const MAX_DIST := 2.5e10
const HANDLE_PX := 78.0
## pick radius of a gizmo handle / node marker (px)
const HANDLE_PICK := 18.0
## the map's colours (lines, markers, labels): one shared resource, editable in the inspector
const STYLE: FlightMapStyle = preload("res://scenes/flight/map_style.tres")
## maneuver identity colour (no SOI trajectory uses it): node markers, the gizmo centre,
## the burn arrow, the "add node" hover and the planned path around the node's body
static var NODE_COLOR: Color = STYLE.node_color
static var PLAN_COLOR: Color = STYLE.plan_color
static var PLAN_COLOR_2: Color = STYLE.plan_color_2
const HANDLE_NAMES := {"Pro": "FL_PROGRADE", "Retro": "FL_RETROGRADE", "Normal": "FL_NORMAL",
	"Anti": "FL_ANTINORMAL", "RadOut": "FL_RADIAL_OUT", "RadIn": "FL_RADIAL_IN"}
const N_MARKERS := 32
## readable mode: smallest body radius on screen (px) and the largest blow-up of a body
const READABLE_PX := 8.0
const READABLE_MAX := 4000.0
const AU_M := 149597870700.0
## trajectory colour per SOI body id (others: STYLE.soi_other)
static var SOI_COLORS: Dictionary = STYLE.soi_colors

signal node_selected(n: FlightManeuverNode)

var world: FlightWorld
var sys: FlightSolar
## -1 = the vessel, -2 = the point `tracked_focus` gives, else a FlightSolar body index
var focus := -1
## the vessel's marker and focus (off when the map shows other things only: FlightWorld.map_only)
var show_vessel := true
## focus -2: returns {"body": FlightSolar index, "pos": PackedFloat64Array (m, relative to the
## body), "name": String}
var tracked_focus := Callable()
var yaw := 0.7
var pitch := 0.42
var dist := 30000.0
var selected: FlightManeuverNode = null
var scale_mode := 0
## bodies at least READABLE_PX on screen (see the class doc)
var readable := false

var _yaw := 0.7
var _pitch := 0.42
var _dist := 30000.0
var _up := Vector3.UP
var _frame := 0
var _focus_off := PackedFloat64Array([0.0, 0.0, 0.0])
var _anim_from := PackedFloat64Array([0.0, 0.0, 0.0])
var _anim_t := 1.0
var _body_nodes: Array[Node3D] = []
var _orbit_nodes: Array[MeshInstance3D] = []
var _orbit_alpha := PackedFloat32Array()
var _labels: Array[Control] = []
var _label_px := PackedFloat32Array()
var _label_screen := PackedVector2Array()
var _seg_nodes: Array[MeshInstance3D] = []
var _seg_count := 0
var _seg_anchor_t := PackedFloat64Array()
var _markers: Array[Control] = []
var _mdata: Array[Dictionary] = []
var _traj_dirty := true
var _traj_ref: FlightTrajectory = null
var _circle: ArrayMesh
## tidally locked moons (FlightSolar indices): turned to face their parent every frame
var _locked: Array[int] = []
## per body: the current blow-up and its geometry's authored visibility ranges
var _body_scale := PackedFloat32Array()
var _geo: Array[Array] = []
## the dot clouds' mean motion (rad/s) and the time their dots were placed at
var _belt_rate := 0.0
var _cloud_t0 := 0.0
var _dots_fade := -1.0
var _atmo_mats: Array[ShaderMaterial] = []
var _text_timer := 0.0
var _initialized := false
# input
var _mouse := Vector2.ZERO
var _rmb := false
var _rmb_moved := 0.0
var _lmb := false
var _lmb_moved := 0.0
var _press := Vector2.ZERO
var _drag := ""
var _drag_axis := Vector3.ZERO
var _drag_handle := ""
var _drag_sdir := Vector2.ZERO
var _hover := {}
var _hover_dirty := true
var _handle_pos := {}
var _gizmo_center := Vector2(-1000, -1000)
## gizmo drawing (local to the gizmo): handle stems {name: [tip, colour]}, burn arrow tip
var _gz_stems := {}
var _gz_burn := Vector2.ZERO
var _gz_hover := ""
var _proj_frame := -1

@onready var viewport: SubViewport = %MapViewport
@onready var camera: Camera3D = %MapCamera
@onready var sun_light: OmniLight3D = %SunLight
@onready var overlay: Control = %Overlay
@onready var labels_root: Control = %Labels
@onready var markers_root: Control = %Markers
@onready var vessel_marker: Control = %VesselMarker
@onready var hover_marker: Control = %Hover
@onready var hover_label: Label = %Label
@onready var gizmo: Control = %Gizmo
@onready var detail: MeshInstance3D = $Container/MapViewport/World/Trajectory/Detail


func _ready() -> void:
	gizmo.draw.connect(_draw_gizmo)
	(hover_marker.get_node("Icon") as CanvasItem).self_modulate = NODE_COLOR
	hover_label.add_theme_color_override("font_color", STYLE.label_node)
	%BtnPrev.pressed.connect(func() -> void: cycle_focus(-1))
	%BtnNext.pressed.connect(func() -> void: cycle_focus(1))
	%BtnVessel.pressed.connect(func() -> void: set_scale_mode(0))
	%BtnSystem.pressed.connect(func() -> void: set_scale_mode(1))
	%BtnSolar.pressed.connect(func() -> void: set_scale_mode(2))
	%BtnReadable.toggled.connect(set_readable)


func setup(w: FlightWorld, planet_to_tex: Basis) -> void:
	world = w
	sys = w.sys
	_body_nodes.resize(sys.ids.size())
	for n in %Bodies.get_children():
		var i := sys.index_of(String(n.get_meta("body_id", "")))
		if i >= 0:
			_body_nodes[i] = n as Node3D
	# the Earth as the flight draws it (same continents under the pad); no planet spins. The
	# others stand on their real spin axes (IAU poles: Saturn's rings tilt as they really do)
	for i in sys.ids.size():
		var tl := _body_nodes[i].get_node_or_null("Tilt") as Node3D
		if tl and i != sys.earth:
			tl.basis = _pole_basis(sys.pole(i), Vector3.ZERO)
			if bool(sys.eph.data[sys.eph.index_of(sys.ids[i])].get("tidally_locked", false)):
				_locked.append(i)
	var e_tilt := _body_nodes[sys.earth].get_node("Tilt") as Node3D
	e_tilt.basis = planet_to_tex.transposed()
	for i in sys.ids.size():
		var atmo := _body_nodes[i].get_node_or_null("Tilt/Atmosphere") as MeshInstance3D
		if atmo:
			_atmo_mats.append(atmo.get_surface_override_material(0) as ShaderMaterial)
	_circle = FlightMapLines.circle(256)
	var fine := FlightMapLines.circle(1536)
	_orbit_nodes.resize(sys.ids.size())
	_orbit_alpha.resize(sys.ids.size())
	for n in %Orbits.get_children():
		var i := sys.index_of(String(n.get_meta("body_id", "")))
		var mi := n as MeshInstance3D
		mi.mesh = fine if sys.kinds[i] == "comet" else _circle
		_orbit_nodes[i] = mi
		_orbit_alpha[i] = (mi.get_instance_shader_parameter(&"line_color") as Color).a
	for r in %SoiRings.get_children():
		(r as MeshInstance3D).mesh = _circle
	for n in %Trajectory.get_children():
		if n != detail:
			_seg_nodes.append(n as MeshInstance3D)
	_labels.resize(sys.ids.size())
	_label_px.resize(sys.ids.size())
	_label_screen.resize(sys.ids.size())
	for i in sys.ids.size():
		var l: Control = BODY_LABEL.instantiate()
		labels_root.add_child(l)
		var icon := load("res://assets/voxel/planets/icons/%s.png" % sys.ids[i]) as Texture2D
		(l.get_node("Icon") as TextureRect).texture = icon
		(l.get_node("Halo") as TextureRect).texture = ICON_BODY
		(l.get_node("Halo") as TextureRect).self_modulate = sys.colors[i]
		_labels[i] = l
	for i in N_MARKERS:
		var m: Control = MARKER.instantiate()
		m.visible = false
		markers_root.add_child(m)
		_markers.append(m)
	_body_scale.resize(sys.ids.size())
	_body_scale.fill(1.0)
	_geo.resize(sys.ids.size())
	for i in sys.ids.size():
		var list: Array = []
		for g in _body_nodes[i].find_children("*", "GeometryInstance3D", true, false):
			var gi := g as GeometryInstance3D
			list.append([gi, gi.visibility_range_begin, gi.visibility_range_begin_margin, gi.visibility_range_end,
				gi.visibility_range_end_margin])
		_geo[i] = list
	_fill_clouds()
	_quality()
	_refresh_names()


## Readable sizes on / off (the map bar's toggle, or a host).
func set_readable(on: bool) -> void:
	readable = on
	if is_node_ready():
		(%BtnReadable as Button).set_pressed_no_signal(on)


## The asteroid belt and the Trojans: dots on real-looking orbits around the Sun (PCI axes, map
## units), placed once from a fixed seed at the current time; the nodes turn at their mean motion.
func _fill_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260
	var gm := sys.mu[sys.sun]
	_cloud_t0 = world.time if world else 0.0
	var belt := %AsteroidBelt as MultiMeshInstance3D
	var n := int(belt.get_meta("count", 2600))
	var inner := float(belt.get_meta("inner_au", 2.1))
	var outer := float(belt.get_meta("outer_au", 3.3))
	var ca: Color = belt.get_meta("color_a", Color(0.6, 0.6, 0.55, 0.85))
	var cb: Color = belt.get_meta("color_b", Color(0.8, 0.75, 0.6, 0.85))
	var mm := belt.multimesh
	mm.instance_count = n
	# Kirkwood gaps (resonances with Jupiter): 3:1 at 2.50 AU, 5:2 at 2.82, 7:3 at 2.95
	var gaps := [2.502, 2.825, 2.958]
	var k := 0
	while k < n:
		var a := lerpf(inner, outer, pow(rng.randf(), 0.85))
		var in_gap := false
		for g: float in gaps:
			in_gap = in_gap or absf(a - g) < 0.025
		if in_gap and rng.randf() < 0.9:
			continue
		var e := minf(absf(rng.randfn(0.0, 0.08)), 0.3)
		var inc := absf(rng.randfn(0.0, deg_to_rad(8.0)))
		var p := _kepler_point(a * AU_M, e, inc, rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, p))
		mm.set_instance_color(k, ca.lerp(cb, rng.randf()))
		k += 1
	_belt_rate = sqrt(gm / pow(2.7 * AU_M, 3.0))
	# Trojans: around Jupiter's L4 / L5 points, 60 deg ahead of / behind it on its orbit
	var tro := %Trojans as MultiMeshInstance3D
	var nt := int(tro.get_meta("count", 700))
	var tm := tro.multimesh
	tm.instance_count = nt
	var jup := sys.index_of("jupiter")
	var js := sys.state_rel_parent(jup, _cloud_t0)
	var jr := Vector3(js[0], js[1], js[2])
	var jn := jr.cross(Vector3(js[3], js[4], js[5])).normalized()
	var ta: Color = tro.get_meta("color_a", Color(0.6, 0.66, 0.56, 0.8))
	var tb: Color = tro.get_meta("color_b", Color(0.78, 0.8, 0.62, 0.8))
	for j in nt:
		var side := 1.0 if j % 2 == 0 else -1.0
		var ang := side * deg_to_rad(60.0) + rng.randfn(0.0, deg_to_rad(11.0))
		var r := jr.length() * (1.0 + rng.randfn(0.0, 0.035))
		var d := jr.normalized().rotated(jn, ang)
		var up := jn * rng.randfn(0.0, 0.09) * r
		var pt := (d * r + up) * K
		tm.set_instance_transform(j, Transform3D(Basis.IDENTITY, pt))
		tm.set_instance_color(j, ta.lerp(tb, rng.randf()))


## A point (map units, PCI axes) of an ecliptic Kepler orbit.
func _kepler_point(a: float, e: float, inc: float, node: float, w: float, mean_anom: float) -> Vector3:
	var s := Ephemeris.kepler_state(a, e, inc, node, w, mean_anom, 0.0)
	var p := sys.to_pci(PackedFloat64Array([s[0], s[1], s[2]]))
	return Vector3(p[0] * K, p[1] * K, p[2] * K)


## Body blow-ups for readable mode, the dot clouds and the comet's tails (every frame).
func _place_extras() -> void:
	var now := world.time
	var focal := _focal_px()
	var cam_pos := camera.global_position
	for i in sys.ids.size():
		var want := 1.0
		if readable:
			var d := maxf(cam_pos.distance_to(_body_nodes[i].position), 1e-6)
			var r_map := sys.radius[i] * K
			want = clampf(READABLE_PX * d / focal / r_map, 1.0, READABLE_MAX)
			var p := sys.parent[i]
			if p >= 0:
				# a moon stays well inside its orbit around the (blown-up) parent; a planet in its own
				var room := sys.sma[i] * K * (0.22 if p != sys.sun else 0.08)
				want = minf(want, maxf(room / r_map, 1.0))
			else:
				want = minf(want, 25.0)
		if absf(want / _body_scale[i] - 1.0) > 0.03 or (want == 1.0 and _body_scale[i] != 1.0):
			_set_body_scale(i, want)
	# dot clouds: around the Sun, turning at their mean motion; faded out close to a planet
	var belt := %AsteroidBelt as MultiMeshInstance3D
	var tro := %Trojans as MultiMeshInstance3D
	var sp := _body_nodes[sys.sun].position
	var n_e := sys.ecliptic_normal.normalized()
	belt.position = sp
	belt.basis = Basis(n_e, _belt_rate * (now - _cloud_t0))
	tro.position = sp
	tro.basis = Basis(n_e, sys.rate[sys.index_of("jupiter")] * (now - _cloud_t0))
	var fade := smoothstep(2.0e7, 2.0e8, _dist)
	belt.visible = fade > 0.01
	tro.visible = fade > 0.01
	if absf(fade - _dots_fade) > 0.01:
		_dots_fade = fade
		(belt.material_override as ShaderMaterial).set_shader_parameter(&"fade", fade)
	_place_comet(now)


func _set_body_scale(i: int, sc: float) -> void:
	_body_scale[i] = sc
	_body_nodes[i].scale = Vector3.ONE * sc
	for g: Array in _geo[i]:
		var gi := g[0] as GeometryInstance3D
		gi.visibility_range_begin = float(g[1]) * sc
		gi.visibility_range_begin_margin = float(g[2]) * sc
		gi.visibility_range_end = float(g[3]) * sc
		gi.visibility_range_end_margin = float(g[4]) * sc


## The comet's coma and tails: away from the Sun, the ion tail straight, the dust tail bent back
## along the path; length and brightness grow as 1 / r^2 inside ~5 AU (0.3 AU long at 1 AU: a
## bright comet's; real ion tails reach 0.1-1 AU and more).
func _place_comet(now: float) -> void:
	var c := sys.comet
	if c < 0:
		return
	var node := _body_nodes[c]
	var ion := node.get_node_or_null("IonTail") as MeshInstance3D
	var dust := node.get_node_or_null("DustTail") as MeshInstance3D
	var coma := node.get_node_or_null("Coma") as MeshInstance3D
	if ion == null or dust == null or coma == null:
		return
	var st := sys.state_rel_parent(c, now)
	var r := Vector3(st[0], st[1], st[2])
	var r_au := r.length() / AU_M
	var act := clampf(smoothstep(6.0, 2.5, r_au) * minf(1.5 / (r_au * r_au), 1.0), 0.0, 1.0)
	ion.visible = act > 0.01
	dust.visible = act > 0.01
	coma.visible = act > 0.005
	if not coma.visible:
		return
	var away := r.normalized()
	var vel := Vector3(st[3], st[4], st[5]).normalized()
	# the tails keep their real size when the nucleus is blown up (readable mode)
	var inv := 1.0 / maxf(_body_scale[c], 1e-6)
	var l := clampf(4.5e10 / (r_au * r_au), 0.0, 1.5e11) * act * K * inv
	ion.basis = _tail_basis(away, l, l * 0.22)
	dust.basis = _tail_basis((away - vel * 0.35).normalized(), l * 0.7, l * 0.4)
	ion.set_instance_shader_parameter(&"activity", act)
	dust.set_instance_shader_parameter(&"activity", act)
	coma.scale = Vector3.ONE * maxf(1.5e8 * act * K * inv, 1e-3)
	coma.set_instance_shader_parameter(&"intensity", 0.5 + act)


## Basis whose X axis runs along `dir` for `length` (the tail mesh's head -> tip), Y = width.
static func _tail_basis(dir: Vector3, length: float, width: float) -> Basis:
	var x := dir.normalized()
	var y := x.cross(Vector3.UP if absf(x.y) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(x * maxf(length, 1e-6), y * maxf(width, 1e-6), x.cross(y))


## The map has its own environment and no screen-space effects at all (GraphicsQuality
## turns SSAO / glow on for every WorldEnvironment it finds). Measured on the integrated
## GPU at 1600x900: glow cost ~5 ms and MSAA 2x ~4 ms in this viewport; the Sun's halo is
## a billboard (flight_map_glow) and the lines anti-alias themselves, so only HIGH keeps
## MSAA (for the voxel edges of close-up planets) and LOW renders at 80 %.
func _quality() -> void:
	var env: Environment = (%WorldEnvironment as WorldEnvironment).environment
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.fog_enabled = false
	env.glow_enabled = false
	var q := GraphicsQuality.current()
	viewport.msaa_3d = Viewport.MSAA_2X if q == GraphicsQuality.Level.HIGH else Viewport.MSAA_DISABLED
	viewport.scaling_3d_scale = 0.8 if q == GraphicsQuality.Level.LOW else 1.0


func set_active(on: bool) -> void:
	visible = on
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		_quality()
		_traj_dirty = true
		if not _initialized:
			_initialized = true
			set_scale_mode(0, true)
	else:
		_end_drag()


func trajectory_changed() -> void:
	_traj_dirty = true
	_hover_dirty = true


# ------------------------------------------------------------ focus / zoom
func frame_body() -> int:
	if focus == -2:
		return int(_tracked().get("body", world.soi))
	return focus if focus >= 0 else world.soi


func focus_name() -> String:
	if focus == -2:
		return String(_tracked().get("name", ""))
	return tr("FL_MAP_VESSEL") if focus < 0 else sys.display_name(focus)


func _tracked() -> Dictionary:
	return tracked_focus.call() if tracked_focus.is_valid() else {}


## Map position (units) now of a point given relative to body `body` (m, PCI axes).
func map_position(body: int, pos: PackedFloat64Array) -> Vector3:
	return body_map(body, world.time) + Vector3(pos[0] * K, pos[1] * K, pos[2] * K)


## A line node with the map's line look (a copy of a trajectory segment, hidden, no mesh) under
## the map's world, for a host's own paths (FlightMapLines meshes, map units).
func new_line() -> MeshInstance3D:
	var src: MeshInstance3D = _seg_nodes[0] if not _seg_nodes.is_empty() else detail
	var mi := src.duplicate() as MeshInstance3D
	mi.mesh = null
	mi.visible = false
	(%Trajectory.get_parent() as Node3D).add_child(mi)
	return mi


func set_focus(f: int, keep_dist := false) -> void:
	if f == focus:
		return
	# animate the origin from the old focus point to the new one (in the new frame)
	var old_frame := frame_body()
	var old_off := _focus_off
	focus = f
	var nf := frame_body()
	var o := sys.pos_rel(old_frame, nf, world.time)
	_anim_from = PackedFloat64Array([o[0] + old_off[0], o[1] + old_off[1], o[2] + old_off[2]])
	_anim_t = 0.0
	if not keep_dist:
		if f >= 0:
			dist = clampf(dist, sys.radius[f] * K * 2.6, maxf(sys.radius[f] * K * 60.0, _system_size(f)))
		elif f == -1:
			dist = clampf(dist, MIN_VESSEL_DIST, _vessel_orbit_size() * 3.0)
	_refresh_names()


func cycle_focus(d: int) -> void:
	var order: Array[int] = [-1, world.soi] if show_vessel else [world.soi]
	for i in sys.ids.size():
		if i != world.soi:
			order.append(i)
	var k := order.find(focus)
	set_focus(order[posmod(k + d, order.size())])


## 0 = the vessel's orbit, 1 = the system of the body it orbits, 2 = the whole solar system
func set_scale_mode(m: int, snap := false) -> void:
	scale_mode = m
	match m:
		0:
			# centred on the body the vessel orbits, its whole orbit in view
			set_focus(world.soi, true)
			dist = _vessel_orbit_size() * 3.2
			pitch = 0.5
		1:
			var b := world.soi if world.soi != sys.moon else sys.earth
			set_focus(b, true)
			dist = _system_size(b)
			pitch = 0.62
		2:
			set_focus(sys.sun, true)
			dist = 2.2e9
			pitch = 0.75
	if snap:
		_dist = dist
		_pitch = pitch
		_yaw = yaw
		_anim_t = 1.0
	_refresh_names()


func _vessel_orbit_size() -> float:
	var el := FlightOrbit.elements(world.sim.pos(), world.sim.vel(), sys.mu[world.soi], sys.radius[world.soi])
	var r: float = el["ra"] if float(el["e"]) < 1.0 and float(el["ra"]) < sys.soi[world.soi] else maxf(float(el["r"]) * 3.0, sys.radius[world.soi] * 3.0)
	return clampf(r, sys.radius[world.soi] * 1.4, sys.soi[world.soi] if sys.soi[world.soi] < INF else 1.0e13) * K


func _system_size(b: int) -> float:
	var s := sys.radius[b] * 30.0
	for c in sys.children[b]:
		s = maxf(s, sys.sma[c] * 2.6)
	if b == sys.sun:
		s = 2.2e12
	return s * K


func _refresh_names() -> void:
	if not is_node_ready() or sys == null:
		return
	(%Focus as Label).text = focus_name()
	(%BtnVessel as Button).set_pressed_no_signal(scale_mode == 0)
	(%BtnSystem as Button).set_pressed_no_signal(scale_mode == 1)
	(%BtnSolar as Button).set_pressed_no_signal(scale_mode == 2 and focus == sys.sun)
	var t := world.target_body
	(%Info as Label).text = (tr("FL_CW_MAP_TARGET") % sys.display_name(t)) if t >= 0 else tr("FL_CW_MAP_TARGET_NONE")


# ------------------------------------------------------------ input
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = _to_local(mm.position)
		_hover_dirty = true
		if _rmb:
			_rmb_moved += mm.relative.length()
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.005, -1.5, 1.5)
			return true
		if _lmb:
			_lmb_moved += mm.relative.length()
			if _drag == "time_pending" and _lmb_moved > 4.0:
				_drag = "time"
				world.plan_dragging = true
			if _drag == "time":
				_drag_time()
			return _drag != ""
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = _to_local(mb.position)
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_rmb = mb.pressed
				if mb.pressed:
					_rmb_moved = 0.0
				elif _rmb_moved < 4.0:
					var b := _body_at(_mouse)
					if b >= 0:
						world.target_body = -1 if world.target_body == b else b
						world._traj_dirty = true
						_refresh_names()
				return true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not mb.pressed:
					return true
				var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
				var h := _handle_at(_mouse)
				if h != "" and selected != null:
					var step := 0.1 if mb.shift_pressed else 1.0
					world.plan.add_dv(selected, _axis_of(h) * (step if up else -step))
				else:
					dist = clampf(dist * (0.85 if up else 1.0 / 0.85), _min_dist(), MAX_DIST)
				return true
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_lmb = true
					_lmb_moved = 0.0
					_press = _mouse
					_on_left_press(mb.shift_pressed)
				else:
					_lmb = false
					_on_left_release()
				return true
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_TAB:
				cycle_focus(-1 if k.shift_pressed else 1)
				return true
			KEY_1:
				set_scale_mode(0)
				return true
			KEY_2:
				set_scale_mode(1)
				return true
			KEY_3:
				set_scale_mode(2)
				return true
			KEY_DELETE:
				if k.shift_pressed:
					# Shift+Delete: clear the whole plan
					if world.executor:
						world.set_executor(false)
					world.plan.clear()
					select_node(null)
				elif selected != null:
					delete_selected()
				return true
	return false


func _to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _min_dist() -> float:
	return MIN_VESSEL_DIST if focus < 0 else sys.radius[focus] * K * 1.25


func _on_left_press(_shift: bool) -> void:
	_drag = ""
	if selected != null and gizmo.visible:
		var h := _handle_at(_mouse)
		if h == "delete":
			delete_selected()
			return
		if h != "":
			_drag = "dv"
			_drag_handle = h
			_drag_axis = _axis_of(h)
			_drag_sdir = (_handle_pos[h] - _gizmo_center).normalized()
			world.plan_dragging = true
			return
		if _mouse.distance_to(_gizmo_center) < 20.0:
			_drag = "time_pending"
			return
	# another node's marker?
	for md in _mdata:
		if md["kind"] == "node" and md.has("screen") and _mouse.distance_to(md["screen"]) < HANDLE_PICK:
			select_node(md["node"])
			_drag = "time_pending"
			return


func _on_left_release() -> void:
	var was := _drag
	_end_drag()
	if _lmb_moved > 4.0 or was == "dv" or was == "time":
		return
	if was == "time_pending":
		return
	var b := _body_at(_mouse)
	if b >= 0:
		set_focus(b)
		return
	if not _hover.is_empty():
		var n := world.plan.add(float(_hover["t"]))
		select_node(n)
		_hover = {}
		return
	select_node(null)


func _end_drag() -> void:
	_drag = ""
	if world:
		world.plan_dragging = false
		world._traj_dirty = true


func select_node(n: FlightManeuverNode) -> void:
	selected = n
	node_selected.emit(n)


func delete_selected() -> void:
	if selected == null:
		return
	var i := world.plan.index_of(selected)
	world.plan.remove(selected)
	if world.executor and world.executor.node == selected:
		world.set_executor(false)
	selected = world.plan.nodes[mini(i, world.plan.nodes.size() - 1)] if not world.plan.nodes.is_empty() else null
	node_selected.emit(selected)


func _axis_of(h: String) -> Vector3:
	match h:
		"Pro":
			return Vector3(1, 0, 0)
		"Retro":
			return Vector3(-1, 0, 0)
		"Normal":
			return Vector3(0, 1, 0)
		"Anti":
			return Vector3(0, -1, 0)
		"RadOut":
			return Vector3(0, 0, 1)
		"RadIn":
			return Vector3(0, 0, -1)
	return Vector3.ZERO


func _handle_at(p: Vector2) -> String:
	if selected == null or not gizmo.visible:
		return ""
	for h in _handle_pos:
		if p.distance_to(_handle_pos[h]) < HANDLE_PICK:
			return h
	return ""


func _body_at(p: Vector2) -> int:
	var best := -1
	var best_d := 1e9
	for i in sys.ids.size():
		if not _labels[i].visible:
			continue
		var d := p.distance_to(_label_screen[i])
		if d < maxf(16.0, _label_px[i]) and d < best_d:
			best = i
			best_d = d
	return best


## Applies a held Δv handle (KSP-style: the further the drag, the faster Δv changes).
func _apply_dv_drag(dt: float) -> void:
	if _drag != "dv" or selected == null:
		return
	var d := (_mouse - _press).dot(_drag_sdir)
	var rate := signf(d) * pow(absf(d) / 40.0, 2.0) * 40.0
	if Input.is_key_pressed(KEY_SHIFT):
		rate *= 0.1
	rate = clampf(rate, -3000.0, 3000.0)
	if absf(rate) > 0.001:
		world.plan.add_dv(selected, _drag_axis * rate * dt)


## Node time drag: nearest point of the path the node sits on (the segments of its plan).
func _drag_time() -> void:
	if selected == null or world.traj == null:
		return
	var idx := world.plan.index_of(selected)
	var best := {}
	var best_d := 1e9
	for si in _seg_count:
		var seg: FlightTrajectory.Segment = world.traj.segments[si]
		if seg.plan != idx:
			continue
		var h := _nearest_on_screen(si, _mouse, best_d)
		if not h.is_empty():
			best = h
			best_d = h["d"]
	if not best.is_empty():
		world.plan.set_time(selected, best["t"], world.time)


# ------------------------------------------------------------ per frame
func update_map() -> void:
	if world == null:
		return
	var dt := get_process_delta_time()
	_apply_dv_drag(dt)
	var k := 1.0 - exp(-dt * 9.0)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = exp(lerpf(log(_dist), log(dist), k))
	var want_up := Vector3.UP
	_frame = frame_body()
	if _frame == sys.sun or sys.parent[_frame] == sys.sun and _frame != sys.earth:
		want_up = sys.ecliptic_normal
	else:
		want_up = sys.orbit_normal(sys.moon)
	_up = _up.slerp(want_up, k * 0.5).normalized()
	# focus point (doubles, frame body coordinates)
	var off := PackedFloat64Array([0.0, 0.0, 0.0])
	if focus == -1:
		off = world.sim.pos()
	elif focus == -2:
		off = _tracked().get("pos", off)
	if _anim_t < 1.0:
		_anim_t = minf(_anim_t + dt / 0.45, 1.0)
		var s := 1.0 - pow(1.0 - _anim_t, 3.0)
		for j in 3:
			off[j] = _anim_from[j] + (off[j] - _anim_from[j]) * s
	_focus_off = off
	_place_camera()
	_place_bodies()
	_place_extras()
	_place_orbits()
	if _traj_dirty or world.traj != _traj_ref:
		_rebuild_trajectory()
	_place_trajectory()
	_place_overlay(dt)


func _place_camera() -> void:
	var ref := _up.cross(Vector3.RIGHT if absf(_up.x) < 0.9 else Vector3.FORWARD).normalized()
	var side := _up.cross(ref).normalized()
	var dir := (ref * cos(_yaw) + side * sin(_yaw)) * cos(_pitch) + _up * sin(_pitch)
	# near / far follow the zoom (a fixed huge range breaks the light culler's frustum)
	camera.near = maxf(_dist * 0.002, 0.001)
	camera.far = _dist * 2.0e4
	camera.look_at_from_position(dir * _dist, Vector3.ZERO, _up)


## Map position (units) of a body at time t.
func body_map(i: int, t: float) -> Vector3:
	var p := sys.pos_rel(i, _frame, t)
	return Vector3((p[0] - _focus_off[0]) * K, (p[1] - _focus_off[1]) * K, (p[2] - _focus_off[2]) * K)


func _place_bodies() -> void:
	var now := world.time
	for i in sys.ids.size():
		_body_nodes[i].position = body_map(i, now)
	# tidally locked moons keep their near side (-X of the voxel model) to the parent
	for i in _locked:
		var to_parent := _body_nodes[sys.parent[i]].position - _body_nodes[i].position
		(_body_nodes[i].get_node("Tilt") as Node3D).basis = _pole_basis(sys.pole(i), to_parent)
	var sp := _body_nodes[sys.sun].position
	sun_light.position = sp
	for m in _atmo_mats:
		m.set_shader_parameter("sun_position", sp)


## A Tilt basis whose +Y is the spin axis and whose -X faces `face` (a direction; zero = any).
static func _pole_basis(pole: Vector3, face: Vector3) -> Basis:
	var y := pole.normalized()
	var x := -face if face.length_squared() > 0.0 else y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD)
	x = (x - y * x.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


func _place_orbits() -> void:
	var now := world.time
	var focal := _focal_px()
	for i in sys.ids.size():
		var mi := _orbit_nodes[i]
		if mi == null:
			continue
		var p := sys.parent[i]
		var center := body_map(p, now)
		var r := sys.sma[i] * K
		var cd := maxf(camera.global_position.distance_to(center), 1e-6)
		var px := r / cd * focal
		# fade out orbits too small to read, and the ones much bigger than the view: their
		# 256-gon chords (sagitta 7.5e-5 r) would visibly miss the bodies on them
		var a := smoothstep(4.0, 24.0, px) * (1.0 - smoothstep(25.0 * _dist, 50.0 * _dist, r))
		var hl := 1.0
		if i == world.target_body:
			hl = 1.9
		elif p == _frame or i == _frame:
			hl = 1.35
		mi.visible = a > 0.01
		if not mi.visible:
			continue
		# the real (osculating) ellipse: the unit circle (cos E, 0, sin E) -> a cos E P + b sin E Q
		var sh := sys.orbit_shape(i, now)
		var vp: Vector3 = sh["p_axis"]
		var vq: Vector3 = sh["q_axis"]
		var c0: PackedFloat64Array = sh["center"]
		var ea := float(sh["a"]) * K
		var eb := float(sh["b"]) * K
		mi.transform = Transform3D(Basis(vp * ea, vp.cross(vq) * ea, vq * eb), center + Vector3(c0[0] * K, c0[1] * K, c0[2] * K))
		var c := mi.get_instance_shader_parameter(&"line_color") as Color
		c.a = minf(_orbit_alpha[i] * a * hl, 1.0)
		mi.set_instance_shader_parameter(&"line_color", c)
	# SOI rings: the focus frame's body and its children, the target
	var rings := %SoiRings.get_children()
	var cands: Array[int] = []
	if sys.parent[_frame] >= 0:
		cands.append(_frame)
	for c in sys.children[_frame]:
		cands.append(c)
	if world.target_body >= 0 and not cands.has(world.target_body):
		cands.append(world.target_body)
	var cb := camera.global_basis
	var used := 0
	for b in cands:
		if used >= rings.size():
			break
		var center := body_map(b, now)
		var rr := sys.soi[b] * K
		var px := rr / maxf(camera.global_position.distance_to(center), 1e-6) * focal
		if px < 24.0 or px > 4000.0 or camera.is_position_behind(center):
			continue
		var ring := rings[used] as MeshInstance3D
		ring.visible = true
		ring.transform = Transform3D(Basis(cb.x * rr, cb.z * rr, cb.y * rr), center)
		used += 1
	for i in range(used, rings.size()):
		(rings[i] as MeshInstance3D).visible = false


## Body indices by label priority: focus, target, frame body, then by size.
func _label_order() -> Array[int]:
	var order: Array[int] = []
	for i in [focus, world.target_body, _frame]:
		if i >= 0 and not order.has(i):
			order.append(i)
	var rest: Array[int] = []
	for i in sys.ids.size():
		if not order.has(i):
			rest.append(i)
	rest.sort_custom(func(a: int, b: int) -> bool: return sys.radius[a] > sys.radius[b])
	order.append_array(rest)
	return order


## True if a map point is hidden behind a body big enough to matter on screen.
func occluded(p: Vector3) -> bool:
	var o := camera.global_position
	var d := p - o
	var dl := d.length()
	if dl <= 0.0:
		return false
	d /= dl
	for i in sys.ids.size():
		if _label_px.size() > i and _label_px[i] < 6.0:
			continue
		var c := _body_nodes[i].position
		var r := sys.radius[i] * K
		var oc := o - c
		var b := oc.dot(d)
		var disc := b * b - (oc.dot(oc) - r * r)
		if disc <= 0.0:
			continue
		var t := -b - sqrt(disc)
		if t > 0.0 and t < dl - r * 0.02:
			return true
	return false


## Turns the camera so it looks at the focus from the side of `dir` (map axes), keeping
## its pitch above the reference plane.
func face_direction(dir: Vector3) -> void:
	var ref := _up.cross(Vector3.RIGHT if absf(_up.x) < 0.9 else Vector3.FORWARD).normalized()
	var side := _up.cross(ref).normalized()
	yaw = atan2(dir.dot(side), dir.dot(ref))


func _focal_px() -> float:
	return viewport.size.y * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)


# ------------------------------------------------------------ trajectory
func _seg_color(seg: FlightTrajectory.Segment) -> Color:
	return STYLE.soi_color(sys.ids[seg.body])


## Colour of segment i: its SOI colour on the current path; after a node, the maneuver
## colour while it stays around the node's body (so the planned orbit stands out from the
## current one), the SOI colour again once it reaches another body (encounter / escape).
func _plan_color(tr: FlightTrajectory, i: int) -> Color:
	var seg := tr.segments[i]
	if seg.plan == 0:
		return _seg_color(seg)
	var j := i
	while j > 0 and tr.segments[j - 1].end != FlightTrajectory.End.NODE:
		j -= 1
	if j > 0 and tr.segments[j - 1].body == seg.body:
		return PLAN_COLOR if seg.plan == 1 else PLAN_COLOR_2
	return _seg_color(seg).lerp(Color.WHITE, 0.15)


func _rebuild_trajectory() -> void:
	_traj_dirty = false
	_traj_ref = world.traj
	_mdata.clear()
	var tr := world.traj
	_seg_count = 0 if tr == null else mini(tr.segments.size(), _seg_nodes.size())
	_seg_anchor_t.resize(_seg_count)
	for i in _seg_nodes.size():
		var mi := _seg_nodes[i]
		if i >= _seg_count:
			mi.visible = false
			continue
		var seg := tr.segments[i]
		mi.visible = true
		mi.mesh = FlightMapLines.polyline(seg.pts, K, mi.mesh as ArrayMesh)
		var c := _plan_color(tr, i)
		mi.set_instance_shader_parameter(&"line_color", Color(c, 0.95))
		mi.set_instance_shader_parameter(&"line_width", 2.6 if seg.plan == 0 else 3.0)
		mi.set_instance_shader_parameter(&"gap", Vector4.ZERO)
		# encounter segments around a ghost of their body at the periapsis time
		var tp := seg.conic.time_at_true_anomaly(0.0, seg.t0) if not seg.conic.degenerate else seg.t0
		_seg_anchor_t[i] = clampf(tp, seg.t0, seg.t1)
	if tr != null:
		_build_markers(tr)
	_text_timer = 0.0


## Anchor (map units) of segment i: its body now, or a ghost at the periapsis time.
func _anchor(i: int) -> Vector3:
	var seg: FlightTrajectory.Segment = world.traj.segments[i]
	var now := world.time
	var t := now
	if not sys.is_ancestor(seg.body, _frame) and not (seg.plan == 0 and seg.t0 <= now and now <= seg.t1):
		t = _seg_anchor_t[i]
	return body_map(seg.body, t)


func _is_ghost(i: int) -> bool:
	var seg: FlightTrajectory.Segment = world.traj.segments[i]
	var now := world.time
	return not sys.is_ancestor(seg.body, _frame) and not (seg.plan == 0 and seg.t0 <= now and now <= seg.t1)


func _place_trajectory() -> void:
	var px_world := _dist * 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / viewport.size.y
	for i in _seg_count:
		var mi := _seg_nodes[i]
		mi.position = _anchor(i)
		var seg: FlightTrajectory.Segment = world.traj.segments[i]
		mi.set_instance_shader_parameter(&"dash", px_world * 18.0 if seg.plan > 0 else 0.0)
	_update_detail()


## Zoomed in far below the sample spacing: a fine polyline around the vessel replaces the
## coarse one there (gap uniform), rebuilt per frame (64 points) only while needed.
func _update_detail() -> void:
	detail.visible = false
	if world.traj == null:
		return
	var si := world.traj.current_segment_at(world.time)
	if si < 0 or si >= _seg_count:
		return
	var seg: FlightTrajectory.Segment = world.traj.segments[si]
	var c := seg.conic
	var size_km := c.rp * K
	if _dist > size_km * 0.05:
		_seg_nodes[si].set_instance_shader_parameter(&"gap", Vector4.ZERO)
		return
	var st := c.state_at(world.time)
	var speed := sqrt(st[3] * st[3] + st[4] * st[4] + st[5] * st[5])
	var span := _dist * 3.0 / K / maxf(speed, 1.0)
	var t0 := maxf(world.time - span, seg.t0)
	var t1 := minf(world.time + span, seg.t1)
	var anchor := _anchor(si)
	var pts := PackedFloat64Array()
	pts.resize(65 * 3)
	for j in 65:
		var p := c.position_at(lerpf(t0, t1, float(j) / 64.0))
		pts[j * 3] = p[0] + anchor.x / K
		pts[j * 3 + 1] = p[1] + anchor.y / K
		pts[j * 3 + 2] = p[2] + anchor.z / K
	detail.mesh = FlightMapLines.polyline(pts, K, detail.mesh as ArrayMesh)
	detail.position = Vector3.ZERO
	detail.visible = true
	detail.set_instance_shader_parameter(&"line_color", Color(_seg_color(seg), 0.95))
	var vp := _vessel_map()
	_seg_nodes[si].set_instance_shader_parameter(&"gap", Vector4(vp.x, vp.y, vp.z, _dist * 2.6))


func _vessel_map() -> Vector3:
	var p := world.sim.pos()
	var o := sys.pos_rel(world.soi, _frame, world.time)
	return Vector3((p[0] + o[0] - _focus_off[0]) * K, (p[1] + o[1] - _focus_off[1]) * K, (p[2] + o[2] - _focus_off[2]) * K)


## Markers of the prediction: apsides, AN / DN to the target, SOI changes, impact,
## encounter periapsis, closest approach, nodes. Positions relative to each segment's body.
func _build_markers(tr: FlightTrajectory) -> void:
	var first := _mdata.size()
	var enc_target := false
	for i in _seg_count:
		var seg := tr.segments[i]
		var c := seg.conic
		var col := _seg_color(seg)
		var entered := i > 0 and tr.segments[i - 1].end == FlightTrajectory.End.ENCOUNTER
		if seg.body == world.target_body:
			enc_target = true
		if not c.degenerate:
			var t_pe := c.time_at_true_anomaly(0.0, seg.t0)
			if t_pe <= seg.t1 and t_pe > seg.t0 - 1.0:
				var kind := "enc_pe" if entered else "pe"
				_mdata.append({"kind": kind, "seg": i, "pos": c.periapsis_position(), "t": t_pe, "color": col,
					"alt": c.rp - sys.radius[seg.body]})
			if c.e < 1.0:
				var t_ap := c.time_at_true_anomaly(PI, seg.t0)
				if t_ap <= seg.t1 and c.ra < sys.soi[seg.body]:
					_mdata.append({"kind": "ap", "seg": i, "pos": c.apoapsis_position(), "t": t_ap, "color": col,
						"alt": c.ra - sys.radius[seg.body]})
			# AN / DN relative to the target's orbit plane (target orbiting this body)
			var tb := world.target_body
			if tb >= 0 and sys.parent[tb] == seg.body and (i == 0 or tr.segments[i - 1].end == FlightTrajectory.End.NODE):
				var nt := sys.orbit_normal(tb)
				var w := Vector3(c.wx, c.wy, c.wz)
				var inc := rad_to_deg(nt.angle_to(w))
				var nl := c.node_line(nt)
				if inc > 0.05 and nl.size() == 3:
					for k in 2:
						var nu := c.true_anomaly_of(PackedFloat64Array([nl[0], nl[1], nl[2]])) + PI * k
						var r := c.radius_at_true_anomaly(nu)
						if r <= 0.0 or r > sys.soi[seg.body]:
							continue
						var t_n := c.time_at_true_anomaly(nu, seg.t0)
						if t_n > seg.t1:
							continue
						var cu := cos(nu) * r
						var su := sin(nu) * r
						var pos := PackedFloat64Array([c.px * cu + c.qx * su, c.py * cu + c.qy * su, c.pz * cu + c.qz * su])
						_mdata.append({"kind": "an" if k == 0 else "dn", "seg": i, "pos": pos, "t": t_n,
							"color": STYLE.line_icon, "inc": inc})
		var end_pos := c.position_at(seg.t1)
		match seg.end:
			FlightTrajectory.End.ENCOUNTER:
				_mdata.append({"kind": "soi_in", "seg": i, "pos": end_pos, "t": seg.t1, "color": STYLE.soi_color(
					sys.ids[seg.next_body]), "body": seg.next_body})
			FlightTrajectory.End.ESCAPE:
				_mdata.append({"kind": "soi_out", "seg": i, "pos": end_pos, "t": seg.t1, "color": col, "body": seg.body})
			FlightTrajectory.End.IMPACT:
				_mdata.append({"kind": "impact", "seg": i, "pos": end_pos, "t": seg.t1, "color": STYLE.impact_icon})
			FlightTrajectory.End.NODE:
				var nd: FlightManeuverNode = world.plan.nodes[seg.node_index] if seg.node_index < world.plan.nodes.size() else null
				if nd != null:
					_mdata.append({"kind": "node", "seg": i, "pos": end_pos, "t": seg.t1, "color": NODE_COLOR,
						"node": nd})
		if _is_ghost(i) and entered:
			_mdata.append({"kind": "ghost", "seg": i, "pos": PackedFloat64Array([0.0, 0.0, 0.0]), "t": _seg_anchor_t[i],
				"color": sys.colors[seg.body], "body": seg.body})
	# size of each marker's segment (km) for decluttering: the orbit's extent, capped by the SOI
	for j in range(first, _mdata.size()):
		var sg := tr.segments[int(_mdata[j]["seg"])]
		var ext := sg.conic.ra if sg.conic.is_closed() else INF
		_mdata[j]["size"] = minf(ext, sys.soi[sg.body] if sys.soi[sg.body] < INF else 1.0e13) * K * 2.0
		if _mdata[j]["kind"] == "soi_in":
			_mdata[j]["size"] = sys.soi[int(_mdata[j]["body"])] * K * 2.0
	if not tr.closest.is_empty() and world.target_body >= 0 and not enc_target:
		var si: int = tr.closest["seg"]
		if si < _seg_count:
			var seg := tr.segments[si]
			var tc: float = tr.closest["t"]
			_mdata.append({"kind": "closest", "seg": si, "pos": seg.conic.position_at(tc), "t": tc,
				"color": STYLE.closest_icon, "d": tr.closest["d"]})
			_mdata.append({"kind": "closest_target", "seg": si, "pos": sys.pos_rel_parent(world.target_body, tc), "t": tc,
				"color": STYLE.closest_icon})


# ------------------------------------------------------------ overlay
func _place_overlay(dt: float) -> void:
	_text_timer -= dt
	var refresh_text := _text_timer <= 0.0
	if refresh_text:
		_text_timer = 0.25
	var focal := _focal_px()
	var vs := overlay.size
	var now := world.time
	# vessel
	var vpos := _vessel_map()
	vessel_marker.visible = show_vessel and not camera.is_position_behind(vpos)
	vessel_marker.position = camera.unproject_position(vpos) - vessel_marker.size * 0.5
	vessel_marker.modulate.a = 0.35 if occluded(vpos) else 1.0
	# bodies: icon when the mesh is too small, name under it; names that would overlap a
	# more important one (focus, target, frame body, then bigger bodies) are hidden
	var name_rects: Array[Rect2] = []
	for i in _label_order():
		var l := _labels[i]
		var p := _body_nodes[i].position
		if camera.is_position_behind(p):
			l.visible = false
			continue
		var sp := camera.unproject_position(p)
		var cd := maxf(camera.global_position.distance_to(p), 1e-9)
		var px := sys.radius[i] * K * _body_scale[i] / cd * focal   # as drawn (readable blow-up)
		_label_px[i] = px
		_label_screen[i] = sp
		var vis := sp.x > -60.0 and sp.y > -60.0 and sp.x < vs.x + 60.0 and sp.y < vs.y + 60.0
		# declutter: a moon on top of its planet
		var par := sys.parent[i]
		if vis and par >= 0 and i != focus and i != world.target_body and par != sys.sun:
			if _label_screen[par].distance_to(sp) < 18.0 and _labels[par].visible:
				vis = false
		l.visible = vis
		if not vis:
			continue
		l.position = sp
		var icon := l.get_node("Icon") as Control
		var halo := l.get_node("Halo") as Control
		icon.visible = px < 2.5
		halo.visible = px < 2.5 and (i == focus or i == world.target_body)
		var name_l := l.get_node("Name") as Label
		name_l.position.y = maxf(px, 9.0) + 3.0
		var w := name_l.get_minimum_size().x
		var rect := Rect2(sp + Vector2(-w * 0.5, name_l.position.y), Vector2(w, 16.0))
		var free := px < 110.0
		for r in name_rects:
			if r.intersects(rect):
				free = false
				break
		name_l.visible = free
		if free:
			name_rects.append(rect)
		if refresh_text:
			name_l.text = sys.display_name(i)
			var col := STYLE.body_name
			if i == world.target_body:
				col = STYLE.body_name_target
			elif i == _frame:
				col = STYLE.body_name_focus
			name_l.add_theme_color_override("font_color", col)
	_place_markers(refresh_text, now)
	_place_gizmo(refresh_text)
	_update_hover()


func _place_markers(refresh_text: bool, now: float) -> void:
	var mi := 0
	var placed := PackedVector2Array()
	for md in _mdata:
		if mi >= _markers.size():
			break
		var si: int = md["seg"]
		if world.traj == null or si >= _seg_count:
			continue
		var kind: String = md["kind"]
		if kind == "node" and md["node"] == selected and gizmo.visible:
			md.erase("screen")
			continue
		var pos: PackedFloat64Array = md["pos"]
		var a := _anchor(si)
		if kind == "closest_target":
			a = body_map(sys.parent[world.target_body], float(md["t"]))
		var p := a + Vector3(pos[0] * K, pos[1] * K, pos[2] * K)
		var cd := camera.global_position.distance_to(p)
		# declutter: markers of a segment that is tiny on screen, or far beyond the view
		var seg_px := float(md.get("size", 1e12)) / maxf(camera.global_position.distance_to(a), 1e-9) * _focal_px()
		var small := (seg_px < 40.0 and kind in ["ap", "pe", "an", "dn"]) or (seg_px < 24.0 and kind != "node")
		if camera.is_position_behind(p) or cd > _dist * 60.0 or small:
			md.erase("screen")
			continue
		var sp := camera.unproject_position(p)
		md["screen"] = sp
		var m := _markers[mi]
		mi += 1
		m.visible = true
		m.position = sp
		m.modulate.a = 0.35 if occluded(p) else 1.0
		# markers on (almost) the same spot: stack their labels instead of overprinting
		var stack := 0
		for q in placed:
			if q.distance_to(sp) < 16.0:
				stack += 1
		placed.append(sp)
		(m.get_node("Label") as Control).position.y = -11.0 + stack * 24.0
		if refresh_text or m.get_meta("kind", "") != kind:
			m.set_meta("kind", kind)
			_style_marker(m, md, now)
	for j in range(mi, _markers.size()):
		_markers[j].visible = false


func _style_marker(m: Control, md: Dictionary, now: float) -> void:
	var icon := m.get_node("Icon") as TextureRect
	var label := m.get_node("Label") as Label
	var kind: String = md["kind"]
	var col: Color = md["color"]
	var t: float = md["t"]
	var eta := fmt_eta(t - now)
	icon.self_modulate = col
	icon.rotation = 0.0
	icon.size = Vector2(20, 20)
	icon.position = Vector2(-10, -10)
	label.add_theme_color_override("font_color", STYLE.label_text)
	label.visible = true
	match kind:
		"ap":
			icon.texture = ICON_APSIS
			icon.self_modulate = STYLE.apsis_icon
			label.text = tr("FL_CW_MAP_AP") % [FlightHUD.fmt_dist(md["alt"]), eta]
		"pe", "enc_pe":
			icon.texture = ICON_APSIS
			icon.self_modulate = col
			var alt: float = md["alt"]
			label.text = tr("FL_CW_MAP_PE") % [FlightHUD.fmt_dist(alt), eta]
			if alt < 0.0:
				label.text = tr("FL_CW_MAP_PE_LOW") % [FlightHUD.fmt_dist(alt), eta]
				label.add_theme_color_override("font_color", STYLE.label_danger)
		"an", "dn":
			icon.texture = ICON_LINE
			label.text = tr("FL_CW_MAP_CROSS") % float(md["inc"])
			label.add_theme_color_override("font_color", STYLE.label_dim)
		"soi_in":
			icon.texture = ICON_SOI
			label.text = tr("FL_CW_MAP_ENCOUNTER") % [sys.display_name(md["body"]), eta]
			label.add_theme_color_override("font_color", STYLE.label_encounter)
		"soi_out":
			icon.texture = ICON_SOI
			label.text = tr("FL_CW_MAP_ESCAPE") % [sys.display_name(md["body"]), eta]
		"impact":
			icon.texture = ICON_IMPACT
			label.text = tr("FL_CW_MAP_IMPACT") % eta
			label.add_theme_color_override("font_color", STYLE.label_danger)
		"closest":
			icon.texture = ICON_CLOSEST
			label.text = tr("FL_CW_MAP_CLOSEST") % [FlightHUD.fmt_dist(md["d"]), eta]
			label.add_theme_color_override("font_color", STYLE.label_warning)
		"closest_target":
			icon.texture = ICON_BODY
			label.text = ""
			label.visible = false
		"ghost":
			icon.texture = ICON_BODY
			icon.size = Vector2(16, 16)
			icon.position = Vector2(-8, -8)
			label.text = tr("FL_CW_MAP_GHOST") % sys.display_name(md["body"])
			label.add_theme_color_override("font_color", STYLE.label_dim)
		"node":
			icon.texture = ICON_NODE
			icon.size = Vector2(28, 28)
			icon.position = Vector2(-14, -14)
			var nd: FlightManeuverNode = md["node"]
			label.text = tr("FL_CW_MAP_NODE") % [FlightHUD.fmt_speed(nd.dv_total()), eta]
			label.add_theme_color_override("font_color", STYLE.label_node)
	# the paper pill hugs the text
	label.reset_size()


static func fmt_eta(s: float) -> String:
	if is_inf(s) or is_nan(s):
		return "—"
	var a := absf(s)
	var sign := "T-" if s >= 0.0 else "T+"
	if a >= 86400.0 * 365.25:
		return "%s %.1f y" % [sign, a / (86400.0 * 365.25)]
	if a >= 86400.0:
		return "%s %dd %02dh" % [sign, int(a / 86400.0), int(fmod(a, 86400.0) / 3600.0)]
	return "%s %s" % [sign, FlightHUD.fmt_time(a)]


func _place_gizmo(refresh_text: bool) -> void:
	_handle_pos.clear()
	_gz_stems.clear()
	_gz_burn = Vector2.ZERO
	var was_visible := gizmo.visible
	gizmo.visible = false
	if selected == null or not selected.valid or world.traj == null or not world.plan.nodes.has(selected):
		if selected != null and not world.plan.nodes.has(selected):
			select_node(null)
		return
	var si := -1
	var idx := world.plan.index_of(selected)
	for i in _seg_count:
		var s: FlightTrajectory.Segment = world.traj.segments[i]
		if s.end == FlightTrajectory.End.NODE and s.node_index == idx:
			si = i
			break
	if si < 0:
		return
	var st := selected.state
	var center := _anchor(si) + Vector3(st[0] * K, st[1] * K, st[2] * K)
	var nb := selected.body
	var soi_px := minf(sys.soi[nb], 1.0e13) * K / maxf(camera.global_position.distance_to(_anchor(si)), 1e-9) * _focal_px()
	if camera.is_position_behind(center) or soi_px < 30.0:
		return
	gizmo.visible = true
	gizmo.modulate.a = 0.55 if occluded(center) else 1.0
	var sc := camera.unproject_position(center)
	_gizmo_center = sc
	gizmo.position = sc
	var f := FlightManeuverNode.frame(st)
	var cdist := maxf(camera.global_position.distance_to(center), 1e-9)
	var l := cdist * 0.01
	var l_px := l / cdist * _focal_px()
	var dirs := {"Pro": f[0], "Retro": -f[0], "Normal": f[1], "Anti": -f[1], "RadOut": f[2], "RadIn": -f[2]}
	for h in dirs:
		var hp := sc + _screen_dir(center, dirs[h], l, l_px, sc) * HANDLE_PX
		var n := gizmo.get_node(h) as Control
		n.position = hp - sc - n.size * 0.5
		_handle_pos[h] = hp
		_gz_stems[h] = [hp - sc, (n as CanvasItem).self_modulate]
	# burn direction (the planned Δv in world axes), longer than the handles so its tip
	# shows past them
	var dvw := Vector3(selected.dv_world[0], selected.dv_world[1], selected.dv_world[2])
	if selected.dv_total() > 0.05 and dvw.length_squared() > 1e-6:
		_gz_burn = _screen_dir(center, dvw.normalized(), l, l_px, sc) * HANDLE_PX * 1.45
	_handle_pos["delete"] = sc + Vector2(26, -26)
	# hovered / dragged handle grows
	var hov := _drag_handle if _drag == "dv" else (_handle_at(_mouse) if not _rmb else "")
	for h in _handle_pos:
		var hn := gizmo.get_node("Delete" if h == "delete" else h) as Control
		hn.pivot_offset = hn.size * 0.5
		hn.scale = Vector2.ONE * (1.3 if h == hov else 1.0)
	_gz_hover = hov
	gizmo.queue_redraw()
	if refresh_text or _drag == "dv" or not was_visible:
		var t := gizmo.get_node("Tag/Text") as Label
		var bt := world.node_burn_time(selected)
		var txt := "Δv %s · %s
%s %s" % [FlightHUD.fmt_speed(selected.dv_total()), fmt_eta(selected.time - world.time),
			tr("FL_BURN"), FlightHUD.fmt_time(bt) if bt > 0.0 else "—"]
		if hov != "" and hov != "delete":
			var d := selected.dv
			var comp := {"Pro": d.x, "Retro": -d.x, "Normal": d.y, "Anti": -d.y, "RadOut": d.z, "RadIn": -d.z}
			txt += "
%s %s" % [tr(HANDLE_NAMES[hov]), FlightHUD.fmt_speed(comp[hov])]
		t.text = txt


## Screen direction (unit, scaled by foreshortening) of world direction `dir` at `center`:
## a handle pointing at the camera still gets a little room.
func _screen_dir(center: Vector3, dir: Vector3, l: float, l_px: float, sc: Vector2) -> Vector2:
	var tip := center + dir * l
	var d := Vector2.ZERO
	if not camera.is_position_behind(tip):
		d = camera.unproject_position(tip) - sc
	var dl := d.length()
	var dirn := d / dl if dl > 1e-3 else Vector2(0, -1)
	return dirn * clampf(dl / maxf(l_px, 1e-6), 0.35, 1.0)


## Gizmo lines (under its icons): a dark disc behind the centre, a stem per handle in
## its colour, and the burn arrow in the maneuver colour.
func _draw_gizmo() -> void:
	if not gizmo.visible:
		return
	gizmo.draw_circle(Vector2.ZERO, 19.0, Color(CwPalette.INK, 0.6))
	for h in _gz_stems:
		var tip: Vector2 = _gz_stems[h][0]
		var col: Color = _gz_stems[h][1]
		var ln := tip.length()
		if ln < 34.0:
			continue
		var u := tip / ln
		var hot: bool = h == _gz_hover
		gizmo.draw_line(u * 17.0, tip - u * 15.0, Color(CwPalette.INK, 0.65), 5.0 if hot else 4.0, true)
		gizmo.draw_line(u * 17.0, tip - u * 15.0, Color(col, 0.95 if hot else 0.6), 2.5 if hot else 1.6, true)
	if _gz_burn != Vector2.ZERO:
		var ln := _gz_burn.length()
		var u := _gz_burn / ln
		var side := Vector2(-u.y, u.x)
		var base := _gz_burn - u * 11.0
		var head := PackedVector2Array([_gz_burn, base + side * 6.5, base - side * 6.5])
		gizmo.draw_line(u * 17.0, base, Color(CwPalette.INK, 0.65), 6.0, true)
		gizmo.draw_line(u * 17.0, base, NODE_COLOR, 3.0, true)
		gizmo.draw_colored_polygon(head, NODE_COLOR)
		gizmo.draw_polyline(PackedVector2Array([_gz_burn, base + side * 6.5, base - side * 6.5, _gz_burn]),
			Color(CwPalette.INK, 0.75), 1.2, true)


## Hovering the trajectory: where a click would add a node.
func _update_hover() -> void:
	if _drag != "" or _rmb:
		hover_marker.visible = false
		return
	# re-projected when the mouse moves, else a few times a second (bodies / camera move):
	# up to a few thousand unproject calls, kept off most frames
	if _hover_dirty or Engine.get_process_frames() - _proj_frame >= 6:
		_hover_dirty = false
		_proj_frame = Engine.get_process_frames()
		_hover = {}
		if world.traj != null and _handle_at(_mouse) == "" and _mouse.distance_to(_gizmo_center) > 20.0:
			var best_d := 11.0
			for si in _seg_count:
				var h := _nearest_on_screen(si, _mouse, best_d)
				if not h.is_empty():
					_hover = h
					best_d = h["d"]
	hover_marker.visible = not _hover.is_empty() and _body_at(_mouse) < 0
	if hover_marker.visible:
		hover_marker.position = _hover["screen"]
		hover_label.text = tr("FL_MAP_ADD_NODE") % fmt_eta(float(_hover["t"]) - world.time)


## Nearest point (screen) of segment si to p closer than max_d: {"t", "d", "screen", "seg"}.
func _nearest_on_screen(si: int, p: Vector2, max_d: float) -> Dictionary:
	var seg: FlightTrajectory.Segment = world.traj.segments[si]
	var a := _anchor(si)
	var n := seg.count()
	var best := {}
	var prev := Vector2.ZERO
	var prev_ok := false
	var stride := 1 if n < 700 else 2
	var i := 0
	while i < n:
		var q := a + Vector3(seg.pts[i * 3] * K, seg.pts[i * 3 + 1] * K, seg.pts[i * 3 + 2] * K)
		var ok := not camera.is_position_behind(q)
		var sp := camera.unproject_position(q) if ok else Vector2.ZERO
		if ok and prev_ok:
			var ab := sp - prev
			var l2 := ab.length_squared()
			var f := clampf((p - prev).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
			var c := prev + ab * f
			var d := c.distance_to(p)
			if d < max_d:
				max_d = d
				var i0 := maxi(i - stride, 0)
				var t := lerpf(seg.times[i0], seg.times[i], f)
				best = {"t": t, "d": d, "screen": c, "seg": si}
		prev = sp
		prev_ok = ok
		if i == n - 1:
			break
		i = mini(i + stride, n - 1)
	return best
