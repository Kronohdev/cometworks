extends SceneTree
## Windowed screenshots of the campus' visual life (scenes/tycoon/fx/, src/tycoon/fx/) on the
## Cometworks main screen, HUD hidden, from fixed cameras, every building busy:
##   fx_e<era>_overview        the game view: smoke, signal rings, crane, flag, cloud shadows
##   fx_e<era>_<kind>          one building close up (cutaway open: sparks, beakers, screens)
##   fx_e<era>_rain / _rain_close   rain over the campus, from the game view and at eye level
##   fx_e<era>_night_sky       night, low towards the comet, a shooting star crossing
##   fx_e<era>_night           the game view at night (fireflies, lit effects)
##   fx_e<era>_works           a lot being built (dust, sparks, beacon)
##   fx_e<era>_levelup         the level-up pop over a building
##   fx_e<era>_celebrate       a first in the race: fireworks over the plaza, Cometlings cheering
##   fx_e<era>_birds           birds on a lamp head (and fx_e<era>_birds_fled: the camera came close)
## Prints the frame time of the game view with every effect on (vsync off).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_campus_fx.gd -- <out_dir> [eras] [shots]
##   eras: comma list (default 1,5); shots: comma list of the names above without the prefix (default all)

const KINDS := ["factory", "workshop", "lab", "antenna", "control", "hq", "training"]

var out_dir := "user://"
var main: TycoonMain
var cam: Camera3D
var fx: CampusEffects
var shots: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var eras := [1, 5]
	if args.size() > 1:
		eras = Array(args[1].split(",")).map(func(x: String) -> int: return int(x))
	if args.size() > 2:
		shots = Array(args[2].split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	MenuSettings.set_weather(true)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(5)
	main.clock.set_speed(0)
	(main.get_node("UI") as CanvasLayer).visible = false
	var main_cam := main.get_node("Camera") as Camera3D
	main_cam.set_process(false)
	main_cam.set_process_input(false)
	main_cam.set_process_unhandled_input(false)
	cam = Camera3D.new()
	cam.fov = 34.0
	cam.far = 1600.0
	main.add_child(cam)
	cam.current = true
	fx = main.get_node("Effects") as CampusEffects
	fx.busy_activity = 1.0
	main.state.staff[0]["assigned"] = "screenshot"   # a project running: every building busy
	var cycle := main.get_node("DayCycle") as CampusDayCycle
	var s := main.state
	for era: int in eras:
		cycle.force_phase = 0.12
		_set_campus(s, era)
		fx.weather.set_kind("cloudy")
		_clouds_now()
		await _frames(30)
		_busy()
		if _want("overview"):
			_place(Vector3(4, 0, 2), 38.0, 40.0, 120.0)
			await _frames(90)
			await _shot("fx_e%d_overview" % era)
		for kind: String in KINDS:
			if not _want(kind):
				continue
			var lot := _lot_of(s, kind)
			var b := main.campus.building_node(lot)
			if b == null:
				continue
			var size: Vector2 = main.campus.lots.get_node(lot).get_meta("size", Vector2(16, 12))
			var yaw := 38.0 + (180.0 if absf(b.rotation.y) > 1.0 else 0.0)
			_place(b.global_position, yaw, 40.0, maxf(size.x, size.y) * 1.5 + 6.0)
			await _frames(70)
			await _shot("fx_e%d_%s" % [era, kind])
		if _want("rain"):
			fx.weather.set_kind("rain")
			fx.weather.rain_amount = 1.0
			_clouds_now()
			_place(Vector3(4, 0, 2), 38.0, 40.0, 120.0)
			await _frames(60)
			await _shot("fx_e%d_rain" % era)
			cam.global_position = Vector3(9, 2.4, 14)
			cam.look_at(Vector3(0, 1.8, 2), Vector3.UP)
			cam.near = 0.1
			await _frames(40)
			await _shot("fx_e%d_rain_close" % era)
			fx.weather.set_kind("clear")
			fx.weather.rain_amount = 0.0
		if _want("night"):
			cycle.force_phase = 0.5
			await _frames(10)
			_place(Vector3(4, 0, 2), 38.0, 40.0, 120.0)
			await _frames(40)
			await _shot("fx_e%d_night" % era)
			cam.global_position = Vector3(46, 7, 46)
			cam.look_at(Vector3(-30, 30, -60), Vector3.UP)
			cam.fov = 52.0
			await _frames(5)
			fx.weather.shoot_star()
			await _frames(18)
			await _shot("fx_e%d_night_sky" % era)
			cam.fov = 34.0
			cycle.force_phase = 0.12
		if _want("works"):
			s.buildings["lab"]["weeks_left"] = 4
			s.changed.emit()
			var lp := main.campus.lot_position("lab")
			_place(lp, 38.0, 40.0, 34.0)
			await _frames(60)
			await _shot("fx_e%d_works" % era)
			s.buildings["lab"]["weeks_left"] = 0
			s.changed.emit()
		if _want("levelup"):
			var hp := main.campus.lot_position("hq")
			_place(hp, 38.0, 32.0, 46.0)
			await _frames(20)
			fx.pop_level_up("hq")
			await _frames(16)
			await _shot("fx_e%d_levelup" % era)
		if _want("celebrate"):
			_place(Vector3(2.5, 6, 4.2), 30.0, 22.0, 70.0)
			await _frames(10)
			fx.celebrate(true)
			await _seconds(2.0)
			await _shot("fx_e%d_celebrate" % era)
		if _want("birds"):
			var bird := fx.get_node("Birds/Lamp1") as RoofBirds
			bird.flee_distance = 0.0
			bird.come_back()
			cam.global_position = bird.global_position + Vector3(4.5, 1.2, 4.5)
			cam.look_at(bird.global_position + Vector3(0, 0.2, 0), Vector3.UP)
			cam.near = 0.05
			await _frames(30)
			await _shot("fx_e%d_birds" % era)
			bird.fly_off()
			await _seconds(0.7)
			await _shot("fx_e%d_birds_fled" % era)
			bird.flee_distance = 24.0
	# performance: game view, everything on, vsync off
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	cycle.force_phase = 0.12
	fx.weather.set_kind("rain")
	fx.weather.rain_amount = 1.0
	_place(Vector3(4, 0, 2), 38.0, 40.0, 110.0)
	await _frames(90)
	var t0 := Time.get_ticks_usec()
	await _frames(180)
	var ms := (Time.get_ticks_usec() - t0) / 180000.0
	print("PERF fx game view (rain, all buildings busy): %.2f ms/frame (%.0f fps), draw calls %d" % [ms, 1000.0 / ms,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	print("CAMPUS FX SCREENSHOTS DONE")
	quit()


func _want(name: String) -> bool:
	return shots.is_empty() or name in shots


func _lot_of(s: TycoonState, kind: String) -> String:
	for lot: String in s.lot_ids():
		if s.lot_kind(lot) == kind:
			return lot
	return ""


func _set_campus(s: TycoonState, era: int) -> void:
	s.weeks = (era - 1) * 5 * 52 + 10
	for lot: String in s.lot_ids():
		s.buildings[lot] = {"kind": s.lot_kind(lot), "level": 3, "target": 3, "weeks_left": 0}
	s.changed.emit()


## Every building at full activity now.
func _busy() -> void:
	for lot: String in main.state.lot_ids():
		var b := fx.fx_of(lot)
		if b:
			b.set_activity(1.0)
			b.snap()


## The clouds of the current weather out at once (no waiting for them to puff in).
func _clouds_now() -> void:
	var wx := fx.weather
	var cover := float(wx.cloud_cover.get(wx.kind, 0.3))
	var n := wx.clouds.get_child_count()
	for i in n:
		wx.clouds.get_child(i).set_meta("pop", 1.0 if float(i) < cover * n - 0.01 else 0.0)


func _place(focus: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> void:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	cam.global_position = focus + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.look_at(focus + Vector3(0, 1.5, 0), Vector3.UP)
	cam.near = maxf(dist * 0.02, 0.2)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved %s" % path)
