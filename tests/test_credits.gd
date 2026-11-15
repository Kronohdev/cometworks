extends SceneTree
## Credits and the tidier main menu:
##   - the menu's top level is Nova campanha, Continuar, Mais modos, Conquistas, Opções, Créditos,
##     Sair; "Mais modos" swaps in the other ways to play (Modo feira, Demonstração, Oficina,
##     Sistema Solar, Superfícies), every one of them reachable and wired, and Back / Esc returns;
##   - the card ends above the footer at 1920x1080, 1600x900 and 1366x768, in both lists;
##   - data/credits.json loads: four developers with names, role lines in both languages and
##     looks, one lead, and the credit sections; the Créditos screen opens, puts each developer
##     on the stage with Kauã in the spotlight, left / right (arrows, A / D, the ‹ › buttons)
##     move the spotlight and wrap around, the info card's name and role follow, and Esc closes;
##   - the Cometling's personal looks (CometlingStyle) are off by default: a plain Cometling
##     has exactly the meshes and vertices it had, and a styled one gets its parts.
## Run: godot --headless --path . --script res://tests/test_credits.gd

const MENU := "res://scenes/menu/main_menu.tscn"
const CREATURE := "res://scenes/npc/creature.tscn"

var _failures := 0


func _initialize() -> void:
	await process_frame
	await _creature()
	await _data()
	await _menu()
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# ------------------------------------------------------------------ creature
## Mesh instances and vertices under a Cometling (the voxel count).
func _voxels(c: Node) -> Vector2i:
	var meshes := 0
	var verts := 0
	for n in c.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		meshes += 1
		for s in mi.mesh.get_surface_count():
			verts += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return Vector2i(meshes, verts)


func _creature() -> void:
	print("creature looks")
	var ps := load(CREATURE) as PackedScene
	# reference: the scene's own meshes, counted before the script can add anything
	var probe := ps.instantiate() as Node3D
	var expected := Vector2i.ZERO
	for n in probe.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh:
			expected.x += 1
	probe.free()
	var plain := ps.instantiate() as Cometling
	plain.listen_to_events = false
	root.add_child(plain)
	await _frames(2)
	_check(plain.style.is_empty(), "style is empty by default")
	var count := 0
	for n in plain.find_children("*", "MeshInstance3D", true, false):
		count += 1
	_check(count == expected.x, "a plain Cometling has the scene's %d meshes (got %d)" % [expected.x, count])
	_check(plain.find_children("Style*", "", true, false).is_empty(), "...and no Style parts")
	var before := _voxels(plain)
	# a styled twin, then the style taken off again: back to the very same voxels
	var styled := ps.instantiate() as Cometling
	styled.listen_to_events = false
	root.add_child(styled)
	await _frames(1)
	_check(_voxels(styled) == before, "two plain Cometlings have the same voxel count (%s)" % before)
	styled.style = {"hair": "mullet", "hair_color": "#dda640", "facial_hair": ["goatee", "moustache"],
		"eyes": "#4fae5c", "glasses": "#7f889c", "headphones": "#2b2d3a", "streak": "#f4dc8c"}
	await _frames(1)
	var neck := styled.get_node("Rig/Hips/Neck")
	for part in ["StyleHair", "StyleHairTop", "StyleFacialHair", "StyleGlasses"]:
		_check(neck.get_node_or_null(part) != null, "a styled Cometling has %s" % part)
	_check(styled.get_node_or_null("Rig/Hips/StyleHeadphones") != null, "...and headphones on the hips")
	var eye := styled.get_node("Rig/Hips/Neck/EyeL").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var plain_eye := plain.get_node("Rig/Hips/Neck/EyeL").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_check(eye.mesh != plain_eye.mesh, "the iris colour gives the eye its own mesh")
	_check(_voxels(styled).y > before.y, "the parts add voxels")
	LeaderHat.wear(styled, "beanie")
	_check(not (neck.get_node("StyleHairTop") as Node3D).visible, "a hat hides the hair's crown")
	LeaderHat.wear(styled, "role")
	styled.role = "ground"
	_check((neck.get_node("StyleHairTop") as Node3D).visible, "...and it comes back without the hat")
	styled.style = {}
	await _frames(2)
	_check(_voxels(styled) == before, "taking the style off restores the plain voxels (%s)" % _voxels(styled))
	_check(eye.mesh == plain_eye.mesh, "...and the eye's own mesh")
	plain.queue_free()
	styled.queue_free()
	await _frames(2)


# ------------------------------------------------------------------ data
func _data() -> void:
	print("credits data")
	var devs := CreditsScreen.developers()
	_check(devs.size() == 4, "four developers (got %d)" % devs.size())
	var leads := 0
	for d in devs:
		var role: Variant = d.get("role", {})
		_check(String(d.get("name", "")) != "", "%s has a name" % d.get("id", "?"))
		_check(role is Dictionary and String(role.get("pt", "")) != "" and String(role.get("en", "")) != "",
			"%s has a role line in pt and en" % d.get("id", "?"))
		_check((d.get("look", {}) as Dictionary).has("style"), "%s has a look with a style" % d.get("id", "?"))
		if bool(d.get("lead", false)):
			leads += 1
			_check(String(role.get("pt", "")) == "Direção e desenvolvimento", "the lead's role line")
	_check(leads == 1, "exactly one lead")
	_check(CreditsScreen.sections().size() >= 3, "the credit sections load")
	var emblem := String(CreditsScreen.data().get("emblem", ""))
	_check(ResourceLoader.exists(emblem), "the emblem exists (%s)" % emblem)


# ------------------------------------------------------------------ menu
func _menu() -> void:
	print("menu")
	var menu := (load(MENU) as PackedScene).instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await _frames(30)
	# the menu's entry animation ends by focusing Nova campanha (about 1.2 s): let it finish
	# before checking where the keyboard is
	await create_timer(1.6).timeout
	var top := ["NewCampaign", "Continue", "MoreModes", "Achievements", "Options", "Credits", "Quit"]
	var shown: Array[String] = []
	for c in menu.main_list.get_children():
		if c is Button and (c as Control).visible:
			shown.append(String(c.name))
	_check(shown == top, "top level: %s" % ", ".join(shown))
	var modes := ["Fair", "Demo", "Workshop", "SolarSystem", "Surfaces"]
	for m in modes:
		var b := menu.get_node("%" + m) as Button
		_check(b != null and menu.modes_list.is_ancestor_of(b), "%s lives in the Mais modos list" % m)
		_check(b != null and b.pressed.get_connections().size() > 0, "%s is wired" % m)
	_check(not menu.modes_list.visible, "the modes list starts closed")
	await _footer(menu, "main list")
	menu.more_button.pressed.emit()
	await _frames(20)
	_check(menu.is_more_open() and not menu.main_list.visible, "Mais modos opens the list")
	_check(menu.fair.has_focus(), "...with the keyboard on Modo feira")
	for m in modes:
		_check((menu.get_node("%" + m) as Control).is_visible_in_tree(), "%s is reachable" % m)
	await _footer(menu, "modes list")
	# the demonstration panel opens from the list and Esc closes it first, not the list
	if not menu.demo.disabled:
		menu.demo.pressed.emit()
		await _frames(10)
		_check(menu.demo_panel.visible, "Demonstração opens its panel")
		_esc()
		await _frames(30)
		_check(not menu.demo_panel.visible and menu.is_more_open(), "Esc closes the demo panel and keeps the list")
	menu.surfaces.pressed.emit()
	await _frames(5)
	_check(menu.surface_picker.visible, "Superfícies opens the surface picker")
	menu.surface_picker.close()
	await _frames(5)
	menu.back_button.pressed.emit()
	await _frames(10)
	_check(not menu.is_more_open() and menu.main_list.visible, "Back returns to the main list")
	_check(menu.more_button.has_focus(), "...with the keyboard on Mais modos")
	menu.open_more()
	await _frames(5)
	_esc()
	await _frames(10)
	_check(not menu.is_more_open(), "Esc returns to the main list too")
	# credits
	menu.credits_button.pressed.emit()
	await _frames(20)
	var scr := menu.get_node_or_null("UI/Root/Credits") as CreditsScreen
	_check(scr != null, "Créditos opens the credits screen")
	if scr:
		await _spotlight(scr)
		_esc()
		await _frames(40)
		_check(menu.get_node_or_null("UI/Root/Credits") == null, "Esc closes the credits")
		_check(not menu.is_more_open(), "...and Esc there does not touch the menu lists")
	menu.queue_free()
	await _frames(3)


## The spotlight: Kauã first, left / right (keys, A / D, the buttons) move it and wrap around,
## the chosen one slides to the middle slot and the info card follows, with their signature.
func _spotlight(scr: CreditsScreen) -> void:
	_check(scr._stage.size() == 4, "four Cometlings on the stage")
	var styled := 0
	for c in scr._stage:
		if c.find_child("StyleHair", true, false):
			styled += 1
	_check(styled == 4, "every developer wears their hair (%d)" % styled)
	_check(scr._cards.size() == 4, "four name chips")
	var devs := CreditsScreen.developers()
	var kaua := CreditsScreen.lead_index()
	_check(String(devs[kaua]["id"]) == "kaua", "the lead in the data is Kauã")
	_check(scr.selected == kaua, "Kauã is in the spotlight when the screen opens")
	_check(scr.info_name.text == "Kauã", "the info card names him (%s)" % scr.info_name.text)
	_check(scr.info_role.text == CreditsScreen.role_text(devs[kaua]), "...with his role line (%s)" % scr.info_role.text)
	_check(scr.info_star.visible, "...and the director's star")
	_check(scr._stage[kaua].transform.is_equal_approx((scr.get_node("%SlotCenter") as Node3D).transform),
		"he stands in the middle slot, on the podium")
	_check((scr.get_node("%Hint") as Label).text != "", "the switch hint shows")
	for d in devs:
		_check(CreditsScreen.signature(d).size() >= 2, "%s has a signature of a few steps" % d["id"])
		_check(CreditsScreen.bio_text(d) != "", "%s has a bio line" % d["id"])
	# keyboard: right moves on
	_key(KEY_RIGHT)
	await _frames(2)
	var next := posmod(kaua + 1, devs.size())
	_check(scr.selected == next, "→ moves the spotlight to %s" % devs[next]["name"])
	_check(scr.info_name.text == String(devs[next]["name"]), "the info card follows (%s)" % scr.info_name.text)
	_check(scr.info_role.text == CreditsScreen.role_text(devs[next]), "the role label updates (%s)" % scr.info_role.text)
	_check(not scr.info_star.visible or bool(devs[next].get("lead", false)), "the star stays with the lead")
	await _settle(scr)
	_check(scr._stage[next].transform.is_equal_approx((scr.get_node("%SlotCenter") as Node3D).transform),
		"%s slides into the middle slot" % devs[next]["name"])
	_check(scr._stage[kaua].scale.x < 1.1, "Kauã steps back to the side")
	var t0 := Time.get_ticks_msec()
	while not scr.is_showing() and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	_check(scr.is_showing(), "the one in the middle plays their signature")
	# wrap around both ways
	for i in devs.size():
		scr.select_next()
	await _frames(2)
	_check(scr.selected == next, "four times → comes back around (wraps)")
	scr.select(0)
	await _frames(2)
	scr.select_prev()
	await _frames(2)
	_check(scr.selected == devs.size() - 1, "← from the first goes to the last (wraps)")
	_check(scr.info_role.text == CreditsScreen.role_text(devs[devs.size() - 1]), "...and the role label follows")
	_key(KEY_A)
	await _frames(2)
	_check(scr.selected == devs.size() - 2, "A moves left too")
	_key(KEY_D)
	await _frames(2)
	_check(scr.selected == devs.size() - 1, "D moves right too")
	(scr.get_node("%Prev") as Button).pressed.emit()
	await _frames(2)
	_check(scr.selected == devs.size() - 2, "the ‹ button moves left")
	(scr.get_node("%Next") as Button).pressed.emit()
	await _frames(2)
	_check(scr.selected == devs.size() - 1, "the › button moves right")
	scr.select(kaua)
	await _frames(40)
	_check(scr.selected == kaua and scr.info_star.visible, "back to Kauã, the star returns")


## Waits until the stage's slide tween has finished (loaded machines run slow frames), at most 10 s.
func _settle(scr: CreditsScreen) -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(2)
	while scr._slide != null and scr._slide.is_valid() and scr._slide.is_running() \
			and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	await _frames(1)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


func _esc() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)


## The card ends above the footer at the three window sizes (16:9: one logical 1600x900 view).
func _footer(menu: MainMenu, tag: String) -> void:
	for res in [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1366, 768)]:
		root.size = res
		await _frames(4)
		var card := menu.panel.get_global_rect()
		var footer := (menu.get_node("UI/Root/Footer") as Control).get_global_rect()
		_check(card.end.y + 4.0 <= footer.position.y,
			"%s at %dx%d: card ends at %.0f, above the footer at %.0f" % [tag, res.x, res.y, card.end.y, footer.position.y])
