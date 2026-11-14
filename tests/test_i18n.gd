extends SceneTree
## Português e inglês conferidos tela por tela: a headless audit of the translations.
## Static part:
##   - every key of i18n/*.csv has an English and a Portuguese text, the same %d / %s
##     placeholders in both, and no key is defined twice with different texts;
##   - every key a scene (text, tooltip_text, placeholder_text, title), a script (tr("..."),
##     "..._key": "...") or the data (fields ending in _key) uses exists, and every {"en", "pt"}
##     text in data/*.json has both languages.
## Screen walk, in pt and in en: the main menu (and its Demonstração panel), the leader
## creator, every HUD screen of a campus loaded from a demonstration save (era 3) and the
## hangar. Every visible text is read as the player sees it (Node.atr) and fails when it shows
## a raw key, when a Portuguese screen shows a text that only exists in English (an English
## translation or an English part name), or an English screen one that only exists in
## Portuguese.
## Run: godot --headless --path . --script res://tests/test_i18n.gd

const I18N := "res://i18n/"
const SCAN_DIRS := ["res://scenes/", "res://src/", "res://ui/"]
const DATA_DIRS := ["res://data/", "res://data/tycoon/"]
const SCREENS_DIR := "res://scenes/tycoon/ui/screens/"
const MENU := "res://scenes/menu/main_menu.tscn"
const LEADER := "res://scenes/tycoon/ui/screens/leader_creator.tscn"
const TYCOON := "res://scenes/tycoon/tycoon_main.tscn"
const HANGAR := "res://scenes/hangar.tscn"
const DEMO_SLOT := "demo_era3"
const KEEP := ["user://settings.cfg"]
## Texts that are the same word in both languages or proper names (not a missing translation).
const SHARED_WORDS := ["Hangar", "Total", "Hype", "Rover", "Radar", "Normal", "Radial", "Solar", "Zoom", "Menu"]

var _failures := 0
var _keys := {}            # key -> {"en", "pt", "file"}
var _en_only := {}         # text -> key: English texts with no equal Portuguese text
var _pt_only := {}         # text -> key
var _raw := RegEx.create_from_string("\\b[A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+\\b")
var _flagged := {}
var _en_surname: RegEx      # an English Cometling surname ("Moonbean"): CrewRoster.SUR_A + SUR_B
var _kept := {}


func _initialize() -> void:
	for p in KEEP:
		_kept[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null
	_read_csvs()
	_static_scenes_and_scripts()
	_static_data()
	_build_language_sets()
	_en_surname = RegEx.create_from_string("\\b(%s)(%s)\\b" % ["|".join(CrewRoster.SUR_A), "|".join(CrewRoster.SUR_B)])
	_check(CrewRoster.generate_name(_seeded(), "pt") != CrewRoster.generate_name(_seeded(), "en")
		and _en_surname.search(CrewRoster.generate_name(_seeded(), "pt")) == null,
		"a Cometling hired in Portuguese gets a Portuguese surname (%s)" % CrewRoster.generate_name(_seeded(), "pt"))
	for loc in ["pt", "en"]:
		MenuSettings.set_locale(loc)   # the main menu applies the saved language (settings.cfg is put back)
		await _walk_menu(loc)
		await _walk_leader(loc)
		await _walk_campus(loc)
		await _walk_hangar(loc)
	MenuSettings.set_locale("pt")
	for p: String in _kept:
		if _kept[p] == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
		else:
			FileAccess.open(p, FileAccess.WRITE).store_buffer(_kept[p])
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


# ------------------------------------------------------------ static checks
func _read_csvs() -> void:
	print("translation tables")
	var spec := RegEx.create_from_string("%[-+0#]*\\d*(?:\\.\\d+)?[sdifxXc]")
	var files := 0
	for f in DirAccess.get_files_at(I18N):
		if not f.ends_with(".csv"):
			continue
		files += 1
		var fa := FileAccess.open(I18N + f, FileAccess.READ)
		var head := fa.get_csv_line()
		var ie := head.find("en")
		var ip := head.find("pt")
		_check(ie > 0 and ip > 0, "%s has en and pt columns" % f)
		while not fa.eof_reached():
			var row := fa.get_csv_line()
			if row.size() == 0 or row[0].strip_edges() == "" or row[0].begins_with("#"):
				continue
			var key := row[0]
			var en := row[ie] if row.size() > ie else ""
			var pt := row[ip] if row.size() > ip else ""
			if en.strip_edges() == "" or pt.strip_edges() == "":
				_fail("%s: %s has no %s text" % [f, key, "English" if en.strip_edges() == "" else "Portuguese"])
			var se := _sorted(spec.search_all(en))
			var sp := _sorted(spec.search_all(pt))
			if se != sp:
				_fail("%s: %s has placeholders %s in en but %s in pt" % [f, key, se, sp])
			if _keys.has(key) and (_keys[key]["en"] != en or _keys[key]["pt"] != pt):
				_fail("%s: %s is also in %s with another text" % [f, key, _keys[key]["file"]])
			_keys[key] = {"en": en, "pt": pt, "file": f}
	_check(files > 10 and _keys.size() > 1000, "read %d tables, %d keys" % [files, _keys.size()])
	# every table is loaded by the project
	var loaded: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	for f in DirAccess.get_files_at(I18N):
		if f.ends_with(".csv"):
			var base := f.get_basename()
			if not (I18N + base + ".pt.translation") in loaded or not (I18N + base + ".en.translation") in loaded:
				_fail("%s is not in the project's translations" % f)
	_check(TranslationServer.get_translation_object("pt") != null, "the Portuguese translation is loaded")


func _sorted(ms: Array[RegExMatch]) -> Array:
	var out: Array = []
	for m in ms:
		out.append(m.get_string())
	out.sort()
	return out


func _static_scenes_and_scripts() -> void:
	print("keys used by scenes and scripts")
	var prop := RegEx.create_from_string("^(?:text|tooltip_text|placeholder_text|title) = \"([A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+)\"$")
	var trcall := RegEx.create_from_string("\\btr\\(\"([A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+)\"\\)")
	var keyfield := RegEx.create_from_string("_key\"?\\s*[:=]\\s*\"([A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+)\"")
	var n_scenes := 0
	var n_scripts := 0
	var used := 0
	for dir: String in SCAN_DIRS:
		for path in _files(dir):
			if path.ends_with(".tscn") or path.ends_with(".tres"):
				n_scenes += 1
				for line in FileAccess.get_file_as_string(path).split("\n"):
					var m := prop.search(line)
					if m:
						used += 1
						_need_key(m.get_string(1), path)
			elif path.ends_with(".gd"):
				n_scripts += 1
				var src := FileAccess.get_file_as_string(path)
				for m in trcall.search_all(src):
					used += 1
					_need_key(m.get_string(1), path)
				for m in keyfield.search_all(src):
					used += 1
					_need_key(m.get_string(1), path)
	_check(n_scenes > 100 and n_scripts > 100 and used > 500,
		"checked %d keys in %d scenes and %d scripts" % [used, n_scenes, n_scripts])


func _static_data() -> void:
	print("keys and texts in data/")
	var counts := {"keys": 0, "texts": 0}
	for dir: String in DATA_DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + f))
				_walk_data(d, dir + f, "", counts)
	_check(counts["keys"] > 200 and counts["texts"] > 300, "checked %d keys and %d en/pt texts in data/" % [counts["keys"], counts["texts"]])


func _walk_data(v: Variant, file: String, field: String, counts: Dictionary) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("en") or d.has("pt"):
			counts["texts"] += 1
			if str(d.get("en", "")).strip_edges() == "" or str(d.get("pt", "")).strip_edges() == "":
				_fail("%s: %s has only one language: %s" % [file.get_file(), field, d])
			return
		for k in d:
			_walk_data(d[k], file, String(k), counts)
	elif v is Array:
		for x in v:
			_walk_data(x, file, field, counts)
	elif v is String and field.ends_with("_key") and _raw.search(String(v)) != null and String(v) == _raw.search(String(v)).get_string():
		counts["keys"] += 1
		_need_key(String(v), file)


## A KEY_LIKE_THIS text with a known prefix must be in a table (colour names such as
## ACCENT_HI in the UI kit are plain text, not keys).
func _need_key(key: String, where: String) -> void:
	if not _looks_like_key(key):
		return
	if not _keys.has(key) and not _flagged.has("key:" + key):
		_flagged["key:" + key] = true
		_fail("%s uses the key %s, which is in no translation table" % [where.trim_prefix("res://"), key])


func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		out.append(dir + f)
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			out.append_array(_files(dir + sub + "/"))
	return out


## Texts that only one language has (the other language never shows them).
func _build_language_sets() -> void:
	var pt_texts := {}
	var en_texts := {}
	for key: String in _keys:
		pt_texts[String(_keys[key]["pt"]).strip_edges()] = true
		en_texts[String(_keys[key]["en"]).strip_edges()] = true
	var word := RegEx.create_from_string("[A-Za-zÀ-ÿ]{4,}")
	for key: String in _keys:
		var en := String(_keys[key]["en"]).strip_edges()
		var pt := String(_keys[key]["pt"]).strip_edges()
		if en == pt or "%" in en or word.search(en) == null:
			continue
		if not pt_texts.has(en) and not en in SHARED_WORDS:
			_en_only[en] = key
		if not en_texts.has(pt) and not pt in SHARED_WORDS:
			_pt_only[pt] = key
	var parts: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/parts.json"))
	for p: Dictionary in (parts as Dictionary).get("parts", []):
		var nm: Dictionary = p.get("name", {})
		var en := String(nm.get("en", "")).strip_edges()
		var pt := String(nm.get("pt", "")).strip_edges()
		if en != "" and en != pt and not pt_texts.has(en):
			_en_only[en] = "part " + String(p.get("id", ""))
		if pt != "" and en != pt and not en_texts.has(pt):
			_pt_only[pt] = "part " + String(p.get("id", ""))


# ------------------------------------------------------------ the screen walk
## Reads every visible text under `node` as shown and checks it for the locale.
func _audit(node: Node, loc: String, where: String) -> int:
	var n := 0
	for c in node.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree():
			continue
		for t in _texts(ctl):
			n += 1
			_check_text(t, loc, where, ctl)
	return n


func _texts(c: Control) -> PackedStringArray:
	var out := PackedStringArray()
	if c is Label:
		out.append(c.atr((c as Label).text))
	elif c is Button:
		out.append(c.atr((c as Button).text))
	elif c is RichTextLabel:
		out.append((c as RichTextLabel).get_parsed_text())
	elif c is LineEdit:
		out.append(c.atr((c as LineEdit).placeholder_text))
	if c.tooltip_text != "":
		out.append(c.atr(c.tooltip_text))
	return out


func _check_text(text: String, loc: String, where: String, c: Control) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	var raw := _raw.search(t)
	if raw != null and _looks_like_key(raw.get_string()):
		_flag("%s (%s): raw key on screen: \"%s\" at %s" % [where, loc, t.left(80), _short_path(c)])
	if loc == "pt" and _en_only.has(t):
		_flag("%s (pt): English text on a Portuguese screen: \"%s\" (%s) at %s" % [where, t.left(80), _en_only[t], _short_path(c)])
	if loc == "pt" and _en_surname.search(t) != null:
		_flag("%s (pt): English Cometling surname on a Portuguese screen: \"%s\" at %s" % [where, t.left(80), _short_path(c)])
	if loc == "en" and _pt_only.has(t):
		_flag("%s (en): Portuguese text on an English screen: \"%s\" (%s) at %s" % [where, t.left(80), _pt_only[t], _short_path(c)])


## Mission codes ("SND-01"), units and acronyms are not keys; KEY_LIKE_THIS with a known
## prefix or a translation entry is.
func _looks_like_key(s: String) -> bool:
	if _keys.has(s):
		return true
	for prefix in ["TY_", "MENU_", "FL_", "UI_", "HANGAR_", "HG_", "SS_", "SURF_", "CREW_", "ROLE_", "CS_", "HELP_",
			"STAT_", "RP_", "ADV_", "WARN_", "PLANET_", "MSG_", "CRASH_", "QUALITY_", "STAB_"]:
		if s.begins_with(prefix):
			return true
	return false


func _flag(msg: String) -> void:
	if _flagged.has(msg):
		return
	_flagged[msg] = true
	_fail(msg)


func _short_path(c: Node) -> String:
	var p := String(c.get_path())
	return p.substr(maxi(p.length() - 70, 0))


func _walk_menu(loc: String) -> void:
	print("main menu (%s)" % loc)
	var menu := (load(MENU) as PackedScene).instantiate()
	root.add_child(menu)
	await _frames(4)
	var n := _audit(menu, loc, "main menu")
	if menu.has_method("open_demos"):
		menu.open_demos()
		await _frames(3)
		var demo := menu.get_node("%DemoPanel") as Control
		n += _audit(demo, loc, "demonstration panel")
		_check(demo.call("rows").size() == TycoonSave.DEMOS.size(), "the demonstration panel lists the %d demonstration saves" % TycoonSave.DEMOS.size())
		menu.close_demos()
	menu.open_options()
	await _frames(3)
	n += _audit(menu.get_node("%OptionsPanel"), loc, "options")
	_check(n > 20, "main menu: %d texts read" % n)
	menu.queue_free()
	await _frames(2)


func _walk_leader(loc: String) -> void:
	print("leader creator (%s)" % loc)
	var lc := (load(LEADER) as PackedScene).instantiate()
	root.add_child(lc)
	await _frames(4)
	var n := _audit(lc, loc, "leader creator")
	_check(n > 10, "leader creator: %d texts read" % n)
	lc.queue_free()
	await _frames(2)


func _walk_campus(loc: String) -> void:
	print("campus screens (%s)" % loc)
	if not TycoonSave.exists(DEMO_SLOT):
		_fail("no demonstration save %s (run tools/make_demo_saves.gd)" % DEMO_SLOT)
		return
	var main := (load(TYCOON) as PackedScene).instantiate() as TycoonMain
	main.load_slot = DEMO_SLOT
	main.cutscenes = false
	root.add_child(main)
	await _frames(6)
	main.clock.set_speed(0)
	var dev := root.get_node_or_null("CwDev") as CwDevMenu
	var n := _audit(main.hud, loc, "campus HUD")
	main.hud.show_lot("lab")
	await _frames(3)
	n += _audit(main.hud, loc, "lot panel")
	main.hud.close_lot()
	var screens := 0
	for f in DirAccess.get_files_at(SCREENS_DIR):
		if not f.ends_with(".tscn") or f == "leader_creator.tscn":
			continue
		var screen := f.get_basename()
		var args: Dictionary = dev.screen_args(screen) if dev else {}
		if not main.hud.open_screen(screen, args):
			continue
		screens += 1
		await _frames(4)
		n += _audit(main.hud, loc, "screen " + screen)
		for i in 4:
			if main.hud.current_screen() == "":
				break
			main.hud.close_screen()
			await _frames(2)
	_check(screens >= 15, "campus: %d screens opened, %d texts read" % [screens, n])
	main.queue_free()
	await _frames(3)


func _walk_hangar(loc: String) -> void:
	print("hangar (%s)" % loc)
	var h := (load(HANGAR) as PackedScene).instantiate()
	root.add_child(h)
	await _frames(8)
	var n := _audit(h, loc, "hangar")
	_check(n > 10, "hangar: %d texts read" % n)
	h.queue_free()
	await _frames(3)


# ------------------------------------------------------------ helpers
func _seeded() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 99
	return r


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _fail(msg: String) -> void:
	_failures += 1
	print("  FAIL %s" % msg)


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_fail(msg)
