extends SceneTree
## Renders the waving Cometling for the Cometlings Crew emblem (tools/make_crew_logo.py) as
## transparent PNGs, one per frame of the wave.
## Run windowed: godot --path . --script res://tools/render_crew_cometling.gd -- <out_dir>

const CREATURE := "res://scenes/npc/creature.tscn"
const OUTLINE := "res://scenes/fx/cw_outline.tscn"
const SIZE := 1024


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://crew_logo"
	DirAccess.make_dir_recursive_absolute(out)
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
	env.ambient_light_color = Color(0.62, 0.66, 0.85)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-35), deg_to_rad(30), 0)), Vector3(0, 3, 2))
	key.light_color = Color(1, 0.9, 0.8)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-15), deg_to_rad(-135), 0)), Vector3(0, 3, -2))
	rim.light_color = Color(0.25, 0.88, 0.77)
	rim.light_energy = 1.1
	vp.add_child(rim)
	var c := (load(CREATURE) as PackedScene).instantiate() as Node3D
	c.set("role", "engineer")
	c.set("body_color", Color(1, 0.741, 0.478))
	c.set("spot_color", Color(0.373, 0.69, 0.847))
	c.set("personality_seed", 7)
	c.set("listen_to_events", false)
	c.set("cull_distance", 50.0)
	c.rotation_degrees = Vector3(0, -12, 0)
	vp.add_child(c)
	var sh := c.get_node_or_null("Shadow")
	if sh:
		sh.visible = false
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-4), 0, 0)), Vector3(0.05, 0.78, 3.4))
	vp.add_child(cam)
	cam.current = true
	if ResourceLoader.exists(OUTLINE):
		cam.add_child((load(OUTLINE) as PackedScene).instantiate())
	for i in 30:
		await process_frame
	c.call("play", "wave")
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 2200:
		await process_frame
		await process_frame
		var img := vp.get_texture().get_image()
		img.save_png("%s/wave_%02d.png" % [out, n])
		n += 1
	print("RENDERED %d frames to %s" % [n, out])
	quit()
