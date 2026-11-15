class_name MissionFit
extends RefCounted
## How well a mission's plan fits its hidden ideals (the Game Dev Tycoon "good combo" layer on
## top of the development grade). Each component is 0..1:
##   objective   briefings only: the client's score of the target x the score of the type
##   instrument  hidden fit of each instrument at the target for the type (payload.json fit:
##               2 great, 1 good, 0 dead weight, -1 wrong), filling instr_cap points, minus
##               dead weight, wrong picks and the modules the briefing needs but the plan lacks;
##               the type's instr_weight says how much it matters (a comms satellite barely)
##   power       the REAL environment: a night the batteries do not cover, cold without a
##               heater or an RTG, panels short by day
##   data        downlink vs the data made (with a buffer allowance)
##   team        the bars the balance leans on (ideal >= bar_min) each have a Cometling of that
##               profession; the ops capacity covers the data; not far below the ideal size
##   match       the bar balance vs the ideal (development grade's own term, used for the
##               great combo and the lever feedback)
## fit = weighted mean (objective counts only for briefings); grade = development grade *
## (1 - w + w * fit) with w = fit_weight_era[era]; a great combo (compat great, instruments,
## match and fit high) multiplies it again. feedback() turns the gaps into readable lines.

static func cfg() -> Dictionary:
	return BriefingDesk.disc()


## Hidden fit of a module on a type at a target: 2, 1, 0 or -1 (non-instruments: 0).
static func instrument_fit(type_id: String, target_id: String, module_id: String) -> int:
	if String(PayloadRules.module(module_id).get("kind", "")) != "instrument":
		return 0
	if module_id in PayloadRules.data().get("surface_only", []) and not PayloadRules.is_surface(type_id):
		return -1
	var tf: Dictionary = PayloadRules.type_rules(type_id).get("fit", {})
	if tf.has(module_id):
		return int(tf[module_id])
	return int((PayloadRules.section("fit").get(target_id, {}) as Dictionary).get(module_id, 0))


## The context of a project (or of a plan on the screens): {"type", "target", "payload",
## "staff" [ids], "briefing_id", "pts" [4] (optional), "ideal" [4]}.
static func ctx_of(state: TycoonState, p: MissionProject) -> Dictionary:
	return {"type": p.type_id, "target": p.target_id, "payload": p.payload_or_default(state), "staff": p.staff_ids,
		"briefing_id": p.briefing_id, "pts": p.pts, "ideal": p.ideal(state)}


static func evaluate(state: TycoonState, ctx: Dictionary) -> Dictionary:
	var c := cfg()
	var type_id := String(ctx.get("type", ""))
	var target_id := String(ctx.get("target", ""))
	var payload: Array = ctx.get("payload", [])
	var b := BriefingDesk.briefing(String(ctx.get("briefing_id", "")))
	var out := {}
	# objective
	var obj := 1.0
	if not b.is_empty():
		var miss := float((c.get("objective", {}) as Dictionary).get("miss", 0.25))
		var sol := BriefingDesk.solution(b)
		out["obj_target"] = float((sol.get("targets", {}) as Dictionary).get(target_id, miss))
		out["obj_type"] = float((sol.get("types", {}) as Dictionary).get(type_id, miss))
		obj = float(out["obj_target"]) * float(out["obj_type"])
	out["objective"] = obj
	# instruments
	var ic: Dictionary = c.get("instrument", {})
	var tr := PayloadRules.type_rules(type_id)
	var cap := maxf(float(tr.get("instr_cap", 3)), 1.0)
	var pos := 0.0
	var ratings := {}
	var useless: Array[String] = []
	var bad: Array[String] = []
	var stars: Array[String] = []
	for m in PayloadRules.instruments(payload):
		var f := instrument_fit(type_id, target_id, m)
		ratings[m] = f
		if f >= 2:
			stars.append(m)
		if f > 0:
			pos += f
		elif f == 0:
			useless.append(m)
		else:
			bad.append(m)
	var missing: Array[String] = []
	for m in BriefingDesk.needs(b):
		if not String(m) in payload:
			missing.append(String(m))
	var ants: Array = tr.get("needs_antenna", [])
	if not BriefingDesk.antennas(b).is_empty():   # the client asks for a given reach
		ants = BriefingDesk.antennas(b)
	if not ants.is_empty() and not PayloadRules.antenna(payload) in ants:
		missing.append(String(ants[0]))
	var raw := clampf(minf(pos, cap) / cap - float(ic.get("useless", 0.12)) * useless.size()
		- float(ic.get("bad", 0.25)) * bad.size() - float(ic.get("missing", 0.3)) * missing.size(), 0.0, 1.0)
	if pos <= 0.0 and float(tr.get("instr_weight", 1.0)) < 0.5 and missing.is_empty():
		raw = maxf(raw, 0.8)  # a comms satellite does not need instruments
	var iw := float(tr.get("instr_weight", 1.0))
	out["instr_raw"] = raw
	out["instrument"] = 1.0 - iw * (1.0 - raw)
	out["ratings"] = ratings
	out["useless"] = useless
	out["bad"] = bad
	out["stars"] = stars
	out["missing"] = missing
	# power, in the real environment
	var pc: Dictionary = c.get("power", {})
	var en := PayloadRules.energy(state, type_id, payload, PayloadRules.env(state, target_id, true))
	var power := 1.0
	out["day_short"] = float(en["day_margin"]) < 0.0
	out["night_fail"] = float(en["night_margin"]) < 0.0
	out["cold_fail"] = not en["cold_ok"]
	if out["day_short"]:
		power -= float(pc.get("day_short", 0.5))
	if out["night_fail"]:
		power -= float(pc.get("night_fail", 0.45))
	if out["cold_fail"]:
		power -= float(pc.get("cold_fail", 0.35))
	out["power"] = clampf(power, 0.0, 1.0)
	out["energy"] = en
	# data
	var dc: Dictionary = c.get("data", {})
	var gen := PayloadRules.data_rate(payload)
	var down := PayloadRules.downlink(state, type_id, target_id, payload)
	out["gen"] = gen
	out["down"] = down
	out["data"] = 1.0 if gen <= 0.0 else clampf(float(dc.get("buffer", 1.4)) * down / gen, float(dc.get("floor", 0.2)), 1.0)
	out["storage_short"] = gen > 0.0 and PayloadRules.storage(state, type_id, payload) < gen * float(PayloadRules.section("bus").get("storage_weeks", 1.5))
	# team
	var tc: Dictionary = c.get("team", {})
	var ideal: Array = ctx.get("ideal", [0.25, 0.25, 0.25, 0.25])
	var team: Array[Dictionary] = []
	for m in state.staff:
		if String(m.get("id", "")) in ctx.get("staff", []):
			team.append(m)
	var covered := 0
	var wanted := 0
	var missing_bars: Array[String] = []
	for bi in 4:
		if float(ideal[bi]) < float(tc.get("bar_min", 0.25)):
			continue
		wanted += 1
		var bar := ProjectRules.BARS[bi]
		var has := false
		for m in team:
			if String(state.profession(String(m.get("profession", ""))).get("primary", "")) == bar:
				has = true
		if has:
			covered += 1
		else:
			missing_bars.append(bar)
	var ops_cap := float(tc.get("ops_base", 2.0))
	for m in team:
		ops_cap += ProjectRules.affinity(state.profession(String(m.get("profession", ""))), "ops", state.pdata) \
			* float(tc.get("ops_per_member", 6.0))
	out["ops_overload"] = gen > ops_cap
	var probe := MissionProject.new()
	probe.type_id = type_id
	out["small_team"] = team.size() * 2 < probe.ideal_team(state)
	var team_s := (float(covered) / wanted) if wanted > 0 else 1.0
	if out["ops_overload"]:
		team_s *= float(tc.get("overload", 0.75))
	if out["small_team"]:
		team_s *= float(tc.get("small", 0.85))
	out["team"] = clampf(team_s, 0.0, 1.0)
	out["missing_bars"] = missing_bars
	# the bar balance
	var pts: Array = ctx.get("pts", [])
	var bal := 1.0
	var gap_bar := -1
	var gap := 0.0
	if not pts.is_empty() and float(pts[0]) + float(pts[1]) + float(pts[2]) + float(pts[3]) > 0.0:
		var frac := MissionProject.fractions_of(pts)
		bal = MissionProject.ratio_match(frac, ideal)
		for bi in 4:
			var g := float(frac[bi]) - float(ideal[bi])
			if absf(g) > absf(gap):
				gap = g
				gap_bar = bi
	out["match"] = bal
	out["gap_bar"] = gap_bar
	out["gap"] = gap
	# fit and the grade multiplier
	var w: Dictionary = c.get("weights", {})
	var sum_w := 0.0
	var fit := 0.0
	for k in ["instrument", "power", "data", "team", "objective"]:
		if k == "objective" and b.is_empty():
			continue
		sum_w += float(w.get(k, 0.0))
		fit += float(w.get(k, 0.0)) * float(out[k])
	fit = fit / maxf(sum_w, 0.001)
	out["fit"] = fit
	var we: Array = c.get("fit_weight_era", [0.3])
	var wv := float(we[clampi(state.era() - 1, 0, we.size() - 1)])
	out["weight"] = wv
	out["mult"] = 1.0 - wv + wv * fit
	var g2: Dictionary = c.get("great", {})
	var tier := ProjectRules.compat_tier(ProjectRules.compat(state.mission_type(type_id), target_id))
	out["great"] = tier == "great" and raw >= float(g2.get("instrument", 0.75)) and bal >= float(g2.get("match", 0.85)) \
		and fit >= float(g2.get("fit", 0.8)) and obj >= 0.99
	out["great_mult"] = float(g2.get("grade_mult", 1.1)) if out["great"] else 1.0
	return out


## The final grade from the development grade and the fit report.
static func apply(grade: float, report: Dictionary) -> float:
	return clampf(grade * float(report.get("mult", 1.0)) * float(report.get("great_mult", 1.0)), 0.0, 10.0)


## Readable lines about what went right and wrong, most telling first (at most feedback_max):
## [{"key", "args", "tone" ("good" | "bad" | "star"), "topic"}].
static func feedback(state: TycoonState, report: Dictionary, type_id: String, target_id: String) -> Array[Dictionary]:
	var bad: Array[Dictionary] = []
	var good: Array[Dictionary] = []
	if report.get("great", false):
		good.append({"key": "TY_FB_GREAT", "args": [], "tone": "star", "topic": "combo"})
	if report.has("obj_target"):
		if float(report["obj_target"]) < 0.5:
			bad.append({"key": "TY_FB_TARGET_OFF", "args": [String(state.mission_target(target_id).get("name_key", ""))], "tone": "bad", "topic": "objective"})
		elif float(report["obj_target"]) < 0.99:
			bad.append({"key": "TY_FB_TARGET_NEAR", "args": [String(state.mission_target(target_id).get("name_key", ""))], "tone": "bad", "topic": "objective"})
		if float(report["obj_type"]) < 0.5:
			bad.append({"key": "TY_FB_TYPE_OFF", "args": [String(state.mission_type(type_id).get("name_key", ""))], "tone": "bad", "topic": "objective"})
		elif float(report["obj_type"]) < 0.99:
			bad.append({"key": "TY_FB_TYPE_NEAR", "args": [String(state.mission_type(type_id).get("name_key", ""))], "tone": "bad", "topic": "objective"})
		if float(report["obj_target"]) >= 0.99 and float(report["obj_type"]) >= 0.99:
			good.append({"key": "TY_FB_OBJECTIVE_OK", "args": [], "tone": "good", "topic": "objective"})
	for m in report.get("missing", []):
		var k := "TY_FB_MISSING_ANTENNA" if PayloadRules.module(String(m)).get("kind", "") == "comms" else "TY_FB_MISSING"
		bad.append({"key": k, "args": [PayloadRules.name_key(String(m))], "tone": "bad", "topic": "instrument"})
	if report.get("night_fail", false):
		bad.append({"key": "TY_FB_NIGHT_" + ("MOON" if target_id.begins_with("lunar") else "OTHER"), "args": [], "tone": "bad", "topic": "power"})
	if report.get("cold_fail", false):
		bad.append({"key": "TY_FB_COLD", "args": [], "tone": "bad", "topic": "power"})
	if report.get("day_short", false):
		bad.append({"key": "TY_FB_DAY_SHORT", "args": [], "tone": "bad", "topic": "power"})
	for m in report.get("bad", []):
		bad.append({"key": "TY_FB_INSTR_BAD", "args": [PayloadRules.name_key(String(m))], "tone": "bad", "topic": "instrument"})
	for bar in report.get("missing_bars", []):
		bad.append({"key": "TY_FB_TEAM_MISSING_" + String(bar).to_upper(), "args": [], "tone": "bad", "topic": "team"})
	if report.get("ops_overload", false):
		bad.append({"key": "TY_FB_OPS_OVERLOAD", "args": [], "tone": "bad", "topic": "team"})
	if float(report.get("data", 1.0)) < 0.6:
		bad.append({"key": "TY_FB_DATA_STUCK", "args": [], "tone": "bad", "topic": "data"})
	elif report.get("storage_short", false):
		bad.append({"key": "TY_FB_STORAGE", "args": [], "tone": "bad", "topic": "data"})
	var gb := int(report.get("gap_bar", -1))
	if gb >= 0 and absf(float(report.get("gap", 0.0))) >= float(cfg().get("lever_gap", 0.08)):
		var low := float(report["gap"]) < 0.0
		bad.append({"key": "TY_FB_BAR_LOW" if low else "TY_FB_BAR_HIGH", "args": ["TY_BAR_" + ProjectRules.BARS[gb].to_upper()],
			"tone": "bad", "topic": "levers"})
	elif gb >= 0 and float(report.get("match", 0.0)) >= 0.9:
		good.append({"key": "TY_FB_BALANCE_OK", "args": [], "tone": "good", "topic": "levers"})
	for m in report.get("useless", []):
		bad.append({"key": "TY_FB_INSTR_USELESS", "args": [PayloadRules.name_key(String(m))], "tone": "bad", "topic": "instrument"})
	for m in report.get("stars", []):
		good.append({"key": "TY_FB_INSTR_STAR", "args": [PayloadRules.name_key(String(m))], "tone": "good", "topic": "instrument"})
	if float(report.get("power", 0.0)) >= 1.0 and not PayloadRules.env_true(target_id).get("hidden", []).is_empty():
		good.append({"key": "TY_FB_POWER_OK", "args": [], "tone": "good", "topic": "power"})
	if float(report.get("team", 0.0)) >= 1.0:
		good.append({"key": "TY_FB_TEAM_OK", "args": [], "tone": "good", "topic": "team"})
	var n := int(cfg().get("feedback_max", 5))
	var out: Array[Dictionary] = []
	# the great combo first, then the gaps, then what went well
	for f in good:
		if f["tone"] == "star":
			out.append(f)
	for f in bad:
		if out.size() < n:
			out.append(f)
	for f in good:
		if out.size() < n and f["tone"] != "star":
			out.append(f)
	return out


## The parameters the flight operations take from the payload (MissionOps.init_mission reads
## these when present): data made, storage, antenna gain, science value, a shorter life when
## the night killed the batteries, a weaker health when the cold got in.
static func ops_fields(state: TycoonState, type_id: String, payload: Array, report: Dictionary) -> Dictionary:
	var o: Dictionary = cfg().get("ops", {})
	var ty := MissionOps.type_ops(type_id)
	var ref := maxf(float(PayloadRules.type_rules(type_id).get("data_ref", 4.0)), 0.1)
	var dmult := clampf(PayloadRules.data_rate(payload) / ref, float(o.get("data_min", 0.3)), float(o.get("data_max", 2.0)))
	var out := {"gen_per_week": float(ty.get("gen_per_week", 5.0)) * dmult,
		"storage": PayloadRules.storage(state, type_id, payload),
		"antenna_gain": PayloadRules.antenna_gain(payload) * float(ty.get("antenna", 1.0)),
		"value": float(ty.get("value", 1.0)) * (float(o.get("value_floor", 0.6)) + float(o.get("value_span", 0.6)) * float(report.get("instr_raw", 0.5))),
		"payload": payload.duplicate()}
	if report.get("night_fail", false):
		out["ops_weeks"] = maxi(roundi(float(ty.get("ops_weeks", 8)) * float(o.get("night_fail_weeks", 0.35))), 1)
	if report.get("cold_fail", false):
		out["health"] = float(o.get("cold_health", 0.6))
	return out
