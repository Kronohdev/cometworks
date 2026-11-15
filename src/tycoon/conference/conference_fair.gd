class_name ConferenceFair
extends Node3D
## The Conferência dos Cometinhos' fair (scenes/tycoon/conference/conference_fair.tscn), opened
## by ConferenceFlow inside the tycoon scene while the campus sleeps. The scene holds what is
## fixed: the sun, the ground and the plaza, the props, the camera, the HUD and the markers where
## things go (Spawn, Exit, Host, Stands/*, Spots/*, Exhibit). This script fills the rest from the
## campaign:
##   - one stand per rival agency at the Stands markers (in the rivals' order), in its colour,
##     with its name, motto and a live board (ConferenceBook.board_text), its leader Lenda in
##     front of the counter
##   - the host (data: "host", Joãozinho Keplerino) at his gossip kiosk, by the Host marker
##   - the guests (ConferenceBook.attendees) two by two at the Spots, a bench behind them; the
##     Lendas with a campus exchange of their own stand together and trade it in bubbles when the
##     player walks up (CampusChatter.say, the chatter's camera lent to the fair)
##   - the player's leader (ConferencePlayer) walking among them; the nearest Lenda in reach (or
##     the gate) shows a prompt: E (or Enter / the pad's A) talks, through the campus dialogue
##     box (CometlingDialogue.open_run with ConferenceBook.make_run), or leaves
##   - Esc (or the pad's Start) opens the pause card: keep strolling or "Sair da feira"
## The mouse is captured while walking and given back for a conversation or the card.
## The look: the ground is shaders/conference_ground.gdshader (paving, walkways and the
## exhibit's rosette on the plaza, grass and a worn fringe round it); the lamps, stage, food
## stall, planters, kerb and plants are scenes/tycoon/conference/conference_dressing.tscn
## (tools/build_conference_dressing.gd); the bunting (`bunting`) is strung here in the
## agencies' colours.

signal leave_requested

const CREATURE := preload("res://scenes/npc/creature.tscn")
const BENCH := preload("res://assets/campus/dressing/bench_wood.glb")
const CRATES := preload("res://assets/campus/dressing/crate_stack.glb")
const TELESCOPE := preload("res://assets/campus/props/telescope.glb")
const TOON := preload("res://shaders/cw_toon_solid.gdshader")
const HOST_COLOR := Color("#8e7cff")
const GATE_COLOR := Color("#f59a36")

## the Cometlings' size at the fair (the campus walkers' Creature scale)
@export var creature_scale := 1.6
## the walkable floor (local x / z)
@export var bounds := Rect2(-27.0, -21.0, 54.0, 42.0)
## how close the gate must be to leave (m)
@export var exit_distance := 3.6
## the bunting: pairs of anchor points (local), one garland of flags from each first to each
## second point, sagging in between
@export var bunting := PackedVector3Array([
	# round the rim, lamp to lamp, and onto the gate
	Vector3(-9.5, 4.45, 20.8), Vector3(-3.6, 5.0, 20.5), Vector3(3.6, 5.0, 20.5), Vector3(9.5, 4.45, 20.8),
	Vector3(9.5, 4.45, 20.8), Vector3(26.6, 4.45, 9.0), Vector3(26.6, 4.45, 9.0), Vector3(26.6, 4.45, -9.0),
	Vector3(26.6, 4.45, -9.0), Vector3(11.0, 4.45, -20.7), Vector3(11.0, 4.45, -20.7), Vector3(-11.0, 4.45, -20.7),
	Vector3(-11.0, 4.45, -20.7), Vector3(-26.6, 4.45, -9.0), Vector3(-26.6, 4.45, -9.0), Vector3(-26.6, 4.45, 9.0),
	Vector3(-26.6, 4.45, 9.0), Vector3(-9.5, 4.45, 20.8),
	# from the exhibit rocket out to the lamps, like a maypole
	Vector3(0, 8.2, -5.0), Vector3(-9.5, 4.45, 20.8), Vector3(0, 8.2, -5.0), Vector3(9.5, 4.45, 20.8),
	Vector3(0, 8.2, -5.0), Vector3(-26.6, 4.45, 9.0), Vector3(0, 8.2, -5.0), Vector3(26.6, 4.45, 9.0),
	Vector3(0, 8.2, -5.0), Vector3(-26.6, 4.45, -9.0), Vector3(0, 8.2, -5.0), Vector3(26.6, 4.45, -9.0),
	Vector3(0, 8.2, -5.0), Vector3(-11.0, 4.45, -20.7), Vector3(0, 8.2, -5.0), Vector3(11.0, 4.45, -20.7),
])
## metres between two flags of the bunting
@export var flag_spacing := 0.6

var state: TycoonState
var talk: CometlingDialogue
var chatter: CampusChatter
## [{"node": Node3D, "id", "role", "rival", "look"}]
var npcs: Array[Dictionary] = []
## the Lenda-to-Lenda exchanges standing here: [{"a": Node3D, "b": Node3D, "a_key", "b_key", "said"}]
var duo_nodes: Array[Dictionary] = []
## what the prompt points at: {"npc": entry} | {"exit": true} | {}
var focus: Dictionary = {}
var run: DialogueRun
var run_npc: Dictionary = {}
var _circles: Array[Vector3] = []          # x, z, radius
var _boxes: Array[Dictionary] = []         # {"c": Vector2, "half": Vector2, "rot": float}
var _replies: Array[Dictionary] = []       # {"t", "who", "text", "key", "look"}
var _greeted := {}
var _talk_distance := 3.4
var _pair_distance := 9.0
var _flash_t := 0.0

@onready var player: ConferencePlayer = $Player
@onready var camera: Camera3D = $Camera
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	%Menu.visible = false
	%Prompt.visible = false
	%Flash.visible = false
	%Resume.pressed.connect(func() -> void: show_menu(false))
	%Leave.pressed.connect(func() -> void: leave_requested.emit())


## Fills the fair for the campaign and hands the player the leader. `p_talk` / `p_chatter` are
## the campus dialogue box and speech bubbles (either may be null in tests).
func open(s: TycoonState, p_talk: CometlingDialogue, p_chatter: CampusChatter) -> void:
	state = s
	talk = p_talk
	chatter = p_chatter
	_talk_distance = float(ConferenceBook.cfg("talk_distance", 3.4))
	_pair_distance = float(ConferenceBook.cfg("pair_distance", 9.0))
	_build_gate()
	_build_exhibit()
	_build_bunting()
	_fill_people()
	_dress_player()
	player.camera = camera
	player.collide = collide
	player.configure()
	var sp := $Markers/Spawn as Node3D
	player.place(sp.position, sp.rotation.y)
	camera.make_current()
	%Title.text = tr("TY_CONF_TITLE")
	%Sub.text = tr("TY_CONF_FAIR_SUB").format({"year": s.year()})
	%Keys.text = tr("TY_CONF_KEYS")
	%Resume.text = tr("TY_CONF_RESUME")
	%Leave.text = tr("TY_CONF_LEAVE")
	%MenuTitle.text = tr("TY_CONF_MENU_TITLE")
	refresh_count()
	flash(tr("TY_CONF_WELCOME"), 5.0)
	if talk:
		talk.closed.connect(_on_talk_closed)
	set_walking(true)


## The campus' time of day at the fair: the sun takes the colour, strength and direction of the
## campus key light (CampusDayCycle drives it; at night it keeps a little strength so the fair
## stays readable) and the campus' other directional lights (the Moon) come along as copies.
## `lights` is the campus' Lights node (null keeps the scene's own sun).
func match_sky(lights: Node) -> void:
	if lights == null:
		return
	var sun := $Sun as DirectionalLight3D
	var first := true
	for l in lights.get_children():
		if not l is DirectionalLight3D:
			continue
		var d := l as DirectionalLight3D
		if first:
			first = false
			sun.light_color = d.light_color
			sun.light_energy = maxf(d.light_energy, float(ConferenceBook.cfg("min_sun", 0.9)))
			sun.global_basis = d.global_basis
		else:
			var copy := DirectionalLight3D.new()
			copy.light_color = d.light_color
			copy.light_energy = d.light_energy
			copy.light_specular = d.light_specular
			copy.sky_mode = d.sky_mode
			add_child(copy)
			copy.global_basis = d.global_basis


## Lets go of the mouse (ConferenceFlow frees the fair right after).
func close() -> void:
	if talk and talk.closed.is_connected(_on_talk_closed):
		talk.closed.disconnect(_on_talk_closed)
	player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_walking(on: bool) -> void:
	player.enabled = on
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func show_menu(on: bool) -> void:
	%Menu.visible = on
	set_walking(not on and not is_talking())


func is_talking() -> bool:
	return talk != null and talk.is_open()


# ------------------------------------------------------------ building the fair
static func _mat(c: Color, glow := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", c)
	if glow > 0.0:
		m.set_shader_parameter("emission", c)
		m.set_shader_parameter("emission_energy", glow)
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, c: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, glow)
	mi.position = at
	parent.add_child(mi)
	return mi


static func _label(parent: Node3D, text: String, at: Vector3, px: float, size: int, c := Color.WHITE,
		outline := Color("#2b2a5c")) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.pixel_size = px
	l.font_size = size
	l.outline_size = maxi(size / 6, 4)
	l.modulate = c
	l.outline_modulate = outline
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = 900.0
	parent.add_child(l)
	return l


## The yaw that turns a node at `p` (local) to face the plaza's centre.
static func _face_centre(p: Vector3) -> float:
	return atan2(-p.x, -p.z)


func _block_box(centre: Vector3, half: Vector2, rot: float) -> void:
	_boxes.append({"c": Vector2(centre.x, centre.z), "half": half, "rot": rot})


func _block_circle(p: Vector3, r: float) -> void:
	_circles.append(Vector3(p.x, p.z, r))


func _build_gate() -> void:
	var ex := $Markers/Exit as Node3D
	var g := Node3D.new()
	g.name = "Gate"
	g.position = ex.position
	$Built.add_child(g)
	for sx in [-3.4, 3.4]:
		_box(g, Vector3(0.45, 4.4, 0.45), Vector3(sx, 2.2, 0.0), Color("#fffdf8"))
		_block_circle(ex.position + Vector3(sx, 0, 0), 0.5)
	_box(g, Vector3(7.6, 0.9, 0.5), Vector3(0, 4.6, 0), GATE_COLOR)
	var banner := _label(g, tr("TY_CONF_BANNER").format({"year": state.year()}), Vector3(0, 4.6, -0.27), 0.006, 64)
	banner.rotation.y = PI   # read from the plaza
	var way_out := _label(g, tr("TY_CONF_EXIT_SIGN"), Vector3(0, 3.6, -0.3), 0.005, 48, Color("#ffe08f"))
	way_out.rotation.y = PI


func _build_exhibit() -> void:
	var m := $Markers.get_node_or_null("Exhibit") as Node3D
	if m:
		_block_circle(m.position, 1.9)
	for p in $Props.find_children("*", "Node3D", true, false):   # props with a footprint (metadata block_radius)
		if p.has_meta("block_radius"):
			_block_circle(to_local((p as Node3D).global_position), float(p.get_meta("block_radius")))


## The garlands of `bunting`: little triangular flags in the rivals' colours and the palette's,
## on a thin cord, as two MultiMeshes (one draw each). No footprint: they hang overhead.
func _build_bunting() -> void:
	if bunting.size() < 2:
		return
	var colours: Array[Color] = []
	for r in state.rivals:
		colours.append(Color(String(r.get("color", "#8c9ab5"))))
	colours.append_array([CwPalette.BUTTER, CwPalette.MINT, CwPalette.PEACH, CwPalette.ICE, CwPalette.PINK, CwPalette.LILAC])
	var flags: Array[Transform3D] = []
	var flag_cols: Array[Color] = []
	var cords: Array[Transform3D] = []
	var k := 0
	for i in range(0, bunting.size() - 1, 2):
		var a := bunting[i]
		var b := bunting[i + 1]
		var length := a.distance_to(b)
		var sag := clampf(length * 0.06, 0.35, 1.5)
		var n := maxi(2, int(length / flag_spacing))
		var pts: Array[Vector3] = []
		for j in n + 1:
			var t := float(j) / n
			pts.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
		for j in n:
			var p0 := pts[j]
			var p1 := pts[j + 1]
			var d := p1 - p0
			var seg := maxf(d.length(), 0.001)
			var along := d / seg
			var side := Vector3.UP.cross(along)
			side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
			cords.append(Transform3D(Basis(side, along.cross(side), along * seg), (p0 + p1) * 0.5))
			if j == 0:
				continue
			# the flag hangs from p0: its face along the cord, its point down
			var flat := Vector3(along.x, 0.0, along.z)
			flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.RIGHT
			var fb := Basis(flat, Vector3.UP, flat.cross(Vector3.UP)) * Basis(Vector3.BACK, PI)
			flags.append(Transform3D(fb, p0 + Vector3.DOWN * 0.21))
			flag_cols.append(colours[k % colours.size()])
			k += 1
	var flag_mesh := PrismMesh.new()
	flag_mesh.size = Vector3(0.36, 0.4, 0.025)
	var fm := _mat(Color.WHITE)
	fm.set_shader_parameter("use_vertex_color", true)
	_multi("Bunting", flag_mesh, fm, flags, flag_cols)
	var cord_mesh := BoxMesh.new()
	cord_mesh.size = Vector3(0.025, 0.025, 1.0)
	_multi("BuntingCord", cord_mesh, _mat(Color("#fff6e6")), cords, [])


func _multi(n: String, mesh: Mesh, mat: Material, xf: Array[Transform3D], cols: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$Built.add_child(mmi)
	return mmi


func _build_stand(marker: Node3D, rid: String) -> Node3D:
	var col := Color(String(state.race.rival(rid).get("color", "#8c9ab5")))
	var st := Node3D.new()
	st.name = "Stand_" + rid
	st.position = marker.position
	st.rotation.y = _face_centre(marker.position)
	$Built.add_child(st)
	var white := Color("#fffdf8")
	# the counter, bands of the agency's colour round it, and a carpet in front
	_box(st, Vector3(4.6, 1.1, 1.0), Vector3(0, 0.55, 0), white)
	_box(st, Vector3(4.64, 0.22, 1.04), Vector3(0, 0.98, 0), col)
	_box(st, Vector3(4.62, 0.12, 1.02), Vector3(0, 0.3, 0), col.lightened(0.25))
	var rug := _box(st, Vector3(4.2, 0.03, 1.8), Vector3(0, 0.065, 1.55), col.lightened(0.15))
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rug_in := _box(st, Vector3(3.9, 0.035, 1.5), Vector3(0, 0.07, 1.55), col.darkened(0.15))
	rug_in.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the back wall with the motto and the live board
	_box(st, Vector3(5.2, 3.3, 0.2), Vector3(0, 1.65, -1.7), col.darkened(0.3))
	_box(st, Vector3(4.7, 1.75, 0.04), Vector3(0, 1.95, -1.58), col.darkened(0.5))
	for sx in [-2.5, 2.5]:
		_box(st, Vector3(0.16, 3.4, 0.16), Vector3(sx, 1.7, 1.0), white)
	# a striped awning sloping to the front, a scalloped valance and a string of bulbs
	for i in 8:
		var stripe := _box(st, Vector3(0.72, 0.1, 3.05), Vector3(-2.52 + i * 0.72, 3.6, -0.3), col if i % 2 == 0 else white)
		stripe.rotation.x = 0.253
	for i in 8:
		var c := white if i % 2 == 0 else col
		_box(st, Vector3(0.66, 0.3, 0.06), Vector3(-2.52 + i * 0.72, 3.08, 1.2), c)
		_box(st, Vector3(0.4, 0.12, 0.06), Vector3(-2.52 + i * 0.72, 2.88, 1.2), c)
	for i in 9:
		var bulb := _box(st, Vector3(0.13, 0.13, 0.13), Vector3(-2.56 + i * 0.64, 2.72, 1.12),
			Color("#ffd25c") if i % 2 == 0 else Color("#fff6e6"), 2.6)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the header board on top: the agency's name, big
	_box(st, Vector3(5.0, 1.15, 0.16), Vector3(0, 4.55, -1.74), col)
	_box(st, Vector3(4.7, 0.9, 0.06), Vector3(0, 4.55, -1.64), Color("#2b2a5c"))
	var title := _label(st, TranslationServer.translate(state.race.agency_name(rid)).to_upper(), Vector3(0, 4.55, -1.6),
		0.0095, 72, Color.WHITE, col.darkened(0.55))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	# two flag poles with banners in the agency's colour
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(0.1, 6.0, 0.1), Vector3(2.75 * sx, 3.0, -1.85), white)
		_box(st, Vector3(0.16, 0.16, 0.16), Vector3(2.75 * sx, 6.05, -1.85), Color("#ffd25c"))
		_box(st, Vector3(0.62, 1.7, 0.05), Vector3(3.08 * sx, 4.9, -1.85), col)
		_box(st, Vector3(0.62, 0.22, 0.055), Vector3(3.08 * sx, 4.55, -1.85), white)
	var motto := ConferenceBook.motto(state, rid)
	if motto != "":
		_label(st, "“%s”" % motto, Vector3(0, 2.5, -1.54), 0.0055, 44, Color("#ffe08f"))
	var board := _label(st, ConferenceBook.board_text(state, rid), Vector3(0, 1.7, -1.54), 0.0052, 40)
	board.name = "Board"
	var crates := CRATES.instantiate() as Node3D
	crates.position = Vector3(3.4, 0, -0.9)
	crates.rotation.y = 0.4
	st.add_child(crates)
	# a warm pool of light under the awning (no shadows)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, 1.3)
	lamp.light_color = Color(1.0, 0.84, 0.66)
	lamp.light_energy = 1.6
	lamp.omni_range = 6.0
	lamp.omni_attenuation = 1.4
	lamp.light_specular = 0.2
	st.add_child(lamp)
	_block_box(st.position + st.basis * Vector3(0, 0, -0.55), Vector2(2.8, 1.35), st.rotation.y)
	_block_circle(st.position + st.basis * Vector3(3.4, 0, -0.9), 1.1)
	return st


func _build_kiosk(marker: Node3D) -> Node3D:
	var k := Node3D.new()
	k.name = "HostKiosk"
	k.position = marker.position
	k.rotation.y = _face_centre(marker.position)
	$Built.add_child(k)
	_box(k, Vector3(2.4, 1.05, 0.9), Vector3(0, 0.52, -0.9), Color("#fffdf8"))
	_box(k, Vector3(2.44, 0.2, 0.94), Vector3(0, 0.95, -0.9), HOST_COLOR)
	for sx in [-1.15, 1.15]:
		_box(k, Vector3(0.12, 2.9, 0.12), Vector3(sx, 1.45, -1.3), Color("#fffdf8"))
	for i in 4:   # a striped roof in the host's colour
		var stripe := _box(k, Vector3(0.7, 0.14, 1.75), Vector3(-1.05 + i * 0.7, 2.98, -0.95),
			HOST_COLOR if i % 2 == 0 else Color("#fffdf8"))
		stripe.rotation.x = 0.2
	for i in 5:
		var bulb := _box(k, Vector3(0.11, 0.11, 0.11), Vector3(-1.12 + i * 0.56, 2.72, -0.12), Color("#ffd25c"), 2.6)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label(k, tr("TY_CONF_HOST_SIGN"), Vector3(0, 2.45, -1.32), 0.005, 48, Color("#ffe08f"))
	var tel := TELESCOPE.instantiate() as Node3D
	tel.position = Vector3(2.2, 0, -0.4)
	tel.rotation.y = -0.6
	k.add_child(tel)
	_block_box(k.position + k.basis * Vector3(0, 0, -0.95), Vector2(1.4, 0.7), k.rotation.y)
	_block_circle(k.position + k.basis * Vector3(2.2, 0, -0.4), 0.9)
	return k


## The rivals' leaders at their stands, the host at his kiosk, the guests two by two.
func _fill_people() -> void:
	var people := ConferenceBook.attendees(state)
	var stands := $Markers/Stands.get_children()
	var spots := $Markers/Spots.get_children()
	var guests: Array[String] = []
	var role_of := {}
	var si := 0
	for p in people:
		var id := String(p["id"])
		role_of[id] = p
		match String(p["role"]):
			ConferenceBook.ROLE_HOST:
				var hm := $Markers/Host as Node3D
				var k := _build_kiosk(hm)
				_spawn(p, k.position, k.rotation.y)
			ConferenceBook.ROLE_RIVAL:
				if si >= stands.size():
					continue
				var st := _build_stand(stands[si] as Node3D, String(p["rival"]))
				si += 1
				_spawn(p, st.position + st.basis * Vector3(0, 0, 1.3), st.rotation.y)
			_:
				guests.append(id)
	# guests: the exchanges first (both in one spot), then the others two by two
	var slots: Array = []   # [[a_id, b_id], ...]
	var duos := ConferenceBook.duos(guests)
	var placed := {}
	for d in duos:
		slots.append([String(d["a"]), String(d["b"]), d])
		placed[String(d["a"])] = true
		placed[String(d["b"])] = true
	var rest: Array[String] = []
	for g in guests:
		if not placed.has(g):
			rest.append(g)
	for i in range(0, rest.size(), 2):
		slots.append([rest[i], rest[i + 1] if i + 1 < rest.size() else "", {}])
	for i in mini(slots.size(), spots.size()):
		var c := (spots[i] as Node3D).position
		var yaw := _face_centre(c)
		var turn := Basis(Vector3.UP, yaw)
		var tangent := turn.x
		var bench := BENCH.instantiate() as Node3D
		bench.position = c - turn.z * 1.5
		bench.rotation.y = yaw
		$Built.add_child(bench)
		_block_box(bench.position, Vector2(1.25, 0.45), yaw)
		var slot: Array = slots[i]
		var a := String(slot[0])
		var b := String(slot[1])
		var na: Dictionary = {}
		var nb: Dictionary = {}
		if b == "":
			na = _spawn(role_of[a], c, yaw)
		else:
			na = _spawn(role_of[a], c + tangent * 0.95, yaw - 0.55)
			nb = _spawn(role_of[b], c - tangent * 0.95, yaw + 0.55)
		var d: Dictionary = slot[2]
		if not d.is_empty() and not nb.is_empty():
			duo_nodes.append({"a": na["node"], "b": nb["node"], "a_key": String(d["a_key"]), "b_key": String(d["b_key"]),
				"said": false})


## One Lenda at `at` (local), turned to `yaw`: its own Cometling scene, else the shared one in
## its colours and hat. Returns its entry in `npcs`.
func _spawn(p: Dictionary, at: Vector3, yaw: float) -> Dictionary:
	var id := String(p["id"])
	var look := TycoonLegends.look(id)
	var holder := Node3D.new()
	holder.name = "Lenda_" + id
	holder.position = at
	holder.rotation.y = yaw
	holder.set_meta("talk_name", TycoonLegends.key(id, "NAME"))
	holder.set_meta("talk_id", id)
	$Npcs.add_child(holder)
	var c: Cometling = TycoonLegends.instance(id)
	var own := c != null
	if c == null:
		c = CREATURE.instantiate() as Cometling
	c.name = "Creature"
	c.listen_to_events = false
	c.personality_seed = absi(hash(id)) % 1000
	holder.add_child(c)
	c.scale = Vector3.ONE * creature_scale
	if not own:
		TycoonLeader.apply_look(c, look)
	c.glow_color = TycoonCrew.profession_color(state, String(look.get("profession", "")))
	_block_circle(at, 0.75)
	var e := {"node": holder, "id": id, "role": String(p["role"]), "rival": String(p.get("rival", "")), "look": look}
	npcs.append(e)
	return e


func _dress_player() -> void:
	var m := TycoonLeader.member(state)
	var c := player.get_node("Creature") as Cometling
	if not m.is_empty():
		c = TycoonLeader.dress(c, m)
		c.glow_color = TycoonCrew.profession_color(state, String(m.get("profession", "")))
	c.listen_to_events = false
	player.creature = c


# ------------------------------------------------------------ walking
## Where a step from `from` toward `to` (local x / z) ends: inside the floor, out of the stands,
## the props and the Lendas (slides along them).
func collide(from: Vector2, to: Vector2) -> Vector2:
	var r := ConferenceBook.player_cfg("body_radius", 0.7)
	var p := to
	for _i in 2:
		for c in _circles:
			var d := p - Vector2(c.x, c.y)
			var min_d := c.z + r
			if d.length_squared() < min_d * min_d:
				p = Vector2(c.x, c.y) + (d.normalized() if d.length() > 0.001 else (from - Vector2(c.x, c.y)).normalized()) * min_d
		for b in _boxes:
			var local := (p - (b["c"] as Vector2)).rotated(float(b["rot"]))
			var half: Vector2 = b["half"] + Vector2(r, r)
			if absf(local.x) < half.x and absf(local.y) < half.y:
				# push out through the nearest side
				var dx := half.x - absf(local.x)
				var dy := half.y - absf(local.y)
				if dx < dy:
					local.x = signf(local.x) * half.x if local.x != 0.0 else half.x
				else:
					local.y = signf(local.y) * half.y if local.y != 0.0 else half.y
				p = (b["c"] as Vector2) + local.rotated(-float(b["rot"]))
	p.x = clampf(p.x, bounds.position.x + r, bounds.end.x - r)
	p.y = clampf(p.y, bounds.position.y + r, bounds.end.y - r)
	return p


func _process(delta: float) -> void:
	if state == null:
		return
	_update_focus()
	_run_pairs(delta)
	_greet()
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			%Flash.visible = false


func _update_focus() -> void:
	var f := {}
	if player.enabled:
		var best := _talk_distance
		var me := player.global_position
		var fwd := player.forward()
		for e in npcs:
			var n: Node3D = e["node"]
			var to := n.global_position - me
			to.y = 0.0
			var d := to.length()
			if d < best and (d < 1.6 or fwd.dot(to / maxf(d, 0.001)) > -0.25):
				best = d
				f = {"npc": e}
		if f.is_empty():
			var ex := ($Markers/Exit as Node3D).global_position
			if Vector2(ex.x - me.x, ex.z - me.z).length() < exit_distance:
				f = {"exit": true}
	focus = f
	%Prompt.visible = not f.is_empty()
	if f.has("npc"):
		%PromptText.text = tr("TY_CONF_PROMPT_TALK").format({"name": TycoonLegends.name_text(String(f["npc"]["id"]))})
	elif f.has("exit"):
		%PromptText.text = tr("TY_CONF_PROMPT_EXIT")


## The Lendas who stand together trade their exchange once when the player walks up.
func _run_pairs(delta: float) -> void:
	for q in _replies.duplicate():
		q["t"] = float(q["t"]) - delta
		if float(q["t"]) > 0.0:
			continue
		_replies.erase(q)
		if chatter and is_instance_valid(q["who"]):
			chatter.say(q["who"], String(q["text"]), -1.0, String(q["key"]))
			_look(q["who"], q["look"])
	if chatter == null or is_talking():
		return
	for d in duo_nodes:
		if d["said"]:
			continue
		var a: Node3D = d["a"]
		var b: Node3D = d["b"]
		var mid := (a.global_position + b.global_position) * 0.5
		if mid.distance_to(player.global_position) > _pair_distance:
			continue
		d["said"] = true
		var na := TycoonLegends.name_text(String(a.get_meta("talk_id")))
		var nb := TycoonLegends.name_text(String(b.get_meta("talk_id")))
		chatter.say(a, ChatterBook.text(String(d["a_key"]), {"name": na, "other": nb}), -1.0, String(d["a_key"]))
		_look(a, b)
		_replies.append({"t": float(ChatterBook.chatter().get("pair_reply_delay", 1.5)) + 0.6, "who": b,
			"text": ChatterBook.text(String(d["b_key"]), {"name": nb, "other": na}), "key": String(d["b_key"]), "look": a})


func _look(who: Node3D, at: Node3D) -> void:
	var c := ChatterBook.find_creature(who)
	if c and is_instance_valid(at):
		c.look_at_point(ChatterBook.head_point(at), 0.7)


## A Lenda waves once when the player first comes near.
func _greet() -> void:
	for e in npcs:
		var n: Node3D = e["node"]
		if _greeted.has(n) or n.global_position.distance_to(player.global_position) > 6.0:
			continue
		_greeted[n] = true
		var c := ChatterBook.find_creature(n)
		if c and not is_talking():
			c.look_at_point(player.head(), 0.6)
			c.play("wave")


# ------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if state == null or is_talking():
		return
	var act := false
	var esc := false
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		act = k in [KEY_E, KEY_ENTER, KEY_KP_ENTER]
		esc = k == KEY_ESCAPE
	elif event is InputEventJoypadButton and event.pressed:
		var jb := (event as InputEventJoypadButton).button_index
		act = jb == JOY_BUTTON_A
		esc = jb == JOY_BUTTON_START
	if esc:
		show_menu(not %Menu.visible)
		get_viewport().set_input_as_handled()
	elif act and not %Menu.visible:
		interact()
		get_viewport().set_input_as_handled()


## E on what the prompt shows: talk to the Lenda, or leave by the gate.
func interact() -> bool:
	if focus.has("exit"):
		leave_requested.emit()
		return true
	if focus.has("npc"):
		return talk_to(focus["npc"])
	return false


## Opens the dialogue box on a Lenda of the fair. False without the box or a tree.
func talk_to(e: Dictionary) -> bool:
	if talk == null:
		return false
	var world: Dictionary = chatter.world() if chatter else {}
	var r := ConferenceBook.make_run(state, String(e["id"]), String(e["role"]), String(e["rival"]), world)
	var n: Node3D = e["node"]
	# face each other before the box turns the Lenda to the camera
	var to := n.global_position - player.global_position
	player.rotation.y = atan2(to.x, to.z)
	if not talk.open_run(r, n, e["look"]):
		return false
	run = r
	run_npc = e
	set_walking(false)
	%Prompt.visible = false
	ConferenceBook.talked(state, String(e["id"]))
	return true


func _on_talk_closed(_who: Node3D) -> void:
	if run and not run_npc.is_empty():
		if String(run_npc["role"]) == ConferenceBook.ROLE_RIVAL and "{conf_status}" in run._seen_lines:
			ConferenceBook.heard(state, String(run_npc["rival"]))
	run = null
	run_npc = {}
	refresh_count()
	set_walking(not %Menu.visible)


# ------------------------------------------------------------ HUD
func refresh_count() -> void:
	var st := ConferenceBook.store(state)
	var rivals := 0
	for e in npcs:
		if String(e["role"]) == ConferenceBook.ROLE_RIVAL:
			rivals += 1
	%Count.text = tr("TY_CONF_FAIR_COUNT").format({"talked": (st["talked"] as Array).size(), "total": npcs.size(),
		"heard": (st["heard"] as Array).size(), "rivals": rivals})


func flash(text: String, seconds := 3.0) -> void:
	%Flash.text = text
	%Flash.visible = true
	_flash_t = seconds
