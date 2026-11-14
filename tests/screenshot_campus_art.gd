extends SceneTree
## Look-development screenshots of the campus art (scenes/tycoon/campus.tscn inside
## scenes/tycoon/tycoon_main.tscn) from fixed cameras, plus frame timings:
##   art_e<era>_<view>   views: game (the default game camera), sky (low, towards the comet),
##                       shore (the sea and the beach), close (eye level on the plaza),
##                       pad (the launch pads), padclose (low, at the first pad)
## for eras 1, 3 and 5 (every lot built at the era's level). Prints the average CPU / GPU
## frame time of the game view per era.
## An optional fourth argument picks day-cycle phases (src/tycoon/campus_day_cycle.gd:
## 0 golden hour, 0.25 dusk, 0.5 night, 0.8 dawn); shots are then named art_e<era>_<view>_p<phase>.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_campus_art.gd -- <out_dir> [eras] [views] [phases]
##   e.g. -- out 1,5 game,sky 0,0.5

const VIEWS := {
	"game": [Vector3(70, 70, 95), Vector3(4, 0, 2), 31.0],
	"sky": [Vector3(46, 7, 46), Vector3(-30, 30, -60), 52.0],
	"shore": [Vector3(110, 14, 92), Vector3(50, -6, 40), 45.0],
	"close": [Vector3(9, 2.2, 13), Vector3(0, 1.5, 2), 50.0],
	"pad": [Vector3(70, 22, 58), Vector3(44, 3, 18), 40.0],
	"padclose": [Vector3(50, 5, 42), Vector3(38, 4, 21), 50.0],
}

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var eras := [1, 3, 5]
	if args.size() > 1:
		eras = Array(args[1].split(",")).map(func(x: String) -> int: return int(x))
	var views: Array = VIEWS.keys()
	if args.size() > 2:
		views = Array(args[2].split(","))
	var phases := [-1.0]
	if args.size() > 3:
		phases = Array(args[3].split(",")).map(func(x: String) -> float: return float(x))
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(5)
	main.clock.set_speed(0)
	var cam := main.camera
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.set_process_unhandled_input(false)
	cam.attributes = null
	(main.get_node("UI") as CanvasLayer).visible = false
	var s := main.state
	var era_levels := {1: 1, 2: 2, 3: 3, 4: 3, 5: 3}
	for era: int in eras:
		s.weeks = (era - 1) * 5 * 52 + 10
		for lot: String in s.lot_ids():
			s.buildings[lot] = {"kind": s.lot_kind(lot), "level": era_levels[era], "target": era_levels[era], "weeks_left": 0}
		s.changed.emit()
		for ph: float in phases:
			var cycle := main.get_node_or_null("DayCycle") as CampusDayCycle
			if cycle and ph >= 0.0:
				cycle.force_phase = ph
			for v: String in views:
				var spec: Array = VIEWS[v]
				cam.fov = spec[2]
				cam.global_transform = Transform3D(Basis.looking_at(spec[1] - spec[0], Vector3.UP), spec[0])
				await _frames(40)
				if v == "game":
					await _measure("era %d" % era)
				var suffix := "" if ph < 0.0 else "_p%02d" % int(round(ph * 100.0))
				await _shot("art_e%d_%s%s" % [era, v, suffix])
	print("CAMPUS ART SCREENSHOTS DONE")
	quit()


func _measure(label: String) -> void:
	var vp := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _frames(10)
	var cpu := 0.0
	var gpu := 0.0
	var proc := 0.0
	var n := 90
	for i in n:
		await process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("%s: render cpu %.2f ms, gpu %.2f ms, process %.2f ms, draw calls %d, objects %d" % [label, cpu / n, gpu / n,
		proc / n, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
