class_name PayloadRules
extends RefCounted
## The payload planner's rules (GDD sections 7 and 8.1): the modules a mission can carry
## (instruments, power, comms, heaters, a recorder; data/tycoon/payload.json, unlocked by the
## research tree's options) and the six gauges a plan is checked against:
##   mass     modules' kg vs the bus allowance of the mission type
##   energy   generation vs consumption by day, batteries (and RTG) vs the night; battery-only
##            types (short flights) run on batteries. Uses the environment the agency KNOWS:
##            a hidden fact (the 14-day lunar night, the cold) is assumed away until discovered
##   data     onboard storage vs storage_weeks of the instruments' data
##   comms    downlink (antenna x network x distance x contact, MissionOps) vs the data made
##   budget   cash vs the plan's total cost (and the client's budget: yellow when over it)
##   time     weeks vs the briefing's deadline
## Margins: green >= 0.2, yellow >= 0.05, red below. Red mass, energy (by day) or budget blocks
## the plan; a night the batteries do not cover or the cold only warns (MissionFit counts it).
## Static functions; the state is only read.

const PATH := "res://data/tycoon/payload.json"

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(PATH)
		_by_id.clear()
		for m: Dictionary in _data.get("modules", []):
			_by_id[String(m["id"])] = m
	return _data


static func section(name: String) -> Dictionary:
	return data().get(name, {})


static func modules() -> Array:
	return data().get("modules", [])


static func module(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func modules_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in modules():
		if String(m.get("kind", "")) == kind:
			out.append(m)
	return out


static func name_key(id: String) -> String:
	return "TY_PL_M_" + id.to_upper()


static func is_available(state: TycoonState, id: String) -> bool:
	var m := module(id)
	if m.is_empty():
		return false
	var opt := String(m.get("option", ""))
	return opt == "" or bool(state.unlocked.get("option:" + opt, false))


static func available(state: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in modules():
		if is_available(state, String(m["id"])):
			out.append(m)
	return out


## The tech that unlocks a module ("" when it is there from the start).
static func tech_for(id: String) -> String:
	var opt := String(module(id).get("option", ""))
	if opt == "":
		return ""
	for t: Dictionary in TycoonResearch.techs():
		if opt in (t.get("unlocks", {}) as Dictionary).get("options", []):
			return String(t["id"])
	return ""


static func type_rules(type_id: String) -> Dictionary:
	return section("types").get(type_id, {})


static func is_surface(type_id: String) -> bool:
	return type_id in data().get("surface_types", [])


# ------------------------------------------------------------ environment
static func env_true(target_id: String) -> Dictionary:
	return section("env").get(target_id, section("assumed"))


## The environment as the agency knows it: hidden facts it has not discovered are replaced by
## the assumed values (`known` = true gives the real one, for the mission's real outcome).
static func env(state: TycoonState, target_id: String, known := false, briefing_id := "") -> Dictionary:
	var e := env_true(target_id).duplicate()
	if known or Discovery.env_known(state, target_id, briefing_id):
		return e
	var a := section("assumed")
	for f: String in e.get("hidden", []):
		e[f] = a.get(f, e[f])
	return e


# ------------------------------------------------------------ plan numbers
static func mass_allowance(state: TycoonState, type_id: String) -> float:
	var b := section("bus")
	var per_type: Dictionary = b.get("allowance_type", {})
	if per_type.has(type_id):
		return float(per_type[type_id])
	var size := float(state.mission_type(type_id).get("size", 1.0))
	return maxf(size * float(b.get("allowance_per_size", 70.0)), float(b.get("allowance_min", 30.0)))


static func bus_power(state: TycoonState, type_id: String) -> float:
	return float(section("bus").get("bus_w_per_size", 8.0)) * float(state.mission_type(type_id).get("size", 1.0))


static func _sum(payload: Array, key: String) -> float:
	var t := 0.0
	for id in payload:
		t += float(module(String(id)).get(key, 0.0))
	return t


static func cost(payload: Array) -> float:
	return _sum(payload, "cost")


static func instruments(payload: Array) -> Array[String]:
	var out: Array[String] = []
	for id in payload:
		if String(module(String(id)).get("kind", "")) == "instrument":
			out.append(String(id))
	return out


static func antenna(payload: Array) -> String:
	for id in payload:
		if String(module(String(id)).get("group", "")) == "antenna":
			return String(id)
	return ""


static func data_rate(payload: Array) -> float:
	return _sum(payload, "data")


static func storage(state: TycoonState, type_id: String, payload: Array) -> float:
	return float(MissionOps.type_ops(type_id).get("storage", 30.0)) + _sum(payload, "storage")


## Antenna gain of the plan (no antenna: a whisper of 0.2).
static func antenna_gain(payload: Array) -> float:
	var a := antenna(payload)
	return float(module(a).get("gain", 1.0)) if a != "" else 0.2


static func contact_mult(payload: Array) -> float:
	var m := 1.0
	for id in payload:
		m = maxf(m, float(module(String(id)).get("contact_mult", 1.0)))
	return m


## Gb per week the agency's antennas would bring down from this plan now.
static func downlink(state: TycoonState, type_id: String, target_id: String, payload: Array) -> float:
	var lvl := MissionOps.antenna_level(state)
	var m := {"target": target_id, "type": type_id, "antenna_gain": antenna_gain(payload)}
	var c := MissionOps.contact(target_id, lvl)
	var boosted := minf(c * contact_mult(payload), 1.0)
	return MissionOps.downlink_rate_at(m, lvl) * (boosted / maxf(c, 0.0001))


static func is_warm(payload: Array) -> bool:
	for id in payload:
		if module(String(id)).get("warm", false):
			return true
	return false


## Energy check of a plan in an environment: {"day_gen", "use", "day_margin", "store",
## "night_need", "night_supply", "night_margin", "cold_ok", "battery_only", "margin"}.
static func energy(state: TycoonState, type_id: String, payload: Array, e: Dictionary) -> Dictionary:
	var b := section("bus")
	var bus := bus_power(state, type_id)
	var use := bus + _sum(payload, "power")
	var store := _sum(payload, "store")
	var rtg := 0.0
	var solar := 0.0
	for id in payload:
		var m := module(String(id))
		if m.get("warm", false) and m.has("gen"):
			rtg += float(m["gen"])
		elif m.has("gen"):
			solar += float(m["gen"])
	var sun := float(e.get("sun", 1.0))
	var day_gen := solar * sun + rtg
	var battery_only: bool = type_id in b.get("battery_only", [])
	var day_margin := 0.0
	if battery_only:
		day_margin = (store + day_gen) / maxf(use * float(b.get("battery_hours", 1.0)), 0.001) - 1.0
	else:
		day_margin = day_gen / maxf(use, 0.001) - 1.0
	var night := float(e.get("night", 0.0)) if not battery_only else 0.0
	var cold := bool(e.get("cold", false))
	var night_use := bus * float(b.get("night_idle", 0.25)) + (_sum(payload, "night_power") if cold else 0.0)
	var night_need := night_use * night
	var night_supply := store + rtg * night
	var night_margin := 1.0 if night_need <= 0.0 else night_supply / night_need - 1.0
	var cold_ok := not cold or is_warm(payload)
	return {"day_gen": day_gen, "use": use, "day_margin": day_margin, "store": store, "night_need": night_need,
		"night_supply": night_supply, "night_margin": night_margin, "cold_ok": cold_ok, "battery_only": battery_only,
		"margin": minf(day_margin, night_margin) if cold_ok else minf(minf(day_margin, night_margin), -1.0)}


static func state_of(margin: float) -> String:
	var g := section("gauges")
	if margin >= float(g.get("green", 0.2)):
		return "green"
	if margin >= float(g.get("yellow", 0.05)):
		return "yellow"
	return "red"


## The six gauges of a plan, as the agency sees them (known environment):
## {"mass": {"have", "need", "margin", "state"}, "energy": {... + "detail" (energy())},
##  "data", "comms", "budget" (+ "client_budget", "over_client"), "time" (+ "deadline"),
##  "blocked": [gauge ids in red that block], "ok": bool}
## `plan`: {"type", "target", "payload", "weeks", "dev_cost", "launch_cost", "budget" (client,
## 0 = none), "deadline_weeks" (weeks left, -1 = none), "briefing_id" (its story may tell the environment)}.
static func gauges(state: TycoonState, plan: Dictionary) -> Dictionary:
	var type_id := String(plan.get("type", ""))
	var target_id := String(plan.get("target", ""))
	var payload: Array = plan.get("payload", [])
	var out := {}
	var allow := mass_allowance(state, type_id)
	var mass := _sum(payload, "mass")
	out["mass"] = _gauge(mass, allow, 1.0 - mass / maxf(allow, 0.001))
	var en := energy(state, type_id, payload, env(state, target_id, false, String(plan.get("briefing_id", ""))))
	var eg := _gauge(en["day_gen"], en["use"], float(en["margin"]))
	eg["detail"] = en
	out["energy"] = eg
	var gen := data_rate(payload)
	var stor := storage(state, type_id, payload)
	var sw := float(section("bus").get("storage_weeks", 1.5))
	out["data"] = _gauge(stor, gen * sw, stor / maxf(gen * sw, 0.001) - 1.0 if gen > 0.0 else 1.0)
	var down := downlink(state, type_id, target_id, payload)
	out["comms"] = _gauge(down, gen, down / maxf(gen, 0.001) - 1.0 if gen > 0.0 else (1.0 if antenna(payload) != "" else -1.0))
	var total := float(plan.get("dev_cost", 0.0)) + float(plan.get("launch_cost", 0.0)) + cost(payload)
	var bg := _gauge(total, state.cash, state.cash / maxf(total, 0.001) - 1.0)
	var client := float(plan.get("budget", 0.0))
	bg["client_budget"] = client
	bg["over_client"] = client > 0.0 and total > client
	if bg["over_client"] and String(bg["state"]) == "green":
		bg["state"] = "yellow"
	out["budget"] = bg
	var dl := int(plan.get("deadline_weeks", -1))
	var wk := int(plan.get("weeks", 0))
	var tg := _gauge(wk, dl, 1.0 if dl < 0 else float(dl - wk) / maxf(dl, 1.0))
	tg["deadline"] = dl
	out["time"] = tg
	var blocked: Array[String] = []
	for g: String in section("gauges").get("blocking", []):
		# energy blocks only by day: a short night or the cold is a warning (the mission lives
		# shorter), so a target never closes before its night-proof power is researched
		var st := String(out[g]["state"]) if g != "energy" else state_of(float(en["day_margin"]))
		if st == "red":
			blocked.append(g)
	out["blocked"] = blocked
	out["ok"] = blocked.is_empty() and not payload.is_empty()
	return out


static func _gauge(have: float, need: float, margin: float) -> Dictionary:
	return {"have": have, "need": need, "margin": margin, "state": state_of(margin)}


## Why a plan cannot go ahead ("" when it can): a translation key. `check_budget` off leaves
## the money to the caller (ProjectDesk.start_error says TY_PJ_ERR_CASH itself).
static func plan_error(state: TycoonState, plan: Dictionary, check_budget := true) -> String:
	var payload: Array = plan.get("payload", [])
	for id in payload:
		if not is_available(state, String(id)):
			return "TY_PL_ERR_LOCKED"
	if instruments(payload).is_empty() and float(type_rules(String(plan.get("type", ""))).get("instr_weight", 1.0)) >= 0.5:
		return "TY_PL_ERR_NO_INSTRUMENT"
	var g := gauges(state, plan)
	var blocked: Array = g["blocked"]
	if "mass" in blocked:
		return "TY_PL_ERR_MASS"
	if "energy" in blocked:
		return "TY_PL_ERR_ENERGY"
	if "budget" in blocked and check_budget:
		return "TY_PL_ERR_CASH"
	return ""


## Toggles a module in a payload (an antenna replaces the other antenna). Returns the new list.
static func toggle(payload: Array, id: String) -> Array[String]:
	var out: Array[String] = []
	for x in payload:
		out.append(String(x))
	if id in out:
		out.erase(id)
		return out
	var grp := String(module(id).get("group", ""))
	if grp != "":
		for x in out.duplicate():
			if String(module(x).get("group", "")) == grp:
				out.erase(x)
	out.append(id)
	return out


## The Cometlings' starter payload for a type at a target: the cheapest working kit with what
## research has unlocked (best antenna, a power source that covers the day, a battery, one
## generic instrument: the sensor pack or the camera). It does not know the hidden ideals.
static func default_payload(state: TycoonState, type_id: String, target_id: String) -> Array[String]:
	var out: Array[String] = []
	var tr := type_rules(type_id)
	if float(tr.get("instr_weight", 1.0)) >= 0.5:
		out.append("camera" if is_available(state, "camera") and target_id != "suborbital" else "sensor_pack")
	var needs: Array = tr.get("needs_antenna", [])
	var ant := ""
	for id in (["hga", "reflector", "omni", "beacon"] if not needs.is_empty() else ["omni", "beacon"]):
		if is_available(state, id):
			ant = id
			break
	if ant != "":
		out.append(ant)
	out.append("battery")
	var e := env(state, target_id)
	var green := float(section("gauges").get("green", 0.2))
	var battery_only: bool = type_id in section("bus").get("battery_only", [])
	if not battery_only:
		var best := ""
		for gen in ["solar_body", "solar_wing", "rtg"]:
			if not is_available(state, gen):
				continue
			best = gen
			var trial := out.duplicate()
			trial.append(gen)
			if float(energy(state, type_id, trial, e)["day_margin"]) >= green:
				break
		if best != "":
			out.append(best)
	if not energy(state, type_id, out, e)["cold_ok"] and is_available(state, "heater"):
		out.append("heater")
	var yellow := float(section("gauges").get("yellow", 0.05))
	var en := energy(state, type_id, out, e)
	if (float(en["day_margin"]) < green or float(en["night_margin"]) < green) and is_available(state, "battery_l"):
		out.append("battery_l")
	if float(energy(state, type_id, out, e)["night_margin"]) < yellow and is_available(state, "rtg") and not "rtg" in out:
		out.append("rtg")
	return out
