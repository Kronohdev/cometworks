extends SceneTree
## Look check of the mentor and rival-leader Lendas (scenes/npc/legends/<id>.tscn) in the toon
## look (opens a window), in the studio of scenes/npc/creature_showcase.tscn:
##   <out.png>            the lineup: the nine Lendas and a regular Cometling for scale
##   <out>_closeups.png   a three-quarter close-up of each face
##   <out>_<id>.png       one sheet per Lenda: front, three-quarter, side, back, then its habits
## Optional second argument: only that Lenda's sheet (e.g. -- out.png keplerino).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_legends_mentors.gd -- <out.png> [id]

const IDS := ["dora", "berta", "keplerino", "dulinha", "sagao", "sali", "gagarinho", "cifrinha", "herschelinha"]
const CREATURE := "res://scenes/npc/creature.tscn"
const CELL := Vector2i(400, 450)

var out_path := "user://legends_mentors.png"
var only := ""
var _studio: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	if args.size() > 1:
		only = args[1]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _run()
	quit()


func _run() -> void:
	_studio = (load("res://scenes/npc/creature_showcase.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(_studio)
	_cam = _studio.get_node("Camera3D") as Camera3D
	_cam.add_child((load("res://scenes/fx/cw_outline.tscn") as PackedScene).instantiate())
	var lendas: Array[LegendCometling] = []
	for id: String in IDS:
		if not ResourceLoader.exists("res://scenes/npc/legends/%s.tscn" % id):
			push_warning("no scene for " + id)
			continue
		var c := (load("res://scenes/npc/legends/%s.tscn" % id) as PackedScene).instantiate() as LegendCometling
		c.listen_to_events = false
		c.habits = false
		c.fidgets = false
		c.paused = true
		_studio.add_child(c)
		lendas.append(c)
	var young := (load(CREATURE) as PackedScene).instantiate() as Cometling
	young.listen_to_events = false
	young.fidgets = false
	young.paused = true
	_studio.add_child(young)
	await _frames(3)
	if only == "":
		await _lineup(lendas, young)
		await _closeups(lendas, young)
	for c in lendas:
		if only == "" or only == c.legend_id:
			await _sheet(c, lendas, young)
	_studio.queue_free()
	await _frames(2)


func _lineup(lendas: Array[LegendCometling], young: Cometling) -> void:
	var all: Array[Cometling] = []
	all.assign(lendas)
	all.append(young)
	var gap := 0.9
	for i in all.size():
		var c := all[i]
		c.visible = true
		c.position = Vector3((i - (all.size() - 1) * 0.5) * gap, 0, 0)
		c.rotation.y = 0.0
		c.play("idle")
		_step(c, 0.6)
		_open_eyes(c)
	_cam.fov = 30.0
	_cam.position = Vector3(0, 1.2, 9.6)
	_cam.look_at(Vector3(0, 0.55, 0), Vector3.UP)
	await _frames(3)
	var img := get_root().get_texture().get_image()
	print("saved ", out_path, " err=", img.save_png(out_path))
	# three-quarter view of the same lineup
	for c in all:
		c.rotation.y = 0.5
		_step(c, 0.1)
	await _frames(3)
	get_root().get_texture().get_image().save_png(out_path.get_basename() + "_lineup_3q.png")


func _closeups(lendas: Array[LegendCometling], young: Cometling) -> void:
	var cols := 5
	var sheet := Image.create(CELL.x * cols, CELL.y * 2, false, Image.FORMAT_RGBA8)
	young.visible = false
	for i in lendas.size():
		_solo(lendas, lendas[i])
		lendas[i].rotation.y = 0.45
		_open_eyes(lendas[i])
		_cam.position = Vector3(0, 0.85, 3.0)
		_cam.look_at(Vector3(0, 0.56, 0), Vector3.UP)
		await _frames(3)
		_blit(sheet, i, cols)
	print("saved ", out_path.get_basename() + "_closeups.png err=",
		sheet.save_png(out_path.get_basename() + "_closeups.png"))
	for c in lendas:
		c.visible = true


func _sheet(c: LegendCometling, lendas: Array[LegendCometling], young: Cometling) -> void:
	young.visible = false
	_solo(lendas, c)
	var views := [
		[Vector3(0, 0.62, 3.3), Vector3(0, 0.5, 0)],
		[Vector3(1.4, 0.85, 1.9), Vector3(0, 0.56, 0)],
		[Vector3(2.4, 0.75, 0.0), Vector3(0, 0.55, 0)],
		[Vector3(-1.3, 0.95, -2.0), Vector3(0, 0.55, 0)],
	]
	var habits := c.habit_names
	var cols := 4
	var rows := ceili((views.size() + habits.size() + 1) / float(cols))
	var sheet := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	var k := 0
	for v: Array in views:
		c.stop_shot()
		c.play("idle")
		c._h = ""
		_step(c, 0.5)
		_open_eyes(c)
		_cam.position = v[0]
		_cam.look_at(v[1], Vector3.UP)
		await _frames(3)
		_blit(sheet, k, cols)
		k += 1
	for h: String in habits:
		c.play_habit(h)
		_step(c, c._h_len * 0.5)
		_cam.position = Vector3(0.9, 0.8, 2.3)
		_cam.look_at(Vector3(0, 0.62, 0), Vector3.UP)
		await _frames(3)
		_blit(sheet, k, cols)
		k += 1
	# walking
	c._h = ""
	c.set_move_velocity(Vector3(0, 0, 0.4))
	for i in 20:
		c.advance(0.05)
	_cam.position = Vector3(2.0, 0.85, 1.7)
	_cam.look_at(Vector3(0, 0.55, 0), Vector3.UP)
	await _frames(3)
	_blit(sheet, k, cols)
	c.set_move_velocity(Vector3.ZERO)
	_step(c, 0.5)
	var p := out_path.get_basename() + "_" + c.legend_id + ".png"
	print("saved ", p, " err=", sheet.save_png(p))


func _solo(lendas: Array[LegendCometling], c: LegendCometling) -> void:
	for o in lendas:
		o.visible = o == c
	c.position = Vector3.ZERO
	c.rotation.y = 0.0
	_cam.fov = 30.0


func _blit(sheet: Image, i: int, cols: int) -> void:
	var img := get_root().get_texture().get_image()
	var crop := img.get_region(Rect2i(Vector2i(800 - 300, 112), Vector2i(600, 675)))
	crop.convert(Image.FORMAT_RGBA8)
	crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))


## No blink in the shot (the timers are the Cometling's own).
func _open_eyes(c: Cometling) -> void:
	c._blink_t = -1.0
	c._blink_next = 9.0
	c.advance(0.001)


## Steps a Cometling's animation by hand in small slices (big steps upset its springs).
func _step(c: Cometling, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		c.advance(0.033)
		t += 0.033


func _frames(k: int) -> void:
	for i in k:
		await process_frame
