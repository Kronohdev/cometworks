extends Node3D
## Hangar (vehicle assembly) controller, inspired by the KSP VAB.
##
## Snapping, in priority order while a part is held:
##   1. stack nodes / engine slots / radial-decoupler sides: the free node nearest to
##      the mouse (screen space) within SNAP_FRACTION of the viewport height; the
##      current snap is kept until another node is clearly closer (hysteresis)
##   2. surface attach (radial parts only): analytic ray vs. cylinder/box of the part
##      under the mouse, with optional 15° angle and 0.25 m height snapping (C)
## Compatible free nodes are shown as gizmos; symmetry copies are previewed as ghosts.
##
## Construction tools: Q/E rotate the held part (Shift = 5° steps), R resets it,
## Alt+click copies a placed part with its subtree, clicking the part palette while
## holding deletes the held part, N shows every free attach node on the vessel
## (colored by size class), double-click focuses the camera on a part.
##
## Assembly: the stack snap distance is the smaller of (mouse -> target node) and
## (held part's own node -> target node), so big parts snap naturally. Occupied stack
## nodes accept an INSERT (violet gizmo): the held part goes in between and the part
## below moves down with its subtree. With symmetry > 1, an engine dropped on a thrust
## plate fills every free slot. Parts can be dragged straight from the palette.
## Ctrl+Z / Ctrl+Y undo and redo.

const SNAP_FRACTION := 0.05
const SNAP_MIN_PX := 28.0
const HYSTERESIS := 0.75
const ANGLE_STEP := deg_to_rad(15.0)
const HEIGHT_STEP := 0.25
const SYMMETRY_STEPS := [1, 2, 3, 4, 6, 8]
const UNDO_LIMIT := 50
const SAVE_PATH := "user://vessel.tscn"
const EXAMPLES_DIR := "res://scenes/examples/"
const GIZMO_SCENE := preload("res://scenes/hangar/attach_gizmo.tscn")
const GIZMO_IDLE := Color(0.3, 0.9, 1.0, 0.7)
const GIZMO_ACTIVE := Color(1.0, 0.72, 0.2, 0.95)
## Attach-node colors by size class (node display mode, N).
const NODE_COLORS := {"XS": Color(0.75, 0.5, 1.0, 0.8), "S": Color(0.4, 0.95, 0.55, 0.8),
	"M": Color(0.3, 0.85, 1.0, 0.8), "L": Color(1.0, 0.72, 0.25, 0.85), "slot": Color(1.0, 0.45, 0.7, 0.8),
	"side": Color(0.95, 0.95, 1.0, 0.8)}
const ROTATE_STEP := deg_to_rad(15.0)
const ROTATE_FINE := deg_to_rad(5.0)
const HIGHLIGHT := preload("res://scenes/hangar/part_highlight.tres")
const GHOST_VALID := preload("res://scenes/hangar/ghost_valid.tres")
const GHOST_INVALID := preload("res://scenes/hangar/ghost_invalid.tres")
const GHOST_INSERT := preload("res://scenes/hangar/ghost_insert.tres")
const GIZMO_INSERT := Color(0.75, 0.5, 1.0, 0.8)
## Insert candidates must be this much closer than free nodes to win.
const INSERT_PENALTY := 1.25
const DRAG_PLACE_PX := 10.0
const JOINT_FLASH := preload("res://scenes/hangar/joint_flash.tscn")
## Magnetic snapping: how fast the held part glides onto its snap target (1/s).
const SNAP_GLIDE := 22.0
## How fast the vessel rises/settles so nothing goes through the floor (1/s).
const LIFT_SPEED := 10.0

## Top of the launch pad in the hangar environment; the vessel stands on it.
@export var pad_top_y := 0.62

var held: PartInstance = null
var symmetry := 1
var angle_snap := true
var show_nodes := false
## Where the held part floats when nothing snaps: on a camera-facing plane through the
## focus point, centered under the mouse.
func _float_transform(r: Dictionary) -> Transform3D:
	var plane := Plane(-cam.camera.global_transform.basis.z, cam.target_focus)
	var hit: Variant = plane.intersects_ray(r["from"], r["dir"])
	var p: Vector3 = hit if hit != null else cam.target_focus
	return Transform3D(Basis(), p - held.aabb.get_center()) * _held_rotation(false)


func _tint_held() -> void:
	var mat: Material = GHOST_INVALID
	if not _snap.is_empty():
		mat = GHOST_INSERT if _snap.get("insert", false) else GHOST_VALID
	elif vessel.root == null:
		mat = GHOST_VALID  # first part becomes the root anywhere
	for p in held.subtree():
		p.set_highlight(mat)


## Rotation of the held part around its attach axis (radians).
var held_angle := 0.0
var _hovered: PartInstance = null
var _snap: Dictionary = {}
var _dirty := true
var _frame_pending := false
var _undo: Array[PackedScene] = []
var _redo: Array[PackedScene] = []
## Set when a part was picked from the palette with the button still down:
## releasing it over the 3D view places it (drag and drop).
var _drag_from_palette := false
var _drag_start := Vector2.ZERO
## Insert preview: the part below the insert point is moved down while previewing.
var _preview_child: PartInstance = null
## Vessel height from the last refresh (standing on the pad) and the temporary extra
## lift applied while a held part or an insert preview would reach below the pad.
var _rest_y := 0.0
var _lift := 0.0
var _held_visual := Transform3D.IDENTITY
var _held_visual_valid := false
var _preview_child_xf := Transform3D.IDENTITY
var _gizmos: Array[Node3D] = []
var _ghosts: Array[Node3D] = []
var _ghost_id := ""

@onready var vessel: Vessel = $Vessel
@onready var cam: HangarCamera = $CameraRig
@onready var markers: HangarMarkers = $Markers
@onready var ui: HangarUI = $UI
@onready var gizmo_root: Node3D = $Gizmos
@onready var ghost_root: Node3D = $SymmetryGhosts
@onready var joint_decor: JointDecor = $Vessel/JointDecor


func _ready() -> void:
	var lang := OS.get_locale_language()
	TranslationServer.set_locale("pt" if lang == "pt" else "en")
	vessel.changed.connect(func() -> void: _dirty = true)
	ui.part_chosen.connect(_on_part_chosen)
	ui.new_pressed.connect(func() -> void:
		_push_undo()
		_drop_held()
		vessel.clear())
	ui.save_pressed.connect(save_vessel)
	ui.load_pressed.connect(load_vessel)
	ui.undo_pressed.connect(undo)
	ui.redo_pressed.connect(redo)
	ui.language_toggled.connect(_toggle_language)
	ui.symmetry_pressed.connect(_cycle_symmetry)
	ui.symmetry_chosen.connect(func(n: int) -> void:
		symmetry = n
		ui.set_symmetry(n))
	ui.angle_snap_pressed.connect(_toggle_angle_snap)
	ui.example_chosen.connect(load_example)
	ui.nodes_toggled.connect(_set_show_nodes)
	ui.palette_clicked.connect(func() -> void:
		if held:
			_drop_held()
			ui.flash(tr("UI_DELETED"), 1.2))
	ui.height_changed.connect(func(y: float) -> void: cam.set_height(y))
	cam.view_changed.connect(func() -> void: ui.set_height(cam.target_focus.y))
	ui.markers_toggled.connect(func(a: bool, b: bool, c: bool) -> void:
		markers.show_com = a
		markers.show_cot = b
		markers.show_col = c
		_dirty = true)
	ui.set_examples(list_examples())
	ui.set_symmetry(symmetry)
	ui.set_angle_snap(angle_snap)
	GraphicsQuality.apply(self)
	# crew panel (authored in the hangar scene under the Crew tab) follows this vessel
	var crew_panel := ui.get_node_or_null("%CrewPanel")
	if crew_panel and crew_panel.has_method("set_vessel"):
		crew_panel.set_vessel(vessel)
	ui.launch_pressed.connect(launch)
	if FlightSession.has_vessel():
		vessel.load_scene(FlightSession.vessel_scene)
		_frame_pending = true


# ------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if held:
		_set_hovered(null)
		_update_held(delta)
		_update_lift(delta)
	else:
		_settle_lift(delta)
		_hide_ghosts()
		_update_hover()
		if show_nodes:
			_show_all_nodes()
		else:
			_hide_gizmos()
	if _dirty:
		_dirty = false
		_refresh()


func _refresh() -> void:
	if vessel.root:
		# keep the vessel standing on the launch pad as parts are added below it
		vessel.position.y += pad_top_y - vessel.bounds().position.y
		_rest_y = vessel.position.y
		_lift = 0.0
	joint_decor.rebuild()
	var a := vessel.analyze()
	var m := vessel.markers()
	var b := vessel.bounds()
	if _frame_pending:
		_frame_pending = false
		cam.frame(b)
	markers.update_from(m, maxf(b.size.y, 2.0))
	ui.show_analysis(a, {"parts": vessel.all_parts().size(), "cost": vessel.cost_musd(), "stable": vessel.stability(m)})


# ------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not _drag_from_palette or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	_drag_from_palette = false
	var over_ui := get_viewport().gui_get_hovered_control() != null
	if held and not over_ui and mb.position.distance_to(_drag_start) > DRAG_PLACE_PX:
		_place_held()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if cam.handle_input(event):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if held:
			_place_held()
		elif mb.double_click:
			_focus_at(mb.position)
		else:
			_pick_at(mb.position, mb.alt_pressed)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and (k.keycode == KEY_Y or (k.keycode == KEY_Z and k.shift_pressed)):
			redo()
			return
		if k.ctrl_pressed and k.keycode == KEY_Z:
			undo()
			return
		match k.keycode:
			KEY_Q, KEY_E:
				if held:
					var step := ROTATE_FINE if k.shift_pressed else ROTATE_STEP
					held_angle = wrapf(held_angle + (step if k.keycode == KEY_E else -step), -PI, PI)
			KEY_R:
				held_angle = 0.0
			KEY_N:
				_set_show_nodes(not show_nodes)
			KEY_X:
				_cycle_symmetry()
			KEY_C:
				_toggle_angle_snap()
			KEY_ESCAPE, KEY_DELETE, KEY_BACKSPACE:
				_drop_held()
			KEY_F:
				cam.frame(vessel.bounds())
			KEY_F3:
				ui.flash(tr("UI_QUALITY") % tr("QUALITY_" + GraphicsQuality.cycle(self)), 2.0)


func _cycle_symmetry() -> void:
	var i := SYMMETRY_STEPS.find(symmetry)
	symmetry = SYMMETRY_STEPS[(i + 1) % SYMMETRY_STEPS.size()]
	ui.set_symmetry(symmetry)


func _set_show_nodes(on: bool) -> void:
	show_nodes = on
	ui.set_show_nodes(on)


func _toggle_angle_snap() -> void:
	angle_snap = not angle_snap
	ui.set_angle_snap(angle_snap)


func _toggle_language() -> void:
	TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("pt") else "pt")
	ui.refresh_texts()
	_dirty = true


# ------------------------------------------------------------ picking (analytic, no physics)
func _mouse_ray() -> Dictionary:
	var mp := get_viewport().get_mouse_position()
	var c := cam.camera
	return {"from": c.project_ray_origin(mp), "dir": c.project_ray_normal(mp), "mouse": mp}


## Nearest pickable vessel part under the ray: {"part", "point", "normal"} or {}.
func _pick_ray(from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for p in vessel.all_parts():
		if not p.pickable:
			continue
		var h := p.ray_hit(from, dir)
		if not h.is_empty() and float(h["t"]) < best_t:
			best_t = h["t"]
			best = {"part": p, "point": h["point"], "normal": h["normal"]}
	return best


# ------------------------------------------------------------ holding / snapping
func _on_part_chosen(id: String) -> void:
	_drop_held()
	held = PartInstance.create(id)
	held.set_pickable(false)
	held.set_ghost(true)
	add_child(held)
	held_angle = 0.0
	_snap = {}
	_held_visual_valid = false
	_drag_from_palette = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_drag_start = get_viewport().get_mouse_position()
	_update_held()


func _drop_held() -> void:
	_restore_insert_preview()
	_held_visual_valid = false
	if held:
		held.queue_free()
		held = null
		_snap = {}


func _snap_threshold() -> float:
	return maxf(SNAP_MIN_PX, get_viewport().get_visible_rect().size.y * SNAP_FRACTION)


func _update_held(delta := 0.0) -> void:
	_restore_insert_preview()  # candidates must see the real stack
	var r := _mouse_ray()
	_snap = _find_snap(r)
	_tint_held()
	var target: Transform3D
	if not _snap.is_empty():
		_snap["xform"] = (_snap["xform"] as Transform3D) * _held_rotation(_snap["pnode"] == "surface")
		var t: PartInstance = _snap["target"]
		target = t.global_transform * (_snap["xform"] as Transform3D)
	else:
		# free float on a camera-facing plane through the focus point, never below the floor
		target = _float_transform(r)
		var low := _world_bounds(held).position.y - held.global_position.y + target.origin.y
		if low < 0.05:
			target.origin.y += 0.05 - low
	# magnetic glide toward the target (snaps feel attracted instead of teleporting)
	if not _held_visual_valid or delta <= 0.0:
		_held_visual = target
		_held_visual_valid = true
	else:
		_held_visual = _held_visual.interpolate_with(target, 1.0 - exp(-SNAP_GLIDE * delta))
	held.global_transform = _held_visual
	_update_gizmos()
	_update_ghosts()
	if _snap.get("insert", false):
		_apply_insert_preview()


## World AABB of a part subtree (its own model bounds, transformed).
func _world_bounds(p: PartInstance) -> AABB:
	var b := p.global_transform * p.aabb
	for c in p.subtree():
		b = b.merge(c.global_transform * c.aabb)
	return b


## While holding: lifts the whole vessel (smoothly) when the held part or an insert
## preview would reach below the pad, and lets it settle back otherwise.
func _update_lift(delta: float) -> void:
	if vessel.root == null:
		return
	var low := vessel.bounds().position.y
	if not _snap.is_empty():
		low = minf(low, _world_bounds(held).position.y)
	var desired := maxf(0.0, _lift + (pad_top_y - low))
	_lift = lerpf(_lift, desired, 1.0 - exp(-LIFT_SPEED * delta))
	vessel.position.y = _rest_y + _lift


func _settle_lift(delta: float) -> void:
	if is_zero_approx(_lift) or vessel.root == null:
		return
	_lift = lerpf(_lift, 0.0, 1.0 - exp(-LIFT_SPEED * delta))
	if _lift < 0.001:
		_lift = 0.0
	vessel.position.y = _rest_y + _lift


## Joint feedback after placing: a ring of light at the joint and a small "clunk"
## squash on the placed part's model.
func _joint_feedback(p: PartInstance, pnode: String) -> void:
	var t := p.part_parent()
	if t == null:
		return
	var point: Vector3
	var axis := Vector3.UP
	var radius := maxf(p.radius(), 0.3)
	if pnode == "surface":
		var c := p.aabb.get_center()
		point = p.global_transform * Vector3(p.aabb.position.x, c.y, c.z)
		axis = p.global_transform.basis.x.normalized()
		radius = maxf(maxf(p.aabb.size.y, p.aabb.size.z) * 0.5, 0.3)
	else:
		point = t.global_transform * t.node_local(pnode)
		radius = maxf(JointDecor.node_radius(t, pnode) if pnode in ["top", "bottom"] else p.radius(), 0.3)
	var f: Node3D = JOINT_FLASH.instantiate()
	add_child(f)
	var up := axis
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	f.global_transform = Transform3D(Basis(side, up, side.cross(up)).scaled(Vector3.ONE * radius * 1.08), point)
	get_tree().create_timer(0.5).timeout.connect(f.queue_free)
	p.pulse()


## Opens the stack while previewing an insert: the child on the insert node is shown
## where it will end up (below the held part), exactly as Vessel.insert will place it.
func _apply_insert_preview() -> void:
	var t: PartInstance = _snap["target"]
	var tnode: String = _snap["pnode"]
	var other := Vessel.insert_node_for(t, tnode, held, _snap["onode"])
	for c in t.part_children():
		if c.parent_node_name == tnode and other != "":
			_preview_child = c
			_preview_child_xf = c.transform
			var xf: Transform3D = _snap["xform"]
			var basis_rel := xf.basis.inverse() * c.transform.basis
			var origin := held.node_local(other) - basis_rel * c.node_local(c.own_node_name)
			c.global_transform = held.global_transform * Transform3D(basis_rel, origin)
			return


func _restore_insert_preview() -> void:
	if _preview_child and is_instance_valid(_preview_child):
		_preview_child.transform = _preview_child_xf
	_preview_child = null


## Rotation of the held part around its attach axis: the part's Y axis for stack
## nodes, the outward axis through the attach point for surface attachment.
func _held_rotation(surface: bool) -> Transform3D:
	if is_zero_approx(held_angle):
		return Transform3D.IDENTITY
	if not surface:
		return Transform3D(Basis(Vector3.UP, held_angle), Vector3.ZERO)
	var c := held.aabb.get_center()
	var pivot := Vector3(held.aabb.position.x, c.y, c.z)
	return Transform3D(Basis(), pivot) * Transform3D(Basis(Vector3.RIGHT, held_angle), Vector3.ZERO) \
		* Transform3D(Basis(), -pivot)


## Stack candidates (free nodes and insert points). Distance d is the smaller of the
## mouse distance and the held part's own node distance (with the part floating at the mouse).
func _stack_candidates(mouse: Vector2) -> Array:
	var out: Array = []
	var fx := _float_transform(_mouse_ray())
	for t in vessel.all_parts():
		var free := t.free_nodes()
		for tn in t.node_names():
			var insert := not free.has(tn)
			var on := Vessel.own_node_for(t, tn, held)
			if on == "" or (insert and Vessel.insert_node_for(t, tn, held, on) == ""):
				continue
			var wp := t.global_transform * t.node_local(tn)
			if cam.camera.is_position_behind(wp):
				continue
			var sp := cam.camera.unproject_position(wp)
			var own_w := fx * held.node_local(on) if on != "sidechild" else fx * held.aabb.get_center()
			var d := sp.distance_to(mouse)
			if not cam.camera.is_position_behind(own_w):
				d = minf(d, sp.distance_to(cam.camera.unproject_position(own_w)))
			out.append({"target": t, "pnode": tn, "onode": on, "world": wp, "insert": insert,
				"d": d * (INSERT_PENALTY if insert else 1.0)})
	return out


func _find_snap(r: Dictionary) -> Dictionary:
	if vessel.root == null:
		return {}
	var thr := _snap_threshold()
	var best := {}
	var best_d := INF
	var current := {}
	for c in _stack_candidates(r["mouse"]):
		if c["d"] < best_d:
			best_d = c["d"]
			best = c
		if not _snap.is_empty() and _snap.get("target") == c["target"] and _snap.get("pnode") == c["pnode"]:
			current = c
	# hysteresis: keep the current node while it is still reasonably close
	if not current.is_empty() and current["d"] < thr * 1.6 and best_d > current["d"] * HYSTERESIS:
		best = current
		best_d = current["d"]
	var stack_ok := best_d <= thr
	if held.can_radial_attach():
		var hit := _pick_ray(r["from"], r["dir"])
		if not hit.is_empty() and not (stack_ok and best_d <= thr * 0.6):
			var t: PartInstance = hit["part"]
			var s := Vessel.surface_from_hit(t, hit["point"], hit["normal"],
				ANGLE_STEP if angle_snap else 0.0, HEIGHT_STEP if angle_snap else 0.0)
			return {"target": t, "pnode": "surface", "onode": "surface",
				"xform": Vessel.local_for_surface(t, s["point"], s["out"], held)}
	if not stack_ok:
		return {}
	best["xform"] = Vessel.local_for_node(best["target"], best["pnode"], held, best["onode"])
	return best


# ------------------------------------------------------------ gizmos and symmetry ghosts
func _hide_gizmos() -> void:
	for g in _gizmos:
		g.visible = false


func _ensure_gizmos(n: int) -> void:
	while _gizmos.size() < n:
		var g: Node3D = GIZMO_SCENE.instantiate()
		gizmo_root.add_child(g)
		var sphere := g.get_node("Sphere") as MeshInstance3D
		sphere.set_surface_override_material(0, sphere.get_surface_override_material(0).duplicate())
		_gizmos.append(g)


## Shows gizmos at the given points: [{world, color, scale}].
func _draw_gizmos(items: Array) -> void:
	_ensure_gizmos(items.size())
	var base := clampf(cam.distance * 0.018, 0.25, 3.0)
	for i in _gizmos.size():
		var g := _gizmos[i]
		if i >= items.size():
			g.visible = false
			continue
		var it: Dictionary = items[i]
		g.visible = true
		g.global_position = it["world"]
		g.scale = Vector3.ONE * base * float(it["scale"])
		var mat := (g.get_node("Sphere") as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		mat.albedo_color = it["color"]
		if not g.global_position.is_equal_approx(cam.camera.global_position):
			g.look_at(cam.camera.global_position, Vector3.UP, true)


func _update_gizmos() -> void:
	var items: Array = []
	if vessel.root:
		for c in _stack_candidates(_mouse_ray()["mouse"]):
			var active: bool = not _snap.is_empty() and _snap.get("target") == c["target"] and _snap.get("pnode") == c["pnode"]
			var col: Color = GIZMO_ACTIVE if active else (GIZMO_INSERT if c["insert"] else GIZMO_IDLE)
			items.append({"world": c["world"], "color": col, "scale": 1.5 if active else (0.8 if c["insert"] else 1.0)})
	_draw_gizmos(items)


## Node display mode (N): every free attach node on the vessel, sized and colored by class.
func _show_all_nodes() -> void:
	var items: Array = []
	for p in vessel.all_parts():
		for n in p.free_nodes():
			var cls := p.node_size(n)
			var d: float = PartDB.size_classes.get(cls, 1.0)
			items.append({"world": p.global_transform * p.node_local(n), "color": NODE_COLORS.get(cls, GIZMO_IDLE),
				"scale": clampf(0.6 + d * 0.3, 0.6, 1.8)})
	_draw_gizmos(items)


func _hide_ghosts() -> void:
	for g in _ghosts:
		g.visible = false


## Extra placements for the current snap: symmetry copies around the target axis for
## surface attach, or the other free slots of a thrust plate when symmetry > 1.
func _extra_placements() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if _snap.is_empty() or symmetry <= 1:
		return out
	var t: PartInstance = _snap["target"]
	var pnode: String = _snap["pnode"]
	if pnode == "surface":
		for i in range(1, symmetry):
			out.append(t.global_transform * Transform3D(Basis(Vector3.UP, TAU * i / symmetry), Vector3.ZERO)
				* (_snap["xform"] as Transform3D))
	elif pnode.begins_with("slot:"):
		for n in _free_slots_except(t, pnode):
			out.append(t.global_transform * Vessel.local_for_node(t, n, held, "top") * _held_rotation(false))
	return out


func _free_slots_except(t: PartInstance, pnode: String) -> Array[String]:
	var out: Array[String] = []
	for n in t.free_nodes():
		if n.begins_with("slot:") and n != pnode:
			out.append(n)
	return out


func _update_ghosts() -> void:
	var extra := _extra_placements()
	var n := extra.size() + 1
	if _ghost_id != held.part_id:
		for g in _ghosts:
			g.queue_free()
		_ghosts.clear()
		_ghost_id = held.part_id
	while _ghosts.size() < n - 1:
		var g := Node3D.new()
		var scene := PartDB.model_scene(held.part_id)
		if scene:
			g.add_child(scene.instantiate())
		PartInstance.apply_voxel_material(g)
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).transparency = 0.6
		ghost_root.add_child(g)
		_ghosts.append(g)
	for i in _ghosts.size():
		var g := _ghosts[i]
		g.visible = i < n - 1
		if g.visible:
			g.global_transform = extra[i]


# ------------------------------------------------------------ placing / picking up
func _place_held() -> void:
	_restore_insert_preview()
	if vessel.root == null:
		_push_undo()
		var p := held
		held = null
		vessel.set_root(p)
		for q in p.subtree():
			q.set_highlight(null)
		_frame_pending = true
		return
	if _snap.is_empty():
		ui.flash(tr("UI_NO_SNAP"))
		return
	_push_undo()
	var p := held
	held = null
	for q in p.subtree():
		q.set_highlight(null)
	var t: PartInstance = _snap["target"]
	var pnode: String = _snap["pnode"]
	_held_visual_valid = false
	if _snap.get("insert", false):
		vessel.insert(t, pnode, p, _snap["xform"], _snap["onode"])
		ui.flash(tr("UI_INSERTED"), 1.5)
	elif pnode.begins_with("slot:") and symmetry > 1:
		# fill every free slot of the thrust plate with copies
		var others := _free_slots_except(t, pnode)
		vessel.attach(t, p, _snap["xform"], pnode, _snap["onode"])
		for n in others:
			var c := Vessel.clone_tree(p)
			vessel.attach(t, c, Vessel.local_for_node(t, n, c, "top") * _held_rotation(false), n, "top")
	else:
		vessel.attach(t, p, _snap["xform"], pnode, _snap["onode"], symmetry)
	for q in ([p] if p.sym_group.is_empty() else p.sym_group):
		if is_instance_valid(q):
			_joint_feedback(q, pnode)
	_snap = {}


func _pick_at(pos: Vector2, copy := false) -> void:
	var c := cam.camera
	var hit := _pick_ray(c.project_ray_origin(pos), c.project_ray_normal(pos))
	if hit.is_empty():
		return
	var p: PartInstance = hit["part"]
	_set_hovered(null)
	var gx := p.global_transform
	if copy:
		# Alt+click: hold a copy of the part and everything attached to it
		var dup := Vessel.clone_tree(p)
		add_child(dup)
		dup.global_transform = gx
		p = dup
		ui.flash(tr("UI_COPIED") % PartDB.part_name(p.part_id), 1.5)
	else:
		_push_undo()
		vessel.detach(p)
		add_child(p)
		p.global_transform = gx
		ui.flash(PartDB.part_name(p.part_id), 1.5)
	p.set_pickable(false)
	p.set_ghost(true)
	held = p
	held_angle = 0.0
	_snap = {}
	_held_visual = p.global_transform  # glide from where the part was
	_held_visual_valid = true


func _focus_at(pos: Vector2) -> void:
	var c := cam.camera
	var hit := _pick_ray(c.project_ray_origin(pos), c.project_ray_normal(pos))
	if hit.is_empty():
		cam.frame(vessel.bounds())
		return
	var p: PartInstance = hit["part"]
	cam.focus_on(p.center_global(), maxf(p.aabb.size.length() * 2.5, 8.0))


func _update_hover() -> void:
	var mp := get_viewport().get_mouse_position()
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var hit := {} if over_ui else _pick_ray(cam.camera.project_ray_origin(mp), cam.camera.project_ray_normal(mp))
	var part: PartInstance = null if hit.is_empty() else hit["part"]
	_set_hovered(part)
	if _hovered:
		ui.show_hover(_hovered.part_id, mp, _hovered.free_nodes().size())


func _set_hovered(p: PartInstance) -> void:
	if p == _hovered:
		return
	if _hovered and is_instance_valid(_hovered):
		_hovered.set_highlight(null)
	_hovered = p
	if _hovered:
		_hovered.set_highlight(HIGHLIGHT)
	else:
		ui.hide_hover()


# ------------------------------------------------------------ undo
func _push_undo() -> void:
	_undo.append(vessel.snapshot())  # null snapshot = empty vessel
	_redo.clear()
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func _restore(ps: PackedScene) -> void:
	if ps:
		vessel.load_scene(ps)
	else:
		vessel.clear()


func undo() -> void:
	if _undo.is_empty():
		return
	_drop_held()
	_redo.append(vessel.snapshot())
	_restore(_undo.pop_back())
	ui.flash(tr("UI_UNDONE"), 1.5)


func redo() -> void:
	if _redo.is_empty():
		return
	_drop_held()
	_undo.append(vessel.snapshot())
	_restore(_redo.pop_back())
	ui.flash(tr("UI_REDONE"), 1.5)


# ------------------------------------------------------------ launch (flight test)
func launch() -> void:
	if vessel.root == null:
		return
	_drop_held()
	FlightSession.set_vessel(vessel.to_packed_scene(), "", vessel.analyze()["ascent_dv"])
	get_tree().change_scene_to_file(FlightSession.FLIGHT_SCENE)


# ------------------------------------------------------------ save / load / examples
func save_vessel() -> void:
	var ps := vessel.to_packed_scene()
	if ps and ResourceSaver.save(ps, SAVE_PATH) == OK:
		ui.flash(tr("UI_SAVED"))


func load_vessel() -> void:
	if not ResourceLoader.exists(SAVE_PATH):
		return
	_push_undo()
	_drop_held()
	vessel.load_scene(ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE))
	_frame_pending = true
	ui.flash(tr("UI_LOADED"))


func list_examples() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(EXAMPLES_DIR):
		var fname := f.trim_suffix(".remap")
		if fname.ends_with(".tscn"):
			out.append(fname.get_basename())
	return out


func load_example(id: String) -> void:
	_push_undo()
	_drop_held()
	vessel.load_scene(load(EXAMPLES_DIR + id + ".tscn"))
	_frame_pending = true
	ui.flash(tr("UI_EXAMPLE_LOADED") % ExampleVessels.display_name(id))
