extends SceneTree
## Bakes the walkable floor of the assembly building for the Cometling crowd and saves
## it to scenes/npc/hangar_navmesh.tres (used by HangarCrowd/NavRegion).
## Obstacles come from the scenes themselves, so re-run after moving props:
##   - vab.tscn: Floor/LaunchPad (circle), every mesh under Props, the ServiceTower base
##   - hangar_crowd.tscn: every mesh under Props (workbench, crate stack)
##   - the wall plinths: the floor stops 2.6 m from the walls
## Run: godot --headless --path . --script res://src/npc/bake_hangar_navmesh.gd

const OUT := "res://scenes/npc/hangar_navmesh.tres"
const HALF := 57.4
const PAD_R := 9.7
const TOWER_HALF := 2.7


func _initialize() -> void:
	var vab := (load("res://scenes/environment/vab.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(vab)
	var crowd := vab.find_child("HangarCrowd", true, false) as Node3D
	if crowd == null:
		crowd = (load("res://scenes/npc/hangar_crowd.tscn") as PackedScene).instantiate() as Node3D
		crowd.process_mode = Node.PROCESS_MODE_DISABLED
		get_root().add_child(crowd)
	crowd.process_mode = Node.PROCESS_MODE_DISABLED

	await process_frame
	var src := NavigationMeshSourceGeometryData3D.new()
	var a := Vector3(-HALF, 0, -HALF)
	var b := Vector3(HALF, 0, -HALF)
	var c := Vector3(HALF, 0, HALF)
	var d := Vector3(-HALF, 0, HALF)
	# both windings: whichever faces up becomes walkable
	src.add_faces(PackedVector3Array([a, b, c, a, c, d, a, c, b, a, d, c]), Transform3D.IDENTITY)

	var n_obs := 0
	var circle := PackedVector3Array()
	for k in 32:
		var ang := TAU * k / 32.0
		circle.append(Vector3(cos(ang) * PAD_R, 0, sin(ang) * PAD_R))
	src.add_projected_obstruction(circle, -1.0, 4.0, false)
	n_obs += 1
	var tower := vab.get_node_or_null("ServiceTower") as Node3D
	if tower:
		var t := tower.global_position
		src.add_projected_obstruction(PackedVector3Array([t + Vector3(-TOWER_HALF, 0, -TOWER_HALF), t + Vector3(TOWER_HALF, 0, -TOWER_HALF),
			t + Vector3(TOWER_HALF, 0, TOWER_HALF), t + Vector3(-TOWER_HALF, 0, TOWER_HALF)]), -1.0, 4.0, false)
		n_obs += 1
	for root in [vab.get_node_or_null("Props"), crowd.get_node_or_null("Props")]:
		if root == null:
			continue
		for mi in (root as Node).find_children("*", "MeshInstance3D", true, false):
			var hull := _footprint(mi as MeshInstance3D)
			if hull.size() >= 3:
				src.add_projected_obstruction(hull, -1.0, 4.0, false)
				n_obs += 1

	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 1.0
	nm.agent_height = 2.5
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 30.0
	nm.region_min_size = 4.0
	nm.edge_max_error = 1.0
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var err := ResourceSaver.save(nm, OUT)
	print("baked hangar navmesh: %d obstacles, %d polygons, %d vertices -> %s (err %d)"
		% [n_obs, nm.get_polygon_count(), nm.vertices.size(), OUT, err])
	quit()


## Convex footprint (y = 0) of a mesh's world AABB corners.
func _footprint(mi: MeshInstance3D) -> PackedVector3Array:
	var bb := mi.get_aabb()
	if bb.size.y <= 0.001 or mi.global_position.y > 3.0:
		return PackedVector3Array()
	var pts := PackedVector2Array()
	for i in 8:
		var p := mi.global_transform * bb.get_endpoint(i)
		pts.append(Vector2(p.x, p.z))
	var hull := Geometry2D.convex_hull(pts)
	var out := PackedVector3Array()
	for i in hull.size() - 1:   # convex_hull repeats the first point at the end
		out.append(Vector3(hull[i].x, 0, hull[i].y))
	return out
