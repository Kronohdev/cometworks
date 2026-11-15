extends SceneTree
## Headless checks of the surface contract (src/world/surface_session.gd and
## src/world/surface_interactable.gd): a session starts with a rover and objectives, an
## interactable answers its objective by kind or by exact id, science is credited once,
## the result lists what was done.
## Run: godot --headless --path . --script res://tests/test_surface_session.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	_check(SurfaceSession != null and SurfaceSession.GROUP == &"surface_interactable", "SurfaceSession script loaded")
	var objs := [
		{"id": "rim", "kind": "reach", "poi_kind": "crater_rim", "science": 10.0, "label_key": "X"},
		{"id": "ice", "kind": "drill", "poi": "ice_a", "science": 20.0},
		{"id": "pano", "kind": "panorama", "science": 5.0},
	]
	var s := SurfaceSession.start(&"moon", {"name": "Tatu"}, objs, {"mission_id": "ROV-01"})
	_check(SurfaceSession.current == s, "start registers the current session")
	_check(s.surface_scene_path().ends_with("moon_surface.tscn"), "moon surface scene")
	_check(SurfaceSession.body_for_target("lunar_pole") == &"moon", "lunar pole is on the Moon")
	var reached: Array = []
	s.objective_reached.connect(func(id: StringName) -> void: reached.append(id))

	var rim := SurfaceInteractable.new()
	rim.kind = &"crater_rim"
	rim.name = "Rim"
	root.add_child(rim)
	_check(rim.is_in_group(SurfaceSession.GROUP), "an interactable joins the group")
	var r := rim.reached(null)
	_check(String(r.get("objective", "")) == "rim", "reaching the rim answers the reach objective")
	_check(rim.reached(null).is_empty(), "reached only once")

	var rock := SurfaceInteractable.new()
	rock.kind = &"rock"
	root.add_child(rock)
	var rr := rock.interact(null, &"drill")
	_check(bool(rr["ok"]) and String(rr["objective"]) == "", "a plain rock answers no objective")
	_check(float(rr["science"]) > 0.0, "but gives science once")
	_check(float(rock.interact(null, &"drill")["science"]) == 0.0, "science only once per action")

	var ice := SurfaceInteractable.new()
	ice.kind = &"ice"
	ice.objective_id = &"ice_a"
	root.add_child(ice)
	_check(not bool(ice.interact(null, &"weather")["ok"]), "an action the POI does not accept is refused")
	_check(String(ice.interact(null, &"drill")["objective"]) == "ice", "exact poi id answers the drill objective")

	_check(not s.free_objective(&"panorama").is_empty(), "panorama needs no POI")
	_check(s.report_objective(&"pano"), "report a free objective")
	_check(not s.report_objective(&"pano"), "not twice")
	_check(s.is_complete(), "all objectives done")
	_check(reached.size() == 3, "objective_reached emitted 3 times (%d)" % reached.size())
	var res := s.finish()
	_check(int(res["objectives_total"]) == 3 and (res["objectives_done"] as Array).size() == 3, "result lists them")
	_check(float(res["science"]) >= 35.0, "science summed (%.1f)" % float(res["science"]))
	_check(SurfaceSession.current == null and SurfaceSession.last_result == res, "finish clears current, keeps last_result")
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL: " + msg)
