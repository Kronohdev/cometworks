extends SceneTree
## Headless checks of the rover controller (src/rover/rover_controller.gd) on analytic voxel
## ground (heights floored to the 1 m voxels, like the real terrain):
##   - drives on the flat, turns, brakes and parks
##   - climbs a gentle ramp; on a slope past the chassis' climb angle the wheels slip (the walker
##     climbs it); a wall stops it
##   - drives off a cliff and flies, longer on the Moon than on Earth; the hopper hops (not on Earth)
##   - power: driving drains the battery, the sun / RTG recharge, an empty battery in the dark stops it
##   - tools: photo / drill / scan on points of interest report the session's objectives, the
##     drill wants the rover stopped, the drone needs air, reaching a POI and driving far count
##   - the voxel scene of the rover assembles from the design
## Run: godot --headless --path . --script res://tests/test_rover_controller.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	_check(RoverController != null, "RoverController loaded")
	_test_flat()
	_test_slopes()
	_test_air()
	_test_power()
	_test_tools()
	_test_scene()
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL: " + msg)


func _rover(design: Dictionary, g: float, heights: Callable, sun := 1.0, air := false, body := "moon") -> RoverController:
	var r := RoverController.new()
	r.player_input = false
	r.setup(design, body, g, sun, heights, air)
	r.reply_delay = 0.0
	r.place(0.0, 0.0, 0.0)
	return r


func _run(r: RoverController, seconds: float, throttle := 1.0, steer := 0.0) -> void:
	r.throttle = throttle
	r.steer = steer
	var t := 0.0
	while t < seconds:
		r.physics_step(1.0 / 60.0)
		t += 1.0 / 60.0


func _flat(_x: float, _z: float) -> float:
	return 10.0


func _basic() -> Dictionary:
	return RoverDesign.make("t", "wheels4", ["solar", "battery", "camera", "beacon"])


func _test_flat() -> void:
	var r := _rover(_basic(), 1.62, _flat)
	_check(is_equal_approx(r.position.y, 10.0), "sits on the ground (%.2f)" % r.position.y)
	_run(r, 8.0)
	_check(r.distance > 15.0, "drives forward on the flat (%.1f m)" % r.distance)
	_check(r.position.z < -15.0, "forward is -Z (z %.1f)" % r.position.z)
	_check(absf(r.speed - r.max_speed()) < 0.3, "reaches its top speed (%.2f / %.2f)" % [r.speed, r.max_speed()])
	var yaw0 := r.yaw
	_run(r, 2.0, 1.0, 1.0)
	_check(r.yaw < yaw0 - 0.5, "steering right turns (yaw %.2f -> %.2f)" % [yaw0, r.yaw])
	_run(r, 3.0, 0.0)
	_check(absf(r.speed) < 0.05, "stops without throttle (%.2f)" % r.speed)
	var e := _rover(_basic(), 9.8, _flat, 1.0, true, "earth")
	var m := _rover(_basic(), 1.62, _flat)
	_run(e, 0.6)
	_run(m, 0.6)
	_check(e.speed > m.speed, "more grip on Earth than on the Moon (%.2f vs %.2f m/s after 0.6 s)" % [e.speed, m.speed])


func _test_slopes() -> void:
	var gentle := func(_x: float, z: float) -> float: return floorf(10.0 - z * tan(deg_to_rad(10.0)))
	var r := _rover(_basic(), 3.71, gentle)
	_run(r, 10.0)
	_check(r.distance > 15.0 and r.position.y > 12.0, "climbs a 10° voxel ramp (%.1f m, up to %.1f)" % [r.distance, r.position.y])
	_check(r.pitch > deg_to_rad(5.0), "noses up on the ramp (%.1f°)" % rad_to_deg(r.pitch))
	var steep := func(_x: float, z: float) -> float: return floorf(10.0 - minf(z + 6.0, 0.0) * tan(deg_to_rad(38.0)))
	var w4 := _rover(_basic(), 3.71, steep)
	_run(w4, 10.0)
	_check(w4.position.z > -14.0, "4 wheels cannot climb 38° (z %.1f)" % w4.position.z)
	_check(w4.slipping or w4.blocked, "its wheels slip or it is blocked")
	var walker := _rover(RoverDesign.make("w", "walker", ["rtg", "camera", "beacon"]), 3.71, steep)
	_run(walker, 14.0)
	_check(walker.position.z < -14.0, "the walker climbs 38° (z %.1f)" % walker.position.z)
	var wall := func(_x: float, z: float) -> float: return 10.0 if z > -8.0 else 16.0
	var b := _rover(_basic(), 1.62, wall)
	_run(b, 8.0)
	_check(b.position.z > -8.0 and b.position.z < -3.0 and absf(b.speed) < 0.5, "a 6 m wall stops it (z %.1f)" % b.position.z)


func _test_air() -> void:
	var cliff := func(_x: float, z: float) -> float: return 20.0 if z > -12.0 else 12.0
	var airtime := {}
	for g in [1.62, 9.8]:
		var r := _rover(RoverDesign.make("t", "wheels6", ["rtg", "camera", "beacon"]), g, cliff)
		var t := 0.0
		var flown := 0.0
		r.throttle = 1.0
		while t < 12.0:
			r.physics_step(1.0 / 60.0)
			if r.airborne:
				flown += 1.0 / 60.0
			t += 1.0 / 60.0
		airtime[g] = flown
		_check(not r.airborne and is_equal_approx(r.position.y, 12.0), "lands at the bottom (g %.2f, y %.2f)" % [g, r.position.y])
	_check(airtime[1.62] > airtime[9.8] * 1.5 and airtime[1.62] > 0.5, "flies off the cliff, longer on the Moon (%.2f s vs %.2f s)" % [
		airtime[1.62], airtime[9.8]])
	var hopper := RoverDesign.make("h", "hopper", ["solar", "battery", "beacon"])
	var h := _rover(hopper, 1.62, _flat)
	var res := h.use_tool(&"hop")
	_check(bool(res["ok"]) and h.airborne, "the hopper hops on the Moon")
	var top := 0.0
	for i in 600:
		h.physics_step(1.0 / 60.0)
		top = maxf(top, h.position.y - 10.0)
	_check(top > 3.5 and h.distance > 15.0, "a hop goes high and far (%.1f m up, %.1f m away)" % [top, h.distance])
	var he := _rover(hopper, 9.8, _flat, 1.0, true, "earth")
	_check(not bool(he.use_tool(&"hop")["ok"]), "no hopping in Earth's gravity")


func _test_power() -> void:
	var dark := _rover(_basic(), 1.62, _flat, 0.0)
	var b0 := dark.battery_wh
	_run(dark, 20.0)
	_check(dark.battery_wh < b0, "driving drains the battery (%.1f -> %.1f Wh)" % [b0, dark.battery_wh])
	_run(dark, 400.0)
	_check(dark.battery_wh <= 0.001 and absf(dark.speed) < 0.05, "empty battery in the dark: it stops (%.2f m/s)" % dark.speed)
	var sunny := _rover(_basic(), 1.62, _flat, 1.0)
	sunny.battery_wh = 5.0
	_run(sunny, 30.0, 0.0)
	_check(sunny.battery_wh > 5.0, "parked in the sun it recharges (%.1f Wh)" % sunny.battery_wh)
	var nuke := _rover(RoverDesign.make("n", "wheels6", ["rtg", "battery", "camera", "beacon"]), 1.62, _flat, 0.0)
	nuke.battery_wh = 10.0
	_run(nuke, 60.0, 0.0)
	_check(nuke.battery_wh > 10.0, "an RTG charges in the dark")
	_check(nuke.power_frac() > 0.3 and nuke.power_frac() <= 1.0, "power fraction")


func _poi(kind: StringName, pos: Vector3, objective := &"") -> SurfaceInteractable:
	var p := SurfaceInteractable.new()
	p.kind = kind
	p.objective_id = objective
	p.position = pos
	root.add_child(p)
	return p


func _test_tools() -> void:
	var objs := [
		{"id": "rim", "kind": "reach", "poi_kind": "crater_rim", "science": 10.0},
		{"id": "ice", "kind": "drill", "poi_kind": "ice", "science": 20.0},
		{"id": "rock", "kind": "scan", "poi_kind": "rock", "science": 8.0},
		{"id": "pano", "kind": "panorama", "science": 5.0},
		{"id": "far", "kind": "drive", "amount": 30.0, "science": 3.0},
	]
	var s := SurfaceSession.start(&"moon", {}, objs)
	var d := RoverDesign.make("t", "wheels6", ["solar", "battery", "camera", "drill", "spectrometer", "drone", "beacon"])
	var r := _rover(d, 1.62, _flat)
	var rim := _poi(&"crater_rim", Vector3(0, 10, -20))
	var ice := _poi(&"ice", Vector3(0, 10, -24))
	var rock := _poi(&"rock", Vector3(8, 10, -24))
	r.interactables.assign([rim, ice, rock])
	_check(not bool(r.use_tool(&"weather")["ok"]), "no weather station, no weather")
	_check(not bool(r.use_tool(&"drone")["ok"]), "the drone does not fly in the Moon's vacuum")
	_run(r, 5.0)
	_check(s.objective(&"rim")["done"], "driving to the crater rim reports it")
	_check(not bool(r.use_tool(&"drill")["ok"]) or absf(r.speed) <= 0.4, "the drill wants the rover stopped")
	_run(r, 3.0, 0.0)
	r.position = Vector3(0, 10, -23)
	var dr := r.use_tool(&"drill")
	_check(bool(dr["ok"]) and String(dr["objective"]) == "ice", "drilling the ice answers its objective (%s)" % [dr])
	_run(r, 4.0, 0.0)
	var sc := r.use_tool(&"scan")
	_check(String(sc["objective"]) == "rock", "the spectrometer scans the rock in range")
	_run(r, 2.0, 0.0)
	var pa := r.use_tool(&"panorama")
	_check(String(pa["objective"]) == "pano" and r.busy > 0.0, "a panorama anywhere, the rover waits for it")
	_run(r, 4.0, 0.0)
	_run(r, 12.0)
	_check(s.objective(&"far")["done"], "driving 30 m counts (%.1f m)" % r.distance)
	_check(s.is_complete(), "all objectives done: %s" % [s.done_ids()])
	_check(s.science > 40.0 and s.photos >= 1, "science (%.1f) and photos counted" % s.science)
	var mars := _rover(d, 3.71, _flat, 0.43, true, "mars")
	mars.interactables.assign([rock])
	_check(bool(mars.use_tool(&"drone")["ok"]) and rock.has_meta("revealed"), "on Mars the drone flies and finds the rock")
	s.finish()
	for n in [rim, ice, rock]:
		n.queue_free()


func _test_scene() -> void:
	var ps := load("res://scenes/rover/rover.tscn") as PackedScene
	_check(ps != null, "rover scene loads")
	if ps == null:
		return
	var r := ps.instantiate() as RoverController
	root.add_child(r)
	r.player_input = false
	r.setup(RoverDesign.make("t", "wheels6", ["solar_wing", "battery", "camera", "drill", "arm", "hga"]), "moon", 1.62, 1.0, _flat)
	var model := r.get_node("Model")
	_check(model.get_child_count() == 1, "one chassis under Model")
	var names := []
	for n in model.find_children("Part_*", "", true, false):
		names.append(String(n.name))
	_check(names.size() == 6, "every part is mounted (%s)" % [names])
	var wheels := model.find_children("Wheel*", "Node3D", true, false)
	_check(wheels.size() == 6, "six wheels (%d)" % wheels.size())
	r.queue_free()
