class_name Vessel
extends Node3D
## The vessel under construction: owns the root PartInstance and implements
## attaching (stack, engine slot, radial-decoupler side, surface + symmetry),
## staging and the CoM / CoT / CoL markers' math.

signal changed

var root: PartInstance = null


func all_parts() -> Array[PartInstance]:
	return root.subtree() if root else ([] as Array[PartInstance])


func clear() -> void:
	if root:
		root.free()
	root = null
	changed.emit()


func set_root(p: PartInstance) -> void:
	if p.get_parent():
		p.get_parent().remove_child(p)
	add_child(p)
	p.transform = Transform3D.IDENTITY
	p.parent_node_name = ""
	p.own_node_name = ""
	root = p
	p.set_pickable(true)
	p.set_ghost(false)
	changed.emit()


# ------------------------------------------------------------ attach rules
## Returns the own node of `held` that may connect to `target_node` of `target`, or "".
static func own_node_for(target: PartInstance, target_node: String, held: PartInstance) -> String:
	if target_node.begins_with("slot:"):
		return "top" if PartDB.is_engine(held.data) and held.has_node_point("top") else ""
	if target_node == "side":
		return "sidechild" if not held.can_radial_attach() else ""
	var size := target.node_size(target_node)
	var want := "top" if target_node == "bottom" else "bottom"
	if not held.has_node_point(want) or not held.free_nodes().has(want):
		return ""
	# Like in KSP, engines mount on any node size; structural parts need matching sizes (or an adapter).
	if PartDB.is_engine(held.data) or PartDB.is_engine(target.data) or held.node_size(want) == size:
		return want
	return ""


## Local transform of `held` inside `target` for a node connection.
static func local_for_node(target: PartInstance, target_node: String, held: PartInstance, own_node: String) -> Transform3D:
	var tp := target.node_local(target_node)
	if own_node == "sidechild":
		var c := held.aabb.get_center()
		return Transform3D(Basis(), Vector3(tp.x - held.aabb.position.x, tp.y - c.y, -c.z))
	return Transform3D(Basis(), tp - held.node_local(own_node))


## Local transform of `held` on the surface of `target` (target-local point and outward direction).
static func local_for_surface(target: PartInstance, surf_local: Vector3, out_local: Vector3, held: PartInstance) -> Transform3D:
	var out := Vector3(out_local.x, 0, out_local.z).normalized()
	if out == Vector3.ZERO:
		out = Vector3.RIGHT
	var b := Basis(Vector3.UP, atan2(-out.z, out.x))
	var c := held.aabb.get_center()
	var origin := surf_local + b * Vector3(-held.aabb.position.x, -c.y, -c.z)
	return Transform3D(b, origin)


## Converts a ray hit (from PartInstance.ray_hit) on `target` into a surface point and
## outward direction in target-local space. Cylinders use the radial direction, boxes the
## face normal. `angle_step` (radians, 0 = free) snaps the angle around round parts and
## `height_step` (m, 0 = free) snaps the height.
static func surface_from_hit(target: PartInstance, hit_world: Vector3, normal_local := Vector3.ZERO,
		angle_step := 0.0, height_step := 0.0) -> Dictionary:
	var lp := target.global_transform.affine_inverse() * hit_world
	var y := clampf(lp.y, target.aabb.position.y, target.aabb.end.y)
	if height_step > 0.0:
		y = clampf(snappedf(y - target.aabb.position.y, height_step) + target.aabb.position.y,
			target.aabb.position.y, target.aabb.end.y)
	if target.is_round():
		var ang := atan2(lp.z, lp.x)
		if angle_step > 0.0:
			ang = snappedf(ang, angle_step)
		var out := Vector3(cos(ang), 0, sin(ang))
		var r := target.radius()
		return {"point": Vector3(out.x * r, y, out.z * r), "out": out}
	var n := Vector3(normal_local.x, 0, normal_local.z)
	if n.length() < 0.5:  # top/bottom face: use the dominant horizontal axis
		var c := target.aabb.get_center()
		var dx := (lp.x - c.x) / maxf(target.aabb.size.x, 1e-3)
		var dz := (lp.z - c.z) / maxf(target.aabb.size.z, 1e-3)
		n = Vector3(signf(dx), 0, 0) if absf(dx) > absf(dz) else Vector3(0, 0, signf(dz))
	n = n.normalized()
	var p := Vector3(lp.x, y, lp.z)
	if absf(n.x) > 0.5:
		p.x = target.aabb.end.x if n.x > 0 else target.aabb.position.x
	else:
		p.z = target.aabb.end.z if n.z > 0 else target.aabb.position.z
	return {"point": p, "out": n}


# ------------------------------------------------------------ tree editing
func _adopt(parent: PartInstance, p: PartInstance, xf: Transform3D, pnode: String, onode: String) -> void:
	if p.get_parent():
		p.get_parent().remove_child(p)
	parent.add_child(p)
	p.transform = xf
	p.parent_node_name = pnode
	p.own_node_name = onode
	p.set_pickable(true)
	p.set_ghost(false)


static func clone_tree(src: PartInstance) -> PartInstance:
	var c := PartInstance.create(src.part_id)
	c.transform = src.transform
	c.parent_node_name = src.parent_node_name
	c.own_node_name = src.own_node_name
	for k in src.part_children():
		c.add_child(clone_tree(k))
	return c


## Attaches `held` and replicates it on every symmetry counterpart of `target`.
## For surface attachment, `symmetry` copies are placed around the target axis.
func attach(target: PartInstance, held: PartInstance, xf: Transform3D, pnode: String, onode: String, symmetry := 1) -> void:
	var targets: Array = [target]
	for t in target.sym_group:
		if t != target and is_instance_valid(t):
			targets.append(t)
	var placed: Array = []
	var first := true
	for t in targets:
		var copies := symmetry if pnode == "surface" else 1
		for k in copies:
			var rot := Transform3D(Basis(Vector3.UP, TAU * k / copies), Vector3.ZERO)
			var p: PartInstance = held if first else clone_tree(held)
			first = false
			_adopt(t, p, rot * xf, pnode, onode)
			placed.append(p)
	if placed.size() > 1:
		var tag := _next_sym_tag()
		for p in placed:
			p.sym_group = placed
			p.sym_tag = tag
	else:
		held.sym_group = []
		held.sym_tag = -1
	changed.emit()


func _next_sym_tag() -> int:
	var t := 0
	for p in all_parts():
		t = maxi(t, p.sym_tag + 1)
	return t


## Returns the attach node of `held` that the child currently on `target.tnode` would move
## to if `held` were inserted there (the node opposite `held_onode`), or "" if not possible.
static func insert_node_for(target: PartInstance, tnode: String, held: PartInstance, held_onode: String) -> String:
	if not (tnode == "top" or tnode == "bottom") or not target.sym_group.is_empty():
		return ""
	var child: PartInstance = null
	for c in target.part_children():
		if c.parent_node_name == tnode:
			child = c
	if child == null or child.own_node_name not in ["top", "bottom"]:
		return ""
	var other := "bottom" if held_onode == "top" else "top"
	if not held.has_node_point(other) or not held.free_nodes().has(other):
		return ""
	# the moved child must accept held's other node (same size rules as a normal attach;
	# its own node is occupied right now by the connection that is about to move)
	var size_ok := PartDB.is_engine(held.data) or PartDB.is_engine(child.data) \
		or held.node_size(other) == child.node_size(child.own_node_name)
	var dir_ok := (other == "bottom" and child.own_node_name == "top") or (other == "top" and child.own_node_name == "bottom")
	return other if size_ok and dir_ok else ""


## Inserts `held` between `target` and the child on `tnode`: held attaches to target with
## `xf`, the old child (and its subtree) re-attaches to held's opposite node.
func insert(target: PartInstance, tnode: String, held: PartInstance, xf: Transform3D, held_onode: String) -> void:
	var other := insert_node_for(target, tnode, held, held_onode)
	assert(other != "", "insert not possible")
	var child: PartInstance = null
	for c in target.part_children():
		if c.parent_node_name == tnode:
			child = c
	_adopt(target, held, xf, tnode, held_onode)
	# keep the child's own rotation relative to the stack
	var basis_rel := xf.basis.inverse() * child.transform.basis
	var origin := held.node_local(other) - basis_rel * child.node_local(child.own_node_name)
	_adopt(held, child, Transform3D(basis_rel, origin), other, child.own_node_name)
	held.sym_group = []
	held.sym_tag = -1
	changed.emit()


## Detaches `p` (with its subtree) from the vessel for the player to hold. Symmetry
## counterparts are deleted, like in KSP. Returns the detached part.
func detach(p: PartInstance) -> PartInstance:
	for q in p.sym_group:
		if q != p and is_instance_valid(q):
			q.get_parent().remove_child(q)
			q.free()
	for s in p.subtree():
		s.sym_group = []
		s.sym_tag = -1
	var gx := p.global_transform
	if p == root:
		root = null
	p.get_parent().remove_child(p)
	p.transform = gx
	changed.emit()
	return p


# ------------------------------------------------------------ staging
## Splits the attach tree at decouplers. Returns {"stages": [...VesselMath stage specs],
## "fairing_kg": float, "stage_parts": Array[Array[PartInstance]] (core + boosters per stage)}.
func compute_stages() -> Dictionary:
	var groups: Array = []  # {parts: Array[PartInstance], level: int, kind: "stack"/"booster", owner: int}
	if root == null:
		return {"stages": [], "fairing_kg": 0.0, "stage_parts": []}
	groups.append({"parts": [], "level": 0, "kind": "stack", "owner": 0})
	_collect(root, 0, groups)
	var max_level := 0
	for g in groups:
		max_level = maxi(max_level, g["level"])
	var n_stages := max_level + 1
	var stages: Array = []
	var stage_parts: Array = []
	for i in n_stages:
		stages.append({"core": [], "boosters": []})
		stage_parts.append([])
	var fairing_kg := 0.0
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var owner_level: int = groups[g["owner"]]["level"] if g["kind"] == "booster" else g["level"]
		var si: int = max_level - owner_level
		var datas: Array = []
		for p: PartInstance in g["parts"]:
			if PartDB.is_fairing(p.data):
				fairing_kg += p.dry_mass()
				continue
			datas.append(p.data)
			stage_parts[si].append(p)
		if g["kind"] == "booster":
			stages[si]["boosters"].append(datas)
		else:
			stages[si]["core"].append_array(datas)
	return {"stages": stages, "fairing_kg": fairing_kg, "stage_parts": stage_parts}


func _collect(p: PartInstance, gi: int, groups: Array) -> void:
	groups[gi]["parts"].append(p)
	for c in p.part_children():
		if PartDB.is_stack_decoupler(c.data):
			groups.append({"parts": [], "level": groups[gi]["level"] + 1, "kind": "stack", "owner": groups.size()})
			_collect(c, groups.size() - 1, groups)
		elif PartDB.is_radial_decoupler(c.data):
			var owner_gi: int = groups[gi]["owner"] if groups[gi]["kind"] == "booster" else gi
			groups.append({"parts": [], "level": groups[gi]["level"], "kind": "booster", "owner": owner_gi})
			_collect(c, groups.size() - 1, groups)
		else:
			_collect(c, gi, groups)


func analyze() -> Dictionary:
	var st := compute_stages()
	var res := VesselMath.analyze(st["stages"], 0.0, st["fairing_kg"], 2)
	res["warnings"] = _warnings(st, res)
	res["stage_parts"] = st["stage_parts"]
	return res


func _warnings(st: Dictionary, res: Dictionary) -> Array[String]:
	var w: Array[String] = []
	if root == null:
		return w
	var has_core := false
	for p in all_parts():
		if PartDB.is_command(p.data):
			has_core = true
	if not has_core:
		w.append(tr("WARN_NO_CORE"))
	for s in st["stages"]:
		var groups: Array = [s["core"]]
		groups.append_array(s["boosters"])
		for g in groups:
			var props := {}
			for d in g:
				if d.get("category", "") == "tank":
					props[d.get("propellant", "")] = true
			for d in g:
				if PartDB.is_engine(d) and d.get("propellant", "") != "solid" and not props.has(d.get("propellant", "")):
					w.append(tr("WARN_NO_FUEL") % PartDB.loc(d["name"]))
	if not res["stages"].is_empty():
		var twr: float = res["liftoff_twr"]
		if twr < 1.0:
			w.append(tr("WARN_TWR_LOW") % twr)
		elif twr < 1.2:
			w.append(tr("WARN_TWR_MARGINAL") % twr)
		if res["ascent_dv"] < 9400.0:
			w.append(tr("WARN_DV_LOW"))
	if stability(markers()) == 0:
		w.append(tr("WARN_UNSTABLE"))
	return w


## 1 = stable (CoL below CoM), 2 = unstable but stage-1 engines can gimbal,
## 0 = unstable and uncontrolled, -1 = not enough parts to tell.
func stability(m: Dictionary) -> int:
	if not (m["has_col"] and m["has_com"]) or all_parts().size() < 2:
		return -1
	if m["col"].y < m["com"].y:
		return 1
	return 2 if m["gimbal_deg"] > 0.0 else 0


# ------------------------------------------------------------ markers
## World-space CoM (wet and dry), CoT of the stage-1 engines and CoL estimate.
func markers() -> Dictionary:
	var parts := all_parts()
	var out := {"has_com": false, "has_cot": false, "has_col": false,
		"com": Vector3.ZERO, "com_dry": Vector3.ZERO, "cot": Vector3.ZERO, "col": Vector3.ZERO, "thrust_dir": Vector3.UP,
		"gimbal_deg": 0.0}
	if parts.is_empty():
		return out
	var mw := 0.0
	var md := 0.0
	var lw := 0.0
	var com := Vector3.ZERO
	var comd := Vector3.ZERO
	var col := Vector3.ZERO
	for p in parts:
		var c := p.center_global()
		com += c * p.wet_mass()
		mw += p.wet_mass()
		comd += c * p.dry_mass()
		md += p.dry_mass()
		if not PartDB.is_engine(p.data) or p.data.get("propellant", "") == "solid":
			col += c * p.lift_weight()
			lw += p.lift_weight()
	if mw > 0.0:
		out["com"] = com / mw
		out["com_dry"] = comd / maxf(md, 1e-6)
		out["has_com"] = true
	if lw > 0.0:
		out["col"] = col / lw
		out["has_col"] = true
	var st := compute_stages()
	if not st["stage_parts"].is_empty():
		var ft := 0.0
		var cot := Vector3.ZERO
		var dir := Vector3.ZERO
		for p: PartInstance in st["stage_parts"][0]:
			if not PartDB.is_engine(p.data):
				continue
			var f := float(p.data.get("thrust_sl_kn", 0.0))
			if f <= 0.0:
				f = float(p.data.get("thrust_vac_kn", 0.0))
			cot += p.thrust_point_global() * f
			dir += p.global_transform.basis.y * f
			ft += f
			out["gimbal_deg"] = maxf(out["gimbal_deg"], float(p.data.get("gimbal_deg", 0.0)))
		if ft > 0.0:
			out["cot"] = cot / ft
			out["thrust_dir"] = dir.normalized()
			out["has_cot"] = true
	return out


func bounds() -> AABB:
	var parts := all_parts()
	if parts.is_empty():
		return AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	var b := AABB()
	var first := true
	for p in parts:
		var pb := p.global_transform * p.aabb
		b = pb if first else b.merge(pb)
		first = false
	return b


func cost_musd() -> float:
	var c := 0.0
	for p in all_parts():
		c += float(p.data.get("cost_musd", 0.0))
	return c


# ------------------------------------------------------------ save / load
## Vessels are saved as regular Godot scenes: the PartInstance tree with transforms,
## attach node names and symmetry tags. They open in the editor (PartInstance is @tool).
func to_packed_scene() -> PackedScene:
	if root == null:
		return null
	for p in all_parts():
		if p != root:
			p.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	for p in all_parts():
		p.owner = null
	return ps


func load_root(r: PartInstance) -> void:
	clear()
	add_child(r)
	r.transform = Transform3D.IDENTITY
	root = r
	var groups := {}
	for p in all_parts():
		p.set_pickable(true)
		if p.sym_tag >= 0:
			if not groups.has(p.sym_tag):
				groups[p.sym_tag] = []
			groups[p.sym_tag].append(p)
	for k in groups:
		for p in groups[k]:
			p.sym_group = groups[k]
	changed.emit()


func load_scene(ps: PackedScene) -> void:
	var r := ps.instantiate() as PartInstance
	if r:
		load_root(r)


## In-memory snapshot used by undo (same data as a saved scene).
func snapshot() -> PackedScene:
	return to_packed_scene()
