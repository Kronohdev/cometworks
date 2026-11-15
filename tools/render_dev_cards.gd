extends SceneTree
## Renders the developers' character cards from data/credits.json into ui/brand/crew/devs/:
##   <name>.png   one card per developer (1200x1700), all in the same clean style: the
##                Cometling in a three-quarter wave, key / rim / fill light, soft shadow and
##                outlines, on a starry nebula in the game's palette, the name in Fredoka and
##                the role line underneath
##   group.png    the four together (2400x1500), the lead in the middle on a small podium
## The file name is the developer's name in lower case without accents ("João Lucas" ->
## joao_lucas.png). Re-run it after editing the names, roles or looks in data/credits.json.
## Needs a window (not --headless): it renders through the GPU.
## Run: godot --path . --script res://tools/render_dev_cards.gd [-- <out_dir>] [en]

const CREATURE := "res://scenes/npc/creature.tscn"
const OUTLINE := "res://scenes/fx/cw_outline.tscn"
const FREDOKA := "res://ui/fonts/fredoka/Fredoka-Variable.ttf"
const OUT := "res://ui/brand/crew/devs/"
const CARD := Vector2i(1200, 1700)
const GROUP := Vector2i(2400, 1500)

const INK := Color("#1b1845")
const CREAM := Color("#fff6e6")
const LILAC := Color("#9b7cff")

var out_dir := OUT
var lang := "pt"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "en" or a == "pt":
			lang = a
		else:
			out_dir = a
	TranslationServer.set_locale(lang)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir)
	await process_frame
	var devs := CreditsScreen.developers()
	for dev in devs:
		await _card(dev)
	await _group(devs)
	print("DEV CARDS DONE")
	quit()


static func slug(name: String) -> String:
	var s := name.to_lower().strip_edges()
	var from := "áàâãäéèêëíìîïóòôõöúùûüçñ"
	var to := "aaaaaeeeeiiiiooooouuuucn"
	var out := ""
	for ch in s:
		var i := from.find(ch)
		out += to[i] if i >= 0 else (ch if ch.is_valid_identifier() or ch.is_valid_int() else "_")
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _font(weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(FREDOKA) as Font
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f


# ------------------------------------------------------------------ pieces
## The 2D card: an offscreen viewport with the backdrop, the 3D stage and the texts.
func _canvas(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var bg := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color("#16133d"), Color("#3a2a78"), Color("#7a4f9e")])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 16
	gt.height = 256
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = Vector2(size)
	vp.add_child(bg)
	var sky := StarField.new()
	sky.size = Vector2(size)
	vp.add_child(sky)
	return vp


## A soft round glow (radial gradient) centred at `at`.
func _glow(parent: Node, at: Vector2, radius: float, col: Color) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([col, Color(col, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.size = Vector2(radius, radius) * 2.0
	t.position = at - Vector2(radius, radius)
	parent.add_child(t)


## The 3D stage (transparent) filling `rect` of the card.
func _stage(parent: Node, rect: Rect2) -> Array:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.position = rect.position
	box.size = rect.size
	parent.add_child(box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.size = Vector2i(rect.size)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	box.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.68, 0.92)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1, 0.92, 0.84)
	key.light_energy = 1.25
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 10.0
	vp.add_child(key)
	key.look_at_from_position(Vector3(2.5, 3.5, 3.0), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.25, 0.88, 0.77)
	rim.light_energy = 1.3
	vp.add_child(rim)
	rim.look_at_from_position(Vector3(-2.5, 2.0, -2.5), Vector3.ZERO, Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.75, 0.62, 1.0)
	fill.light_energy = 0.45
	vp.add_child(fill)
	fill.look_at_from_position(Vector3(-3.0, 1.0, 2.0), Vector3.ZERO, Vector3.UP)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.add_child((load(OUTLINE) as PackedScene).instantiate())
	return [vp, cam]


func _cometling(vp: Node, dev: Dictionary, at: Vector3, yaw: float, scale := 1.0) -> Cometling:
	var c := (load(CREATURE) as PackedScene).instantiate() as Cometling
	c.listen_to_events = false
	c.fidgets = false
	c.auto_emotes = false
	c.eye_darts = false
	c.cull_distance = 100.0
	c.personality_seed = absi(hash(String(dev.get("id", "")))) % 1000 + 1
	vp.add_child(c)
	CreditsScreen.dress(c, dev)
	c.position = at
	c.rotation.y = yaw
	c.scale = Vector3.ONE * scale
	c.paused = true
	return c


func _label(parent: Node, text: String, font: Font, size: int, col: Color, rect: Rect2, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = rect.position
	l.size = rect.size
	parent.add_child(l)
	return l


func _frame(parent: Node, size: Vector2i, col: Color) -> void:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(14)
	sb.border_color = col
	sb.set_corner_radius_all(56)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(26, 26)
	p.size = Vector2(size) - Vector2(52, 52)
	parent.add_child(p)


## A small podium (two flat cylinders) under the lead.
func _podium(vp: Node, at: Vector3, radius: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = LILAC
	mat.roughness = 0.8
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = CREAM
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius * 1.08
	m.height = 0.2
	m.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = at + Vector3(0, 0.1, 0)
	vp.add_child(mi)
	var t := CylinderMesh.new()
	t.top_radius = radius * 0.9
	t.bottom_radius = radius * 0.9
	t.height = 0.03
	t.radial_segments = 10
	var ti := MeshInstance3D.new()
	ti.mesh = t
	ti.material_override = top_mat
	ti.position = at + Vector3(0, 0.215, 0)
	vp.add_child(ti)


func _save(vp: SubViewport, file: String) -> void:
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := out_dir.path_join(file)
	var full := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	print("saved ", path, " err=", img.save_png(full))


# ------------------------------------------------------------------ one card
func _card(dev: Dictionary) -> void:
	var vp := _canvas(CARD)
	var stage_rect := Rect2(0, 120, CARD.x, 1240)
	_glow(vp, Vector2(CARD.x * 0.5, 760), 520, Color(LILAC, 0.35))
	var st := _stage(vp, stage_rect)
	var svp: SubViewport = st[0]
	var cam: Camera3D = st[1]
	var c := _cometling(svp, dev, Vector3.ZERO, 0.32)
	cam.fov = 30.0
	cam.look_at_from_position(Vector3(0.62, 0.98, 3.05), Vector3(0.02, 0.44, 0), Vector3.UP)
	c.play("wave")
	c.advance(0.75)
	var big := _font(650)
	var small := _font(500)
	var name_text := String(dev.get("name", ""))
	_label(vp, name_text, big, 132, CREAM, Rect2(60, 1330, CARD.x - 120, 170), 18)
	_label(vp, CreditsScreen.role_text(dev), small, 54, Color("#cfc3ff"), Rect2(80, 1490, CARD.x - 160, 90), 10)
	_label(vp, String(CreditsScreen.data().get("team", "")).to_upper(), small, 34, Color(CREAM, 0.75),
		Rect2(80, 1588, CARD.x - 160, 50), 8)
	_frame(vp, CARD, Color(CREAM, 0.85))
	await _frames(8)
	_save(vp, slug(name_text) + ".png")
	vp.queue_free()
	await _frames(2)


# ------------------------------------------------------------------ group
func _group(devs: Array[Dictionary]) -> void:
	var vp := _canvas(GROUP)
	var stage_rect := Rect2(0, 60, GROUP.x, 1140)
	_glow(vp, Vector2(GROUP.x * 0.5, 700), 900, Color(LILAC, 0.3))
	var st := _stage(vp, stage_rect)
	var svp: SubViewport = st[0]
	var cam: Camera3D = st[1]
	cam.fov = 30.0
	cam.look_at_from_position(Vector3(0.3, 1.05, 5.0), Vector3(0.3, 0.62, 0), Vector3.UP)
	# the lead in the middle on the podium, the others beside it in data order (as on the
	# credits screen's stage: one to the left, two to the right)
	var slots := [Vector3(-1.05, 0, -0.05), Vector3(0.95, 0, -0.05), Vector3(1.8, 0, -0.45), Vector3(-1.9, 0, -0.45)]
	var yaws := [0.3, -0.3, -0.45, 0.45]
	var placed: Array = []   # [dev, position]
	var k := 0
	for dev in devs:
		if bool(dev.get("lead", false)):
			_podium(svp, Vector3(0, 0, 0.2), 0.5)
			var c := _cometling(svp, dev, Vector3(0, 0.22, 0.2), 0.0, 1.12)
			c.play("wave")
			c.advance(0.75)
			placed.append([dev, Vector3(0, 0, 0.2)])
		elif k < slots.size():
			var c := _cometling(svp, dev, slots[k], yaws[k])
			c.play(["wave", "cheer", "clap", "wave"][k % 4])
			c.advance(0.55 + 0.1 * k)
			placed.append([dev, slots[k]])
			k += 1
	await _frames(4)
	var big := _font(650)
	var small := _font(500)
	for pd: Array in placed:
		var dev: Dictionary = pd[0]
		var p := cam.unproject_position(pd[1] + Vector3(0, 0, 0.3)) + stage_rect.position
		var lead := bool(dev.get("lead", false))
		_label(vp, String(dev.get("name", "")), big, 78 if lead else 66, CREAM,
			Rect2(p.x - 260, p.y + 10, 520, 96), 12)
		_label(vp, CreditsScreen.role_text(dev), small, 34, Color("#cfc3ff"), Rect2(p.x - 260, p.y + 100, 520, 60), 8)
	_label(vp, String(CreditsScreen.data().get("team", "")), big, 96, CREAM, Rect2(0, 1290, GROUP.x, 120), 14)
	_frame(vp, GROUP, Color(CREAM, 0.85))
	await _frames(8)
	_save(vp, "group.png")
	vp.queue_free()
	await _frames(2)


## A seeded sky of dots and four-point sparkles.
class StarField:
	extends Control

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 2026
		var n := int(size.x * size.y / 9000.0)
		for i in n:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y * 0.85)
			var r := rng.randf_range(1.2, 3.2)
			draw_circle(p, r, Color(1, 0.97, 0.9, rng.randf_range(0.35, 0.9)))
		for i in 14:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y * 0.7)
			var s := rng.randf_range(10.0, 26.0)
			var col := Color(1, 0.95, 0.8, 0.9)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.22, -s * 0.22),
				p + Vector2(s, 0), p + Vector2(s * 0.22, s * 0.22), p + Vector2(0, s),
				p + Vector2(-s * 0.22, s * 0.22), p + Vector2(-s, 0), p + Vector2(-s * 0.22, -s * 0.22)]), col)
