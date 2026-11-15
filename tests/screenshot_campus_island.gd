extends SceneTree
## Screenshots of the campus island and its surroundings (scenes/tycoon/campus.tscn inside
## scenes/tycoon/tycoon_main.tscn) for look development:
##   isl_e<era>_<view>_<day|night>
## views: start (the game camera's own start view), high (straight-ish from above, the whole
## island), north / west / east (low angles from three sides), shore (the beach and the sea up
## close), pad (the launch headland), signs (eye level on a story sign).
## Eras 1, 3 and 5 by default (every lot built at the era's level), day (golden hour, phase 0)
## and night (phase 0.5) of src/tycoon/campus_day_cycle.gd; dusk (0.25) and dawn (0.8) on demand.
## Prints the frame time of the start view (vsync off).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_campus_island.gd -- <out_dir> [eras] [views] [day,dusk,night,dawn]

const VIEWS := {
	"high": [Vector3(8, 210, 120), Vector3(8, 0, 4), 45.0],
	"north": [Vector3(-10, 38, -150), Vector3(6, 0, 0), 42.0],
	"west": [Vector3(-160, 30, 30), Vector3(0, 0, 4), 42.0],
	"east": [Vector3(170, 26, -40), Vector3(20, 0, 10), 42.0],
	"shore": [Vector3(30, 9, 92), Vector3(10, -4, 50), 50.0],
	"pad": [Vector3(100, 24, 70), Vector3(50, 2, 22), 42.0],
	"signs": [Vector3(6, 3.2, 11), Vector3(0, 1.4, 2), 50.0],
}
const PHASES := {"day": 0.0, "dusk": 0.25, "night": 0.5, "dawn": 0.8}

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var eras := [1, 3, 5]
	if args.size() > 1:
		eras = Array(args[1].split(",")).map(func(x: String) -> int: return int(x))
	var views: Array = ["start"] + VIEWS.keys()
	if args.size() > 2:
		views = Array(args[2].split(","))
	var phases: Array = ["day", "night"]
	if args.size() > 3:
		phases = Array(args[3].split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # frame times, not the refresh rate
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(8)
	main.clock.set_speed(0)
	var cam := main.camera
	cam.tour_enabled = false
	await _frames(60)
	var start_xf := cam.global_transform
	var start_fov := cam.fov
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.set_process_unhandled_input(false)
	(main.get_node("UI") as CanvasLayer).visible = false
	var s := main.state
	var era_levels := {1: 1, 2: 2, 3: 3, 4: 3, 5: 3}
	for era: int in eras:
		s.weeks = (era - 1) * 5 * 52 + 10
		for lot: String in s.lot_ids():
			s.buildings[lot] = {"kind": s.lot_kind(lot), "level": era_levels[era], "target": era_levels[era], "weeks_left": 0}
		s.changed.emit()
		for ph: String in phases:
			var cycle := main.get_node_or_null("DayCycle") as CampusDayCycle
			if cycle:
				cycle.force_phase = float(PHASES[ph])
			for v: String in views:
				if v == "start":
					cam.fov = start_fov
					cam.global_transform = start_xf
				else:
					var spec: Array = VIEWS[v]
					cam.fov = spec[2]
					cam.global_transform = Transform3D(Basis.looking_at(spec[1] - spec[0], Vector3.UP), spec[0])
				await _frames(30)
				if v == "start":
					await _measure("era %d %s" % [era, ph])
				await _shot("isl_e%d_%s_%s" % [era, v, ph])
	print("CAMPUS ISLAND SCREENSHOTS DONE")
	quit()


func _measure(label: String) -> void:
	await _frames(10)
	var t0 := Time.get_ticks_usec()
	var n := 120
	for i in n:
		await process_frame
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / n
	print("%s: %.2f ms/frame (%.0f fps), draw calls %d, objects %d" % [label, ms, 1000.0 / ms,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
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
