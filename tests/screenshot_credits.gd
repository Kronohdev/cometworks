extends SceneTree
## Windowed screenshots of the credits and the tidier main menu:
##   devs_<id>.png         close-up sheet of each developer's Cometling (data/credits.json):
##                         front, three-quarter, side, back and waving
##   devs_lineup.png       the four together
##   menu_<w>x<h>.png      the main menu at 1920x1080, 1600x900 and 1366x768
##   menu_more.png         the "Mais modos" sub-list open
##   credits_<w>x<h>.png   the Créditos screen
##   credits_spot_<id>.png each developer in the spotlight, mid-signature (1920x1080)
## With "devs" after the output folder only the developer sheets are rendered.
## Run: godot --path . --script res://tests/screenshot_credits.gd -- <out_dir> [devs]

const CREATURE := "res://scenes/npc/creature.tscn"
const MENU := "res://scenes/menu/main_menu.tscn"
const CELL := Vector2i(400, 450)

var out_dir := "user://"
var _studio: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	await _devs()
	if not (args.size() > 1 and args[1] == "devs"):
		for res in [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1366, 768)]:
			await _menu(res)
		await _credits(Vector2i(1920, 1080))
		await _credits(Vector2i(1366, 768))
	print("CREDITS SCREENSHOTS DONE")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(img: Image, file: String) -> void:
	var p := out_dir.path_join(file)
	print("saved ", p, " err=", img.save_png(p))


# ------------------------------------------------------------------ developers
func _spawn(dev: Dictionary) -> Cometling:
	var c := (load(CREATURE) as PackedScene).instantiate() as Cometling
	c.listen_to_events = false
	c.fidgets = false
	c.auto_emotes = false
	_studio.add_child(c)
	CreditsScreen.dress(c, dev)
	c.paused = true
	return c


func _devs() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(2)
	_studio = (load("res://scenes/npc/creature_showcase.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(_studio)
	_cam = _studio.get_node("Camera3D") as Camera3D
	_cam.add_child((load("res://scenes/fx/cw_outline.tscn") as PackedScene).instantiate())
	for n in _studio.get_children():
		if n is Cometling:
			(n as Node3D).visible = false
	var devs := CreditsScreen.developers()
	# lineup
	var cs: Array[Cometling] = []
	for i in devs.size():
		var c := _spawn(devs[i])
		c.position = Vector3((i - (devs.size() - 1) * 0.5) * 1.05, 0, 0)
		c.advance(0.6)
		cs.append(c)
	_cam.fov = 26.0
	_cam.look_at_from_position(Vector3(0, 0.95, 6.2), Vector3(0, 0.55, 0), Vector3.UP)
	await _frames(4)
	_save(get_root().get_texture().get_image(), "devs_lineup.png")
	for c in cs:
		c.queue_free()
	await _frames(2)
	for dev in devs:
		await _sheet(dev)
	_studio.queue_free()
	await _frames(2)


func _sheet(dev: Dictionary) -> void:
	var c := _spawn(dev)
	_cam.fov = 30.0
	var shots := [
		[Vector3(0, 0.78, 2.0), Vector3(0, 0.62, 0), ""],
		[Vector3(1.3, 0.85, 1.6), Vector3(0, 0.6, 0), ""],
		[Vector3(2.1, 0.75, 0.0), Vector3(0, 0.58, 0), ""],
		[Vector3(-1.2, 0.95, -1.8), Vector3(0, 0.58, 0), ""],
		[Vector3(0.5, 0.8, 3.0), Vector3(0, 0.5, 0), "wave"],
		[Vector3(0, 0.66, 1.2), Vector3(0, 0.66, 0), ""],
	]
	var sheet := Image.create(CELL.x * 3, CELL.y * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s: Array = shots[i]
		c.stop_shot()
		if String(s[2]) != "":
			c.play(String(s[2]))
			c.advance(0.7)
		else:
			c.advance(0.05)
		_cam.look_at_from_position(s[0], s[1], Vector3.UP)
		await _frames(3)
		var img := get_root().get_texture().get_image()
		var vs := img.get_size()
		var crop := img.get_region(Rect2i((vs.x - vs.y * CELL.x / CELL.y) / 2, 0, vs.y * CELL.x / CELL.y, vs.y))
		crop.convert(Image.FORMAT_RGBA8)
		crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % 3) * CELL.x, (i / 3) * CELL.y))
	_save(sheet, "devs_%s.png" % String(dev["id"]))
	c.queue_free()
	await _frames(2)


# ------------------------------------------------------------------ menu and credits
func _open_menu(res: Vector2i) -> Node:
	DisplayServer.window_set_size(res)
	get_root().size = res
	await _frames(3)
	var menu := (load(MENU) as PackedScene).instantiate()
	get_root().add_child(menu)
	current_scene = menu
	await _frames(90)
	return menu


func _menu(res: Vector2i) -> void:
	var menu: Node = await _open_menu(res)
	_save(get_root().get_texture().get_image(), "menu_%dx%d.png" % [res.x, res.y])
	if res == Vector2i(1920, 1080) and menu.has_method("open_more"):
		menu.call("open_more")
		await _frames(40)
		_save(get_root().get_texture().get_image(), "menu_more.png")
		menu.call("close_more")
		await _frames(30)
	menu.queue_free()
	await _frames(3)


func _credits(res: Vector2i) -> void:
	var menu: Node = await _open_menu(res)
	menu.call("open_credits")
	await _frames(150)
	_save(get_root().get_texture().get_image(), "credits_%dx%d.png" % [res.x, res.y])
	if res == Vector2i(1920, 1080):
		# each developer in the spotlight, mid-signature
		var scr := menu.get_node("UI/Root/Credits") as CreditsScreen
		var devs := CreditsScreen.developers()
		for i in devs.size():
			scr.select(i)
			await _frames(75)
			_save(get_root().get_texture().get_image(), "credits_spot_%s.png" % String(devs[i]["id"]))
	menu.queue_free()
	await _frames(3)
