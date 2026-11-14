class_name LaunchSightlines
extends RefCounted
## Line of sight on the campus for the launch shots (src/tycoon/launch/launch_sequence.gd): what
## stands on the campus (the buildings' meshes, each scattered tree, bush, rock and fence piece,
## each dressing prop), and the walk grid (CampusNav) for the plateau's edge and free ground.
## `blocked(a, b)` tells whether a sight line from a camera to a subject crosses one of them.
## Each piece is a world box first (hashed in CELL metre columns); a line through a box is then
## tested against the piece's real triangles (Mesh.generate_triangle_mesh, cached per mesh), so a
## launch tower's lattice or a tree's crown block only where they really are.

const CELL := 8.0
## things lower than this (m) do not block a view (kerbs, flower beds, low walls)
const MIN_HEIGHT := 1.0
## things thinner than this (m, both ways) do not block a view either (poles, lamp posts)
const MIN_WIDTH := 0.5

## the world box of each piece
var boxes: Array[AABB] = []
## the walk grid's plateau in world x / z (cameras low outside it would look at the cliff)
var plateau := Rect2()
var nav: CampusNav
var _meshes: Array[Mesh] = []            # per piece: its mesh (null: the box is the shape)
var _to_local: Array[Transform3D] = []   # per piece: world -> the mesh's space
var _to_campus := Transform3D.IDENTITY
var _cells := {}      # Vector2i -> Array[int]
var _top := 0.0       # the highest box top
var _skip: Array = []
static var _tris := {}   # Mesh -> TriangleMesh


## Everything standing on `campus`, except the nodes in `skip` and what is under them (the
## rocket that is about to leave, which the sequence flies itself).
static func from_campus(campus: Campus, skip: Array = []) -> LaunchSightlines:
	var s := LaunchSightlines.new()
	s._skip = skip
	if campus == null:
		return s
	s._to_campus = campus.global_transform.affine_inverse()
	s.nav = campus.nav
	if campus.nav:
		var n := campus.nav
		var r := Rect2(n.origin, Vector2(n.nx, n.nz) * CampusNav.CELL)
		var a := campus.global_transform * Vector3(r.position.x, 0, r.position.y)
		var b := campus.global_transform * Vector3(r.end.x, 0, r.end.y)
		s.plateau = Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), (Vector2(b.x, b.z) - Vector2(a.x, a.z)).abs())
	for lot in campus.lots.get_children():
		for c in lot.get_children():
			if c is CampusBuilding and (c as Node3D).visible and c not in skip:
				s._add_meshes(c as Node3D)
	for group in ["Props", "Dressing", "Nature"]:
		var g := campus.get_node_or_null(group) as Node3D
		if g and g.visible:
			s._add_under(g)
	return s


## True when the segment from `a` to `b` passes through something standing on the campus.
func blocked(a: Vector3, b: Vector3) -> bool:
	# above every box nothing blocks: clip the segment to the boxes' height
	if a.y > _top and b.y > _top:
		return false
	var lo := a if a.y <= b.y else b
	var hi := b if a.y <= b.y else a
	if hi.y > _top and absf(hi.y - lo.y) > 1e-4:
		hi = lo.lerp(hi, (_top - lo.y) / (hi.y - lo.y))
	var c0 := _cell(Vector2(minf(lo.x, hi.x), minf(lo.z, hi.z)))
	var c1 := _cell(Vector2(maxf(lo.x, hi.x), maxf(lo.z, hi.z)))
	var seen := {}
	for k in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			for idx: int in _cells.get(Vector2i(i, k), []):
				if seen.has(idx):
					continue
				seen[idx] = true
				if boxes[idx].intersects_segment(lo, hi) != null and _hits(idx, lo, hi):
					return true
	return false


## True when `p` is inside something (its box).
func inside(p: Vector3) -> bool:
	for idx: int in _cells.get(_cell(Vector2(p.x, p.z)), []):
		if boxes[idx].has_point(p):
			return true
	return false


## True when a point on the ground is on the plateau, `margin` metres in from its edge.
func on_plateau(p: Vector3, margin := 0.0) -> bool:
	if plateau.size == Vector2.ZERO:
		return true
	return plateau.grow(-margin).has_point(Vector2(p.x, p.z))


## True when the ground at `p` is free to stand on (the Cometlings' walk grid).
func free_ground(p: Vector3) -> bool:
	if nav == null:
		return true
	var q := _to_campus * p
	return nav.is_free(Vector2(q.x, q.z))


## A piece: its world box, and optionally its mesh placed by `xf` for the exact test.
func add_box(box: AABB, mesh: Mesh = null, xf := Transform3D.IDENTITY) -> void:
	if box.size.y < MIN_HEIGHT or (box.size.x < MIN_WIDTH and box.size.z < MIN_WIDTH):
		return
	boxes.append(box)
	_meshes.append(mesh)
	_to_local.append(xf.affine_inverse() if mesh else Transform3D.IDENTITY)
	_top = maxf(_top, box.end.y)
	var idx := boxes.size() - 1
	var c0 := _cell(Vector2(box.position.x, box.position.z))
	var c1 := _cell(Vector2(box.end.x, box.end.z))
	for k in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var key := Vector2i(i, k)
			if not _cells.has(key):
				_cells[key] = []
			_cells[key].append(idx)


func _hits(idx: int, a: Vector3, b: Vector3) -> bool:
	var m := _meshes[idx]
	if m == null:
		return true
	if not _tris.has(m):
		_tris[m] = m.generate_triangle_mesh()
	var tm := _tris[m] as TriangleMesh
	if tm == null:
		return true
	var inv := _to_local[idx]
	return not tm.intersect_segment(inv * a, inv * b).is_empty()


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## Scattered instances one piece each, everything else one piece per mesh.
func _add_under(node: Node) -> void:
	for c in node.get_children():
		if not c is Node3D or not (c as Node3D).visible:
			continue
		if c is CampusScatter:
			var sc := c as CampusScatter
			var mm := sc.multimesh
			if sc.blocks_walkers and mm and mm.mesh:
				var a := mm.mesh.get_aabb()
				for t in sc.placed():
					var xf := sc.global_transform * t
					add_box(xf * a, mm.mesh, xf)
			continue
		if c is MeshInstance3D or c.scene_file_path != "":
			_add_meshes(c as Node3D)
			continue
		_add_under(c)


## Every shown mesh under `n` (lights, particles and the like are not in the way).
func _add_meshes(n: Node3D) -> void:
	if not n.is_visible_in_tree() or n in _skip:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		add_box(mi.global_transform * mi.get_aabb(), mi.mesh, mi.global_transform)
	for c in n.get_children():
		if c is Node3D:
			_add_meshes(c as Node3D)
