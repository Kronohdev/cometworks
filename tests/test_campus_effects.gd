extends SceneTree
## Checks the campus' visual life (scenes/tycoon/fx/, src/tycoon/fx/): every building gets its
## BuildingFx and its activity follows the staff (idle when nobody works, busier with a
## project, busiest with Cometlings on the lot), construction sites and level-ups show, the
## weather follows the settings switch (off = always clear), fireflies follow the night, the
## comet grows with the eras, celebrations wait for the screens to close and make the
## Cometlings cheer, the launch's failure puff has no debris, the options panel has its
## weather row, and none of it touches the campaign (same state, same random numbers).
## Run: godot --headless --path . --script res://tests/test_campus_effects.gd

var _fails := 0
var main: TycoonMain
var fx: CampusEffects


func _initialize() -> void:
	var weather_was := MenuSettings.weather()
	MenuSettings.set_weather(true)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(5)
	main.clock.set_speed(0)
	var s := main.state
	fx = main.get_node_or_null("Effects") as CampusEffects
	_check(fx != null and fx.get_script().resource_path == "res://src/tycoon/fx/campus_effects.gd", "Effects node runs CampusEffects")
	_check(fx != null and fx.weather is CampusWeather, "Weather child runs CampusWeather")
	if fx == null or fx.weather == null:
		_finish(weather_was)
		return
	# every lot built at level 3, era 3
	s.weeks = 2 * 5 * 52 + 10
	for lot: String in s.lot_ids():
		s.buildings[lot] = {"kind": s.lot_kind(lot), "level": 3, "target": 3, "weeks_left": 0}
	s.changed.emit()
	await _frames(3)
	var kinds_ok := true
	for lot: String in s.lot_ids():
		var kind := s.lot_kind(lot)
		if fx.building_fx.has(kind):
			var b := fx.fx_of(lot)
			kinds_ok = kinds_ok and b is BuildingFx and b.get_parent() == main.campus.building_node(lot)
	_check(kinds_ok, "every building with an effect scene has its BuildingFx on it")
	# purely visual: running the effects (weather, night, activity, fireworks, cheers) leaves
	# the campaign exactly as it was
	var before := JSON.stringify(s.to_dict())
	var rng_before := s.rng.state
	await _activity(s)
	await _weather()
	await _night()
	fx.cheer_all()
	fx.launch_fireworks(Vector3.ZERO)
	fx.pop_level_up("hq")
	await _frames(10)
	_check(s.rng.state == rng_before, "the campaign RNG was not drawn from")
	_check(JSON.stringify(s.to_dict()) == before, "the campaign state is unchanged by the effects")
	await _works(s)
	await _celebrations(s)
	_launch_scene()
	_options()
	_finish(weather_was)


func _finish(weather_was: bool) -> void:
	MenuSettings.set_weather(weather_was)
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails else 0)


# ------------------------------------------------------------ activity
func _activity(s: TycoonState) -> void:
	var f := fx.fx_of("factory")
	_check(f != null, "the factory has its effect")
	if f == null:
		return
	# nobody on the campus, nobody on a project: idle
	for w in main.campus.cometlings():
		w.visible = false
	for m in s.staff:
		m["assigned"] = ""
	fx._update_activity()
	_check(is_zero_approx(f.target_activity), "empty, no project: the factory idles (%.2f)" % f.target_activity)
	f.snap()
	var smoke := f.get_node("Stack/Smoke") as GPUParticles3D
	_check(is_equal_approx(smoke.amount_ratio, float(smoke.get_meta("idle"))), "idle factory: thin smoke (%.2f)" % smoke.amount_ratio)
	var interior_off := true
	for n in f.find_children("*", "GPUParticles3D", true, false):
		if n.get_meta("interior", false):
			interior_off = interior_off and not (n as GPUParticles3D).emitting
	_check(interior_off, "closed building: the inside effects do not emit")
	# someone on a project: every building a little busy
	s.staff[0]["assigned"] = "test_project"
	fx._update_activity()
	_check(is_equal_approx(f.target_activity, fx.busy_activity), "a project running: busy (%.2f)" % f.target_activity)
	# a Cometling standing on the lot: busier
	var w := main.campus.get_node("Crowd").get_child(0) as Node3D
	w.visible = true
	w.set_process(false)
	w.global_position = main.campus.lot_position("factory") + Vector3(0, 0, 1)
	fx._update_activity()
	_check(is_equal_approx(f.target_activity, fx.busy_activity + fx.per_worker), "a Cometling on the lot: busier (%.2f)" % f.target_activity)
	f.snap()
	_check(is_equal_approx(smoke.amount_ratio, 1.0 if fx.busy_activity + fx.per_worker >= 1.0 else lerpf(float(smoke.get_meta("idle")), 1.0, f.activity)), "busy factory: full smoke")
	var lab := fx.fx_of("lab")
	var lab_ap := lab.get_node_or_null("AnimationPlayer") as AnimationPlayer if lab else null
	lab.set_activity(0.0)
	lab.snap()
	var idle_speed := lab_ap.speed_scale if lab_ap else -1.0
	lab.set_activity(1.0)
	lab.snap()
	_check(lab_ap != null and is_equal_approx(idle_speed, lab.idle_speed) and is_equal_approx(lab_ap.speed_scale, 1.0), "the lab's loops slow down when idle and run at full speed when busy")
	s.staff[0]["assigned"] = ""
	w.set_process(true)


# ------------------------------------------------------------ construction and level-up
func _works(s: TycoonState) -> void:
	s.buildings["lab"]["weeks_left"] = 3
	s.changed.emit()
	await _frames(2)
	var w := fx.works_of("lab")
	_check(w != null and w.get_node_or_null("Dust") != null, "a lot being built shows the construction dust")
	s.buildings["lab"]["weeks_left"] = 0
	s.changed.emit()
	await _frames(2)
	_check(fx.works_of("lab") == null, "the construction effect leaves when the works end")
	var n := _count_shots("level_up_fx")
	s.building_finished.emit("lab", 3)
	await _frames(1)
	_check(_count_shots("level_up_fx") == n + 1, "a finished building pops the level-up flourish")


## Flourishes of one scene playing under the Effects node ("level_up_fx", "fireworks").
func _count_shots(scene: String) -> int:
	var n := 0
	for c in fx.get_children():
		if c is FxOneShot and c.scene_file_path.get_file().get_basename() == scene and not c.is_queued_for_deletion():
			n += 1
	return n


# ------------------------------------------------------------ weather
func _weather() -> void:
	var wx := fx.weather
	MenuSettings.set_weather(false)
	_check(not wx.enabled and wx.kind == "clear", "weather off in the settings: clear sky")
	wx.set_kind("rain")
	_check(wx.kind == "clear", "weather off: rain is ignored")
	MenuSettings.set_weather(true)
	_check(wx.enabled, "weather on again from the settings")
	wx.set_kind("rain")
	wx.rain_fade = 50.0
	await _frames(4)
	_check(wx.kind == "rain" and wx.rain_amount > 0.9 and wx.rain.emitting, "rain falls (%.2f)" % wx.rain_amount)
	var shown := 0
	for c in wx.clouds.get_children():
		if float(c.get_meta("pop", 0.0)) > 0.0:
			shown += 1
	_check(shown > 0, "clouds come out with the rain (%d)" % shown)
	wx.set_kind("clear")
	await _frames(4)
	_check(wx.rain_amount < 0.1 and not wx.rain.emitting, "the rain stops")
	wx.rain_fade = 0.2
	wx.set_era(1)
	var sky := (main.campus.get_node("WorldEnvironment") as WorldEnvironment).environment.sky.sky_material as ShaderMaterial
	var l1 := float(sky.get_shader_parameter("comet_length"))
	wx.set_era(5)
	var l5 := float(sky.get_shader_parameter("comet_length"))
	_check(l5 > l1 * 2.0, "the comet grows from era 1 to era 5 (%.2f -> %.2f)" % [l1, l5])
	wx.set_era(main.campus.era)


func _night() -> void:
	var cycle := main.get_node("DayCycle") as CampusDayCycle
	var ff := main.campus.get_node("Life/Fireflies") as GPUParticles3D
	cycle.force_phase = 0.5
	await _frames(3)
	_check(ff.emitting and ff.amount_ratio > 0.9, "fireflies glow at night (%.2f)" % ff.amount_ratio)
	cycle.force_phase = 0.0
	await _frames(3)
	_check(not ff.emitting, "no fireflies in the daylight")
	cycle.force_phase = -0.01


# ------------------------------------------------------------ celebrations
func _celebrations(s: TycoonState) -> void:
	for w in main.campus.get_node("Crowd").get_children():
		if String(w.get("member_id")) != "":
			(w as Node3D).visible = true
	var n := fx.cheer_all()
	_check(n > 0 and n == main.campus.cometlings().size(), "every Cometling cheers (%d)" % n)
	main.hud.open_screen("settings")
	await _frames(2)
	var fw := _count_shots("fireworks")
	s.milestone_claimed.emit("test_first", RaceDirector.PLAYER)
	await _frames(3)
	_check(_count_shots("fireworks") == fw, "a celebration waits while a screen is open")
	main.hud.close_screen()
	await _frames(3)
	_check(_count_shots("fireworks") == fw + 1, "the first's fireworks go up once the screen closes")
	s.milestone_claimed.emit("test_rival", "rival_x")
	await _frames(3)
	_check(_count_shots("fireworks") == fw + 1, "a rival's milestone sets off nothing")
	s.mission_completed.emit({"success": true, "pad": "pad"})
	await _frames(3)
	_check(_count_shots("fireworks") == fw + 2, "a mission success sets off fireworks over its pad")


# ------------------------------------------------------------ scenes
func _launch_scene() -> void:
	var ls := (load("res://scenes/tycoon/launch/launch_sequence.tscn") as PackedScene).instantiate()
	var debris := ls.get_node_or_null("Stage/FailFX/Debris") as GPUParticles3D
	_check(debris != null and debris.draw_pass_1 is QuadMesh, "the failure puff throws stars, not debris cubes")
	_check(ls.get_node_or_null("Stage/Spectators/Fireworks") is FxOneShot, "the launch has fireworks for a success")
	ls.free()


func _options() -> void:
	var was := MenuSettings.weather()
	var op := (load("res://scenes/menu/options_panel.tscn") as PackedScene).instantiate()
	get_root().add_child(op)
	var on := op.get_node_or_null("%WeatherOn") as Button
	var off := op.get_node_or_null("%WeatherOff") as Button
	_check(on != null and off != null, "the options panel has the weather row")
	if off:
		off.pressed.emit()
		_check(not MenuSettings.weather(), "the weather row turns the weather off")
		on.pressed.emit()
		_check(MenuSettings.weather(), "and on again")
	MenuSettings.set_weather(was)
	op.queue_free()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1
