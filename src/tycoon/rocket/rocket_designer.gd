class_name RocketDesigner
extends RefCounted
## The tycoon rocket designer (GDD 8.2, roadmap E2): a rocket is one component per slot
## (main stage, upper stage, tanks, side boosters, fairing, avionics, recovery), each with a
## cost, a reliability, a delta-v / lift contribution and build weeks, all in
## data/tycoon/rockets.json. Components come from the research tree (research.json
## unlocks.rockets; components no tech lists are there from the start).
##
## A design is a Dictionary slot -> component id ("parts"). This class turns parts into numbers
## (stats), checks them against a mission (check: "pode chegar / não chega"), and proposes the
## three designs of the automatic designer (Barata, Equilibrada, Robusta). Rocket families and
## their flight heritage live in RocketFamilies; the launch risks in DesignReview.
## Pure rules, no scene access.

const PATH := "res://data/tycoon/rockets.json"
const RESEARCH_PATH := "res://data/tycoon/research.json"

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}
static var _tech_of: Dictionary = {}
static var _proposal_cache: Dictionary = {}


# ------------------------------------------------------------ data
static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(PATH)
		for c: Dictionary in _data.get("components", []):
			_by_id[String(c["id"])] = c
		var rd := TycoonState.load_json(RESEARCH_PATH)
		for t: Dictionary in rd.get("techs", []):
			for x in t.get("unlocks", {}).get("rockets", []):
				_tech_of[String(x)] = String(t["id"])
	return _data


static func section(name: String) -> Dictionary:
	var v: Variant = data().get(name, {})
	return v if v is Dictionary else {}


static func slots() -> Array:
	return data().get("slots", [])


static func slot_ids() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in slots():
		out.append(String(s["id"]))
	return out


static func slot(id: String) -> Dictionary:
	for s: Dictionary in slots():
		if String(s["id"]) == id:
			return s
	return {}


static func component(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


## Every component of a slot, in data order.
static func components(slot_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in data().get("components", []):
		if String(c["slot"]) == slot_id:
			out.append(c)
	return out


## The tech that unlocks a component, "" for the starting ones.
static func tech_for(id: String) -> String:
	data()
	return String(_tech_of.get(id, ""))


static func available(state: TycoonState, id: String) -> bool:
	var t := tech_for(id)
	return t == "" or bool(state.unlocked.get("rocket:" + id, false)) or TycoonResearch.is_done(state, t)


## The components of a slot the agency can use now.
static func options(state: TycoonState, slot_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in components(slot_id):
		if available(state, String(c["id"])):
			out.append(c)
	return out


## Can the agency build these parts now (every component unlocked)?
static func buildable(state: TycoonState, parts: Dictionary) -> bool:
	var p := normalize(parts)
	for sid in slot_ids():
		if not available(state, String(p[sid])):
			return false
	return true


static func locked_count(state: TycoonState, slot_id: String) -> int:
	return components(slot_id).size() - options(state, slot_id).size()


## Every slot filled: missing or unknown slots take the slot's first component.
static func normalize(parts: Dictionary) -> Dictionary:
	var out := {}
	for sid in slot_ids():
		var id := String(parts.get(sid, ""))
		var c := component(id)
		if c.is_empty() or String(c["slot"]) != sid:
			var all := components(sid)
			id = String(all[0]["id"]) if not all.is_empty() else ""
		out[sid] = id
	return out


static func same_parts(a: Dictionary, b: Dictionary) -> bool:
	var na := normalize(a)
	var nb := normalize(b)
	for sid in slot_ids():
		if String(na[sid]) != String(nb[sid]):
			return false
	return true


static func _num(c: Dictionary, key: String, fallback: float) -> float:
	return float(c.get(key, fallback))


# ------------------------------------------------------------ stats
## The numbers of a design: {"dv" km/s, "lift" t, "max_size", "cost" (one new unit, no
## discounts), "weeks" (a first build), "rel" (hardware reliability, product of the
## components), "class", "refund" (cr back after a good flight), "boosters" (count),
## "booster_size", "height" (relative stack height), "model" (era model 1..5)}.
static func stats(parts: Dictionary) -> Dictionary:
	var p := normalize(parts)
	var core := component(String(p["core"]))
	var upper := component(String(p["upper"]))
	var tank := component(String(p["tank"]))
	var boost := component(String(p["boosters"]))
	var fairing := component(String(p["fairing"]))
	var av := component(String(p["avionics"]))
	var rec := component(String(p["recovery"]))
	var dv := (_num(core, "dv", 0.0) + _num(upper, "dv", 0.0)) * _num(tank, "dv_mult", 1.0) + _num(boost, "dv", 0.0)
	var lift := _num(core, "lift", 0.0) * _num(tank, "lift_mult", 1.0) * _num(boost, "lift_mult", 1.0) \
		* _num(rec, "lift_mult", 1.0) * _num(upper, "lift_mult", 1.0)
	var stack := (_num(core, "cost", 0.0) + _num(upper, "cost", 0.0)) * _num(tank, "cost_mult", 1.0)
	var cost := stack * (1.0 + _num(boost, "cost_mult", 0.0)) + _num(fairing, "cost", 0.0) + _num(av, "cost", 0.0) \
		+ _num(rec, "cost", 0.0)
	var weeks := 0
	var rel := 1.0
	for c: Dictionary in [core, upper, tank, boost, fairing, av, rec]:
		weeks += int(c.get("weeks", 0))
		rel *= _num(c, "rel", 1.0)
	return {"dv": dv, "lift": lift, "max_size": _num(fairing, "max_size", 0.6), "cost": cost, "weeks": maxi(weeks, 1),
		"rel": rel, "class": class_of(lift), "refund": _num(rec, "refund", 0.0) * _num(core, "cost", 0.0),
		"boosters": int(boost.get("count", 0)), "booster_size": _num(boost, "size", 0.3),
		"height": _num(tank, "height", 1.0) + _num(upper, "height", 0.0), "model": int(core.get("model", 1))}


## Launch class of a lift (rockets.json classes): sounding, light, medium, heavy, lunar.
static func class_of(lift: float) -> String:
	var last := "light"
	for c: Dictionary in data().get("classes", []):
		last = String(c["id"])
		if lift < float(c.get("max_lift", 0.0)):
			return last
	return last


## What a mission asks of its rocket: {"dv" km/s for the target, "lift" t of the type's
## payload, "size" (the type's size, the fairing must hold it)}.
static func need(state: TycoonState, type_id: String, target_id: String) -> Dictionary:
	var mt := state.mission_type(type_id)
	return {"dv": float(section("targets").get(target_id, 9.4)),
		"lift": float(section("payload_t").get(type_id, float(mt.get("size", 1.0)))),
		"size": float(mt.get("size", 1.0))}


## "green" | "yellow" | "red" for a margin (have / need - 1).
static func meter_state(margin: float, green: float) -> String:
	if margin < 0.0:
		return "red"
	return "green" if margin >= green - 1e-6 else "yellow"


## The chance a thin margin costs the flight: risk_max at margin 0, 0 at the green margin.
static func margin_risk(kind: String, margin: float) -> float:
	var m := section("margins").get(kind, {}) as Dictionary
	var green := float(m.get("green", 0.1))
	if margin < 0.0:
		return 1.0
	if margin >= green:
		return 0.0
	return float(m.get("risk_max", 0.1)) * (1.0 - margin / maxf(green, 0.0001))


## The requirement check of a design for a mission: {"dv": meter, "lift": meter, "size": meter,
## "reaches": bool, "stats"}; a meter is {"have", "need", "margin", "state"}.
static func check(state: TycoonState, parts: Dictionary, type_id: String, target_id: String) -> Dictionary:
	var st := stats(parts)
	var nd := need(state, type_id, target_id)
	var mg := section("margins")
	var out := {"stats": st}
	for k in ["dv", "lift"]:
		var have := float(st[k])
		var want := maxf(float(nd[k]), 0.0001)
		var margin := have / want - 1.0
		out[k] = {"have": have, "need": float(nd[k]), "margin": margin,
			"state": meter_state(margin, float((mg.get(k, {}) as Dictionary).get("green", 0.1)))}
	var fits := float(st["max_size"]) >= float(nd["size"]) - 1e-6
	out["size"] = {"have": float(st["max_size"]), "need": float(nd["size"]),
		"margin": float(st["max_size"]) / maxf(float(nd["size"]), 0.0001) - 1.0, "state": "green" if fits else "red"}
	out["reaches"] = String(out["dv"]["state"]) != "red" and String(out["lift"]["state"]) != "red" and fits
	return out


## Quick check: can any rocket the agency builds now reach this mission? (The best part of
## each slot for delta-v, lift and fairing room; the parts' numbers all grow together, so this
## bound is what the best design gets.)
static func reachable(state: TycoonState, type_id: String, target_id: String) -> bool:
	var nd := need(state, type_id, target_id)
	var best := {}
	for sid in slot_ids():
		var bd := {"dv": 0.0, "dv_mult": 0.0, "lift": 0.0, "lift_mult": 0.0, "max_size": 0.0}
		for c in options(state, sid):
			for k in bd:
				bd[k] = maxf(float(bd[k]), _num(c, k, 1.0 if k.ends_with("_mult") else 0.0))
		best[sid] = bd
	var dv := (float(best["core"]["dv"]) + float(best["upper"]["dv"])) * float(best["tank"]["dv_mult"]) + float(best["boosters"]["dv"])
	var lift := float(best["core"]["lift"]) * float(best["tank"]["lift_mult"]) * float(best["boosters"]["lift_mult"]) \
		* float(best["recovery"]["lift_mult"])
	return dv >= float(nd["dv"]) and lift >= float(nd["lift"]) and float(best["fairing"]["max_size"]) >= float(nd["size"]) - 1e-6


# ------------------------------------------------------------ cost and weeks of a unit
static func factory_level(state: TycoonState) -> int:
	var best := 0
	for lot: String in state.buildings:
		if state.lot_kind(lot) == "factory":
			best = maxi(best, int(state.building(lot).get("level", 0)))
	return best


static func _factory(key: String, state: TycoonState) -> float:
	var arr: Array = section("factory").get(key, [1.0])
	return float(arr[clampi(factory_level(state), 0, arr.size() - 1)]) if not arr.is_empty() else 1.0


## What one unit of this design costs the agency now: the design's cost, less the family's
## repeat discount (cost_step per flight, down to cost_floor) and the factory's.
static func unit_cost(state: TycoonState, parts: Dictionary, flights := 0) -> float:
	var r := section("repeat")
	var rep := maxf(1.0 - float(r.get("cost_step", 0.04)) * flights, float(r.get("cost_floor", 0.8)))
	return roundf(float(stats(parts)["cost"]) * rep * _factory("cost_mult", state))


## Weeks to build one unit: the components' weeks, faster once the family has flown and with
## the factory.
static func build_weeks(state: TycoonState, parts: Dictionary, flights := 0) -> int:
	var w := float(stats(parts)["weeks"])
	if flights > 0:
		w *= float(section("repeat").get("weeks_mult", 0.6))
	return maxi(ceili(w * _factory("weeks_mult", state) - 0.001), 1)


# ------------------------------------------------------------ the automatic designer
## Every design the agency can build now (one available component per slot), with its stats.
static func all_designs(state: TycoonState, with_recovery := false) -> Array[Dictionary]:
	var lists: Array = []
	for sid in slot_ids():
		var opts := options(state, sid)
		if sid == "recovery" and not with_recovery:
			opts = opts.slice(0, 1)
		lists.append(opts)
	var out: Array[Dictionary] = []
	var ids := slot_ids()
	var idx: Array[int] = []
	idx.resize(ids.size())
	idx.fill(0)
	for l: Array in lists:
		if l.is_empty():
			return out
	while true:
		var parts := {}
		for i in ids.size():
			parts[ids[i]] = String((lists[i] as Array)[idx[i]]["id"])
		out.append(parts)
		var k := ids.size() - 1
		while k >= 0:
			idx[k] += 1
			if idx[k] < (lists[k] as Array).size():
				break
			idx[k] = 0
			k -= 1
		if k < 0:
			break
	return out


## The chance this design flies (hardware x the debut trust x thin margins): what the
## designer ranks proposals by.
static func flight_odds(state: TycoonState, parts: Dictionary, chk: Dictionary) -> float:
	var st: Dictionary = chk["stats"]
	return float(st["rel"]) * RocketFamilies.debut_trust(state, parts) \
		* (1.0 - margin_risk("dv", float(chk["dv"]["margin"]))) * (1.0 - margin_risk("lift", float(chk["lift"]["margin"])))


## The three proposals of the automatic designer (GDD 8.2) that reach the target:
## [{"kind": "cheap" | "balanced" | "robust", "parts", "check", "odds", "cost"}]; empty when no
## design the agency can build reaches it. Cheap: the lowest unit cost. Robust: the best odds.
## Balanced: the best odds - cost_weight * (cost / cheapest - 1), other than those two when it can.
static func proposals(state: TycoonState, type_id: String, target_id: String) -> Array[Dictionary]:
	var key := "%d|%s|%s|%d|%d|%d" % [state.get_instance_id(), type_id, target_id, state.unlocked.size(),
		factory_level(state), RocketFamilies.heritage_stamp(state)]
	if _proposal_cache.has(key):
		return (_proposal_cache[key] as Array[Dictionary]).duplicate(true)
	var out := _proposals(state, type_id, target_id)
	if _proposal_cache.size() > 64:
		_proposal_cache.clear()
	_proposal_cache[key] = out
	return out.duplicate(true)


static func _proposals(state: TycoonState, type_id: String, target_id: String) -> Array[Dictionary]:
	var ok: Array[Dictionary] = []
	for parts in all_designs(state):
		var chk := check(state, parts, type_id, target_id)
		if not chk["reaches"]:
			continue
		ok.append({"parts": parts, "check": chk, "odds": flight_odds(state, parts, chk), "cost": float(chk["stats"]["cost"])})
	if ok.is_empty():
		return []
	var cheap: Dictionary = ok[0]
	var robust: Dictionary = ok[0]
	for d in ok:
		if float(d["cost"]) < float(cheap["cost"]) - 0.5 or (absf(float(d["cost"]) - float(cheap["cost"])) <= 0.5 and float(d["odds"]) > float(cheap["odds"])):
			cheap = d
		if float(d["odds"]) > float(robust["odds"]) + 1e-9 or (absf(float(d["odds"]) - float(robust["odds"])) <= 1e-9 and float(d["cost"]) < float(robust["cost"])):
			robust = d
	var w := float(section("proposals").get("cost_weight", 0.05))
	# the best value; a design other than the cheap and the robust ones when there is one
	var balanced: Dictionary = {}
	var best := -INF
	for pass_n in 2:
		for d in ok:
			if pass_n == 0 and (same_parts(d["parts"], cheap["parts"]) or same_parts(d["parts"], robust["parts"])):
				continue
			var v := float(d["odds"]) - w * (float(d["cost"]) / maxf(float(cheap["cost"]), 1.0) - 1.0)
			if v > best + 1e-9:
				best = v
				balanced = d
		if not balanced.is_empty():
			break
	var out: Array[Dictionary] = []
	for pair: Array in [["cheap", cheap], ["balanced", balanced], ["robust", robust]]:
		var d: Dictionary = (pair[1] as Dictionary).duplicate()
		d["kind"] = pair[0]
		out.append(d)
	return out


## The rocket a project gets when none is chosen: the most reliable family that reaches the
## target, else the balanced proposal. {"parts", "family"} ({} when nothing reaches).
static func default_design(state: TycoonState, type_id: String, target_id: String) -> Dictionary:
	var fam := RocketFamilies.best_fitting(state, type_id, target_id)
	if not fam.is_empty():
		return {"parts": normalize(fam["parts"]), "family": String(fam["id"])}
	for pr in proposals(state, type_id, target_id):
		if String(pr["kind"]) == "balanced":
			return {"parts": pr["parts"], "family": ""}
	return {}
