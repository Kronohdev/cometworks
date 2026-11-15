extends SceneTree
## Every rocket and rover the player can build is ready for the launch cutscene, and the cutscene
## shows the very rocket that flies (LaunchVessels.scene_for is the one source):
##   1. every rocket design of rockets.json (each core x upper x tank x boosters x fairing)
##      builds a vessel with no error, flies as a FlightCraft with its stages and boosters, and
##      the cutscene path (DesignedRocket, as LaunchSequence dresses it) shows that same packed
##      scene part for part, at the flight's campus size
##   2. every rover the builder offers (the starter on each chassis, each part on it) assembles
##      with every part on a mount, and rides on the rocket (under a fairing and without one)
##   3. the launch sequence of a rover mission shows the rover on the rocket the flight flies
##   4. a rocket built in the hangar carries the mission's rover too (scene_for, the pad, the
##      flight), and the flight measures the real parts (FlightCraft length = the vessel's)
## Failures are listed by design, so a broken preset says which one.
## Run: godot --headless --path . --script res://tests/test_launch_vessels.gd

const DESIGNED_ROCKET := "res://scenes/tycoon/launch/designed_rocket.tscn"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	await _test_rockets()
	await _test_rovers()
	await _test_sequence()
	await _test_hangar_rover()
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL  " + msg)


static func _ids(parts: Array[PartInstance]) -> Array[String]:
	var out: Array[String] = []
	for p in parts:
		out.append(p.part_id)
	out.sort()
	return out


# ------------------------------------------------------------ 1
func _test_rockets() -> void:
	var designs := LaunchVessels.every_design()
	print("every rocket design (%d) through the cutscene path" % designs.size())
	_check(designs.size() >= 5 * 4 * 3 * 4 * 4, "every combination is listed (%d)" % designs.size())
	var dr := (load(DESIGNED_ROCKET) as PackedScene).instantiate() as DesignedRocket
	get_root().add_child(dr)
	await process_frame
	var bad := 0
	var shown := {}
	for parts in designs:
		var name := "%s/%s/%s/%s/%s" % [parts["core"], parts["upper"], parts["tank"], parts["boosters"], parts["fairing"]]
		var ps := LaunchVessels.scene_for(parts, "leo")
		var flight := TycoonModes.watch_vessel(null, parts, "leo")
		var ok := ps != null and flight == ps
		if ok:
			var c := FlightCraft.from_scene(ps, 500.0)
			var want_stages := 1 if String(parts["upper"]) == "upper_none" else 2
			var boosters := c.groups.filter(func(g: Dictionary) -> bool: return g["kind"] == "booster").size()
			var want_b := int(RocketDesigner.component(String(parts["boosters"])).get("count", 0))
			var want_f := String(parts["fairing"]) != "fairing_none"
			if c.stage_count != want_stages or boosters != want_b or (not c.fairings.is_empty()) != want_f or c.engines.is_empty():
				ok = false
				print("    %s: stages %d/%d boosters %d/%d fairing %s engines %d" % [name, c.stage_count, want_stages,
					boosters, want_b, not c.fairings.is_empty(), c.engines.size()])
			dr.build(parts)
			var flown := Vessel.new()
			flown.load_scene(ps)
			if dr.vessel == null or dr.vessel_scene != ps or _ids(dr.vessel.all_parts()) != _ids(flown.all_parts()):
				ok = false
				print("    %s: the cutscene does not show the flying vessel" % name)
			elif not is_equal_approx(dr.core_size.y, dr.vessel_length / FlightRun.island_scale(c.length)):
				ok = false
				print("    %s: size %.2f m / %.2f campus, flight %.2f m" % [name, dr.vessel_length, dr.core_size.y, c.length])
			elif dr.shown_boosters() != want_b:
				ok = false
				print("    %s: %d boosters shown, %d flown" % [name, dr.shown_boosters(), want_b])
			flown.free()
			shown[ps] = true
		if not ok:
			bad += 1
			if bad <= 20:
				print("    broken: " + name)
	dr.queue_free()
	await process_frame
	_check(bad == 0, "every rocket design flies and is shown as it flies (%d broken)" % bad)
	_check(shown.size() > 100, "the designs look different from one another (%d looks)" % shown.size())
	# the tank, the upper stage and the fairing are part of the look
	var a := LaunchVessels.scene_for({"core": "core_falcao", "tank": "tank_s"})
	var b := LaunchVessels.scene_for({"core": "core_falcao", "tank": "tank_l"})
	_check(a != b and FlightCraft.from_scene(a).length < FlightCraft.from_scene(b).length, "a longer tank is a longer rocket")


# ------------------------------------------------------------ 2
func _rovers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st := RoverDesign.starter("Teste")
	for ch: Dictionary in RoverDesign.chassis_list():
		var base := RoverDesign.toggle(st, String(ch["id"]))
		out.append(base)
		for slot in ["power", "instrument", "comms"]:
			for p in RoverDesign.parts_of(slot):
				if not RoverDesign.has_part(base, String(p["id"])):
					out.append(RoverDesign.toggle(base, String(p["id"])))
	return out


func _test_rovers() -> void:
	var rovers := _rovers()
	print("every rover (%d) on the rocket" % rovers.size())
	var bad := 0
	for d in rovers:
		var name := "%s+%s" % [d["chassis"], ",".join(d["parts"])]
		var root := Node3D.new()
		var body := RoverDesign.assemble(d, root)
		var placed := 0
		var want := 0
		for id in d["parts"]:
			if String(RoverDesign.part(String(id)).get("scene", "")) != "":
				want += 1
		var has_body := body != null
		if has_body:
			placed = body.find_children("Part_*", "", true, false).size()
		root.free()
		var look := LaunchVessels.rover_look(d)
		var ok := has_body and look != null and placed == want
		if look:
			look.free()
		if ok:
			var payload := RoverDesign.payload_ids(d)
			for fairing in ["fairing_l", "fairing_none"]:
				var ps := LaunchVessels.for_design({"core": "core_harpia", "upper": "upper_falcao_v", "fairing": fairing}, "lunar_surface", payload)
				var v := Vessel.new()
				if ps:
					v.load_scene(ps)
				var rover := v.find_child(LaunchVessels.PAYLOAD_NODE, true, false) as Node3D
				if rover == null or rover.get_child_count() == 0:
					ok = false
					print("    %s: no rover on the rocket (%s)" % [name, fairing])
				v.free()
		else:
			print("    %s: %d of %d parts on a mount" % [name, placed, want])
		if not ok:
			bad += 1
	_check(bad == 0, "every rover assembles and rides on the rocket (%d broken)" % bad)


# ------------------------------------------------------------ 3
func _test_sequence() -> void:
	print("a rover mission's launch cutscene")
	var rover := RoverDesign.starter("Teste")
	var parts := {"core": "core_harpia", "upper": "upper_falcao_v", "tank": "tank_m", "boosters": "boost_srb2", "fairing": "fairing_none"}
	var payload: Array = RoverDesign.payload_ids(rover)
	var seq := (load("res://scenes/tycoon/launch/launch_sequence.tscn") as PackedScene).instantiate() as LaunchSequence
	get_root().add_child(seq)
	await process_frame
	var team: Array[Dictionary] = []
	seq.state = TycoonState.new_campaign(31, team)
	var r := {"project_id": "", "code": "ROV-01", "type": "rover", "target": "lunar_surface", "grade": 5.0, "success": true,
		"outcome": "full", "p_success": 0.9, "payload": payload,
		"rocket": {"family": "", "name": "Teste", "parts": parts, "class": "heavy"}}
	seq.play(r)
	await process_frame
	var flies := TycoonModes.watch_vessel(null, parts, "lunar_surface", payload)
	_check(seq.designed != null and seq.designed.vessel_scene == flies, "the cutscene shows the scene the flight flies")
	_check(seq.designed != null and seq.designed.carries_rover(), "the rover rides on top of the rocket")
	_check(seq.designed != null and seq.designed.shown_boosters() == 2, "with its two boosters")
	if seq.designed:
		seq.designed.drop_boosters(0.05)
	await create_timer(0.5).timeout
	_check(seq.designed != null and seq.designed.shown_boosters() == 0, "the boosters drop at separation")
	seq.queue_free()
	await process_frame


# ------------------------------------------------------------ 4
func _test_hangar_rover() -> void:
	print("a hangar rocket with the mission's rover")
	var team: Array[Dictionary] = []
	var s := TycoonState.new_campaign(32, team)
	var m := HangarRocket.mission_for(s, "rover", "lunar_surface")
	var parts := HangarRocket.adopt(s, HangarRocket.from_scene(load("res://scenes/examples/garca.tscn"), m, "Garça"))
	var payload: Array = RoverDesign.payload_ids(RoverDesign.starter("Teste"))
	var plain := LaunchVessels.scene_for(parts, "lunar_surface", [], s)
	var ps := LaunchVessels.scene_for(parts, "lunar_surface", payload, s)
	_check(plain != null and ps != null and ps != plain, "the hangar vessel gets a copy with the rover")
	_check(ps == LaunchVessels.scene_for(parts, "lunar_surface", payload, s), "cached per vessel and rover")
	_check(TycoonModes.watch_vessel(s, parts, "lunar_surface", payload) == ps, "the career flight flies it")
	var v := Vessel.new()
	v.load_scene(ps)
	_check(v.find_child(LaunchVessels.PAYLOAD_NODE, true, false) != null, "the rover rides on it")
	v.free()
	_check(JSON.stringify(HangarRocket.tree(ps)) == JSON.stringify(HangarRocket.tree(plain)),
		"the rover is no part of the saved design")
	# the flight measures real parts: its length is the shown vessel's
	var dr := (load(DESIGNED_ROCKET) as PackedScene).instantiate() as DesignedRocket
	get_root().add_child(dr)
	await process_frame
	dr.build(parts, payload, "lunar_surface", s)
	_check(dr.carries_rover(), "the cutscene / pad look carries it")
	var len := FlightCraft.from_scene(ps).length
	_check(absf(len - dr.vessel_length) < 0.05, "the flight's length is the real vessel's (%.2f / %.2f m)" % [len, dr.vessel_length])
	dr.queue_free()
	# the pad stands the rocket of the project that leaves from it, with its payload
	var pad := (load("res://scenes/tycoon/buildings/pad.tscn") as PackedScene).instantiate() as CampusBuilding
	get_root().add_child(pad)
	await process_frame
	pad.set_look(3, 1, false)
	pad.set_rocket_design(parts, payload, "lunar_surface", s)
	await process_frame
	var d := pad.get_node_or_null("Era3/Level1/Rocket/Designed") as DesignedRocket
	_check(d != null and d.carries_rover(), "the pad's rocket carries the rover")
	pad.queue_free()
	await process_frame
