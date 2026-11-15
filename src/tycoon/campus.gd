class_name Campus
extends Node3D
## The Cometworks campus (scenes/tycoon/campus.tscn): terrain, roads, lots and props are
## authored in the scene; this script places the buildings on the lots from TycoonState,
## switches the look of buildings and roads with the era, keeps a crowd of Cometlings
## walking between the buildings' spots, and answers which lot is under the mouse.
##
## Walking: the campus keeps a walk grid (src/tycoon/campus_nav.gd) built from what stands on
## it (building walk masks, props, dressing, scattered trees and rocks; nodes with metadata
## walk_through = true are ignored), kept inside the island's flat top (Terrain/Plateau's
## walk_outline, scenes/tycoon/campus_island.tscn) and rebuilt when a building or the era changes. Each spot
## is claimed by one Cometling at a time, so nobody walks onto someone else.

signal lot_clicked(lot_id: String)
signal era_changed(era: int)

const BUILDINGS_DIR := "res://scenes/tycoon/buildings/%s.tscn"
## how mowed the lawns are per era (shaders/campus_terrain.gdshader `tidy`)
const TIDY := [0.0, 0.25, 0.55, 0.8, 1.0]
## metadata of the extra walkers the dev menu spawns (no staff member; the crowd sync keeps them)
const DEV_EXTRA := &"dev_extra"

@export_group("Walkers")
## cost of walking a metre on the roads and the plaza (the cheapest ground)
@export var road_cost := 1.0
## cost of walking a metre on the lawns: Cometlings keep to the roads unless a lawn saves
## them a long way round
@export var grass_cost := 1.6
## cost of a metre close to a wall, a desk or a tree: paths keep away from things
@export var near_cost := 4.0
## how close counts as close (m)
@export var near_radius := 0.75

var state: TycoonState
var era := 1
## the walk grid of the Cometlings (rebuilt by sync when buildings or the era change)
var nav: CampusNav
## the road and plaza materials authored in the scene (shaders/campus_road.gdshader, by `era`)
var _road_mat: ShaderMaterial
var _plaza_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _buildings := {}      # lot id -> CampusBuilding
var _rng := RandomNumberGenerator.new()
var _crowd_synced := false
var _nav_key := ""
var _claims := {}         # spot key -> the Cometling walking to or standing at it

@onready var lots: Node3D = $Lots
@onready var roads: Node3D = $Roads
## the story signs around the island (scenes/tycoon/campus_signs.tscn), null in scenes without them
@onready var signs: CampusSigns = get_node_or_null("Signs") as CampusSigns


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
	if signs:
		signs.bind(state)


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
		if node.kind == "pad":
			var pl := LaunchPads.pad_launch(state, id)  # the designed rocket (E2) and the rover it carries
			node.set_rocket_design(pl["parts"], pl["payload"], String(pl["target"]), state)
			node.set_rocket_progress(LaunchPads.rocket_progress(state, id))  # the next rocket rolls out
	_sync_nav()
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


## The building standing on a lot (null while the lot is empty).
func building_node(lot_id: String) -> CampusBuilding:
	return _buildings.get(lot_id) as CampusBuilding


func lot_position(lot_id: String) -> Vector3:
	var n := lots.get_node_or_null(lot_id) as Node3D
	return n.global_position if n else Vector3.ZERO


# ------------------------------------------------------------ walking
## Rebuilds the walk grid when the buildings or the era changed.
func _sync_nav() -> void:
	var key := str(era)
	for id: String in _buildings:
		var b: CampusBuilding = _buildings[id]
		key += "|%s:%d:%d" % [id, b.level, int(b.building)]
	if nav != null and key == _nav_key:
		return
	_nav_key = key
	nav = build_nav()
	for w in cometlings():
		if not nav.is_free(Vector2(w.position.x, w.position.z)):
			w.call("place_free")
		w.call("replan")


## A walk grid of the campus as it stands now (campus-local x, z).
func build_nav() -> CampusNav:
	var n := CampusNav.new()
	n.road_cost = road_cost
	n.grass_cost = grass_cost
	n.near_cost = near_cost
	n.near_radius = near_radius
	var inv := global_transform.affine_inverse()
	var rect := Rect2(-70, -50, 152, 106)
	var plateau := get_node_or_null("Terrain/Plateau") as MeshInstance3D
	if plateau:
		var xf := inv * plateau.global_transform
		var a := plateau.get_aabb()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in 8:
			var p := xf * a.get_endpoint(i)
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
		rect = Rect2(lo, hi - lo)
	n.setup(rect)
	# the island's flat top: off it the ground drops to the terraces, the beach and the sea
	if plateau and plateau.has_meta("walk_outline"):
		var pxf := inv * plateau.global_transform
		var outline := PackedVector2Array()
		for q: Vector2 in plateau.get_meta("walk_outline"):
			var w := pxf * Vector3(q.x, 0.0, q.y)
			outline.append(Vector2(w.x, w.z))
		n.block_outside(outline)
	for c in roads.get_children():
		if c is MeshInstance3D:
			n.add_road(inv * (c as Node3D).global_transform, (c as MeshInstance3D).get_aabb())
	for group in ["Props", "Dressing", "Nature", "Signs"]:
		var g := get_node_or_null(group) as Node3D
		if g and g.visible:
			_add_footprints(n, g, inv)
	for lot in lots.get_children():
		var frame := lot.get_node_or_null("Frame") as Node3D
		if frame and frame.visible:
			_add_footprints(n, frame, inv)
	for id: String in _buildings:
		var b: CampusBuilding = _buildings[id]
		var kind := b.kind if b.kind != "" else String(lots.get_node(id).get_meta("kind", "hq"))
		n.add_mask(kind, inv * b.global_transform, b.era, b.level, b.building)
	n.finish()
	return n


## Footprints of what stands under `node`: scattered instances (CampusScatter with
## blocks_walkers), each instanced scene as one box, other meshes one box each.
func _add_footprints(n: CampusNav, node: Node, inv: Transform3D) -> void:
	for c in node.get_children():
		if not c is Node3D or not (c as Node3D).visible or c.get_meta("walk_through", false):
			continue
		if c is CampusScatter:
			var sc := c as CampusScatter
			var mm := sc.multimesh
			if sc.blocks_walkers and mm and mm.mesh:
				var a := mm.mesh.get_aabb()
				var f := sc.walk_footprint
				var foot := AABB(Vector3(a.position.x * f, a.position.y, a.position.z * f),
					Vector3(a.size.x * f, a.size.y, a.size.z * f))
				var base := inv * sc.global_transform
				for t in sc.placed():
					n.add_box(base * t, foot, String(sc.name))
			continue
		if c.scene_file_path != "":
			var a2 := _merged_aabb(c, Transform3D.IDENTITY)
			if a2.size != Vector3.ZERO:
				n.add_box(inv * (c as Node3D).global_transform, a2, String(c.name))
			continue
		if c is MeshInstance3D:
			n.add_box(inv * (c as Node3D).global_transform, (c as MeshInstance3D).get_aabb(), String(c.name))
		_add_footprints(n, c, inv)


func _merged_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	if n is MeshInstance3D or n is MultiMeshInstance3D:
		out = xf * (n as VisualInstance3D).get_aabb()
	for c in n.get_children():
		if c is Node3D and (c as Node3D).visible:
			var a := _merged_aabb(c, xf * (c as Node3D).transform)
			if a.size == Vector3.ZERO:
				continue
			out = a if out.size == Vector3.ZERO else out.merge(a)
	return out


## Where a Cometling may appear near `p`: free ground, two body radii from the others.
func free_point(p: Vector2, who: Node = null) -> Vector2:
	if nav == null:
		return p
	var r := float(who.get("body_radius")) if who else 0.8
	return nav.free_point_near(p, walker_positions(who), r * 2.0 + 0.05)


## Positions (x, z) of the walking Cometlings other than `except`.
func walker_positions(except: Node = null) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for w in $Crowd.get_children():
		if w != except and w is Node3D and (w as Node3D).visible:
			out.append(Vector2((w as Node3D).position.x, (w as Node3D).position.z))
	return out


## Claims a random spot nobody else has claimed for `who` (its previous claim is released);
## {} when every spot is taken.
func claim_spot(who: Node, rng: RandomNumberGenerator) -> Dictionary:
	release_spot(who)
	var open: Array[Dictionary] = []
	for s in all_spots():
		if not _claims.has(s["key"]):
			open.append(s)
	if open.is_empty():
		return {}
	var t: Dictionary = open[rng.randi() % open.size()]
	_claims[t["key"]] = who
	return t


func release_spot(who: Node) -> void:
	for k in _claims.keys():
		if _claims[k] == who:
			_claims.erase(k)


# ------------------------------------------------------------ crowd
## Every spot a Cometling can walk to: {"key", "pos" (campus space), "action", "yaw", "door"}.
func all_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv := global_transform.affine_inverse()
	for m in $Spots.get_children():
		if m is Marker3D:
			out.append({"key": "campus/" + String(m.name), "pos": inv * (m as Marker3D).global_position,
				"door": m.get_meta("door", Vector3.ZERO), "action": String(m.get_meta("action", "idle")),
				"yaw": (m as Marker3D).global_rotation.y})
	for id: String in _buildings:
		var b: CampusBuilding = _buildings[id]
		if b.building:
			continue
		for s in b.spots():
			s["key"] = id + "/" + String(s.get("name", ""))
			s["pos"] = inv * (s["pos"] as Vector3)
			out.append(s)
	return out


## Shows one Cometling of the Crowd (editable instances in the scene) per staff member, in
## their colours with the antenna lit in their profession's colour (TycoonCrew); napping
## members nap, new hires walk in from the Gate marker. More staff than authored Cometlings:
## the last one is duplicated.
func _sync_crowd() -> void:
	var walkers: Array[Node] = []
	walkers.assign($Crowd.get_children().filter(func(w: Node) -> bool: return not w.has_meta(DEV_EXTRA)))
	while walkers.size() < state.staff.size():
		var copy := walkers[walkers.size() - 1].duplicate()
		$Crowd.add_child(copy)
		walkers.append(copy)
	var by_id := {}
	for m in state.staff:
		by_id[String(m.get("id", ""))] = m
	var shown := {}
	var free: Array[Node] = []
	for w in walkers:
		var id := String(w.get("member_id"))
		if by_id.has(id) and not shown.has(id):
			shown[id] = w
		else:
			free.append(w)
	for m in state.staff:
		var id := String(m.get("id", ""))
		if shown.has(id) or free.is_empty():
			continue
		var w: Node = free.pop_front()
		shown[id] = w
		var prof := String(m.get("profession", ""))
		w.call("setup", self, _rng.randi(), int(m.get("variant", 0)), TycoonCrew.look_role(prof))
		w.call("set_member", id, TycoonCrew.profession_color(state, prof))
		(w as Node3D).visible = true
		if _crowd_synced and int(m.get("adapt_weeks", 0)) > 0:
			var gate := get_node_or_null("Gate") as Node3D
			w.call("walk_in", gate.position if gate else Vector3(0, 0, 30))
		else:
			w.call("place_free")
	for w in free:
		release_spot(w)
		w.set("member_id", "")
		w.call("set_napping", false)
		(w as Node3D).visible = false
		w.set_process(false)
	for id: String in shown:
		var w: Node3D = shown[id]
		w.visible = true
		w.set_process(true)
		w.call("set_napping", bool(by_id[id].get("napping", false)))
		# the leader's look + star; a Lenda's own look (no star)
		w.call("set_leader", by_id[id] if TycoonLeader.is_leader(by_id[id]) or TycoonLegends.is_legend(by_id[id]) else {})
	_crowd_synced = true


## The Cometlings walking on the campus right now (the visible members of the Crowd).
func cometlings() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for w in $Crowd.get_children():
		if w is Node3D and (w as Node3D).visible:
			out.append(w)
	return out


# ------------------------------------------------------------ dev menu (src/dev/cw_dev.gd)
## Dev only: `n` more Cometlings walking the campus (copies of the first Crowd walker, no staff
## member behind them, random looks), to test crowds. Returns them.
func dev_spawn_walkers(n: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var crowd := $Crowd
	if crowd.get_child_count() == 0:
		return out
	var src := crowd.get_child(0)
	for i in n:
		var w := src.duplicate() as Node3D
		w.set_meta(DEV_EXTRA, true)
		crowd.add_child(w)
		w.visible = true
		w.set_process(true)
		w.call("setup", self, _rng.randi(), _rng.randi_range(0, 8), ["ground", "pilot", "engineer", "scientist"][_rng.randi() % 4])
		w.set("member_id", "")
		w.call("set_leader", {})
		w.position = Vector3(_rng.randf_range(-20.0, 20.0), w.position.y, _rng.randf_range(-15.0, 15.0))
		w.call("place_free")
		out.append(w)
	return out


## Dev only: the walkers dev_spawn_walkers() added leave.
func dev_clear_walkers() -> int:
	var n := 0
	for w in $Crowd.get_children():
		if w.has_meta(DEV_EXTRA):
			release_spot(w)
			w.queue_free()
			n += 1
	return n


## Dev only: shows / hides the walk grid over the campus (CampusNav.debug_image(): red blocked,
## orange near a wall, blue road, clear lawn) on a flat overlay.
func dev_show_nav(on: bool) -> void:
	var old := get_node_or_null("DevNavOverlay")
	if old:
		old.free()
	if not on or nav == null:
		return
	var tex := ImageTexture.create_from_image(nav.debug_image())
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = tex
	var plane := PlaneMesh.new()
	plane.size = Vector2(nav.nx, nav.nz) * CampusNav.CELL
	var mi := MeshInstance3D.new()
	mi.name = "DevNavOverlay"
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = Vector3(nav.origin.x + plane.size.x * 0.5, 0.2, nav.origin.y + plane.size.y * 0.5)


func dev_nav_shown() -> bool:
	return get_node_or_null("DevNavOverlay") != null


## The staff member a Crowd Cometling stands for ({"name", "profession", ...}), {} if none.
func cometling_member(w: Node) -> Dictionary:
	if state == null or w == null or w.get_parent() != $Crowd:
		return {}
	return TycoonCrew.find(state, String(w.get("member_id")))
