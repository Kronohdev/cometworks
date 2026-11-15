extends SceneTree
## FPS of the graphics levels (GraphicsQuality: Baixo / Médio / Alto) on the campus and at the
## Conferência dos Cometinhos fair, windowed with vsync off, plus a screenshot of each level on
## the campus (quality_campus_<level>.png). The player's saved level is put back at the end.
## Run: godot --path . --resolution 1600x900 --script res://tests/bench_quality.gd -- <out_dir> [seconds]

const LEVELS := [GraphicsQuality.Level.LOW, GraphicsQuality.Level.MEDIUM, GraphicsQuality.Level.HIGH]
const NAMES := ["baixo", "medio", "alto"]

var out_dir := "user://"
var seconds := 6.0
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		seconds = float(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var saved := GraphicsQuality.current()
	TranslationServer.set_locale("pt_BR")
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.race_flow.autosave = false
	main.camera.tour_enabled = false
	main.clock.set_speed(0)
	if main.tutorial:
		main.tutorial.visible = false
	while main.hud.current_screen() != "":
		main.hud.close_screen()
		await _frames(2)
	await _wait(2.0)
	print("GPU: %s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
	print("window %s, render scale per level" % [DisplayServer.window_get_size()])
	var res := {}
	for i in LEVELS.size():
		GraphicsQuality.set_level(LEVELS[i])
		await _wait(1.5)
		res["campus " + NAMES[i]] = await _measure()
		await _shot("quality_campus_" + NAMES[i])
	main.conference.dev_open()
	var fair := main.conference.fair
	if fair:
		fair.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(2.5)
	for i in LEVELS.size():
		GraphicsQuality.set_level(LEVELS[i])
		await _wait(1.5)
		res["fair " + NAMES[i]] = await _measure()
		await _shot("quality_fair_" + NAMES[i])
	for k: String in res:
		var r: Dictionary = res[k]
		print("FPS %-13s avg %6.1f  frame median %6.2f ms  p95 %6.2f ms  | GPU %6.2f ms  CPU (process + render submit) %6.2f ms"
			% [k, r["fps"], r["median_ms"], r["p95_ms"], r["gpu_ms"], r["cpu_ms"]])
	GraphicsQuality.set_level(saved)
	print("BENCH DONE")
	quit()


## Average FPS over `seconds`, the median and the 95th-percentile frame time.
func _measure() -> Dictionary:
	var times: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var vp := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < int(seconds * 1e6):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		last = now
	var total := (last - t0) / 1e6
	times.sort()
	gpu.sort()
	cpu.sort()
	return {"fps": times.size() / total, "median_ms": times[times.size() / 2],
		"p95_ms": times[int(times.size() * 0.95)], "gpu_ms": gpu[gpu.size() / 2], "cpu_ms": cpu[cpu.size() / 2]}


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout
