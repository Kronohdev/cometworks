extends SceneTree
## Checks that the Cometlings of every main-menu shot and every story cutscene shot
## (scenes/cutscenes/shots) keep their distance: samples each shot's cue animation and fails when two Cometlings on the same ground come closer than
## their body widths (one walking through another, or two standing inside each other).
## Run: godot --headless --path . --script res://tests/test_menu_spacing.gd

const MENU := "res://scenes/menu/main_menu.tscn"
const CUTSCENE_SHOTS := "res://scenes/cutscenes/shots/"
const STEP := 0.2
## Body footprint of a Cometling at scale 1 (radius in metres: ears and arms of creature.tscn span about 0.85 m).
const RADIUS := 0.45
const GAP := 0.12

var failures := 0


func _initialize() -> void:
	await process_frame
	var probe := (load(MENU) as PackedScene).instantiate()
	var shots := (probe.get_node("Background") as MenuDirector).shots.duplicate()
	probe.free()
	for f in DirAccess.get_files_at(CUTSCENE_SHOTS):
		if f.ends_with(".tscn"):
			shots.append(CUTSCENE_SHOTS + f)
	for path: String in shots:
		_check(path)
	print("MENU SPACING ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures else 0)


func _check(path: String) -> void:
	var shot := (load(path) as PackedScene).instantiate() as MenuShot
	root.add_child(shot)
	var crowd: Array[Node3D] = []
	for n in shot.find_children("*", "Node3D", true, false):
		if n.get_script() == preload("res://src/npc/creature.gd"):
			crowd.append(n)
	var ap := shot.animation_player
	var has_anim := ap != null and ap.has_animation(shot.animation)
	var worst := {}
	var t := 0.0
	while t <= shot.duration + 0.001:
		if has_anim:
			ap.play(shot.animation)
			ap.seek(t, true)
		for i in crowd.size():
			for j in range(i + 1, crowd.size()):
				var a := crowd[i]
				var b := crowd[j]
				if not a.is_visible_in_tree() or not b.is_visible_in_tree():
					continue
				var pa := a.global_position
				var pb := b.global_position
				if absf(pa.y - pb.y) > 0.8:
					continue   # one stands on a rocket or a ledge
				var ra := RADIUS * a.global_basis.get_scale().x
				var rb := RADIUS * b.global_basis.get_scale().x
				var d := Vector2(pa.x - pb.x, pa.z - pb.z).length()
				var need := ra + rb + GAP
				if d < need:
					var key := "%s/%s" % [a.name, b.name]
					if not worst.has(key) or d < worst[key][0]:
						worst[key] = [d, need, t]
		t += STEP
	for key: String in worst:
		var w: Array = worst[key]
		failures += 1
		print("  %s: %s %.2f m apart at %.1f s (needs %.2f)" % [path.get_file(), key, w[0], w[2], w[1]])
	shot.queue_free()
