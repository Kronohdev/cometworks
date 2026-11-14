extends SceneTree
## Headless checks for the solar-system map:
##  - data/solar_system.json has every required body/field with a NASA source URL
##  - the scene loads, every body has a SolarBody node with 3 LOD meshes whose visibility
##    ranges are ordered and contiguous (lod0.end == lod1.begin, lod1.end == lod2.begin)
##  - moons are children of their parent body, orbit math advances and stays periodic
##  - translation keys exist in EN and PT for every body
## Run: godot --headless --path . --script res://tests/test_solar_system.gd

const REQUIRED := ["sun", "mercury", "venus", "earth", "moon", "mars", "jupiter", "europa", "saturn",
	"uranus", "neptune"]
const FIELDS := ["radius_km", "orbital_period_days", "rotation_period_hours", "axial_tilt_deg",
	"surface_gravity_ms2", "parent", "name", "src", "visual"]

var failures := 0
var checks := 0


func _initialize() -> void:
	_check_data()
	var scene := load("res://scenes/solar_system/solar_system.tscn") as PackedScene
	_ok(scene != null, "scene loads")
	if scene == null:
		_finish()
		return
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	_check_scene(root)
	_check_motion(root)
	_check_i18n(root)
	root.queue_free()
	await process_frame
	_finish()


func _check_data() -> void:
	var txt := FileAccess.get_file_as_string("res://data/solar_system.json")
	var parsed: Variant = JSON.parse_string(txt)
	_ok(parsed is Dictionary, "json parses")
	if not parsed is Dictionary:
		return
	var ids := {}
	for b: Dictionary in (parsed as Dictionary)["bodies"]:
		ids[b["id"]] = b
		for k in FIELDS:
			_ok(b.has(k), "%s has %s" % [b["id"], k])
		_ok(String(b["src"]).begins_with("https://nssdc.gsfc.nasa.gov/"), "%s src is a NASA fact sheet" % b["id"])
		var nm: Dictionary = b["name"]
		_ok(nm.has("en") and nm.has("pt"), "%s bilingual name" % b["id"])
		_ok((b["visual"] as Dictionary).has("palette"), "%s palette" % b["id"])
		if String(b["parent"]) != "" and String(b["parent"]) != "sun":
			_ok(b.has("semi_major_axis_km"), "%s moon distance in km" % b["id"])
		elif String(b["parent"]) == "sun":
			_ok(b.has("semi_major_axis_au"), "%s distance in AU" % b["id"])
	for id in REQUIRED:
		_ok(ids.has(id), "body %s present" % id)
	_ok(ids.has("saturn") and (ids["saturn"] as Dictionary).has("rings"), "saturn rings data")


func _check_scene(root: Node) -> void:
	var bodies := {}
	for n in root.find_children("*", "SolarBody", true, false):
		bodies[(n as SolarBody).body_id] = n
	for id in REQUIRED:
		_ok(bodies.has(id), "SolarBody %s in scene" % id)
	var tris := 0
	for id: String in bodies:
		var b: SolarBody = bodies[id]
		var lods: Array[GeometryInstance3D] = []
		for k in 3:
			var inst := b.get_node_or_null("Pivot/Anchor/Tilt/Spin/LOD%d" % k)
			_ok(inst != null, "%s LOD%d node" % [id, k])
			if inst == null:
				continue
			var mi := inst.get_node_or_null("%s_lod%d" % [id, k]) as MeshInstance3D
			_ok(mi != null and mi.mesh != null, "%s lod%d mesh loaded" % [id, k])
			if mi:
				lods.append(mi)
				if k == 0:
					for s in mi.mesh.get_surface_count():
						tris += (mi.mesh.surface_get_array_index_len(s)) / 3
		if lods.size() == 3:
			_ok(lods[0].visibility_range_begin == 0.0 and lods[0].visibility_range_end > 0.0, "%s lod0 range" % id)
			_ok(is_equal_approx(lods[0].visibility_range_end, lods[1].visibility_range_begin), "%s lod0/1 contiguous" % id)
			_ok(lods[1].visibility_range_end > lods[1].visibility_range_begin, "%s lod1 ordered" % id)
			_ok(is_equal_approx(lods[1].visibility_range_end, lods[2].visibility_range_begin), "%s lod1/2 contiguous" % id)
			_ok(lods[2].visibility_range_end == 0.0 or lods[2].visibility_range_end > lods[2].visibility_range_begin,
				"%s lod2 ordered" % id)
			var t0 := _tris(lods[0])
			var t1 := _tris(lods[1])
			var t2 := _tris(lods[2])
			_ok(t0 > t1 and t1 > t2, "%s triangle counts decrease (%d > %d > %d)" % [id, t0, t1, t2])
		_ok(b.label() != null, "%s label" % id)
	# moons orbit their parent
	for pair in [["moon", "earth"], ["europa", "jupiter"]]:
		var m: Node = bodies.get(pair[0])
		var p: SolarBody = bodies.get(pair[1])
		_ok(m != null and p != null and m.get_parent() == p.get_node("Pivot/Anchor"), "%s orbits %s" % pair)
	_ok(root.get_node_or_null("Bodies/Saturn/Pivot/Anchor/Tilt/Rings/Rings0") != null, "saturn rings in scene")
	_ok(root.get_node_or_null("UI/Root") is Control, "HUD present")
	print("lod0 triangles, all bodies: %d" % tris)


func _tris(g: GeometryInstance3D) -> int:
	var m := (g as MeshInstance3D).mesh
	var t := 0
	for s in m.get_surface_count():
		t += m.surface_get_array_index_len(s) / 3
	return t


func _check_motion(root: Node) -> void:
	var earth: SolarBody = null
	for n in root.find_children("Earth", "SolarBody", true, false):
		earth = n
	if earth == null:
		_ok(false, "earth for motion test")
		return
	earth.time_scale = 1.0
	earth.reset_to_days(0.0)
	var a0 := earth.orbit_angle
	var p0 := earth.body_position()
	earth.advance(0.5)
	_ok(earth.orbit_angle > a0, "orbit angle advances")
	_ok(earth.body_position().distance_to(p0) > 0.0, "earth moves")
	earth.reset_to_days(earth.orbital_period_days)
	_ok(is_equal_approx(fposmod(earth.orbit_angle - a0, TAU), 0.0) or is_equal_approx(fposmod(earth.orbit_angle - a0, TAU), TAU),
		"orbit is periodic")
	_ok(absf(earth.body_position().length() - earth.orbit_radius) < 0.01, "earth stays on its orbit radius")
	_ok(is_equal_approx(SolarBody._soft(0.1, 1.0), 1.0 * tanh(0.1)), "soft clamp")


func _check_i18n(root: Node) -> void:
	var sys := root as SolarSystem
	for loc in ["en", "pt"]:
		TranslationServer.set_locale(loc)
		for id: String in sys.bodies:
			var k := "SS_NAME_" + id.to_upper()
			_ok(TranslationServer.translate(k) != k, "%s %s" % [loc, k])
			for pre in ["SS_KIND_", "SS_DESC_"]:
				_ok(TranslationServer.translate(pre + id.to_upper()) != pre + id.to_upper(), "%s %s%s" % [loc, pre, id])
	TranslationServer.set_locale("pt")
	_ok(TranslationServer.translate("SS_NAME_EARTH") == "Terra", "pt Earth = Terra")
	_ok(sys.num(149597.87, 1) == "149.597,9", "pt number format (%s)" % sys.num(149597.87, 1))
	TranslationServer.set_locale("en")
	_ok(sys.num(149597.87, 1) == "149,597.9", "en number format")


func _ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)


func _finish() -> void:
	print("solar system tests: %d checks, %d failures" % [checks, failures])
	print("ALL PASSED" if failures == 0 else "FAILED")
	quit(0 if failures == 0 else 1)
