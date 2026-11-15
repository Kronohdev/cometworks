extends SceneTree
## Headless checks for the solar-system view (scenes/solar_system/solar_system.tscn: the flight's
## map in its map-only mode, the same map as the campus' Solar System map, plus its panels):
##  - data/solar_system.json has every required body/field, a source URL, an orbit model, GM
##    and a spin pole per body
##  - the scene loads; the map shows every body (a node with 3 LOD meshes, ordered visibility
##    ranges), readable sizes are on, the list has a row per body, the card fills in
##  - the date is today's and runs with the speed keys; focusing a body moves the map
##  - every orbit line is the body's real ellipse (its periapsis / apoapsis distances)
##  - the asteroid belt and the Trojans are filled; the comet grows tails pointing away from the
##    Sun when it comes in, none far out
##  - translation keys exist in EN and PT for every body
## Run: godot --headless --path . --script res://tests/test_solar_system.gd

const REQUIRED := ["sun", "mercury", "venus", "earth", "moon", "mars", "phobos", "deimos", "jupiter", "io",
	"europa", "ganymede", "callisto", "saturn", "titan", "uranus", "neptune", "pluto", "mae_gelo"]
const FIELDS := ["radius_km", "orbital_period_days", "rotation_period_hours", "axial_tilt_deg",
	"surface_gravity_ms2", "parent", "name", "src", "visual", "orbit", "gm_km3_s2", "pole_ra_deg", "pole_dec_deg"]

var failures := 0
var checks := 0


func _initialize() -> void:
	_check_data()
	var scene := load("res://scenes/solar_system/solar_system.tscn") as PackedScene
	_ok(scene != null, "scene loads")
	if scene == null:
		_finish()
		return
	var root := scene.instantiate() as SolarSystem
	_ok(root != null, "SolarSystem script loaded")
	root.leave_to_menu = false
	get_root().add_child(root)
	for k in 6:
		await process_frame
	await _check_scene(root)
	_check_i18n(root)
	root.queue_free()
	await process_frame
	_finish()


func _check_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/solar_system.json"))
	_ok(parsed is Dictionary, "json parses")
	if not parsed is Dictionary:
		return
	var ids := {}
	for b: Dictionary in (parsed as Dictionary)["bodies"]:
		ids[b["id"]] = b
		for k in FIELDS:
			_ok(b.has(k) or (k == "orbit" and b["id"] == "sun"), "%s has %s" % [b["id"], k])
		_ok(String(b["src"]).begins_with("https://"), "%s has a source URL" % b["id"])
		var nm: Dictionary = b["name"]
		_ok(nm.has("en") and nm.has("pt"), "%s bilingual name" % b["id"])
		if b.has("orbit"):
			_ok(String((b["orbit"] as Dictionary).get("model", "")) in ["standish", "meeus47", "kepler_laplace", "kepler_helio"],
				"%s orbit model" % b["id"])
		if String(b["parent"]) != "" and String(b["parent"]) != "sun":
			_ok(b.has("semi_major_axis_km"), "%s moon distance in km" % b["id"])
		elif String(b["parent"]) == "sun":
			_ok(b.has("semi_major_axis_au"), "%s distance in AU" % b["id"])
	for id in REQUIRED:
		_ok(ids.has(id), "body %s present" % id)
	_ok(ids.has("saturn") and (ids["saturn"] as Dictionary).has("rings"), "saturn rings data")


func _check_scene(root: SolarSystem) -> void:
	var world := root.world
	var ov := root.overlay
	_ok(world != null and world.map_only, "the flight's map in map-only mode")
	_ok(ov != null and ov.world == world, "overlay bound to it")
	var map := world.map
	_ok(map.visible and map.readable, "map on screen, readable sizes on")
	var sys := world.sys
	# every body on the map with its LODs
	for i in sys.ids.size():
		var node: Node3D = map._body_nodes[i]
		_ok(node != null, "%s has a map node" % sys.ids[i])
		if node == null:
			continue
		var lods: Array[GeometryInstance3D] = []
		for k in 3:
			var inst := node.get_node_or_null("Tilt/LOD%d" % k)
			var mi := inst.get_child(0) as GeometryInstance3D if inst and inst.get_child_count() > 0 else null
			_ok(mi != null, "%s LOD%d mesh" % [sys.ids[i], k])
			if mi:
				lods.append(mi)
		if lods.size() == 3:
			var e0 := lods[0].visibility_range_end
			var e1 := lods[1].visibility_range_end
			_ok(absf(e0 - lods[1].visibility_range_begin) <= e0 * 1e-5 and absf(e1 - lods[2].visibility_range_begin) <= e1 * 1e-5,
				"%s LOD ranges contiguous" % sys.ids[i])
	# the list and the card
	var rows := 0
	for c in ov.get_node("%RowTemplate").get_parent().get_children():
		if c.visible and c.has_meta("body_id"):
			rows += 1
	_ok(rows == sys.ids.size(), "a row per body (%d)" % rows)
	ov.show_info("saturn")
	_ok((ov.get_node("%BodyName") as Label).text != "" and (ov.get_node("%VPeriod") as Label).text != "-", "Saturn's card fills in")
	# today's date, running
	var today := Time.get_datetime_dict_from_system()
	var d := sys.date_at(world.time)
	_ok(int(d["year"]) == int(today["year"]) and int(d["month"]) == int(today["month"]), "the map starts at today's date")
	ov.set_speed(4)
	var t0 := world.time
	for k in 10:
		await process_frame
	_ok(world.time > t0 + 3600.0, "a year per second: the clock runs (%.1f days in 10 frames)" % ((world.time - t0) / 86400.0))
	ov.set_speed(0)
	await process_frame
	var t1 := world.time
	for k in 4:
		await process_frame
	_ok(absf(world.time - t1) < 1e-6, "paused")
	root.focus_body("jupiter")
	_ok(map.focus == sys.index_of("jupiter"), "focusing Jupiter moves the map")
	for k in 4:
		await process_frame
	await _check_map_sync(root, ov, map, sys)
	# orbit lines are the real ellipses
	var mars := sys.index_of("mars")
	var mi_orbit: MeshInstance3D = map._orbit_nodes[mars]
	var bx := mi_orbit.transform.basis
	var a_map := bx.x.length()
	var b_map := bx.z.length()
	var sh := sys.orbit_shape(mars, world.time)
	_ok(absf(a_map / (float(sh["a"]) * FlightMap.K) - 1.0) < 1e-4 and absf(b_map / a_map - sqrt(1.0 - float(sh["e"]) ** 2)) < 1e-4,
		"Mars' orbit line is its real ellipse (e %.4f)" % float(sh["e"]))
	# clouds
	var belt := map.get_node("%AsteroidBelt") as MultiMeshInstance3D
	_ok(belt.multimesh.instance_count >= 2000, "asteroid belt filled (%d dots)" % belt.multimesh.instance_count)
	_ok((map.get_node("%Trojans") as MultiMeshInstance3D).multimesh.instance_count >= 300, "Trojans filled")
	# the comet: no tail far out (campaign start), tails away from the Sun near perihelion
	var c := sys.comet
	var cnode: Node3D = map._body_nodes[c]
	ov.t = 0.0
	for k in 3:
		await process_frame
	_ok(not (cnode.get_node("IonTail") as Node3D).visible, "no tail at 31 AU")
	ov.t = 9100.0 * 86400.0 - 3.0 * 86400.0
	for k in 3:
		await process_frame
	var ion := cnode.get_node("IonTail") as MeshInstance3D
	var st := sys.state_rel_parent(c, world.time)
	var away := Vector3(st[0], st[1], st[2]).normalized()
	_ok(ion.visible and ion.global_basis.x.normalized().dot(away) > 0.999, "near the Sun the ion tail points straight away from it")
	_ok((cnode.get_node("DustTail") as Node3D).visible, "...and the dust tail shows too")
	_ok(ion.global_basis.x.length() > 1.0e6, "the tail is millions of km long (%.0f km)" % ion.global_basis.x.length())


## Selecting from either side updates both: a click on a body in 3D -> the card and the list
## highlight; the MAPA controller's ‹ › arrows cycle the focus (label, card); Órbita / Sistema
## act on the focused body (the Moon stays in focus), Solar on the Sun.
func _check_map_sync(root: SolarSystem, ov: SolarSystemOverlay, map: FlightMap, sys: FlightSolar) -> void:
	_ok(ov.selected == sys.ids[map.focus], "the card shows the focused body (%s)" % ov.selected)
	# a left click on a body's marker on the map (no list involved)
	var pick := -1
	for i in sys.ids.size():
		if i != map.focus and map._labels[i].visible and map._body_at(map._label_screen[i]) == i:
			pick = i
			break
	_ok(pick >= 0, "a body to click on the map")
	if pick >= 0:
		var at: Vector2 = map.get_global_transform_with_canvas() * map._label_screen[pick]
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = pressed
			mb.position = at
			map.handle_input(mb)
		await process_frame
		var id := sys.ids[pick]
		_ok(map.focus == pick, "a click on %s focuses it" % id)
		_ok(ov.selected == id and (ov.get_node("%BodyName") as Label).text == ov.body_name(id),
			"...and the card follows the 3D pick (%s / %s)" % [ov.selected, id])
		var lit := []
		for c in ov.get_node("%RowTemplate").get_parent().get_children():
			if c is Button and (c as Button).button_pressed and c.visible:
				lit.append(String(c.get_meta("body_id", "")))
		_ok(lit == [id], "...and the list highlights only it (%s)" % [lit])
	# the arrows
	root.focus_body("earth")
	await process_frame
	var order := map.focus_order()
	var nxt: int = order[posmod(order.find(map.focus) + 1, order.size())]
	(map.get_node("%BtnNext") as Button).pressed.emit()
	await process_frame
	_ok(map.focus == nxt and map.focus != sys.earth, "› cycles to the next body (%s)" % map.focus_name())
	_ok((map.get_node("%Focus") as Label).text == map.focus_name(), "...the controller's label follows")
	_ok(ov.selected == sys.ids[nxt], "...and so does the card (%s)" % ov.selected)
	(map.get_node("%BtnPrev") as Button).pressed.emit()
	await process_frame
	_ok(map.focus == sys.earth, "‹ goes back to the Earth")
	# Órbita / Sistema on the Moon
	root.focus_body("moon")
	await process_frame
	(map.get_node("%BtnVessel") as Button).pressed.emit()
	await process_frame
	var moon_a := sys.sma[sys.moon] * FlightMap.K
	_ok(map.focus == sys.moon and map.dist > moon_a * 1.5 and map.dist < moon_a * 6.0,
		"Órbita keeps the Moon in focus and frames its orbit (%s, %.0f)" % [map.focus_name(), map.dist])
	(map.get_node("%BtnSystem") as Button).pressed.emit()
	await process_frame
	_ok(map.focus == sys.moon and map.dist >= moon_a * 1.5, "Sistema keeps the Moon (the Earth-Moon system in view)")
	root.focus_body("mars")
	await process_frame
	(map.get_node("%BtnSystem") as Button).pressed.emit()
	await process_frame
	_ok(map.focus == sys.index_of("mars") and map.dist >= sys.sma[sys.index_of("deimos")] * FlightMap.K * 2.0,
		"Sistema on Mars: Mars and its moons, not the Earth")
	(map.get_node("%BtnSolar") as Button).pressed.emit()
	await process_frame
	_ok(map.focus == sys.sun and ov.selected == "sun", "Solar goes to the Sun (card too)")


func _check_i18n(_root: Node) -> void:
	var sys := FlightSolar.get_system()
	for loc in ["en", "pt"]:
		TranslationServer.set_locale(loc)
		for id in sys.ids:
			for pre in ["SS_NAME_", "SS_KIND_", "SS_DESC_"]:
				var key: String = pre + id.to_upper()
				_ok(TranslationServer.translate(key) != key, "%s %s" % [loc, key])
		for key in ["SSM_READABLE", "SSM_DATE_FMT", "SSM_MONTH_12", "SSM_MENU", "SSM_COMET_NOW"]:
			_ok(TranslationServer.translate(key) != key, "%s %s" % [loc, key])
	TranslationServer.set_locale("en")


func _ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _finish() -> void:
	print("solar system tests: %d checks, %d failures" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures > 0 else 0)
