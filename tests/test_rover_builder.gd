extends SceneTree
## Headless checks of the rover builder's rules (src/rover/rover_design.gd, rover_garage.gd):
##   - the parts load; payload parts take their numbers from payload.json
##   - validation: chassis, power, antenna, bays, research locks
##   - stats: mass and cost add up, range, sun per body, tools
##   - the payload link: a design becomes payload modules + one rover module, its mass counts in
##     the planner's mass gauge, and the payload gives the design back
##   - the garage saves designs per career and survives a save / load (and old saves have none)
## Run: godot --headless --path . --script res://tests/test_rover_builder.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	_check(RoverDesign != null and RoverDesign.chassis_list().size() == 4, "RoverDesign loaded with 4 chassis")
	_test_parts()
	_test_validation()
	_test_stats()
	_test_payload()
	_test_garage()
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL: " + msg)


func _test_parts() -> void:
	for slot in ["chassis", "power", "instrument", "comms"]:
		_check(not RoverDesign.parts_of(slot).is_empty(), "parts of slot %s" % slot)
	for p: Dictionary in RoverDesign.parts_of("power") + RoverDesign.parts_of("instrument") + RoverDesign.parts_of("comms") \
			+ RoverDesign.parts_of("chassis"):
		var id := String(p["id"])
		_check(ResourceLoader.exists(String(p.get("scene", ""))), "%s has a voxel scene" % id)
		if p.has("payload"):
			_check(not PayloadRules.module(String(p["payload"])).is_empty(), "%s maps to payload %s" % [id, p["payload"]])
		_check(TranslationServer.translate(RoverDesign.name_key(id)) != RoverDesign.name_key(id), "%s has a name" % id)
	var cam := RoverDesign.part_stats("camera")
	_check(cam["mass"] == float(PayloadRules.module("camera")["mass"]), "camera mass comes from payload.json")


func _test_validation() -> void:
	var d := RoverDesign.starter("Tatu")
	_check(RoverDesign.validate(d).is_empty(), "the starter rover is valid: %s" % [RoverDesign.validate(d)])
	var none := RoverDesign.make("x", "", ["solar", "beacon"])
	_check("RV_ERR_NO_CHASSIS" in RoverDesign.validate(none), "no chassis")
	var dark := RoverDesign.make("x", "wheels4", ["camera", "beacon"])
	_check("RV_ERR_NO_POWER" in RoverDesign.validate(dark), "no power")
	var deaf := RoverDesign.make("x", "wheels4", ["solar", "camera"])
	_check("RV_ERR_NO_ANTENNA" in RoverDesign.validate(deaf), "no antenna")
	var full := RoverDesign.make("x", "wheels4", ["solar", "beacon", "camera", "drill", "spectrometer", "arm"])
	_check("RV_ERR_BAYS" in RoverDesign.validate(full), "4 instruments do not fit 3 bays")
	full["chassis"] = "wheels6"
	_check(not "RV_ERR_BAYS" in RoverDesign.validate(full), "they fit the 6-wheeler's 5 bays")
	var t := RoverDesign.toggle(d, "omni")
	_check("omni" in t["parts"] and not "beacon" in t["parts"], "an antenna replaces the antenna")
	t = RoverDesign.toggle(t, "wheels6")
	_check(t["chassis"] == "wheels6", "a chassis replaces the chassis")
	t = RoverDesign.toggle(t, "camera")
	_check(not "camera" in t["parts"], "toggle removes a part")
	# research
	var s := TycoonState.new_campaign(4242)
	_check(not RoverDesign.is_available(s, "wheels6"), "6 wheels locked before Mobilidade de rover")
	_check(not RoverDesign.is_available(s, "drill"), "drill locked before its research")
	_check("RV_ERR_LOCKED" in RoverDesign.validate(full, s), "a locked part blocks the design")
	s.unlocked["rover_mobility"] = true
	_check(RoverDesign.is_available(s, "wheels6"), "6 wheels after the research")
	_check(RoverDesign.tech_for("wheels6") == "rover_mobility", "tech_for names the research")
	_check(RoverDesign.tech_for("drill") == "guided_descent", "the drill comes with its payload research")


func _test_stats() -> void:
	var d := RoverDesign.make("x", "wheels4", ["solar", "battery", "camera", "beacon"])
	var st := RoverDesign.stats(d, "moon")
	var want := 18.0 + 4.0 + 3.0 + 8.0 + 1.0
	_check(is_equal_approx(st["mass"], want), "mass adds up (%.1f == %.1f)" % [st["mass"], want])
	_check(st["cost"] > 20000.0, "cost adds up")
	_check(st["tools"] == ["photo"], "a camera gives the photo tool")
	_check(st["range_km"] > 0.0, "battery range on the Moon (%.1f km)" % st["range_km"])
	var mars := RoverDesign.stats(d, "mars")
	_check(mars["gen_here"] < st["gen_here"], "Mars has less sunlight than the Moon")
	var nuke := RoverDesign.toggle(d, "rtg")
	_check(RoverDesign.stats(nuke, "mars")["range_km"] < 0.0, "an RTG drives forever")
	var drone := RoverDesign.make("x", "wheels6", ["solar", "battery", "drone", "beacon"])
	_check(not RoverDesign.stats(drone, "moon")["drone_ok"] and RoverDesign.stats(drone, "mars")["drone_ok"],
		"the drone flies on Mars, not in the Moon's vacuum")
	var two := RoverDesign.make("x", "wheels6", ["solar", "beacon", "camera", "spectrometer"])
	_check(RoverDesign.stats(two)["science"] > 6.0 + 12.0, "two tools get the combo bonus")
	_check("hop" in RoverDesign.tools(RoverDesign.make("x", "hopper", ["solar", "beacon"])), "the hopper hops")


func _test_payload() -> void:
	var d := RoverDesign.make("Tatu Ágil", "wheels6", ["solar", "battery", "camera", "arm", "omni"])
	var ids := RoverDesign.payload_ids(d)
	_check("camera" in ids and "solar_body" in ids and "omni" in ids, "payload modules of the design: %s" % [ids])
	var code := RoverDesign.payload_code(d)
	_check(code in ids and RoverDesign.is_code(code), "one rover module (%s)" % code)
	var m := PayloadRules.module(code)
	_check(String(m.get("kind", "")) == "rover", "PayloadRules knows the rover module")
	_check(is_equal_approx(float(m["mass"]), 30.0 + 9.0), "rover module = chassis + own parts (%.1f)" % float(m["mass"]))
	_check(PayloadRules.name_key(code) == "TY_PL_M_ROVER", "its name key")
	var back := RoverDesign.from_payload(ids)
	_check(back["name"] == "Tatu Ágil" and back["chassis"] == "wheels6", "name and chassis come back")
	for p in d["parts"]:
		_check(p in back["parts"], "part %s comes back" % p)
	_check(RoverDesign.from_payload(["camera", "omni"]).is_empty(), "no rover module, no rover")
	var s := TycoonState.new_campaign(99)
	var g := PayloadRules.gauges(s, {"type": "rover", "target": "lunar_surface", "payload": ids})
	var total := 0.0
	for id in ids:
		total += float(PayloadRules.module(id).get("mass", 0.0))
	_check(is_equal_approx(float(g["mass"]["have"]), total), "the planner's mass gauge counts the rover (%.1f kg)" % total)
	var heavy := RoverDesign.make("Pesadão", "wheels6", ["solar_wing", "rtg", "camera", "spectrometer", "drill", "arm", "hga"])
	var gh := PayloadRules.gauges(s, {"type": "rover", "target": "lunar_surface", "payload": RoverDesign.payload_ids(heavy)})
	_check(String(gh["mass"]["state"]) == "red", "a too heavy rover does not fit the lander (%.0f kg / %.0f)" % [
		gh["mass"]["have"], gh["mass"]["need"]])
	var applied := RoverDesign.apply_to_payload(["sensor_pack", "beacon", "rover:wheels4:@old"], d)
	_check("sensor_pack" in applied and not "beacon" in applied and not "rover:wheels4:@old" in applied,
		"applying a rover replaces the old rover and the antenna: %s" % [applied])


func _test_garage() -> void:
	var s := TycoonState.new_campaign(7)
	_check(RoverGarage.designs(s).is_empty(), "a new career has no rovers")
	RoverGarage.save_design(s, RoverDesign.starter("Tatu"))
	RoverGarage.save_design(s, RoverDesign.make("Tatu", "wheels6", ["solar", "beacon"]))
	RoverGarage.save_design(s, RoverDesign.make("Jabuti", "walker", ["rtg", "hga", "drill"]))
	_check(RoverGarage.designs(s).size() == 2, "same name replaces")
	_check(RoverGarage.find(s, "Tatu")["chassis"] == "wheels6", "the newer Tatu is kept")
	_check(RoverGarage.free_name(s, "Tatu") == "Tatu 2", "free name")
	RoverGarage.drives(s)["ROV-01"] = {"science": 12.0}
	var json := JSON.stringify(s.to_dict())
	var s2 := TycoonState.from_dict(JSON.parse_string(json))
	_check(RoverGarage.designs(s2).size() == 2 and RoverGarage.find(s2, "Jabuti")["chassis"] == "walker", "designs survive save / load")
	_check(float(RoverGarage.drive_of(s2, "ROV-01").get("science", 0.0)) == 12.0, "drives survive save / load")
	var old := s.to_dict()
	old.erase("rovers")
	var s3 := TycoonState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(RoverGarage.designs(s3).is_empty(), "an old save loads with an empty garage")
	_check(RoverGarage.delete(s, "Jabuti") and RoverGarage.designs(s).size() == 1, "delete")
