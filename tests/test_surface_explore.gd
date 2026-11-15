extends SceneTree
## Free play on the planet surfaces (SurfaceExplore, data/surface_explore.json, the
## scenes/surface/<body>_surface.tscn worlds):
##   data       every POI has a kind, name, fact (with an English and a Portuguese text), an
##              official source, science and known rover actions; challenge rules point at real
##              POIs; collectible types and lore lines exist
##   scenes     every POI of a body is placed once in its scene and every placed POI / ring has
##              data; reach_before / jump challenges have a start ring; every scene has the
##              Explore layer, a spawn, finds and the landforms the POIs talk about
##   placement  POIs, finds and rings sit on the voxel ground (after snapping) and not on a cliff;
##              finds are apart from each other
##   gravity    each world sets its profile's gravity (NSSDC values) in the physics space
##   play       a placeholder explorer (no rover: the test's own driver) reaches every POI and
##              find: discoveries and finds are logged, the cards show, find_all / collect_all
##              complete; the crater race completes in time and fails when too slow; the sample
##              delivery completes; the ramp jump completes in low gravity (a ballistic jump off
##              the ramp lip at rover speed stays longer in the air on the Moon than on Mars,
##              and longer there than on Earth)
##   log        the free-play log survives a save / load round trip in its file; in a career it
##              lives in the discovery journal, survives to_dict / from_dict, writes a journal
##              note and research points; a new career opens only Earth, a lunar landing opens
##              the Moon; collected finds stay hidden on the next visit
##   photo      photo mode hides the other HUD layers and gives them back
##   free play  without the rover side the menu opens the body's scene (drone); a sandbox session
##              carries its context; the campus button shows only after a landing, its picker
##              locks the bodies not reached (the menu's picker none); the campus viewer puts the
##              campus to sleep, holds the clock, runs the surface and gives everything back on Esc
## Run: godot --headless --path . --script res://tests/test_surface_explore.gd

const BODIES := ["moon", "mars", "europa", "mercury", "earth"]
const ACTIONS := ["photo", "scan", "drill", "sample"]
const NSSDC := {"moon": 1.62, "mars": 3.71, "europa": 1.315, "mercury": 3.70, "earth": 9.80}
const TEST_LOG := "user://test_surface_log.json"

var _fails := 0
var _checks := 0
var _csv := {}


## The placeholder explorer: stands on the ground (no rover yet in this branch).
class Driver:
	extends Node3D
	var airborne := false


func _initialize() -> void:
	SurfaceLog.free_path = TEST_LOG
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LOG))
	_read_csv()
	_data()
	for b: String in BODIES:
		await _world(b)
	await _jump_physics()
	await _career_log()
	await _free_play()
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LOG))
	print("SURFACE EXPLORE: %d checks, %s" % [_checks, "PASS" if _fails == 0 else "FAIL (%d)" % _fails])
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _read_csv() -> void:
	var f := FileAccess.open("res://i18n/surface_explore_strings.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3:
			_csv[row[0]] = [row[1], row[2]]


func _has_text(key: String) -> bool:
	return _csv.has(key) and String(_csv[key][0]) != "" and String(_csv[key][1]) != ""


# ------------------------------------------------------------ data
func _data() -> void:
	var d := SurfaceExplore.data()
	_check(d.has("bodies") and d.has("collectible_types"), "data loads")
	var ids := {}
	for t: String in d["collectible_types"]:
		var ct: Dictionary = d["collectible_types"][t]
		_check(_has_text(String(ct.get("name_key", ""))) and _has_text(String(ct.get("desc_key", ""))), "collectible %s texts" % t)
	for k: String in d.get("crumb_lore", []):
		_check(_has_text(k), "lore %s" % k)
	for b: String in BODIES:
		var bd := SurfaceExplore.body_data(b)
		_check(not bd.is_empty(), "%s has free-play data" % b)
		_check(_has_text(String(bd.get("name_key", ""))), "%s name" % b)
		var poi_ids := {}
		for e: Dictionary in bd.get("pois", []):
			var id := String(e.get("id", ""))
			_check(id != "" and not ids.has(id), "POI id %s unique" % id)
			ids[id] = true
			poi_ids[id] = true
			_check(String(e.get("kind", "")) != "", "%s kind" % id)
			_check(_has_text(String(e.get("name_key", ""))), "%s name text" % id)
			_check(_has_text(String(e.get("fact_key", ""))), "%s fact text (en + pt)" % id)
			_check(_has_text("TY_SX_KIND_" + String(e.get("kind", "")).to_upper()), "%s kind hint text" % id)
			_check(String(e.get("source", "")).begins_with("https://"), "%s has a source" % id)
			_check(float(e.get("science", 0)) > 0.0, "%s gives science" % id)
			for a: String in e.get("actions", []):
				_check(a in ACTIONS, "%s action %s known" % [id, a])
		for k: String in (bd.get("collect_facts", {}) as Dictionary).values():
			_check(_has_text(k), "%s find fact %s" % [b, k])
		for c: Dictionary in bd.get("challenges", []):
			var cid := String(c.get("id", ""))
			_check(_has_text(String(c.get("name_key", ""))) and _has_text(String(c.get("desc_key", ""))), "%s texts" % cid)
			match String(c.get("type", "")):
				"reach_before":
					_check(poi_ids.has(String(c.get("target", ""))) and float(c.get("time_s", 0)) > 0.0, "%s target / time" % cid)
				"jump":
					_check(float(c.get("air_s", 0)) > 0.0, "%s air time" % cid)
				"deliver":
					_check(poi_ids.has(String(c.get("from", ""))) and poi_ids.has(String(c.get("to", ""))), "%s from / to" % cid)
				"find_all", "collect_all":
					pass
				_:
					_check(false, "%s type known" % cid)


# ------------------------------------------------------------ one world
func _world(b: String) -> void:
	var path := "res://scenes/surface/%s_surface.tscn" % b
	var surf := (load(path) as PackedScene).instantiate() as PlanetSurface
	get_root().add_child(surf)
	await _frames(3)
	var bd := SurfaceExplore.body_data(b)
	var ex := surf.get_node_or_null("Explore") as SurfaceExplore
	_check(ex != null, "%s has the Explore layer" % b)
	_check(not get_nodes_in_group(SurfaceSession.SPAWN_GROUP).is_empty(), "%s has a spawn" % b)
	_check(not surf.collect_features().is_empty(), "%s has authored landforms" % b)
	# gravity
	var g := float(PhysicsServer3D.area_get_param(surf.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY))
	_check(is_equal_approx(g, surf.profile.gravity) and absf(surf.profile.gravity - float(NSSDC[b])) < 0.006,
		"%s gravity %.3f m/s² (NSSDC %.3f)" % [b, g, NSSDC[b]])
	# scene <-> data
	var placed := {}
	for p: SurfacePoi in ex.pois:
		var id := String(p.entry_id)
		_check(not placed.has(id), "%s POI %s placed once" % [b, id])
		placed[id] = true
		_check(not p.entry.is_empty(), "%s POI %s has data" % [b, id])
		_check(p.is_in_group(SurfaceSession.GROUP), "%s POI %s is a SurfaceInteractable for the rover" % [b, id])
		_on_ground(surf, p, 0.05 + absf(p.ground_offset), "%s POI %s" % [b, id])
		_check(_slope(surf, p.global_position) < 1.6, "%s POI %s not on a cliff (%.2f)" % [b, id, _slope(surf, p.global_position)])
	for e: Dictionary in bd.get("pois", []):
		_check(placed.has(String(e["id"])), "%s data POI %s is placed in the scene" % [b, e["id"]])
	var rings := {}
	for n in surf.find_children("*", "SurfaceChallenge", true, false):
		var r := n as SurfaceChallenge
		_check(not r.entry.is_empty(), "%s ring %s has data" % [b, r.entry_id])
		rings[String(r.entry_id)] = r
		_on_ground(surf, r, 0.1, "%s ring %s" % [b, r.entry_id])
	for c: Dictionary in bd.get("challenges", []):
		if String(c["type"]) in ["reach_before", "jump"]:
			_check(rings.has(String(c["id"])), "%s challenge %s has a start ring" % [b, c["id"]])
	_check(ex.collectibles.size() >= 4, "%s has finds (%d)" % [b, ex.collectibles.size()])
	for i in ex.collectibles.size():
		var c := ex.collectibles[i]
		_on_ground(surf, c, 0.05, "%s find %s" % [b, c.name])
		for j in range(i + 1, ex.collectibles.size()):
			var d := c.global_position.distance_to(ex.collectibles[j].global_position)
			_check(d > 8.0, "%s finds %s and %s apart (%.1f m)" % [b, c.name, ex.collectibles[j].name, d])
	await _play(surf, ex, b, rings)
	surf.queue_free()
	await _frames(3)


func _on_ground(surf: PlanetSurface, n: Node3D, tol: float, what: String) -> void:
	var p := n.global_position
	var g := surf.ground_height(p.x, p.z)
	var off := float(n.get("ground_offset")) if "ground_offset" in n else 0.0
	_check(absf(p.y - (g + off)) <= tol, "%s on the ground (y %.2f, ground %.2f)" % [what, p.y, g])
	if surf.profile.has_sea:
		_check(g > surf.profile.sea_level + 0.5, "%s above the sea" % what)


func _slope(surf: PlanetSurface, p: Vector3) -> float:
	var hx := absf(surf.ground_height(p.x + 2.0, p.z) - surf.ground_height(p.x - 2.0, p.z)) / 4.0
	var hz := absf(surf.ground_height(p.x, p.z + 2.0) - surf.ground_height(p.x, p.z - 2.0)) / 4.0
	return maxf(hx, hz)


func _put(surf: PlanetSurface, d: Driver, x: float, z: float) -> void:
	d.global_position = Vector3(x, surf.ground_height(x, z), z)


# ------------------------------------------------------------ playing it with the placeholder driver
func _play(surf: PlanetSurface, ex: SurfaceExplore, b: String, rings: Dictionary) -> void:
	var d := Driver.new()
	d.name = "TestDriver"
	surf.add_child(d)
	surf.set_focus(d)
	ex.set_process(false)
	ex.set_process_unhandled_input(false)
	ex._refresh_explorer()
	_check(ex.explorer == d and not ex.is_rover(), "%s explorer is the placeholder driver" % b)
	var bd := SurfaceExplore.body_data(b)
	var flog := ex.field_log
	# races first, before the target POI is reached by the walk
	for c: Dictionary in bd.get("challenges", []):
		if String(c["type"]) == "reach_before" and rings.has(String(c["id"])):
			_race(surf, ex, d, c, rings[String(c["id"])], b)
	# deliveries: take the sample, then go to the lander
	for c: Dictionary in bd.get("challenges", []):
		if String(c["type"]) == "deliver":
			var from := ex._poi_by_id(String(c["from"]))
			var to := ex._poi_by_id(String(c["to"]))
			from.interact(d, StringName(from.actions[0]))
			var ch := _ch(ex, String(c["id"]))
			_check(String(ch["phase"]) == "carry", "%s %s: sample on board" % [b, c["id"]])
			_put(surf, d, to.global_position.x, to.global_position.z)
			to.was_reached = false
			ex._drone_reach()
			_check(bool(flog.challenge(b, String(c["id"])).get("done", false)), "%s %s delivered" % [b, c["id"]])
	# walk to every POI and find
	var found_signal := [0]
	ex.discovered.connect(func(_id: String, first: bool) -> void:
		if first:
			found_signal[0] += 1)
	for p in ex.pois:
		_put(surf, d, p.global_position.x + 1.0, p.global_position.z)
		ex._drone_reach()
		_check(flog.is_found(b, String(p.get_interact_id())), "%s POI %s found when reached" % [b, p.entry_id])
	_check(_card_visible(ex), "%s discovery card shows" % b)
	for c in ex.collectibles:
		_put(surf, d, c.global_position.x, c.global_position.z + 1.0)
		ex._drone_reach()
		_check(c.is_collected and not c.visible and not c.is_in_group(SurfaceSession.GROUP), "%s find %s picked up" % [b, c.name])
	_check(flog.collected_count(b) == ex.collectibles.size(), "%s every find logged (%d)" % [b, flog.collected_count(b)])
	for c: Dictionary in bd.get("challenges", []):
		if String(c["type"]) in ["find_all", "collect_all"]:
			_check(bool(flog.challenge(b, String(c["id"])).get("done", false)), "%s %s complete" % [b, c["id"]])
	# drone F on a POI: the next action, its fact as the message
	var p0 := ex.pois[0]
	_put(surf, d, p0.global_position.x, p0.global_position.z)
	var res := ex.drone_investigate()
	_check(bool(res.get("ok", false)) and String(res.get("message_key", "")) == p0.fact_key(), "%s F investigates %s" % [b, p0.entry_id])
	# the log panel fills without errors and lists every place
	ex.open_log()
	_check(_log_rows(ex) == (bd.get("pois", []) as Array).size(), "%s log lists every place" % b)
	ex.close_log()
	# photo mode hides the other HUD layers and gives them back
	var other := CanvasLayer.new()
	surf.add_child(other)
	ex.enter_photo_mode()
	_check(ex.photo_mode and not other.visible and ex.photo_cam.current, "%s photo mode hides the HUDs" % b)
	_check(ex.photographed_pois() is Array, "%s photo mode frames POIs" % b)
	ex.exit_photo_mode()
	_check(not ex.photo_mode and other.visible, "%s photo mode gives the HUDs back" % b)
	other.queue_free()
	# free play log file: saved and read back
	flog.save()
	var again := SurfaceLog.open(null)
	_check(again.found_count(b) == flog.found_count(b) and again.collected_count(b) == flog.collected_count(b),
		"%s free-play log round trip (%d places, %d finds)" % [b, again.found_count(b), again.collected_count(b)])
	d.queue_free()
	# next visit: the finds stay picked up
	var surf2 := (load("res://scenes/surface/%s_surface.tscn" % b) as PackedScene).instantiate() as PlanetSurface
	get_root().add_child(surf2)
	await _frames(3)
	var ex2 := surf2.get_node("Explore") as SurfaceExplore
	var hidden := 0
	for c in ex2.collectibles:
		hidden += 1 if c.is_collected and not c.visible else 0
	_check(hidden == ex2.collectibles.size(), "%s finds stay hidden next visit (%d/%d)" % [b, hidden, ex2.collectibles.size()])
	surf2.queue_free()
	await _frames(2)


func _ch(ex: SurfaceExplore, id: String) -> Dictionary:
	for ch in ex.challenges:
		if String(ch["entry"]["id"]) == id:
			return ch
	return {}


func _race(surf: PlanetSurface, ex: SurfaceExplore, d: Driver, c: Dictionary, ring: SurfaceChallenge, b: String) -> void:
	var ch := _ch(ex, String(c["id"]))
	var target := ex._poi_by_id(String(c["target"]))
	# too slow: leave the ring and dawdle past the time limit
	_put(surf, d, ring.global_position.x, ring.global_position.z)
	ex._tick_challenges(0.1)
	_check(String(ch["phase"]) == "armed", "%s %s armed in the ring" % [b, c["id"]])
	_put(surf, d, ring.global_position.x + ring.radius + 2.0, ring.global_position.z)
	ex._tick_challenges(0.1)
	_check(String(ch["phase"]) == "running", "%s %s starts when leaving the ring" % [b, c["id"]])
	ex._tick_challenges(float(c["time_s"]) + 1.0)
	_check(String(ch["phase"]) == "idle" and not bool(ex.field_log.challenge(b, String(c["id"])).get("done", false)),
		"%s %s fails when too slow" % [b, c["id"]])
	# in time: back to the ring, out, then at the rim after 30 s
	_put(surf, d, ring.global_position.x, ring.global_position.z)
	ex._tick_challenges(0.1)
	_put(surf, d, ring.global_position.x + ring.radius + 2.0, ring.global_position.z)
	ex._tick_challenges(0.1)
	ex._tick_challenges(30.0)
	_put(surf, d, target.global_position.x, target.global_position.z)
	ex._tick_challenges(0.1)
	var rec := ex.field_log.challenge(b, String(c["id"]))
	_check(bool(rec.get("done", false)) and absf(float(rec.get("best", 0)) - 30.2) < 0.2,
		"%s %s done in time (best %.1f s)" % [b, c["id"], float(rec.get("best", 0))])


static func _card_visible(ex: SurfaceExplore) -> bool:
	return ex.get_node("%Card").visible


static func _log_rows(ex: SurfaceExplore) -> int:
	var n := 0
	for c in ex.get_node("%PlaceTemplate").get_parent().get_children():
		if c.has_meta("from_template"):
			n += 1
	return n


# ------------------------------------------------------------ the jump, with gravity
## A ballistic jump off the ramp lip at rover speed (4 m/s) over the real terrain of each body:
## the airtime grows as gravity shrinks, and on the Moon / Mars / Europa / Mercury it passes the
## challenge's air time; the challenge completes when the driver lands after that long.
func _jump_physics() -> void:
	var times := {}
	for b: String in ["moon", "mars", "europa", "mercury", "earth"]:
		var surf := (load("res://scenes/surface/%s_surface.tscn" % b) as PackedScene).instantiate() as PlanetSurface
		get_root().add_child(surf)
		await _frames(3)
		var ramp: SurfaceTerrainFeature = null
		for f in surf.find_children("*", "SurfaceTerrainFeature", true, false):
			if (f as SurfaceTerrainFeature).shape == SurfaceTerrainFeature.Shape.RAMP:
				ramp = f
		_check(ramp != null, "%s has a ramp" % b)
		if ramp == null:
			surf.queue_free()
			continue
		var fd := ramp.to_feature()
		var dir := Vector3(cos(float(fd["yaw"])), 0.0, sin(float(fd["yaw"])))
		var lip := ramp.global_position + dir * (ramp.size_a - 0.3)
		var top := surf.ground_height(lip.x, lip.z)
		# the ramp's own slope at the lip (the voxel steps are smoothed by the rover's wheels)
		var angle := atan(ramp.height * 1.4 / (2.0 * ramp.size_a))
		_check(top - surf.ground_height(lip.x + dir.x * 3.0, lip.z + dir.z * 3.0) > 1.0, "%s ramp has a lip to jump from" % b)
		var v := 4.0
		var vel := Vector3(dir.x * v * cos(angle), v * sin(angle), dir.z * v * cos(angle))
		var pos := Vector3(lip.x, top + 0.3, lip.z)
		var g := surf.profile.gravity
		var t := 0.0
		while t < 20.0:
			t += 0.01
			vel.y -= g * 0.01
			pos += vel * 0.01
			if pos.y <= surf.ground_height(pos.x, pos.z) + 0.3 and vel.y < 0.0:
				break
		times[b] = t
		# the challenge: in the ring, then that long in the air, then landing
		var ex := surf.get_node("Explore") as SurfaceExplore
		ex.set_process(false)
		var d := Driver.new()
		surf.add_child(d)
		surf.set_focus(d)
		ex._refresh_explorer()
		var cid := ""
		for c: Dictionary in SurfaceExplore.body_data(b).get("challenges", []):
			if String(c["type"]) == "jump":
				cid = String(c["id"])
		var ring: SurfaceChallenge = null
		for n in surf.find_children("*", "SurfaceChallenge", true, false):
			if String((n as SurfaceChallenge).entry_id) == cid:
				ring = n
		var need := float(SurfaceExplore.challenge_entry(StringName(cid)).get("air_s", 1.0))
		_put(surf, d, ring.global_position.x, ring.global_position.z)
		ex._tick_challenges(0.1)
		d.airborne = true
		var flown := 0.0
		while flown < t:
			ex._tick_challenges(0.05)
			flown += 0.05
		d.airborne = false
		ex._tick_challenges(0.05)
		var done := bool(ex.field_log.challenge(b, cid).get("done", false))
		print("  jump %s: g %.3f m/s², %.2f s in the air (goal %.1f s) -> %s" % [b, g, t, need, "done" if done else "short"])
		_check(done == (t >= need), "%s jump challenge %s matches the airtime" % [b, cid])
		if b != "earth":
			_check(done, "%s: the low-gravity jump makes it at rover speed" % b)
		surf.queue_free()
		await _frames(2)
	_check(times.get("europa", 0.0) > times.get("moon", 0.0) and times.get("moon", 0.0) > times.get("mars", 0.0)
		and times.get("mars", 0.0) > times.get("earth", 0.0), "airtime grows as gravity shrinks: %s" % str(times))


# ------------------------------------------------------------ career
func _career_log() -> void:
	var s := TycoonState.new_campaign(7)
	var open := SurfaceLog.unlocked_bodies(s)
	_check(open.size() == 1 and open[0] == "earth", "a new career opens only Earth (%s)" % str(open))
	s.mission_archive.append({"type": "lander", "target": "lunar_surface", "outcome": "partial"})
	_check(SurfaceLog.is_unlocked(s, "moon") and not SurfaceLog.is_unlocked(s, "mars"), "a lunar landing opens the Moon")
	s.mission_archive.clear()
	s.active_missions.append({"type": "rover", "target": "lunar_pole", "status": "ops"})
	_check(SurfaceLog.is_unlocked(s, "moon"), "a rover at work on the Moon opens it too")
	s.active_missions.clear()
	_check(not SurfaceLog.is_unlocked(s, "moon"), "a failed / no landing keeps the Moon closed")
	SurfaceLog.unlock_all(s)
	_check(SurfaceLog.unlocked_bodies(s).size() == BODIES.size(), "dev: every surface open")
	# a career run on the Moon: the log lives in the journal
	var host := Node.new()
	host.set_script(load("res://tests/surface_test_host.gd"))
	host.set("state", s)
	get_root().add_child(host)
	var surf := (load("res://scenes/surface/moon_surface.tscn") as PackedScene).instantiate() as PlanetSurface
	host.add_child(surf)
	await _frames(3)
	var ex := surf.get_node("Explore") as SurfaceExplore
	_check(ex.state == s and ex.field_log.state == s, "the Moon run finds the career")
	var rp0 := s.research_points
	var notes0 := Discovery.notes(s).size()
	var d := Driver.new()
	surf.add_child(d)
	surf.set_focus(d)
	ex.set_process(false)
	ex._refresh_explorer()
	var p := ex._poi_by_id("moon_eagle_homage")
	_put(surf, d, p.global_position.x, p.global_position.z)
	ex._drone_reach()
	_check(ex.field_log.is_found("moon", "moon_eagle_homage"), "career: the tribute site is logged")
	_check(s.research_points > rp0, "career: research points from the discovery (%.1f -> %.1f)" % [rp0, s.research_points])
	_check(Discovery.notes(s).size() > notes0 and String(Discovery.notes(s)[0]["key"]) == "TY_SX_NOTE_FOUND",
		"career: a journal note per place found (%d)" % (Discovery.notes(s).size() - notes0))
	_check(TycoonHUD.news_text(Discovery.notes(s)[0]).find("TY_") < 0, "career: the journal note reads without raw keys")
	var rp1 := s.research_points
	p.was_reached = false
	ex._drone_reach()
	_check(is_equal_approx(s.research_points, rp1), "career: science only once per place")
	var back := TycoonState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var l2 := SurfaceLog.open(back)
	_check(l2.is_found("moon", "moon_eagle_homage") and l2.found_count("moon") == ex.field_log.found_count("moon"),
		"career log survives to_dict / from_dict")
	_check(SurfaceLog.is_unlocked(back, "mars"), "career: the dev unlock survives the save")
	host.queue_free()
	await _frames(2)


# ------------------------------------------------------------ free play entry points
func _free_play() -> void:
	_check(not SurfaceFreePlay.has_rover() or ResourceLoader.exists(SurfaceSession.DRIVE_SCENE), "rover side detection")
	if not SurfaceFreePlay.has_rover():
		_check(SurfaceFreePlay.scene_path(&"mars") == "res://scenes/surface/mars_surface.tscn", "no rover: the menu opens the body's scene")
		_check(SurfaceFreePlay.prepare_from_menu(&"moon") == "res://scenes/surface/moon_surface.tscn" and SurfaceSession.current == null,
			"no rover: no session for the drone")
	var ss := SurfaceFreePlay.make_session(&"europa", {"return": "tycoon"})
	_check(ss.body == &"europa" and bool(ss.context.get("sandbox", false)) and bool(ss.context.get("free_play", false))
		and String(ss.context.get("return", "")) == "tycoon", "a free-play session carries its context")
	SurfaceSession.current = null
	# the career host with a campus to put to sleep
	var s := TycoonState.new_campaign(11)
	var host := Node.new()
	host.set_script(load("res://tests/surface_test_host.gd"))
	host.set("state", s)
	host.set("clock", TycoonClock.new(s.rules))
	var campus := Node3D.new()
	campus.name = "Campus"
	host.add_child(campus)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	host.add_child(ui)
	get_root().add_child(host)
	var button := (load("res://scenes/surface/explore/surface_campus_button.tscn") as PackedScene).instantiate() as SurfaceCampusButton
	ui.add_child(button)
	await _frames(3)
	_check(button.main() == host and not button.visible, "campus button hidden before any landing")
	s.mission_archive.append({"type": "rover", "target": "lunar_surface", "outcome": "full"})
	button._refresh()
	_check(button.visible, "campus button shows after a lunar landing")
	button.open_picker()
	await _frames(2)
	var rows := _picker_rows(button.picker)
	_check(rows.has("moon") and not (rows["moon"] as Button).disabled and rows.has("mars") and (rows["mars"] as Button).disabled
		and not (rows["earth"] as Button).disabled, "campus picker: the Moon and Earth open, Mars locked")
	button.picker.close()
	var menu_picker := (load("res://scenes/surface/explore/surface_picker.tscn") as PackedScene).instantiate() as SurfacePicker
	get_root().add_child(menu_picker)
	menu_picker.open(null)
	await _frames(2)
	var mrows := _picker_rows(menu_picker)
	var all_open := mrows.size() == BODIES.size()
	for k: String in mrows:
		all_open = all_open and not (mrows[k] as Button).disabled
	_check(all_open, "menu picker: every surface open")
	menu_picker.queue_free()
	# the viewer over the sleeping campus
	(host.get("clock") as TycoonClock).set_speed(2)
	button.picker._pick("moon")
	await _frames(4)
	var viewer: SurfaceViewer = null
	for c in host.get_children():
		if c is SurfaceViewer:
			viewer = c
	_check(viewer != null and viewer.surface != null and viewer.surface.profile.id == &"moon", "campus viewer opens the Moon")
	_check(not campus.visible and campus.process_mode == Node.PROCESS_MODE_DISABLED and not ui.visible
		and (host.get("clock") as TycoonClock).speed == 0, "the campus sleeps, its HUD hides and the clock holds")
	var ex := viewer.surface.get_node("Explore") as SurfaceExplore
	_check(ex.state == s, "the surface in the viewer finds the career")
	ex.leave()
	await _frames(3)
	_check(not is_instance_valid(viewer) or viewer.is_queued_for_deletion(), "Esc / Voltar closes the viewer")
	_check(campus.visible and campus.process_mode == Node.PROCESS_MODE_INHERIT and ui.visible
		and (host.get("clock") as TycoonClock).speed == 2, "the campus wakes up with its clock speed")
	host.queue_free()
	await _frames(2)


func _picker_rows(p: SurfacePicker) -> Dictionary:
	var out := {}
	for c in p.get_node("%BodyTemplate").get_parent().get_children():
		if c.has_meta("from_template") and c.has_meta("body"):
			out[String(c.get_meta("body"))] = c
	return out
