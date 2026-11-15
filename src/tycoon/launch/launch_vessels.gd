class_name LaunchVessels
extends RefCounted
## A real hangar vessel for a design that was not built in the hangar (a RocketDesigner design:
## main stage, upper stage, boosters, fairing), so every launch flies hangar parts: the flight
## (FlightCraft) stages, burns and drops them like any vessel the player assembled. Built with
## the hangar's own attach API (ExampleVessels' helpers) and cached per design:
##   main stage "model" 1 (Kestrel)   small kerolox stack, a cluster of Kestrels on a plate
##   2..3 (Falcão, Harpia)            large kerolox stack (Condor's), Falcão cluster
##   4..5 (Metano, Hidra)             large hydrolox stack (Garça's), a Hidra 25
##   upper stage                      its own tank and vacuum engine over a decoupler (none:
##                                    the avionics sit on the main stage)
##   boosters                         2 or 4 solid boosters on radial decouplers
##   fairing                          the fairing of its size on top (none: a payload adapter)
## The numbers of the flight come from these parts; the career outcome stays the design's.

static var _cache: Dictionary = {}


static func for_design(parts: Dictionary, target := "leo") -> PackedScene:
	var p := RocketDesigner.normalize(parts) if not parts.is_empty() else {}
	if p.is_empty():
		return null
	var key := "%s|%s|%s|%s" % [p.get("core", ""), p.get("upper", ""), p.get("boosters", ""), p.get("fairing", "")]
	if _cache.has(key):
		return _cache[key]
	var v := Vessel.new()
	var ok := _build(v, p)
	var ps: PackedScene = v.to_packed_scene() if ok and v.root else null
	v.free()
	_cache[key] = ps
	return ps


static func _model(p: Dictionary) -> int:
	return int(RocketDesigner.component(String(p.get("core", ""))).get("model", 1))


static func _build(v: Vessel, p: Dictionary) -> bool:
	var model := _model(p)
	var upper := String(p.get("upper", "upper_none"))
	var boosters := RocketDesigner.component(String(p.get("boosters", "boost_none")))
	var fairing := String(p.get("fairing", "fairing_none"))
	var small := model <= 1
	v.set_root(PartInstance.create("avionics_core_s" if small else "avionics_core_m"))
	# the top: a fairing of its size, or a payload adapter
	var top_id := "payload_adapter"
	if fairing != "fairing_none":
		top_id = "fairing_s" if small else ("fairing_m" if fairing in ["fairing_s", "fairing_m"] else "fairing_l")
		if top_id == "fairing_l" and not small:
			top_id = "fairing_m"
	_try_stack(v, v.root, "top", top_id)
	var t: PartInstance = v.root
	if upper != "upper_none":
		if small:
			t = ExampleVessels.stack(v, t, "bottom", "tank_kerolox_s2")
			t = ExampleVessels.stack(v, t, "bottom", "eng_kestrel_v")
			t = ExampleVessels.stack(v, t, "bottom", "decoupler_s")
		elif model <= 3:
			t = ExampleVessels.stack(v, t, "bottom", "adapter_ml")
			t = ExampleVessels.stack(v, t, "bottom", "tank_kerolox_l8")
			t = ExampleVessels.stack(v, t, "bottom", "tank_kerolox_l4")
			t = ExampleVessels.stack(v, t, "bottom", "eng_falcao_v")
			t = ExampleVessels.stack(v, t, "bottom", "decoupler_l")
			t = ExampleVessels.stack(v, t, "bottom", "interstage_l")
		else:
			t = ExampleVessels.stack(v, t, "bottom", "tank_hydrolox_m8")
			t = ExampleVessels.stack(v, t, "bottom", "tank_hydrolox_m4")
			t = ExampleVessels.stack(v, t, "bottom", "eng_hidra_rl")
			t = ExampleVessels.stack(v, t, "bottom", "decoupler_m")
			t = ExampleVessels.stack(v, t, "bottom", "adapter_ml")
	elif not small:
		t = ExampleVessels.stack(v, t, "bottom", "adapter_ml")
	# the main stage
	var core_top: PartInstance = null
	if small:
		core_top = ExampleVessels.stack(v, t, "bottom", "tank_kerolox_s8")
		var plate := ExampleVessels.stack(v, core_top, "bottom", "thrust_plate_s9")
		ExampleVessels.fill_slots(v, plate, "eng_kestrel")
	elif model <= 3:
		core_top = ExampleVessels.stack(v, t, "bottom", "tank_kerolox_l8")
		var ct := core_top
		for i in (3 if model == 2 else 4):
			ct = ExampleVessels.stack(v, ct, "bottom", "tank_kerolox_l8")
		var plate := ExampleVessels.stack(v, ct, "bottom", "thrust_plate_l9")
		ExampleVessels.fill_slots(v, plate, "eng_falcao")
	else:
		core_top = ExampleVessels.stack(v, t, "bottom", "tank_hydrolox_l8")
		var ct := core_top
		for i in (3 if model == 4 else 4):
			ct = ExampleVessels.stack(v, ct, "bottom", "tank_hydrolox_l8")
		ExampleVessels.stack(v, ct, "bottom", "eng_hidra_25")
	# side boosters
	var n := int(boosters.get("count", 0))
	if n >= 2 and core_top:
		var srb := "eng_srb_s" if small else "eng_srb_m"
		var rd := ExampleVessels.radial(v, core_top, "decoupler_radial", 0.0, core_top.height() * 0.5, n)
		# one booster on the first decoupler: the attach mirrors it on its symmetry partners
		var b := PartInstance.create(srb)
		v.attach(rd, b, Vessel.local_for_node(rd, "side", b, "sidechild"), "side", "sidechild")
	return true


static func _try_stack(v: Vessel, t: PartInstance, node: String, id: String) -> PartInstance:
	if PartDB.get_part(id).is_empty():
		return null
	var p := PartInstance.create(id)
	var on := Vessel.own_node_for(t, node, p)
	if on == "":
		p.free()
		return null
	v.attach(t, p, Vessel.local_for_node(t, node, p, on), node, on)
	return p
