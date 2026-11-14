extends SceneTree
## Showcase bench for the Cometling animations (opens a window). Lines up Cometlings in
## the studio (scenes/npc/creature_showcase.tscn) and saves:
##   anims_<group>.png    film strips: each row is one action, 6 Cometlings frozen at
##                        increasing times of it (left to right), name and time above
##   anims_faces.png      face close-ups of every expression
##   anims_crowd.png      a crowd idling with different moods and personalities (habits on)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_creature_anims.gd -- <out_dir> [group...]
## Groups: loops, shots_a, shots_b, shots_c, gait, faces, crowd

const CREATURE := preload("res://scenes/npc/creature.tscn")
const STEP := 1.0 / 60.0
const ROWS_PER_SHEET := 4

## [action, [times...], role, variant, extra]  extra: "walk" / "run" / "turn" / "" / "expr:<name>"
const GROUPS := {
	"loops": [
		["idle", [0.2, 1.0, 2.0, 3.0, 4.0, 5.0], "ground", 0, ""],
		["sleep", [0.6, 2.0, 4.6, 5.4, 5.85, 6.3], "pilot", 1, ""],
		["think", [0.6, 2.0, 3.5, 7.0, 7.2, 7.5], "scientist", 4, ""],
		["sad", [0.6, 1.5, 2.5, 3.5, 4.35, 5.0], "ground", 3, ""],
		["work_type", [0.5, 0.62, 0.75, 1.6, 3.8, 4.3], "scientist", 7, ""],
		["work_wrench", [0.3, 0.55, 0.8, 1.0, 6.1, 6.3], "engineer", 2, ""],
		["clipboard", [0.5, 1.6, 1.7, 2.0, 2.6, 3.0], "pilot", 5, ""],
		["carry", [0.5, 1.5, 4.5, 4.6, 4.7, 4.85], "ground", 6, ""],
	],
	"loops_b": [
		["talk", [0.4, 1.1, 2.0, 2.6, 5.4, 5.6], "engineer", 0, ""],
		["dance", [0.3, 0.55, 0.8, 7.2, 7.45, 7.7], "ground", 8, ""],
		["look_up", [0.5, 1.5, 5.4, 5.6, 5.8, 6.0], "pilot", 2, ""],
		["work_hammer", [0.3, 0.5, 0.58, 0.64, 0.7, 0.75], "engineer", 3, ""],
		["work_scan", [0.4, 1.0, 1.6, 2.2, 2.8, 3.4], "scientist", 1, ""],
		["sit", [0.4, 1.0, 2.0, 3.0, 4.0, 5.0], "ground", 4, ""],
	],
	"shots_a": [
		["hop", [0.06, 0.12, 0.2, 0.26, 0.4, 0.48], "ground", 2, ""],
		["clap", [0.1, 0.25, 0.34, 0.42, 0.51, 1.2], "pilot", 0, ""],
		["celebrate", [0.2, 0.45, 0.6, 0.8, 1.0, 1.6], "engineer", 4, ""],
		["startled", [0.05, 0.12, 0.25, 0.5, 0.8, 1.2], "scientist", 6, ""],
		["point", [0.12, 0.25, 0.35, 0.6, 1.0, 1.5], "ground", 7, ""],
		["salute", [0.08, 0.18, 0.3, 0.6, 1.0, 1.4], "pilot", 3, ""],
	],
	"shots_b": [
		["bow", [0.1, 0.3, 0.5, 0.8, 1.1, 1.35], "scientist", 5, ""],
		["shrug", [0.1, 0.25, 0.5, 0.8, 1.0, 1.2], "engineer", 1, ""],
		["laugh", [0.1, 0.3, 0.6, 0.9, 1.2, 1.5], "ground", 8, ""],
		["sigh", [0.3, 0.6, 0.9, 1.2, 1.5, 1.9], "pilot", 4, ""],
		["shake_head", [0.1, 0.2, 0.35, 0.5, 0.7, 0.9], "scientist", 2, ""],
		["yawn", [0.3, 0.7, 1.2, 1.6, 2.05, 2.3], "engineer", 6, ""],
	],
	"shots_c": [
		["stretch", [0.3, 0.6, 0.9, 1.2, 1.5, 1.8], "ground", 0, ""],
		["wave", [0.2, 0.5, 0.8, 1.1, 1.4, 1.8], "pilot", 7, ""],
		["cheer", [0.1, 0.25, 0.4, 0.6, 0.9, 1.2], "ground", 5, ""],
		["jump", [0.1, 0.2, 0.3, 0.45, 0.62, 0.8], "engineer", 2, ""],
		["surprise", [0.05, 0.15, 0.25, 0.5, 0.7, 0.9], "scientist", 3, ""],
		["spin", [0.1, 0.3, 0.5, 0.7, 0.9, 1.1], "pilot", 8, ""],
	],
	"gait": [
		["idle", [0.25, 0.33, 0.41, 0.49, 0.57, 0.65], "ground", 1, "walk"],
		["idle", [0.25, 0.3, 0.35, 0.4, 0.45, 0.5], "pilot", 0, "run"],
		["idle", [0.3, 0.6, 0.9, 1.2, 1.5, 1.8], "engineer", 4, "turn"],
		["idle", [0.05, 0.12, 0.2, 0.3, 0.45, 0.7], "scientist", 6, "stop"],
	],
}

var out_dir := "user://"
var only: Array[String] = []
var _studio: Node3D
var _slots: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	for i in range(1, args.size()):
		only.append(args[i])
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_studio = (load("res://scenes/npc/creature_showcase.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(_studio)
	_slots = _studio.get_node("Slots")
	_cam = _studio.get_node("Camera3D")
	await _frames(4)
	for g in GROUPS:
		if only.is_empty() or g in only:
			await _sheet(g, GROUPS[g])
	if only.is_empty() or "faces" in only:
		await _faces()
	if only.is_empty() or "crowd" in only:
		await _crowd()
	quit()


func _spawn(variant: int, role: String, pos: Vector3, yaw_deg: float, seed_v: int) -> Cometling:
	var c := CREATURE.instantiate() as Cometling
	c.listen_to_events = false
	c.personality_seed = seed_v
	c.position = pos
	c.rotation.y = deg_to_rad(yaw_deg)
	_slots.add_child(c)
	CometlingLooks.apply(c, variant, role)
	c.paused = true
	return c


func _label(text: String, pos: Vector3, size := 40) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0024
	l.modulate = Color("#3c4450")
	l.outline_size = 0
	l.position = pos
	_slots.add_child(l)


## One action as a film strip: n Cometlings, each advanced to its own time.
func _strip(row: Array) -> Image:
	var action := String(row[0])
	var times: Array = row[1]
	var extra := String(row[4])
	var n := times.size()
	var spacing := 0.95
	for i in n:
		var x := (i - (n - 1) * 0.5) * spacing
		var holder := Node3D.new()
		holder.position = Vector3(x, 0, 0)
		# same 3/4 view for every slot, whatever its place in the perspective
		holder.rotation.y = deg_to_rad(20.0) + atan2(-x, 7.6)
		_slots.add_child(holder)
		var c := CREATURE.instantiate() as Cometling
		c.listen_to_events = false
		c.personality_seed = 5
		c.fidgets = action == "idle" and extra == ""
		holder.add_child(c)
		CometlingLooks.apply(c, int(row[3]), String(row[2]))
		c.paused = true
		if action != "idle":
			c.play(action)
		var t := 0.0
		var target := float(times[i])
		if extra == "stop":
			# arrive walking briskly, then stop: t counts from the stop
			for k in 60:
				c.set_move_velocity(holder.global_basis.z * 1.4)
				c.advance(STEP)
			c.set_move_velocity(Vector3.ZERO)
		while t < target:
			match extra:
				"walk":
					c.set_move_velocity(holder.global_basis.z * 0.9)
				"run":
					c.set_move_velocity(holder.global_basis.z * 3.4)
				"turn":
					holder.rotation.y += 2.2 * STEP
					c.set_move_velocity(holder.global_basis.z * 1.0)
			c.advance(STEP)
			t += STEP
		var name := action if extra == "" else extra
		_label("%s  %.2fs" % [name, target] if i == 0 else "%.2fs" % target, Vector3(x, 1.72, 0), 34 if i else 40)
	_cam.position = Vector3(0, 0.82, 7.6)
	_cam.rotation = Vector3(deg_to_rad(-2.0), 0, 0)
	_cam.fov = 24.0
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var crop := img.get_region(Rect2i(0, 80, 1600, 590))
	crop.convert(Image.FORMAT_RGBA8)
	crop.resize(1200, int(590 * 0.75), Image.INTERPOLATE_LANCZOS)
	_clear()
	return crop


func _sheet(group: String, rows: Array) -> void:
	var strips: Array[Image] = []
	for row in rows:
		strips.append(await _strip(row))
	var sheet_i := 0
	var i := 0
	while i < strips.size():
		var count := mini(ROWS_PER_SHEET, strips.size() - i)
		var h := strips[0].get_height()
		var sheet := Image.create(1200, h * count, false, Image.FORMAT_RGBA8)
		for k in count:
			sheet.blit_rect(strips[i + k], Rect2i(0, 0, 1200, h), Vector2i(0, k * h))
		var suffix := "" if strips.size() <= ROWS_PER_SHEET else "_%d" % (sheet_i + 1)
		var path := out_dir.path_join("anims_%s%s.png" % [group, suffix])
		print("saved ", path, " err=", sheet.save_png(path))
		i += count
		sheet_i += 1


func _faces() -> void:
	# every expression plus a few action faces, each rendered alone then put in a 5 x 3 sheet
	var faces: Array = []
	for e in Cometling.EXPRESSIONS:
		faces.append(["expr", String(e), 0.7])
	for a in [["sleep", 1.0], ["think", 2.0], ["sad", 1.0], ["yawn", 1.2], ["laugh", 0.6], ["startled", 0.4]]:
		faces.append(["play", String(a[0]), float(a[1])])
	var cell := Vector2i(320, 300)
	var sheet := Image.create(cell.x * 5, cell.y * 3, false, Image.FORMAT_RGBA8)
	_cam.position = Vector3(0, 0.78, 2.6)
	_cam.rotation = Vector3(deg_to_rad(-2.0), 0, 0)
	_cam.fov = 26.0
	for i in faces.size():
		var f: Array = faces[i]
		var c := _spawn(i % 9, ["pilot", "scientist", "engineer", "ground"][i % 4], Vector3.ZERO, 0.0, 9)
		c.fidgets = false
		c.eye_darts = false
		if f[0] == "expr":
			c.set_expression(String(f[1]))
		else:
			c.play(String(f[1]))
		var t := 0.0
		while t < float(f[2]):
			c.advance(STEP)
			t += STEP
		_label(String(f[1]), Vector3(0, 0.08, 0.45), 30)
		await _frames(3)
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var crop := img.get_region(Rect2i(800 - 400, 0, 800, 750))
		crop.convert(Image.FORMAT_RGBA8)
		crop.resize(cell.x, cell.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(crop, Rect2i(0, 0, cell.x, cell.y), Vector2i((i % 5) * cell.x, (i / 5) * cell.y))
		_clear()
	var path := out_dir.path_join("anims_faces.png")
	print("saved ", path, " err=", sheet.save_png(path))


func _crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var roles := ["pilot", "engineer", "scientist", "ground"]
	for i in 15:
		var pos := Vector3((i % 5 - 2) * 1.15 + rng.randf_range(-0.2, 0.2), 0, -(i / 5) * 1.3 + rng.randf_range(-0.2, 0.2))
		var c := _spawn(i % 9, roles[i % 4], pos, rng.randf_range(-35.0, 35.0), 200 + i)
		c.mood = [-0.8, 0.0, 0.5, 1.0, 0.2][i % 5]
		var t := rng.randf_range(4.0, 14.0)
		var k := 0.0
		while k < t:
			c.advance(STEP)
			k += STEP
	_cam.position = Vector3(0, 1.35, 5.6)
	_cam.rotation = Vector3(deg_to_rad(-9.0), 0, 0)
	_cam.fov = 34.0
	await _frames(4)
	await _shot("anims_crowd")
	_clear()


func _clear() -> void:
	for c in _slots.get_children():
		c.free()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	print("saved ", path, " (", img.get_size(), ") err=", img.save_png(path))
