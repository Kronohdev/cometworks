extends SceneTree
## Visual check of the rebuilt hangar HUD (opens a window) walking a first build with the
## part advisor: empty pad (the Recommended tab suggests the flight computer), one-click Add
## of the core, a kerosene tank in hand (kerosene engines recommended, other engines dimmed
## in the Engines tab, detail card), the engine added, a tycoon mission goal (Δv short:
## upper stage advice, payload, budget), the Garça example in PT and EN, the symmetry
## popup, the help overlay, the crew drawer and the collapsed HUD. Prints the checks it makes.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_hangar_ui.gd -- <out_dir>

var out_dir := "user://"
var hangar: Node
var ui: HangarUI
var _fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	FlightSession.clear()
	FlightSession.mission = {}
	hangar = (load("res://scenes/hangar.tscn") as PackedScene).instantiate()
	get_root().add_child(hangar)
	await _frames(2)
	TranslationServer.set_locale("pt")
	ui = hangar.ui
	ui.refresh_texts()
	hangar.cam.snap_to(Vector3(0, 5, 0), deg_to_rad(30), deg_to_rad(10), 22.0)
	_park_mouse()
	await _frames(12)
	_check(not ui._recs.is_empty() and PartDB.is_command(PartDB.get_part(ui._recs[0]["id"])), "empty pad recommends a flight computer")
	_check(ui._rec_full.get_child_count() > 0, "the Recommended tab lists it")
	_shot("hui_01_empty")

	# one-click Add of the recommended core
	var ok: bool = hangar.quick_add(ui._recs[0]["id"], ui._recs[0]["hint"])
	await _frames(6)
	_check(ok and hangar.vessel.root != null, "quick add places the core as the root")
	# a kerosene tank under it (as if dropped there), then hold another one
	hangar.quick_add("tank_kerolox_s4", "bottom")
	await _frames(4)
	_check(hangar.vessel.all_parts().size() == 2, "quick add attaches the tank under the core")
	await _frame_vessel()
	var engines := ui._recs.filter(func(r: Dictionary) -> bool: return PartDB.is_engine(PartDB.get_part(r["id"])))
	_check(not engines.is_empty() and engines.all(func(r: Dictionary) -> bool:
		return PartDB.get_part(r["id"])["propellant"] == "kerolox"), "the kerosene tank asks for kerosene engines")
	_shot("hui_02_tank_recommends")

	# browse the Engines tab: other propellants are dimmed, hover a card for the detail
	ui.select_category("engine")
	await _frames(4)
	var dim := 0
	var target: Control = null
	for c in ui._part_grid.get_children():
		if c.get_node("Mismatch").visible:
			dim += 1
		elif c.get_meta("part_id") == "eng_falcao":
			target = c
	_check(dim > 0, "engines of other propellants are dimmed (%d)" % dim)
	if target:
		await _hover_card(target)
	await _frames(4)
	_shot("hui_03_engines_detail")
	var hydro: Control = null
	for c in ui._part_grid.get_children():
		if c.get_meta("part_id") == "eng_hidra_25":
			hydro = c
	if hydro:
		await _hover_card(hydro)
	await _frames(4)
	_shot("hui_04_mismatch_detail")
	ui._show_detail("")
	_park_mouse()

	# add the recommended engine with one click on the strip's + button
	var row: Control = null
	for r in ui._rec_list.get_children():
		if PartDB.is_engine(PartDB.get_part(r.get_meta("part_id"))):
			row = r
			break
	_check(row != null, "the Engines tab shows the recommended engines on top")
	var eng_id: String = row.get_meta("part_id") if row else "eng_falcao"
	if row:
		(row.get_node("Row/Add") as Button).pressed.emit()
	else:
		hangar.quick_add(eng_id, "below_tank:kerolox")
	await _frames(4)
	var has_engine: bool = hangar.vessel.all_parts().any(func(p: PartInstance) -> bool: return p.part_id == eng_id)
	_check(has_engine, "the + button puts %s under the tank" % eng_id)
	await _frame_vessel()
	_shot("hui_05_engine_added")

	# a tycoon mission: Δv short, payload and budget on the goal card
	FlightSession.mission = {"title": "DEM-01 · Satélite de demonstração", "target": "Órbita baixa", "dv_needed": 9400.0,
		"payload_kg": 320.0, "budget_musd": 6.0, "crewed": false}
	ui.refresh_texts()
	hangar._dirty = true
	await _frames(4)
	var up := ui._recs.filter(func(r: Dictionary) -> bool: return r["reason"] == "ADV_UPPER_STAGE")
	_check(not up.is_empty(), "mission Δv short: upper stage advice")
	ui.select_category("tank")
	await _frames(4)
	_shot("hui_06_mission_short")
	# follow the advice: decoupler below, then the first stage the advisor asks for
	if not up.is_empty():
		hangar.quick_add(up[0]["id"], up[0]["hint"])
		await _frames(4)
		for i in 3:
			var nxt: Array = ui._recs.filter(func(r: Dictionary) -> bool: return r["reason"] in ["ADV_FIRST_STAGE", "ADV_ENGINE_FOR", "ADV_TANK_FOR"])
			if nxt.is_empty():
				break
			hangar.quick_add(nxt[0]["id"], nxt[0]["hint"])
			await _frames(4)
	print("staged build: %s" % [hangar.vessel.all_parts().map(func(p: PartInstance) -> String: return p.part_id)])
	await _frame_vessel()
	ui.select_category(HangarUI.REC_CATEGORY)
	await _frames(4)
	_shot("hui_07_mission_staged")
	FlightSession.mission = {}
	ui.refresh_texts()

	# the Garça example, PT then EN
	hangar.load_example("garca")
	await _settle()
	_park_mouse()
	ui.select_category("tank")
	await _frames(6)
	_shot("hui_08_garca_pt")
	hangar._toggle_language()
	await _frames(6)
	_shot("hui_09_garca_en")
	hangar._toggle_language()
	await _frames(3)

	# symmetry popup, help, crew drawer, collapsed
	ui._open_symmetry()
	await _frames(6)
	_shot("hui_10_symmetry")
	ui._choose_symmetry(1)
	ui._btn_help.button_pressed = true
	await _frames(6)
	_shot("hui_11_help")
	ui._btn_help.button_pressed = false
	ui._tab_crew.button_pressed = true
	await _frames(6)
	_shot("hui_12_crew")
	ui._tab_stages.button_pressed = true
	ui.set_parts_collapsed(true)
	ui.set_stages_collapsed(true)
	await _frames(6)
	_shot("hui_13_collapsed")
	ui.set_parts_collapsed(false)
	ui.set_stages_collapsed(false)
	ui._search_box.text = "tanque"
	ui._search_box.text_changed.emit("tanque")
	await _frames(6)
	_shot("hui_14_search")
	ui._search_box.clear()
	ui._search_box.text_changed.emit("")
	await _frames(2)
	# clicking a card in the Recommended tab picks the part up (the tab rebuilds under the click)
	ui.select_category(HangarUI.REC_CATEGORY)
	await _frames(2)
	if ui._part_grid.get_child_count() > 0:
		var card := ui._part_grid.get_child(0) as Button
		var want: String = card.get_meta("part_id")
		card.pressed.emit()
		await _frames(4)
		_check(hangar.held != null and hangar.held.part_id == want, "clicking a card puts %s in the hand" % want)
		hangar._drop_held()
		await _frames(2)
	_check(_fits_on_screen(), "every panel fits inside the window")
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	print("SHOTS DONE")
	quit()


## Panels stay inside the viewport (the HUD is authored at 1600x900, stretch canvas_items).
func _fits_on_screen() -> bool:
	var vp: Vector2 = ui._root.size
	var ok := true
	for c in [ui._parts_panel, ui._rocket_panel, ui.get_node("Root/TopBar")]:
		var r: Rect2 = (c as Control).get_rect()
		if r.position.x < 0 or r.position.y < 0 or r.end.x > vp.x + 0.5 or r.end.y > vp.y + 0.5:
			print("  off screen: %s %s (viewport %s)" % [c.name, r, vp])
			ok = false
	return ok


func _check(ok: bool, msg: String) -> void:
	print(("  ok: " if ok else "  FAIL: ") + msg)
	if not ok:
		_fails += 1


## Scrolls the palette to a card, puts the mouse on it and opens its detail card.
func _hover_card(c: Control) -> void:
	ui._part_scroll.ensure_control_visible(c)
	await _frames(2)
	Input.warp_mouse(get_root().get_final_transform() * c.get_global_rect().get_center())
	await _frames(2)
	ui._show_detail(c.get_meta("part_id"), c)


func _park_mouse() -> void:
	Input.warp_mouse(Vector2(DisplayServer.window_get_size()) * Vector2(0.62, 0.55))


func _frame_vessel() -> void:
	var b: AABB = hangar.vessel.bounds()
	hangar.cam.snap_to(b.get_center(), deg_to_rad(30), deg_to_rad(8), maxf(b.size.length() * 2.2, 12.0))
	await _frames(6)


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
	print("shot %s" % shot_name)
