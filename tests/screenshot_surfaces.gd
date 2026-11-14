extends SceneTree
## Visual + performance check of the voxel planet surfaces (opens a window).
## For every profile of scenes/surface/surface_demo.tscn: waits for streaming to
## finish, saves a landing-site shot and a vista shot (HUD hidden), plus HUD
## shots (PT and EN), an LOD-rings shot, then flies over Earth and the Moon with
## vsync off and reports FPS, chunk generation time, triangles and memory.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_surfaces.gd -- <out_dir> [ids|all] [maps] [jobs=N]
##   ids: comma-separated subset (e.g. moon,mars); "maps" (headless OK) only writes
##   top-down 2 km terrain maps for quick tuning.

var out_dir := "user://"
var demo: SurfaceDemo
var summary := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only: PackedStringArray = []
	if args.size() > 1 and args[1] != "all" and args[1] != "maps":
		only = args[1].split(",")
	var jobs := 0
	for a in args:
		if a.begins_with("jobs="):
			jobs = int(a.substr(5))
	if "maps" in args:
		_maps(only)
		quit()
		return
	demo = (load("res://scenes/surface/surface_demo.tscn") as PackedScene).instantiate() as SurfaceDemo
	get_root().add_child(demo)
	await _frames(3)
	if jobs > 0:
		demo.planet.terrain.max_jobs_in_flight = jobs
	summary["jobs_in_flight"] = demo.planet.terrain._max_jobs()
	TranslationServer.set_locale("en")
	for i in demo.profiles.size():
		var p := demo.profiles[i]
		if not only.is_empty() and not (String(p.id) in only):
			continue
		await _shots_for(i)
	if only.is_empty() or "earth" in only:
		await _hud_shots()
		await _lod_shot()
		await _perf_flight(0, "earth")
	if only.is_empty() or "moon" in only:
		await _perf_flight(1, "moon")
	var f := FileAccess.open(out_dir.path_join("perf_summary.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	print("SUMMARY ", JSON.stringify(summary))
	print("SHOTS DONE")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_idle(max_s: float = 25.0) -> float:
	var t0 := Time.get_ticks_msec()
	await _frames(4)
	while (Time.get_ticks_msec() - t0) / 1000.0 < max_s:
		await process_frame
		if Time.get_ticks_msec() - t0 > 500 and demo.planet.terrain.is_idle():
			break
	return (Time.get_ticks_msec() - t0) / 1000.0


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


## Camera `dist` m from the site, `alt` m above the ground, looking along
## azimuth `az` (deg) with pitch `pitch` (deg).
func _pose(az: float, dist: float, alt: float, pitch: float, side: float = 0.0) -> void:
	var a := deg_to_rad(az)
	var fwd := Vector3(sin(a), 0.0, cos(a))
	var right := fwd.cross(Vector3.UP)
	var pos := -fwd * dist + right * side
	var g := demo.planet.ground_height(pos.x, pos.z)
	demo.camera.global_position = Vector3(pos.x, g + alt, pos.z)
	var p := deg_to_rad(pitch)
	demo.camera.look_toward(demo.camera.global_position + Vector3(fwd.x * cos(p), sin(p), fwd.z * cos(p)))


func _shots_for(i: int) -> void:
	demo.select_planet(i)
	demo.hud.visible = false
	var p := demo.profiles[i]
	var id := String(p.id)
	# look across the sun direction for long, readable shadows
	var az := _shot_azimuth(p)
	_pose(az, 75.0, 22.0, -13.0)
	var t := await _wait_idle()
	await _frames(20)
	var st := demo.planet.terrain.get_stats()
	summary[id + "_load"] = {"seconds": t, "chunks": st["chunks"], "tris": st["tris"], "naive_tris": st["naive_tris"],
		"gen_ms_avg": st["gen_ms_avg"]}
	_shot(id + "_site")
	_pose(az + 20.0, 260.0, 160.0, -9.0)
	await _wait_idle()
	await _frames(20)
	_shot(id + "_vista")


## Look across the sun for long, readable shadows; toward the sky body if any;
## Earth looks east, toward the coast.
func _shot_azimuth(p: PlanetSurfaceProfile) -> float:
	if p.id == &"earth":
		return 80.0
	if p.sky_body_enabled:
		return p.sky_body_azimuth_deg + 25.0
	return p.sun_azimuth_deg + 115.0


func _hud_shots() -> void:
	demo.select_planet(0)
	demo.hud.visible = true
	TranslationServer.set_locale("pt")
	_pose(_shot_azimuth(demo.profiles[0]), 75.0, 22.0, -13.0)
	await _wait_idle()
	await _frames(30)
	_shot("hud_earth_pt")
	demo.select_planet(2)
	TranslationServer.set_locale("en")
	_pose(demo.profiles[2].sun_azimuth_deg + 115.0, 75.0, 22.0, -13.0)
	await _wait_idle()
	await _frames(30)
	_shot("hud_mars_en")


func _lod_shot() -> void:
	demo.select_planet(1)
	demo.hud.visible = false
	demo.set_lod_view(true)
	_pose(30.0, 900.0, 700.0, -38.0)
	await _wait_idle()
	await _frames(20)
	_shot("lod_rings_moon")
	demo.set_lod_view(false)


func _perf_flight(i: int, id: String) -> void:
	demo.select_planet(i)
	demo.hud.visible = true
	var p := demo.profiles[i]
	var az := p.sun_azimuth_deg + 115.0
	_pose(az, 0.0, 30.0, -8.0)
	await _wait_idle()
	await _frames(30)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var a := deg_to_rad(az)
	var fwd := Vector3(sin(a), 0.0, cos(a))
	var speed := 40.0
	var times: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	var gen0: int = demo.planet.terrain.gen_count
	while Time.get_ticks_usec() - t0 < 12_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1.0e6
		last = now
		times.append(dt)
		var pos := demo.camera.global_position + fwd * speed * dt
		var g := demo.planet.ground_height(pos.x, pos.z)
		pos.y = lerpf(pos.y, maxf(g + 30.0, pos.y - 2.0 * dt), 0.05)
		demo.camera.global_position = pos
	var total := 0.0
	for t in times:
		total += t
	var sorted := times.duplicate()
	sorted.sort()
	var worst := sorted.slice(int(sorted.size() * 0.99))
	var w_avg := 0.0
	for t in worst:
		w_avg += t
	w_avg /= maxf(worst.size(), 1)
	var st := demo.planet.terrain.get_stats()
	var res := {
		"avg_fps": times.size() / total,
		"one_percent_low_fps": 1.0 / w_avg,
		"frames": times.size(),
		"distance_m": speed * total,
		"chunks_generated_in_flight": demo.planet.terrain.gen_count - gen0,
		"chunks": st["chunks"], "tris": st["tris"], "naive_tris": st["naive_tris"],
		"gen_ms_avg": st["gen_ms_avg"],
		"mem_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"gpu": RenderingServer.get_video_adapter_name(),
	}
	summary[id + "_flight"] = res
	print("FLIGHT %s %s" % [id, JSON.stringify(res)])
	_shot(id + "_flight_hud")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


## Top-down 2 km maps (4 m columns) with hillshade, for tuning profiles.
func _maps(only: PackedStringArray) -> void:
	for f in DirAccess.get_files_at("res://resources/planets"):
		if not f.ends_with(".tres"):
			continue
		var p := load("res://resources/planets/" + f) as PlanetSurfaceProfile
		if not only.is_empty() and not (String(p.id) in only):
			continue
		var gen := VoxelTerrainGenerator.new(p)
		var s := 4.0
		var tiles := 16
		var n := 32
		var size := tiles * n
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		var hmap := PackedFloat32Array()
		hmap.resize(size * size)
		var tmap := PackedInt32Array()
		tmap.resize(size * size)
		var half := size * s * 0.5
		for tz in tiles:
			for tx in tiles:
				var d := gen.sample_chunk(-half + tx * n * s, -half + tz * n * s, s, n)
				var hs: PackedInt32Array = d["heights"]
				var tp: PackedInt32Array = d["tops"]
				for j in n:
					for i in n:
						var k := (j + 1) * (n + 2) + i + 1
						var o := (tz * n + j) * size + tx * n + i
						hmap[o] = hs[k] * s
						tmap[o] = tp[k]
		var sun := p.sun_direction()
		var hmin := 1e9
		var hmax := -1e9
		for y in size:
			for x in size:
				var o := y * size + x
				hmin = minf(hmin, hmap[o])
				hmax = maxf(hmax, hmap[o])
				var hx := hmap[o + 1] - hmap[o - 1] if x > 0 and x < size - 1 else 0.0
				var hz := hmap[o + size] - hmap[o - size] if y > 0 and y < size - 1 else 0.0
				var nrm := Vector3(-hx / (2.0 * s), 1.0, -hz / (2.0 * s)).normalized()
				var lit := clampf(nrm.dot(sun), 0.0, 1.0) * 0.8 + 0.3
				var c: Color = gen.palette[tmap[o]].linear_to_srgb()
				if gen.has_sea and hmap[o] < gen.sea_level:
					c = c.lerp(p.water_deep_color, clampf((gen.sea_level - hmap[o]) / 8.0, 0.3, 0.9))
				img.set_pixel(x, y, Color(c.r * lit, c.g * lit, c.b * lit))
		img.set_pixel(size / 2, size / 2, Color.RED)
		var path := out_dir.path_join(String(p.id) + "_map.png")
		img.save_png(path)
		print("map %s: h %.0f..%.0f m (flat zone %.1f m) -> %s" % [p.id, hmin, hmax, gen.flat_height, path])
