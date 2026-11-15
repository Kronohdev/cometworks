class_name FlightReport
extends RefCounted
## "Por que foi assim?": the short post-mission report after any launch, watched or skipped (the
## last page of the comic recap, FlightComic). Reads the project's history entry (ProjectDesk
## launch: outcome, cause, odds, risks, MissionFit report, rocket, rewards) and names the causes
## of a partial or a failed mission, most telling first:
##   cause        what broke (the Design Review's risk the launch drew)
##   risk open    that risk could have been fixed in the review and was not
##   bad luck     every risk was fixed or small: the odds were good and the dice said no
##   delta-v      the rocket reached with little margin (RocketDesigner.check: not green)
##   lift         the same for the mass it lifts
##   instruments  the payload did not suit the target (MissionFit instrument)
##   power        night, cold or short panels (MissionFit power)
##   comms        the downlink could not carry the data (MissionFit data)
##   team         the specialities the mission asked for were missing (MissionFit team)
##   grade        the project's grade was under the full mission's
## and one friendly tip, the first cause's. When the Design Review has its CML checklist
## (CmlChecklist), the tip names the maturity item that cause leaves unchecked.
## Pure rules: headless, no scene.

const CML_SCRIPT := "res://src/tycoon/project/cml_checklist.gd"
## the reason -> its tip and the CML item it leaves unchecked
const LINKS := {
	"TY_FC_WHY_RISK_OPEN": {"tip": "TY_FC_TIP_RISKS", "cml": "risks"},
	"TY_FC_WHY_RANDOM": {"tip": "TY_FC_TIP_RANDOM", "cml": ""},
	"TY_FC_WHY_CAUSE": {"tip": "", "cml": ""},
	"TY_FC_WHY_DV": {"tip": "TY_FC_TIP_MARGIN", "cml": "mass_margin"},
	"TY_FC_WHY_LIFT": {"tip": "TY_FC_TIP_MARGIN", "cml": "mass_margin"},
	"TY_FC_WHY_INSTRUMENTS": {"tip": "TY_FC_TIP_INSTRUMENTS", "cml": "instruments"},
	"TY_FC_WHY_POWER": {"tip": "TY_FC_TIP_POWER", "cml": "power"},
	"TY_FC_WHY_DATA": {"tip": "TY_FC_TIP_DATA", "cml": "comms"},
	"TY_FC_WHY_TEAM": {"tip": "TY_FC_TIP_TEAM", "cml": "team"},
	"TY_FC_WHY_GRADE": {"tip": "TY_FC_TIP_GRADE", "cml": ""},
	"TY_FC_WHY_ALL_GOOD": {"tip": "TY_FC_TIP_KEEP", "cml": ""},
}
const MAX_REASONS := 4
## the fit thresholds when the CML checklist has none
const FIT_MIN := {"instrument": 0.6, "power": 0.99, "data": 0.9, "team": 0.75}
const TITLES := {"exceptional": "TY_FC_END_EXCEPTIONAL", "full": "TY_FC_END_FULL", "partial": "TY_FC_END_PARTIAL",
	"fail": "TY_FC_END_FAIL"}


## The report of a history entry; `flown` is FlightLog.outcome() ({} when the flight was not
## flown). {"outcome", "title_key", "reasons": [{"key", "args" (String.format), "tone"}],
## "tip": {"key", "args"}, "cml": {"id", "level", "label_key", "hint_key"} or {}, "rewards": [{"key", "value"}]}.
static func build(state: TycoonState, entry: Dictionary, flown := {}) -> Dictionary:
	var outcome := String(entry.get("outcome", "full"))
	if bool(flown.get("lost", false)):
		outcome = "fail"
	var reasons: Array[Dictionary] = []
	if outcome == "fail":
		_fail_reasons(entry, reasons)
	if outcome != "exceptional":
		_rocket_reasons(state, entry, reasons)
		_fit_reasons(entry, reasons)
	if outcome == "partial":
		var need := float(ProjectRules.section("launch").get("full_grade", 5.5))
		var g := float(entry.get("grade_project", entry.get("grade", need)))
		if g < need:
			reasons.append({"key": "TY_FC_WHY_GRADE", "args": {"grade": "%.1f" % g, "need": "%.1f" % need}, "tone": "bad"})
	if reasons.is_empty():
		reasons.append({"key": "TY_FC_WHY_ALL_GOOD", "args": {}, "tone": "good"})
	reasons = reasons.slice(0, MAX_REASONS)
	# the tip of the first reason that has one (what broke has none: why it broke tells)
	var tip := {"key": "TY_FC_TIP_KEEP", "args": {}}
	for r in reasons:
		var t := String((LINKS.get(String(r["key"]), {}) as Dictionary).get("tip", ""))
		if t != "":
			tip["key"] = t
			break
	var cml := {}
	for r in reasons:
		var item := String((LINKS.get(String(r["key"]), {}) as Dictionary).get("cml", ""))
		if item != "":
			cml = cml_item(item)
			if not cml.is_empty():
				break
	return {"outcome": outcome, "title_key": String(TITLES.get(outcome, "TY_FC_END_FULL")), "reasons": reasons,
		"tip": tip, "cml": cml, "rewards": rewards(entry)}


## The failure: what broke, and whether the review could have fixed it or the dice decided.
static func _fail_reasons(entry: Dictionary, out: Array[Dictionary]) -> void:
	var ck := String(entry.get("cause_key", ""))
	if ck != "":
		out.append({"key": "TY_FC_WHY_CAUSE", "args": {"cause": TranslationServer.translate(ck)}, "tone": "bad"})
	var open := {}
	for rk: Dictionary in entry.get("risks", []):
		if not bool(rk.get("fixed", false)) and float(rk.get("p", 0.0)) >= 0.04:
			if open.is_empty() or float(rk.get("p", 0.0)) > float(open.get("p", 0.0)):
				open = rk
	if not open.is_empty():
		out.append({"key": "TY_FC_WHY_RISK_OPEN", "args": {"risk": TranslationServer.translate(String(open.get("name_key", "")))},
			"tone": "bad"})
	else:
		out.append({"key": "TY_FC_WHY_RANDOM", "args": {"p": "%d" % roundi(float(entry.get("p_success", 0.0)) * 100.0)},
			"tone": "neutral"})


## The rocket's margins (delta-v, lift) for the mission it flew.
static func _rocket_reasons(state: TycoonState, entry: Dictionary, out: Array[Dictionary]) -> void:
	var parts: Dictionary = (entry.get("rocket", {}) as Dictionary).get("parts", {})
	if parts.is_empty() or state == null:
		return
	var chk := RocketDesigner.check(state, RocketDesigner.normalize(parts), String(entry.get("type", "")),
		String(entry.get("target", "")))
	if String((chk.get("dv", {}) as Dictionary).get("state", "green")) != "green":
		out.append({"key": "TY_FC_WHY_DV", "args": {}, "tone": "bad"})
	if String((chk.get("lift", {}) as Dictionary).get("state", "green")) != "green":
		out.append({"key": "TY_FC_WHY_LIFT", "args": {}, "tone": "bad"})


## The plan's fit (MissionFit, written in the entry at the launch).
static func _fit_reasons(entry: Dictionary, out: Array[Dictionary]) -> void:
	var fit: Dictionary = entry.get("fit", {})
	if fit.is_empty():
		return
	var mins := {"instrument": _cml_min("instruments", "min_instrument", FIT_MIN["instrument"]),
		"power": _cml_min("power", "min_power", FIT_MIN["power"]), "data": _cml_min("comms", "min_data", FIT_MIN["data"]),
		"team": _cml_min("team", "min_team", FIT_MIN["team"])}
	var keys := {"instrument": "TY_FC_WHY_INSTRUMENTS", "power": "TY_FC_WHY_POWER", "data": "TY_FC_WHY_DATA",
		"team": "TY_FC_WHY_TEAM"}
	for k: String in ["instrument", "power", "data", "team"]:
		if fit.has(k) and float(fit[k]) < float(mins[k]) - 1e-6:
			out.append({"key": keys[k], "args": {"pct": "%d" % roundi(float(fit[k]) * 100.0)}, "tone": "bad"})


## The rewards the launch paid (the entry's "rewards"), as label keys and texts.
static func rewards(entry: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rw: Dictionary = entry.get("rewards", {})
	if entry.has("grade"):
		out.append({"key": "TY_FC_RW_GRADE", "value": "%.1f" % float(entry["grade"])})
	if rw.has("cash"):
		var c := float(rw["cash"])
		out.append({"key": "TY_FC_RW_CASH", "value": "%s%s cr" % ["+" if c >= 0.0 else "−", _group(absf(c))]})
	for k: String in ["reputation", "hype", "research"]:
		if rw.has(k) and absf(float(rw[k])) >= 0.05:
			out.append({"key": "TY_FC_RW_" + k.to_upper(), "value": "%+.1f" % float(rw[k])})
	return out


static func _group(v: float) -> String:
	var s := "%d" % roundi(v)
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


# ------------------------------------------------------------ the CML checklist (when there is one)
static func _cml() -> Script:
	return load(CML_SCRIPT) as Script if ResourceLoader.exists(CML_SCRIPT) else null


## A CML item's level and texts ({} without the checklist or such an item).
static func cml_item(id: String) -> Dictionary:
	var c := _cml()
	if c == null:
		return {}
	var d: Dictionary = c.call("item_def", id)
	if d.is_empty():
		return {}
	var level := 0
	for lv: Dictionary in c.call("levels"):
		if id in (lv.get("items", []) as Array):
			level = int(lv.get("level", 0))
	return {"id": id, "level": level, "label_key": String(d.get("label_key", "")), "hint_key": String(d.get("hint_key", ""))}


static func _cml_min(id: String, field: String, fallback: float) -> float:
	var c := _cml()
	if c == null:
		return fallback
	var d: Dictionary = c.call("item_def", id)
	return float(d.get(field, fallback))
