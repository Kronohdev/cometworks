extends SceneTree
## Visual check of the HUD redesign (opens a window): hangar with the Garça example
## (EN/PT, stage cards, part detail card, symmetry selector open, collapsed rail, problems
## of a broken vessel, crew drawer, empty hangar, search; the advisor flow has its own
## script, screenshot_hangar_ui.gd), the UI kit
## showcase, the solar-system map HUD and the planet-surface HUD.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_ui.gd -- <out_dir> [hangar|kit|map|surface]...

var out_dir := "user://"
var hangar: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only := args.slice(1)
	if only.is_empty() or "hangar" in only:
		await _hangar_shots()
	if only.is_empty() or "kit" in only:
		await _kit_shot()
	if only.is_empty() or "map" in only:
		await _map_shot()
	if only.is_empty() or "surface" in only:
		await _surface_shot()
	print("UI SHOTS DONE")
	quit()


func _hangar_shots() -> void:
	hangar = (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(2)
	TranslationServer.set_locale("en")
	hangar.ui.refresh_texts()
	await _frames(8)
	_shot("ui_hangar_empty")
	var ui: HangarUI = hangar.ui
	hangar.load_example("garca")
	await _settle()
	_warp(Vector2(1120, 650))
	await _frames(4)
	_shot("ui_hangar_en")
	# part detail card: hover an engine card in the engine tab
	(ui._category_bar.get_node("engine") as Button).button_pressed = true
	await _frames(3)
	var card := ui._part_grid.get_child(0) as Control
	_warp(card.get_global_rect().get_center())
	await _frames(6)
	ui._show_detail(_first_engine(), card)
	await _frames(3)
	_shot("ui_part_card")
	_warp(Vector2(1120, 650))
	await _frames(3)
	_shot("ui_stages_detailed")
	# symmetry selector open
	hangar.symmetry = 4
	ui.set_symmetry(4)
	ui._open_symmetry()
	await _frames(6)
	_shot("ui_symmetry_popup")
	ui._choose_symmetry(6)
	await _frames(3)
	print("symmetry after choosing 6: hangar=%d ui=%d" % [hangar.symmetry, ui._symmetry])
	ui._choose_symmetry(1)
	await _frames(2)
	# Portuguese
	hangar._toggle_language()
	await _frames(6)
	_shot("ui_hangar_pt")
	hangar._toggle_language()
	await _frames(4)
	# problems: a kerosene tank on a hydrogen engine, no core, tumbling
	var bad := [{"core": [PartDB.get_part("tank_kerolox_s4"), PartDB.get_part("eng_hidra_rl")], "boosters": []}]
	ui.show_analysis(VesselMath.analyze(bad), {"parts": 2, "cost": 3.4, "stable": 0, "specs": bad})
	await _frames(4)
	_shot("ui_warnings")
	hangar._dirty = true
	await _frames(3)
	# collapsed rail + collapsed stages
	ui.set_parts_collapsed(true)
	ui.set_stages_collapsed(true)
	await _frames(4)
	_shot("ui_collapsed")
	ui.set_parts_collapsed(false)
	ui.set_stages_collapsed(false)
	# crew tab + search
	ui._tab_crew.button_pressed = true
	ui._search_box.text = "tank"
	ui._search_box.text_changed.emit("tank")
	ui._search_box.grab_focus()
	await _frames(4)
	_shot("ui_crew_search")
	ui._tab_stages.button_pressed = true
	ui._search_box.release_focus()
	ui._search_box.clear()
	ui._search_box.text_changed.emit("")
	# favorites: right-click toggles (restored afterwards so the prefs file is unchanged)
	var fav_id := _first_engine()
	var was_fav: bool = ui._favorites.has(fav_id)
	if not was_fav:
		ui._toggle_favorite(fav_id)
	(ui._category_bar.get_node("favorites") as Button).button_pressed = true
	await _frames(4)
	print("favorites tab: %d card(s)" % ui._part_grid.get_child_count())
	_shot("ui_favorites")
	if not was_fav:
		ui._toggle_favorite(fav_id)
	(ui._category_bar.get_node("command") as Button).button_pressed = true
	# help
	ui._btn_help.button_pressed = true
	await _frames(4)
	_shot("ui_help")
	ui._btn_help.button_pressed = false
	hangar.queue_free()
	await _frames(2)


func _first_engine() -> String:
	return PartDB.parts_in_category("engine")[0]


func _kit_shot() -> void:
	var kit: Node = (load("res://scenes/ui/ui_kit.tscn") as PackedScene).instantiate()
	get_root().add_child(kit)
	await _frames(4)
	(kit.get_node("%Focused") as LineEdit).grab_focus()
	await _frames(4)
	_shot("ui_kit")
	kit.queue_free()
	await _frames(2)


func _map_shot() -> void:
	var sys: Node = (load("res://scenes/solar_system/solar_system.tscn") as PackedScene).instantiate()
	get_root().add_child(sys)
	await _frames(10)
	TranslationServer.set_locale("en")
	sys.call("refresh_texts")
	sys.call("_on_pause_toggled", true)
	sys.call("show_info", "saturn")
	await _frames(20)
	_shot("ui_map_hud")
	sys.queue_free()
	await _frames(2)


func _surface_shot() -> void:
	var demo: Node = (load("res://scenes/surface/surface_demo.tscn") as PackedScene).instantiate()
	get_root().add_child(demo)
	TranslationServer.set_locale("en")
	await _frames(3)
	demo.call("select_planet", 2)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		var terrain: Object = demo.get("planet").get("terrain")
		if Time.get_ticks_msec() - t0 > 1500 and terrain.call("is_idle"):
			break
	await _frames(20)
	_shot("ui_surface_hud")
	demo.queue_free()
	await _frames(2)


func _warp(p: Vector2) -> void:
	Input.warp_mouse(p)
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	get_root().push_input(ev)


## Lets the camera finish easing toward its target view.
func _settle() -> void:
	await _frames(2)
	var c: HangarCamera = hangar.cam
	c.snap_to(c.target_focus, c.target_yaw, c.target_pitch, c.target_distance)
	await _frames(4)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	get_root().get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])
