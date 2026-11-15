extends SceneTree
## Accessibility options and the graphics quality (CwAccess, CwKeys, GraphicsQuality):
##   - text size: set, snapped to the steps, saved, and applied as the root's content scale
##   - graphics quality: saved, read back after a "restart", and applied to a small scene and
##     to scenes added later (the watch): render scale, AA, SSAO / SSIL / glow, lamps, foliage
##   - colour-blind mode: saved, swaps the agency and kind colours, every agency a shape cue
##   - keys: a rebind is saved and restored, a taken key swaps, the actions answer the new key,
##     Restore keys puts the defaults back
##   - the options panel's buttons drive all of it (quality, text size, colour-blind, a key row)
## user://settings.cfg is put back at the end.
## Run: godot --headless --path . --script res://tests/test_settings_access.gd

const SETTINGS := "user://settings.cfg"

var _fails := 0
var _checks := 0
var _kept: Variant = null


func _initialize() -> void:
	_kept = FileAccess.get_file_as_bytes(SETTINGS) if FileAccess.file_exists(SETTINGS) else null
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)
	CwAccess.ensure_applied()
	await process_frame
	_text_size()
	await _quality()
	_colorblind()
	_keys()
	await _panel()
	# back to the player's settings
	if _kept == null:
		if FileAccess.file_exists(SETTINGS):
			DirAccess.remove_absolute(SETTINGS)
	else:
		FileAccess.open(SETTINGS, FileAccess.WRITE).store_buffer(_kept)
	GraphicsQuality.level = -1
	CwAccess.apply()
	print("%d checks" % _checks)
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL  " + what)


static func _saved(section: String, key: String) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg.get_value(section, key) if cfg.has_section_key(section, key) else null


func _text_size() -> void:
	print("text size")
	_check(is_equal_approx(CwAccess.ui_scale(), 1.0), "the text size starts at 100 %")
	CwAccess.set_ui_scale(1.3)
	_check(is_equal_approx(float(_saved("access", "ui_scale")), 1.3), "130 %% is saved")
	_check(is_equal_approx(root.content_scale_factor, 1.3), "130 %% scales the root (%s)" % root.content_scale_factor)
	CwAccess.set_ui_scale(1.2)
	_check(is_equal_approx(CwAccess.ui_scale(), 1.15), "1.2 snaps to 115 %% (%s)" % CwAccess.ui_scale())
	CwAccess.set_ui_scale(0.9)
	_check(is_equal_approx(root.content_scale_factor, 0.9), "90 % scales the root")
	CwAccess.set_ui_scale(1.0)
	_check(is_equal_approx(root.content_scale_factor, 1.0), "back to 100 %")


## A stand-in for the campus: an environment with every effect, a shadowed sun, a lamp of the
## campus, a big floodlight, a grass scatter (100 instances) and a tree scatter.
func _scene() -> Node3D:
	var campus := Node3D.new()
	campus.name = "FakeCampus"
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.ssao_enabled = true
	we.environment.ssil_enabled = true
	we.environment.glow_enabled = true
	campus.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	campus.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.omni_range = 10.0
	lamp.shadow_enabled = true
	lamp.add_to_group(&"campus_lamps")
	campus.add_child(lamp)
	var flood := SpotLight3D.new()
	flood.name = "Flood"
	flood.spot_range = 40.0
	campus.add_child(flood)
	for n in ["Grass", "Trees"]:
		var sc := CampusScatter.new()
		sc.name = n
		sc.blocks_walkers = n == "Trees"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new()
		mm.instance_count = 100
		sc.multimesh = mm
		campus.add_child(sc)
	return campus


func _quality() -> void:
	print("graphics quality")
	GraphicsQuality.set_level(GraphicsQuality.Level.LOW)
	_check(int(_saved("graphics", "quality")) == GraphicsQuality.Level.LOW, "Baixo is saved")
	GraphicsQuality.level = -1   # as after a restart
	_check(GraphicsQuality.current() == GraphicsQuality.Level.LOW, "Baixo is read back")
	# added after the level is set: the watch applies it as the scene enters the tree
	var sc := _scene()
	root.add_child(sc)
	await process_frame
	var env := (sc.get_child(0) as WorldEnvironment).environment
	var grass := sc.get_node("Grass") as CampusScatter
	var trees := sc.get_node("Trees") as CampusScatter
	var lamp := sc.get_node("Lamp") as OmniLight3D
	var flood := sc.get_node("Flood") as SpotLight3D
	var sun := sc.get_child(1) as DirectionalLight3D
	_check(not env.ssao_enabled and not env.ssil_enabled and not env.glow_enabled, "Baixo: SSAO, SSIL and glow off")
	_check(root.scaling_3d_scale < 1.0 and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR,
		"Baixo: lower 3D render scale (%s)" % root.scaling_3d_scale)
	_check(root.msaa_3d == Viewport.MSAA_DISABLED and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED,
		"Baixo: no anti-aliasing")
	_check(grass.multimesh.visible_instance_count == 35, "Baixo: 35 of 100 grass tufts (%d)" % grass.multimesh.visible_instance_count)
	_check(trees.multimesh.visible_instance_count == -1, "Baixo: the trees (walkers go round them) all stay")
	_check(not lamp.visible and not lamp.shadow_enabled, "Baixo: the campus lamp is off")
	_check(flood.visible, "Baixo: the floodlight (not a lamp) stays")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "Baixo: one shadow split")
	GraphicsQuality.set_level(GraphicsQuality.Level.HIGH)
	_check(env.ssao_enabled and env.ssil_enabled and env.glow_enabled, "Alto: the scene's effects come back")
	_check(is_equal_approx(root.scaling_3d_scale, 1.0), "Alto: full render scale")
	_check(root.screen_space_aa == CwLook.aa_screen_space(CwLook.antialiasing()), "Alto: the player's AA again")
	_check(grass.multimesh.visible_instance_count == -1, "Alto: all the grass")
	_check(lamp.visible and lamp.shadow_enabled, "Alto: the lamp and its shadow are back")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Alto: four shadow splits")
	GraphicsQuality.set_level(GraphicsQuality.Level.MEDIUM)
	_check(grass.multimesh.visible_instance_count == 70 and lamp.visible and not lamp.shadow_enabled,
		"Médio: 70 % grass, lamps without shadows")
	sc.queue_free()
	await process_frame


func _colorblind() -> void:
	print("colour-blind mode")
	var s := TycoonState.new_campaign(7)
	var ids := [RaceDirector.PLAYER]
	for r: Dictionary in s.rivals:
		ids.append(String(r["id"]))
	_check(CwPalette.cue_of(s.race.agency_color(ids[1])) == CwPalette.Cue.NONE, "off: no shape cues")
	CwAccess.set_colorblind(true)
	_check(bool(_saved("access", "colorblind")), "colour-blind mode is saved")
	_check(CwPalette.colorblind, "colour-blind mode is on")
	var cols := {}
	var cues := {}
	for id: String in ids:
		var c := s.race.agency_color(id)
		cols[c.to_html()] = true
		cues[CwPalette.cue_of(c)] = true
	_check(cols.size() == ids.size(), "every agency has its own colour")
	_check(cues.size() == ids.size() and not cues.has(CwPalette.Cue.NONE), "every agency has its own shape cue (%s)" % [cues.keys()])
	_check(TycoonLeader.agency_color(s, CwPalette.IGNITION) == s.race.agency_color(RaceDirector.PLAYER),
		"the player's colour is the same on the map and the race")
	var kinds := {}
	for k: String in CwPalette.CB_KIND:
		kinds[CwPalette.cue_of(CwPalette.kind(k, Color.WHITE))] = true
	_check(kinds.size() == CwPalette.CB_KIND.size(), "every briefing kind has its own shape cue")
	CwAccess.set_colorblind(false)
	_check(not CwPalette.colorblind and s.race.agency_color(RaceDirector.PLAYER) == CwPalette.IGNITION, "off again: the usual colours")


func _keys() -> void:
	print("keys")
	CwKeys.reset_defaults()
	_check(CwKeys.key_of(&"cw_pause") == KEY_SPACE, "pause starts on Space")
	CwKeys.rebind(&"cw_pause", KEY_P)
	_check(CwKeys.key_of(&"cw_pause") == KEY_P, "pause on P")
	_check(int(_saved("keys", "cw_pause")) == KEY_P, "P is saved")
	# as after a restart: the defaults first, then the saved keys
	CwKeys._set_events(&"cw_pause", KEY_SPACE)
	CwKeys.apply()
	_check(CwKeys.key_of(&"cw_pause") == KEY_P, "P is restored")
	var ev := InputEventKey.new()
	ev.keycode = KEY_P
	ev.pressed = true
	_check(CwKeys.pressed(ev, &"cw_pause"), "a P press is the pause action")
	ev.keycode = KEY_SPACE
	_check(not CwKeys.pressed(ev, &"cw_pause"), "Space no longer pauses")
	var swapped := CwKeys.rebind(&"cw_map", KEY_P)
	_check(swapped == &"cw_pause" and CwKeys.key_of(&"cw_pause") == KEY_M and CwKeys.key_of(&"cw_map") == KEY_P,
		"a taken key swaps (pause gets M)")
	_check(CwKeys.rebind(&"cw_map", KEY_ESCAPE) == &"" and CwKeys.key_of(&"cw_map") == KEY_P, "Esc cannot be bound")
	ev.keycode = KEY_LEFT
	_check(CwKeys.pressed(ev, &"cw_cam_left"), "the arrows always work")
	CwKeys.reset_defaults()
	_check(CwKeys.key_of(&"cw_pause") == KEY_SPACE and CwKeys.key_of(&"cw_map") == KEY_M, "Restore keys")
	_check(_saved("keys", "cw_pause") == null, "the defaults leave nothing saved")


func _panel() -> void:
	print("options panel")
	var panel := (load("res://scenes/menu/options_panel.tscn") as PackedScene).instantiate() as MenuOptionsPanel
	root.add_child(panel)
	await process_frame
	panel.show_page("access")
	_check((panel.grid.get_node("TextSize") as Control).visible and not (panel.grid.get_node("Lang") as Control).visible,
		"the Access page shows its rows")
	(panel.quality_buttons[GraphicsQuality.Level.LOW] as Button).emit_signal("pressed")
	_check(GraphicsQuality.current() == GraphicsQuality.Level.LOW, "the Baixo key sets Baixo")
	_check(panel.aa_smaa.disabled, "Baixo greys out the AA keys")
	(panel.quality_buttons[GraphicsQuality.Level.HIGH] as Button).emit_signal("pressed")
	_check(not panel.aa_smaa.disabled, "Alto lets the AA be chosen")
	panel.text_buttons[2].emit_signal("pressed")
	_check(is_equal_approx(CwAccess.ui_scale(), 1.15), "the 115 % key sets 115 %")
	panel.text_buttons[1].emit_signal("pressed")
	panel.colorblind_on.emit_signal("pressed")
	_check(CwAccess.colorblind(), "the colour-blind key turns it on")
	panel.colorblind_off.emit_signal("pressed")
	var list := panel.get_node("%KeyList")
	_check(list.get_child_count() - 1 == CwKeys.ids().size(), "one key row per action")
	panel.listen(&"cw_speed_1")
	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	ev.pressed = true
	root.push_input(ev)
	await process_frame
	_check(CwKeys.key_of(&"cw_speed_1") == KEY_J and panel.listening == &"", "a key row takes the next key (J)")
	var row := list.get_child(2)
	_check((row.get_node("Key") as Button).text == OS.get_keycode_string(KEY_J), "the row shows J")
	panel.get_node("%KeysReset").emit_signal("pressed")
	_check(CwKeys.key_of(&"cw_speed_1") == KEY_1, "Restore keys from the panel")
	panel.queue_free()
	await process_frame
