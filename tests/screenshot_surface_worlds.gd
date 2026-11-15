extends SceneTree
## Shots of the playable surfaces (scenes/surface/<body>_surface.tscn, with their landforms,
## points of interest, collectibles and challenges) seen through their fly camera, plus the
## explore layer (discovery card, log, challenge) and photo mode.
## With "perf" it also flies the drone low over each world for 10 s with vsync off and prints
## the FPS (average and 1% low), chunk generation time and triangles (content included).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_surface_worlds.gd -- <out_dir> [ids|all] [perf]

const BODIES := ["moon", "mars", "europa", "mercury", "earth"]
## per body: [shot name, camera x, z, height above ground, look x, z, look height above ground]
const POSES := {
	"moon": [["site", -40.0, 70.0, 9.0, 60.0, -20.0, 3.0], ["crater", 70.0, 10.0, 26.0, 170.0, -45.0, -6.0],
		["homage", -86.0, 76.0, 4.5, -112.0, 58.0, 1.0], ["rille", 40.0, -110.0, 30.0, -60.0, -200.0, -4.0],
		["vista", -260.0, 230.0, 140.0, 40.0, -40.0, 0.0]],
	"mars": [["site", -40.0, 70.0, 9.0, 80.0, -40.0, 6.0], ["buttes", 60.0, -10.0, 14.0, 150.0, -60.0, 12.0],
		["homage", -96.0, 82.0, 4.5, -120.0, 64.0, 1.0], ["channel", -30.0, 160.0, 26.0, 90.0, 230.0, -2.0],
		["vista", -260.0, 230.0, 140.0, 40.0, -40.0, 0.0]],
	"europa": [["site", -40.0, 70.0, 9.0, 60.0, -40.0, 4.0], ["chaos", -90.0, -100.0, 30.0, -190.0, -200.0, 0.0],
		["plume", 100.0, 120.0, 14.0, 165.0, 185.0, 20.0], ["ridge", 30.0, -60.0, 12.0, -40.0, -150.0, 3.0],
		["vista", -260.0, 230.0, 140.0, 40.0, -40.0, 0.0]],
	"mercury": [["site", -40.0, 70.0, 9.0, 60.0, -40.0, 4.0], ["vista", -260.0, 230.0, 140.0, 40.0, -40.0, 0.0]],
	"earth": [["site", -40.0, 70.0, 9.0, 60.0, -40.0, 4.0], ["vista", -260.0, 230.0, 140.0, 40.0, -40.0, 0.0]],
}

var out_dir := "user://"
var perf := false
var surf: PlanetSurface
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only: PackedStringArray = args[1].split(",") if args.size() > 1 and args[1] != "all" else PackedStringArray()
	perf = "perf" in args
	TranslationServer.set_locale("pt")
	for id: String in BODIES:
		if not only.is_empty() and not (id in only):
			continue
		await _body(id)
	print("SHOTS DONE")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_idle(max_s := 25.0) -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(4)
	while (Time.get_ticks_msec() - t0) / 1000.0 < max_s:
		await process_frame
		if Time.get_ticks_msec() - t0 > 600 and surf.terrain.is_idle():
			break
	await _frames(20)


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


func _body(id: String) -> void:
	var path := "res://scenes/surface/%s_surface.tscn" % id
	surf = (load(path) as PackedScene).instantiate() as PlanetSurface
	get_root().add_child(surf)
	await _frames(3)
	cam = get_root().get_camera_3d()
	var explore := surf.get_node_or_null("Explore")
	if explore and explore.has_method("set_ui_visible"):
		explore.call("set_ui_visible", false)
	for pose: Array in POSES.get(id, []):
		var g := surf.ground_height(pose[1], pose[2])
		cam.global_position = Vector3(pose[1], g + pose[3], pose[2])
		var lg := surf.ground_height(pose[4], pose[5])
		var target := Vector3(pose[4], lg + pose[6], pose[5])
		if cam.has_method("look_toward"):
			cam.call("look_toward", target)
		else:
			cam.look_at(target)
		await _wait_idle()
		_shot("%s_%s" % [id, pose[0]])
	if perf:
		await _flight(id)
	surf.queue_free()
	await _frames(3)


func _flight(id: String) -> void:
	var start := Vector3(-150.0, 0.0, 150.0)
	var dir := Vector3(1.0, 0.0, -1.0).normalized()
	cam.global_position = start + Vector3(0, surf.ground_height(start.x, start.z) + 20.0, 0)
	cam.call("look_toward", cam.global_position + dir * 10.0 + Vector3(0, -2.5, 0))
	await _wait_idle()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var times: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	var gen0: int = surf.terrain.gen_count
	while Time.get_ticks_usec() - t0 < 10_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1.0e6
		last = now
		times.append(dt)
		var p := cam.global_position + dir * 30.0 * dt
		p.y = lerpf(p.y, surf.ground_height(p.x, p.z) + 20.0, 0.05)
		cam.global_position = p
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var total := 0.0
	for t in times:
		total += t
	var sorted := times.duplicate()
	sorted.sort()
	var worst := sorted.slice(int(sorted.size() * 0.99))
	var w := 0.0
	for t in worst:
		w += t
	w /= maxf(worst.size(), 1)
	var st := surf.terrain.get_stats()
	print("FLIGHT %s %s" % [id, JSON.stringify({"avg_fps": snappedf(times.size() / total, 0.1),
		"one_percent_low_fps": snappedf(1.0 / w, 0.1), "chunks_generated": surf.terrain.gen_count - gen0,
		"gen_ms_avg": snappedf(float(st["gen_ms_avg"]), 0.01), "tris": st["tris"],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"gpu": RenderingServer.get_video_adapter_name()})])
