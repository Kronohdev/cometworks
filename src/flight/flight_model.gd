class_name FlightModel
extends Node3D
## The look of the flying rocket: the hangar's own part tree (a Vessel with its JointDecor
## collars, exactly as built in the hangar) plus an engine plume per engine
## (scenes/flight/engine_plume.tscn). It mirrors a FlightCraft: setup() builds the same tree the
## craft was read from, so `part_nodes[i]` is the craft's part i; detach() cuts a group's
## subtree off (it becomes a falling Debris piece of the world), set_engines() drives the plumes.
## The node's origin is the simulation's point: the bottom of the rocket on the pad.

const PLUME_SCENE := preload("res://scenes/flight/engine_plume.tscn")

var vessel: Vessel
var decor: JointDecor
var part_nodes: Array[PartInstance] = []
var plumes: Array = []   # engine index -> plume node (or null)
var craft: FlightCraft
## local bounds of what is still attached (for the camera)
var bounds := AABB(Vector3.ZERO, Vector3.ONE)


func setup(ps: PackedScene, c: FlightCraft) -> void:
	craft = c
	vessel = build_look(ps, self)
	decor = vessel.get_node("JointDecor") as JointDecor
	part_nodes = vessel.all_parts()
	# the rocket's base sits on the node's origin
	var b := _bounds()
	vessel.position = Vector3(0, -b.position.y, 0)
	plumes.clear()
	for e: Dictionary in c.engines:
		var p := part_nodes[int(e["part"])] if int(e["part"]) < part_nodes.size() else null
		if p == null:
			plumes.append(null)
			continue
		var plume: Node3D = PLUME_SCENE.instantiate()
		p.add_child(plume)
		plume.position = Vector3(0, p.aabb.position.y, 0)
		if plume.has_method("setup"):
			plume.call("setup", p.radius(), String(p.data.get("propellant", "")), float(e["f_vac"]))
		plumes.append(plume)
	bounds = _bounds()


## The look of a packed vessel, exactly as it flies: the part tree under a Vessel node (added
## to `parent`) with its JointDecor collars. The launch cutscene, the pad and the designer's
## preview (DesignedRocket) build the rocket through this too, so they show the flying one.
static func build_look(ps: PackedScene, parent: Node3D) -> Vessel:
	var v := Vessel.new()
	v.name = "Vessel"
	parent.add_child(v)
	v.load_scene(ps)
	var d := JointDecor.new()
	d.name = "JointDecor"
	d.vessel = v
	v.add_child(d)
	if v.is_inside_tree():
		d.rebuild()
	return v


func _bounds() -> AABB:
	var box := AABB()
	var first := true
	for p in vessel.all_parts():
		var xf := _xf(p)
		var b := xf * p.aabb
		box = b if first else box.merge(b)
		first = false
	return box


## Transform of a part relative to this node.
func _xf(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Centre of what is still attached (local), for the camera's focus.
func center() -> Vector3:
	return bounds.get_center()


## Cuts the subtree of a craft group (or a fairing part) off the model. Returns the piece
## (a Node3D holding the parts, already at the same place) for the world to throw away.
func detach_part(part_index: int) -> Node3D:
	if part_index < 0 or part_index >= part_nodes.size():
		return null
	var p := part_nodes[part_index]
	if not is_instance_valid(p) or not vessel.is_ancestor_of(p):
		return null
	var xf := _xf(p)
	var piece := Node3D.new()
	piece.name = "Piece_" + p.part_id
	p.get_parent().remove_child(p)
	piece.add_child(p)
	p.transform = Transform3D.IDENTITY
	piece.set_meta("local_xf", xf)
	# the plumes that left with it go out
	for i in plumes.size():
		var pl: Variant = plumes[i]
		if pl is Node3D and is_instance_valid(pl) and piece.is_ancestor_of(pl):
			(pl as Node3D).call("set_state", 0.0, 1.0)
			plumes[i] = null
	decor.rebuild()
	bounds = _bounds() if vessel.root else AABB()
	return piece


func detach_group(gi: int) -> Node3D:
	if craft == null or gi < 0 or gi >= craft.groups.size():
		return null
	return detach_part(int(craft.groups[gi]["root"]))


## Plumes follow the craft's engines (throttle of the engines that burn, the air pressure).
func set_engines(pressure: float) -> void:
	if craft == null:
		return
	for i in mini(plumes.size(), craft.engines.size()):
		var pl: Variant = plumes[i]
		if not (pl is Node3D) or not is_instance_valid(pl):
			continue
		var e: Dictionary = craft.engines[i]
		var thr := float(e["thr"]) if float(e["thrust"]) > 0.0 else 0.0
		(pl as Node3D).call("set_state", thr, pressure)


## Nozzle points (local) and their radius of the engines burning now: [{pos, r, solid}].
func burning_nozzles() -> Array:
	var out: Array = []
	if craft == null:
		return out
	for i in mini(plumes.size(), craft.engines.size()):
		var e: Dictionary = craft.engines[i]
		if float(e["thrust"]) <= 0.0 or plumes[i] == null:
			continue
		var p := part_nodes[int(e["part"])]
		if not is_instance_valid(p) or not vessel.is_ancestor_of(p):
			continue
		var xf := _xf(p)
		out.append({"pos": xf * Vector3(0, p.aabb.position.y, 0), "r": p.radius(), "solid": bool(e["solid"])})
	return out


## Engine-off look: every plume out.
func engines_off() -> void:
	for pl: Variant in plumes:
		if pl is Node3D and is_instance_valid(pl):
			(pl as Node3D).call("set_state", 0.0, 1.0)
