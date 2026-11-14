extends SceneTree
## Visual smoke test: opens the hangar, loads the Garça example, saves screenshots
## (empty hangar, PT/EN UI, snapping preview with symmetry ghosts, placed fins and
## a wide shot of the assembly building) and checks undo.
## Run (windowed): godot --path . --script res://tests/screenshot_hangar.gd -- <out_dir>

var out_dir := "user://"
var hangar: Node


func _initialize() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out_dir = OS.get_cmdline_user_args()[0]
	hangar = (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(12)
	_shot("hangar_empty")

	hangar.load_example("garca")
	await _settle()
	_shot("hangar_pt")
	hangar._toggle_language()
	await _frames(6)
	_shot("hangar_en")

	# interactive snapping: hold a fin over the lowest core tank with 4x symmetry
	var v: Vessel = hangar.vessel
	var core_bottom := _lowest(v, "tank_hydrolox_l8")
	hangar.symmetry = 4
	hangar.ui.set_symmetry(4)
	hangar._on_part_chosen("fin_basic")
	var axis := core_bottom.global_transform * Vector3(0, 2.0, 0)
	var to_cam: Vector3 = hangar.cam.camera.global_position - axis
	var aim := axis + Vector3(to_cam.x, 0, to_cam.z).normalized() * core_bottom.radius() * 0.6
	var mouse: Vector2 = hangar.cam.camera.unproject_position(aim)
	for i in 12:
		Input.warp_mouse(mouse)
		await process_frame
	var did_snap: bool = not hangar._snap.is_empty()
	_shot("hangar_snap_preview")
	hangar._place_held()
	await _frames(6)
	var fins := _count(v, "fin_basic")
	print("interactive fin placement: snapped=%s fins=%d" % [did_snap, fins])
	_shot("hangar_fins")

	hangar.undo()
	await _frames(4)
	print("undo: fins %d -> %d" % [fins, _count(v, "fin_basic")])

	# insert with the mouse: hold a tank over the seam between the two upper core tanks
	var tanks: Array[PartInstance] = []
	for p in v.all_parts():
		if p.part_id == "tank_hydrolox_l8":
			tanks.append(p)
	tanks.sort_custom(func(a: PartInstance, b: PartInstance) -> bool: return a.global_position.y > b.global_position.y)
	var seam: Vector3 = tanks[0].global_transform * tanks[0].node_local("bottom")
	var before_parts := v.all_parts().size()
	hangar.symmetry = 1
	hangar.ui.set_symmetry(1)
	hangar._on_part_chosen("tank_hydrolox_l2")
	for i in 12:
		Input.warp_mouse(hangar.cam.camera.unproject_position(seam))
		await process_frame
	var is_insert: bool = hangar._snap.get("insert", false)
	_shot("hangar_insert_preview")
	hangar._place_held()
	await _frames(6)
	print("insert with mouse: insert=%s parts %d -> %d" % [is_insert, before_parts, v.all_parts().size()])
	_shot("hangar_inserted")
	hangar.undo()
	await _frames(4)

	# lean HUD: collapsed panels, help overlay, hidden HUD
	hangar.ui.set_parts_collapsed(true)
	hangar.ui.set_stages_collapsed(true)
	await _frames(4)
	_shot("hud_collapsed")
	hangar.ui.set_parts_collapsed(false)
	hangar.ui.set_stages_collapsed(false)
	hangar.ui._btn_help.button_pressed = true
	await _frames(4)
	_shot("hud_help")
	hangar.ui._btn_help.button_pressed = false
	hangar.ui.set_hud_visible(false)
	await _frames(4)
	_shot("hud_hidden")
	hangar.ui.set_hud_visible(true)

	# node display mode (N) and hover highlight
	hangar._set_show_nodes(true)
	core_bottom = _lowest(v, "tank_hydrolox_l8")  # undo reloaded the vessel, so look it up again
	var tank_mouse: Vector2 = hangar.cam.camera.unproject_position(core_bottom.center_global())
	for i in 6:
		Input.warp_mouse(tank_mouse)
		await process_frame
	_shot("hangar_nodes_hover")
	hangar._set_show_nodes(false)

	# wide shot of the building
	hangar.cam.snap_to(Vector3(0, 32, 0), deg_to_rad(28), deg_to_rad(18), 105.0)
	await _frames(8)
	_shot("hangar_wide")
	hangar.queue_free()
	var kit: Node = (load("res://scenes/ui/ui_kit.tscn") as PackedScene).instantiate()
	get_root().add_child(kit)
	await _frames(6)
	_shot("ui_kit")
	print("SHOTS DONE")
	quit()


func _lowest(v: Vessel, id: String) -> PartInstance:
	var best: PartInstance = null
	for p in v.all_parts():
		if p.part_id == id and (best == null or p.global_position.y < best.global_position.y):
			best = p
	return best


func _count(v: Vessel, id: String) -> int:
	var n := 0
	for p in v.all_parts():
		if p.part_id == id:
			n += 1
	return n


## Lets the camera finish easing toward its target view.
func _settle() -> void:
	await _frames(2)
	var c: HangarCamera = hangar.cam
	c.snap_to(c.target_focus, c.target_yaw, c.target_pitch, c.target_distance)
	await _frames(4)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	get_root().get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])
