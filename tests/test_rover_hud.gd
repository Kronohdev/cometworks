extends SceneTree
## Headless checks of the rover drive's HUD (scenes/surface/rover_drive.tscn on the Moon):
##   - the mini-map arrow points where the rover drives: for several headings its tip matches
##     the rover's forward as the map camera projects it, and the way it actually moves
##   - the free-play "Desafio" card docks under the mini-map (RoverHUD side slot) and no HUD
##     panel overlaps another or leaves the screen, at the logical sizes the 1600x900
##     canvas_items / expand stretch gives (16:9, 16:10, 4:3, ultrawide)
## Run: godot --headless --path . --script res://tests/test_rover_hud.gd

## window sizes -> logical viewport (expand keeps 1600x900 visible)
const WINDOWS: Array[Vector2i] = [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1280, 800),
	Vector2i(1024, 768), Vector2i(2560, 1080)]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	SurfaceSession.current = null
	var d := (load("res://scenes/surface/rover_drive.tscn") as PackedScene).instantiate() as RoverDrive
	d.default_body = &"moon"
	get_root().add_child(d)
	for i in 10:
		await process_frame
	d.rover.player_input = false
	_check_arrow(d)
	await _check_layout(d)
	d.queue_free()
	SurfaceSession.current = null
	await process_frame
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL: " + msg)


func _check_arrow(d: RoverDrive) -> void:
	var hud := d.hud
	var arrow := hud.get_node("%RoverArrow") as Control
	var cam := hud.get_node("%MapCam") as Camera3D
	_check(cam.global_transform.basis.y.is_equal_approx(Vector3(0, 0, -1)), "map camera: north (-Z) up")
	for yaw in [0.0, 0.7, PI * 0.5, -2.0, PI, 2.6]:
		d.rover.yaw = yaw
		hud._update_map()
		var tip := Vector2(0, 1).rotated(arrow.rotation)  # the texture rests pointing down
		var fw := d.rover.forward()
		var on_map := cam.unproject_position(d.rover.position + fw * 20.0) - cam.unproject_position(d.rover.position)
		_check(tip.dot(on_map.normalized()) > 0.99,
			"arrow points ahead at yaw %.2f (tip %s, forward on the map %s)" % [yaw, tip, on_map.normalized()])
	# and the way it really drives
	var p0 := d.rover.position
	d.rover.place(p0.x, p0.z, 1.1)
	d.rover.throttle = 1.0
	var start := d.rover.position
	for i in 90:
		d.rover.physics_step(1.0 / 60.0)
	d.rover.throttle = 0.0
	hud._update_map()
	var moved := d.rover.position - start
	var tip2 := Vector2(0, 1).rotated(arrow.rotation)
	var seen := cam.unproject_position(d.rover.position + Vector3(moved.x, 0, moved.z).normalized() * 20.0) \
		- cam.unproject_position(d.rover.position)
	_check(moved.length() > 1.0 and tip2.dot(seen.normalized()) > 0.95,
		"arrow matches the drive direction (moved %s, tip %s, on the map %s)" % [moved, tip2, seen.normalized()])
	d.rover.place(p0.x, p0.z, 0.0)


func _logical(win: Vector2i) -> Vector2i:
	var base := Vector2(1600, 900)
	var a := float(win.x) / win.y
	if a >= base.x / base.y:
		return Vector2i(roundi(base.y * a), 900)
	return Vector2i(1600, roundi(base.x / a))


func _check_layout(d: RoverDrive) -> void:
	var ex: SurfaceExplore = null
	for n in d.find_children("*", "SurfaceExplore", true, false):
		ex = n
	_check(ex != null, "the surface has its explore layer")
	if ex == null:
		return
	ex._refresh_explorer()
	var running := false
	for ch in ex.challenges:
		if String(ch["entry"].get("type", "")) == "reach_before":
			ch["phase"] = "running"
			ch["t"] = 3.0
			ex._ch_focus = ch
			running = true
			break
	_check(running, "the Moon has a race challenge")
	var hud := d.hud
	_check(ex.ch_card.get_parent() == hud.side_slot(), "the challenge card docks under the mini-map")
	var r := get_root()
	r.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	for win in WINDOWS:
		var sz := _logical(win)
		r.content_scale_size = sz
		for i in 4:
			await process_frame
		ex._fill_challenge_card(0.0)
		await process_frame
		var view := Rect2(Vector2.ZERO, Vector2(sz))
		var panels := {
			"map": hud.get_node("%MapPanel"), "challenge": ex.ch_card, "mission": hud.get_node("%MissionCard") if hud.has_node("%MissionCard") else hud.get_node("Root/MissionCard"),
			"gauges": hud.get_node("Root/Gauges"), "tools": hud.get_node("Root/ToolsPanel"), "chip": ex.get_node("%Chip"),
		}
		_check(ex.ch_card.visible, "%s: the challenge card shows" % sz)
		var box := hud.get_node("%MapBox") as Control
		_check(absf(box.size.x - box.size.y) < 1.0, "%s: the mini-map stays square (%s)" % [sz, box.size])
		var names := panels.keys()
		for i in names.size():
			var a := panels[names[i]] as Control
			if not a.is_visible_in_tree():
				continue
			var ra := a.get_global_rect()
			_check(view.grow(1.0).encloses(ra), "%s: %s inside the screen (%s)" % [sz, names[i], ra])
			for j in range(i + 1, names.size()):
				var b := panels[names[j]] as Control
				if not b.is_visible_in_tree():
					continue
				var rb := b.get_global_rect()
				_check(not ra.grow(-1.0).intersects(rb.grow(-1.0)),
					"%s: %s %s and %s %s do not overlap" % [sz, names[i], ra, names[j], rb])
	r.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	r.content_scale_size = Vector2i(1600, 900)
