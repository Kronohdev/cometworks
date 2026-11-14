extends SceneTree
## Authoring helper (run once): the little meadow on the stargazing hill of the main menu
## (scenes/menu/props/stargaze_meadow.tscn, instanced in scenes/menu/shots/shot_stargaze.tscn):
## grass tufts and flower clumps from the campus nature kit (assets/campus/nature/meshes),
## scattered with CampusScatter around the Cometlings, the telescope and the lantern.
## Re-run "Scatter now" on a node in the editor to re-roll it. Not --headless (MultiMesh data).
## Run: godot --path . --script res://tools/build_menu_meadow.gd

const MESH_DIR := "res://assets/campus/nature/meshes/"
const GRASS := "res://assets/campus/nature/grass.tres"


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Meadow"
	var mask := CampusScatterMask.new()
	var avoid: Array[Rect2] = [Rect2(-2.4, -1.6, 5.6, 3.0), Rect2(0.3, 0.7, 0.7, 0.7)]
	mask.avoid = avoid
	# hill crest (y 0), then the three steps towards the camera (sides only, so nothing
	# grows between the camera and the Cometlings)
	var areas := [
		[Rect2(-13, -4, 26, 4.8), 0.0, 1.0],
		[Rect2(-13, 1.0, 10.5, 1.4), -0.22, 0.8], [Rect2(4.5, 1.0, 8.5, 1.4), -0.22, 0.8],
		[Rect2(-13, 2.4, 10.0, 2.2), -0.48, 0.6], [Rect2(5.0, 2.4, 8.0, 2.2), -0.48, 0.6],
	]
	var k := 0
	for a: Array in areas:
		var r: Rect2 = a[0]
		var y: float = a[1]
		var density: float = a[2]
		var n := int(r.get_area() * 1.3 * density)
		_scatter(root, "Grass%d" % k, "grass_a", mask, n, 300 + k, r, y, Vector2(0.25, 0.45), 6, 1.4)
		_scatter(root, "GrassB%d" % k, "grass_b", mask, int(n * 0.7), 320 + k, r, y, Vector2(0.22, 0.4), 5, 1.2)
		var flowers := ["flowers_violet", "flowers_white", "flowers_yellow", "flowers_pink"]
		_scatter(root, "Flowers%d" % k, flowers[k % 4], mask, int(n * 0.3), 340 + k, r, y, Vector2(0.3, 0.5), 3, 0.8)
		k += 1
	var ps := PackedScene.new()
	_own(root, root)
	ps.pack(root)
	DirAccess.make_dir_recursive_absolute("res://scenes/menu/props")
	ResourceSaver.save(ps, "res://scenes/menu/props/stargaze_meadow.tscn")
	print("saved meadow")
	root.free()
	quit()


func _scatter(parent: Node, node_name: String, mesh: String, mask: CampusScatterMask, n: int, seed_v: int,
		r: Rect2, y: float, sc: Vector2, clusters: int, radius: float) -> void:
	var s := CampusScatter.new()
	s.name = node_name
	s.multimesh = MultiMesh.new()
	s.multimesh.mesh = load(MESH_DIR + mesh + ".res")
	s.material_override = load(GRASS)
	s.mask = mask
	s.area = r
	s.count = n
	s.seed_value = seed_v
	s.height = y
	s.scale_range = sc
	s.clusters = clusters
	s.cluster_radius = radius
	s.margin = 0.1
	s.tint_variation = 0.12
	s.tint_color = Color(0.55, 0.62, 0.8)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(s)
	s.scatter()
	print("%s: %d" % [node_name, s.multimesh.instance_count])


func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
