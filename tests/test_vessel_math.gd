extends SceneTree
## Headless regression test: builds the three validation rockets from
## tools/hangar_calc.py with the hangar attach API (src/hangar/example_vessels.gd)
## and checks staging and Δv against the Python numbers, then checks analytic
## picking, surface snapping, scene save/load and the saved example scenes.
## Run: godot --headless --path . --script res://tests/test_vessel_math.gd

## Ascent Δv (m/s) and liftoff TWR from `python tools/hangar_calc.py`
const EXPECTED := {
	"andorinha": {"dv": 9302.0, "twr": 1.71, "stages": 2},
	"condor": {"dv": 9741.0, "twr": 1.32, "stages": 2},
	"garca": {"dv": 10282.0, "twr": 1.96, "stages": 2},
}
const TOL := 0.01

var _failures := 0


func _initialize() -> void:
	await process_frame
	for id in EXPECTED:
		_check(id, _built(id))
	_check_scene_roundtrip()
	_check_picking()
	_check_example_scenes()
	_check_insert()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _fail(msg: String) -> void:
	print("  FAIL: " + msg)
	_failures += 1


func _built(id: String) -> Vessel:
	var v := Vessel.new()
	get_root().add_child(v)
	ExampleVessels.build(v, id)
	return v


func _check(name: String, v: Vessel) -> void:
	var st := v.compute_stages()
	var r := VesselMath.analyze(st["stages"], ExampleVessels.PAYLOAD_KG[name], st["fairing_kg"], 2)
	var expd: Dictionary = EXPECTED[name]
	var dv: float = r["ascent_dv"]
	var twr: float = r["liftoff_twr"]
	var exp_dv: float = expd["dv"]
	var exp_twr: float = expd["twr"]
	var ok: bool = absf(dv - exp_dv) / exp_dv <= TOL and absf(twr - exp_twr) <= 0.02 \
		and r["stages"].size() == expd["stages"]
	var nb := 0
	for s in st["stages"]:
		nb += s["boosters"].size()
	var m := v.markers()
	print("%-10s parts=%3d stages=%d boosters=%d  dv=%7.0f (exp %5.0f)  twr=%.2f (exp %.2f)  %s" % [
		name, v.all_parts().size(), r["stages"].size(), nb, dv, exp_dv, twr, exp_twr, "OK" if ok else "MISMATCH"])
	if not ok:
		_fail("%s numbers" % name)
	if not (m["cot"].y < m["com"].y):
		_fail("%s: CoT should be below CoM" % name)


func _check_scene_roundtrip() -> void:
	var v := _built("garca")
	var before := v.all_parts().size()
	var ps := v.to_packed_scene()
	var v2 := Vessel.new()
	get_root().add_child(v2)
	v2.load_scene(ps)
	var after := v2.all_parts().size()
	var sym_ok := false
	for p in v2.all_parts():
		if p.part_id == "eng_srb_m" and p.sym_group.size() == 2:
			sym_ok = true
	var dv: float = VesselMath.analyze(v2.compute_stages()["stages"], 9000.0)["ascent_dv"]
	print("scene save/load  parts %d -> %d, symmetry restored: %s, dv %.0f" % [before, after, sym_ok, dv])
	if before != after or not sym_ok or absf(dv - 10282.0) > 5.0:
		_fail("scene roundtrip")


func _check_picking() -> void:
	var v := _built("andorinha")
	var tank: PartInstance = null
	for p in v.all_parts():
		if p.part_id == "tank_kerolox_s8":
			tank = p
	var c := tank.global_transform * Vector3(0, tank.aabb.get_center().y, 0)  # point on the tank axis
	# ray from the side aimed at the tank axis must hit the cylinder surface
	var hit := tank.ray_hit(c + Vector3(20, 0, 0), Vector3(-1, 0, 0))
	var ok_hit := not hit.is_empty() and absf((hit["point"] as Vector3).x - (c.x + tank.radius())) < 0.01
	# a ray passing beside the tank must miss
	var miss := tank.ray_hit(c + Vector3(20, 0, 5), Vector3(-1, 0, 0))
	# angle snapping: a hit at 37° snaps to 30° with 15° steps
	var a := deg_to_rad(37.0)
	var w := tank.global_transform * Vector3(cos(a) * tank.radius(), 3.0, sin(a) * tank.radius())
	var s := Vessel.surface_from_hit(tank, w, Vector3.ZERO, deg_to_rad(15.0), 0.25)
	var out: Vector3 = s["out"]
	var snapped_deg := rad_to_deg(atan2(out.z, out.x))
	var ok_snap := absf(snapped_deg - 30.0) < 0.01
	print("picking  side hit: %s  beside miss: %s  angle snap 37° -> %.1f°" % [ok_hit, miss.is_empty(), snapped_deg])
	if not ok_hit or not miss.is_empty() or not ok_snap:
		_fail("picking / snapping")


func _check_example_scenes() -> void:
	for id in EXPECTED:
		var path := "res://scenes/examples/%s.tscn" % id
		if not ResourceLoader.exists(path):
			_fail("missing example scene %s" % path)
			continue
		var v := Vessel.new()
		get_root().add_child(v)
		v.load_scene(load(path))
		var exp_dv: float = EXPECTED[id]["dv"]
		var st := v.compute_stages()
		var dv: float = VesselMath.analyze(st["stages"], ExampleVessels.PAYLOAD_KG[id], st["fairing_kg"])["ascent_dv"]
		var ok := absf(dv - exp_dv) / exp_dv <= TOL
		print("example scene %-10s parts=%d dv=%.0f %s" % [id, v.all_parts().size(), dv, "OK" if ok else "MISMATCH"])
		if not ok:
			_fail("example scene %s" % id)


func _check_insert() -> void:
	# insert a 4 m tank between Andorinha's stage decoupler and its stage-1 tank
	var v := _built("andorinha")
	var dec: PartInstance = null
	for p in v.all_parts():
		if p.part_id == "decoupler_s":
			dec = p
	var before_parts := v.all_parts().size()
	var dv_before: float = VesselMath.analyze(v.compute_stages()["stages"], 300.0, 60.0)["stages"][0]["dv_vac"]
	var held := PartInstance.create("tank_kerolox_s4")
	var on := Vessel.own_node_for(dec, "bottom", held)
	var other := Vessel.insert_node_for(dec, "bottom", held, on)
	var ok_nodes := on == "top" and other == "bottom"
	v.insert(dec, "bottom", held, Vessel.local_for_node(dec, "bottom", held, on), on)
	var moved: PartInstance = held.part_children()[0] if held.part_children().size() == 1 else null
	var ok_tree := moved != null and moved.part_id == "tank_kerolox_s8" and moved.parent_node_name == "bottom"
	# the moved tank's top must sit exactly on the inserted tank's bottom
	var gap := (held.global_transform * held.node_local("bottom")).distance_to(moved.global_transform * moved.node_local("top")) if moved else 99.0
	var dv_after: float = VesselMath.analyze(v.compute_stages()["stages"], 300.0, 60.0)["stages"][0]["dv_vac"]
	print("insert  nodes ok: %s  tree ok: %s  gap %.3f m  parts %d -> %d  stage-1 dv %.0f -> %.0f" % [
		ok_nodes, ok_tree, gap, before_parts, v.all_parts().size(), dv_before, dv_after])
	if not (ok_nodes and ok_tree and gap < 0.001 and v.all_parts().size() == before_parts + 1 and dv_after > dv_before):
		_fail("insert")
