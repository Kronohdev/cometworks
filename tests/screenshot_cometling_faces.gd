extends SceneTree
## Close-up check of the Cometling faces in the toon look (opens a window). One Cometling at a
## time in the studio (scenes/npc/creature_showcase.tscn), seen from a few distances and under
## a few lights, all put in one contact sheet:
##   faces_sheet.png   rows: day front, day side light, under a cast shadow, night;
##                     columns: close (face fills the frame), mid (follow camera), far
##                     (game camera distance, cropped 2x), happy, surprised
##   faces_close_<light>.png   the full close-up frame of each light
## Each cell is a crop of the 1600 x 900 frame scaled to the cell (close and mid unscaled
## crops of the centre, far a 2x nearest-neighbour blow-up so the pixels show).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_cometling_faces.gd -- <out_dir>

const CREATURE := preload("res://scenes/npc/creature.tscn")
const CELL := Vector2i(400, 300)

var out_dir := "user://"
var _studio: Node3D
var _cam: Camera3D
var _key: DirectionalLight3D
var _fill: OmniLight3D
var _env: Environment
var _roof: MeshInstance3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _run()
	quit()


func _run() -> void:
	_studio = (load("res://scenes/npc/creature_showcase.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(_studio)
	_cam = _studio.get_node("Camera3D") as Camera3D
	_key = _studio.get_node("Key") as DirectionalLight3D
	_fill = _studio.get_node("Fill") as OmniLight3D
	_env = (_studio.get_node("WorldEnvironment") as WorldEnvironment).environment
	# the game's ink outline, as on every gameplay camera (also applies the player's AA)
	_cam.add_child((load("res://scenes/fx/cw_outline.tscn") as PackedScene).instantiate())
	# a floating slab that shades the Cometling (the "under a cast shadow" row)
	_roof = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.1, 2.4)
	_roof.mesh = bm
	_studio.add_child(_roof)
	_roof.visible = false

	var lights := ["day", "side", "shadow", "night"]
	var cols := ["close", "mid", "far", "happy", "surprised"]
	var sheet := Image.create(CELL.x * cols.size(), CELL.y * lights.size(), false, Image.FORMAT_RGBA8)
	for r in lights.size():
		_light(String(lights[r]))
		for c in cols.size():
			var img := await _cell(String(cols[c]), String(lights[r]))
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, r * CELL.y))
	var path := out_dir.path_join("faces_sheet.png")
	print("saved ", path, " err=", sheet.save_png(path))
	_studio.queue_free()
	await _frames(2)


func _light(mode: String) -> void:
	_key.visible = true
	_key.light_energy = 1.3
	_key.light_color = Color(1, 0.886, 0.749)
	_key.rotation = Vector3(deg_to_rad(-36.5), deg_to_rad(35.0), 0)
	_fill.visible = true
	_env.ambient_light_energy = 0.65
	_env.background_color = Color(0.82, 0.86, 0.9)
	_roof.visible = false
	match mode:
		"side":
			_key.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(85.0), 0)
			_fill.visible = false
		"shadow":
			_roof.visible = true
			_roof.position = Vector3(0.6, 2.2, 1.2)
		"night":
			_key.light_energy = 0.25
			_key.light_color = Color(0.55, 0.65, 1.0)
			_fill.visible = false
			_env.ambient_light_energy = 0.18
			_env.background_color = Color(0.08, 0.1, 0.18)


func _cell(col: String, light: String) -> Image:
	var slots := _studio.get_node("Slots")
	for ch in slots.get_children():
		ch.free()
	var c := CREATURE.instantiate() as Cometling
	c.listen_to_events = false
	c.personality_seed = 11
	slots.add_child(c)
	CometlingLooks.apply(c, 2 if light != "night" else 4, "pilot")
	c.rotation.y = deg_to_rad(12.0)
	c.paused = true
	match col:
		"happy":
			c.set_expression("joy")
		"surprised":
			c.set_expression("surprised")
	for k in 40:
		c.advance(1.0 / 60.0)
	var dist := 1.6
	var fov := 24.0
	match col:
		"mid":
			dist = 4.5
		"far":
			dist = 14.0
	_cam.fov = fov
	_cam.position = Vector3(0, 0.66, dist)
	_cam.look_at(Vector3(0, 0.64, 0))
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var centre := img.get_size() / 2
	if col == "far":
		var src := img.get_region(Rect2i(centre - CELL / 4, CELL / 2))
		src.resize(CELL.x, CELL.y, Image.INTERPOLATE_NEAREST)
		return src
	if col == "mid":
		return img.get_region(Rect2i(centre - CELL / 2, CELL))
	# close: the whole face, scaled down to the cell (and the full frame saved for detail)
	if col == "close":
		img.save_png(out_dir.path_join("faces_close_%s.png" % light))
	var face := img.get_region(Rect2i(centre - Vector2i(560, 420), Vector2i(1120, 840)))
	face.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	return face


func _frames(n: int) -> void:
	for i in n:
		await process_frame
