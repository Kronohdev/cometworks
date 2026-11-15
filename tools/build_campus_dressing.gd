extends SceneTree
## Authoring helper (run once, headless) for the campus dressing. Writes editor scenes that are
## then tweaked by hand in the editor; re-running overwrites those edits.
##   assets/campus/nature/meshes/*.res     meshes pulled out of the voxel props
##                                          (tools/build_campus_nature.py) for MultiMeshes
##   assets/campus/nature/campus_mask.tres  where nothing grows (lots, roads, plaza, lamps)
##   scenes/tycoon/campus_nature.tscn       trees, bushes, rocks, grass, flowers, reeds
##                                          (CampusScatter nodes: "Scatter now" re-rolls them)
##   scenes/tycoon/campus_dressing.tscn     era props: fences, windsock, hay, benches, the
##                                          monument, planters, floodlights, beacon masts
##                                          (metadata era_min / era_max, read by campus.gd)
##   scenes/tycoon/campus_life.tscn         birds, fireflies, pad steam
## The island's shape (terrain, sea, shore plants, fences along the edge, the mask's `inside`)
## comes from tools/build_campus_island.gd: run it again after this one.
## Run: godot --path . --script res://tools/build_campus_dressing.gd
## (not --headless: the MultiMesh buffers are read back from a real renderer when saving)

const NATURE_DIR := "res://assets/campus/nature/"
const DRESS_DIR := "res://assets/campus/dressing/"
const MESH_DIR := "res://assets/campus/nature/meshes/"
const FOLIAGE := "res://assets/campus/nature/foliage.tres"
const GRASS := "res://assets/campus/nature/grass.tres"
const ROCK := "res://assets/campus/nature/rock.tres"
const VOXEL := "res://assets/campus/campus_voxel.tres"

## lots: centre, size (tools/build_campus_scene.py)
const LOTS := [
	[Vector2(-16, -13), Vector2(18, 13)], [Vector2(16, -14), Vector2(26, 17)], [Vector2(38, 20), Vector2(17, 17)],
	[Vector2(-17, 17), Vector2(20, 13)], [Vector2(14, 17), Vector2(16, 12)], [Vector2(-43, -13), Vector2(15, 15)],
	[Vector2(-43, 17), Vector2(22, 13)], [Vector2(43, -13), Vector2(16, 13)], [Vector2(60, 20), Vector2(17, 17)],
]
const LAMPS := [Vector2(-7, -2.5), Vector2(7, -2.5), Vector2(-7, 6.5), Vector2(7, 6.5), Vector2(26, -2.2),
	Vector2(-26, -2.2), Vector2(26, 6.2), Vector2(-26, 6.2), Vector2(52, -2.2), Vector2(-52, 6.2)]

var _meshes := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(MESH_DIR)
	for f in DirAccess.get_files_at(NATURE_DIR):
		if f.ends_with(".glb"):
			_extract(NATURE_DIR + f)
	for f in ["fence_wood", "fence_steel"]:
		_extract(DRESS_DIR + f + ".glb")
	var mask := _mask()
	ResourceSaver.save(mask, NATURE_DIR + "campus_mask.tres")
	mask = load(NATURE_DIR + "campus_mask.tres")
	_save_scene(_nature(mask), "res://scenes/tycoon/campus_nature.tscn")
	_save_scene(_dressing(mask), "res://scenes/tycoon/campus_dressing.tscn")
	_save_scene(_life(), "res://scenes/tycoon/campus_life.tscn")
	print("CAMPUS DRESSING BUILT")
	quit()


func _extract(glb: String) -> void:
	var ps := load(glb) as PackedScene
	if ps == null:
		push_error("cannot load " + glb)
		return
	var root := ps.instantiate()
	var mi := root.find_child("Model", true, false) as MeshInstance3D
	if mi == null:
		for c in root.get_children():
			if c is MeshInstance3D:
				mi = c
	var mesh := mi.mesh.duplicate() as ArrayMesh
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, null)
	var out := MESH_DIR + glb.get_file().get_basename() + ".res"
	ResourceSaver.save(mesh, out, ResourceSaver.FLAG_COMPRESS)
	_meshes[glb.get_file().get_basename()] = out
	root.free()


func _mesh(name: String) -> Mesh:
	return load(MESH_DIR + name + ".res") as Mesh


func _mask() -> CampusScatterMask:
	var m := CampusScatterMask.new()
	var a: Array[Rect2] = []
	for l in LOTS:
		var c: Vector2 = l[0]
		var s: Vector2 = l[1]
		a.append(Rect2(c - s * 0.5 - Vector2(1, 1), s + Vector2(2, 2)))
	a.append(Rect2(-57, -1.0, 130, 6))      # main road (x -56..72, z -0.5..4.5)
	a.append(Rect2(-3.0, -43, 6, 78))       # north-south road
	a.append(Rect2(-8, -6, 16, 16))         # plaza
	for l in LOTS:                           # driveways
		var c: Vector2 = l[0]
		var s: Vector2 = l[1]
		var z0: float = c.y + s.y * 0.5 if c.y < 0 else 4.0
		var z1: float = 0.0 if c.y < 0 else c.y - s.y * 0.5
		a.append(Rect2(c.x - 2.6, minf(z0, z1) - 0.5, 5.2, absf(z1 - z0) + 1.0))
	for p in LAMPS:
		a.append(Rect2(p - Vector2(0.8, 0.8), Vector2(1.6, 1.6)))
	m.avoid = a
	return m


func _scatter(parent: Node, name: String, mesh: String, mat: String, mask: CampusScatterMask, count: int,
		seed_v: int, area := Rect2(-68, -49, 148, 102), opts := {}) -> CampusScatter:
	var s := CampusScatter.new()
	s.name = name
	s.multimesh = MultiMesh.new()
	s.multimesh.mesh = _mesh(mesh)
	s.material_override = load(mat)
	s.mask = mask
	s.count = count
	s.seed_value = seed_v
	s.area = area
	for k: String in opts:
		s.set(k, opts[k])
	parent.add_child(s)
	s.owner = parent.owner if parent.owner else parent
	var n := s.scatter()
	print("%s: %d" % [name, n])
	return s


func _group(parent: Node, name: String, meta := {}) -> Node3D:
	var g := Node3D.new()
	g.name = name
	for k: String in meta:
		g.set_meta(k, meta[k])
	parent.add_child(g)
	g.owner = parent.owner if parent.owner else parent
	return g


func _nature(mask: CampusScatterMask) -> Node3D:
	var root := Node3D.new()
	root.name = "Nature"
	var trees := _group(root, "Trees")
	var north := Rect2(-68, -49, 148, 24)
	var south := Rect2(-68, 26, 148, 27)
	var all := Rect2(-68, -49, 148, 102)
	var t_opts := {"min_spacing": 3.2, "margin": 1.6, "scale_range": Vector2(0.85, 1.25), "tint_variation": 0.08}
	_scatter(trees, "RoundA", "tree_round_a", FOLIAGE, mask, 22, 11, all, t_opts)
	_scatter(trees, "RoundB", "tree_round_b", FOLIAGE, mask, 18, 12, all, t_opts)
	_scatter(trees, "RoundC", "tree_round_c", FOLIAGE, mask, 16, 13, south, t_opts)
	_scatter(trees, "PineA", "tree_pine_a", FOLIAGE, mask, 22, 14, north, t_opts.merged({"clusters": 5, "cluster_radius": 9.0}))
	_scatter(trees, "PineB", "tree_pine_b", FOLIAGE, mask, 18, 15, Rect2(-68, -49, 30, 102), t_opts.merged({"clusters": 4, "cluster_radius": 8.0}))
	_scatter(trees, "Blossom", "tree_blossom", FOLIAGE, mask, 9, 16, Rect2(-30, -30, 60, 60), t_opts.merged({"clusters": 3, "cluster_radius": 6.0}))
	# a row of trees on the lower terrace, and pines on the far terrace corners
	var terrace := _group(root, "Terrace")
	for i in 4:
		var r: Rect2 = [Rect2(-75, -56, 162, 5.5), Rect2(-75, 54.5, 162, 5.5), Rect2(-75, -50, 5.5, 104), Rect2(81.5, -50, 5.5, 104)][i]
		_scatter(terrace, "Trees%d" % i, "tree_round_c" if i % 2 == 0 else "tree_pine_b", FOLIAGE, null, 9, 30 + i, r,
			{"height": -3.0, "min_spacing": 6.0, "scale_range": Vector2(0.8, 1.1), "tint_variation": 0.08})
		_scatter(terrace, "Bushes%d" % i, "bush_b", FOLIAGE, null, 16, 40 + i, r,
			{"height": -3.0, "scale_range": Vector2(0.8, 1.3), "tint_variation": 0.1})
		_scatter(terrace, "Grass%d" % i, "grass_b", GRASS, null, 60, 50 + i, r,
			{"height": -3.0, "clusters": 8, "cluster_radius": 3.0, "tint_variation": 0.1})
	var bushes := _group(root, "Bushes")
	var b_opts := {"margin": 0.9, "scale_range": Vector2(0.8, 1.35), "tint_variation": 0.1}
	_scatter(bushes, "BushA", "bush_a", FOLIAGE, mask, 45, 21, all, b_opts.merged({"clusters": 14, "cluster_radius": 3.5}))
	_scatter(bushes, "BushB", "bush_b", FOLIAGE, mask, 40, 22, all, b_opts.merged({"clusters": 12, "cluster_radius": 3.0}))
	_scatter(bushes, "FlowerBushA", "bush_flower_a", FOLIAGE, mask, 18, 23, all, b_opts.merged({"clusters": 6, "cluster_radius": 3.0}))
	_scatter(bushes, "FlowerBushB", "bush_flower_b", FOLIAGE, mask, 18, 24, all, b_opts.merged({"clusters": 6, "cluster_radius": 3.0}))
	var rocks := _group(root, "Rocks")
	var r_opts := {"margin": 0.8, "scale_range": Vector2(0.8, 1.3), "tint_variation": 0.06}
	_scatter(rocks, "RockA", "rock_a", ROCK, mask, 18, 61, all, r_opts.merged({"clusters": 6, "cluster_radius": 4.0}))
	_scatter(rocks, "RockB", "rock_b", ROCK, mask, 10, 62, all, r_opts)
	_scatter(rocks, "RockC", "rock_c", ROCK, mask, 30, 63, all, r_opts.merged({"clusters": 8, "cluster_radius": 3.0}))
	for i in 4:  # boulders on the cliff ledge around the terrace
		var r: Rect2 = [Rect2(-80, -61, 172, 4.5), Rect2(-80, 60.5, 172, 4.5), Rect2(-80, -56, 4.5, 116), Rect2(87.5, -56, 4.5, 116)][i]
		_scatter(rocks, "RockBig%d" % i, "rock_big", ROCK, null, 4, 64 + i, r, {"height": -6.0, "scale_range": Vector2(0.9, 1.6)})
	var ground := _group(root, "Ground")
	var g_opts := {"margin": 0.4, "scale_range": Vector2(0.8, 1.4), "tint_variation": 0.12}
	_scatter(ground, "GrassA", "grass_a", GRASS, mask, 900, 71, all, g_opts.merged({"clusters": 90, "cluster_radius": 3.2}))
	_scatter(ground, "GrassB", "grass_b", GRASS, mask, 700, 72, all, g_opts.merged({"clusters": 70, "cluster_radius": 2.6}))
	for k in 4:
		var col: String = ["yellow", "pink", "white", "violet"][k]
		_scatter(ground, "Flowers" + col.capitalize(), "flowers_" + col, GRASS, mask, 110, 80 + k, all,
			{"margin": 0.4, "clusters": 10, "cluster_radius": 2.2, "scale_range": Vector2(0.9, 1.3)})
	var beach := _group(root, "Beach")
	for i in 4:
		var r: Rect2 = [Rect2(-84, -65, 180, 3.5), Rect2(-84, 65.5, 180, 3.5), Rect2(-84, -61, 3.5, 126), Rect2(92.5, -61, 3.5, 126)][i]
		_scatter(beach, "Reeds%d" % i, "reeds", GRASS, null, 40, 90 + i, r,
			{"height": -8.4, "clusters": 7, "cluster_radius": 3.0, "scale_range": Vector2(0.8, 1.3), "tint_variation": 0.1})
		_scatter(beach, "Rocks%d" % i, "rock_a", ROCK, null, 6, 95 + i, r,
			{"height": -8.6, "scale_range": Vector2(0.7, 1.4)})
	for c in _all_children(root):
		if c is CampusScatter:
			var cs := c as CampusScatter
			var small := cs.name.begins_with("Grass") or cs.name.begins_with("Flowers") or cs.name.begins_with("Reeds")
			# only trees and boulders cast shadows: bushes, small rocks and grass would
			# multiply the shadow cascades' triangles for little visible gain
			var low := small or cs.name.begins_with("Bush") or cs.name.begins_with("FlowerBush") 				or cs.name in ["RockA", "RockC"] or cs.name.begins_with("Rocks")
			cs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if small:
				cs.visibility_range_end = 175.0
				cs.visibility_range_end_margin = 20.0
				cs.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return root


func _all_children(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out += _all_children(c)
	return out


func _prop(parent: Node, name: String, glb: String, pos: Vector3, yaw_deg := 0.0, scale_v := 1.0) -> Node3D:
	var n := (load(DRESS_DIR + glb + ".glb") as PackedScene).instantiate() as Node3D
	n.name = name
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale_v), pos)
	parent.add_child(n)
	n.owner = parent.owner if parent.owner else parent
	return n


func _beacon(parent: Node, name: String, pos: Vector3, phase: float, mat: ShaderMaterial, mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.set_instance_shader_parameter("phase", phase)
	parent.add_child(mi)
	mi.owner = parent.owner if parent.owner else parent


func _dressing(mask: CampusScatterMask) -> Node3D:
	var root := Node3D.new()
	root.name = "Dressing"
	# perimeter fence along the plateau edge, with a gap where the north road leaves
	var edge := PackedVector3Array([Vector3(-67, 0, -48), Vector3(-4, 0, -48), Vector3(4, 0, -48), Vector3(79, 0, -48),
		Vector3(79, 0, 52), Vector3(-67, 0, 52), Vector3(-67, 0, -48)])
	var wood := _group(root, "Workshop", {"era_min": 1, "era_max": 2})
	_scatter(wood, "FenceWood", "fence_wood", VOXEL, null, 0, 1, Rect2(), {"path": edge, "spacing": 4.0,
		"margin": 0.0, "scale_range": Vector2(0.95, 1.05)})
	_prop(wood, "Windsock", "windsock", Vector3(30.5, 0, 31), -30)
	_prop(wood, "HayBale", "hay_bale", Vector3(31, 0, -8), 10)
	_prop(wood, "HayBale2", "hay_bale", Vector3(32.6, 0, -9.2), 80)
	_prop(wood, "HayBale3", "hay_bale", Vector3(31.8, 1.1, -8.6), 40)
	_prop(wood, "Crates", "crate_stack", Vector3(30.5, 0, -18), 75)
	_prop(wood, "Picnic", "picnic_table", Vector3(8, 0, 29), 15)
	_prop(wood, "Bench", "bench_wood", Vector3(-3.5, 0, -1.2), 0)
	_prop(wood, "Bench2", "bench_wood", Vector3(3.5, 0, 5.2), 180)
	var steel := _group(root, "Base", {"era_min": 3, "era_max": 5})
	_scatter(steel, "FenceSteel", "fence_steel", VOXEL, null, 0, 2, Rect2(), {"path": edge, "spacing": 4.0,
		"margin": 0.0, "scale_range": Vector2(1.0, 1.0)})
	var beacon_mat := ShaderMaterial.new()
	beacon_mat.shader = load("res://shaders/campus_beacon.gdshader")
	var bulb := SphereMesh.new()
	bulb.radius = 0.16
	bulb.height = 0.32
	bulb.radial_segments = 8
	bulb.rings = 4
	var flood := [Vector3(27.5, 0, 30.5), Vector3(48.8, 0, 30.5), Vector3(48.8, 0, 9.5), Vector3(70.5, 0, 30.5),
		Vector3(70.5, 0, 9.5)]
	for i in flood.size():
		var p: Vector3 = flood[i]
		var yaw := rad_to_deg(atan2(44.0 - p.x, 20.0 - p.z))
		_prop(steel, "Floodlight%d" % (i + 1), "floodlight", p, yaw)
		_beacon(steel, "FloodBeacon%d" % (i + 1), p + Vector3(0, 11.95, 0), float(i) * 0.37, beacon_mat, bulb)
	var lamp_glow := _group(steel, "FloodLights")
	for i in [0, 1, 3]:
		var p: Vector3 = flood[i]
		var l := SpotLight3D.new()
		l.name = "Spot%d" % (i + 1)
		l.light_color = Color(1.0, 0.93, 0.8)
		l.light_energy = 6.0
		l.spot_range = 40.0
		l.spot_angle = 32.0
		l.spot_attenuation = 0.9
		var target := Vector3(lerpf(p.x, 49.0, 0.7), 0.0, lerpf(p.z, 20.0, 0.7))
		l.transform = Transform3D(Basis.looking_at(target - (p + Vector3(0, 11, 0)), Vector3.UP), p + Vector3(0, 11, 0))
		lamp_glow.add_child(l)
		l.owner = root
	_prop(steel, "Bench", "bench_steel", Vector3(-3.5, 0, -1.2), 0)
	_prop(steel, "Bench2", "bench_steel", Vector3(3.5, 0, 5.2), 180)
	var tidy := _group(root, "Planters", {"era_min": 2, "era_max": 5})
	for i in 4:
		var p := Vector3(-5.2 if i % 2 == 0 else 5.2, 0, -4.0 if i < 2 else 8.0)
		_prop(tidy, "Planter%d" % (i + 1), "planter_stone" if i % 2 == 0 else "planter_wood", p, 0)
	var late := _group(root, "LaunchBase", {"era_min": 4, "era_max": 5})
	var masts := [Vector3(-53, 0, -23), Vector3(-33, 0, -23), Vector3(-53, 0, -3.5), Vector3(80, 0, 0)]
	for i in masts.size():
		var p: Vector3 = masts[i]
		_prop(late, "Mast%d" % (i + 1), "beacon_mast", p)
		_beacon(late, "MastBeacon%d" % (i + 1), p + Vector3(0, 8.45, 0), float(i) * 0.21 + 0.5, beacon_mat, bulb)
	_prop(late, "FuelCart", "fuel_cart", Vector3(49.2, 0, 24), 90)
	_prop(late, "FuelCart2", "fuel_cart", Vector3(49.2, 0, 16), 90)
	_prop(root, "Monument", "monument", Vector3(0, 0.08, 2), 0)
	return root


func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var body_f := Vector3(0, 0, -0.35)
	var body_b := Vector3(0, 0, 0.3)
	for side in [-1.0, 1.0]:
		st.add_vertex(body_f)
		st.add_vertex(Vector3(side * 1.0, 0, 0.12))
		st.add_vertex(body_b)
	st.add_vertex(body_b)
	st.add_vertex(Vector3(-0.18, 0, 0.55))
	st.add_vertex(Vector3(0.18, 0, 0.55))
	return st.commit()


func _life() -> Node3D:
	var root := Node3D.new()
	root.name = "Life"
	var bird_mesh := _bird_mesh()
	ResourceSaver.save(bird_mesh, MESH_DIR + "bird.res")
	bird_mesh = load(MESH_DIR + "bird.res")
	var bird_mat := ShaderMaterial.new()
	bird_mat.shader = load("res://shaders/campus_birds.gdshader")
	var flocks := [[Vector3(-20, 30, -30), 9, 26.0], [Vector3(70, 24, 60), 6, 18.0], [Vector3(-80, 18, 40), 5, 14.0]]
	for i in flocks.size():
		var f: Array = flocks[i]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Birds%d" % (i + 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bird_mesh
		mm.instance_count = int(f[1])
		for k in mm.instance_count:
			mm.set_instance_transform(k, Transform3D())
		mmi.multimesh = mm
		var m := bird_mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("radius", float(f[2]))
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-45, -8, -35), Vector3(90, 16, 70))
		mmi.position = f[0]
		root.add_child(mmi)
		mmi.owner = root
	# fireflies over the meadows (they glow at dusk; the glow pass makes them sparkle)
	var ff := GPUParticles3D.new()
	ff.name = "Fireflies"
	ff.amount = 220
	ff.lifetime = 7.0
	ff.preprocess = 7.0
	ff.position = Vector3(6, 1.2, 2)
	ff.visibility_aabb = AABB(Vector3(-80, -2, -56), Vector3(160, 8, 112))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(72, 0.9, 50)
	pm.gravity = Vector3(0, 0.02, 0)
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 0.6, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.15), Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	ff.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(2.6, 3.2, 1.3)
	qm.disable_receive_shadows = true
	q.material = qm
	ff.draw_pass_1 = q
	ff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ff)
	ff.owner = root
	# steam drifting off the pads (shown from era 3 with the tanked rockets)
	var steam_group := Node3D.new()
	steam_group.name = "PadSteam"
	steam_group.set_meta("era_min", 3)
	root.add_child(steam_group)
	steam_group.owner = root
	var puff := GradientTexture2D.new()
	var pg := Gradient.new()
	pg.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	pg.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
	puff.gradient = pg
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	puff.width = 64
	puff.height = 64
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = puff
	sm.albedo_color = Color(0.92, 0.94, 1.0)
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spm.emission_sphere_radius = 0.6
	spm.direction = Vector3(0.3, 1, 0.1)
	spm.spread = 25.0
	spm.initial_velocity_min = 0.6
	spm.initial_velocity_max = 1.2
	spm.gravity = Vector3(0.25, 0.15, 0.1)
	spm.damping_min = 0.2
	spm.damping_max = 0.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	spm.scale_curve = sct
	spm.scale_min = 1.6
	spm.scale_max = 2.6
	var sfade := Gradient.new()
	sfade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	sfade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var sft := GradientTexture1D.new()
	sft.gradient = sfade
	spm.color_ramp = sft
	var sq := QuadMesh.new()
	sq.size = Vector2(1.0, 1.0)
	sq.material = sm
	for i in 2:
		var s := GPUParticles3D.new()
		s.name = "Steam%d" % (i + 1)
		s.amount = 18
		s.lifetime = 5.0
		s.preprocess = 5.0
		s.process_material = spm
		s.draw_pass_1 = sq
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = Vector3(38.0 if i == 0 else 60.0, 1.0, 22.5)
		s.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(14, 16, 14))
		steam_group.add_child(s)
		s.owner = root
	return root


func _save_scene(root: Node, path: String) -> void:
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %s" % path)
	ResourceSaver.save(ps, path)
	print("saved ", path)
	root.free()


func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		if c.scene_file_path == "":
			_own(c, root)
