extends SceneTree
## Renders the four-Cometling crew for the Cometlings Crew emblem (tools/make_crew_logo.py)
## as a transparent PNG: an engineer waving, a pilot pointing at the comet, a scientist
## looking up and a ground Cometling cheering, lit warm from the comet (upper left) with a
## teal rim from behind.
## Run windowed: godot --path . --script res://tools/render_crew_group.gd -- <out_dir> [delay]

const CREATURE := "res://scenes/npc/creature.tscn"
const OUTLINE := "res://scenes/fx/cw_outline.tscn"
const SIZE := 2048
## role, body, spots, seed, position, yaw (deg), action ("" = none), loop action
const CREW := [
	["scientist", Color(0.44, 0.85, 0.72), Color(1.0, 0.85, 0.45), 11, Vector3(-1.05, 0.0, -0.35), 28.0, "", "look_up"],
	["pilot", Color(0.70, 0.61, 1.0), Color(1.0, 0.6, 0.72), 3, Vector3(-0.36, 0.0, 0.18), 14.0, "point", ""],
	["engineer", Color(1.0, 0.741, 0.478), Color(0.373, 0.69, 0.847), 7, Vector3(0.38, 0.0, 0.22), -10.0, "wave", ""],
	["ground", Color(0.49, 0.78, 1.0), Color(1.0, 0.82, 0.5), 21, Vector3(1.08, 0.0, -0.3), -26.0, "cheer", ""],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://crew_logo"
	var delay := float(args[1]) if args.size() > 1 else 0.55
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
	env.ambient_light_color = Color(0.55, 0.52, 0.9)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()   # the comet's warm glow, upper left
	key.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-38), deg_to_rad(-38), 0)), Vector3.ZERO)
	key.light_color = Color(1.0, 0.86, 0.62)
	key.light_energy = 1.45
	vp.add_child(key)
	var rim := DirectionalLight3D.new()   # teal night rim from behind
	rim.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-12), deg_to_rad(160), 0)), Vector3.ZERO)
	rim.light_color = Color(0.3, 0.95, 0.85)
	rim.light_energy = 1.6
	vp.add_child(rim)
	var crew: Array[Node3D] = []
	for c in CREW:
		var n := (load(CREATURE) as PackedScene).instantiate() as Node3D
		n.set("role", c[0])
		n.set("body_color", c[1])
		n.set("spot_color", c[2])
		n.set("personality_seed", c[3])
		n.set("listen_to_events", false)
		n.set("cull_distance", 80.0)
		if String(c[7]) != "":
			n.set("start_action", c[7])
		n.position = c[4]
		n.rotation_degrees = Vector3(0, c[5], 0)
		vp.add_child(n)
		var sh := n.get_node_or_null("Shadow")
		if sh:
			sh.visible = false
		crew.append(n)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(6), 0, 0)), Vector3(0.0, 0.55, 5.6))
	vp.add_child(cam)
	cam.current = true
	if ResourceLoader.exists(OUTLINE):
		cam.add_child((load(OUTLINE) as PackedScene).instantiate())
	for i in 40:
		await process_frame
	for i in crew.size():
		var act := String(CREW[i][6])
		if act != "":
			crew[i].call("play", act)
	var t0 := Time.get_ticks_msec()
	var n_shot := 0
	while Time.get_ticks_msec() - t0 < 1800:
		await process_frame
		await process_frame
		await process_frame
		vp.get_texture().get_image().save_png("%s/crew_%02d.png" % [out, n_shot])
		n_shot += 1
	print("RENDERED %d crew frames to %s" % [n_shot, out])
	quit()
