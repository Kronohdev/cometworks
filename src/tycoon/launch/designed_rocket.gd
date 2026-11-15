class_name DesignedRocket
extends Node3D
## The look of a designed rocket (scenes/tycoon/launch/designed_rocket.tscn, E2): the launch
## sequence (the cutscene), the pad, the rollout and the designer's preview show the rocket the
## project really flies. build(parts, payload) asks LaunchVessels.scene_for() for the packed
## vessel the career flight flies (the hangar vessel of a rocket built in the hangar, else the
## one built from the design with hangar parts: its stages, tanks, boosters, fairing and a
## carried rover) and shows it through FlightModel.build_look(), the flight's own builder, so
## the cutscene and the flight are the same rocket part for part. Its size is the flight's
## campus size: the flight grows the campus island under a long rocket (FlightRun.island_scale),
## so here the vessel is shrunk by that same factor and the handoff into the 3D flight keeps it
## the same size on screen. An invisible box (BoundsProxy) lets the shots and the pad measure it.
## The era models (`models`, `booster_models`) are only a fallback for a design no vessel can be
## built for; {} parts show the authored look (the default Core model, era 1, what the editor shows).

## fallback: the rocket model per main-stage "model" (1..5)
@export var models: Array[PackedScene] = []
## fallback: booster models: [0] for small solid boosters, [1] for big ones (boosters "size" >= big_size)
@export var booster_models: Array[PackedScene] = []
@export var big_size := 0.45
## fallback: rocket size per launch class (rockets.json classes)
@export var class_scale := {"sounding": 0.85, "light": 1.0, "medium": 1.08, "heavy": 1.15, "lunar": 1.22}
## fallback: a booster's height, times the core's
@export_range(0.2, 1.0, 0.01) var booster_length := 0.55
## fallback: a booster's width, times the core's ("size" of the boosters component scales it too)
@export_range(0.1, 1.0, 0.01) var booster_girth := 1.0
## fallback: how far into the core a booster sits (0 = touching, in booster widths)
@export_range(0.0, 0.5, 0.01) var booster_tuck := 0.12
## fallback: where along the core the boosters stand (0 = on the ground, 1 = at the top), in core heights
@export_range(0.0, 0.5, 0.01) var booster_base := 0.0

## the parts shown ({} = the authored look)
var parts: Dictionary = {}
## width (x) and height (y) of the core as shown, campus metres
var core_size := Vector2(1.4, 7.0)
## the vessel shown (null: the authored look or the era-model fallback)
var vessel: Vessel
## the packed vessel shown: the very scene the flight flies
var vessel_scene: PackedScene
## the vessel's length in real metres (the flight's FlightCraft.length)
var vessel_length := 0.0
## the scene of the authored core model (shown again for an empty design)
var _authored := ""
static var _flight_lengths: Dictionary = {}
## the vessel's side boosters (their radial decouplers, each holding its booster)
var _vessel_boosters: Array[Node3D] = []

@onready var core: Node3D = $Core
@onready var boosters: Node3D = $Boosters


func _ready() -> void:
	for c in core.get_children():
		if c.scene_file_path != "":
			_authored = c.scene_file_path
	var raw0 := _raw_size(core)
	core_size = Vector2(raw0.x * core.scale.x, raw0.y * core.scale.y)
	for s in boosters.get_children():
		for c in s.get_children():
			c.queue_free()


## Shows a design (RocketDesigner parts) with the mission's payload (module ids: a rover in it
## rides on the rocket). {} keeps the authored look. `state` finds a hangar design's own vessel.
func build(p_parts: Dictionary, payload: Array = [], target := "leo", state: TycoonState = null) -> void:
	if not is_node_ready():
		await ready
	parts = RocketDesigner.normalize(p_parts) if not p_parts.is_empty() else {}
	_clear()
	if parts.is_empty():
		if _authored != "":
			core.add_child((load(_authored) as PackedScene).instantiate())
		core.scale = Vector3.ONE
		core_size = _raw_size(core)
		return
	var ps := LaunchVessels.scene_for(p_parts, target, payload, state)
	if ps != null and _show_vessel(ps):
		return
	push_warning("DesignedRocket: no vessel for %s, showing the era model" % [parts])
	_build_era_model()


## Shows a packed vessel as it flies (a launch with no design flies an example rocket:
## TycoonModes.watch_vessel). False (and the authored look) when it has no parts or this node
## is not ready yet (add it to the tree first).
func show_scene(ps: PackedScene) -> bool:
	if not is_node_ready():
		return false
	parts = {}
	_clear()
	if ps != null and _show_vessel(ps):
		return true
	if _authored != "":
		core.add_child((load(_authored) as PackedScene).instantiate())
	core_size = _raw_size(core)
	return false


func _clear() -> void:
	for s in boosters.get_children():
		for c in s.get_children():
			s.remove_child(c)
			c.queue_free()
	for c in core.get_children():
		core.remove_child(c)
		c.queue_free()
	vessel = null
	vessel_scene = null
	vessel_length = 0.0
	_vessel_boosters.clear()
	core.scale = Vector3.ONE


## The flying rocket's look (FlightModel.build_look), at its flight campus size.
func _show_vessel(ps: PackedScene) -> bool:
	var v := FlightModel.build_look(ps, core)
	if v.root == null:
		core.remove_child(v)
		v.free()
		return false
	vessel = v
	vessel_scene = ps
	var box := AABB()
	var first := true
	var axis_w := 0.0
	for p in v.all_parts():
		var xf := _xf_to(p, core)
		var b := xf * p.aabb
		box = b if first else box.merge(b)
		first = false
		if PartDB.is_radial_decoupler(p.data) and not p.part_children().is_empty():
			_vessel_boosters.append(p)
		# the core stack: the parts on the axis (the side boosters are not its width)
		if Vector2(xf.origin.x, xf.origin.z).length() < 0.05:
			axis_w = maxf(axis_w, maxf(b.size.x, b.size.z))
	var w := maxf(maxf(box.size.x, box.size.z), 0.01)
	var h := maxf(box.size.y, 0.01)
	vessel_length = h
	var s := 1.0 / FlightRun.island_scale(flight_length_of(ps))
	var c := box.get_center()
	v.position = Vector3(-c.x, -box.position.y, -c.z)
	core.scale = Vector3.ONE * s
	var proxy := MeshInstance3D.new()
	proxy.name = "BoundsProxy"
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, w)
	proxy.mesh = bm
	proxy.position = Vector3(0, h * 0.5, 0)
	proxy.visible = false
	core.add_child(proxy)
	core_size = Vector2((axis_w if axis_w > 0.0 else w) * s, h * s)
	return true


## The length the flight gives this vessel (FlightCraft.length), which sizes the campus island
## under it in the 3D flight (FlightRun.island_scale): the cutscene shrinks the rocket by that
## same factor so the handoff keeps its size. Cached per packed scene.
static func flight_length_of(ps: PackedScene) -> float:
	if not _flight_lengths.has(ps):
		if _flight_lengths.size() > 256:
			_flight_lengths.clear()
		_flight_lengths[ps] = FlightCraft.from_scene(ps).length
	return float(_flight_lengths[ps])


## Transform of `n` relative to `stop` (works off the tree).
static func _xf_to(n: Node3D, stop: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## How many side boosters are shown (the vessel's, or the fallback's).
func shown_boosters() -> int:
	var n := 0
	if vessel:
		for d in _vessel_boosters:
			if is_instance_valid(d) and d.visible:
				n += 1
		return n
	for slot in boosters.get_children():
		n += slot.get_child_count()
	return n


## Is a rover riding on the vessel (LaunchVessels' carried payload)?
func carries_rover() -> bool:
	return vessel != null and vessel.find_child(LaunchVessels.PAYLOAD_NODE, true, false) != null


## Fallback: the era model of the main stage, sized by launch class, with model boosters.
func _build_era_model() -> void:
	var st := RocketDesigner.stats(parts)
	var mi := clampi(int(st["model"]), 1, maxi(models.size(), 1)) - 1
	if mi < models.size() and models[mi] != null:
		core.add_child(models[mi].instantiate())
	var k := float(class_scale.get(String(st["class"]), 1.0))
	core.scale = Vector3(k, k * float(st["height"]), k)
	var raw := _raw_size(core)
	core_size = Vector2(raw.x * k, raw.y * k * float(st["height"]))
	var n := int(st["boosters"])
	if n <= 0 or booster_models.is_empty():
		return
	var big := float(st["booster_size"]) >= big_size and booster_models.size() > 1
	var ps: PackedScene = booster_models[1 if big else 0]
	if ps == null:
		return
	var probe := ps.instantiate() as Node3D
	var b_raw := _raw_size(probe)
	probe.free()
	var h := core_size.y * booster_length
	var sy := h / maxf(b_raw.y, 0.01)
	var w := core_size.x * booster_girth * clampf(float(st["booster_size"]) / 0.32, 0.6, 1.6) * 0.5
	var sx := w / maxf(b_raw.x, 0.01)
	var radius := core_size.x * 0.5 + w * (0.5 - booster_tuck)
	var slots := boosters.get_children()
	for i in mini(n, slots.size()):
		var slot := slots[i] as Node3D
		var dir := Vector3(slot.position.x, 0.0, slot.position.z)
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.RIGHT
		slot.position = dir * radius + Vector3(0, core_size.y * booster_base, 0)
		slot.rotation = Vector3.ZERO
		slot.visible = true
		var b := ps.instantiate() as Node3D
		b.scale = Vector3(sx, sy, sx)
		slot.add_child(b)


## The side boosters let go: they drift out and down from the core and vanish over `seconds`
## (the launch sequence calls it at the stage separation).
func drop_boosters(seconds := 1.4) -> void:
	# the vessel's own: each radial decoupler leaves with its booster, like the flight drops them
	for d in _vessel_boosters:
		if not is_instance_valid(d) or not d.visible:
			continue
		var out := Vector3(d.position.x, 0.0, d.position.z)
		out = out.normalized() if out.length() > 0.001 else Vector3.RIGHT
		var len := vessel_length if vessel_length > 0.0 else 10.0
		var tw0 := create_tween().set_parallel()
		tw0.tween_property(d, "position", d.position + out * len * 0.12 + Vector3(0, -len * 0.35, 0), seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw0.tween_property(d, "rotation", d.rotation + Vector3(out.z, 0.0, -out.x) * 0.6, seconds)
		tw0.chain().tween_callback(func() -> void: d.visible = false)
	for s in boosters.get_children():
		var slot := s as Node3D
		if slot == null or slot.get_child_count() == 0:
			continue
		var out := Vector3(slot.position.x, 0.0, slot.position.z).normalized()
		var tw := create_tween().set_parallel()
		tw.tween_property(slot, "position", slot.position + out * core_size.x * 1.6 + Vector3(0, -core_size.y * 0.9, 0), seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(slot, "rotation", Vector3(out.z, 0.0, -out.x) * 0.6, seconds)
		tw.chain().tween_callback(func() -> void: slot.visible = false)


## The bounds of what is shown (core and boosters), in this node's space.
func bounds() -> AABB:
	return local_bounds(self)


## Bounds of the meshes under `n`, in `n`'s own space (its own transform left out); works
## outside the tree.
static func local_bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var c: Node = mi
		while c != null and c != n:
			if c is Node3D:
				xf = (c as Node3D).transform * xf
			c = c.get_parent()
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Width / height of the meshes under `n` before its own scale.
static func _raw_size(n: Node3D) -> Vector2:
	var box := local_bounds(n)
	return Vector2(box.size.x, box.size.y)
