extends SceneTree
## Windowed screenshots of Mãe-Gelo, the comet prop (scenes/menu/props/comet_mae_gelo.tscn) in the
## cutscenes' space set (scenes/cutscenes/sets/space_comet.tscn), from fixed cameras:
##   comet_wide      the opening's framing: the whole comet, tails across the sky
##   comet_side      side-on, the two tails apart (curved dust, straight ion)
##   comet_close     the probe's view in the ending: the nucleus, jets and coma up close
##   comet_face      the same, her face on (the story shots turn it on)
##   comet_campus    the big comet over a dark sky, nucleus hidden (the ending's campus shots)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_comet.gd -- <out_dir> [names]

var out_dir := "user://comet"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var only: Array = Array(args[1].split(",")) if args.size() > 1 else []
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	var set_ps := load("res://scenes/cutscenes/sets/space_comet.tscn") as PackedScene
	var root := set_ps.instantiate() as Node3D
	get_root().add_child(root)
	(root.get_node("Jupiter") as Node3D).visible = false
	var comet := root.get_node("Comet") as Node3D
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true
	await _frames(2)
	var face := comet.get_node("Nucleus/Face") as Node3D
	var shots := {
		"comet_wide": [Vector3(0, 0, 0), comet.global_position + Vector3(8, 3, 0), 40.0, false],
		"comet_side": [comet.global_position + Vector3(10, 34, 26), comet.global_position + Vector3(12, 2, 0), 50.0, false],
		"comet_close": [comet.global_position + comet.global_basis * Vector3(-1.2, 0.5, 2.6), comet.global_position, 40.0, false],
		"comet_face": [comet.global_position + comet.global_basis * Vector3(-0.2, 0.0, 2.4), comet.global_position + comet.global_basis * Vector3(0.0, 0.05, 0.0), 40.0, true],
	}
	for n: String in shots:
		if not only.is_empty() and not n in only:
			continue
		var s: Array = shots[n]
		cam.fov = s[2]
		cam.global_position = s[0]
		cam.look_at(s[1], Vector3.UP)
		face.visible = s[3]
		await _frames(30)
		await _shot(n)
	if only.is_empty() or "comet_campus" in only:
		comet.get_node("Nucleus").visible = false
		comet.global_transform = Transform3D(Basis.from_euler(Vector3(0.2, 0.5, 0.75)).scaled(Vector3(4.5, 4.5, 4.5)), Vector3(7, 15, -62))
		cam.fov = 60.0
		cam.global_position = Vector3(0, 1.6, 4)
		cam.look_at(Vector3(4, 14, -40), Vector3.UP)
		await _frames(30)
		await _shot("comet_campus")
	print("COMET SCREENSHOTS DONE")
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
