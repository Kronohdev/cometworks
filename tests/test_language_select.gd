extends SceneTree
## The language screen (scenes/menu/language_select.tscn, LanguageSelect) between the intro and
## the main menu:
##   - the intro's end opens the language screen (not the menu), and the intro still quits
##     instead with --intro-quit / quit_at_end (movie capture); choosing a language there opens
##     the main menu;
##   - choosing Português or English sets the locale at once (the labels follow) and saves it
##     (MenuSettings.saved_locale), and says `chosen`;
##   - the keyboard: ← / → (and A / D) send the Cometling to a side and highlight that language,
##     the Cometling really walks there (and faces the way it goes), Enter chooses;
##   - the mouse: the Cometling follows the mouse x, a click on a flag chooses it;
##   - the last chosen language starts highlighted with the Cometling at its flag;
##   - the language names stay in their own language, the subtitle previews the highlighted one;
##   - an Enter right as the screen opens (mashed to skip the intro) does not choose.
## user://settings.cfg is put back as it was.
## Run: godot --headless --path . --script res://tests/test_language_select.gd

const INTRO := "res://scenes/menu/intro.tscn"
const SCENE := "res://scenes/menu/language_select.tscn"
const MENU := "res://scenes/menu/main_menu.tscn"
const SETTINGS := "user://settings.cfg"

var _failures := 0
var _kept: Variant = null


func _initialize() -> void:
	_kept = FileAccess.get_file_as_bytes(SETTINGS) if FileAccess.file_exists(SETTINGS) else null
	await process_frame
	await _preselect()
	await _choose()
	await _keyboard()
	await _mouse()
	await _flow()
	if _kept == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	else:
		FileAccess.open(SETTINGS, FileAccess.WRITE).store_buffer(_kept)
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _open() -> LanguageSelect:
	var ls := (load(SCENE) as PackedScene).instantiate() as LanguageSelect
	ls.open_menu_on_choice = false
	root.add_child(ls)
	await _frames(3)
	return ls


func _close(ls: Node) -> void:
	ls.queue_free()
	await _frames(2)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		root.push_input(e)


## The Cometling's x on the Stage (px).
static func _cx(ls: LanguageSelect) -> float:
	return float(ls.get("_x"))


# ------------------------------------------------------------------ preselection
func _preselect() -> void:
	print("the last choice starts highlighted")
	for loc: String in ["pt", "en"]:
		MenuSettings.set_locale(loc)
		TranslationServer.set_locale("en" if loc == "pt" else "pt")   # _ready applies the saved one
		var ls := await _open()
		var end := ls.walk_x.x if loc == "pt" else ls.walk_x.y
		_check(ls.selected == loc, "%s saved: %s is highlighted (got %s)" % [loc, loc, ls.selected])
		_check(is_equal_approx(_cx(ls), end), "...and the Cometling starts at its flag (%.0f, flag %.0f)" % [_cx(ls), end])
		var pt := ls.get_node("%PT") as LanguageStation
		var en := ls.get_node("%EN") as LanguageStation
		_check(pt.lit == (loc == "pt") and en.lit == (loc == "en"), "...only that flag is lit")
		_check(MenuSettings.locale() == loc, "...and the game is in it (%s)" % TranslationServer.get_locale())
		_check(ls.subtitle.text == LanguageSelect.text_in("LANG_SUBTITLE", loc) and ls.subtitle.text != "LANG_SUBTITLE",
			"...the subtitle is in it: %s" % ls.subtitle.text)
		_check((pt.get_node("Plaque/Name") as Label).text == "Português" and (en.get_node("Plaque/Name") as Label).text == "English",
			"the language names stay in their own language")
		# a key mashed to skip the intro does not choose right as the screen opens
		ls.celebrate_time = 0.05
		_key(KEY_ENTER)
		await _frames(2)
		_check(not ls.confirmed, "...an Enter in the first moment (skipping the intro) does not choose")
		await _wait(LanguageSelect.GRACE)
		# then Enter confirms at once: the Cometling is already there
		_key(KEY_ENTER)
		await _frames(2)
		_check(ls.confirmed and ls.get("_celebrated"), "...Enter chooses it at once and the celebration starts")
		_check(MenuSettings.saved_locale() == loc, "...the choice is kept (%s)" % MenuSettings.saved_locale())
		await _close(ls)


# ------------------------------------------------------------------ choosing
func _choose() -> void:
	print("choosing sets and saves the locale")
	for pair: Array in [["pt", "en"], ["en", "pt"]]:
		var from: String = pair[0]
		var to: String = pair[1]
		MenuSettings.set_locale(from)
		var ls := await _open()
		var said: Array = []
		ls.chosen.connect(func(l: String) -> void: said.append(l))
		ls.choose(to)
		await _frames(2)
		_check(said == [to], "choose(%s) says chosen(%s) (got %s)" % [to, to, said])
		_check(MenuSettings.locale() == to, "...the locale is %s right away (%s)" % [to, TranslationServer.get_locale()])
		_check(MenuSettings.saved_locale() == to, "...and saved (%s)" % MenuSettings.saved_locale())
		_check(ls.subtitle.text == LanguageSelect.text_in("LANG_SUBTITLE", to), "...the labels follow: %s" % ls.subtitle.text)
		_check(ls.get_node("%GoLabel").text == TranslationServer.translate("LANG_GO") or not ls.get("_celebrated"),
			"...the cheer is in %s" % to)
		await _wait(1.6)
		_check(ls.get("_celebrated"), "...the Cometling ran over and celebrated")
		_check(absf(_cx(ls) - ls.call("_end_of", to)) < 31.0, "...at the %s flag (x %.0f)" % [to, _cx(ls)])
		ls.choose(from)
		await _frames(2)
		_check(MenuSettings.saved_locale() == to, "...a second choice is ignored")
		await _close(ls)


# ------------------------------------------------------------------ keyboard
func _keyboard() -> void:
	print("the keyboard")
	MenuSettings.set_locale("en")
	var ls := await _open()
	var x0 := _cx(ls)
	_key(KEY_LEFT)
	await _frames(2)
	_check(ls.selected == "pt", "← highlights Português (got %s)" % ls.selected)
	_check((ls.get_node("%PT") as LanguageStation).lit, "...its flag lights up")
	_check(ls.move_hint.text == LanguageSelect.text_in("LANG_HINT_MOVE", "pt"), "...the hints preview it: %s" % ls.move_hint.text)
	await _wait(0.3)
	var v := float(ls.get("_v"))
	_check(v < -50.0, "...the Cometling sets off to the left (%.0f px/s)" % v)
	var yaw := float(ls.creature.rotation.y)
	_check(yaw < -0.5, "...facing the way it goes (yaw %.2f)" % yaw)
	await _wait(1.6)
	_check(_cx(ls) < x0 - 300.0 and absf(_cx(ls) - ls.walk_x.x) < 2.0, "...and gets to the Brazilian flag (x %.0f -> %.0f)" % [x0, _cx(ls)])
	_key(KEY_D)
	await _frames(2)
	_check(ls.selected == "en", "D highlights English")
	_key(KEY_A)
	await _frames(2)
	_check(ls.selected == "pt", "A highlights Português")
	_key(KEY_RIGHT)
	await _frames(2)
	_check(ls.selected == "en", "→ highlights English")
	_key(KEY_LEFT)
	await _frames(2)
	_key(KEY_SPACE)
	await _frames(2)
	_check(ls.confirmed and MenuSettings.saved_locale() == "pt", "Space chooses the highlighted one (Português)")
	_key(KEY_RIGHT)
	await _frames(2)
	_check(ls.selected == "pt", "after choosing the keys do nothing")
	await _close(ls)


# ------------------------------------------------------------------ mouse
func _mouse() -> void:
	print("the mouse")
	MenuSettings.set_locale("pt")
	var ls := await _open()
	var stage := ls.stage
	var to_screen := stage.get_global_transform_with_canvas()
	var m := InputEventMouseMotion.new()
	m.position = to_screen * Vector2(stage.size.x * 0.5 + 120.0, 300.0)
	m.global_position = m.position
	root.push_input(m, true)
	await _frames(2)
	_check(ls.selected == "en", "the mouse right of the middle highlights English")
	_check(is_equal_approx(float(ls.get("_target")), stage.size.x * 0.5 + 120.0), "...and the Cometling follows its x")
	await _wait(1.2)
	_check(absf(_cx(ls) - (stage.size.x * 0.5 + 120.0)) < 3.0, "...and stops under it (x %.0f)" % _cx(ls))
	m = m.duplicate()
	m.position = to_screen * Vector2(5.0, 300.0)
	root.push_input(m, true)
	await _frames(2)
	_check(ls.selected == "pt" and is_equal_approx(float(ls.get("_target")), ls.walk_x.x),
		"far left: Português, the walk stops at its flag")
	# a click on the US flag chooses English
	var en := ls.get_node("%EN") as LanguageStation
	var c := en.get_global_transform_with_canvas() * (en.size * 0.5)
	m = m.duplicate()
	m.position = c
	root.push_input(m, true)
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.position = c
		b.global_position = c
		root.push_input(b, true)
	await _frames(2)
	_check(ls.confirmed and MenuSettings.saved_locale() == "en", "a click on the US flag chooses English")
	await _close(ls)


# ------------------------------------------------------------------ the flow
func _flow() -> void:
	print("intro -> language screen -> main menu")
	var src := FileAccess.get_file_as_string("res://src/menu/intro.gd")
	var open_fn := src.substr(src.find("func _open_menu"))
	open_fn = open_fn.substr(0, open_fn.find("\nfunc ", 5))
	_check(open_fn.find("--intro-quit") >= 0 and open_fn.find("quit()") < open_fn.find("LANGUAGE"),
		"the intro still quits first with --intro-quit / quit_at_end (no language screen)")
	MenuSettings.set_locale("pt")
	var intro := (load(INTRO) as PackedScene).instantiate()
	root.add_child(intro)
	current_scene = intro
	await _frames(3)
	intro.call("_open_menu")
	await _frames(4)
	var ls := current_scene as LanguageSelect
	_check(ls != null and ls.scene_file_path == SCENE,
		"the intro's end opens the language screen (%s)" % (current_scene.scene_file_path if current_scene else "none"))
	if ls == null:
		return
	_check(not is_instance_valid(intro), "...and the intro is gone")
	ls.celebrate_time = 0.1
	ls.fade_time = 0.1
	ls.choose("en")
	await _wait(1.8)
	_check(current_scene != null and current_scene.scene_file_path == MENU,
		"choosing opens the main menu (%s)" % (current_scene.scene_file_path if current_scene else "none"))
	_check(MenuSettings.locale() == "en", "...in English")
	if current_scene:
		current_scene.queue_free()
	await _frames(3)
