extends SceneTree
## Renders the voxel Cometling's head (the engineer with the hard hat) as a transparent PNG
## for the app / site icon (composed by tools/make_icon.py).
## Run windowed: godot --path . --script res://tools/render_icon_head.gd -- <out.png>

const CREATURE := "res://scenes/npc/creature.tscn"
const OUTLINE := "res://scenes/fx/cw_outline.tscn"
const SIZE := 1024


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://icon_head.png"
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.68, 0.9)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(25), 0)), Vector3.ZERO)
	key.light_color = Color(1, 0.92, 0.82)
	key.light_energy = 1.35
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-10), deg_to_rad(-150), 0)), Vector3.ZERO)
	rim.light_color = Color(0.3, 0.92, 0.82)
	rim.light_energy = 1.3
	vp.add_child(rim)
	var c := (load(CREATURE) as PackedScene).instantiate() as Node3D
	c.set("role", "engineer")
	c.set("body_color", Color(1, 0.741, 0.478))
	c.set("spot_color", Color(0.373, 0.69, 0.847))
	c.set("personality_seed", 7)
	c.set("listen_to_events", false)
	c.set("cull_distance", 50.0)
	c.rotation_degrees = Vector3(0, -14, 0)
	vp.add_child(c)
	var sh := c.get_node_or_null("Shadow")
	if sh:
		sh.visible = false
	var cam := Camera3D.new()
	cam.fov = 24.0
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-3), 0, 0)), Vector3(0.0, 0.92, 2.7))
	vp.add_child(cam)
	cam.current = true
	if ResourceLoader.exists(OUTLINE):
		cam.add_child((load(OUTLINE) as PackedScene).instantiate())
	for i in 40:
		await process_frame
	# a few frames apart, keep the one with the eyes open (no blink): the most opaque head
	for i in 6:
		vp.get_texture().get_image().save_png(out.get_basename() + "_%d.png" % i)
		for k in 9:
			await process_frame
	print("RENDERED ", out)
	quit()
