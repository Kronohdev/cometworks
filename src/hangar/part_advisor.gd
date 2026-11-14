class_name PartAdvisor
extends RefCounted
## Part advisor of the hangar: pure rules over the vessel's stage specs (the same
## {"core": [part dicts], "boosters": [[part dicts]]} list Vessel.compute_stages() gives
## VesselMath), so it runs headless with no scene. Given the vessel, an optional mission
## goal and the part the player is working with (the "focus": held or last placed), it says
##   advise()    -> which parts to add next, each with a short reason (translation key + args)
##                  and a placement hint the hangar uses for one-click add
##   problems()  -> what is wrong with the vessel, in plain language (key + args + tone)
##   engine_fit() / matching_props() -> which engines burn what the tanks carry (palette dims
##                  the others)
##
## Goal: {"dv_needed": float m/s, "payload_kg": float, "budget_musd": float, "crewed": bool}
## (FlightSession.mission, or free_goal() in the free workshop).
##
## Placement hints (read by the hangar's quick_add):
##   "root"               the first part of an empty vessel
##   "top" / "bottom"     the free top node of the highest part / bottom node of the lowest
##   "below_tank:<prop>"  the free bottom node of the lowest tank carrying <prop>
##   "above_engine:<id>"  between the engine <id> and the part it hangs from
##   "hand"               no obvious spot: the part goes to the player's hand

## Low Earth orbit (ascent Δv, m/s): the free workshop's training goal.
const LEO_DV := 9400.0
const TWR_MIN := 1.0
const TWR_GOOD := 1.2
const MAX_ITEMS := 6
const SIZE_ORDER: Array[String] = ["XS", "S", "M", "L"]

enum Tone { OK, INFO, WARN, DANGER }


## Goal of the free workshop: reach low orbit.
static func free_goal() -> Dictionary:
	return {"dv_needed": LEO_DV, "payload_kg": 0.0, "budget_musd": 0.0, "crewed": false, "free": true}


# ------------------------------------------------------------ catalog queries
static func _size_index(s: String) -> int:
	var i := SIZE_ORDER.find(s)
	return 1 if i < 0 else i


static func _size_dist(a: String, b: String) -> int:
	return absi(_size_index(a) - _size_index(b))


static func is_liquid_engine(p: Dictionary) -> bool:
	return PartDB.is_engine(p) and p.get("propellant", "") not in ["", "solid"]


static func is_tank(p: Dictionary) -> bool:
	return p.get("category", "") == "tank"


static func is_crewed(p: Dictionary) -> bool:
	return int(p.get("crew_seats", 0)) > 0 and PartDB.is_command(p)


## Engines that burn `prop`, best first: closest size to `size`, then (with `sea_level`)
## the ones that work at the pad, then the strongest.
static func engines_for(prop: String, size: String, sea_level := true) -> Array[String]:
	PartDB._ensure()
	var ids: Array[String] = []
	for id in PartDB.part_order:
		var p: Dictionary = PartDB.parts[id]
		if PartDB.is_engine(p) and p.get("propellant", "") == prop:
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa := PartDB.get_part(a)
		var pb := PartDB.get_part(b)
		if sea_level:
			var sa := float(pa.get("thrust_sl_kn", 0.0)) > 0.0
			var sb := float(pb.get("thrust_sl_kn", 0.0)) > 0.0
			if sa != sb:
				return sa
		var da := _size_dist(pa.get("size", ""), size)
		var db := _size_dist(pb.get("size", ""), size)
		if da != db:
			return da < db
		var ka := "thrust_sl_kn" if sea_level else "isp_vac_s"
		return float(pa.get(ka, 0.0)) > float(pb.get(ka, 0.0)))
	return ids


## Tanks of `prop`, closest size to `size` first, smaller loads first.
static func tanks_for(prop: String, size: String) -> Array[String]:
	PartDB._ensure()
	var ids: Array[String] = []
	for id in PartDB.part_order:
		var p: Dictionary = PartDB.parts[id]
		if is_tank(p) and p.get("propellant", "") == prop:
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa := PartDB.get_part(a)
		var pb := PartDB.get_part(b)
		var da := _size_dist(pa.get("size", ""), size)
		var db := _size_dist(pb.get("size", ""), size)
		if da != db:
			return da < db
		return float(pa.get("prop_mass_kg", 0.0)) < float(pb.get("prop_mass_kg", 0.0)))
	return ids


## A middle-sized tank of `prop` at `size` (not the stubby one, not the giant).
static func tank_for(prop: String, size: String) -> String:
	var same: Array[String] = []
	for id in tanks_for(prop, size):
		if PartDB.get_part(id).get("size", "") == size:
			same.append(id)
	if same.is_empty():
		var any := tanks_for(prop, size)
		return "" if any.is_empty() else any[0]
	return same[mini(1, same.size() - 1)]


## The next bigger tank of `prop` than `than_kg` (closest size first), or "".
static func bigger_tank(prop: String, size: String, than_kg: float) -> String:
	var best := ""
	var best_kg := INF
	for id in tanks_for(prop, size):
		var p := PartDB.get_part(id)
		var kg := float(p.get("prop_mass_kg", 0.0))
		if kg > than_kg * 1.05 and _size_dist(p.get("size", ""), size) <= 1 and kg < best_kg:
			best = id
			best_kg = kg
	return best


## Flight computer for a stack of `size` (crewed: a capsule with seats).
static func core_for(size: String, crewed := false) -> String:
	PartDB._ensure()
	var best := ""
	var best_d := 99
	for id in PartDB.part_order:
		var p: Dictionary = PartDB.parts[id]
		if p.get("category", "") != "command":
			continue
		if crewed != is_crewed(p):
			continue
		var d := _size_dist(p.get("size", ""), size)
		if d < best_d:
			best = id
			best_d = d
	return best


## A catalog part of `prefix` family (fairing_, nose_cone_, decoupler_) closest to `size`.
static func sized_part(prefix: String, size: String, exclude := "") -> String:
	PartDB._ensure()
	var best := ""
	var best_d := 99
	for id in PartDB.part_order:
		if not id.begins_with(prefix) or (exclude != "" and id.contains(exclude)):
			continue
		var d := _size_dist(PartDB.parts[id].get("size", ""), size)
		if d < best_d:
			best = id
			best_d = d
	return best


# ------------------------------------------------------------ vessel queries
static func _groups(spec: Dictionary) -> Array:
	var out: Array = [spec.get("core", [])]
	out.append_array(spec.get("boosters", []))
	return out


static func all_parts(specs: Array) -> Array:
	var out: Array = []
	for s in specs:
		for g in _groups(s):
			out.append_array(g)
	return out


## Liquid propellant -> kg carried by the tanks of a group of parts.
static func group_props(group: Array) -> Dictionary:
	var out := {}
	for p in group:
		if is_tank(p):
			var k: String = p.get("propellant", "")
			out[k] = float(out.get(k, 0.0)) + float(p.get("prop_mass_kg", 0.0))
	return out


static func _main_prop(props: Dictionary) -> String:
	var best := ""
	var best_kg := -1.0
	for k in props:
		if float(props[k]) > best_kg:
			best = k
			best_kg = props[k]
	return best


## Size class of a stack of parts: its biggest tank, else its biggest part.
static func main_size(parts: Array) -> String:
	var best := -1
	var tank_best := -1
	for p in parts:
		var s: String = p.get("size", "")
		if not SIZE_ORDER.has(s):
			continue
		best = maxi(best, _size_index(s))
		if is_tank(p):
			tank_best = maxi(tank_best, _size_index(s))
	var i := tank_best if tank_best >= 0 else best
	return "S" if i < 0 else SIZE_ORDER[i]


static func _has(parts: Array, f: Callable) -> bool:
	for p in parts:
		if f.call(p):
			return true
	return false


## Liquid propellants carried anywhere on the vessel, plus the focus tank's.
static func matching_props(specs: Array, focus_id := "") -> Dictionary:
	var out := group_props(all_parts(specs))
	var f := PartDB.get_part(focus_id)
	if is_tank(f):
		out[f.get("propellant", "")] = float(out.get(f.get("propellant", ""), 0.0)) + float(f.get("prop_mass_kg", 0.0))
	return out


## 1 = the engine burns what the vessel's tanks carry, -1 = the vessel has tanks and none
## carries its propellant (it would sit dry), 0 = nothing to say (solid, no tanks, not an engine).
static func engine_fit(engine_id: String, specs: Array, focus_id := "") -> int:
	var e := PartDB.get_part(engine_id)
	if not is_liquid_engine(e):
		return 0
	var props := matching_props(specs, focus_id)
	if props.is_empty():
		return 0
	return 1 if props.has(e.get("propellant", "")) else -1


## Parts that go well with the vessel, for browsing: the flight computers on an empty pad,
## else the engines that burn its propellants and more tanks of them at its size, then the
## staging parts and a nose of its size.
static func compatible(specs: Array, focus_id := "", limit := 10) -> Array[String]:
	var out: Array[String] = []
	var parts := all_parts(specs)
	if parts.is_empty() and focus_id == "":
		for id in PartDB.parts_in_category("command"):
			out.append(id)
		return out.slice(0, limit)
	var with_focus := parts.duplicate()
	if not PartDB.get_part(focus_id).is_empty():
		with_focus.append(PartDB.get_part(focus_id))
	var size := main_size(with_focus)
	var props := matching_props(specs, focus_id)
	var order := props.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return float(props[a]) > float(props[b]))
	for prop in order:
		for id in engines_for(prop, size, specs.size() <= 1).slice(0, 3):
			if not out.has(id):
				out.append(id)
		for id in tanks_for(prop, size).slice(0, 3):
			if not out.has(id):
				out.append(id)
	for p in parts:
		if is_liquid_engine(p) and not props.has(p.get("propellant", "")):
			for id in tanks_for(p.get("propellant", ""), p.get("size", size)).slice(0, 2):
				if not out.has(id):
					out.append(id)
	for id in [sized_part("decoupler_", size, "clamp"), sized_part("nose_cone_", size), sized_part("fairing_", size, "long")]:
		if id != "" and not out.has(id):
			out.append(id)
	return out.slice(0, limit)


static func prop_name(prop: String) -> String:
	PartDB._ensure()
	return PartDB.loc(PartDB.propellants.get(prop, {}).get("name", prop))


## Ascent figures with the goal's payload on top (VesselMath.analyze).
static func evaluate(specs: Array, goal := {}, fairing_kg := 0.0) -> Dictionary:
	return VesselMath.analyze(specs, float(goal.get("payload_kg", 0.0)), fairing_kg, 2)


static func _stage_thrust_sl(spec: Dictionary) -> float:
	var f := 0.0
	for g in _groups(spec):
		var props := group_props(g)
		for p in g:
			if PartDB.is_engine(p) and (p.get("propellant", "") == "solid" or props.has(p.get("propellant", ""))):
				f += float(p.get("thrust_sl_kn", 0.0))
	return f


## True when some engine of the stage has something to burn (its own solid grain or a tank).
static func _stage_fueled(spec: Dictionary) -> bool:
	for g in _groups(spec):
		var props := group_props(g)
		for p in g:
			if PartDB.is_engine(p) and (p.get("propellant", "") == "solid" or props.has(p.get("propellant", ""))):
				return true
	return false


static func _has_engine(spec: Dictionary) -> bool:
	for g in _groups(spec):
		if _has(g, func(p: Dictionary) -> bool: return PartDB.is_engine(p)):
			return true
	return false


# ------------------------------------------------------------ advice
## Recommended parts, best first: [{"id", "reason" (translation key), "args": Array,
## "hint" (placement, see above), "score": int}]. `ctx`: {"focus": part id, "stable": int
## (Vessel.stability), "fairing_kg": float, "analysis": Dictionary (else computed)}.
static func advise(specs: Array, goal := {}, ctx := {}) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var parts := all_parts(specs)
	var crewed := bool(goal.get("crewed", false))
	if parts.is_empty():
		var first := core_for("S", crewed)
		_add(items, first, "ADV_START_CREW" if crewed else "ADV_START", [], "root", 100)
		return items
	var size := main_size(parts)
	var focus_id: String = ctx.get("focus", "")
	var focus := PartDB.get_part(focus_id)
	var a: Dictionary = ctx.get("analysis", {})
	if a.is_empty():
		a = evaluate(specs, goal, float(ctx.get("fairing_kg", 0.0)))

	# a brain (and seats when the mission flies people)
	if crewed and not _has(parts, func(p: Dictionary) -> bool: return is_crewed(p)):
		_add(items, core_for(size, true), "ADV_CREW", [], "top", 95)
	elif not _has(parts, func(p: Dictionary) -> bool: return PartDB.is_command(p)):
		_add(items, core_for(size), "ADV_NO_CORE", [], "top", 90)

	# fuel and engines that belong together, group by group
	for si in specs.size():
		for g in _groups(specs[si]):
			var props := group_props(g)
			var burns := {}
			for p in g:
				if is_liquid_engine(p):
					burns[p.get("propellant", "")] = true
			for p in g:
				if is_liquid_engine(p) and not props.has(p.get("propellant", "")):
					var prop: String = p.get("propellant", "")
					_add(items, tank_for(prop, p.get("size", size)), "ADV_TANK_FOR",
						[prop_name(prop), PartDB.loc(p.get("name", ""))], "above_engine:" + String(p.get("id", "")), 88)
			for prop in props:
				if burns.has(prop):
					continue
				var tsize := main_size(g)
				var e := engines_for(prop, tsize, si == 0)
				for k in mini(2, e.size()):
					_add(items, e[k], "ADV_ENGINE_FOR", [prop_name(prop)], "below_tank:" + prop, 86 - k)

	# the tank in the player's hands asks for its engine
	if is_tank(focus):
		var fprop: String = focus.get("propellant", "")
		var burned := _has(parts, func(p: Dictionary) -> bool: return is_liquid_engine(p) and p.get("propellant", "") == fprop)
		if not burned:
			var e := engines_for(fprop, focus.get("size", size), specs.size() <= 1)
			for k in mini(2, e.size()):
				_add(items, e[k], "ADV_ENGINE_FOR", [prop_name(fprop)], "below_tank:" + fprop, 84 - k)
	elif is_liquid_engine(focus):
		var eprop: String = focus.get("propellant", "")
		if not group_props(parts).has(eprop):
			_add(items, tank_for(eprop, focus.get("size", size)), "ADV_TANK_FOR",
				[prop_name(eprop), PartDB.loc(focus.get("name", ""))], "above_engine:" + focus_id, 84)

	if specs.is_empty():
		return _finish(items)
	var s0: Dictionary = specs[0]
	var s0_parts: Array = []
	for g in _groups(s0):
		s0_parts.append_array(g)
	var s0_props := group_props(s0_parts)
	var s0_prop := _main_prop(s0_props)
	if s0_prop == "":
		s0_prop = _main_prop(group_props(parts))

	# the first stage must have something to burn
	if not _has_engine(s0):
		if s0_props.is_empty():
			var prop := s0_prop if s0_prop != "" else "kerolox"
			_add(items, tank_for(prop, main_size(s0_parts) if not s0_parts.is_empty() else size),
				"ADV_FIRST_STAGE", [], "bottom", 75)
	else:
		var stages: Array = a.get("stages", [])
		var twr := float(a.get("liftoff_twr", 0.0))
		var thrust := _stage_thrust_sl(s0)
		if thrust <= 0.0 and s0_prop != "":
			# vacuum engines do not push at the pad
			var e := engines_for(s0_prop, main_size(s0_parts), true)
			if not e.is_empty():
				_add(items, e[0], "ADV_SL_ENGINE", [], "hand", 80)
		elif thrust > 0.0 and not stages.is_empty() and twr < TWR_MIN:
			var need_kn := float(stages[0]["m0_kg"]) * PartDB.G0 * TWR_GOOD / 1000.0
			var pick := _engine_with_thrust(s0_prop, need_kn) if s0_prop != "" else ""
			if pick != "":
				_add(items, pick, "ADV_MORE_THRUST", [twr], "hand", 78)
			var srb := _engine_with_thrust("solid", (need_kn - thrust) * 0.5)
			if srb != "":
				_add(items, srb, "ADV_BOOSTERS", [], "hand", 74)
				_add(items, "decoupler_radial", "ADV_BOOSTER_MOUNT", [], "hand", 73)

	# reach: Δv short of the goal
	var need := float(goal.get("dv_needed", 0.0))
	var dv := float(a.get("ascent_dv", 0.0))
	if need > 0.0 and dv < need and _has_engine(s0) and float(a.get("liftoff_twr", 0.0)) >= TWR_MIN:
		var short := need - dv
		if specs.size() <= 1:
			_add(items, sized_part("decoupler_", _bottom_size(s0_parts, size), "clamp"), "ADV_UPPER_STAGE",
				[short], "bottom", 70)
		var biggest := 0.0
		var eng_id := ""
		for p in s0_parts:
			if is_tank(p) and p.get("propellant", "") == s0_prop:
				biggest = maxf(biggest, float(p.get("prop_mass_kg", 0.0)))
			if is_liquid_engine(p) and p.get("propellant", "") == s0_prop and eng_id == "":
				eng_id = p.get("id", "")
		if s0_prop != "":
			var bt := bigger_tank(s0_prop, main_size(s0_parts), biggest)
			if bt != "":
				_add(items, bt, "ADV_MORE_TANK", [short], "above_engine:" + eng_id if eng_id != "" else "hand", 68)

	# a nose for the payload, fins when it tumbles
	var nosed := _has(parts, func(p: Dictionary) -> bool:
		return PartDB.is_fairing(p) or String(p.get("id", "")).begins_with("nose_cone"))
	var top_size := _top_size(specs, size)
	if not nosed:
		var cargo := float(goal.get("payload_kg", 0.0)) > 0.0 or _has(parts, func(p: Dictionary) -> bool:
			return p.get("category", "") in ["bus", "instrument"])
		if cargo:
			_add(items, sized_part("fairing_", top_size, "long"), "ADV_FAIRING", [], "top", 60)
		elif parts.size() >= 3 and _has(parts, func(p: Dictionary) -> bool: return PartDB.is_engine(p)) \
				and not crewed:
			_add(items, sized_part("nose_cone_", top_size), "ADV_NOSE", [], "top", 55)
	if int(ctx.get("stable", -1)) == 0:
		_add(items, "fin_basic", "ADV_FINS", [], "hand", 50)
	return _finish(items)


static func _bottom_size(parts: Array, fallback: String) -> String:
	for p in parts:
		if PartDB.is_engine(p):
			return p.get("size", fallback)
	return fallback


## Size of the top of the stack: the last stage's biggest part.
static func _top_size(specs: Array, fallback: String) -> String:
	if specs.is_empty():
		return fallback
	var top: Array = specs[specs.size() - 1].get("core", [])
	return main_size(top) if not top.is_empty() else fallback


## The weakest engine of `prop` that alone gives `kn` at the pad (else the strongest).
static func _engine_with_thrust(prop: String, kn: float) -> String:
	PartDB._ensure()
	var best := ""
	var best_f := INF
	var strongest := ""
	var strongest_f := 0.0
	for id in PartDB.part_order:
		var p: Dictionary = PartDB.parts[id]
		if not PartDB.is_engine(p) or p.get("propellant", "") != prop:
			continue
		var f := float(p.get("thrust_sl_kn", 0.0))
		if f <= 0.0:
			continue
		if f >= kn and f < best_f:
			best = id
			best_f = f
		if f > strongest_f:
			strongest = id
			strongest_f = f
	return best if best != "" else strongest


static func _add(items: Array[Dictionary], id: String, reason: String, args: Array, hint: String, score: int) -> void:
	if id == "" or PartDB.get_part(id).is_empty():
		return
	for it in items:
		if it["id"] == id:
			if score > int(it["score"]):
				it["reason"] = reason
				it["args"] = args
				it["hint"] = hint
				it["score"] = score
			return
	items.append({"id": id, "reason": reason, "args": args, "hint": hint, "score": score})


static func _finish(items: Array[Dictionary]) -> Array[Dictionary]:
	items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["score"]) > int(y["score"]))
	if items.size() > MAX_ITEMS:
		items.resize(MAX_ITEMS)
	return items


## Translated reason line of an advice item.
static func reason_text(item: Dictionary) -> String:
	var t := TranslationServer.translate(item.get("reason", ""))
	var args: Array = item.get("args", [])
	if args.is_empty():
		return t
	var fmt: Array = []
	for v in args:
		fmt.append(HangarFormat.numk(v) if v is float and absf(v) >= 10.0 else (HangarFormat.num(v, 2) if v is float else v))
	return t % fmt


# ------------------------------------------------------------ problems
## Plain-language problems of the vessel, worst first: [{"key", "args", "tone": Tone}].
## `ctx`: {"stable": int, "cost": float (US$ M), "analysis": Dictionary, "fairing_kg"}.
static func problems(specs: Array, goal := {}, ctx := {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parts := all_parts(specs)
	if parts.is_empty():
		return out
	var a: Dictionary = ctx.get("analysis", {})
	if a.is_empty():
		a = evaluate(specs, goal, float(ctx.get("fairing_kg", 0.0)))
	if not _has(parts, func(p: Dictionary) -> bool: return PartDB.is_command(p)):
		out.append({"key": "ADV_P_NO_CORE", "args": [], "tone": Tone.DANGER})
	if bool(goal.get("crewed", false)) and not _has(parts, func(p: Dictionary) -> bool: return is_crewed(p)):
		out.append({"key": "ADV_P_NO_CREW", "args": [], "tone": Tone.DANGER})
	for s in specs:
		for g in _groups(s):
			var props := group_props(g)
			for p in g:
				if not is_liquid_engine(p) or props.has(p.get("propellant", "")):
					continue
				var ename := PartDB.loc(p.get("name", ""))
				if props.is_empty():
					out.append({"key": "ADV_P_NO_FUEL", "args": [ename, prop_name(p.get("propellant", ""))], "tone": Tone.DANGER})
				else:
					out.append({"key": "ADV_P_MISMATCH", "args": [ename, prop_name(p.get("propellant", "")),
						prop_name(_main_prop(props))], "tone": Tone.DANGER})
	if not specs.is_empty() and not _has_engine(specs[0]):
		out.append({"key": "ADV_P_NO_ENGINE", "args": [], "tone": Tone.DANGER})
	elif _stage_fueled(specs[0]) and not (a.get("stages", []) as Array).is_empty():
		var twr := float(a.get("liftoff_twr", 0.0)) if _stage_thrust_sl(specs[0]) > 0.0 else 0.0
		if twr < TWR_MIN:
			out.append({"key": "ADV_P_TWR_LOW", "args": [twr], "tone": Tone.DANGER})
		elif twr < TWR_GOOD:
			out.append({"key": "ADV_P_TWR_MARGINAL", "args": [twr], "tone": Tone.WARN})
	var need := float(goal.get("dv_needed", 0.0))
	var dv := float(a.get("ascent_dv", 0.0))
	if need > 0.0 and dv < need:
		out.append({"key": "ADV_P_DV_SHORT", "args": [need - dv], "tone": Tone.WARN})
	var budget := float(goal.get("budget_musd", 0.0))
	var cost := float(ctx.get("cost", 0.0))
	if budget > 0.0 and cost > budget:
		out.append({"key": "ADV_P_OVER_BUDGET", "args": [cost - budget], "tone": Tone.DANGER})
	if int(ctx.get("stable", -1)) == 0:
		out.append({"key": "ADV_P_UNSTABLE", "args": [], "tone": Tone.WARN})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["tone"]) > int(y["tone"]))
	return out


## Translated problem line.
static func problem_text(pr: Dictionary) -> String:
	return reason_text({"reason": pr.get("key", ""), "args": pr.get("args", [])})
