class_name FlightStaging
extends RefCounted
## Instance-level version of the hangar's staging (Vessel.compute_stages): the same walk
## of the attach tree, split at decouplers, but keeping the PartInstances of every group
## so the flight can drain each group's own tanks and detach whole subtrees.
## tests/test_flight.gd checks that the stage of every part matches compute_stages().
##
## Group: {"parts": Array[PartInstance], "level": int, "kind": "stack"/"booster",
##         "owner": int (group index), "root": PartInstance (decoupler or vessel root),
##         "stage": int (0 = fires first)}


static func groups(v: Vessel) -> Array:
	var out: Array = []
	if v.root == null:
		return out
	out.append({"parts": [], "level": 0, "kind": "stack", "owner": 0, "root": v.root})
	_collect(v.root, 0, out)
	var max_level := 0
	for g in out:
		max_level = maxi(max_level, g["level"])
	for g in out:
		var owner_level: int = out[g["owner"]]["level"] if g["kind"] == "booster" else g["level"]
		g["stage"] = max_level - owner_level
	return out


static func _collect(p: PartInstance, gi: int, out: Array) -> void:
	out[gi]["parts"].append(p)
	for c in p.part_children():
		if PartDB.is_stack_decoupler(c.data):
			out.append({"parts": [], "level": out[gi]["level"] + 1, "kind": "stack", "owner": out.size(), "root": c})
			_collect(c, out.size() - 1, out)
		elif PartDB.is_radial_decoupler(c.data):
			var owner_gi: int = out[gi]["owner"] if out[gi]["kind"] == "booster" else gi
			out.append({"parts": [], "level": out[gi]["level"], "kind": "booster", "owner": owner_gi, "root": c})
			_collect(c, out.size() - 1, out)
		else:
			_collect(c, gi, out)


static func stage_count(gs: Array) -> int:
	var n := 0
	for g in gs:
		n = maxi(n, int(g["stage"]) + 1)
	return n


## Propellant pools of one group, like VesselMath._pools: one pool per liquid propellant
## (fed by the group's tanks, feeding the group's engines of that propellant) plus one pool
## per solid motor. Each pool: {"propellant", "tanks": Array[PartInstance], "engines":
## Array[PartInstance], "solid": bool}. Fairings never carry propellant.
static func pools(group_parts: Array) -> Array:
	var liquid := {}
	var out: Array = []
	for p: PartInstance in group_parts:
		if p.data.get("category", "") == "tank":
			var prop: String = p.data.get("propellant", "")
			if not liquid.has(prop):
				liquid[prop] = {"propellant": prop, "tanks": [], "engines": [], "solid": false}
			liquid[prop]["tanks"].append(p)
	for p: PartInstance in group_parts:
		if not PartDB.is_engine(p.data):
			continue
		var prop: String = p.data.get("propellant", "")
		if prop == "solid":
			out.append({"propellant": prop, "tanks": [p], "engines": [p], "solid": true})
		elif liquid.has(prop):
			liquid[prop]["engines"].append(p)
	for k in liquid:
		if not liquid[k]["engines"].is_empty():
			out.append(liquid[k])
	return out
