extends SceneTree
## Checks the campus building scenes (tools/build_campus_buildings.py): the contract used by
## src/tycoon/campus.gd (Era1..5 / Level1..3, Scaffold, Spots with action / door / level),
## and the cutaway of src/tycoon/campus_building.gd (roofs fold and the walls facing a
## close camera drop; far away everything stands).
## Run: godot --headless --path . --script res://tests/test_campus_buildings.gd

const KINDS := ["hq", "workshop", "pad", "lab", "control", "antenna", "training", "factory"]
const ACTIONS := ["idle", "sit", "look_up", "work_hammer", "work_scan", "carry", "clipboard", "talk", "dance"]

var _fails := 0


func _initialize() -> void:
	await process_frame
	for kind: String in KINDS:
		var ps := load("res://scenes/tycoon/buildings/%s.tscn" % kind) as PackedScene
		_check(ps != null, "%s scene loads" % kind)
		if ps == null:
			continue
		var b := ps.instantiate() as CampusBuilding
		get_root().add_child(b)
		await process_frame
		_check(b.kind == kind, "%s kind set" % kind)
		var ok := true
		for e in range(1, 6):
			for l in range(1, 4):
				ok = ok and b.get_node_or_null("Era%d/Level%d" % [e, l]) != null
		_check(ok, "%s has Era1..5 / Level1..3" % kind)
		_check(b.get_node_or_null("Scaffold") != null, "%s has a scaffold" % kind)
		var spots_ok := true
		var n := 0
		for m in b.get_node("Spots").get_children():
			n += 1
			var door: Vector3 = m.get_meta("door", Vector3.ZERO)
			spots_ok = spots_ok and String(m.get_meta("action", "")) in ACTIONS and absf(door.z - 9.0) < 0.01
			if m.has_meta("via"):
				var via: Vector3 = m.get_meta("via")
				spots_ok = spots_ok and absf(via.x - door.x) < 0.01 and via.z < door.z
		_check(spots_ok and n > 0, "%s spots: %d with actions, road-side doors, vias inside" % [kind, n])
		b.set_look(5, 1)
		_check(b.spots().size() < n or kind == "pad", "%s level 1 hides spots of later levels" % kind)
		b.set_look(3, 3)
		_check(b.spots().size() == n, "%s level 3 shows every spot" % kind)
		b.queue_free()
	await _cutaway()
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails else 0)


func _cutaway() -> void:
	var b := (load("res://scenes/tycoon/buildings/hq.tscn") as PackedScene).instantiate() as CampusBuilding
	get_root().add_child(b)
	b.set_look(3, 3)
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.current = true
	await process_frame
	# camera close, in front (+z) and to the right (+x) of the building
	cam.global_position = Vector3(20, 25, 25)
	b.snap_cutaway()
	var roof := b.get_node("Era3/Level1/Model/CutRoof") as Node3D
	var front := b.get_node("Era3/Level1/Model/CutPZ") as Node3D
	var back := b.get_node("Era3/Level1/Model/CutNZ") as Node3D
	var upper := b.get_node("Era3/Level3/Model/CutUpper") as Node3D
	_check(not roof.visible and not front.visible and not upper.visible, "close camera: roof, front wall, upper storeys fold")
	_check(back.visible and is_equal_approx(back.scale.y, 1.0), "close camera: the back wall stands")
	cam.global_position = Vector3(150, 150, 150)
	b.snap_cutaway()
	_check(roof.visible and front.visible and upper.visible and is_equal_approx(front.scale.y, 1.0),
		"far camera: everything stands")
	b.cutaway_enabled = false
	cam.global_position = Vector3(20, 25, 25)
	b.snap_cutaway()
	_check(roof.visible, "cutaway off: the roof stays")
	b.queue_free()
	cam.queue_free()
	await process_frame


func _check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + what)
	if not cond:
		_fails += 1
