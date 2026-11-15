class_name LaunchVessels
extends RefCounted
## The one rocket of a design: the packed hangar vessel the flight flies (FlightCraft stages,
## burns and drops its parts) AND the launch cutscene, the pad and the designer's preview show
## (DesignedRocket builds its look from this same PackedScene, the way FlightModel does). There
## is no other model of a designed rocket: scene_for() is the single source.
##   scene_for(parts, target, payload, state)
##       the project's hangar vessel (a rocket built in the hangar: HangarRocket) with the
##       mission's rover put on it (with_rover), else for_design(): a vessel built from the
##       RocketDesigner design with the hangar's own attach API (ExampleVessels' helpers),
##       cached per design and payload.
## for_design() maps every slot of the design onto hangar parts:
##   main stage "model" 1 (Kestrel)   small kerolox stack, a cluster of Kestrels on a plate
##   2..3 (Falcão, Harpia)            large kerolox stack (Condor's), Falcão cluster
##   4..5 (Metano, Hidra)             large hydrolox stack (Garça's), a Hidra 25
##   tank                             one tank section fewer (tank_s) / more (tank_l)
##   upper stage                      its own vacuum engine (upper_kestrel_v, upper_falcao_v,
##                                    upper_hidra_5) on a tank of its propellant over a
##                                    decoupler (none: the avionics sit on the main stage)
##   boosters                         2 or 4 boosters on radial decouplers (solid: the core's
##                                    size; the liquid pair: the big ones)
##   fairing                          the fairing of its size on top (none: a payload adapter)
##   payload                          a rover the mission carries (RoverDesign.from_payload)
##                                    rides on the avionics under the fairing (seen when the
##                                    fairing goes), or on the payload adapter: its voxel look,
##                                    fitted to the room, as plain meshes (no mass: the flight's
##                                    payload mass is the mission's)
## The numbers of the flight come from these parts; the career outcome stays the design's.

const UPPER_ENGINE := {"upper_kestrel_v": "eng_kestrel_v", "upper_falcao_v": "eng_falcao_v", "upper_hidra_5": "eng_hidra_5"}
## upper-stage tanks per stack size ("S" small core, "L" model 2..3, "M" model 4..5) and engine
const UPPER_TANKS := {
	"S": {"upper_kestrel_v": ["tank_kerolox_s2"], "upper_falcao_v": ["tank_kerolox_s4"],
		"upper_hidra_5": ["tank_hydrolox_s4"]},
	"L": {"upper_kestrel_v": ["tank_kerolox_l4"], "upper_falcao_v": ["tank_kerolox_l8", "tank_kerolox_l4"],
		"upper_hidra_5": ["tank_hydrolox_l8", "tank_hydrolox_l4"]},
	"M": {"upper_kestrel_v": ["tank_kerolox_m4"], "upper_falcao_v": ["tank_kerolox_m8"],
		"upper_hidra_5": ["tank_hydrolox_m8", "tank_hydrolox_m4"]},
}
## name of the node holding a carried rover's look (a child of the part it rides on)
const PAYLOAD_NODE := "PayloadRover"
## how much of the room (diameter / fairing height) a carried rover may take
const PAYLOAD_FIT := 0.8

static var _cache: Dictionary = {}


## The packed vessel a design flies (and is shown) as; null for no design. `state` finds a
## hangar design's own vessel (without it the registered hangar component's tree is used).
static func scene_for(parts: Dictionary, target := "leo", payload: Array = [], state: TycoonState = null) -> PackedScene:
	if parts.is_empty():
		return null
	var ps: PackedScene = HangarRocket.scene_for(state, parts) if state else null
	if ps == null:
		var core := RocketDesigner.component(String(parts.get("core", "")))
		if core.has("tree"):
			ps = HangarRocket.scene_of(core["tree"])
	if ps != null:
		return with_rover(ps, payload)
	return for_design(parts, target, payload)


## A hangar vessel with the mission's rover riding on it (the same look as for_design's: under
## its fairing, else on top), cached per vessel tree and rover; `ps` itself when the payload has
## no rover. The rover is plain meshes: HangarRocket.tree() and the flight's numbers skip it.
static func with_rover(ps: PackedScene, payload: Array) -> PackedScene:
	var rover := RoverDesign.from_payload(payload) if not payload.is_empty() else {}
	if ps == null or rover.is_empty():
		return ps
	var key := "hg|%d|%s" % [hash(JSON.stringify(HangarRocket.tree(ps))), RoverDesign.payload_code(rover)]
	if _cache.has(key):
		return _cache[key]
	var v := Vessel.new()
	v.load_scene(ps)
	var out := ps
	if v.root:
		# off the tree the parts have no models yet: their real sizes place the rover
		for p in v.all_parts():
			p.ensure_size()
		_carry_rover(v, rover)
		out = v.to_packed_scene()
	v.free()
	_cache[key] = out
	return out


static func for_design(parts: Dictionary, _target := "leo", payload: Array = []) -> PackedScene:
	var p := RocketDesigner.normalize(parts) if not parts.is_empty() else {}
	if p.is_empty():
		return null
	var rover := RoverDesign.from_payload(payload) if not payload.is_empty() else {}
	var key := "%s|%s|%s|%s|%s|%s" % [p.get("core", ""), p.get("upper", ""), p.get("tank", ""), p.get("boosters", ""),
		p.get("fairing", ""), RoverDesign.payload_code(rover) if not rover.is_empty() else ""]
	if _cache.has(key):
		return _cache[key]
	var v := Vessel.new()
	var ok := _build(v, p)
	if ok and v.root and not rover.is_empty():
		_carry_rover(v, rover)
	var ps: PackedScene = v.to_packed_scene() if ok and v.root else null
	v.free()
	_cache[key] = ps
	return ps


## Every rocket design the designer can make (one component per slot, any research): what
## the dev check and the tests build to prove each one has a model.
static func every_design() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{}]
	for sid in RocketDesigner.slot_ids():
		var next: Array[Dictionary] = []
		var ids: Array[String] = []
		for c in RocketDesigner.components(sid):
			if String(c.get("id", "")).begins_with("hg"):
				continue  # a hangar rocket's own component (it has its vessel)
			ids.append(String(c["id"]))
		if sid in ["avionics", "recovery"]:
			ids = ids.slice(0, 1)  # no part of the look
		for d in out:
			for id in ids:
				var e := d.duplicate()
				e[sid] = id
				next.append(e)
		out = next
	return out


static func _model(p: Dictionary) -> int:
	return int(RocketDesigner.component(String(p.get("core", ""))).get("model", 1))


static func _tank_delta(p: Dictionary) -> int:
	var h := float(RocketDesigner.component(String(p.get("tank", "tank_m"))).get("height", 1.0))
	return -1 if h < 0.95 else (1 if h > 1.05 else 0)


static func _build(v: Vessel, p: Dictionary) -> bool:
	var model := _model(p)
	var upper := String(p.get("upper", "upper_none"))
	var boosters := RocketDesigner.component(String(p.get("boosters", "boost_none")))
	var fairing := String(p.get("fairing", "fairing_none"))
	var small := model <= 1
	var tank_d := _tank_delta(p)
	v.set_root(PartInstance.create("avionics_core_s" if small else "avionics_core_m"))
	# the top: a fairing of its size, or a payload adapter
	var top_id := "payload_adapter"
	if fairing != "fairing_none":
		if small:
			top_id = "fairing_s" if fairing == "fairing_s" else "fairing_s_long"
		else:
			top_id = "fairing_m_long" if fairing == "fairing_l" else "fairing_m"
	if _try_stack(v, v.root, "top", top_id) == null and top_id != "payload_adapter":
		_try_stack(v, v.root, "top", "fairing_s" if small else "fairing_m")
	var t: PartInstance = v.root
	if upper != "upper_none":
		var size := "S" if small else ("L" if model <= 3 else "M")
		var tanks: Array = (UPPER_TANKS[size] as Dictionary).get(upper, (UPPER_TANKS[size] as Dictionary)["upper_falcao_v"])
		var engine := String(UPPER_ENGINE.get(upper, "eng_falcao_v"))
		if size == "L":
			t = ExampleVessels.stack(v, t, "bottom", "adapter_ml")
		for tk in tanks:
			t = ExampleVessels.stack(v, t, "bottom", String(tk))
		t = ExampleVessels.stack(v, t, "bottom", engine)
		match size:
			"S":
				t = ExampleVessels.stack(v, t, "bottom", "decoupler_s")
			"L":
				t = ExampleVessels.stack(v, t, "bottom", "decoupler_l")
				t = ExampleVessels.stack(v, t, "bottom", "interstage_l")
			_:
				t = ExampleVessels.stack(v, t, "bottom", "decoupler_m")
				t = ExampleVessels.stack(v, t, "bottom", "adapter_ml")
	elif not small:
		t = ExampleVessels.stack(v, t, "bottom", "adapter_ml")
	# the main stage
	var core_top: PartInstance = null
	if small:
		var ids: Array = [["tank_kerolox_s4", "tank_kerolox_s2"], ["tank_kerolox_s8"], ["tank_kerolox_s8", "tank_kerolox_s2"]][tank_d + 1]
		var ct := t
		for id in ids:
			ct = ExampleVessels.stack(v, ct, "bottom", String(id))
			if core_top == null:
				core_top = ct
		var plate := ExampleVessels.stack(v, ct, "bottom", "thrust_plate_s9")
		ExampleVessels.fill_slots(v, plate, "eng_kestrel")
	elif model <= 3:
		core_top = ExampleVessels.stack(v, t, "bottom", "tank_kerolox_l8")
		var ct := core_top
		for i in maxi((3 if model == 2 else 4) + tank_d, 0):
			ct = ExampleVessels.stack(v, ct, "bottom", "tank_kerolox_l8")
		var plate := ExampleVessels.stack(v, ct, "bottom", "thrust_plate_l9")
		ExampleVessels.fill_slots(v, plate, "eng_falcao")
	else:
		core_top = ExampleVessels.stack(v, t, "bottom", "tank_hydrolox_l8")
		var ct := core_top
		for i in maxi((3 if model == 4 else 4) + tank_d, 0):
			ct = ExampleVessels.stack(v, ct, "bottom", "tank_hydrolox_l8")
		ExampleVessels.stack(v, ct, "bottom", "eng_hidra_25")
	# side boosters
	var n := int(boosters.get("count", 0))
	if n >= 2 and core_top:
		var big := float(boosters.get("size", 0.32)) >= 0.45
		var srb := "eng_srb_s" if small and not big else "eng_srb_m"
		var rd := _radial(v, core_top, "decoupler_radial", core_top.aabb.position.y + core_top.height() * 0.5, n)
		# one booster on the first decoupler: the attach mirrors it on its symmetry partners
		var b := PartInstance.create(srb)
		v.attach(rd, b, Vessel.local_for_node(rd, "side", b, "sidechild"), "side", "sidechild")
	return true


## A radial part on the surface of `t` at local height `y` (ExampleVessels.radial in t's own
## space, so it works off the tree: no global transforms).
static func _radial(v: Vessel, t: PartInstance, id: String, y: float, symmetry: int) -> PartInstance:
	var p := PartInstance.create(id)
	var point := Vector3(t.radius(), clampf(y, t.aabb.position.y, t.aabb.end.y), 0.0)
	v.attach(t, p, Vessel.local_for_surface(t, point, Vector3.RIGHT, p), "surface", "surface", symmetry)
	return p


static func _try_stack(v: Vessel, t: PartInstance, node: String, id: String) -> PartInstance:
	if PartDB.get_part(id).is_empty():
		return null
	var p := PartInstance.create(id)
	var on := Vessel.own_node_for(t, node, p)
	if on == "":
		p.free()
		return null
	v.attach(t, p, Vessel.local_for_node(t, node, p, on), node, on)
	return p


# ------------------------------------------------------------ the carried rover
## The rover's voxel look on the vessel: inside its fairing (on the part the fairing stands on,
## at that attach node; the topmost fairing when there are several), else on the topmost part
## with a free top node (the payload adapter of a design without a fairing). Plain meshes owned
## by the root, so they pack with the vessel.
static func _carry_rover(v: Vessel, rover: Dictionary) -> void:
	var fairing: PartInstance = null
	var fairing_y := -INF
	var top: PartInstance = null
	var top_y := -INF
	for p in v.all_parts():
		var y := (DesignedRocket._xf_to(p, v) * p.aabb).end.y
		if PartDB.is_fairing(p.data):
			if y > fairing_y:
				fairing_y = y
				fairing = p
		elif p.has_node_point("top") and not "top" in p.occupied_nodes() and y > top_y:
			top_y = y
			top = p
	var on: PartInstance = top if top else v.root
	var at := "top"
	if fairing:
		on = fairing.part_parent()
		at = fairing.parent_node_name
		if on == null:  # the fairing is the root: the rover stands on its base, inside it
			on = fairing
			at = "bottom"
	var holder := rover_look(rover)
	if holder == null:
		return
	var box := DesignedRocket.local_bounds(holder)
	var room := 1.25
	if fairing:
		room = float(PartDB.size_classes.get(fairing.node_size("bottom"), 1.25))
	else:
		room = float(PartDB.size_classes.get(on.node_size("top"), 1.25))
		if on != v.root:
			room = maxf(room, float(PartDB.size_classes.get(on.node_size("bottom"), 1.25)))
	var w := maxf(maxf(box.size.x, box.size.z), 0.01)
	var k := room * PAYLOAD_FIT / w
	if fairing:
		k = minf(k, fairing.height() * PAYLOAD_FIT * 0.75 / maxf(box.size.y, 0.01))
	k = minf(k, 1.0)
	holder.scale = Vector3.ONE * k
	var c0 := box.get_center()
	holder.position = on.node_local(at) - Vector3(c0.x, box.position.y, c0.z) * k
	on.add_child(holder)
	holder.owner = v.root
	for n in holder.find_children("*", "", true, false):
		n.owner = v.root


## A rover design's look as one Node3D of plain MeshInstance3D copies (RoverDesign.assemble,
## flattened: no scripts, no instanced scenes), its base at the origin; null without a chassis.
static func rover_look(rover: Dictionary) -> Node3D:
	var tmp := Node3D.new()
	var body := RoverDesign.assemble(rover, tmp)
	if body == null:
		tmp.free()
		return null
	var holder := Node3D.new()
	holder.name = PAYLOAD_NODE
	var i := 0
	for m in tmp.find_children("*", "MeshInstance3D", true, false):
		var src := m as MeshInstance3D
		if src.mesh == null or not src.visible:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = src
		while n != null and n != tmp:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var mi := MeshInstance3D.new()
		mi.name = "Mesh%d" % i
		i += 1
		mi.mesh = src.mesh
		mi.transform = xf
		mi.material_override = src.material_override
		for s in src.get_surface_override_material_count():
			mi.set_surface_override_material(s, src.get_surface_override_material(s))
		mi.cast_shadow = src.cast_shadow
		holder.add_child(mi)
	tmp.free()
	if holder.get_child_count() == 0:
		holder.free()
		return null
	return holder
