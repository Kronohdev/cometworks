extends SceneTree
## Authoring helper for the dressing of the Conferência dos Cometinhos' fair: writes
## scenes/tycoon/conference/conference_dressing.tscn, instanced under Props in
## scenes/tycoon/conference/conference_fair.tscn. Re-running replaces the file (same seeds, same
## result); nothing here is generated at runtime. It holds:
##   Curb       the pale stone kerb round the plaza (open at the gate)
##   Lamps      warm lamp posts on the plaza's rim with agency-coloured pennants, outside the
##              walkable floor (ConferenceFair.bounds), so they need no footprint
##   Stage      a little stage with speakers, bulbs and a spot (front-right corner)
##   FoodStall  a cotton-candy cart with a striped awning and crates (front-left corner)
##   DesignLab  the Mission Design Lab booth (an easter egg after NASA Goddard's): a deck, a navy
##              wall with two whiteboards of mission sketches (an orbit, a trade study), the
##              "Mission Design Lab" banner, a table covered in sketches, a blueprint, a laptop
##              and models, a flip chart with the CML ladder, an "Office Hours" sign; Team1..3
##              mark where ConferenceFair puts its Cometlings (conference.json design_lab). Back
##              row, between the left and the middle stands, behind the promenade. Its Label3Ds
##              hold i18n keys (the fair sets their text)
##   Planters   stone flower boxes along the rim
##   Nature     the campus' trees, bushes, grass tufts, flowers and rocks (CampusScatter, baked)
##              round the plaza, keeping off the plaza and the gate's track
## The stage and the stall carry metadata/block_radius, which ConferenceFair turns into
## footprints; the lab a box (block_half, block_offset: half size and centre, local). The bunting is strung at runtime (ConferenceFair.bunting) in the agencies'
## colours.
## Run (windowed, so the MultiMesh buffers fill):
##   godot --path . --script res://tools/build_conference_dressing.gd

const OUT := "res://scenes/tycoon/conference/conference_dressing.tscn"
const TOON := preload("res://shaders/cw_toon_solid.gdshader")
const SCATTER := preload("res://src/tycoon/campus_scatter.gd")
const FOLIAGE := preload("res://assets/campus/nature/foliage.tres")
const GRASS := preload("res://assets/campus/nature/grass.tres")
const ROCK := preload("res://assets/campus/nature/rock.tres")
const NATURE := "res://assets/campus/nature/meshes/"
const PLANTER := preload("res://assets/campus/dressing/planter_stone.glb")
const CRATES := preload("res://assets/campus/dressing/crate_stack.glb")
const HAY := preload("res://assets/campus/dressing/hay_bale.glb")

## the plaza's half size (matches the Plaza mesh in the fair scene)
const HALF := Vector2(28.0, 22.0)
const LAMP_LIGHT := Color(1.0, 0.8235, 0.6039)
const POLE := Color("#2b3445")
const STONE := Color("#efe3cc")
const WOOD := Color("#b97a4a")
const PENNANTS := [Color("#ff9a5c"), Color("#ffd25c"), Color("#6fe0be"), Color("#7cc8ff"), Color("#b39cff"), Color("#ff8fb8")]
## the lamps (x, z) and where their arm points (toward the plaza)
const LAMPS := [Vector2(-26.6, -9.0), Vector2(26.6, -9.0), Vector2(-26.6, 9.0), Vector2(26.6, 9.0),
	Vector2(-11.0, -20.7), Vector2(11.0, -20.7), Vector2(-9.5, 20.8), Vector2(9.5, 20.8)]

var _mats := {}
var dress: Node3D


func _initialize() -> void:
	dress = Node3D.new()
	dress.name = "Dressing"
	get_root().add_child(dress)
	_curb()
	_lamps()
	_stage(Vector3(21.5, 0, 16.0))
	_food_stall(Vector3(-21.5, 0, 16.0))
	_design_lab(Vector3(-8.0, 0, -17.6), 0.15)
	_planters()
	await process_frame
	_nature()
	await process_frame
	_own(dress)
	var ps := PackedScene.new()
	var err := ps.pack(dress)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("wrote ", OUT, " ", error_string(err))
	quit(0 if err == OK else 1)


func _own(n: Node) -> void:
	for c in n.get_children():
		if c.owner == null:   # not a node inside an instanced glb
			c.owner = dress
		_own(c)


func _mat(c: Color, glow := 0.0) -> ShaderMaterial:
	var key := "%s/%s" % [c.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", c)
	if glow > 0.0:
		m.set_shader_parameter("emission", c)
		m.set_shader_parameter("emission_energy", glow)
	_mats[key] = m
	return m


func _box(parent: Node3D, name: String, size: Vector3, at: Vector3, c: Color, glow := 0.0, rot := Vector3.ZERO,
		shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, glow)
	mi.position = at
	mi.rotation = rot
	if not shadow or glow > 0.0:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, name: String, r_top: float, r_bot: float, h: float, at: Vector3, c: Color,
		glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(c, glow)
	mi.position = at
	parent.add_child(mi)
	return mi


func _node(parent: Node3D, name: String, at: Vector3, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = at
	n.rotation.y = yaw
	parent.add_child(n)
	return n


func _light(parent: Node3D, name: String, at: Vector3, energy: float, rng: float, c := LAMP_LIGHT) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = name
	l.position = at
	l.light_color = c
	l.light_energy = energy
	l.light_indirect_energy = 0.6
	l.light_specular = 0.3
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	parent.add_child(l)
	return l


static func _face_centre(p: Vector3) -> float:
	return atan2(-p.x, -p.z)


# ------------------------------------------------------------ pieces
func _curb() -> void:
	var g := _node(dress, "Curb", Vector3.ZERO)
	var w := 0.42
	var h := 0.16
	var y := h * 0.5 + 0.01
	_box(g, "North", Vector3(HALF.x * 2.0 + w, h, w), Vector3(0, y, -HALF.y), STONE)
	_box(g, "West", Vector3(w, h, HALF.y * 2.0), Vector3(-HALF.x, y, 0), STONE)
	_box(g, "East", Vector3(w, h, HALF.y * 2.0), Vector3(HALF.x, y, 0), STONE)
	var gap := 2.2
	var len := HALF.x - gap + w * 0.5
	_box(g, "SouthW", Vector3(len, h, w), Vector3(-gap - len * 0.5, y, HALF.y), STONE)
	_box(g, "SouthE", Vector3(len, h, w), Vector3(gap + len * 0.5, y, HALF.y), STONE)


func _lamps() -> void:
	var g := _node(dress, "Lamps", Vector3.ZERO)
	for i in LAMPS.size():
		var p: Vector2 = LAMPS[i]
		var at := Vector3(p.x, 0, p.y)
		var l := _node(g, "Lamp%d" % (i + 1), at, _face_centre(at))
		_box(l, "Base", Vector3(0.42, 0.34, 0.42), Vector3(0, 0.17, 0), POLE)
		_box(l, "Pole", Vector3(0.16, 4.4, 0.16), Vector3(0, 2.2, 0), POLE)
		_box(l, "Arm", Vector3(0.1, 0.1, 0.95), Vector3(0, 4.3, 0.4), POLE)
		_box(l, "Cap", Vector3(0.48, 0.1, 0.48), Vector3(0, 4.12, 0.82), POLE)
		_box(l, "Lantern", Vector3(0.36, 0.42, 0.36), Vector3(0, 3.86, 0.82), LAMP_LIGHT, 3.0)
		_box(l, "Finial", Vector3(0.2, 0.2, 0.2), Vector3(0, 4.5, 0), Color("#ffd25c"), 0.0, Vector3(0, PI / 4, PI / 4))
		var pc: Color = PENNANTS[i % PENNANTS.size()]
		_box(l, "Pennant", Vector3(0.05, 1.3, 0.62), Vector3(0, 2.75, -0.38), pc)
		_box(l, "PennantTip", Vector3(0.05, 0.3, 0.62), Vector3(0, 1.95, -0.38), pc.lightened(0.35))
		_light(l, "Light", Vector3(0, 3.5, 0.82), 2.2, 9.0)


func _stage(at: Vector3) -> void:
	var s := _node(dress, "Stage", at, _face_centre(at))
	s.set_meta("block_radius", 2.9)
	var navy := Color("#3d3a7a")
	_box(s, "Platform", Vector3(5.2, 0.55, 3.2), Vector3(0, 0.275, 0), navy)
	_box(s, "Deck", Vector3(5.3, 0.08, 3.3), Vector3(0, 0.59, 0), WOOD)
	_box(s, "Skirt", Vector3(5.22, 0.14, 0.04), Vector3(0, 0.36, 1.61), Color("#6fe0be"))
	_box(s, "Step", Vector3(1.4, 0.28, 0.6), Vector3(0, 0.14, 1.9), WOOD.darkened(0.15))
	_box(s, "Backdrop", Vector3(5.2, 3.4, 0.2), Vector3(0, 2.3, -1.5), Color("#7652e8"))
	_box(s, "BackdropBand", Vector3(5.22, 0.35, 0.22), Vector3(0, 1.0, -1.5), Color("#b39cff"))
	_box(s, "Star", Vector3(0.9, 0.9, 0.08), Vector3(0, 2.7, -1.36), Color("#ffd25c"), 1.6, Vector3(0, 0, PI / 4))
	_box(s, "StarCore", Vector3(0.45, 0.45, 0.1), Vector3(0, 2.7, -1.33), Color("#fff6e6"), 2.0)
	for sx in [-1, 1]:
		_box(s, "Post%d" % sx, Vector3(0.26, 4.4, 0.26), Vector3(2.7 * sx, 2.2, -1.2), Color("#fffdf8"))
		_box(s, "Speaker%d" % sx, Vector3(0.7, 1.2, 0.6), Vector3(2.1 * sx, 1.23, 0.9), Color("#1e1d4a"))
		_cyl(s, "Cone%d" % sx, 0.22, 0.22, 0.05, Vector3(2.1 * sx, 1.35, 1.21), Color("#5d5b8c")).rotation.x = PI / 2
	_box(s, "Beam", Vector3(5.8, 0.5, 0.32), Vector3(0, 4.45, -1.2), Color("#ff9a5c"))
	for i in 9:
		var c := Color("#ffd25c") if i % 2 == 0 else Color("#fff6e6")
		_box(s, "Bulb%d" % i, Vector3(0.16, 0.16, 0.08), Vector3(-2.6 + i * 0.65, 4.45, -1.02), c, 3.0)
	_cyl(s, "MicStand", 0.025, 0.025, 1.3, Vector3(0, 1.28, 0.5), POLE)
	_box(s, "Mic", Vector3(0.1, 0.18, 0.1), Vector3(0, 1.98, 0.5), Color("#2b2a5c"))
	_light(s, "Spot", Vector3(0, 3.4, 1.4), 2.4, 7.5, Color(1.0, 0.86, 0.72))


func _food_stall(at: Vector3) -> void:
	var f := _node(dress, "FoodStall", at, _face_centre(at))
	f.set_meta("block_radius", 2.0)
	var pink := Color("#ff8fb8")
	var white := Color("#fffdf8")
	_box(f, "Cart", Vector3(2.8, 1.0, 1.2), Vector3(0, 0.75, 0), white)
	_box(f, "CartStripe", Vector3(2.84, 0.22, 1.24), Vector3(0, 0.95, 0), pink)
	_box(f, "Counter", Vector3(3.0, 0.1, 1.4), Vector3(0, 1.3, 0.05), WOOD)
	for sx in [-1, 1]:
		var w := _cyl(f, "Wheel%d" % sx, 0.4, 0.4, 0.14, Vector3(1.48 * sx, 0.4, 0.0), Color("#2b2a5c"))
		w.rotation.z = PI / 2
		_cyl(f, "Hub%d" % sx, 0.12, 0.12, 0.18, Vector3(1.5 * sx, 0.4, 0.0), Color("#ffd25c")).rotation.z = PI / 2
		_box(f, "Post%d" % sx, Vector3(0.1, 2.0, 0.1), Vector3(1.35 * sx, 2.3, -0.55), white)
		_box(f, "PostF%d" % sx, Vector3(0.1, 1.6, 0.1), Vector3(1.35 * sx, 2.1, 0.62), white)
	for i in 6:   # striped awning, sloping to the front
		var c := pink if i % 2 == 0 else white
		_box(f, "Awning%d" % i, Vector3(0.56, 0.08, 1.75), Vector3(-1.4 + 0.56 * i, 3.07, 0.05), c, 0.0,
			Vector3(0.32, 0, 0))
	for i in 6:
		var c := white if i % 2 == 0 else pink
		_box(f, "Scallop%d" % i, Vector3(0.5, 0.26, 0.05), Vector3(-1.4 + 0.56 * i, 2.62, 0.92), c)
	var flavours := [Color("#ff8fb8"), Color("#b39cff"), Color("#7cc8ff"), Color("#ffd25c")]
	for i in 4:   # cotton-candy clouds on sticks
		var x := -0.95 + i * 0.62
		_cyl(f, "Stick%d" % i, 0.02, 0.02, 0.5, Vector3(x, 1.6, 0.25), Color("#fff6e6"))
		var puff := MeshInstance3D.new()
		puff.name = "Candy%d" % i
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.4
		sm.radial_segments = 8
		sm.rings = 4
		puff.mesh = sm
		puff.material_override = _mat(flavours[i])
		puff.position = Vector3(x, 1.95, 0.25)
		f.add_child(puff)
	_box(f, "Sign", Vector3(1.6, 0.6, 0.08), Vector3(0, 3.62, -0.62), Color("#ffd25c"), 0.4)
	_box(f, "SignIcon", Vector3(0.36, 0.36, 0.1), Vector3(0, 3.62, -0.56), pink, 0.8, Vector3(0, 0, PI / 4))
	var cr := CRATES.instantiate() as Node3D
	cr.name = "Crates"
	cr.position = Vector3(2.4, 0, -0.6)
	cr.rotation.y = -0.5
	f.add_child(cr)
	var hay := HAY.instantiate() as Node3D
	hay.name = "Hay"
	hay.position = Vector3(-2.3, 0, -0.3)
	f.add_child(hay)
	_light(f, "Glow", Vector3(0, 2.4, 1.0), 1.6, 6.0, Color(1.0, 0.8, 0.75))


func _label(parent: Node3D, name: String, key: String, at: Vector3, px: float, size: int, c := Color.WHITE,
		outline := Color("#2b2a5c")) -> Label3D:
	var l := Label3D.new()
	l.name = name
	l.text = key
	l.position = at
	l.pixel_size = px
	l.font_size = size
	l.outline_size = maxi(size / 6, 4)
	l.modulate = c
	l.outline_modulate = outline
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(l)
	return l


## A marker line on a board: a thin flat stroke from `a` to `b` (board-local x / y) at depth `z`.
func _stroke(parent: Node3D, name: String, a: Vector2, b: Vector2, z: float, c: Color, w := 0.035) -> void:
	var d := b - a
	_box(parent, name, Vector3(d.length(), w, 0.012), Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, z), c, 0.0,
		Vector3(0, 0, d.angle()), false)


## An ellipse of `n` strokes (dashed or whole) round `centre` (radii `r`), from angle `from` to `to`.
func _ellipse(parent: Node3D, name: String, centre: Vector2, r: Vector2, z: float, c: Color, n := 22,
		from := 0.0, to := TAU, dashed := true) -> void:
	for i in n:
		var t0 := lerpf(from, to, float(i) / n)
		var t1 := lerpf(from, to, (float(i) + (0.6 if dashed else 1.0)) / n)
		_stroke(parent, "%s%d" % [name, i], centre + Vector2(cos(t0), sin(t0)) * r, centre + Vector2(cos(t1), sin(t1)) * r,
			z, c, 0.03)


func _disc(parent: Node3D, name: String, r: float, at: Vector3, c: Color, glow := 0.0) -> MeshInstance3D:
	var d := _cyl(parent, name, r, r, 0.012, at, c, glow)
	d.rotation.x = PI / 2   # faces +z
	(d.mesh as CylinderMesh).radial_segments = 16
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return d


func _sphere(parent: Node3D, name: String, r: float, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _mat(c)
	mi.position = at
	parent.add_child(mi)
	return mi


## A sheet of paper lying on the table with a few scribbles in marker colours.
func _sheet(parent: Node3D, name: String, at: Vector3, yaw: float, size: Vector2, paper: Color, ink: Array) -> void:
	var sh := _node(parent, name, at, yaw)
	_box(sh, "Paper", Vector3(size.x, 0.012, size.y), Vector3.ZERO, paper, 0.0, Vector3.ZERO, false)
	for i in ink.size():
		var w := size.x * (0.7 - 0.15 * (i % 3))
		_box(sh, "Ink%d" % i, Vector3(w, 0.014, 0.022), Vector3(-size.x * 0.5 + 0.04 + w * 0.5, 0.004,
			-size.y * 0.5 + 0.07 + i * (size.y - 0.12) / maxf(ink.size() - 1, 1)), ink[i], 0.0, Vector3.ZERO, false)


func _design_lab(at: Vector3, yaw: float) -> void:
	var l := _node(dress, "DesignLab", at, yaw)
	l.set_meta("block_half", Vector2(2.95, 1.4))
	l.set_meta("block_offset", Vector3(0, 0, -0.45))
	var navy := Color("#24305e")
	var mint := Color("#6fe0be")
	var white := Color("#fffdf8")
	var board := Color("#f6f8fc")
	var frame := Color("#aeb8cc")
	var blue := Color("#2f6fe0")
	var red := Color("#e0525a")
	var green := Color("#2fae6a")
	var orange := Color("#ff9a5c")
	var grey := Color("#8a93a8")
	# the deck, a mint trim at its front edge and a blueprint rug under the table
	_box(l, "Deck", Vector3(5.6, 0.1, 2.75), Vector3(0, 0.05, -0.45), Color("#dfe6f2"))
	_box(l, "DeckTrim", Vector3(5.62, 0.07, 0.1), Vector3(0, 0.08, 0.9), mint)
	_box(l, "Rug", Vector3(3.4, 0.02, 1.9), Vector3(0, 0.11, -0.4), Color("#3d6fd1"), 0.0, Vector3.ZERO, false)
	_box(l, "RugIn", Vector3(3.2, 0.024, 1.7), Vector3(0, 0.112, -0.4), Color("#5a88e6"), 0.0, Vector3.ZERO, false)
	# the back wall and two low side panels
	_box(l, "Wall", Vector3(5.6, 3.0, 0.18), Vector3(0, 1.5, -1.75), navy)
	_box(l, "WallBand", Vector3(5.62, 0.16, 0.2), Vector3(0, 0.4, -1.75), mint)
	for sx in [-1, 1]:
		_box(l, "Side%d" % sx, Vector3(0.14, 2.1, 1.1), Vector3(2.73 * sx, 1.05, -1.15), navy.lightened(0.12))
		_box(l, "SideCap%d" % sx, Vector3(0.18, 0.08, 1.14), Vector3(2.73 * sx, 2.12, -1.15), mint)
	# the whiteboards
	var boards := {}
	for side in [["BoardL", -1.35], ["BoardR", 1.35]]:
		var b := _node(l, String(side[0]), Vector3(float(side[1]), 1.78, -1.64))
		_box(b, "Frame", Vector3(2.4, 1.42, 0.05), Vector3.ZERO, frame)
		_box(b, "Face", Vector3(2.28, 1.3, 0.05), Vector3(0, 0, 0.012), board)
		_box(b, "Tray", Vector3(2.0, 0.05, 0.1), Vector3(0, -0.72, 0.06), frame)
		for i in 3:   # markers on the tray
			_box(b, "Marker%d" % i, Vector3(0.14, 0.035, 0.035), Vector3(-0.5 + i * 0.22, -0.68, 0.07), [blue, red, green][i])
		boards[side[0]] = b
	var z := 0.045
	# left board: an orbit sketch (a planet, a dashed orbit, a little satellite, a transfer arc)
	var bl: Node3D = boards["BoardL"]
	_disc(bl, "Planet", 0.17, Vector3(-0.45, 0.02, z), blue)
	_disc(bl, "PlanetCap", 0.07, Vector3(-0.5, 0.08, z + 0.004), Color("#9cc4ff"))
	_ellipse(bl, "Orbit", Vector2(-0.45, 0.02), Vector2(0.42, 0.26), z, blue, 20)
	_ellipse(bl, "Transfer", Vector2(0.05, 0.02), Vector2(0.92, 0.5), z, red, 9, -0.1, 1.45, true)
	_box(bl, "Sat", Vector3(0.08, 0.08, 0.012), Vector3(-0.05, 0.27, z), grey, 0.0, Vector3.ZERO, false)
	_box(bl, "SatWings", Vector3(0.26, 0.035, 0.012), Vector3(-0.05, 0.27, z + 0.002), blue, 0.0, Vector3.ZERO, false)
	_disc(bl, "Target", 0.09, Vector3(0.62, 0.5, z), orange)
	_stroke(bl, "Arrow1", Vector2(0.4, 0.46), Vector2(0.5, 0.52), z, red, 0.03)
	_stroke(bl, "Arrow2", Vector2(0.46, 0.4), Vector2(0.5, 0.52), z, red, 0.03)
	for i in 3:   # notes in the corner
		_stroke(bl, "Note%d" % i, Vector2(0.35, -0.3 - i * 0.12), Vector2(0.95 - i * 0.12, -0.3 - i * 0.12), z, grey, 0.025)
	# right board: a trade study (a bar chart with the winner circled) and a checklist
	var br: Node3D = boards["BoardR"]
	_stroke(br, "AxisY", Vector2(-0.95, -0.5), Vector2(-0.95, 0.5), z, grey, 0.025)
	_stroke(br, "AxisX", Vector2(-0.95, -0.5), Vector2(0.05, -0.5), z, grey, 0.025)
	var bars := [[0.45, orange], [0.8, green], [0.3, red], [0.6, blue]]
	for i in bars.size():
		var h := float(bars[i][0])
		_box(br, "Bar%d" % i, Vector3(0.14, h, 0.012), Vector3(-0.78 + i * 0.22, -0.5 + h * 0.5, z), bars[i][1], 0.0,
			Vector3.ZERO, false)
	_ellipse(br, "Winner", Vector2(-0.56, 0.38), Vector2(0.14, 0.1), z + 0.002, red, 12, 0.0, TAU, false)
	for i in 4:   # the checklist: boxes, ticks, lines
		var y := 0.38 - i * 0.24
		_ellipse(br, "Box%d" % i, Vector2(0.32, y), Vector2(0.07, 0.07), z, grey, 4, PI / 4, PI / 4 + TAU, false)
		if i < 3:
			_stroke(br, "TickA%d" % i, Vector2(0.28, y + 0.01), Vector2(0.32, y - 0.04), z + 0.002, green, 0.03)
			_stroke(br, "TickB%d" % i, Vector2(0.32, y - 0.04), Vector2(0.4, y + 0.07), z + 0.002, green, 0.03)
		_stroke(br, "Line%d" % i, Vector2(0.45, y), Vector2(0.95 - (i % 2) * 0.15, y), z, grey, 0.025)
	# the banner on top of the wall and the line under it
	_box(l, "BannerBack", Vector3(5.9, 1.0, 0.16), Vector3(0, 3.5, -1.75), mint)
	_box(l, "BannerFace", Vector3(5.66, 0.8, 0.06), Vector3(0, 3.5, -1.65), Color("#1e2a5a"))
	_label(l, "Banner", "TY_CONF_LAB_BANNER", Vector3(0, 3.5, -1.61), 0.0064, 72, Color.WHITE, Color("#101736"))
	_label(l, "Sub", "TY_CONF_LAB_SUB", Vector3(0, 2.75, -1.65), 0.0048, 40, Color("#ffe08f"), Color("#101736"))
	for sx in [-1, 1]:   # a little orbit badge at each end of the banner
		_disc(l, "BadgeDot%d" % sx, 0.09, Vector3(2.58 * sx, 3.5, -1.61), Color("#ffd25c"), 0.6)
		var badge := _node(l, "Badge%d" % sx, Vector3(2.58 * sx, 3.5, -1.61))
		badge.rotation.z = 0.35 * sx
		_ellipse(badge, "Ring", Vector2.ZERO, Vector2(0.2, 0.09), 0.006, white, 14, 0.0, TAU, false)
	for i in 9:   # bulbs along the banner's lower edge
		_box(l, "Bulb%d" % i, Vector3(0.12, 0.12, 0.12), Vector3(-2.6 + i * 0.65, 2.98, -1.55),
			Color("#ffd25c") if i % 2 == 0 else Color("#fff6e6"), 2.6)
	# the table covered in mission sketches
	var t := _node(l, "Table", Vector3(0, 0.1, -0.3))
	var top_y := 0.78
	_box(t, "Top", Vector3(1.9, 0.07, 1.0), Vector3(0, top_y, 0), WOOD.lightened(0.2))
	var legs := 0
	for lx in [-0.85, 0.85]:
		for lz in [-0.42, 0.42]:
			_box(t, "Leg%d" % legs, Vector3(0.07, top_y, 0.07), Vector3(lx, top_y * 0.5, lz), WOOD.darkened(0.1))
			legs += 1
	var y0 := top_y + 0.042
	var bp := _node(t, "Blueprint", Vector3(0.02, y0, -0.05), 0.06)
	_box(bp, "Sheet", Vector3(0.82, 0.012, 0.56), Vector3.ZERO, Color("#3d6fd1"), 0.0, Vector3.ZERO, false)
	_box(bp, "Body", Vector3(0.42, 0.014, 0.1), Vector3(-0.02, 0.003, 0), white, 0.0, Vector3.ZERO, false)
	_box(bp, "BodyIn", Vector3(0.38, 0.016, 0.06), Vector3(-0.02, 0.004, 0), Color("#3d6fd1"), 0.0, Vector3.ZERO, false)
	_box(bp, "Nose", Vector3(0.1, 0.014, 0.1), Vector3(0.24, 0.003, 0), white, 0.0, Vector3(0, PI / 4, 0), false)
	for sz in [-1, 1]:
		_box(bp, "Fin%d" % sz, Vector3(0.1, 0.014, 0.05), Vector3(-0.22, 0.003, 0.08 * sz), white, 0.0, Vector3.ZERO, false)
	_box(bp, "Dim", Vector3(0.6, 0.014, 0.012), Vector3(0, 0.003, 0.2), white, 0.0, Vector3.ZERO, false)
	_box(bp, "Title", Vector3(0.18, 0.014, 0.06), Vector3(0.28, 0.003, -0.2), white, 0.0, Vector3.ZERO, false)
	var paper := Color("#fffaf0")
	_sheet(t, "SheetA", Vector3(-0.62, y0 + 0.002, 0.18), 0.3, Vector2(0.36, 0.48), paper, [blue, red, grey])
	_sheet(t, "SheetB", Vector3(0.62, y0 + 0.002, -0.22), -0.25, Vector2(0.36, 0.48), paper, [green, grey, grey, orange])
	_sheet(t, "SheetC", Vector3(-0.55, y0 + 0.004, -0.3), -0.5, Vector2(0.3, 0.4), Color("#fff2a8"), [grey, blue])
	_sheet(t, "SheetD", Vector3(0.45, y0 + 0.004, 0.3), 0.6, Vector2(0.3, 0.4), Color("#ffd6e6"), [red, grey])
	# a laptop with a glowing plot, a rocket model, a ringed planet, a mug and pencils
	var lap := _node(t, "Laptop", Vector3(-0.12, y0, 0.3), PI + 0.15)
	_box(lap, "Base", Vector3(0.36, 0.02, 0.25), Vector3.ZERO, Color("#3a3f55"))
	_box(lap, "Screen", Vector3(0.36, 0.24, 0.015), Vector3(0, 0.12, -0.13), Color("#3a3f55"), 0.0, Vector3(-0.25, 0, 0))
	_box(lap, "Glow", Vector3(0.32, 0.2, 0.01), Vector3(0, 0.12, -0.12), mint, 1.2, Vector3(-0.25, 0, 0))
	var rk := _node(t, "Rocket", Vector3(0.62, y0, 0.22))
	_cyl(rk, "Stand", 0.08, 0.1, 0.03, Vector3(0, 0.015, 0), navy)
	_cyl(rk, "Body", 0.045, 0.045, 0.3, Vector3(0, 0.18, 0), white)
	_cyl(rk, "Nose", 0.0, 0.045, 0.1, Vector3(0, 0.38, 0), red)
	_box(rk, "Fins", Vector3(0.16, 0.06, 0.02), Vector3(0, 0.06, 0), red)
	var pl := _node(t, "Planet", Vector3(-0.72, y0, -0.28))
	_cyl(pl, "Stand", 0.015, 0.06, 0.16, Vector3(0, 0.08, 0), navy)
	_sphere(pl, "Ball", 0.1, Vector3(0, 0.25, 0), Color("#ffb86b"))
	var ring := _cyl(pl, "Ring", 0.17, 0.17, 0.01, Vector3(0, 0.25, 0), Color("#b39cff"))
	ring.rotation = Vector3(0.45, 0, 0.2)
	_cyl(t, "Mug", 0.045, 0.04, 0.1, Vector3(0.3, y0 + 0.05, 0.02), orange)
	for i in 3:
		_box(t, "Pencil%d" % i, Vector3(0.16, 0.018, 0.018), Vector3(0.12 + i * 0.05, y0 + 0.012, -0.36),
			[Color("#ffd25c"), blue, red][i], 0.0, Vector3(0, 0.4 + i * 0.5, 0), false)
	# a flip chart with the CML ladder (CML 1 to 4, a star on top), turned to the plaza
	var fc := _node(l, "FlipChart", Vector3(2.15, 0.1, 0.25), -0.45)
	var fl := 0
	for lx in [-0.32, 0.32]:
		_box(fc, "Leg%d" % fl, Vector3(0.05, 1.7, 0.05), Vector3(lx, 0.85, 0.0), frame, 0.0, Vector3(0.08, 0, 0))
		fl += 1
	_box(fc, "LegBack", Vector3(0.05, 1.6, 0.05), Vector3(0, 0.8, -0.2), frame, 0.0, Vector3(-0.22, 0, 0))
	_box(fc, "Pad", Vector3(0.82, 0.95, 0.04), Vector3(0, 1.25, 0.07), board, 0.0, Vector3(0.08, 0, 0))
	var ladder := _node(fc, "Ladder", Vector3(0, 1.25, 0.1))
	ladder.rotation.x = 0.08
	var steps := [Color("#9be8d0"), mint, Color("#5fb6f0"), blue]
	for i in 4:
		var h := 0.12 + i * 0.13
		_box(ladder, "Step%d" % i, Vector3(0.14, h, 0.012), Vector3(-0.27 + i * 0.18, -0.34 + h * 0.5, 0), steps[i], 0.0,
			Vector3.ZERO, false)
	_box(ladder, "Star", Vector3(0.1, 0.1, 0.014), Vector3(0.27, 0.32, 0), Color("#ffd25c"), 0.8, Vector3(0, 0, PI / 4), false)
	_stroke(ladder, "Arrow", Vector2(-0.3, -0.05), Vector2(0.12, 0.3), 0.004, red, 0.025)
	# the "Office Hours" A-frame sign out front
	var sg := _node(l, "HoursSign", Vector3(-2.2, 0.1, 0.55), 0.35)
	_box(sg, "Front", Vector3(0.82, 0.92, 0.04), Vector3(0, 0.48, 0.11), Color("#2f3a4f"), 0.0, Vector3(-0.2, 0, 0))
	_box(sg, "Back", Vector3(0.82, 0.92, 0.04), Vector3(0, 0.48, -0.11), Color("#2f3a4f"), 0.0, Vector3(0.2, 0, 0))
	_box(sg, "Trim", Vector3(0.86, 0.05, 0.05), Vector3(0, 0.93, 0.0), WOOD)
	var hl := _label(sg, "Hours", "TY_CONF_LAB_HOURS", Vector3(0, 0.5, 0.145), 0.0032, 36, Color("#fffdf8"), Color("#2f3a4f"))
	hl.rotation.x = -0.2
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.width = 220.0
	# plants in the back corners
	for sx in [-1, 1]:
		_cyl(l, "Pot%d" % sx, 0.22, 0.17, 0.4, Vector3(2.3 * sx, 0.3, -1.38), Color("#e58a5a"))
		_sphere(l, "Leaves%d" % sx, 0.34, Vector3(2.3 * sx, 0.78, -1.38), Color("#5fbf6a"))
	# where the team stands: at the table's sides and one behind it, all turned to the table
	for m in [["Team1", Vector3(-1.45, 0.1, -0.2), 1.05], ["Team2", Vector3(1.45, 0.1, -0.25), -1.1],
			["Team3", Vector3(0.25, 0.1, -1.2), 0.0]]:
		var mk := Marker3D.new()
		mk.name = String(m[0])
		mk.position = m[1]
		mk.rotation.y = float(m[2])
		l.add_child(mk)
	_light(l, "Glow", Vector3(0, 2.5, 0.9), 1.5, 6.5, Color(0.92, 0.95, 1.0))


func _planters() -> void:
	var g := _node(dress, "Planters", Vector3.ZERO)
	var spots := [Vector3(-26.9, 0, 0.0), Vector3(26.9, 0, 0.0), Vector3(-19.0, 0, -21.0), Vector3(19.0, 0, -21.0),
		Vector3(-26.9, 0, -17.0), Vector3(26.9, 0, -17.0), Vector3(-15.5, 0, 21.0), Vector3(15.5, 0, 21.0)]
	var kinds := ["flowers_pink", "flowers_yellow", "flowers_violet", "flowers_white"]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var p := PLANTER.instantiate() as Node3D
		p.name = "Planter%d" % (i + 1)
		p.position = at
		p.rotation.y = PI / 2 if absf(at.x) > 26.0 else 0.0
		g.add_child(p)
		for k in 3:
			var fl := MeshInstance3D.new()
			fl.name = "Flowers%d" % k
			fl.mesh = load(NATURE + String(kinds[(i + k) % kinds.size()]) + ".res")
			fl.material_override = FOLIAGE
			fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fl.position = Vector3(-0.65 + 0.65 * k, 0.78, 0.0)
			fl.rotation.y = k * 1.3
			fl.scale = Vector3.ONE * 0.9
			p.add_child(fl)


# ------------------------------------------------------------ nature
func _mask(grow: float, track := true) -> CampusScatterMask:
	var m := CampusScatterMask.new()
	var r := Rect2(-HALF.x, -HALF.y, HALF.x * 2.0, HALF.y * 2.0).grow(grow)
	m.avoid.append(r)
	if track:
		m.avoid.append(Rect2(-3.8, HALF.y, 7.6, 40.0))
	return m


func _scatter(parent: Node3D, name: String, mesh: String, mat: Material, mask: CampusScatterMask, seed_v: int,
		area: Rect2, count: int, scale_range: Vector2, min_spacing := 0.0, clusters := 0, cluster_r := 4.0,
		tint := 0.08, shadow := true) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.set_script(SCATTER)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = load(NATURE + mesh + ".res")
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set("mask", mask)
	mmi.set("seed_value", seed_v)
	mmi.set("area", area)
	mmi.set("count", count)
	mmi.set("scale_range", scale_range)
	mmi.set("min_spacing", min_spacing)
	mmi.set("clusters", clusters)
	mmi.set("cluster_radius", cluster_r)
	mmi.set("margin", 0.2)
	mmi.set("tint_variation", tint)
	parent.add_child(mmi)
	var n: int = mmi.call("scatter")
	print("  ", name, ": ", n)


func _nature() -> void:
	var g := _node(dress, "Nature", Vector3.ZERO)
	var far := Rect2(-62, -56, 124, 116)
	var near := Rect2(-34, -28, 68, 60)
	var trees_mask := _mask(4.0)
	var bush_mask := _mask(0.7)
	var low_mask := _mask(0.35)
	var t := _node(g, "Trees", Vector3.ZERO)
	var tree_kinds := ["tree_round_a", "tree_round_b", "tree_round_c", "tree_pine_a", "tree_pine_b", "tree_blossom"]
	for i in tree_kinds.size():
		_scatter(t, String(tree_kinds[i]).to_pascal_case(), tree_kinds[i], FOLIAGE, trees_mask, 900 + i, far, 11,
			Vector2(1.05, 1.6), 6.0, 0, 4.0, 0.06)
	var b := _node(g, "Bushes", Vector3.ZERO)
	var bush_kinds := ["bush_a", "bush_b", "bush_flower_a", "bush_flower_b"]
	for i in bush_kinds.size():
		_scatter(b, String(bush_kinds[i]).to_pascal_case(), bush_kinds[i], FOLIAGE, bush_mask, 920 + i, near, 18,
			Vector2(0.8, 1.25), 1.6, 0, 4.0, 0.08)
	var gr := _node(g, "Grass", Vector3.ZERO)
	_scatter(gr, "GrassA", "grass_a", GRASS, low_mask, 940, far, 1600, Vector2(0.35, 0.6), 0.0, 0, 4.0, 0.1, false)
	_scatter(gr, "GrassB", "grass_b", GRASS, low_mask, 941, far, 1100, Vector2(0.3, 0.55), 0.0, 0, 4.0, 0.1, false)
	var fl := _node(g, "Flowers", Vector3.ZERO)
	var flower_kinds := ["flowers_pink", "flowers_yellow", "flowers_violet", "flowers_white"]
	for i in flower_kinds.size():
		_scatter(fl, String(flower_kinds[i]).to_pascal_case(), flower_kinds[i], FOLIAGE, low_mask, 950 + i, near, 70,
			Vector2(0.6, 0.95), 0.0, 8, 2.5, 0.06, false)
	var r := _node(g, "Rocks", Vector3.ZERO)
	_scatter(r, "RockA", "rock_a", ROCK, bush_mask, 960, far, 14, Vector2(0.6, 1.2), 3.0)
	_scatter(r, "RockC", "rock_c", ROCK, bush_mask, 961, far, 10, Vector2(0.6, 1.1), 3.0)
