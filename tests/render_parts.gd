extends SceneTree
## Hangar part renders (docs/hangar_renders/<model>.png) for the parts palette and the PDF catalog.
## Loads each part's .glb from assets/voxel/parts/, frames it with a 3/4 camera and two lights in
## an isolated SubViewport (transparent background), crops to the model, and saves it on the
## dark render background used by tools/make_part_icons.py (#0F1524).
## Run (windowed, needs a GPU):
##   godot --path . --resolution 1600x900 --script res://tests/render_parts.gd -- <out_dir> <model=part_id> ...
## Each argument is "model=part_id" (render part_id, save as <model>.png) or a bare part id
## (saved under its catalog model name). An optional "@<pitch deg>" suffix changes the camera
## pitch for that render, e.g. "heat_shield=heat_shield_m@-28" to show a part from below.

const BG := Color8(15, 21, 36)
const SIZE := 1024
const PAD := 14
const YAW_DEG := 35.0
const PITCH_DEG := 20.0
const FOV := 28.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <out_dir> <model=part_id> ...")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.66, 0.9)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.1
	key.light_color = Color(1.0, 0.97, 0.92)
	key.rotation_degrees = Vector3(-38, 58, 0)
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.85, 1.0)
	fill.rotation_degrees = Vector3(-15, -120, 0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = FOV
	vp.add_child(cam)
	cam.current = true
	var holder := Node3D.new()
	vp.add_child(holder)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/parts.json"))
	var models := {}
	for p in data["parts"]:
		models[p["id"]] = p["model"]
	for i in range(1, args.size()):
		var a: String = args[i]
		var model := ""
		var pid := a
		var pitch := PITCH_DEG
		if a.contains("@"):
			pitch = float(a.get_slice("@", 1))
			a = a.get_slice("@", 0)
			pid = a
		if a.contains("="):
			model = a.get_slice("=", 0)
			pid = a.get_slice("=", 1)
		else:
			model = models.get(pid, pid)
		var path := "res://assets/voxel/parts/%s.glb" % pid
		if not ResourceLoader.exists(path):
			push_error("missing " + path)
			continue
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var bb := _aabb(inst)
		_frame(cam, bb, pitch)
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		_save(img, "%s/%s.png" % [out_dir, model])
		print("rendered %-22s <- %-22s size %s" % [model, pid, bb.size])
		inst.queue_free()
		await process_frame
	print("RENDER PARTS DONE")
	quit()


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b: AABB = m.global_transform * m.get_aabb() if m.is_inside_tree() else m.transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _frame(cam: Camera3D, bb: AABB, pitch_deg: float) -> void:
	var c := bb.get_center()
	var r := bb.size.length() * 0.5
	var yaw := deg_to_rad(YAW_DEG)
	var pitch := deg_to_rad(pitch_deg)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var dist := r / sin(deg_to_rad(FOV) * 0.5) * 1.02
	cam.near = maxf(dist * 0.01, 0.01)
	cam.far = dist * 4.0
	cam.look_at_from_position(c + dir * dist, c, Vector3.UP)


func _save(img: Image, path: String) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size.x <= 0:
		push_error("empty render " + path)
		return
	var out := Image.create(used.size.x + PAD * 2, used.size.y + PAD * 2, false, Image.FORMAT_RGBA8)
	out.fill(BG)
	out.blend_rect(img, used, Vector2i(PAD, PAD))
	out.convert(Image.FORMAT_RGB8)
	out.save_png(path)
