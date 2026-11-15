extends SceneTree
## Story signs on the campus island (StorySigns, data/tycoon/story_signs.json, CampusSigns in
## scenes/tycoon/campus_signs.tscn, the "sign" card):
##   data      ids unique, kinds known, icons exist, unlock conditions use known keys,
##             milestones and lots; every title / text / fact / source has English and
##             Portuguese text (and real facts carry a source)
##   scene     every placed sign has data, every sign in the data is placed once
##   placement no sign stands on a lot, a road or the plaza, nor too close to another sign; every
##             sign stands on the island's ground (its foot on the terrain under it)
##   unlocks   era, year, milestone and launch conditions open the signs only when they hold;
##             covered signs show the tarp, uncovered unread ones the star
##   reading   a covered sign cannot be read, an uncovered one once; read signs survive
##             to_dict / from_dict and a save from before the signs loads with none read
##   in game   on the main screen a click on a sign opens its card and marks it read, Esc
##             closes the card; a click on a lot still opens the lot; the journal shows the
##             count; hovering a sign shows its tag (a sticker on the screen) with the title
##   card      every sign's card, in pt and en, at 1280x720 and 1600x900: the board keeps its
##             size inside the screen, the title takes two lines at most and the text and the
##             fact fit the board without scrolling; every hover tag stays small
## Run: godot --headless --path . --script res://tests/test_story_signs.gd

const SIGNS_SCENE := "res://scenes/tycoon/campus_signs.tscn"
const CAMPUS := "res://scenes/tycoon/campus.tscn"
const ISLAND := "res://scenes/tycoon/campus_island.tscn"
## how far (m) a sign keeps from a lot or a road, and from another sign
const LOT_CLEARANCE := 1.2
const SIGN_SPACING := 3.0

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_data()
	_scene_and_placement()
	await _unlocks_and_reading()
	await _in_game()
	await _card_layout()
	print("STORY SIGNS: %d checks, %s" % [_checks, "PASS" if _fails == 0 else "FAIL (%d)" % _fails])
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL ", what)
	else:
		print("  ok   ", what)


func _text(key: String, loc: String) -> String:
	TranslationServer.set_locale(loc)
	var t := TranslationServer.translate(key)
	return String(t)


# ------------------------------------------------------------ data
func _data() -> void:
	print("data")
	var all := StorySigns.all()
	_check(all.size() >= 24, "the island has %d story signs (StorySigns loaded %s)" % [all.size(), StorySigns.DATA])
	var seen := {}
	var bad := []
	var kinds := {}
	var milestones := {}
	for m: Dictionary in TycoonState.load_json("res://data/tycoon/milestones.json").get("milestones", []):
		milestones[String(m["id"])] = true
	var lots: Dictionary = TycoonState.load_json("res://data/tycoon/buildings.json").get("lots", {})
	for s: Dictionary in all:
		var id := String(s.get("id", ""))
		if id == "" or seen.has(id):
			bad.append("duplicate or empty id '%s'" % id)
		seen[id] = true
		var kind := String(s.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if not kind in StorySigns.KINDS:
			bad.append("%s: unknown kind %s" % [id, kind])
		if not ResourceLoader.exists("res://ui/cometworks/icons/%s.svg" % String(s.get("icon", ""))):
			bad.append("%s: no icon %s" % [id, s.get("icon", "")])
		var u: Dictionary = s.get("unlock", {})
		for k: String in u:
			if not k in StorySigns.UNLOCK_KEYS:
				bad.append("%s: unknown unlock key %s" % [id, k])
		if u.has("milestone") and not milestones.has(String(u["milestone"])):
			bad.append("%s: unknown milestone %s" % [id, u["milestone"]])
		if u.has("building") and not lots.has(String(u["building"])):
			bad.append("%s: unknown lot %s" % [id, u["building"]])
		if kind == "history" and String(s.get("fact_key", "")) == "":
			bad.append("%s: space history without a real fact" % id)
		if String(s.get("fact_key", "")) != "" and String(s.get("source_key", "")) == "":
			bad.append("%s: a fact without a source" % id)
		for f in ["title_key", "text_key", "fact_key", "source_key"]:
			var key := String(s.get(f, ""))
			if key == "":
				if f in ["title_key", "text_key"]:
					bad.append("%s: no %s" % [id, f])
				continue
			var en := _text(key, "en")
			var pt := _text(key, "pt_BR")
			if en == key or pt == key or en.strip_edges() == "" or pt.strip_edges() == "":
				bad.append("%s: %s missing in a language" % [id, key])
			elif f != "source_key" and en == pt:
				bad.append("%s: %s is the same in both languages" % [id, key])
	_check(bad.is_empty(), "sign data is valid, with English and Portuguese texts%s" % ("" if bad.is_empty() else ": " + ", ".join(bad)))
	_check(kinds.get("lore", 0) >= 5 and kinds.get("history", 0) >= 8 and kinds.get("joke", 0) >= 5,
		"lore, history and jokes all there (%s)" % kinds)
	for k in ["SIGN_KIND_LORE", "SIGN_FACT_CAPTION", "SIGN_READ_COUNT", "SIGN_COVERED", "SIGN_LOCK_ERA", "SIGN_JN_CAPTION"]:
		_check(_text(k, "en") != k and _text(k, "pt_BR") != k and _text(k, "en") != _text(k, "pt_BR"), "%s in both languages" % k)
	TranslationServer.set_locale("pt_BR")


# ------------------------------------------------------------ scene and placement
func _scene_and_placement() -> void:
	print("scene and placement")
	var campus := (load(CAMPUS) as PackedScene).instantiate() as Node3D
	get_root().add_child(campus)
	var signs := campus.get_node_or_null("Signs") as CampusSigns
	_check(signs != null and signs.get_script() == load("res://src/tycoon/campus_signs.gd"), "the campus has its Signs (CampusSigns)")
	if signs == null:
		campus.free()
		return
	var placed := {}
	var orphan := []
	for s in signs.signs():
		if StorySigns.find(s.sign_id).is_empty():
			orphan.append(String(s.name))
		placed[s.sign_id] = int(placed.get(s.sign_id, 0)) + 1
	var missing := []
	var twice := []
	for id in StorySigns.ids():
		if not placed.has(id):
			missing.append(id)
		elif int(placed[id]) > 1:
			twice.append(id)
	_check(orphan.is_empty(), "every sign node has data %s" % (orphan if not orphan.is_empty() else ""))
	_check(missing.is_empty() and twice.is_empty(), "every sign is placed once (missing %s, twice %s)" % [missing, twice])

	# lots, roads and the plaza: rectangles on the ground (campus x, z)
	var rects: Array = []
	for lot in campus.get_node("Lots").get_children():
		var sz: Vector2 = lot.get_meta("size", Vector2.ZERO)
		var c := (lot as Node3D).position
		rects.append([String(lot.name), Rect2(Vector2(c.x, c.z) - sz * 0.5, sz)])
	for r in campus.get_node("Roads").get_children():
		if r is MeshInstance3D:
			var a := (r as MeshInstance3D).get_aabb()
			var xf := (r as Node3D).transform
			var lo := xf * a.position
			var hi := xf * a.end
			rects.append([String(r.name), Rect2(Vector2(minf(lo.x, hi.x), minf(lo.z, hi.z)), Vector2(absf(hi.x - lo.x), absf(hi.z - lo.z)))])
	var hits := []
	var close := []
	var list := signs.signs()
	for i in list.size():
		var s := list[i]
		var p := Vector2(s.position.x, s.position.z)
		for r: Array in rects:
			if (r[1] as Rect2).grow(LOT_CLEARANCE).has_point(p):
				hits.append("%s on %s" % [s.sign_id, r[0]])
		for j in range(i + 1, list.size()):
			var q := Vector2(list[j].position.x, list[j].position.z)
			if p.distance_to(q) < SIGN_SPACING:
				close.append("%s / %s" % [s.sign_id, list[j].sign_id])
	_check(hits.is_empty(), "no sign on a lot, a road or the plaza %s" % (hits if not hits.is_empty() else ""))
	_check(close.is_empty(), "signs keep %.0f m apart %s" % [SIGN_SPACING, close if not close.is_empty() else ""])

	# every sign stands on the ground: the terrain right under it is at its foot
	var island := campus.get_node("Terrain")
	var tris := []
	for n in ["Plateau", "Terraces", "Sand", "Rock", "Steps"]:
		var mi := island.get_node_or_null(n) as MeshInstance3D
		if mi:
			tris.append(mi.mesh.generate_triangle_mesh())
	var floating := []
	var outline: PackedVector2Array = island.get_node("Plateau").get_meta("walk_outline", PackedVector2Array())
	var on_top := 0
	for s in list:
		var top := -INF
		for t: TriangleMesh in tris:
			var hit := t.intersect_ray(Vector3(s.position.x, 200, s.position.z), Vector3.DOWN)
			if not hit.is_empty():
				top = maxf(top, (hit["position"] as Vector3).y)
		if absf(top - s.position.y) > 0.3:
			floating.append("%s (foot %.2f, ground %.2f)" % [s.sign_id, s.position.y, top])
		if Geometry2D.is_point_in_polygon(Vector2(s.position.x, s.position.z), outline):
			on_top += 1
	_check(floating.is_empty(), "every sign stands on the island's ground %s" % (floating if not floating.is_empty() else ""))
	_check(on_top >= list.size() - 4, "most signs stand on the walkable top (%d of %d)" % [on_top, list.size()])
	campus.free()


# ------------------------------------------------------------ unlocks and reading
func _unlocks_and_reading() -> void:
	print("unlocks and reading")
	var s := TycoonState.new_campaign(7, [], "normal")
	_check(StorySigns.is_unlocked(s, "welcome") and StorySigns.is_unlocked(s, "mae_gelo"), "the lore of year 1 is open from the start")
	_check(not StorySigns.is_unlocked(s, "moon_first"), "an era-2 sign is covered in era 1")
	_check(StorySigns.lock_text(s, "moon_first") != "" and StorySigns.lock_text(s, "welcome") == "",
		"a covered sign says what uncovers it ('%s')" % StorySigns.lock_text(s, "moon_first"))
	_check(not StorySigns.is_unlocked(s, "lost_found"), "a year-2 sign is covered in year 1")
	s.weeks = 5 * s.weeks_per_year() + 2
	_check(StorySigns.is_unlocked(s, "moon_first") and StorySigns.is_unlocked(s, "lost_found") and not StorySigns.is_unlocked(s, "giotto"),
		"in era 2 the era-2 and year-2 signs open, not the era-3 ones")
	_check(not StorySigns.is_unlocked(s, "sputnik"), "a milestone sign is covered before the milestone")
	s.race.claim("first_satellite", "rival_a" if s.rivals.is_empty() else String(s.rivals[0]["id"]))
	_check(not StorySigns.is_unlocked(s, "sputnik"), "...and stays covered when only a rival took it")
	s.race.claim("first_satellite", RaceDirector.PLAYER)
	_check(StorySigns.is_unlocked(s, "sputnik"), "...and opens when the player takes it")
	_check(not StorySigns.is_unlocked(s, "scd1"), "a launch sign is covered before any launch")
	s.project_history.append({"id": "test"})
	_check(StorySigns.is_unlocked(s, "scd1") and not StorySigns.is_unlocked(s, "weather"), "one launch opens the 1-launch sign, not the 3-launch one")

	_check(not StorySigns.mark_read(s, "giotto"), "a covered sign cannot be read")
	_check(StorySigns.mark_read(s, "welcome"), "an uncovered sign is read")
	_check(not StorySigns.mark_read(s, "welcome"), "...only once")
	_check(not StorySigns.mark_read(s, "no_such_sign"), "an unknown sign is never read")
	StorySigns.mark_read(s, "sputnik")
	_check(StorySigns.read_count(s) == 2 and not StorySigns.unread(s).has("welcome"), "two signs read (%d)" % StorySigns.read_count(s))
	var d := TycoonSave.decode(JSON.parse_string(JSON.stringify(TycoonSave.encode(s.to_dict())))) as Dictionary
	var back := TycoonState.from_dict(d)
	_check(StorySigns.is_read(back, "welcome") and StorySigns.is_read(back, "sputnik") and StorySigns.read_count(back) == 2,
		"read signs survive a save and load")
	d.erase("signs")
	var old := TycoonState.from_dict(d)
	_check(old.signs.is_empty() and StorySigns.read_count(old) == 0 and StorySigns.mark_read(old, "welcome"),
		"a save from before the signs loads with none read, and reading still works")

	# the sign model follows its state
	var sign := (load("res://scenes/tycoon/campus_sign.tscn") as PackedScene).instantiate() as CampusSign
	get_root().add_child(sign)
	await _frames(1)
	_check(sign.is_node_ready(), "the sign model is ready")
	sign.set_kind("history")
	sign.set_state(false, false)
	_check(sign.cover.visible and not sign.faces.visible and not sign.new_mark.visible, "a covered sign shows the tarp")
	sign.set_state(true, false)
	_check(not sign.cover.visible and sign.faces.visible and sign.new_mark.visible and sign.faces.get_node("History").visible
		and not sign.faces.get_node("Lore").visible, "an uncovered unread sign shows its painted face and the star")
	sign.set_state(true, true)
	_check(not sign.new_mark.visible, "a read sign loses the star")
	sign.free()


# ------------------------------------------------------------ in game
func _in_game() -> void:
	print("in game")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(4)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	if main.tutorial:
		main.tutorial.set_process(false)
	var cam := main.camera
	cam.tour_enabled = false
	cam.set_process(false)
	cam.set_physics_process(false)
	var signs := main.campus.signs
	_check(signs != null and signs.state == main.state, "the campus binds its signs to the campaign")
	# look straight at the welcome sign by the plaza
	var sign := signs.sign_node("welcome")
	var target := sign.pick_point()
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(-0.4, -0.6, -1.0).normalized(), Vector3.UP), target + Vector3(8, 12, 20))
	cam.fov = 40.0
	await _frames(2)
	var screen := cam.unproject_position(target)
	_check(signs.sign_at(cam, screen) == "welcome", "the welcome sign is under its board on screen")
	var mm := InputEventMouseMotion.new()
	mm.position = screen
	signs._unhandled_input(mm)
	await _frames(1)
	var tag := signs.tag
	var tag_title := tag.get_node("%Title") as Label if tag else null
	_check(signs.hovered == "welcome" and tag != null and tag.visible and tag_title.text == tr("SIGN_WELCOME_TITLE"),
		"hovering the sign shows its tag ('%s')" % (tag_title.text if tag_title else "none"))
	if tag:
		var vr := Rect2(Vector2.ZERO, tag.get_viewport_rect().size)
		_check(vr.encloses(tag.get_global_rect()), "...inside the screen (%s in %s)" % [tag.get_global_rect(), vr.size])
	signs._hover("giotto")
	_check(tag != null and tag.visible and (tag.get_node("%DiscCovered") as Control).visible
		and tag_title.text == StorySigns.lock_text(main.state, "giotto"), "a covered sign's tag says what uncovers it")
	signs._hover("")
	_check(tag != null and not tag.visible, "the tag hides when the mouse leaves")
	signs._hover("welcome")
	main.click(screen)
	await _frames(3)
	_check(main.hud.current_screen() == "sign", "a click on the sign opens its card (got '%s')" % main.hud.current_screen())
	_check(StorySigns.is_read(main.state, "welcome") and not sign.new_mark.visible, "...marks it read and takes its star off")
	var card := main.hud.get_node("%Screens").get_child(0) if main.hud.get_node("%Screens").get_child_count() > 0 else null
	if card:
		_check(String(card.get_node("%Title").text) == tr("SIGN_WELCOME_TITLE") and String(card.get_node("%Count").text).begins_with("1 "),
			"the card shows the sign's title and the count ('%s')" % card.get_node("%Count").text)
	_press(KEY_ESCAPE)
	await _frames(3)
	_check(main.hud.current_screen() == "", "Esc closes the card")
	# a covered sign only says what uncovers it
	var covered := signs.sign_node("giotto")
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(-0.4, -0.6, -1.0).normalized(), Vector3.UP), covered.pick_point() + Vector3(8, 12, 20))
	await _frames(2)
	main.click(cam.unproject_position(covered.pick_point()))
	await _frames(2)
	_check(main.hud.current_screen() == "" and not StorySigns.is_read(main.state, "giotto"), "a covered sign opens no card")
	# a lot still wins over a sign: the hq lot under the mouse
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, -0.3).normalized(), Vector3.UP), Vector3(-16, 40, 0))
	await _frames(2)
	var hq_screen := cam.unproject_position(main.campus.lot_position("hq"))
	_check(signs.sign_at(cam, hq_screen) == "", "no sign is picked over a lot")
	main.click(hq_screen)
	await _frames(2)
	_check(main.hud.lot_id == "hq" and main.hud.current_screen() == "", "a click on the hq lot still opens the lot panel")
	main.hud.close_lot()
	# the journal shows the count
	main.hud.open_screen("journal")
	await _frames(3)
	var jn := main.hud.get_node("%Screens").get_child(0)
	var count := jn.get_node_or_null("%SignCount") as Label
	_check(count != null and count.text == "1/%d" % StorySigns.unlocked_count(main.state), "the journal counts the signs read (%s)" % (count.text if count else "none"))
	main.hud.close_screen()
	main.queue_free()
	await _frames(3)


# ------------------------------------------------------------ the card and the tag of every sign
func _card_layout() -> void:
	print("card layout")
	var state := TycoonState.new_campaign(5)
	var clock := TycoonClock.new(state.rules)
	var card_scene := load("res://scenes/tycoon/ui/screens/sign.tscn") as PackedScene
	var tag_scene := load("res://scenes/tycoon/ui/sign_tag.tscn") as PackedScene
	var worst := 0.0
	var worst_id := ""
	for size: Vector2 in [Vector2(1280, 720), Vector2(1600, 900)]:
		var host := Control.new()
		host.size = size
		get_root().add_child(host)
		for loc in ["pt_BR", "en"]:
			TranslationServer.set_locale(loc)
			var bad: Array[String] = []
			for id in StorySigns.ids():
				var card := card_scene.instantiate() as Control
				host.add_child(card)
				card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				card.call("bind", state, clock, null)
				card.call("open_with", {"id": id})
				await _frames(2)
				var panel := card.get_node("Panel") as Control
				var title := card.get_node("%Title") as Label
				var scroll := card.get_node("%Scroll") as ScrollContainer
				var body := card.get_node("%ScrollBody") as Control
				var view := Rect2(Vector2.ZERO, size)
				var need := body.get_combined_minimum_size().y
				if need / maxf(scroll.size.y, 1.0) > worst:
					worst = need / maxf(scroll.size.y, 1.0)
					worst_id = "%s %s" % [id, loc]
				var why := ""
				var ropes := card.get_node("Ropes") as Control
				if not view.encloses(panel.get_global_rect()) or not view.encloses(ropes.get_global_rect()):
					why = "board off screen %s" % panel.get_global_rect()
				elif panel.size.y > 541.0 or panel.size.x > 781.0:
					why = "board grew to %s" % panel.size
				elif title.get_line_count() > 2:
					why = "title in %d lines" % title.get_line_count()
				elif need > scroll.size.y + 0.5:
					why = "text %.0f px for %.0f px" % [need, scroll.size.y]
				elif title.text == "" or (card.get_node("%Body") as Label).text.begins_with("SIGN_") \
						or (card.get_node("%Number") as Label).text.begins_with("SIGN_"):
					why = "untranslated"
				if why != "":
					bad.append("%s (%s)" % [id, why])
				card.queue_free()
				await _frames(1)
			_check(bad.is_empty(), "every sign card fits at %dx%d in %s%s" % [size.x, size.y, loc, "" if bad.is_empty() else ": " + ", ".join(bad)])
			# the hover tags
			var tag := tag_scene.instantiate() as Control
			host.add_child(tag)
			var wide: Array[String] = []
			for id in StorySigns.ids():
				(tag.get_node("%Title") as Label).text = tr(String(StorySigns.find(id).get("title_key", "")))
				(tag.get_node("%Hint") as Label).text = tr("SIGN_HOVER_NEW")
				tag.reset_size()
				await _frames(1)
				if tag.get_combined_minimum_size().x > 560.0:
					wide.append("%s %.0f px" % [id, tag.get_combined_minimum_size().x])
			_check(wide.is_empty(), "every hover tag stays small at %dx%d in %s %s" % [size.x, size.y, loc, wide])
			tag.queue_free()
		host.queue_free()
		await _frames(1)
	TranslationServer.set_locale("pt_BR")
	print("  the fullest card (%s) uses %.0f%% of its text area" % [worst_id, worst * 100.0])


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(k: int) -> void:
	for i in k:
		await process_frame
