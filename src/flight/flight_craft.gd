class_name FlightCraft
extends RefCounted
## The flying rocket as data (no nodes): the hangar vessel's stages, engines, propellant and
## masses, read once from its part tree (FlightStaging walks it exactly like the hangar's
## Vessel.compute_stages, so stage numbers match the hangar), then kept as plain numbers. The
## simulation (FlightSim) asks it for thrust, mass flow and mass; the view (FlightModel) mirrors
## which groups are still attached.
##
## Groups (FlightStaging): a group is the part subtree between decouplers. Each keeps:
##   {"stage": int (0 fires first), "kind": "stack" | "booster", "parent": group index (-1 for
##    the root), "dry": kg, "attached": bool, "parts": Array[int] (indices into `parts`)}
## Pools: one per liquid propellant of a group (its tanks feed its engines) plus one per solid
## motor, as VesselMath: {"group", "stage", "solid", "prop", "prop0", "engines": Array[int]}.
## Engines: {"group", "stage", "pool", "f_vac", "isp_vac", "isp_sl", "mdot", "tmin", "solid",
##   "restarts", "lit", "running", "thr", "thrust", "part": index, "y": nozzle height (local)}.
## Fairings ride on their group and are jettisoned at the first staging (or by `jettison()`).
## Deterministic: no randomness anywhere.

enum Sas { OFF, HOLD, PROGRADE, RETROGRADE, DIRECTION }

## Structural limits of the active rocket: q·sin(AoA) (Pa), dynamic pressure (Pa), load (g)
const LIMIT_Q_AOA := 9000.0
const LIMIT_Q := 90000.0
const LIMIT_G := 16.0

var parts: Array = []       # [{"id", "data", "group", "prop0", "y", "r", "h", "dry"}]
var groups: Array = []
var pools: Array = []
var engines: Array = []
var fairings: Array = []    # [{"part": index, "group": index, "kg": dry, "attached": bool}]
var stage_count := 0
## -1 = on the pad, nothing ignited yet
var current_stage := -1
var throttle := 1.0
var payload_kg := 0.0
## the group carrying the mission payload (the command part's)
var payload_group := 0
## Δv spent so far (m/s), for the HUD's goal and the report
var dv_used := 0.0
## autopilot / SAS mode shown on the HUD (FlightSim steers)
var sas := Sas.OFF
## the last step's total thrust (N), for the HUD
var thrust_n := 0.0
var crashed := false

# aerodynamics of the stack (axial)
var a_front := 1.0
var cd := 0.4
var length := 10.0
var radius := 1.0


# ------------------------------------------------------------ building
## The craft of a packed hangar vessel. `payload_kg` rides on the command part. Its parts are
## read off the tree, so each gets its model's real size (PartInstance.ensure_size): length,
## frontal area and nozzle heights are the rocket's own, not 1 m placeholder boxes.
static func from_scene(ps: PackedScene, payload := 0.0) -> FlightCraft:
	var v := Vessel.new()
	v.load_scene(ps)
	for p in v.all_parts():
		p.ensure_size()
	var c := from_vessel(v, payload)
	v.free()
	return c


## The craft of an assembled vessel (in the tree or not: only local transforms are read).
static func from_vessel(v: Vessel, payload := 0.0) -> FlightCraft:
	var c := FlightCraft.new()
	c.payload_kg = payload
	if v == null or v.root == null:
		return c
	var gs := FlightStaging.groups(v)
	c.stage_count = FlightStaging.stage_count(gs)
	var index := {}
	var all := v.all_parts()
	for p: PartInstance in all:
		var xf := _xf_of(p, v)
		index[p] = c.parts.size()
		c.parts.append({"id": p.part_id, "data": p.data, "group": -1, "prop0": PartDB.prop_mass(p.data),
			"y": (xf * p.aabb.get_center()).y, "top": (xf * p.aabb.end).y, "bottom": (xf * p.aabb.position).y,
			"x": (xf * p.aabb.get_center()).x, "z": (xf * p.aabb.get_center()).z,
			"r": maxf(p.radius(), 0.05), "h": maxf(p.aabb.size.y, 0.05), "dry": p.dry_mass()})
	for gi in gs.size():
		var g: Dictionary = gs[gi]
		var idx: Array[int] = []
		var dry := 0.0
		for p: PartInstance in g["parts"]:
			var i: int = index[p]
			idx.append(i)
			c.parts[i]["group"] = gi
			if not PartDB.is_fairing(p.data):
				dry += p.dry_mass()
		var root: PartInstance = g["root"]
		var parent := -1
		if root.part_parent() != null and index.has(root.part_parent()):
			parent = -2  # resolved below
		c.groups.append({"stage": int(g["stage"]), "kind": String(g["kind"]), "parent": parent, "dry": dry,
			"attached": true, "parts": idx, "root": index[root]})
	for gi in c.groups.size():
		var root_i: int = c.groups[gi]["root"]
		var rp: PartInstance = all[root_i].part_parent()
		c.groups[gi]["parent"] = int(c.parts[index[rp]]["group"]) if rp != null and index.has(rp) else -1
	# pools and engines
	for gi in gs.size():
		for pl in FlightStaging.pools(gs[gi]["parts"]):
			var pool := {"group": gi, "stage": int(gs[gi]["stage"]), "solid": bool(pl["solid"]), "prop": 0.0,
				"prop0": 0.0, "engines": [], "tanks": []}
			for t: PartInstance in pl["tanks"]:
				pool["prop0"] += PartDB.prop_mass(t.data)
				pool["tanks"].append(index[t])
			pool["prop"] = pool["prop0"]
			var pi := c.pools.size()
			for p: PartInstance in pl["engines"]:
				var d := p.data
				var f_vac := float(d.get("thrust_vac_kn", 0.0)) * 1000.0
				var isp_vac := float(d.get("isp_vac_s", 0.0))
				if f_vac <= 0.0 or isp_vac <= 0.0:
					continue
				var isp_sl := float(d.get("isp_sl_s", 0.0))
				pool["engines"].append(c.engines.size())
				c.engines.append({"group": gi, "stage": int(gs[gi]["stage"]), "pool": pi, "f_vac": f_vac,
					"isp_vac": isp_vac, "isp_sl": isp_sl if isp_sl > 0.0 else isp_vac * 0.3,
					"mdot": f_vac / (isp_vac * PartDB.G0), "tmin": float(d.get("throttle_min", 0.0)),
					"solid": bool(pl["solid"]), "restarts": int(d.get("restarts", 0)), "lit": false,
					"running": false, "thr": 0.0, "thrust": 0.0, "part": index[p],
					"y": float(c.parts[index[p]]["bottom"])})
			c.pools.append(pool)
	for p: PartInstance in all:
		if PartDB.is_fairing(p.data):
			c.fairings.append({"part": index[p], "group": int(c.parts[index[p]]["group"]), "kg": p.dry_mass(),
				"attached": true})
	c.payload_group = 0
	for p: PartInstance in all:
		if PartDB.is_command(p.data):
			c.payload_group = int(c.parts[index[p]]["group"])
			break
	c._shape()
	return c


static func _xf_of(n: Node3D, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Length, frontal area and drag coefficient of what is still attached.
func _shape() -> void:
	var lo := INF
	var hi := -INF
	var rmax := 0.05
	var area := 0.0
	var top_id := ""
	var top_y := -INF
	var discs: Array[Vector3] = []  # (x, z, r) of each attached part seen from the nose
	for i in parts.size():
		var p: Dictionary = parts[i]
		if not is_attached_part(i):
			continue
		lo = minf(lo, float(p["bottom"]))
		hi = maxf(hi, float(p["top"]))
		var off := Vector2(float(p["x"]), float(p["z"])).length()
		rmax = maxf(rmax, off + float(p["r"]))
		if float(p["top"]) > top_y:
			top_y = float(p["top"])
			top_id = String(p["data"].get("category", "")) + ":" + String(p["id"])
		discs.append(Vector3(float(p["x"]), float(p["z"]), float(p["r"])))
	# the frontal area: side by side discs add up (the core and its boosters); a disc inside a
	# wider one is in its shadow (the stack's tanks under the fairing, the engines under the plate)
	for i in discs.size():
		var d := discs[i]
		var hidden := false
		for j in discs.size():
			var o := discs[j]
			if j == i or o.z < d.z or (o.z == d.z and j > i):
				continue
			if Vector2(d.x - o.x, d.y - o.y).length() + d.z <= o.z + 0.05:
				hidden = true
				break
		if not hidden:
			area += PI * d.z * d.z
	length = maxf(hi - lo, 1.0) if lo < INF else 1.0
	radius = rmax
	a_front = maxf(area, 0.05)
	cd = 0.3 if top_id.begins_with("aero:") or top_id.ends_with("crew_capsule") else 0.42


# ------------------------------------------------------------ queries
func is_attached_part(i: int) -> bool:
	var g := int(parts[i]["group"])
	if g < 0 or not bool(groups[g]["attached"]):
		return false
	for f: Dictionary in fairings:
		if int(f["part"]) == i:
			return bool(f["attached"])
	return true


func group_attached(g: int) -> bool:
	return g >= 0 and g < groups.size() and bool(groups[g]["attached"])


## Total mass (kg) of what is attached: dry parts, propellant, fairings, payload.
func mass() -> float:
	var m := 0.0
	for g: Dictionary in groups:
		if g["attached"]:
			m += float(g["dry"])
	for pool: Dictionary in pools:
		if group_attached(int(pool["group"])):
			m += float(pool["prop"])
	for f: Dictionary in fairings:
		if f["attached"] and group_attached(int(f["group"])):
			m += float(f["kg"])
	if group_attached(payload_group):
		m += payload_kg
	return maxf(m, 1.0)


func pool_prop(pi: int) -> float:
	return float(pools[pi]["prop"]) if group_attached(int(pools[pi]["group"])) else 0.0


## Thrust (N) and mass flow (kg/s) of the lit engines at `pressure` (0 = vacuum, 1 = sea level)
## and the current throttle, without burning anything.
func thrust_at(pressure: float) -> Vector2:
	var f := 0.0
	var mdot := 0.0
	for e: Dictionary in engines:
		var thr := _engine_throttle(e, false)
		if thr <= 0.0 or pool_prop(int(e["pool"])) <= 0.0:
			continue
		var isp := float(e["isp_vac"]) + (float(e["isp_sl"]) - float(e["isp_vac"])) * pressure
		f += float(e["mdot"]) * thr * PartDB.G0 * isp
		mdot += float(e["mdot"]) * thr
	return Vector2(f, mdot)


## Burns for `dt` seconds at `pressure`: drains the pools, updates every engine's thrust and
## returns the total thrust (N). Engines whose pool runs dry flame out (`events` gets them).
func burn(dt: float, pressure: float, events: Array) -> float:
	var total := 0.0
	for pi in pools.size():
		var pool: Dictionary = pools[pi]
		var demand := 0.0
		for ei: int in pool["engines"]:
			var e: Dictionary = engines[ei]
			e["thrust"] = 0.0
			e["thr"] = _engine_throttle(e, true)
			demand += float(e["mdot"]) * float(e["thr"]) * dt
		if demand <= 0.0:
			continue
		var avail := pool_prop(pi)
		var frac := clampf(avail / demand, 0.0, 1.0)
		if frac <= 0.0:
			for ei: int in pool["engines"]:
				var e: Dictionary = engines[ei]
				if e["running"]:
					e["running"] = false
					e["thr"] = 0.0
					events.append(["EV_FLAMEOUT", {"stage": int(e["stage"]) + 1}])
			continue
		pool["prop"] = maxf(avail - demand * frac, 0.0)
		for ei: int in pool["engines"]:
			var e: Dictionary = engines[ei]
			var thr: float = e["thr"]
			if thr <= 0.0:
				continue
			var isp := float(e["isp_vac"]) + (float(e["isp_sl"]) - float(e["isp_vac"])) * pressure
			e["thrust"] = float(e["mdot"]) * thr * frac * PartDB.G0 * isp
			total += float(e["thrust"])
	thrust_n = total
	return total


func _engine_throttle(e: Dictionary, commit: bool) -> float:
	if not e["lit"] or not group_attached(int(e["group"])):
		return 0.0
	if e["solid"]:
		return 1.0 if e["running"] else 0.0
	if throttle <= 0.001:
		if commit:
			e["running"] = false
		return 0.0
	if not e["running"]:
		if int(e["restarts"]) <= 0:
			return 0.0
		if commit:
			e["restarts"] = int(e["restarts"]) - 1
			e["running"] = true
	return maxf(throttle, float(e["tmin"]))


func ignite(stage: int) -> void:
	for e: Dictionary in engines:
		if int(e["stage"]) == stage and group_attached(int(e["group"])):
			e["lit"] = true
			e["running"] = bool(e["solid"]) or throttle > 0.001


## Next stage (the space bar). Returns {"groups": detached group indices, "fairings": jettisoned
## fairing part indices}; `events` gets the stage / ignition events.
func next_stage(events: Array) -> Dictionary:
	var out := {"groups": [], "fairings": []}
	if current_stage < 0:
		current_stage = 0
		ignite(0)
		events.append(["EV_IGNITION", {"stage": 1}])
		return out
	if current_stage >= stage_count - 1:
		return out
	# the groups of the current stage drop: every stack group that fired now (not the root)
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		if g["attached"] and int(g["stage"]) == current_stage and String(g["kind"]) == "stack" 				and int(g["parent"]) >= 0:
			out["groups"].append_array(detach(gi))
	current_stage += 1
	events.append(["EV_STAGE_SEP", {"stage": current_stage}])
	if current_stage == 1:
		out["fairings"] = jettison(events)
	ignite(current_stage)
	events.append(["EV_IGNITION", {"stage": current_stage + 1}])
	return out


## Detaches a group and everything hanging from it. Returns the group indices that left
## (the first is `gi`, the subtree root the view cuts).
func detach(gi: int) -> Array:
	var out: Array = []
	if not group_attached(gi):
		return out
	out.append(gi)
	groups[gi]["attached"] = false
	for e: Dictionary in engines:
		if not group_attached(int(e["group"])):
			e["lit"] = false
			e["running"] = false
			e["thrust"] = 0.0
			e["thr"] = 0.0
	var changed := true
	while changed:
		changed = false
		for k in groups.size():
			if groups[k]["attached"] and int(groups[k]["parent"]) >= 0 and not groups[int(groups[k]["parent"])]["attached"]:
				groups[k]["attached"] = false
				changed = true
	_shape()
	return out


## Drops the fairings still attached. Returns their part indices.
func jettison(events: Array) -> Array:
	var out: Array = []
	for f: Dictionary in fairings:
		if f["attached"] and group_attached(int(f["group"])):
			f["attached"] = false
			out.append(int(f["part"]))
	if not out.is_empty():
		events.append(["EV_FAIRING", {}])
		_shape()
	return out


## Side boosters of the current stage whose propellant is gone (dropped as soon as they are
## empty, like VesselMath). Returns the detached group indices.
func spent_boosters(events: Array) -> Array:
	var out: Array = []
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		if String(g["kind"]) != "booster" or int(g["stage"]) != current_stage or not g["attached"]:
			continue
		var has_engine := false
		var empty := true
		for pi in pools.size():
			if int(pools[pi]["group"]) == gi and not (pools[pi]["engines"] as Array).is_empty():
				has_engine = true
				if pool_prop(pi) > 1e-3:
					empty = false
		if has_engine and empty:
			out.append_array(detach(gi))
			events.append(["EV_BOOSTER_SEP", {}])
	return out


## Engines of a stage still attached (the HUD's stage stickers count them).
func stage_engines(stage: int) -> Array:
	var out: Array = []
	for e: Dictionary in engines:
		if int(e["stage"]) == stage and group_attached(int(e["group"])):
			out.append(e)
	return out


## [core left, core initial, boosters left, boosters initial] propellant (kg) of a stage.
func stage_fuel(stage: int) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for pi in pools.size():
		var pool: Dictionary = pools[pi]
		if int(pool["stage"]) != stage:
			continue
		var k := 2 if String(groups[int(pool["group"])]["kind"]) == "booster" else 0
		out[k + 1] += float(pool["prop0"])
		out[k] += pool_prop(pi)
	return out


## Vacuum thrust (N) and mass flow of the engines that would burn now: the current stage, else
## the next one with propellant. {"stage", "thrust", "mdot"}.
func burn_engines() -> Dictionary:
	for s in range(maxi(current_stage, 0), stage_count):
		var f := 0.0
		var mdot := 0.0
		for e: Dictionary in stage_engines(s):
			if pool_prop(int(e["pool"])) <= 0.0:
				continue
			f += float(e["mdot"]) * PartDB.G0 * float(e["isp_vac"])
			mdot += float(e["mdot"])
		if f > 0.0:
			return {"stage": s, "thrust": f, "mdot": mdot}
	return {"stage": -1, "thrust": 0.0, "mdot": 0.0}


## Seconds of full-throttle vacuum burn for a Δv with the engines that would burn now.
func burn_time(dv: float) -> float:
	var be := burn_engines()
	if float(be["thrust"]) <= 0.0:
		return INF
	var ve := float(be["thrust"]) / float(be["mdot"])
	return mass() * (1.0 - exp(-absf(dv) / ve)) / float(be["mdot"])


## True when nothing left can burn (no stage with engines and propellant).
func spent() -> bool:
	return float(burn_engines()["thrust"]) <= 0.0


## Δv left per stage with the hangar's own math (VesselMath) and the propellant actually left:
## [{"stage", "dv" (at `pressure`), "dv_vac", "twr"}].
func remaining_dv(pressure := 0.0) -> Array:
	var out: Array = []
	var first := maxi(current_stage, 0)
	var specs: Array = []
	for s in range(first, stage_count):
		var spec := {"core": [], "boosters": []}
		for gi in groups.size():
			var g: Dictionary = groups[gi]
			if int(g["stage"]) != s or not g["attached"]:
				continue
			var datas: Array = []
			for i: int in g["parts"]:
				var d: Dictionary = parts[i]["data"]
				if PartDB.is_fairing(d):
					continue
				d = d.duplicate()
				if float(parts[i]["prop0"]) > 0.0:
					d["prop_mass_kg"] = _part_prop(i)
				datas.append(d)
			if String(g["kind"]) == "booster":
				if not datas.is_empty():
					spec["boosters"].append(datas)
			else:
				spec["core"].append_array(datas)
		specs.append(spec)
	if specs.is_empty():
		return out
	var fairing_kg := 0.0
	for f: Dictionary in fairings:
		if f["attached"] and group_attached(int(f["group"])):
			fairing_kg += float(f["kg"])
	var res := VesselMath.analyze(specs, payload_kg if group_attached(payload_group) else 0.0, fairing_kg,
		2 if current_stage <= 0 else 1)
	for st: Dictionary in res["stages"]:
		var i := int(st["stage"]) - 1
		var dv := float(st["dv_vac"])
		if i == 0:
			dv = lerpf(float(st["dv_vac"]), float(st["dv_sl"]), pressure)
		out.append({"stage": first + i, "dv": dv, "dv_vac": st["dv_vac"], "twr": st["twr_vac"]})
	return out


## Propellant left in one part (its pool's share).
func _part_prop(i: int) -> float:
	for pi in pools.size():
		var pool: Dictionary = pools[pi]
		if (pool["tanks"] as Array).has(i):
			var k := float(pool["prop"]) / maxf(float(pool["prop0"]), 1e-6)
			return float(parts[i]["prop0"]) * k
	return float(parts[i]["prop0"])


func total_dv() -> float:
	var s := 0.0
	for r: Dictionary in remaining_dv():
		s += float(r["dv_vac"])
	return s
