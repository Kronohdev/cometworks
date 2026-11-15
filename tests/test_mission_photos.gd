extends SceneTree
## Headless checks for the photos missions send home (MissionPhotos, MissionPhotoStudio,
## data/tycoon/mission_photos.json, the album screen):
##   - the data: every shot named by a target / type exists, its set and pose exist in the
##     studio scene and its subject has a text in both languages
##   - a launch with a camera that succeeds records count[outcome] photos (none on a failure,
##     none without a camera, false colours with only the infrared camera, no duplicates,
##     new views of a target already pictured), a real project launch too
##   - photos_for() gives the documented keys; the mural picks the pinned first, one per mission
##   - saves keep the photos; old saves without them load with an empty album
##   - headless the studio renders nothing (can_render false) and the album opens on records
##     without pictures ("Developing…"); a PNG on disk turns into a texture
## Run: godot --headless --path . --script res://tests/test_mission_photos.gd

const STUDIO := "res://scenes/tycoon/photos/photo_studio.tscn"

var _failures := 0


func _initialize() -> void:
	_test_data()
	_test_records()
	_test_project_launch()
	_test_save()
	_test_mural()
	await _test_headless_studio()
	_test_texture()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


static func _team() -> Array[Dictionary]:
	return [
		{"id": "a", "name": "Ada", "profession": "systems_engineer", "skill": 0.6, "morale": 80.0, "level": 1},
		{"id": "b", "name": "Bel", "profession": "scientist", "skill": 0.5, "morale": 70.0, "level": 2},
		{"id": "c", "name": "Cid", "profession": "test_technician", "skill": 0.5, "morale": 70.0, "level": 1},
		{"id": "d", "name": "Duo", "profession": "flight_controller", "skill": 0.4, "morale": 60.0, "level": 1}]


static func _launch(pid: String, target: String, outcome: String, payload: Array, type := "orbiter") -> Dictionary:
	return {"project_id": pid, "code": "T-" + pid, "type": type, "target": target,
		"success": outcome != "fail", "outcome": outcome, "payload": payload}


# ------------------------------------------------------------ data
func _test_data() -> void:
	print("data")
	var d := MissionPhotos.data()
	_check(not d.is_empty() and (d.get("shots", {}) as Dictionary).size() >= 10, "mission_photos.json loads with its shots")
	var named := {}
	for t: String in d.get("by_target", {}):
		for s in d["by_target"][t]:
			named[String(s)] = true
	for t: String in d.get("by_type", {}):
		for s in d["by_type"][t].get("shots", []):
			named[String(s)] = true
	var missing: Array = []
	for s: String in named:
		if MissionPhotos.shot(s).is_empty():
			missing.append(s)
	_check(missing.is_empty(), "every shot named by a target or a type is defined %s" % str(missing))
	# every mission target has shots
	var no_shots: Array = []
	var s0 := TycoonState.new_campaign(1)
	for t: Dictionary in s0.mdata.get("targets", []):
		if MissionPhotos.shots_for("orbiter", String(t["id"])).is_empty():
			no_shots.append(t["id"])
	_check(no_shots.is_empty(), "every mission target has photos to take %s" % str(no_shots))
	_check(MissionPhotos.shots_for("rover", "lunar_surface")[0] == "rover_view", "a lunar rover sends its own view first")
	_check(MissionPhotos.shots_for("rover", "leo") == MissionPhotos.shots_for("orbiter", "leo"), "the rover shots only on its targets")
	_check(MissionPhotos.shots_for("telescope", "leo")[0].begins_with("planet_"), "a telescope pictures the planets")
	# the studio has every set and pose; every subject has its texts
	var studio := (load(STUDIO) as PackedScene).instantiate()
	var sets := studio.get_node("Frame/Root/View/World/Stage/Sets")
	var bad: Array = []
	var untranslated: Array = []
	for id: String in d["shots"]:
		var sh: Dictionary = d["shots"][id]
		var set_node := sets.get_node_or_null(String(sh["set"]))
		if set_node == null or set_node.get_node_or_null("Poses/%s/Look" % String(sh["pose"])) == null:
			bad.append(id)
		for loc in ["en", "pt"]:
			TranslationServer.set_locale(loc)
			if tr(String(sh["subject_key"])) == String(sh["subject_key"]):
				untranslated.append("%s/%s" % [id, loc])
	studio.free()
	_check(bad.is_empty(), "every shot's set and pose (with its Look) are in the studio %s" % str(bad))
	_check(untranslated.is_empty(), "every subject has an English and a Portuguese text %s" % str(untranslated))
	TranslationServer.set_locale("pt")
	_check(MissionPhotos.cameras_in(["battery", "camera", "omni"]) == ["camera"], "the camera is a camera")
	_check(MissionPhotos.cameras_in(["sensor_pack", "omni"]).is_empty(), "a sensor pack is not")


# ------------------------------------------------------------ records
func _test_records() -> void:
	print("records")
	var s := TycoonState.new_campaign(7)
	var counts := {}
	for out in ["partial", "full", "exceptional", "fail"]:
		counts[out] = MissionPhotos.on_launch(s, _launch("p_" + out, "leo", out, ["camera", "battery"])).size()
	_check(counts["partial"] == 1 and counts["full"] == 2 and counts["exceptional"] == 3 and counts["fail"] == 0,
		"partial 1, full 2, exceptional 3, failure 0 photos (%s)" % str(counts))
	_check(MissionPhotos.on_launch(s, _launch("p_nocam", "leo", "full", ["sensor_pack", "battery"])).is_empty(),
		"no camera, no photos")
	_check(MissionPhotos.on_launch(s, _launch("p_full", "leo", "full", ["camera"])).is_empty(), "a project's photos are recorded once")
	var ir := MissionPhotos.on_launch(s, _launch("p_ir", "comet", "full", ["ir_camera"]))
	_check(ir.size() == 2 and String(ir[0]["filter"]) == "ir", "only the infrared camera: false colours")
	var plain := MissionPhotos.on_launch(s, _launch("p_both", "lunar_orbit", "partial", ["camera", "ir_camera"]))
	_check(plain.size() == 1 and String(plain[0]["filter"]) == "", "with the plain camera aboard: plain colours")
	var a := MissionPhotos.on_launch(s, _launch("p_m1", "lunar_flyby", "partial", ["camera"]))
	var b := MissionPhotos.on_launch(s, _launch("p_m2", "lunar_flyby", "partial", ["camera"]))
	_check(a[0]["shot"] != b[0]["shot"], "a second mission to a target brings a new view (%s, %s)" % [a[0]["shot"], b[0]["shot"]])
	var ph: Dictionary = s.photos[0]
	var keys_ok := true
	for k in ["id", "project_id", "code", "type", "target", "shot", "filter", "outcome", "week", "seed", "file", "pinned"]:
		keys_ok = keys_ok and ph.has(k)
	_check(keys_ok, "a record has every field")
	_check(String(ph["file"]).begins_with("user://") and String(ph["file"]).ends_with(".png")
		and String(ph["file"]).contains(String(ph["project_id"])), "its PNG lives in user://, keyed by project id (%s)" % ph["file"])
	var files := {}
	for p in s.photos:
		files[p["file"]] = true
	_check(files.size() == s.photos.size(), "every photo has its own file")
	_check(String(s.news[0]["key"]) == "TY_PH_NEWS", "the Tail Radio tells the photos arrived")
	var list := MissionPhotos.photos_for(s, "p_exceptional")
	_check(list.size() == 3, "photos_for gives a project's photos")
	var d: Dictionary = list[0]
	_check(d.has("path") and d.has("has_image") and d.has("subject_key") and d.has("date") and not bool(d["has_image"]),
		"photos_for fills path, has_image (false: nothing rendered headless), subject_key and date")
	_check(String(d["date"]).length() > 0 and String(d["subject_key"]).begins_with("TY_PH_SUBJ_"), "the date and subject read well (%s)" % d["date"])
	_check(MissionPhotos.photos_for(s, "nope").is_empty(), "an unknown project has none")
	_check(MissionPhotos.album(s)[0]["id"] == s.photos[s.photos.size() - 1]["id"], "the album lists the newest first")
	_check(MissionPhotos.missing(s).size() == s.photos.size(), "every photo waits for the studio")


func _test_project_launch() -> void:
	print("a real launch")
	var s := TycoonState.new_campaign(11, _team())
	TycoonResearch.complete(s, TycoonResearch.tech_for_type("demo_sat"))
	TycoonResearch.complete(s, TycoonResearch.tech_for_target("leo"))
	s.cash = 5.0e6
	var p := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b", "c", "d"])
	_check(p != null, "a demo satellite to low orbit starts")
	if p == null:
		return
	_check("camera" in p.payload_or_default(s), "its starter kit carries the camera")
	var id := p.id
	ProjectDesk.dev_force_outcome = "success"
	var guard := 0
	while ProjectDesk.find(s, id) != null and guard < 40:
		var q := ProjectDesk.find(s, id)
		if q and q.awaiting_sliders:
			ProjectDesk.set_sliders(s, id, [40, 30, 30])
		s.advance_week()
		guard += 1
	ProjectDesk.dev_force_outcome = ""
	var h := ProjectDesk.history_entry(s, id)
	_check(bool(h.get("success", false)), "it launched with success (%s)" % h.get("outcome", "?"))
	var list := MissionPhotos.photos_for(s, id)
	_check(list.size() == MissionPhotos.count_for(String(h.get("outcome", ""))) and list.size() > 0,
		"and sent %d photo(s) home, as its outcome says" % list.size())
	_check(not list.is_empty() and String(list[0]["target"]) == "leo" and String(list[0]["shot"]).begins_with("earth"),
		"pictures of the Earth from orbit")


# ------------------------------------------------------------ saves
func _test_save() -> void:
	print("saves")
	var s := TycoonState.new_campaign(21)
	MissionPhotos.on_launch(s, _launch("p1", "comet", "exceptional", ["camera"]))
	MissionPhotos.set_pinned(s, "p1_2", true)
	var d := JSON.parse_string(JSON.stringify(s.to_dict())) as Dictionary   # numbers come back as floats
	var l := TycoonState.from_dict(d)
	_check(l.photos.size() == 3, "the photos survive a save")
	_check(JSON.stringify(l.photos) == JSON.stringify(s.photos), "with every field the same")
	_check(l.photos[0]["week"] is int and l.photos[0]["seed"] is int, "numbers come back as integers")
	_check(bool(MissionPhotos.find(l, "p1_2")["pinned"]), "the pin on the mural too")
	d.erase("photos")
	var old := TycoonState.from_dict(d)
	_check(old.photos.is_empty(), "an old save without photos loads with an empty album")
	# a loaded campaign keeps recording photos
	MissionPhotos.on_launch(old, _launch("p9", "leo", "partial", ["camera"]))
	_check(old.photos.size() == 1, "and its next missions send photos")
	old.mission_launched.emit(_launch("p10", "leo", "full", ["camera"]))
	_check(old.photos.size() == 3, "through the state's mission_launched (attached on load)")
	_check(TycoonSave.save(s, "test_photos") == OK and TycoonSave.load_state("test_photos").photos.size() == 3,
		"TycoonSave writes and reads them")
	DirAccess.remove_absolute(TycoonSave.path("test_photos"))


func _test_mural() -> void:
	print("mural")
	var s := TycoonState.new_campaign(31)
	_check(MissionPhotos.mural(s).is_empty(), "no photos, no mural")
	MissionPhotos.on_launch(s, _launch("a", "leo", "partial", ["camera"]))
	MissionPhotos.on_launch(s, _launch("b", "comet", "exceptional", ["camera"]))
	MissionPhotos.on_launch(s, _launch("c", "lunar_orbit", "full", ["camera"]))
	MissionPhotos.on_launch(s, _launch("d", "geo", "full", ["camera"]))
	var m := MissionPhotos.mural(s)
	var max_n := int(MissionPhotos.data().get("mural_max", 3))
	_check(m.size() == max_n, "the mural holds %d photos" % max_n)
	_check(m[0]["project_id"] == "b", "the exceptional one first")
	var pids := {}
	for ph in m:
		pids[ph["project_id"]] = true
	_check(pids.size() == m.size(), "one photo per mission")
	_check(m[1]["project_id"] == "d", "then the newest of the best (%s)" % m[1]["project_id"])
	MissionPhotos.set_pinned(s, "a_1", true)
	_check(MissionPhotos.mural(s)[0]["id"] == "a_1", "a pinned photo goes up first")


# ------------------------------------------------------------ headless studio and album
func _test_headless_studio() -> void:
	print("headless")
	_check(not MissionPhotoStudio.can_render(), "headless: the studio does not render")
	var s := TycoonState.new_campaign(41)
	MissionPhotos.on_launch(s, _launch("h1", "comet", "full", ["camera"]))
	var studio := (load(STUDIO) as PackedScene).instantiate() as MissionPhotoStudio
	get_root().add_child(studio)
	studio.bind(s)
	var ok: bool = await studio.render(s.photos[0], s)
	_check(not ok and not MissionPhotos.has_image(s.photos[0]), "a render request skips quietly, the record stays")
	studio.queue_free()
	# the album opens through the HUD on records without pictures
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await process_frame
	await process_frame
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	_check(main.photo_studio != null and main.photo_mural != null, "the campus has the studio and the mural")
	var album_key := main.hud.get_node("%Album") as Control
	_check(not album_key.visible and not main.photo_mural.visible, "no photos: no album key, no mural")
	MissionPhotos.on_launch(main.state, _launch("h2", "lunar_surface", "exceptional", ["camera"], "rover"))
	main.state.changed.emit()
	await process_frame
	_check(album_key.visible and main.photo_mural.visible, "a photo home: the album key and the mural show up")
	_check(main.hud.open_screen("album", {"project_id": "h2"}), "the album screen opens")
	await process_frame
	var scr := main.hud.get_node("%Screens").get_child(0)
	_check(scr.get("selected") == "h2_1", "on the mission's first photo")
	var grid := scr.get_node("%Grid")
	var thumbs := 0
	for c in grid.get_children():
		if c.has_meta("from_template"):
			thumbs += 1
	_check(thumbs == 3, "with its thumbnails (%d)" % thumbs)
	_check((scr.get_node("%Developing") as Control).visible, "a picture still developing says so")
	scr.call("select", "h2_2")
	(scr.get_node("%Pin") as BaseButton).button_pressed = true
	_check(bool(MissionPhotos.find(main.state, "h2_2")["pinned"]), "Pin on the mural pins it")
	_check(MissionPhotos.mural(main.state)[0]["id"] == "h2_2", "and the mural puts it up")
	main.hud.close_screen()
	main.queue_free()
	await process_frame


func _test_texture() -> void:
	print("texture")
	var ph := {"id": "t1", "file": "user://mission_photos/test/t1.png"}
	DirAccess.remove_absolute(ph["file"])
	_check(MissionPhotos.texture(ph) == null, "no picture yet: no texture")
	DirAccess.make_dir_recursive_absolute("user://mission_photos/test")
	var img := Image.create(48, 30, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.4, 0.8))
	img.save_png(ph["file"])
	var tex := MissionPhotos.texture(ph)
	_check(tex != null and tex.get_width() == 48 and MissionPhotos.has_image(ph), "a PNG on disk loads as the photo's texture")
	DirAccess.remove_absolute(ph["file"])
	DirAccess.remove_absolute("user://mission_photos/test")
