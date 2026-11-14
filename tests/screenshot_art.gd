extends SceneTree
## Art review captures for the hangar environment (windowed): loads the hangar with the
## Garça example and saves a set of camera angles (with and without UI), a render of the
## MARGIN emblem texture, and prints draw calls / FPS per shot.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_art.gd -- <out_dir>

var out_dir := "user://"
var hangar: Node


func _initialize() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out_dir = OS.get_cmdline_user_args()[0]
	hangar = (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(10)
	hangar.load_example("garca")
	await _frames(20)
	var cam: HangarCamera = hangar.cam
	var ui: CanvasLayer = hangar.get_node("UI")
	var d0 := cam.distance
	var f0 := cam.focus
	var y0 := cam.yaw
	var p0 := cam.pitch
	# [name, focus, yaw deg, pitch deg, distance, ui]
	var shots := [
		["art_default", f0, rad_to_deg(y0), rad_to_deg(p0), d0, true],
		["art_default_clean", f0, rad_to_deg(y0), rad_to_deg(p0), d0, false],
		["art_hero_low", Vector3(0, 24, 0), 32.0, 4.0, 62.0, false],
		["art_door_view", Vector3(-12, 20, -40), 8.0, 2.0, 70.0, false],
		["art_emblem_wall", Vector3(-58, 34, -22), 90.0, 6.0, 60.0, false],
		["art_banner", Vector3(-50, 34, -58), 25.0, 4.0, 52.0, false],
		["art_wide", Vector3(0, 32, 0), 28.0, 18.0, 105.0, true],
		["art_cutaway_far", Vector3(0, 30, -40), 35.0, 24.0, 260.0, false],
		["art_outside_site", Vector3(-120, 40, -700), 20.0, 12.0, 260.0, false],
		["art_top_down", Vector3(0, 0, 0), 20.0, 70.0, 150.0, false],
		["art_reverse", Vector3(0, 24, 0), 200.0, 8.0, 70.0, false],
	]
	for s in shots:
		cam.focus = s[1]
		cam.yaw = deg_to_rad(s[2])
		cam.pitch = deg_to_rad(s[3])
		cam.distance = s[4]
		cam._apply()
		ui.visible = s[5]
		await _frames(16)
		var t0 := Time.get_ticks_usec()
		await _frames(30)
		var fps := 30.0 / ((Time.get_ticks_usec() - t0) / 1000000.0)
		var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var objs := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		print("%s: draw_calls=%d objects=%d primitives=%d fps=%.1f" % [s[0], dc, objs, prims, fps])
		_shot(s[0])
	var tex: Texture2D = load("res://ui/kit/emblem_margin.svg")
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.save_png("%s/emblem_margin.png" % out_dir)
	print("ART SHOTS DONE")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	get_root().get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])
