class_name Campus
extends Node3D
## The Cometworks campus (scenes/tycoon/campus.tscn): terrain, roads, lots and props are
## authored in the scene; this script places the buildings on the lots from TycoonState,
## switches the look of buildings and roads with the era, keeps a crowd of Cometlings
## walking between the buildings' spots, and answers which lot is under the mouse.

signal lot_clicked(lot_id: String)
signal era_changed(era: int)

const BUILDINGS_DIR := "res://scenes/tycoon/buildings/%s.tscn"
const MAX_WALKERS := 12
## how mowed the lawns are per era (shaders/campus_terrain.gdshader `tidy`)
const TIDY := [0.0, 0.25, 0.55, 0.8, 1.0]

var state: TycoonState
var era := 1
## the road and plaza materials authored in the scene (shaders/campus_road.gdshader, by `era`)
var _road_mat: ShaderMaterial
var _plaza_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _buildings := {}      # lot id -> CampusBuilding
var _rng := RandomNumberGenerator.new()

@onready var lots: Node3D = $Lots
@onready var roads: Node3D = $Roads


func _ready() -> void:
	_rng.seed = 1234
	# the roads share one material and the plaza has its own; the era is a shader parameter
	for c in roads.get_children():
		if c is MeshInstance3D:
			var m := (c as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
			if m == null:
				continue
			if c.name == "Plaza":
				_plaza_mat = m
			elif _road_mat == null:
				_road_mat = m
			else:
				(c as MeshInstance3D).set_surface_override_material(0, _road_mat)
	var plateau := get_node_or_null("Terrain/Plateau") as MeshInstance3D
	if plateau:
		_ground_mat = plateau.get_surface_override_material(0) as ShaderMaterial


func bind(s: TycoonState) -> void:
	state = s
	state.changed.connect(sync)
	sync()


## Rebuilds what changed: buildings on lots, construction scaffolds, era looks, crowd size.
func sync() -> void:
	if state == null:
		return
	era = state.era()
	apply_era(era)
	for lot in lots.get_children():
		var id := String(lot.name)
		var b := state.building(id)
		var frame := lot.get_node_or_null("Frame") as Node3D
		var level := int(b.get("level", 0))
		var constructing := int(b.get("weeks_left", 0)) > 0
		if frame:
			frame.visible = level == 0 and not constructing
		if level == 0 and not constructing:
			if _buildings.has(id):
				(_buildings[id] as Node).queue_free()
				_buildings.erase(id)
			continue
		var node: CampusBuilding = _buildings.get(id)
		if node == null:
			var ps := load(BUILDINGS_DIR % String(lot.get_meta("kind", "hq"))) as PackedScene
			node = ps.instantiate() as CampusBuilding
			node.rotation.y = float(lot.get_meta("face", 0.0))
			lot.add_child(node)
			_buildings[id] = node
		node.set_look(era, level, constructing)
	_sync_crowd()


## The era look of everything that is not a building: road surface, lawns, path lights and
## the era dressing (under the Dressing and Life nodes, any node with metadata era_min /
## era_max is shown only in those eras: wooden fences in the workshop years, floodlights and
## pad steam at the launch base).
func apply_era(e: int) -> void:
	era = clampi(e, 1, 5)
	if _road_mat:
		_road_mat.set_shader_parameter("era", era)
	if _plaza_mat:
		_plaza_mat.set_shader_parameter("era", era)
	if _ground_mat:
		_ground_mat.set_shader_parameter("tidy", TIDY[era - 1])
	var pl := roads.get_node_or_null("PathLights") as Node3D
	if pl:
		pl.visible = era >= 4
	for group in ["Dressing", "Life"]:
		var n := get_node_or_null(group)
		if n:
			_apply_era_meta(n)
	era_changed.emit(era)


func _apply_era_meta(n: Node) -> void:
	for c in n.get_children():
		if c.has_meta("era_min") or c.has_meta("era_max"):
			var lo := int(c.get_meta("era_min", 1))
			var hi := int(c.get_meta("era_max", 5))
			if c is Node3D:
				(c as Node3D).visible = era >= lo and era <= hi
			if not (era >= lo and era <= hi):
				continue
		if c.get_child_count() > 0:
			_apply_era_meta(c)


## Lot id under a screen point (ray against the ground plane), "" if none.
func lot_at(camera: Camera3D, screen: Vector2) -> String:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 1e-4:
		return ""
	var t := -from.y / dir.y
	if t < 0.0:
		return ""
	var p := from + dir * t
	for lot in lots.get_children():
		var sz: Vector2 = lot.get_meta("size", Vector2.ZERO)
		var c := (lot as Node3D).global_position
		if absf(p.x - c.x) <= sz.x * 0.5 and absf(p.z - c.z) <= sz.y * 0.5:
			return String(lot.name)
	return ""


func lot_position(lot_id: String) -> Vector3:
	var n := lots.get_node_or_null(lot_id) as Node3D
	return n.global_position if n else Vector3.ZERO


# ------------------------------------------------------------ crowd
func all_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in $Spots.get_children():
		if m is Marker3D:
			out.append({"pos": (m as Marker3D).global_position, "door": m.get_meta("door", Vector3.ZERO),
				"action": String(m.get_meta("action", "idle")), "yaw": (m as Marker3D).global_rotation.y})
	for b: CampusBuilding in _buildings.values():
		if not b.building:
			out += b.spots()
	return out


## Shows one Cometling of the Crowd (editable instances in the scene) per staff member.
func _sync_crowd() -> void:
	var want := clampi(state.staff.size(), 3, MAX_WALKERS)
	var i := 0
	for w in $Crowd.get_children():
		var on := i < want
		if on and not w.visible or (on and not w.get("campus")):
			var member: Dictionary = state.staff[i] if i < state.staff.size() else {}
			w.call("setup", self, _rng.randi(), int(member.get("variant", w.get("variant"))),
				String(member.get("role", w.get("role"))))
		w.visible = on
		w.set_process(on)
		i += 1


## The Cometlings walking on the campus right now (the visible members of the Crowd).
func cometlings() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for w in $Crowd.get_children():
		if w is Node3D and (w as Node3D).visible:
			out.append(w)
	return out


## The staff member a Crowd Cometling stands for ({"name", "role", ...}), {} for an extra.
func cometling_member(w: Node) -> Dictionary:
	if state == null or w == null or w.get_parent() != $Crowd:
		return {}
	var i := w.get_index()
	return state.staff[i] if i < state.staff.size() else {}
