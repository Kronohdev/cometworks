extends SceneTree
## UI motion (src/tycoon/ui/motion/): every motion node in the HUD, the main menu and the
## screens points at a node that exists; screens open and close through the HUD with their
## transition (the Screens layer is free at once, the leaving screen is freed after its exit);
## the number ticker lands on the value; reduce motion still lands everything.
## Run: godot --headless --path . --script res://tests/test_ui_motion.gd

const SCREENS := ["book", "contracts", "crew", "final_score", "finale", "finance", "map", "new_project",
	"newspaper", "project_phase", "project_review", "race", "research", "settings", "rocket_designer", "design_review"]

var _fails := 0


func _initialize() -> void:
	CwMotion.set_reduced(false)
	print("motion nodes resolve")
	for path in ["res://scenes/tycoon/ui/tycoon_hud.tscn", "res://scenes/menu/main_menu.tscn",
			"res://scenes/menu/menu_item.tscn", "res://scenes/menu/options_panel.tscn"]:
		_check_paths(path)
	for n: String in SCREENS:
		_check_paths("res://scenes/tycoon/ui/screens/%s.tscn" % n)
	await _hud_screens()
	await _ticker()
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _check_paths(path: String) -> void:
	var ps := load(path) as PackedScene
	_check(ps != null, "%s loads" % path.get_file())
	if ps == null:
		return
	var root := ps.instantiate()
	var bad: PackedStringArray = []
	var count := 0
	for n in _all(root):
		var sc := n.get_script() as Script
		if sc == null or not sc.resource_path.begins_with("res://src/tycoon/ui/motion/"):
			continue
		count += 1
		for prop in ["target", "root", "items", "backdrop", "panel"]:
			if not prop in n:
				continue
			var p: NodePath = n.get(prop)
			if not p.is_empty() and n.get_node_or_null(p) == null:
				bad.append("%s.%s -> %s" % [root.get_path_to(n), prop, p])
		if "extra" in n:
			for p: NodePath in n.get("extra"):
				if n.get_node_or_null(p) == null:
					bad.append("%s.extra -> %s" % [root.get_path_to(n), p])
	_check(bad.is_empty() and count > 0, "%s: %d motion nodes, all targets found %s" % [path.get_file(), count,
		"" if bad.is_empty() else str(bad)])
	root.free()


static func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _hud_screens() -> void:
	print("screens through the HUD")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	get_root().add_child(main)
	await process_frame
	await process_frame
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	var hud := main.hud
	var layer := hud.get_node("%Screens")
	for n in ["research", "contracts", "finance", "crew", "race", "book", "map", "settings", "new_project", "rocket_designer"]:
		_check(hud.open_screen(n), "%s opens" % n)
		var scr := layer.get_child(0) if layer.get_child_count() > 0 else null
		_check(scr != null and CwScreenTransition.of(scr) != null, "%s has its transition" % n)
		await _wait(0.1)
		hud.close_screen()
		_check(hud.current_screen() == "" and layer.get_child_count() == 0, "%s: Screens layer free at once" % n)
		_check(scr != null and is_instance_valid(scr) and scr.get_parent() == hud, "%s plays its exit below the layer" % n)
		await _wait(0.6)
		_check(not is_instance_valid(scr), "%s freed after the exit" % n)
	# one screen replacing another: the new one is the only child of the layer
	hud.open_screen("research")
	hud.open_screen("finance")
	_check(layer.get_child_count() == 1 and hud.current_screen() == "finance", "a screen replaces another at once")
	hud.close_screen()
	await _wait(0.6)
	main.queue_free()
	await process_frame


func _ticker() -> void:
	print("number ticker")
	var l := Label.new()
	var t := CwNumberTicker.new()
	t.seconds = 0.2
	l.add_child(t)
	get_root().add_child(l)
	await process_frame
	CwNumberTicker.show(l, 100.0, TycoonHUD.fmt_int)
	_check(l.text == "100", "first value is set at once")
	CwNumberTicker.show(l, 250.0, TycoonHUD.fmt_int)
	_check(l.text == "100", "a new value counts from the old one")
	await _wait(0.4)
	_check(l.text == "250", "and lands on it (%s)" % l.text)
	CwMotion.set_reduced(true)
	CwNumberTicker.show(l, 300.0, TycoonHUD.fmt_int)
	_check(l.text == "300", "reduce motion: the value jumps")
	CwMotion.set_reduced(false)
	var plain := Label.new()
	CwNumberTicker.show(plain, 42.0, TycoonHUD.fmt_int)
	_check(plain.text == "42", "a label without a ticker gets the text")
	plain.free()
	l.queue_free()


func _wait(s: float) -> void:
	await create_timer(s).timeout
