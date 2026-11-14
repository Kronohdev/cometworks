extends SceneTree
## Visual check of the Cometlings (opens a window):
##   creature_turnaround   one Cometling from 5 angles
##   creature_roles        the four roles / colour variants
##   creature_poses        pose sheet (idle, walk, jump, wave, cheer, carry, sit, work...)
##   creature_closeup      face close-up (blink / happy / surprise)
##   hangar_crowd*         the crowd in the hangar from the default camera and closer
##   crew_panel            the crew panel over the hangar
## and measures the FPS of the hangar with and without the crowd.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_creatures.gd -- <out_dir> [only...]

const CREATURE := preload("res://scenes/npc/creature.tscn")

var out_dir := "user://"
var only: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	for i in range(1, args.size()):
		only.append(args[i])
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _run()
	quit()


func _want(n: String) -> bool:
	return only.is_empty() or n in only


func _run() -> void:
	if _want("creatures"):
		await _creature_shots()
	if _want("hangar"):
		await _hangar_shots()
	if _want("panel"):
		await _panel_shots()
	if _want("fps"):
		await _fps()


# ------------------------------------------------------------------ studio shots
func _studio() -> Node3D:
	var s := (load("res://scenes/npc/creature_showcase.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(s)
	return s


func _spawn(parent: Node, variant: int, role: String, pos: Vector3, yaw_deg: float, action := "idle") -> Cometling:
	var c := CREATURE.instantiate() as Cometling
	c.listen_to_events = false
	c.start_action = action
	c.personality_seed = variant * 31 + 7
	parent.add_child(c)
	CometlingLooks.apply(c, variant, role)
	c.position = pos
	c.rotation.y = deg_to_rad(yaw_deg)
	return c


func _creature_shots() -> void:
	var s := _studio()
	var slots := s.get_node("Slots")
	var cam := s.get_node("Camera3D") as Camera3D
	# turnaround
	for i in 5:
		var c := _spawn(slots, 0, "pilot", Vector3(-2.4 + i * 1.2, 0, 0), [0.0, 40.0, 90.0, 180.0, -130.0][i])
		c.paused = true
		c.advance(0.4)
	cam.position = Vector3(0, 0.95, 6.4)
	cam.rotation = Vector3(deg_to_rad(-4), 0, 0)
	cam.fov = 30.0
	await _frames(8)
	await _shot("creature_turnaround")
	_clear(slots)

	# roles and colours
	var roles := ["pilot", "engineer", "scientist", "ground", "pilot", "engineer", "scientist", "ground", "ground"]
	for i in 9:
		var c := _spawn(slots, i, roles[i], Vector3(-3.6 + i * 0.9, 0, -0.3 * (i % 2)), 15.0 - i * 3.0)
		c.paused = true
		c.advance(0.2 + i * 0.37)
	cam.position = Vector3(0, 1.1, 7.6)
	cam.rotation = Vector3(deg_to_rad(-6), 0, 0)
	await _frames(8)
	await _shot("creature_roles")
	_clear(slots)

	# pose sheet (3 rows x 5)
	var poses := [
		["idle", "", 0.6, "ground", 1], ["walk", "", 0.35, "engineer", 2], ["jump", "jump", 0.3, "pilot", 0],
		["wave", "wave", 0.7, "scientist", 4], ["cheer", "cheer", 0.6, "ground", 7],
		["carry", "carry", 1.0, "ground", 3], ["sit", "sit", 1.2, "scientist", 5], ["work_hammer", "work_hammer", 0.6, "engineer", 8],
		["work_scan", "work_scan", 0.9, "scientist", 6], ["surprise", "surprise", 0.18, "pilot", 1],
		["look_up", "look_up", 1.0, "ground", 2], ["clipboard", "clipboard", 1.0, "pilot", 4], ["talk", "talk", 0.8, "engineer", 0],
		["dance", "dance", 0.3, "ground", 3], ["spin", "spin", 1.02, "scientist", 7],
	]
	# each pose rendered alone, then composited into one 5 x 3 sheet
	var cell := Vector2i(320, 340)
	var sheet := Image.create(cell.x * 5, cell.y * 3, false, Image.FORMAT_RGBA8)
	cam.position = Vector3(0, 0.8, 3.7)
	cam.rotation = Vector3(deg_to_rad(-6), 0, 0)
	cam.fov = 30.0
	for i in poses.size():
		var pr: Array = poses[i]
		var c := _spawn(slots, int(pr[4]), String(pr[3]), Vector3.ZERO, 24.0)
		c.paused = true
		var act := String(pr[1])
		if act != "":
			c.play(act)
		if pr[0] == "walk":
			c.set_move_velocity(c.global_basis.z * 1.1)
		if pr[0] == "look_up":
			c.look_at_point(c.global_position + Vector3(0, 30, 6), 1.0)
		var t := 0.0
		while t < float(pr[2]):
			c.advance(1.0 / 60.0)
			t += 1.0 / 60.0
		var lbl := Label3D.new()
		lbl.text = String(pr[0]).replace("_", " ")
		lbl.font_size = 64
		lbl.pixel_size = 0.0024
		lbl.modulate = Color("#3c4450")
		lbl.outline_size = 0
		lbl.position = Vector3(0, 0.01, 0.5)
		lbl.rotation.x = -PI / 2
		slots.add_child(lbl)
		await _frames(3)
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var src := Rect2i(800 - 300, 450 - 330, 600, 640)
		var crop := img.get_region(src)
		crop.convert(Image.FORMAT_RGBA8)
		crop.resize(cell.x, int(cell.x * 640.0 / 600.0), Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(crop, Rect2i(0, 0, cell.x, cell.y), Vector2i((i % 5) * cell.x, (i / 5) * cell.y))
		_clear(slots)
	var path := out_dir.path_join("creature_poses.png")
	print("saved ", path, " err=", sheet.save_png(path))
	_clear(slots)

	# face close-ups
	var faces := [["idle", 0.0], ["happy", 0.0], ["surprise", 0.15], ["sleepy", 0.0]]
	for i in faces.size():
		var c := _spawn(slots, [0, 4, 3, 7][i], ["pilot", "scientist", "engineer", "ground"][i], Vector3(-1.05 + i * 0.7, 0, 0), 0.0)
		c.paused = true
		match String(faces[i][0]):
			"happy":
				c.play("cheer")
			"surprise":
				c.play("surprise")
			"sleepy":
				c.play("sit")
		for k in 30:
			c.advance(1.0 / 60.0)
	cam.position = Vector3(0, 0.66, 3.9)
	cam.rotation = Vector3(deg_to_rad(-2), 0, 0)
	cam.fov = 26.0
	await _frames(8)
	await _shot("creature_closeup")
	s.queue_free()
	await _frames(2)


# ------------------------------------------------------------------ hangar
func _hangar_shots() -> void:
	var hangar := (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(30)
	hangar.call("load_example", "garca")
	await _frames(240)
	await _shot("hangar_crowd")
	var crowd := hangar.find_child("HangarCrowd", true, false)
	print("crowd found: ", crowd != null)
	var cam = hangar.get("cam")
	if cam:
		# behind-left of the pad, where most of the crew hangs out
		cam.call("snap_to", Vector3(-8, 2.0, -8), deg_to_rad(20.0), deg_to_rad(16.0), 34.0)
		await _frames(150)
		await _shot("hangar_crowd_close")
		NpcEvents.emit("part_placed", {"stagger": 0.15})
		await _frames(9)
		await _shot("hangar_crowd_react")
		cam.call("snap_to", Vector3(-14, 2.0, -6), deg_to_rad(10.0), deg_to_rad(12.0), 16.0)
		await _frames(200)
		await _shot("hangar_crowd_zoom")
	hangar.queue_free()
	await _frames(4)


func _panel_shots() -> void:
	var hangar := (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(20)
	# a vessel with a crew capsule on the pad, two Cometlings seated
	var v: Vessel = hangar.get("vessel")
	v.clear()
	var cap := PartInstance.create("crew_capsule")
	v.set_root(cap)
	await _frames(10)
	var layer := CanvasLayer.new()
	layer.layer = 20
	hangar.add_child(layer)
	var panel := (load("res://scenes/ui/crew_panel.tscn") as PackedScene).instantiate() as CrewPanel
	layer.add_child(panel)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -440
	panel.offset_right = -14
	panel.offset_top = 70
	panel.offset_bottom = -14
	panel.set_vessel(v)
	var roster := panel.roster
	roster.unassign_all()
	if roster.members.size() >= 2:
		roster.assign(roster.members[0], cap, 0)
		roster.assign(roster.members[2 % roster.members.size()], cap, 1)
	panel.refresh()
	panel.select_member(roster.members[1])
	await _frames(90)
	await _shot("crew_panel")
	TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("pt") else "pt")
	await _frames(30)
	await _shot("crew_panel_other_locale")
	hangar.queue_free()
	await _frames(4)


## Average FPS of the hangar (Garça example, default camera) with and without the crowd.
func _fps() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var hangar := (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(30)
	hangar.call("load_example", "garca")
	await _frames(120)
	var crowd := hangar.find_child("HangarCrowd", true, false) as NpcCrowd
	var cam = hangar.get("cam")
	var results := []
	for view in ["default", "close"]:
		if view == "close" and cam:
			cam.call("snap_to", Vector3(-8, 2.0, -8), deg_to_rad(20.0), deg_to_rad(16.0), 34.0)
			await _frames(60)
		for on in [true, false, true, false]:
			crowd.crowd_enabled = on
			await _frames(30)
			var fps := await _measure(4.0)
			results.append([view, on, fps])
			print("FPS %s crowd=%s: %.1f" % [view, on, fps])
	for view in ["default", "close"]:
		var a := 0.0
		var b := 0.0
		for r in results:
			if r[0] == view:
				if r[1]:
					a += r[2] / 2.0
				else:
					b += r[2] / 2.0
		print("FPS SUMMARY %s view: with crowd %.1f fps (%.2f ms), without %.1f fps (%.2f ms), cost %.2f ms/frame"
			% [view, a, 1000.0 / a, b, 1000.0 / b, 1000.0 / a - 1000.0 / b])
	hangar.queue_free()
	await _frames(4)


func _measure(seconds: float) -> float:
	var t0 := Time.get_ticks_usec()
	var n := 0
	var proc := 0.0
	var phys := 0.0
	var draws := 0.0
	var prims := 0.0
	while Time.get_ticks_usec() - t0 < int(seconds * 1e6):
		await process_frame
		n += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	print("    process %.2f ms, physics %.2f ms, draw calls %d, primitives %d"
		% [proc / n * 1000.0, phys / n * 1000.0, roundi(draws / n), roundi(prims / n)])
	return n / ((Time.get_ticks_usec() - t0) / 1e6)


# ------------------------------------------------------------------ utils
func _clear(n: Node) -> void:
	for c in n.get_children():
		c.free()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	print("saved ", path, " (", img.get_size(), ") err=", err)
