extends SceneTree
## Windowed screenshots of the solar-system view (scenes/solar_system/solar_system.tscn: the same
## map as the campus' Solar System map, on the real ephemeris) and render statistics:
##   ss_overview_en / _pt   the whole system today, readable sizes
##   ss_true_scale          the same at true scale (the planets are specks: why readable exists)
##   ss_inner               the inner planets and the asteroid belt
##   ss_earth_moon          the Earth and the Moon's real (inclined, elliptical) orbit
##   ss_earth, ss_moon      close-ups (clouds, maria)
##   ss_mars                Mars with Phobos and Deimos
##   ss_jupiter             Jupiter's bands and the Galilean moons' orbits in its equator
##   ss_saturn              Saturn's rings at their real tilt, Titan
##   ss_comet_inner         the comet Mae-Gelo near the end of the campaign, tails away from the Sun
##   ss_comet               the comet close up
## Run (windowed): godot --path . --resolution 1600x900 --script res://tests/screenshot_solar_system.gd -- <out_dir> [view ...]

var out_dir := "user://"
var ssv: SolarSystem
var map: FlightMap


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var only := args.slice(1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("en")
	ssv = (load("res://scenes/solar_system/solar_system.tscn") as PackedScene).instantiate() as SolarSystem
	ssv.leave_to_menu = false
	get_root().add_child(ssv)
	await _frames(10)
	map = ssv.world.map
	ssv._on_pause_toggled(true)
	var sys := ssv.world.sys
	var views := [
		# name, focus id, distance (km), pitch, yaw, readable, time offset (days from today or "end")
		["overview_en", "sun", 2.4e9, 0.62, 0.9, true, 0.0],
		["true_scale", "sun", 2.4e9, 0.62, 0.9, false, 0.0],
		["inner", "sun", 6.5e8, 0.75, 0.9, true, 0.0],
		["earth_moon", "earth", 1.35e6, 0.45, 0.6, true, 0.0],
		["earth", "earth", 2.6e4, 0.25, 2.2, false, 0.0],
		["moon", "moon", 7.5e3, 0.2, 1.4, false, 0.0],
		["mars", "mars", 1.1e5, 0.4, 0.7, true, 0.0],
		["jupiter", "jupiter", 5.5e6, 0.3, 0.9, true, 0.0],
		["saturn", "saturn", 7.0e5, 0.22, 0.6, false, 0.0],
		["comet_inner", "sun", 4.2e8, 0.8, 0.5, true, "end"],
		["comet", "mae_gelo", 2.2e7, 0.35, 1.2, true, "end"],
	]
	for v in views:
		if not only.is_empty() and not v[0] in only:
			continue
		await _view(v)
		_shot("ss_" + String(v[0]))
		if v[0] == "overview_en":
			await _stats("overview")
			if only.is_empty() or "overview_pt" in only:
				TranslationServer.set_locale("pt")
				ssv.overlay.show_info("saturn")
				await _frames(6)
				_shot("ss_overview_pt")
				TranslationServer.set_locale("en")
	print("SHOTS DONE (%s)" % sys.date_at(ssv.world.time))
	quit()


func _view(v: Array) -> void:
	var ov := ssv.overlay
	var tt: Variant = v[6]
	ov.t = (9100.0 - 12.0) * 86400.0 if tt is String else SolarSystemOverlay.today_t() + float(tt) * 86400.0
	map.set_readable(bool(v[5]))
	ssv.focus_body(String(v[1]))
	await _frames(2)
	map.dist = float(v[2])
	map.pitch = float(v[3])
	map.yaw = float(v[4])
	if String(v[1]) != "sun":
		# close-ups from the sunlit side: the yaw is measured from the Sun's direction
		var sp := map._body_nodes[ssv.world.sys.sun].position.normalized()
		var up := map._up
		var ref := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		var side := up.cross(ref).normalized()
		map.yaw = atan2(sp.dot(side), sp.dot(ref)) + float(v[4]) * 0.5
	map._dist = map.dist
	map._pitch = map.pitch
	map._yaw = map.yaw
	map._anim_t = 1.0
	await _frames(24)


func _stats(what: String) -> void:
	await _frames(60)
	var fps := Engine.get_frames_per_second()
	var vp := map.viewport.get_viewport_rid()
	var prims := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var calls := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	print("STATS %s: %d fps, %d primitives, %d draw calls in the map viewport" % [what, fps, prims, calls])


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
