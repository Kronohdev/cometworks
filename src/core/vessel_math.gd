class_name VesselMath
extends RefCounted
## Hangar engineering math. GDScript port of tools/hangar_calc.py; the regression
## test in tests/test_vessel_math.gd checks both give the same numbers.
##
## A stage spec is {"core": Array[Dictionary part], "boosters": Array[Array[Dictionary part]]}.
## Stages are in firing order (index 0 = stage 1). Each booster group is one booster
## instance; it fires with its stage and is dropped as soon as its propellant runs out.

const DT := 0.25


static func _engine_thrust_isp(e: Dictionary, vacuum: bool) -> Vector2:
	var f := float(e.get("thrust_vac_kn" if vacuum else "thrust_sl_kn", 0.0)) * 1000.0
	var isp := float(e.get("isp_vac_s" if vacuum else "isp_sl_s", 0.0))
	return Vector2(f, isp)


## Builds propellant pools for a group of parts: one pool per liquid propellant
## (fed by the group's tanks) plus one pool per solid motor.
static func _pools(group: Array) -> Array:
	var liquid := {}
	var pools: Array = []
	for p in group:
		if p.get("category", "") == "tank":
			var prop: String = p.get("propellant", "")
			if not liquid.has(prop):
				liquid[prop] = {"prop": 0.0, "engines": []}
			liquid[prop]["prop"] += float(p.get("prop_mass_kg", 0.0))
	for p in group:
		if p.get("category", "") != "engine":
			continue
		var prop: String = p.get("propellant", "")
		if prop == "solid":
			pools.append({"prop": float(p.get("prop_mass_kg", 0.0)), "engines": [p]})
		elif liquid.has(prop):
			liquid[prop]["engines"].append(p)
	for k in liquid:
		pools.append(liquid[k])
	return pools


static func _pool_thrust(pool: Dictionary, vacuum: bool) -> Vector2:
	## Returns (total thrust N, combined Isp s) with Isp_eff = ΣF / Σ(F/Isp).
	var f_tot := 0.0
	var flow := 0.0
	for e in pool["engines"]:
		var fi := _engine_thrust_isp(e, vacuum)
		if fi.x <= 0.0 or fi.y <= 0.0:
			continue
		f_tot += fi.x
		flow += fi.x / fi.y
	return Vector2(f_tot, f_tot / flow if flow > 0.0 else 0.0)


static func _group_mass(group: Array) -> float:
	var m := 0.0
	for p in group:
		m += float(p.get("mass_kg", 0.0)) + PartDB.prop_mass(p)
	return m


static func _group_dry(group: Array) -> float:
	var m := 0.0
	for p in group:
		m += float(p.get("mass_kg", 0.0))
	return m


static func _stage_wet(st: Dictionary) -> float:
	var m := _group_mass(st["core"])
	for b in st["boosters"]:
		m += _group_mass(b)
	return m


static func _simulate(stages: Array, payload_kg: float, fairing_kg: float, fairing_drop_stage: int,
		vacuum_all: bool) -> Array:
	var rows: Array = []
	for i in stages.size():
		var stage_no := i + 1
		var vac := vacuum_all or stage_no > 1
		var upper := payload_kg + (fairing_kg if stage_no < fairing_drop_stage else 0.0)
		for j in range(i + 1, stages.size()):
			upper += _stage_wet(stages[j])
		var st: Dictionary = stages[i]
		var core_pools := _pools(st["core"])
		var boosters: Array = []
		for b in st["boosters"]:
			var pools := _pools(b)
			var prop_in_pools := 0.0
			for pl in pools:
				prop_in_pools += pl["prop"]
			boosters.append({"pools": pools, "dry": _group_mass(b) - prop_in_pools})
		var m := upper + _stage_wet(st)
		var m0 := m
		var all_pools: Array = core_pools.duplicate()
		for b in boosters:
			all_pools.append_array(b["pools"])
		var f0 := 0.0
		for pl in all_pools:
			if pl["prop"] > 0.0:
				f0 += _pool_thrust(pl, vac).x
		var dv := 0.0
		var t := 0.0
		var guard := 0
		while guard < 200000:
			guard += 1
			var f_tot := 0.0
			for pl in all_pools:
				if pl["prop"] <= 1e-6:
					continue
				var fi := _pool_thrust(pl, vac)
				if fi.x <= 0.0:
					continue
				var mdot := fi.x / (fi.y * PartDB.G0)
				var burn := minf(mdot * DT, pl["prop"])
				pl["prop"] -= burn
				m -= burn
				f_tot += fi.x * (burn / (mdot * DT))
			if f_tot <= 0.0:
				break
			dv += f_tot / m * DT
			t += DT
			for b in boosters:
				var empty := true
				for pl in b["pools"]:
					if pl["prop"] > 1e-6 and _pool_thrust(pl, vac).x > 0.0:
						empty = false
				if empty and b["dry"] > 0.0:
					m -= b["dry"]
					for pl in b["pools"]:
						m -= pl["prop"]  # unburnable leftovers leave with the booster
						pl["prop"] = 0.0
					b["dry"] = 0.0
		rows.append({"stage": stage_no, "m0_kg": m0, "dv": dv, "twr": f0 / (m0 * PartDB.G0), "burn_s": t})
	return rows


## Returns {"stages": [{stage, m0_kg, dv_sl, dv_vac, twr_sl, twr_vac, burn_s}], "ascent_dv", "liftoff_twr", "mass_kg"}
static func analyze(stages: Array, payload_kg := 0.0, fairing_kg := 0.0, fairing_drop_stage := 2) -> Dictionary:
	if stages.is_empty():
		return {"stages": [], "ascent_dv": 0.0, "liftoff_twr": 0.0, "mass_kg": payload_kg + fairing_kg}
	var sl := _simulate(stages, payload_kg, fairing_kg, fairing_drop_stage, false)
	var vac := _simulate(stages, payload_kg, fairing_kg, fairing_drop_stage, true)
	var out: Array = []
	for i in sl.size():
		out.append({"stage": i + 1, "m0_kg": vac[i]["m0_kg"], "dv_sl": sl[i]["dv"], "dv_vac": vac[i]["dv"],
			"twr_sl": sl[i]["twr"], "twr_vac": vac[i]["twr"], "burn_s": vac[i]["burn_s"]})
	var ascent: float = (out[0]["dv_sl"] + out[0]["dv_vac"]) * 0.5
	for i in range(1, out.size()):
		ascent += out[i]["dv_vac"]
	return {"stages": out, "ascent_dv": ascent, "liftoff_twr": out[0]["twr_sl"], "mass_kg": out[0]["m0_kg"]}
