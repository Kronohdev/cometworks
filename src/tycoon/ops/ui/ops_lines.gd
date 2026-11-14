class_name OpsLines
extends RefCounted
## Strip meshes for shaders/flight_map_line.gdshader (constant pixel width lines, see
## FlightMapLines) with a per-point alpha, so one polyline can show only some arcs: the
## map's antenna-coverage arcs and the fading transfer trajectories.


static func build(pts: PackedVector3Array, alphas: PackedFloat32Array, closed: bool, mesh: ArrayMesh = null) -> ArrayMesh:
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
		var prev := pts[i - 1] if i > 0 else (pts[n - 2] if closed else p)
		var next := pts[i + 1] if i < n - 1 else (pts[1] if closed else p)
		if i > 0:
			arc += p.distance_to(pts[i - 1])
		var a := alphas[i] if i < alphas.size() else 1.0
		for s in 2:
			var v := i * 2 + s
			verts[v] = p
			c0[v * 4] = prev.x
			c0[v * 4 + 1] = prev.y
			c0[v * 4 + 2] = prev.z
			c0[v * 4 + 3] = -1.0 if s == 0 else 1.0
			c1[v * 4] = next.x
			c1[v * 4 + 1] = next.y
			c1[v * 4 + 2] = next.z
			c1[v * 4 + 3] = arc
			cols[v] = Color(1, 1, 1, a)
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
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, FlightMapLines.FORMAT)
	return mesh
