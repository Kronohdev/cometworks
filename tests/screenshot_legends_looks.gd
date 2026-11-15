extends SceneTree
## Look check of the Lenda Cometlings (scenes/npc/legends/<id>.tscn, data/tycoon/legends.json
## `scene`) in the toon look (opens a window), in the studio of scenes/npc/creature_showcase.tscn:
##   <out>.png            the lineup: every Lenda with a scene, a regular Cometling at the end
##   <out>_row<k>.png     the same lineup closer, five Lendas and a regular Cometling per row
##   <out>_portraits.png  the card portraits the game's photo studio (CwPortraitStudio) takes of
##                        every Lenda (TycoonLegends.look: its own body when it has a scene)
##   <out>_<id>.png       one sheet per Lenda: face front, three-quarter, side, back, and each of
##                        its habits mid-way, a regular Cometling beside the full-body cell
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_legends_looks.gd -- <out.png> [ids...]

const CREATURE := "res://scenes/npc/creature.tscn"
const CELL := Vector2i(360, 405)

var out_path := "user://legends_looks.png"
var only: Array[String] = []
var _studio: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	for i in range(1, args.size()):
		only.append(args[i])
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _run()
	quit()


func _legends() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in TycoonLegends.all():
		var id := String(l["id"])
		if not only.is_empty() and not id in only:
			continue
		var path := TycoonLegends.scene_path(id)
		if path != "":
			out.append({"id": id, "path": path})
	return out


func _run() -> void:
	_studio = (load("res://scenes/npc/creature_showcase.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(_studio)
	_cam = _studio.get_node("Camera3D") as Camera3D
	_cam.add_child((load("res://scenes/fx/cw_outline.tscn") as PackedScene).instantiate())
	for n in _studio.get_children():
		if n is Cometling:
			(n as Node3D).visible = false
	var list := _legends()
	await _lineup(list, out_path)
	var k := 0
	while k * 5 < list.size():
		await _lineup(list.slice(k * 5, k * 5 + 5), out_path.get_basename() + "_row%d.png" % (k + 1))
		k += 1
	await _portraits()
	for l in list:
		await _sheet(l)
	_studio.queue_free()
	await _frames(2)


func _spawn(path: String) -> Cometling:
	var c := (load(path) as PackedScene).instantiate() as Cometling
	c.listen_to_events = false
	if c is LegendCometling:
		(c as LegendCometling).habits = false
	c.fidgets = false
	_studio.add_child(c)
	c.paused = true
	return c


func _lineup(list: Array, path: String) -> void:
	var cs: Array[Cometling] = []
	var n := list.size() + 1
	var gap := 1.05
	for i in n:
		var c := _spawn(CREATURE if i == list.size() else String(list[i]["path"]))
		c.position = Vector3((i - (n - 1) * 0.5) * gap, 0, 0)
		cs.append(c)
	for c in cs:
		_step(c, 0.6)
	var w := (n - 1) * gap + 1.2
	_cam.fov = 26.0
	_cam.look_at_from_position(Vector3(0, 0.85, w * 1.2 + 0.6), Vector3(0, 0.5, 0), Vector3.UP)
	await _frames(4)
	var img := get_root().get_texture().get_image()
	print("saved ", path, " err=", img.save_png(path))
	# three-quarter view of the lineup too
	_cam.look_at_from_position(Vector3(w * 0.45, 1.2, w * 1.15 + 0.4), Vector3(0, 0.45, 0), Vector3.UP)
	await _frames(3)
	get_root().get_texture().get_image().save_png(path.get_basename() + "_3q.png")
	for c in cs:
		c.queue_free()
	await _frames(2)


func _sheet(l: Dictionary) -> void:
	var c := _spawn(String(l["path"]))
	var young := _spawn(CREATURE)
	young.position = Vector3(1.25, 0, 0)
	young.rotation.y = -0.4
	_cam.fov = 34.0
	var shots := [
		["front", Vector3(0, 0.72, 2.0), Vector3(0, 0.6, 0), ""],
		["three_q", Vector3(1.3, 0.8, 1.6), Vector3(0, 0.58, 0), ""],
		["side", Vector3(2.1, 0.72, 0.0), Vector3(0, 0.55, 0), ""],
		["back", Vector3(-1.1, 0.9, -1.8), Vector3(0, 0.55, 0), ""],
		["full", Vector3(1.0, 1.0, 4.0), Vector3(0.55, 0.5, 0), ""],
	]
	var lc := c as LegendCometling
	if lc:
		for h in lc.habit_names:
			shots.append([h, Vector3(0.9, 0.85, 2.3), Vector3(0, 0.6, 0), h])
	shots.append(["walk", Vector3(2.2, 0.8, 1.6), Vector3(0, 0.55, 0), "~walk"])
	var cols := 4
	var rows := ceili(shots.size() / float(cols))
	var sheet := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s: Array = shots[i]
		c.stop_shot()
		c.play("idle")
		c.set_move_velocity(Vector3.ZERO)
		if lc:
			lc._h = ""
		young.visible = s[0] == "full"
		var h := String(s[3])
		if h == "~walk":
			c.set_move_velocity(Vector3(0, 0, 0.6))
			_step(c, 1.0)
		elif h != "" and lc:
			lc.play_habit(h)
			# mid-way through the habit (one-shots: a bit in)
			var len := lc._h_len if lc.current_habit() != "" else 0.8
			_step(c, len * 0.5)
		else:
			_step(c, 0.5)
		_step(young, 0.5)
		_cam.look_at_from_position(s[1], s[2], Vector3.UP)
		await _frames(3)
		var img := get_root().get_texture().get_image()
		var crop := img.get_region(Rect2i(Vector2i(800 - 300, 112), Vector2i(600, 675)))
		crop.convert(Image.FORMAT_RGBA8)
		crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
	var p := out_path.get_basename() + "_" + String(l["id"]) + ".png"
	print("saved ", p, " err=", sheet.save_png(p))
	c.queue_free()
	young.queue_free()
	await _frames(2)


## The real portrait studio, one still per Lenda (all of them: the ones without a scene of their
## own still wear colours and hat), in a grid.
func _portraits() -> void:
	var studio := (load("res://scenes/tycoon/ui/cw_portrait_studio.tscn") as PackedScene).instantiate() as CwPortraitStudio
	get_root().add_child(studio)
	var ids: Array[String] = []
	for l: Dictionary in TycoonLegends.all():
		ids.append(String(l["id"]))
	var got := {}
	studio.shot.connect(func(k: String, t: Texture2D) -> void: got[k] = t)
	for id in ids:
		studio.portrait(TycoonLegends.look(id), Color(1, 0.85, 0.4))
	var wait := 0
	while got.size() < ids.size() and wait < 600:
		await process_frame
		wait += 1
	var cols := 7
	var cell := 200
	var sheet := Image.create(cell * cols, cell * ceili(ids.size() / float(cols)), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.18, 0.26))
	for i in ids.size():
		var tex := studio.portrait(TycoonLegends.look(ids[i])) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % cols) * cell, (i / cols) * cell))
	var p := out_path.get_basename() + "_portraits.png"
	print("saved ", p, " err=", sheet.save_png(p))
	studio.queue_free()
	await _frames(2)


## Steps a Cometling's animation by hand in small slices (big steps upset its springs).
func _step(c: Cometling, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		c.advance(0.033)
		t += 0.033


func _frames(k: int) -> void:
	for i in k:
		await process_frame
