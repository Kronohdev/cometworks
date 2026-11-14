class_name FlightMapLines
extends RefCounted
## Strip meshes for shaders/flight_map_line.gdshader: every polyline point becomes two
## vertices (side -1 / +1) carrying their neighbours (CUSTOM0.xyz = previous point,
## CUSTOM1.xyz = next point) and the arc length (CUSTOM1.w), so the vertex shader can
## widen the line to a constant pixel width. Built only when the geometry changes.

const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)


## Unit circle in the XZ plane (closed), for orbits and SOI rings.
static func circle(n: int) -> ArrayMesh:
	var pts := PackedVector3Array()
	pts.resize(n + 1)
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		pts[i] = Vector3(cos(a), 0.0, sin(a))
	return build(pts, true)


## Polyline from doubles (x, y, z triplets, metres) scaled by k into map units. Reuses
## `mesh` when given (clears its surface).
static func polyline(p: PackedFloat64Array, k: float, mesh: ArrayMesh = null) -> ArrayMesh:
	var n := p.size() / 3
	var pts := PackedVector3Array()
	pts.resize(n)
	for i in n:
		pts[i] = Vector3(p[i * 3] * k, p[i * 3 + 1] * k, p[i * 3 + 2] * k)
	return build(pts, false, mesh)


static func build(pts: PackedVector3Array, closed: bool, mesh: ArrayMesh = null) -> ArrayMesh:
	var n := pts.size()
	if mesh == null:
		mesh = ArrayMesh.new()
	else:
		mesh.clear_surfaces()
	if n < 2:
		return mesh
	var verts := PackedVector3Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * 2)
	c0.resize(n * 8)
	c1.resize(n * 8)
	cols.resize(n * 2)
	idx.resize((n - 1) * 6)
	var arc := 0.0
	for i in n:
		var p := pts[i]
		var prev: Vector3
		var next: Vector3
		if i > 0:
			prev = pts[i - 1]
		elif closed:
			prev = pts[n - 2]
		else:
			prev = p
		if i < n - 1:
			next = pts[i + 1]
		elif closed:
			next = pts[1]
		else:
			next = p
		if i > 0:
			arc += p.distance_to(pts[i - 1])
		for s in 2:
			var v := i * 2 + s
			var side := -1.0 if s == 0 else 1.0
			verts[v] = p
			c0[v * 4] = prev.x
			c0[v * 4 + 1] = prev.y
			c0[v * 4 + 2] = prev.z
			c0[v * 4 + 3] = side
			c1[v * 4] = next.x
			c1[v * 4 + 1] = next.y
			c1[v * 4 + 2] = next.z
			c1[v * 4 + 3] = arc
			cols[v] = Color.WHITE
		if i < n - 1:
			var b := i * 6
			var v0 := i * 2
			idx[b] = v0
			idx[b + 1] = v0 + 1
			idx[b + 2] = v0 + 2
			idx[b + 3] = v0 + 1
			idx[b + 4] = v0 + 3
			idx[b + 5] = v0 + 2
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, FORMAT)
	return mesh
