class_name HangarRocket
extends RefCounted
## Rockets built in the hangar for a tycoon mission (the hangar and the flight inside the main
## mode, TycoonModes). The vessel the player assembled part by part becomes a tycoon design the
## rest of the loop understands: a RocketDesigner "parts" dictionary whose slots hold dynamic
## components made from the vessel (registered with RocketDesigner.register_component):
##   core      hgr_<id>  stage 1 (engines, tanks): the whole delta-v / lift, the cost, the weeks
##   upper     hgu_<id>  stages 2+ (their reliability), or upper_none for a single stage
##   boosters  hgb_<id>  the side boosters (their reliability, their count for the look)
##   fairing   hgf_<id>  separations: decouplers and fairings (reliability, payload room)
##   avionics  hga_<id>  command, control, power and comms parts (reliability)
##   tank / recovery     the neutral tank_m / recovery_none
## So phases, the Design Review (one risk per real stage), the launch odds, the cost and the
## build weeks all read it like any design. Numbers (data/tycoon/rockets.json "hangar"):
##   delta-v  VesselMath.analyze(stages, mission payload).ascent_dv (the hangar's own math)
##   lift     the payload (t) with which the ascent delta-v still covers the target's need
##   cost     cost_musd x cr_per_musd;  weeks  ceil(parts / parts_per_week) + stages
##   reliability  the product of the parts' "reliability" (data/parts.json) per slot, times
##                stage_rel for every powered stage; no command part: no_command_rel
## RocketDesigner.check() asks performance() for the mission at hand, so a hangar family reused
## for another target is judged with that target's delta-v and payload.
##
## The vessel is saved as data, not as a PackedScene: tree() / scene_of() turn the part tree
## into nested dictionaries ({"id", "pn", "on", "sym", "xf", "c"}) and back. The definitions live
## in TycoonState.rockets["hangar"] (saved with the families); RocketFamilies.restore registers
## them again on load. A save whose definition went missing degrades to an abstract rocket
## (RocketDesigner.normalize falls back to the slot's first component).
## The flight's report becomes a launch outcome through flight_verdict(). Pure rules, headless.

const PREFIX := {"core": "hgr_", "upper": "hgu_", "boosters": "hgb_", "fairing": "hgf_", "avionics": "hga_"}
const NEUTRAL := {"upper": "upper_none", "tank": "tank_m", "boosters": "boost_none", "recovery": "recovery_none"}
## parts whose reliability counts for the avionics slot
const AVIONICS_CATEGORIES: Array[String] = ["command", "bus", "control", "power", "comms", "thermal"]

static var _perf_cache: Dictionary = {}


static func cfg() -> Dictionary:
	return RocketDesigner.section("hangar")


static func _num(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


# ------------------------------------------------------------ registry
static func _db(state: TycoonState) -> Dictionary:
	if not state.rockets.has("hangar") or not state.rockets["hangar"] is Dictionary:
		state.rockets["hangar"] = {}
	return state.rockets["hangar"]


## The hangar definition with this id ({} if none).
static func definition(state: TycoonState, id: String) -> Dictionary:
	return _db(state).get(id, {})


## The hangar id of a design ("" for an abstract one).
static func id_of(parts: Dictionary) -> String:
	var core := String(parts.get("core", ""))
	return core.trim_prefix(PREFIX["core"]) if core.begins_with(PREFIX["core"]) else ""


static func is_hangar(parts: Dictionary) -> bool:
	return id_of(parts) != "" and not RocketDesigner.component(String(parts["core"])).is_empty()


## The definition behind a design ({} for an abstract one or a missing definition).
static func definition_of(state: TycoonState, parts: Dictionary) -> Dictionary:
	var id := id_of(parts)
	return definition(state, id) if id != "" else {}


## Registers every saved definition (RocketFamilies.restore calls it on load).
static func register_all(state: TycoonState) -> void:
	var db: Variant = state.rockets.get("hangar", {})  # read only: no empty entry in saves without one
	if not db is Dictionary:
		return
	for id: String in db:
		var d: Dictionary = db[id]
		_sanitize(d)
		register(d)


## Keeps a definition (in the state) and registers its components. Returns its parts.
static func adopt(state: TycoonState, d: Dictionary) -> Dictionary:
	_db(state)[String(d["id"])] = d
	register(d)
	return parts_of(d)


## The RocketDesigner parts of a definition.
static func parts_of(d: Dictionary) -> Dictionary:
	var id := String(d["id"])
	var out := NEUTRAL.duplicate()
	out["core"] = PREFIX["core"] + id
	out["fairing"] = PREFIX["fairing"] + id
	out["avionics"] = PREFIX["avionics"] + id
	if int(d.get("stages_n", 1)) > 1:
		out["upper"] = PREFIX["upper"] + id
	if int(d.get("boosters", 0)) > 0:
		out["boosters"] = PREFIX["boosters"] + id
	return out


## Puts the definition's components in RocketDesigner's catalogue.
static func register(d: Dictionary) -> void:
	var id := String(d["id"])
	var rel: Dictionary = d.get("rel", {})
	RocketDesigner.register_component({"id": PREFIX["core"] + id, "slot": "core", "name_key": "TY_HG_C_CORE",
		"desc_key": "TY_HG_D_CORE", "cost": float(d.get("cost", 0.0)), "rel": float(rel.get("core", 1.0)),
		"dv": float(d.get("dv", 0.0)), "lift": float(d.get("lift", 0.0)), "weeks": int(d.get("weeks", 1)),
		"model": int(d.get("model", 1)), "hangar": id, "stages": d.get("stages", []),
		"fairing_kg": float(d.get("fairing_kg", 0.0)), "tree": d.get("tree", {})})
	RocketDesigner.register_component({"id": PREFIX["upper"] + id, "slot": "upper", "name_key": "TY_HG_C_UPPER",
		"desc_key": "TY_HG_D_UPPER", "rel": float(rel.get("upper", 1.0)), "height": 0.1, "hangar": id})
	RocketDesigner.register_component({"id": PREFIX["boosters"] + id, "slot": "boosters", "name_key": "TY_HG_C_BOOSTERS",
		"desc_key": "TY_HG_D_BOOSTERS", "rel": float(rel.get("boosters", 1.0)), "count": mini(int(d.get("boosters", 0)), 4),
		"size": 0.32, "hangar": id})
	RocketDesigner.register_component({"id": PREFIX["fairing"] + id, "slot": "fairing", "name_key": "TY_HG_C_FAIRING",
		"desc_key": "TY_HG_D_FAIRING", "rel": float(rel.get("fairing", 1.0)), "max_size": float(d.get("max_size", 0.6)),
		"hangar": id})
	RocketDesigner.register_component({"id": PREFIX["avionics"] + id, "slot": "avionics", "name_key": "TY_HG_C_AVIONICS",
		"desc_key": "TY_HG_D_AVIONICS", "rel": float(rel.get("avionics", 1.0)), "hangar": id})


## JSON brings numbers back as floats; the tree and the stage lists stay as they are.
static func _sanitize(d: Dictionary) -> void:
	for k in ["weeks", "model", "stages_n", "boosters", "parts_n"]:
		d[k] = int(d.get(k, 0))
	d["id"] = String(d.get("id", ""))


# ------------------------------------------------------------ the mission
## What a tycoon mission asks of the hangar (FlightSession.mission): {"title", "target" (its
## name), "dv_needed" m/s, "payload_kg", "budget_musd", "crewed"} plus "target_id", "type_id"
## and "code". `budget_cr` is what the rocket may cost (<= 0: no limit given).
static func mission_for(state: TycoonState, type_id: String, target_id: String, budget_cr := 0.0, code := "") -> Dictionary:
	var nd := RocketDesigner.need(state, type_id, target_id)
	var mt := state.mission_type(type_id)
	var tname := TranslationServer.translate(String(state.mission_target(target_id).get("name_key", target_id)))
	var title := TranslationServer.translate(String(mt.get("name_key", type_id)))
	if code != "":
		title = "%s · %s" % [code, title]
	return {"title": title, "target": tname, "dv_needed": float(nd["dv"]) * 1000.0,
		"payload_kg": float(nd["lift"]) * 1000.0, "budget_musd": maxf(budget_cr, 0.0) / maxf(_num("cr_per_musd", 10000.0), 1.0),
		"crewed": ProjectRules.is_crewed(type_id), "target_id": target_id, "type_id": type_id, "code": code}


## What a project may spend on its rocket: the briefing's budget less what the project costs
## besides the rocket, else the agency's cash less that (never below 0).
static func budget_for(state: TycoonState, type_id: String, target_id: String, payload: Array, budget := 0.0,
		spent := 0.0) -> float:
	var est := ProjectDesk.estimate(state, type_id, {}, target_id)
	var other := float(est["dev_cost"]) + PayloadRules.cost(payload) - spent
	var pot := budget if budget > 0.0 else state.cash
	return maxf(pot - maxf(other, 0.0), 0.0)


# ------------------------------------------------------------ vessel <-> data
## The part tree of a packed vessel as nested dictionaries.
static func tree(ps: PackedScene) -> Dictionary:
	if ps == null:
		return {}
	var r := ps.instantiate() as PartInstance
	if r == null:
		return {}
	var out := _node_data(r)
	r.free()
	return out


static func _node_data(p: PartInstance) -> Dictionary:
	var kids: Array = []
	for c in p.get_children():
		if c is PartInstance:
			kids.append(_node_data(c))
	var x := p.transform
	return {"id": p.part_id, "pn": p.parent_node_name, "on": p.own_node_name, "sym": p.sym_tag,
		"xf": [x.basis.x.x, x.basis.x.y, x.basis.x.z, x.basis.y.x, x.basis.y.y, x.basis.y.z,
			x.basis.z.x, x.basis.z.y, x.basis.z.z, x.origin.x, x.origin.y, x.origin.z], "c": kids}


## A packed vessel from tree() data (null for empty data).
static func scene_of(data: Dictionary) -> PackedScene:
	if data.is_empty() or String(data.get("id", "")) == "":
		return null
	var r := _node_of(data)
	var ps := Vessel.pack_tree(r)
	r.free()
	return ps


static func _node_of(d: Dictionary) -> PartInstance:
	var p := PartInstance.new()
	p.part_id = String(d.get("id", ""))
	p.name = p.part_id
	p.parent_node_name = String(d.get("pn", ""))
	p.own_node_name = String(d.get("on", ""))
	p.sym_tag = int(d.get("sym", -1))
	var a: Array = d.get("xf", [])
	if a.size() == 12:
		p.transform = Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
			Vector3(a[9], a[10], a[11]))
	for c: Dictionary in d.get("c", []):
		p.add_child(_node_of(c), true)
	return p


## The packed vessel of a design ({} parts or a missing definition: null).
static func scene_for(state: TycoonState, parts: Dictionary) -> PackedScene:
	var d := definition_of(state, parts)
	return scene_of(d.get("tree", {})) if not d.is_empty() else null


# ------------------------------------------------------------ vessel -> definition
## A definition from a packed vessel (built off the tree, nothing is shown).
static func from_scene(ps: PackedScene, mission: Dictionary, name := "") -> Dictionary:
	if ps == null:
		return {}
	var v := Vessel.new()
	v.load_scene(ps)
	var d := from_vessel(v, mission, name)
	v.free()
	return d


## A definition from an assembled vessel for a mission (mission_for()). {} when it is empty.
static func from_vessel(v: Vessel, mission: Dictionary, name := "") -> Dictionary:
	if v == null or v.root == null:
		return {}
	var st := v.compute_stages()
	var stages: Array = []
	var boosters := 0
	for s: Dictionary in st["stages"]:
		var core_ids: Array = []
		for pd: Dictionary in s["core"]:
			core_ids.append(String(pd.get("id", "")))
		var bl: Array = []
		for g: Array in s["boosters"]:
			var ids: Array = []
			for pd: Dictionary in g:
				ids.append(String(pd.get("id", "")))
			bl.append(ids)
			boosters += 1
		stages.append({"core": core_ids, "boosters": bl})
	var all := v.all_parts()
	var t := tree(v.to_packed_scene())
	var d := {"name": name.strip_edges(), "tree": t, "stages": stages, "fairing_kg": float(st["fairing_kg"]),
		"stages_n": maxi(stages.size(), 1), "boosters": boosters, "parts_n": all.size(), "cost_musd": v.cost_musd(),
		"mission": {"type_id": String(mission.get("type_id", "")), "target_id": String(mission.get("target_id", "")),
			"payload_kg": float(mission.get("payload_kg", 0.0)), "dv_needed": float(mission.get("dv_needed", 0.0))}}
	d["cost"] = roundf(v.cost_musd() * _num("cr_per_musd", 10000.0) / 100.0) * 100.0
	d["weeks"] = clampi(ceili(all.size() / maxf(_num("parts_per_week", 5.0), 1.0)) + stages.size(),
		int(_num("weeks_min", 2.0)), int(_num("weeks_max", 14.0)))
	d["rel"] = reliability(st, all)
	d["max_size"] = payload_room(all)
	var wet := 0.0
	for p in all:
		wet += PartDB.wet_mass(p.data)
	d["wet_kg"] = wet
	d["model"] = model_of(wet)
	var perf := performance_of(stages, float(st["fairing_kg"]), float(d["mission"]["payload_kg"]),
		float(d["mission"]["dv_needed"]))
	d["dv"] = perf["dv"]
	d["lift"] = perf["lift"]
	d["dv0"] = float(VesselMath.analyze(_stage_specs(stages), 0.0, float(st["fairing_kg"]), 2)["ascent_dv"]) / 1000.0
	d["id"] = _id_for(d)
	return d


static func _id_for(d: Dictionary) -> String:
	var key := JSON.stringify(d["tree"]) + "|" + JSON.stringify(d["mission"])
	return "%08x" % (hash(key) & 0x7fffffff)


## Reliability per slot from the parts (rockets.json hangar): {"core", "upper", "boosters",
## "fairing", "avionics"}.
static func reliability(st: Dictionary, all: Array) -> Dictionary:
	var out := {"core": 1.0, "upper": 1.0, "boosters": 1.0, "fairing": 1.0, "avionics": 1.0}
	var stage_rel := _num("stage_rel", 0.985)
	var command := false
	var stages: Array = st["stages"]
	for i in stages.size():
		var s: Dictionary = stages[i]
		var slot := "core" if i == 0 else "upper"
		var powered := false
		for pd: Dictionary in s["core"]:
			var k := _slot_of(pd, slot)
			out[k] = float(out[k]) * float(pd.get("reliability", 1.0))
			powered = powered or PartDB.is_engine(pd)
			command = command or PartDB.is_command(pd)
		if powered:
			out[slot] = float(out[slot]) * stage_rel
		for g: Array in s["boosters"]:
			for pd: Dictionary in g:
				var k := _slot_of(pd, "boosters")
				out[k] = float(out[k]) * float(pd.get("reliability", 1.0))
				command = command or PartDB.is_command(pd)
	for p: PartInstance in all:
		if PartDB.is_fairing(p.data):
			out["fairing"] = float(out["fairing"]) * _num("fairing_rel", 0.997)
	if not command:
		out["avionics"] = float(out["avionics"]) * _num("no_command_rel", 0.85)
	return out


static func _slot_of(pd: Dictionary, stage_slot: String) -> String:
	if PartDB.is_stack_decoupler(pd):
		return "fairing"
	if PartDB.is_radial_decoupler(pd):
		return "boosters"
	if String(pd.get("category", "")) in AVIONICS_CATEGORIES:
		return "avionics"
	return stage_slot


## The room for the payload, in the mission types' size units (about metres of diameter): the
## widest fairing x fairing_size, else the widest part x bare_size.
static func payload_room(all: Array) -> float:
	var widest := 0.0
	var fairing := 0.0
	for p: PartInstance in all:
		var dia := float(PartDB.size_classes.get(String(p.data.get("size", "S")), 1.25))
		if PartDB.is_fairing(p.data):
			fairing = maxf(fairing, dia)
		else:
			widest = maxf(widest, dia)
	if fairing > 0.0:
		return snappedf(fairing * _num("fairing_size", 1.0), 0.01)
	return snappedf(widest * _num("bare_size", 0.8), 0.01)


## The era rocket model (1..5) that stands in for a vessel this heavy (wet kg).
static func model_of(wet_kg: float) -> int:
	var steps: Array = cfg().get("model_wet_t", [20.0, 150.0, 400.0, 800.0])
	var m := 1
	for s in steps:
		if wet_kg / 1000.0 >= float(s):
			m += 1
	return clampi(m, 1, 5)


# ------------------------------------------------------------ performance
static func _stage_specs(stages: Array) -> Array:
	var out: Array = []
	for s: Dictionary in stages:
		var core: Array = []
		for id in s.get("core", []):
			core.append(PartDB.get_part(String(id)))
		var bl: Array = []
		for g: Array in s.get("boosters", []):
			var datas: Array = []
			for id in g:
				datas.append(PartDB.get_part(String(id)))
			bl.append(datas)
		out.append({"core": core, "boosters": bl})
	return out


## Ascent delta-v (m/s) of stage lists carrying `payload_kg`.
static func ascent_dv(stages: Array, fairing_kg: float, payload_kg: float) -> float:
	return float(VesselMath.analyze(_stage_specs(stages), payload_kg, fairing_kg, 2)["ascent_dv"])


## {"dv" km/s with the payload, "lift" t: the heaviest payload whose ascent delta-v still covers
## `dv_need_ms`} (0 when even an empty rocket falls short). Cached.
static func performance_of(stages: Array, fairing_kg: float, payload_kg: float, dv_need_ms: float) -> Dictionary:
	var key := "%d|%.1f|%.1f|%.1f" % [hash(stages), fairing_kg, payload_kg, dv_need_ms]
	if _perf_cache.has(key):
		return _perf_cache[key]
	var dv := ascent_dv(stages, fairing_kg, payload_kg)
	var lift := 0.0
	if dv_need_ms > 0.0 and ascent_dv(stages, fairing_kg, 0.0) >= dv_need_ms:
		var lo := 0.0
		var hi := maxf(payload_kg, 500.0)
		var guard := 0
		while ascent_dv(stages, fairing_kg, hi) >= dv_need_ms and guard < 14:
			lo = hi
			hi *= 2.0
			guard += 1
		for i in 10:
			var mid := (lo + hi) * 0.5
			if ascent_dv(stages, fairing_kg, mid) >= dv_need_ms:
				lo = mid
			else:
				hi = mid
		lift = lo / 1000.0
	var out := {"dv": dv / 1000.0, "lift": lift}
	if _perf_cache.size() > 256:
		_perf_cache.clear()
	_perf_cache[key] = out
	return out


## RocketDesigner.check() hook: the delta-v and lift of a hangar core for this need
## ({"dv" km/s, "lift" t}); {} for an abstract core.
static func performance(core: Dictionary, need: Dictionary) -> Dictionary:
	if not core.has("stages"):
		return {}
	return performance_of(core["stages"], float(core.get("fairing_kg", 0.0)), float(need["lift"]) * 1000.0,
		float(need["dv"]) * 1000.0)


## What a piloted flight must do for this mission (flight_verdict's line), as text.
static func goal_text(mission: Dictionary) -> String:
	var target := String(mission.get("target_id", ""))
	if target == "suborbital":
		return TranslationServer.translate("TY_HG_GOAL_SPACE")
	if target in ["leo", "sso"]:
		return TranslationServer.translate("TY_HG_GOAL_ORBIT")
	var leo := float(RocketDesigner.section("targets").get("leo", 9.4)) * 1000.0
	return TranslationServer.translate("TY_HG_GOAL_BEYOND") % TycoonHUD.fmt_int(maxf(float(mission.get("dv_needed", leo)) - leo, 0.0))


# ------------------------------------------------------------ the flight's verdict
## The launch outcome of a piloted flight (FlightWorld report) for a mission ("target_id",
## "dv_needed" m/s): {"outcome": "success" | "partial" | "fail", "reached": "none" | "space" |
## "orbit" | "target", "cause_key", "piloted": true, "flight": a short summary}.
##   suborbital  reaching space (100 km) is the mission; coming down after it is the plan
##   leo / sso   a stable orbit (the flight's own "orbit" test)
##   farther     an orbit with the delta-v left for the rest of the way (dv_needed - the LEO
##               need), or the target body's sphere reached (the Moon for lunar targets); an
##               orbit without that is a partial success
## Anything short of the mission's line is a failure: "lost" when the vehicle crashed,
## "short" when it ended the flight before getting there.
static func flight_verdict(report: Dictionary, mission: Dictionary) -> Dictionary:
	var target := String(mission.get("target_id", "leo"))
	var crashed := String(report.get("result", "")) == "crash"
	var space := float(report.get("max_alt", 0.0)) >= _num("space_alt", 100000.0)
	var orbit := bool(report.get("orbit", false))
	var leo_need := float(RocketDesigner.section("targets").get("leo", 9.4)) * 1000.0
	var beyond := maxf(float(mission.get("dv_needed", leo_need)) - leo_need, 0.0)
	var dv_left := float(report.get("dv_left", 0.0))
	var at_body := bool(report.get("reached_moon", false)) and target.begins_with("lunar")
	var reached := "none"
	if space:
		reached = "space"
	if orbit:
		reached = "orbit"
	var outcome := "fail"
	if target == "suborbital":
		if space:
			outcome = "success"
			reached = "target"
	elif target in ["leo", "sso"]:
		if orbit:
			outcome = "success"
			reached = "target"
	else:
		if at_body or (orbit and dv_left >= beyond * _num("beyond_margin", 1.0)):
			outcome = "success"
			reached = "target"
		elif orbit:
			outcome = "partial"
	var cause := ""
	if outcome == "fail":
		cause = "TY_HG_CAUSE_LOST" if crashed else "TY_HG_CAUSE_SHORT"
	return {"outcome": outcome, "reached": reached, "cause_key": cause, "piloted": true,
		"flight": {"max_alt": float(report.get("max_alt", 0.0)), "orbit": orbit, "ap": float(report.get("ap", 0.0)),
			"pe": float(report.get("pe", 0.0)), "dv_left": dv_left, "time": float(report.get("time", 0.0)),
			"result": String(report.get("result", "")), "reached": reached}}
