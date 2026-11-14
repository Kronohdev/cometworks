class_name ExampleVessels
extends RefCounted
## The validation rockets from tools/hangar_calc.py, assembled through the same
## attach API the hangar uses. tools/make_example_scenes.gd saves them as
## scenes/examples/*.tscn, so they can be opened in the editor and loaded in the hangar.
##
## How a rocket is built (read top to bottom, like the scene tree):
##   avionics core (root, top of the rocket)
##     └ bottom → tank → tank → engine        stage 2 (upper stage)
##         └ bottom → stack decoupler          everything below it is stage 1
##             └ bottom → tank ... → thrust plate
##                 └ slot:0..8 → engines
##     radial decoupler (surface, symmetry 2) → side → solid booster

const PAYLOAD_KG := {"andorinha": 300.0, "condor": 15000.0, "garca": 9000.0}
const DISPLAY_NAMES := {"andorinha": "Andorinha", "condor": "Condor", "garca": "Garça"}


static func display_name(id: String) -> String:
	return DISPLAY_NAMES.get(id, id.capitalize())


static func build(v: Vessel, id: String) -> void:
	match id:
		"andorinha":
			andorinha(v)
		"condor":
			condor(v)
		"garca":
			garca(v)


static func stack(v: Vessel, t: PartInstance, tnode: String, id: String) -> PartInstance:
	var p := PartInstance.create(id)
	var on := Vessel.own_node_for(t, tnode, p)
	assert(on != "", "cannot attach %s to %s.%s" % [id, t.part_id, tnode])
	v.attach(t, p, Vessel.local_for_node(t, tnode, p, on), tnode, on)
	return p


static func fill_slots(v: Vessel, plate: PartInstance, id: String) -> void:
	for k in int(plate.data["engine_slots"]):
		stack(v, plate, "slot:%d" % k, id)


static func radial(v: Vessel, t: PartInstance, id: String, angle_deg: float, height: float, symmetry: int) -> PartInstance:
	var p := PartInstance.create(id)
	var a := deg_to_rad(angle_deg)
	var world := t.global_transform * Vector3(cos(a) * t.radius(), height, sin(a) * t.radius())
	var s := Vessel.surface_from_hit(t, world)
	v.attach(t, p, Vessel.local_for_surface(t, s["point"], s["out"], p), "surface", "surface", symmetry)
	return p


static func andorinha(v: Vessel) -> void:
	v.set_root(PartInstance.create("avionics_core_s"))
	stack(v, v.root, "top", "fairing_s")
	var t2 := stack(v, v.root, "bottom", "tank_kerolox_s2")
	var e2 := stack(v, t2, "bottom", "eng_kestrel_v")
	var dec := stack(v, e2, "bottom", "decoupler_s")
	var t1 := stack(v, dec, "bottom", "tank_kerolox_s8")
	var plate := stack(v, t1, "bottom", "thrust_plate_s9")
	fill_slots(v, plate, "eng_kestrel")


static func condor(v: Vessel) -> void:
	v.set_root(PartInstance.create("avionics_core_m"))
	stack(v, v.root, "top", "payload_adapter")
	var ad := stack(v, v.root, "bottom", "adapter_ml")
	var t := stack(v, ad, "bottom", "tank_kerolox_l8")
	t = stack(v, t, "bottom", "tank_kerolox_l4")
	var e2 := stack(v, t, "bottom", "eng_falcao_v")
	var dec := stack(v, e2, "bottom", "decoupler_l")
	var ist := stack(v, dec, "bottom", "interstage_l")
	t = stack(v, ist, "bottom", "tank_kerolox_l8")
	for i in 4:
		t = stack(v, t, "bottom", "tank_kerolox_l8")
	var plate := stack(v, t, "bottom", "thrust_plate_l9")
	fill_slots(v, plate, "eng_falcao")


static func garca(v: Vessel) -> void:
	v.set_root(PartInstance.create("avionics_core_m"))
	stack(v, v.root, "top", "payload_adapter")
	var t := stack(v, v.root, "bottom", "tank_hydrolox_m8")
	t = stack(v, t, "bottom", "tank_hydrolox_m4")
	var e2 := stack(v, t, "bottom", "eng_hidra_rl")
	var dec := stack(v, e2, "bottom", "decoupler_m")
	var ad := stack(v, dec, "bottom", "adapter_ml")
	var core_top := stack(v, ad, "bottom", "tank_hydrolox_l8")
	t = core_top
	for i in 3:
		t = stack(v, t, "bottom", "tank_hydrolox_l8")
	stack(v, t, "bottom", "eng_hidra_25")
	var rd := radial(v, core_top, "decoupler_radial", 0.0, 4.0, 2)
	var srb := PartInstance.create("eng_srb_m")
	v.attach(rd, srb, Vessel.local_for_node(rd, "side", srb, "sidechild"), "side", "sidechild")
