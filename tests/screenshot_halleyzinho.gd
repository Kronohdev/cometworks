extends SceneTree
## Look check of Vovô Edmundo Halleyzinho (scenes/npc/halleyzinho.tscn) in the toon look (opens
## a window): a contact sheet of the studio (scenes/npc/creature_showcase.tscn) with a young
## Cometling beside him for scale.
##   row 1: face close-up front, three-quarter, side, back
##   row 2: full body, each habit mid-way (specs, doze, forehead, stargaze), walking
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_halleyzinho.gd -- <out.png>

const HALLEY := "res://scenes/npc/halleyzinho.tscn"
const CREATURE := "res://scenes/npc/creature.tscn"
const CELL := Vector2i(400, 450)

var out_path := "user://halleyzinho_sheet.png"
var _studio: Node3D
var _cam: Camera3D
var _h: Halleyzinho
var _young: Cometling


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _run()
	quit()


func _run() -> void:
	_studio = (load("res://scenes/npc/creature_showcase.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(_studio)
	_cam = _studio.get_node("Camera3D") as Camera3D
	_cam.add_child((load("res://scenes/fx/cw_outline.tscn") as PackedScene).instantiate())
	_h = (load(HALLEY) as PackedScene).instantiate() as Halleyzinho
	_h.listen_to_events = false
	_h.habits = false
	_studio.add_child(_h)
	_young = (load(CREATURE) as PackedScene).instantiate() as Cometling
	_young.listen_to_events = false
	_young.fidgets = false
	_studio.add_child(_young)
	_young.position = Vector3(1.4, 0, 0)
	_young.rotation.y = -0.4
	await _frames(4)
	var shots := [
		["front", Vector3(0, 0.72, 2.0), Vector3(0, 0.6, 0), 0.0, ""],
		["three_q", Vector3(1.3, 0.8, 1.6), Vector3(0, 0.58, 0), 0.0, ""],
		["side", Vector3(2.1, 0.72, 0.0), Vector3(0, 0.55, 0), 0.0, ""],
		["back", Vector3(-1.1, 0.9, -1.8), Vector3(0, 0.55, 0), 0.0, ""],
		["full", Vector3(1.4, 1.0, 4.4), Vector3(0.6, 0.5, 0), 0.0, ""],
		["specs", Vector3(0.7, 0.75, 2.0), Vector3(0, 0.58, 0), 0.4, "specs"],
		["doze", Vector3(0.7, 0.75, 2.0), Vector3(0, 0.58, 0), 0.55, "doze"],
		["forehead", Vector3(0.7, 0.75, 2.0), Vector3(0, 0.58, 0), 0.45, "forehead"],
	]
	var cols := 4
	var rows := ceili(shots.size() / float(cols))
	var sheet := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s: Array = shots[i]
		_h.stop_shot()
		_h.play("idle")
		_h.paused = true
		_young.paused = true
		_young.visible = s[0] == "full"
		if String(s[4]) != "":
			_h.play_habit(String(s[4]))
			_step(_h, float(s[3]) * 4.0)
		else:
			_step(_h, 0.5)
		_step(_young, 0.5)
		_cam.position = s[1]
		_cam.look_at(s[2], Vector3.UP)
		await _frames(3)
		var img := get_root().get_texture().get_image()
		var crop := img.get_region(Rect2i(Vector2i(800 - 300, 112), Vector2i(600, 675)))
		crop.convert(Image.FORMAT_RGBA8)
		crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
		if s[0] == "front":
			img.save_png(out_path.get_basename() + "_front.png")
	print("saved ", out_path, " err=", sheet.save_png(out_path))
	# extra frames: stargaze and walking
	var extra := Image.create(CELL.x * 2, CELL.y, false, Image.FORMAT_RGBA8)
	_h.play_habit("stargaze")
	_step(_h, 2.0)
	_cam.position = Vector3(1.2, 0.7, 2.0)
	_cam.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	await _frames(3)
	var a := get_root().get_texture().get_image().get_region(Rect2i(Vector2i(500, 112), Vector2i(600, 675)))
	a.convert(Image.FORMAT_RGBA8)
	a.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	extra.blit_rect(a, Rect2i(Vector2i.ZERO, CELL), Vector2i.ZERO)
	_h.play_habit("cane_rest")
	_h._h = ""
	_h.set_move_velocity(Vector3(0, 0, 0.3))
	for k in 20:
		_h.advance(0.05)
	_cam.position = Vector3(2.2, 0.8, 1.6)
	_cam.look_at(Vector3(0, 0.55, 0), Vector3.UP)
	await _frames(3)
	var b := get_root().get_texture().get_image().get_region(Rect2i(Vector2i(500, 112), Vector2i(600, 675)))
	b.convert(Image.FORMAT_RGBA8)
	b.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	extra.blit_rect(b, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x, 0))
	extra.save_png(out_path.get_basename() + "_extra.png")
	_studio.queue_free()
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
