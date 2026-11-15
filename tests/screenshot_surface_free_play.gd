extends SceneTree
## Shots of the surface free play in use (opens a window):
##   explore_*   on the Moon with the drone: a discovery card, the challenge card of the crater
##               race, the field log and photo mode; Mars and Europa discovery cards
##   menu_*      the main menu's "Superfícies" item and its picker
##   campus_*    a career (demo save, a lunar landing added): the HUD's Superfícies button, the
##               picker with the reached worlds, the Moon opened over the sleeping campus, and back
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_surface_free_play.gd -- <out_dir>

const TEST_LOG := "user://screenshot_surface_log.json"

var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	SurfaceLog.free_path = TEST_LOG
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LOG))
	TranslationServer.set_locale("pt")
	await _explore("moon", "moon_eagle_homage", Vector3(-96, 0, 74), true)
	await _explore("mars", "mars_viking_homage", Vector3(-108, 0, 76), false)
	await _explore("europa", "europa_plume", Vector3(150, 0, 168), false)
	await _menu()
	await _campus()
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LOG))
	print("SHOTS DONE")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


func _idle(surf: PlanetSurface, max_s := 20.0) -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(4)
	while (Time.get_ticks_msec() - t0) / 1000.0 < max_s:
		await process_frame
		if Time.get_ticks_msec() - t0 > 600 and surf.terrain.is_idle():
			break
	await _frames(15)


func _explore(body: String, poi_id: String, cam_at: Vector3, full: bool) -> void:
	var surf := (load("res://scenes/surface/%s_surface.tscn" % body) as PackedScene).instantiate() as PlanetSurface
	get_root().add_child(surf)
	await _frames(3)
	var ex := surf.get_node("Explore") as SurfaceExplore
	var cam := surf.get_node("FlyCamera") as SurfaceFlyCamera
	var poi := ex._poi_by_id(poi_id)
	var g := surf.ground_height(cam_at.x, cam_at.z)
	cam.global_position = Vector3(cam_at.x, g + 5.0, cam_at.z)
	cam.look_toward(poi.global_position + Vector3(0, 1.5, 0))
	await _idle(surf)
	# fly low over it: the drone reaches the place
	var keep := cam.global_position
	cam.global_position = Vector3(poi.global_position.x + 2.0, poi.global_position.y + 4.0, poi.global_position.z + 2.0)
	ex._drone_reach()
	cam.global_position = keep
	cam.look_toward(poi.global_position + Vector3(0, 1.5, 0))
	await _frames(10)
	await _shot("explore_%s_discovery" % body)
	if not full:
		surf.queue_free()
		await _frames(3)
		return
	# the crater race: armed in the ring by the lander, then running
	var ring: SurfaceChallenge = null
	for n in surf.find_children("*", "SurfaceChallenge", true, false):
		if String((n as SurfaceChallenge).entry_id) == "moon_rim_dash":
			ring = n
	cam.global_position = ring.global_position + Vector3(-14, 7, 16)
	cam.look_toward(ring.global_position)
	await _idle(surf)
	cam.global_position = ring.global_position + Vector3(0, 1.5, 0)
	ex._tick_challenges(0.1)
	cam.global_position = ring.global_position + Vector3(ring.radius + 3.0, 1.5, 0)
	ex._tick_challenges(0.1)
	ex._tick_challenges(23.4)
	cam.global_position = ring.global_position + Vector3(-14, 7, 16)
	cam.look_toward(ex._poi_by_id("moon_bright_crater").global_position)
	await _idle(surf)
	ex._card_t = 0.0
	ex.get_node("%Card").visible = false
	await _frames(5)
	await _shot("explore_moon_challenge")
	# the field log
	ex.open_log()
	await _frames(6)
	await _shot("explore_moon_log")
	ex.close_log()
	# photo mode around the tribute site
	cam.global_position = Vector3(-100, surf.ground_height(-100, 70) + 3.0, 70)
	cam.look_toward(poi.global_position)
	await _idle(surf)
	ex.enter_photo_mode()
	await _frames(10)
	await _shot("explore_moon_photo_mode")
	ex.exit_photo_mode()
	surf.queue_free()
	await _frames(3)


func _menu() -> void:
	var menu := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	await _frames(90)
	(menu.get_node("%Surfaces") as Control).grab_focus()
	await _frames(20)
	await _shot("menu_surfaces_item")
	(menu.get_node("%SurfacePicker") as SurfacePicker).open()
	await _frames(10)
	await _shot("menu_surfaces_picker")
	menu.queue_free()
	await _frames(5)


func _campus() -> void:
	if not TycoonSave.exists("demo_era3"):
		print("no demo_era3 save: campus shots skipped")
		return
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.load_slot = "demo_era3"
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(8)
	main.clock.set_speed(0)
	if main.tutorial:
		main.tutorial.visible = false
	main.state.mission_archive.append({"type": "lander", "target": "lunar_surface", "outcome": "full"})
	await _frames(70)
	var button := main.hud.find_child("Surfaces", true, false) as SurfaceCampusButton
	print("campus button visible: ", button.visible)
	await _shot("campus_surfaces_button")
	button.open_picker()
	await _frames(10)
	await _shot("campus_surfaces_picker")
	button.picker._pick("moon")
	await _frames(10)
	var viewer: SurfaceViewer = null
	for c in main.get_children():
		if c is SurfaceViewer:
			viewer = c
	if viewer:
		await _idle(viewer.surface)
		await _shot("campus_moon_viewer")
		viewer.surface_leave()
		await _frames(10)
		await _shot("campus_back")
	main.queue_free()
	await _frames(5)
