class_name RoverDesign
extends RefCounted
## Rules of the rover and robot builder (data/tycoon/rovers.json). A design is plain data,
## saved as it is in the career (RoverGarage) and in a mission's payload:
##   {"name": String, "chassis": chassis id, "parts": [part ids]}
## Parts with a "payload" id ARE the payload planner's modules (payload.json), so their mass,
## power and cost come from there; the rover's own parts (chassis, arm, drone, weather station,
## sample cache) travel in the plan as one payload module whose id encodes them:
##   "rover:<chassis>:<own part,own part>@<name, uri-encoded>"   (payload_code / from_payload)
## so a project, its history entry and its mission in operation all know the rover with no new
## save field. PayloadRules asks code_module() for that module's numbers.
## Static functions; no scene access except assemble() (the voxel preview / vehicle).

const PATH := "res://data/tycoon/rovers.json"
const CODE_PREFIX := "rover:"
const ERRORS: Array[String] = ["RV_ERR_NO_CHASSIS", "RV_ERR_LOCKED", "RV_ERR_DUPLICATE", "RV_ERR_NO_POWER",
	"RV_ERR_NO_ANTENNA", "RV_ERR_BAYS", "RV_ERR_POWER_BAYS"]

static var _data: Dictionary = {}
static var _parts: Dictionary = {}
static var _chassis: Dictionary = {}
static var _code_cache: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var v: Variant = JSON.parse_string(f.get_as_text())
			_data = v if v is Dictionary else {}
		_parts.clear()
		_chassis.clear()
		for c: Dictionary in _data.get("chassis", []):
			_chassis[String(c["id"])] = c
		for p: Dictionary in _data.get("parts", []):
			_parts[String(p["id"])] = p
	return _data


static func rules() -> Dictionary:
	return data().get("rules", {})


static func time_scale() -> float:
	return float(data().get("time_scale", 20.0))


static func chassis_list() -> Array:
	return data().get("chassis", [])


static func chassis(id: String) -> Dictionary:
	data()
	return _chassis.get(id, {})


static func part(id: String) -> Dictionary:
	data()
	if _chassis.has(id):
		var c: Dictionary = _chassis[id].duplicate()
		c["slot"] = "chassis"
		return c
	return _parts.get(id, {})


static func parts_of(slot: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if slot == "chassis":
		for c: Dictionary in chassis_list():
			out.append(part(String(c["id"])))
		return out
	for p: Dictionary in data().get("parts", []):
		if String(p.get("slot", "")) == slot:
			out.append(p)
	return out


static func body(body_id: String) -> Dictionary:
	return (data().get("bodies", {}) as Dictionary).get(body_id, {"sun": 1.0, "air": false, "delay_s": 1.0})


static func name_key(id: String) -> String:
	return "RV_PART_" + id.to_upper()


## A part's numbers: mass, power (W used), gen (W), store (Wh), data, cost, warm. Payload parts
## read the payload planner's module; the rover's own read rovers.json.
static func part_stats(id: String) -> Dictionary:
	var p := part(id)
	var src := p
	var pid := String(p.get("payload", ""))
	if pid != "":
		src = PayloadRules.module(pid)
	return {"mass": float(src.get("mass", 0.0)), "power": float(src.get("power", 0.0)), "gen": float(src.get("gen", 0.0)),
		"store": float(src.get("store", 0.0)), "data": float(src.get("data", 0.0)), "cost": float(src.get("cost", 0.0)),
		"warm": bool(src.get("warm", false)), "gain": float(src.get("gain", 0.0))}


## Can the agency build this part? (state null = the dev sandbox: everything)
static func is_available(state: TycoonState, id: String) -> bool:
	var p := part(id)
	if p.is_empty():
		return false
	if state == null:
		return true
	var pid := String(p.get("payload", ""))
	if pid != "" and not PayloadRules.is_available(state, pid):
		return false
	var opt := String(p.get("option", ""))
	if opt != "" and not bool(state.unlocked.get("option:" + opt, false)):
		return false
	var tech := String(p.get("tech", ""))
	if tech != "" and not bool(state.unlocked.get(tech, false)):
		return false
	return true


## The research that opens a part ("" = there from the start).
static func tech_for(id: String) -> String:
	var p := part(id)
	if p.has("tech"):
		return String(p["tech"])
	var pid := String(p.get("payload", ""))
	return PayloadRules.tech_for(pid) if pid != "" else ""


# ------------------------------------------------------------ designs
static func make(design_name: String, chassis_id: String, part_ids: Array) -> Dictionary:
	data()
	var parts: Array[String] = []
	for x in part_ids:
		if not String(x) in parts and not part(String(x)).is_empty() and not _chassis.has(String(x)):
			parts.append(String(x))
	return {"name": design_name, "chassis": chassis_id, "parts": parts}


static func starter(design_name := "") -> Dictionary:
	var s: Dictionary = data().get("starter", {})
	var n := design_name if design_name != "" else String(TranslationServer.translate(String(s.get("name_key", "RV_STARTER_NAME"))))
	return make(n, String(s.get("chassis", "wheels4")), s.get("parts", []))


static func normalize(d: Dictionary) -> Dictionary:
	return make(String(d.get("name", "")), String(d.get("chassis", "")), d.get("parts", []))


static func parts_in(d: Dictionary, slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in d.get("parts", []):
		if String(part(String(id)).get("slot", "")) == slot:
			out.append(String(id))
	return out


static func has_part(d: Dictionary, id: String) -> bool:
	return String(d.get("chassis", "")) == id or id in (d.get("parts", []) as Array)


## Adds or removes a part (a chassis replaces the chassis, an antenna the antenna).
static func toggle(d: Dictionary, id: String) -> Dictionary:
	var out := normalize(d)
	var p := part(id)
	if p.is_empty():
		return out
	if String(p["slot"]) == "chassis":
		out["chassis"] = id
		return out
	var parts: Array = out["parts"]
	if id in parts:
		parts.erase(id)
		return out
	if String(p["slot"]) == "comms":
		for x in parts_in(out, "comms"):
			parts.erase(x)
	parts.append(id)
	return out


## Translation keys of what is wrong with a design (empty = it can be built).
static func validate(d: Dictionary, state: TycoonState = null) -> Array[String]:
	var errs: Array[String] = []
	var ch := chassis(String(d.get("chassis", "")))
	if ch.is_empty():
		errs.append("RV_ERR_NO_CHASSIS")
	var seen := {}
	for id in [String(d.get("chassis", ""))] + Array(d.get("parts", [])):
		if String(id) == "":
			continue
		if not is_available(state, String(id)):
			if not "RV_ERR_LOCKED" in errs:
				errs.append("RV_ERR_LOCKED")
		if seen.has(id) and not "RV_ERR_DUPLICATE" in errs:
			errs.append("RV_ERR_DUPLICATE")
		seen[id] = true
	var st := stats(d)
	if st["gen"] <= 0.0 and st["store"] <= 0.0:
		errs.append("RV_ERR_NO_POWER")
	if parts_in(d, "comms").is_empty():
		errs.append("RV_ERR_NO_ANTENNA")
	if not ch.is_empty():
		if parts_in(d, "instrument").size() > int(ch.get("bays", 3)):
			errs.append("RV_ERR_BAYS")
		if parts_in(d, "power").size() > int(ch.get("power_bays", 2)):
			errs.append("RV_ERR_POWER_BAYS")
	return errs


static func is_valid(d: Dictionary, state: TycoonState = null) -> bool:
	return validate(d, state).is_empty()


## The tools (surface actions) of a design: photo, scan, drill, sample, weather, drone (+ hop).
static func tools(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in d.get("parts", []):
		var t := String(part(String(id)).get("tool", ""))
		if t != "" and not t in out:
			out.append(t)
	if chassis(String(d.get("chassis", ""))).has("hop"):
		out.append("hop")
	return out


static func has_tool(d: Dictionary, tool: String) -> bool:
	return tool in tools(d)


## Plain-language numbers of a design on a body:
## {"mass", "cost", "use" (W idle + instruments), "drive" (W driving), "gen" (W full sun),
##  "gen_here" (W on this body's light), "rtg" (W), "store" (Wh), "speed" (m/s), "climb" (deg),
##  "step" (m), "range_km" (battery only, -1 = endless: the panels / RTG run it), "science",
##  "tools", "warm", "needs_air", "drone_ok", "sample_capacity", "gain", "data", "delay_s"}
static func stats(d: Dictionary, body_id := "moon") -> Dictionary:
	var ch := chassis(String(d.get("chassis", "")))
	var r := rules()
	var mass := float(ch.get("mass", 0.0))
	var cost := float(ch.get("cost", 0.0))
	var use := float(r.get("idle_power", 4.0))
	var gen := 0.0
	var rtg := 0.0
	var store := 0.0
	var dat := 0.0
	var gain := 0.0
	var warm := false
	var sci := 0.0
	var n_tools := 0
	var needs_air := false
	var capacity := 0
	for id in d.get("parts", []):
		var p := part(String(id))
		if p.is_empty():
			continue
		var s := part_stats(String(id))
		mass += s["mass"]
		cost += s["cost"]
		# instruments sleep between uses (their power is spent per use, RoverController.TOOL_WH)
		use += s["power"] * (float(r.get("instrument_idle", 0.1)) if String(p.get("slot", "")) == "instrument" else 1.0)
		store += s["store"]
		dat += s["data"]
		gain = maxf(gain, s["gain"])
		if s["warm"] and s["gen"] > 0.0:
			rtg += s["gen"]
		else:
			gen += s["gen"]
		warm = warm or s["warm"]
		if p.has("science"):
			sci += float(p["science"])
			n_tools += 1
		needs_air = needs_air or bool(p.get("needs_air", false))
		capacity += int(p.get("capacity", 0))
	if n_tools >= int(r.get("min_tools_for_bonus", 2)):
		sci *= 1.0 + float(r.get("tool_bonus", 0.15)) * (n_tools - 1)
	var b := body(body_id)
	var gen_here := gen * float(b.get("sun", 1.0)) + rtg
	var drive := float(ch.get("drive_power", 0.0)) + use
	var speed := float(ch.get("speed", 0.0))
	var range_km := -1.0
	if gen_here < drive:
		var hours := store / maxf(drive - gen_here, 0.001)
		range_km = hours * 3600.0 * speed / 1000.0
	var air := bool(b.get("air", false))
	return {"mass": mass, "cost": cost, "use": use, "drive": drive, "gen": gen + rtg, "gen_here": gen_here, "rtg": rtg,
		"store": store, "speed": speed, "climb": float(ch.get("climb", 0.0)), "step": float(ch.get("step", 0.0)),
		"range_km": range_km, "science": sci, "tools": tools(d), "warm": warm, "needs_air": needs_air,
		"drone_ok": air, "sample_capacity": capacity, "gain": gain, "data": dat,
		"delay_s": float(b.get("delay_s", 1.0)), "hop": ch.get("hop", {})}


# ------------------------------------------------------------ the payload link
## The payload module id that carries the rover's own parts.
static func payload_code(d: Dictionary) -> String:
	var own: Array[String] = []
	for id in d.get("parts", []):
		if String(part(String(id)).get("payload", "")) == "":
			own.append(String(id))
	return "%s%s:%s@%s" % [CODE_PREFIX, String(d.get("chassis", "")), ",".join(own), String(d.get("name", "")).uri_encode()]


static func is_code(id: String) -> bool:
	return id.begins_with(CODE_PREFIX)


## The payload of a design: its payload-planner modules plus its rover module.
static func payload_ids(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in d.get("parts", []):
		var pid := String(part(String(id)).get("payload", ""))
		if pid != "" and not pid in out:
			out.append(pid)
	out.append(payload_code(d))
	return out


## Replaces the rover in a payload (other modules the player added stay; the design's payload
## modules are added, an antenna replaces the antenna).
static func apply_to_payload(payload: Array, d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for x in payload:
		if not is_code(String(x)):
			out.append(String(x))
	for pid in payload_ids(d):
		if is_code(pid):
			out.append(pid)
		elif not pid in out:
			out = PayloadRules.toggle(out, pid)
	return out


## The design a payload carries ({} when it carries no rover). Its parts: the rover module's own
## parts plus every payload module that is a rover part.
static func from_payload(payload: Array) -> Dictionary:
	var code := ""
	for x in payload:
		if is_code(String(x)):
			code = String(x)
			break
	if code == "":
		return {}
	var d := decode(code)
	var parts: Array = d["parts"]
	for x in payload:
		for p: Dictionary in data().get("parts", []):
			if String(p.get("payload", "")) == String(x) and not String(p["id"]) in parts:
				parts.append(String(p["id"]))
	return d


## {"name", "chassis", "parts": own parts} of a rover module id.
static func decode(code: String) -> Dictionary:
	var body_s := code.substr(CODE_PREFIX.length())
	var at := body_s.find("@")
	var nm := body_s.substr(at + 1).uri_decode() if at >= 0 else ""
	var head := body_s.substr(0, at) if at >= 0 else body_s
	var bits := head.split(":")
	var ch := bits[0] if bits.size() > 0 else ""
	var own: Array = []
	if bits.size() > 1 and bits[1] != "":
		for x in bits[1].split(","):
			own.append(x)
	return make(nm, ch, own)


## The payload-planner module of a rover id: the chassis and the rover's own parts.
static func code_module(code: String) -> Dictionary:
	if _code_cache.has(code):
		return _code_cache[code]
	var d := decode(code)
	var ch := chassis(String(d["chassis"]))
	var m := {"id": code, "kind": "rover", "icon": String(ch.get("icon", "build")), "mass": float(ch.get("mass", 0.0)),
		"power": 0.0, "data": 0.0, "cost": float(ch.get("cost", 0.0)), "tech": String(ch.get("tech", ""))}
	for id in d["parts"]:
		var s := part_stats(String(id))
		m["mass"] = float(m["mass"]) + s["mass"]
		m["power"] = float(m["power"]) + s["power"]
		m["data"] = float(m["data"]) + s["data"]
		m["cost"] = float(m["cost"]) + s["cost"]
	if ch.is_empty():
		m = {}
	_code_cache[code] = m
	return m


## Can the agency build the rover of this module id?
static func code_available(state: TycoonState, code: String) -> bool:
	var d := decode(code)
	if chassis(String(d["chassis"])).is_empty():
		return false
	for id in [String(d["chassis"])] + Array(d["parts"]):
		if not is_available(state, String(id)):
			return false
	return true


# ------------------------------------------------------------ voxel look
## Builds the design's voxel model under `root` from the editor-authored part scenes: the chassis
## scene, then each part on the first free Marker3D of its "mounts" (chassis node "Mounts/<name>").
## Returns the chassis node (null without a chassis). Old children of root are freed.
static func assemble(d: Dictionary, root: Node3D) -> Node3D:
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	var ch := chassis(String(d.get("chassis", "")))
	if ch.is_empty() or not ResourceLoader.exists(String(ch.get("scene", ""))):
		return null
	var body_node := (load(String(ch["scene"])) as PackedScene).instantiate() as Node3D
	root.add_child(body_node)
	var used := {}
	for id in d.get("parts", []):
		var p := part(String(id))
		var path := String(p.get("scene", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var mount: Node3D = null
		for mname in p.get("mounts", []):
			var mk := body_node.get_node_or_null("Mounts/" + String(mname)) as Node3D
			if mk and not used.has(String(mname)):
				mount = mk
				used[String(mname)] = true
				break
		if mount == null:
			continue
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		inst.name = "Part_" + String(id)
		mount.add_child(inst)
	return body_node
