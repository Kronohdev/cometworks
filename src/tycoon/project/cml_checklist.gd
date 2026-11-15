class_name CmlChecklist
extends RefCounted
## The Concept Maturity Level checklist of the Design Review (NASA/JPL CML, data/tycoon/cml.json).
## A mission concept matures through levels, each a short checklist auto-checked from the
## project's real state:
##   CML 1 Cocktail-napkin idea    objective    a briefing or contract, or a target the type suits
##   CML 2 Initial feasibility     reaches      the rocket reaches (no delta-v / lift / fairing block)
##                                 team         MissionFit team: the bars the balance leans on are covered
##   CML 3 Trade space explored    instruments  MissionFit instrument fit at the target, no wrong picks
##                                 power        MissionFit power: day, night and cold covered
##   CML 4 Preferred design point  mass_margin  delta-v and lift in the green (a real margin)
##                                 comms        the antenna the mission (or its client) asks for; the
##                                              downlink carries the data
##   CML 5 Concept baseline        budget       the briefing's budget and the cash cover the fixes and launch
##                                 schedule     the briefing's or contract's deadline holds after the fixes
##   CML 6 Initial design          risks        every fixable high-severity risk is being fixed, nothing blocks
## The level is the highest n whose items, and all the items below, are checked. A higher level
## gives a modest bonus at the launch (bonus(): hype on a success, reputation always) and never
## blocks anything. Pure rules, headless; the Design Review screen draws it.

const PATH := "res://data/tycoon/cml.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(PATH)
	return _data


static func levels() -> Array:
	return data().get("levels", [])


static func max_level() -> int:
	return levels().size()


static func item_def(id: String) -> Dictionary:
	return (data().get("items", {}) as Dictionary).get(id, {})


static func level_name_key(level: int) -> String:
	for lv: Dictionary in levels():
		if int(lv.get("level", 0)) == level:
			return String(lv.get("name_key", ""))
	return ""


## The checklist of a project in review, with these fixes (default: the project's own).
## `planned`: the fixes are still to be paid and worked (the review screen); false at the launch,
## when they are already done. Returns {"level" (0..max), "items" [{"id", "level", "label_key",
## "hint_key", "ok"}] in level order, "levels" [{"level", "name_key", "ok"}]}.
static func evaluate(state: TycoonState, p: MissionProject, fixes: Variant = null, planned := true) -> Dictionary:
	var fx: Array = p.review_fixes if fixes == null else fixes
	var ctx := _context(state, p, fx, planned)
	var items: Array[Dictionary] = []
	var lv_rows: Array[Dictionary] = []
	var level := 0
	var climbing := true
	for lv: Dictionary in levels():
		var n := int(lv.get("level", 0))
		var all_ok := true
		for id in lv.get("items", []):
			var d := item_def(String(id))
			var ok := check(String(id), d, ctx)
			all_ok = all_ok and ok
			items.append({"id": String(id), "level": n, "label_key": String(d.get("label_key", "")),
				"hint_key": String(d.get("hint_key", "")), "ok": ok})
		lv_rows.append({"level": n, "name_key": String(lv.get("name_key", "")), "ok": all_ok})
		if climbing and all_ok:
			level = n
		else:
			climbing = false
	return {"level": level, "items": items, "levels": lv_rows}


## What the items read, gathered once: the fit report, the rocket's check, the risks and the money.
static func _context(state: TycoonState, p: MissionProject, fx: Array, planned: bool) -> Dictionary:
	var parts := RocketDesigner.normalize(p.rocket.get("parts", {}))
	var plan := DesignReview.fix_plan(state, p, fx) if planned else {"weeks": 0, "cost": 0.0}
	var fam := RocketFamilies.find(state, String(p.rocket.get("family", "")))
	return {"state": state, "p": p, "fixes": fx, "plan": plan,
		"report": MissionFit.evaluate(state, MissionFit.ctx_of(state, p)),
		"check": RocketDesigner.check(state, parts, p.type_id, p.target_id),
		"risks": DesignReview.risks(state, p, fx),
		"launch_cost": RocketDesigner.unit_cost(state, parts, RocketFamilies.flights(fam)) if not p.rocket.is_empty()
			else ProjectRules.launch_cost(p.type_id)}


## One item: is it checked? `d` is its entry in cml.json (thresholds).
static func check(id: String, d: Dictionary, ctx: Dictionary) -> bool:
	var state: TycoonState = ctx["state"]
	var p: MissionProject = ctx["p"]
	var report: Dictionary = ctx["report"]
	var chk: Dictionary = ctx["check"]
	match id:
		"objective":
			if p.briefing_id != "" or p.contract_id != "":
				return true
			var tier := ProjectRules.compat_tier(ProjectRules.compat(state.mission_type(p.type_id), p.target_id))
			return tier in ["great", "good"]
		"reaches":
			return bool(chk.get("reaches", false))
		"team":
			return float(report.get("team", 0.0)) >= float(d.get("min_team", 0.75))
		"instruments":
			return float(report.get("instrument", 0.0)) >= float(d.get("min_instrument", 0.6)) \
				and (report.get("bad", []) as Array).is_empty()
		"power":
			return float(report.get("power", 0.0)) >= float(d.get("min_power", 0.99))
		"mass_margin":
			return String(chk["dv"]["state"]) == "green" and String(chk["lift"]["state"]) == "green"
		"comms":
			return _antenna_ok(p, state) and float(report.get("data", 0.0)) >= float(d.get("min_data", 0.9))
		"budget":
			var plan: Dictionary = ctx["plan"]
			var budget := float(p.briefing_terms.get("budget", 0.0))
			if budget > 0.0 and p.cost_spent + float(plan["cost"]) > budget:
				return false
			return state.cash >= float(plan["cost"]) + float(ctx["launch_cost"])
		"schedule":
			var deadline := deadline_week(state, p)
			return deadline < 0 or state.weeks + int((ctx["plan"] as Dictionary)["weeks"]) <= deadline
		"risks":
			for rk: Dictionary in ctx["risks"]:
				if rk.get("blocking", false):
					return false
				if String(rk["fix_key"]) != "" and not rk.get("fixed", false) and String(rk["severity"]) == "high":
					return false
			return true
	return false


## The antenna the mission type (or the briefing's client) asks for is on board (none asked: ok).
static func _antenna_ok(p: MissionProject, state: TycoonState) -> bool:
	var payload := p.payload_or_default(state)
	var ants: Array = PayloadRules.type_rules(p.type_id).get("needs_antenna", [])
	var b := BriefingDesk.briefing(p.briefing_id)
	if not BriefingDesk.antennas(b).is_empty():
		ants = BriefingDesk.antennas(b)
	return ants.is_empty() or PayloadRules.antenna(payload) in ants


## The week the project must launch by: the briefing's deadline, else the contract's; -1 for none.
static func deadline_week(state: TycoonState, p: MissionProject) -> int:
	if p.briefing_id != "":
		var b := BriefingDesk.briefing(p.briefing_id)
		return p.start_week + int(p.briefing_terms.get("deadline", b.get("deadline", 30)))
	if p.contract_id != "":
		var c := ProjectDesk.contract(state, p.contract_id)
		if c.has("deadline_week"):
			return int(c["deadline_week"])
	return -1


## The launch bonus of a level: {"hype", "reputation"} (0 below bonus.from_level).
static func bonus(level: int) -> Dictionary:
	var b: Dictionary = data().get("bonus", {})
	var n := maxi(level - int(b.get("from_level", 4)) + 1, 0)
	return {"hype": n * float(b.get("hype_per_level", 1.5)), "reputation": n * float(b.get("reputation_per_level", 0.25))}
