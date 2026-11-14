class_name DesignReview
extends RefCounted
## The Design Review (GDD section 7, roadmap E2): the gate between the end of development and
## the launch. It lists the launch's risks, each a failure mode with a chance p:
##   stage1 / stage2 / boosters / fairing / avionics   1 - the component's reliability
##                                                      (the tanks count with the main stage)
##   debut      1 - the family's trust (flight heritage, RocketFamilies)
##   dv / lift  a thin delta-v or lift margin (RocketDesigner.margin_risk); a design that does
##              not reach blocks the launch (p = 1)
##   fairing_size  the payload does not fit the fairing (blocks)
##   payload    1 - p_payload of the project (GDD 6.6: reliability fraction and residual defects)
##   crew       crewed flights: the crew's courage (GDD 6.6)
## The launch succeeds with the product of (1 - p). Each fixable risk can be fixed (rockets.json
## review: fix_factor of its p for fix weeks and money; the payload fix is an extra readiness
## review that cuts the residual defects); the fixes run in parallel. A failed launch names its
## cause from these risks (pick_cause), so the result card and the papers can say what broke.
## Pure rules, headless; ProjectDesk asks it for the odds.

const ROCKET_KINDS: Array[String] = ["component", "debut", "margin"]


static func cfg() -> Dictionary:
	return RocketDesigner.section("review")


## Every risk of the project's launch, with these fixes applied (default: the project's own):
## [{"id", "kind" ("component" | "debut" | "margin" | "payload" | "crew"), "name_key",
## "cause_key", "fix_key" ("" when it cannot be fixed), "detail" (component id or text args),
## "p" (with the fixes), "p0" (without), "fixed", "fix_weeks", "fix_cost", "blocking",
## "severity" ("low" | "mid" | "high")}], most likely first (before fixes).
static func risks(state: TycoonState, p: MissionProject, fixes: Variant = null) -> Array[Dictionary]:
	var fx: Array = p.review_fixes if fixes == null else fixes
	var parts := RocketDesigner.normalize(p.rocket.get("parts", {}))
	var st := RocketDesigner.stats(parts)
	var r := cfg()
	var factor := float(r.get("fix_factor", 0.5))
	var unit := RocketDesigner.unit_cost(state, parts, RocketFamilies.flights(RocketFamilies.find(state, String(p.rocket.get("family", "")))))
	var out: Array[Dictionary] = []
	# the rocket's components
	var tank_rel := float(RocketDesigner.component(String(parts["tank"])).get("rel", 1.0))
	for sd: Dictionary in RocketDesigner.slots():
		var rk: Dictionary = sd.get("risk", {})
		if rk.is_empty():
			continue
		var cid := String(parts[String(sd["id"])])
		var c := RocketDesigner.component(cid)
		var rel := float(c.get("rel", 1.0))
		if String(sd["id"]) == "core":
			rel *= tank_rel
		var p0 := 1.0 - rel
		if p0 <= 1e-6:
			continue
		out.append(_risk(String(rk["id"]), "component", rk, cid, p0, factor, fx,
			int(rk.get("fix_weeks", 1)), _fix_cost(unit, float(rk.get("fix_cost_frac", 0.1)))))
	# the family's heritage
	var fam := RocketFamilies.find(state, String(p.rocket.get("family", "")))
	var tr_v := RocketFamilies.trust(fam) if not fam.is_empty() else RocketFamilies.debut_trust(state, parts)
	var hk: Dictionary = RocketFamilies.heritage().get("risk", {})
	if 1.0 - tr_v > 1e-6:
		out.append(_risk("debut", "debut", hk, String(fam.get("name", "")), 1.0 - tr_v, factor, fx,
			int(hk.get("fix_weeks", 2)), _fix_cost(unit, float(hk.get("fix_cost_frac", 0.15)))))
	# the requirement margins
	var chk := RocketDesigner.check(state, parts, p.type_id, p.target_id)
	var mg := RocketDesigner.section("margins")
	for k in ["dv", "lift"]:
		var m: Dictionary = chk[k]
		var pm := RocketDesigner.margin_risk(k, float(m["margin"]))
		if pm <= 1e-6:
			continue
		var e := _risk(k, "margin", mg.get(k, {}), "", pm, 1.0, [], 0, 0.0)
		e["blocking"] = String(m["state"]) == "red"
		e["detail"] = [float(m["have"]), float(m["need"])]
		out.append(e)
	if String(chk["size"]["state"]) == "red":
		var e := _risk("fairing_size", "margin", {"name_key": "TY_RK_RISK_SIZE", "cause_key": "TY_RK_CAUSE_SIZE"}, "",
			1.0, 1.0, [], 0, 0.0)
		e["blocking"] = true
		e["detail"] = [float(chk["size"]["have"]), float(chk["size"]["need"])]
		out.append(e)
	# the payload (the project's own reliability and defects)
	var pp := payload_chance(state, p, "payload" in fx)
	var pp0 := payload_chance(state, p, false)
	var pr := {"name_key": "TY_RK_RISK_PAYLOAD", "cause_key": "TY_RK_CAUSE_PAYLOAD", "fix_key": "TY_RK_FIX_PAYLOAD"}
	var pe := _risk("payload", "payload", pr, "", 1.0 - pp0, 1.0, [], int(r.get("payload_fix_weeks", 1)), 0.0)
	pe["fixed"] = "payload" in fx
	pe["p"] = 1.0 - pp
	var pfix := "payload" in fx
	pe["detail"] = [p.defects * (float(r.get("payload_fix_defects", 0.4)) if pfix else 1.0), roundi(rel_norm(state, p, pfix) * 100.0)]
	pe["severity"] = severity(float(pe["p"]))
	out.append(pe)
	# the crew
	var crew := crew_factor(state, p)
	if crew < 1.0 - 1e-6:
		out.append(_risk("crew", "crew", {"name_key": "TY_RK_RISK_CREW", "cause_key": "TY_RK_CAUSE_CREW"}, "",
			1.0 - crew, 1.0, [], 0, 0.0))
	# most likely first, before any fix (the rows keep their places while fixes are toggled)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["p0"]) > float(b["p0"]))
	return out


static func _risk(id: String, kind: String, def: Dictionary, detail: Variant, p0: float, factor: float, fixes: Array,
		weeks: int, cost: float) -> Dictionary:
	var fixable := String(def.get("fix_key", "")) != ""
	var fixed := fixable and id in fixes
	var pv := p0 * (factor if fixed else 1.0)
	return {"id": id, "kind": kind, "name_key": String(def.get("name_key", "")), "cause_key": String(def.get("cause_key", "")),
		"fix_key": String(def.get("fix_key", "")), "detail": detail, "p0": p0, "p": pv, "fixed": fixed,
		"fix_weeks": weeks if fixable else 0, "fix_cost": cost if fixable else 0.0, "blocking": false,
		"severity": severity(pv)}


static func _fix_cost(unit: float, frac: float) -> float:
	return roundf(maxf(unit * frac, float(cfg().get("fix_cost_min", 3000))) / 100.0) * 100.0


## "low" (green), "mid" (yellow) or "high" (red) for a risk's chance.
static func severity(pv: float) -> String:
	var r := cfg()
	if pv >= float(r.get("high", 0.05)):
		return "high"
	return "mid" if pv >= float(r.get("low", 0.02)) else "low"


## The project's reliability fraction against its ideal (0..1), plus the readiness fix.
static func rel_norm(state: TycoonState, p: MissionProject, fixed := false) -> float:
	var v := p.fractions()[ProjectRules.REL] / maxf(p.ideal(state)[ProjectRules.REL], 0.01)
	if fixed:
		v += float(cfg().get("payload_fix_rel", 0.15))
	return clampf(v, 0.0, 1.0)


## p_payload of GDD 6.6: clamp(0.55 + 0.45 * rel_norm - 0.03 * residual defects, 0.30, 0.99).
static func payload_chance(state: TycoonState, p: MissionProject, fixed := false) -> float:
	var l := ProjectRules.section("launch")
	var defects := p.defects * (float(cfg().get("payload_fix_defects", 0.4)) if fixed else 1.0)
	return clampf(float(l.get("payload_base", 0.55)) + float(l.get("payload_rel", 0.45)) * rel_norm(state, p, fixed)
		- float(l.get("payload_defect", 0.03)) * defects, float(l.get("payload_min", 0.3)), float(l.get("payload_max", 0.99)))


## Crewed flights: lerp(crewed_courage_floor, 1, the team's mean courage); 1 otherwise.
static func crew_factor(state: TycoonState, p: MissionProject) -> float:
	if not ProjectRules.is_crewed(p.type_id):
		return 1.0
	var l := ProjectRules.section("launch")
	var courage := 0.0
	var team := p.team(state)
	for m in team:
		courage += float(m.get("courage", 0.5))
	courage /= maxf(team.size(), 1)
	return lerpf(float(l.get("crewed_courage_floor", 0.85)), 1.0, courage)


## The odds of the launch: {"total", "rocket" (components x heritage x margins), "payload",
## "crew", "risks"}; total = rocket * payload * crew = the product of every (1 - p).
static func odds(state: TycoonState, p: MissionProject, fixes: Variant = null) -> Dictionary:
	var list := risks(state, p, fixes)
	var rocket := 1.0
	var payload := 1.0
	var crew := 1.0
	for rk in list:
		var q := 1.0 - clampf(float(rk["p"]), 0.0, 1.0)
		match String(rk["kind"]):
			"payload":
				payload *= q
			"crew":
				crew *= q
			_:
				rocket *= q
	return {"total": rocket * payload * crew, "rocket": rocket, "payload": payload, "crew": crew, "risks": list}


## What a set of fixes costs: {"weeks" (the longest, they run in parallel), "cost" (the sum)}.
static func fix_plan(state: TycoonState, p: MissionProject, fixes: Array) -> Dictionary:
	var weeks := 0
	var cost := 0.0
	for rk in risks(state, p, []):
		if String(rk["id"]) in fixes and String(rk["fix_key"]) != "":
			weeks = maxi(weeks, int(rk["fix_weeks"]))
			cost += float(rk["fix_cost"])
	return {"weeks": weeks, "cost": cost}


## The ids of the risks that keep the rocket on the ground (a design that does not reach).
static func blockers(state: TycoonState, p: MissionProject) -> Array[String]:
	var out: Array[String] = []
	for rk in risks(state, p):
		if rk.get("blocking", false):
			out.append(String(rk["id"]))
	return out


## The risk most likely to end the flight (the advisor's warning), {} if none.
static func riskiest(list: Array) -> Dictionary:
	var best: Dictionary = {}
	for rk: Dictionary in list:
		if best.is_empty() or float(rk["p"]) > float(best["p"]):
			best = rk
	return best


## The cause of a failed launch: one risk, chosen with a weight of -ln(1 - p) (the share of the
## failure chance it brings). `roll` in 0..1.
static func pick_cause(list: Array, roll: float) -> Dictionary:
	var weights: Array[float] = []
	var total := 0.0
	for rk: Dictionary in list:
		var w := -log(maxf(1.0 - clampf(float(rk["p"]), 0.0, 0.999999), 1e-6))
		weights.append(w)
		total += w
	if total <= 0.0:
		return {}
	var x := roll * total
	for i in list.size():
		if weights[i] <= 0.0:
			continue
		x -= weights[i]
		if x <= 0.0:
			return list[i]
	return list[list.size() - 1]
