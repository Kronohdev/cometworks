extends CwScreen
## Payload planner (scenes/tycoon/ui/screens/payload_planner.tscn), the step after the target
## and type: which modules go on board (PayloadRules: instruments, power, comms, heaters, a
## recorder). Each module is a toggle row with its weight, power and data and, for
## instruments, what the journal knows of it here (great / good / dead weight / wrong / ?).
## On the right the six gauges (mass, energy, data, comms, budget, time) as the agency sees
## them: a hidden environment (the lunar night, the cold) is assumed away until the journal
## knows it. Red mass, energy (by day) or cash blocks Next. Then the team (project_team).
## Everything visual is in the scene; rows are copies of its hidden templates.

const ICONS := "res://ui/cometworks/icons/%s.svg"
const STATE_COLORS := {"green": CwPalette.SUCCESS, "yellow": CwPalette.WARNING, "red": CwPalette.DANGER}
const RATING_COLORS := {"great": CwPalette.AURORA_TEAL, "good": CwPalette.COMET_ICE, "useless": CwPalette.WARNING,
	"bad": CwPalette.DANGER, "": CwPalette.TEXT_DIM}
## group id -> module kinds
const GROUPS := {"Instrument": ["instrument"], "Power": ["power"], "Comms": ["comms"], "Other": ["thermal", "data"]}

var type_id := ""
var target_id := ""
var contract_id := ""
var briefing_id := ""
var staff_ids: Array[String] = []
var payload: Array[String] = []
var info_id := ""


func _ready() -> void:
	super._ready()
	%Next.pressed.connect(_next)
	%Back.pressed.connect(_back)


## args: {"type", "target", "contract_id", "briefing_id", "payload", "staff"}
func open_with(args: Dictionary) -> void:
	type_id = String(args.get("type", ""))
	target_id = String(args.get("target", ""))
	contract_id = String(args.get("contract_id", ""))
	briefing_id = String(args.get("briefing_id", ""))
	staff_ids.clear()
	for sid in args.get("staff", []):
		staff_ids.append(String(sid))
	payload.clear()
	for m in args.get("payload", []):
		payload.append(String(m))
	if payload.is_empty():
		payload = PayloadRules.default_payload(state, type_id, target_id)
	refresh()


func args_out() -> Dictionary:
	return {"type": type_id, "target": target_id, "contract_id": contract_id, "briefing_id": briefing_id,
		"payload": payload.duplicate(), "staff": staff_ids.duplicate()}


func _next() -> void:
	if plan_error() != "":
		return
	if hud:
		hud.open_screen("project_team", args_out())


func _back() -> void:
	if hud:
		hud.open_screen("new_project", args_out())
	else:
		close_screen()


func _toggle(id: String) -> void:
	payload = PayloadRules.toggle(payload, id)
	info_id = id
	refresh()


func _hover(id: String) -> void:
	info_id = id
	_fill_info()


## The plan the gauges check: the payload with the estimate, the client's budget and deadline.
func plan() -> Dictionary:
	var e := ProjectDesk.estimate(state, type_id, {}, target_id)
	var o := BriefingDesk.offer(state, briefing_id)
	var dl := -1
	if not o.is_empty():
		dl = int(o.get("deadline", -1))
	var c := ProjectDesk.contract(state, contract_id)
	if not c.is_empty():
		dl = int(c.get("deadline_week", state.weeks)) - state.weeks
	return {"type": type_id, "target": target_id, "payload": payload, "weeks": int(e["weeks"]), "dev_cost": float(e["dev_cost"]),
		"launch_cost": float(e["launch_cost"]), "budget": float(o.get("budget", 0.0)), "deadline_weeks": dl,
		"briefing_id": briefing_id}


func plan_error() -> String:
	return PayloadRules.plan_error(state, plan())


# ------------------------------------------------------------ fill
func refresh() -> void:
	if state == null or type_id == "":
		return
	%Caption.text = "%s · %s → %s" % [tr("TY_PL_CAPTION"), tr(String(state.mission_type(type_id).get("name_key", ""))),
		tr(String(state.mission_target(target_id).get("name_key", "")))]
	%Brief.visible = briefing_id != ""
	if briefing_id != "":
		%BriefGoal.text = tr(BriefingDesk.goal_key(briefing_id))
	for gid: String in GROUPS:
		_fill_group(gid)
	_fill_gauges()
	_fill_env()
	_fill_info()
	var err := plan_error()
	%Error.text = tr(err) if err != "" else ""
	%Next.disabled = err != ""


func _fill_group(gid: String) -> void:
	var avail: Array[Dictionary] = []
	var locked := 0
	for k: String in GROUPS[gid]:
		for m in PayloadRules.modules_of(k):
			if PayloadRules.is_available(state, String(m["id"])):
				avail.append(m)
			else:
				locked += 1
	var rows := copies(get_node("%" + gid + "Template"), avail.size())
	for i in avail.size():
		var m: Dictionary = avail[i]
		var id := String(m["id"])
		var b := rows[i] as Button
		b.set_meta("id", id)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: _toggle(String(b.get_meta("id", ""))))
			b.mouse_entered.connect(func() -> void: _hover(String(b.get_meta("id", ""))))
		b.set_pressed_no_signal(id in payload)
		var icon := ICONS % String(m.get("icon", "research"))
		if ResourceLoader.exists(icon):
			(b.get_node("Box/Row/Icon") as TextureRect).texture = load(icon)
		(b.get_node("Box/Row/Names/Name") as Label).text = tr(PayloadRules.name_key(id))
		(b.get_node("Box/Row/Names/Stats") as Label).text = stats_text(m)
		var rl := b.get_node("Box/Row/Rating") as Label
		if String(m.get("kind", "")) == "instrument":
			var r := Discovery.instr_rating(state, type_id, target_id, id)
			rl.text = tr("TY_JN_RATE_" + (r.to_upper() if r != "" else "UNKNOWN"))
			rl.add_theme_color_override("font_color", RATING_COLORS.get(r, CwPalette.TEXT_DIM))
		else:
			rl.text = ""
	var ll := get_node("%Locked" + gid) as Label
	ll.visible = locked > 0
	ll.text = tr("TY_PL_LOCKED") % locked


## "14 kg · 12 W · 3 Gb/wk" (what matters for the kind).
func stats_text(m: Dictionary) -> String:
	var parts: Array[String] = [tr("TY_PL_KG") % int(m.get("mass", 0))]
	match String(m.get("kind", "")):
		"instrument":
			parts.append(tr("TY_PL_W") % int(m.get("power", 0)))
			parts.append(tr("TY_PL_GBW") % float(m.get("data", 0.0)))
		"power":
			if m.has("gen"):
				parts.append(tr("TY_PL_GEN") % int(m["gen"]))
			if m.has("store"):
				parts.append(tr("TY_PL_STORE") % int(m["store"]))
		"comms":
			parts.append(tr("TY_PL_W") % int(m.get("power", 0)))
			if m.has("gain"):
				parts.append(tr("TY_PL_GAIN") % float(m["gain"]))
			if m.has("contact_mult"):
				parts.append(tr("TY_PL_CONTACT") % float(m["contact_mult"]))
		"thermal":
			parts.append(tr("TY_PL_NIGHT_W") % int(m.get("night_power", 0)))
		"data":
			parts.append(tr("TY_PL_STORAGE") % int(m.get("storage", 0)))
	return " · ".join(parts)


func _fill_gauges() -> void:
	var g := PayloadRules.gauges(state, plan())
	for gid in ["mass", "energy", "data", "comms", "budget", "time"]:
		var row := get_node("%Gauge" + gid.capitalize()) as Control
		var d: Dictionary = g[gid]
		var st := String(d["state"])
		var col: Color = STATE_COLORS.get(st, CwPalette.TEXT_DIM)
		var bar := row.get_node("Bar") as CwSegmentBar
		bar.value = clampf(0.35 + float(d["margin"]), 0.0, 1.0)
		bar.color = col
		var sl := row.get_node("State") as Label
		sl.text = tr("TY_PL_ST_" + st.to_upper())
		sl.add_theme_color_override("font_color", col)
		(row.get_node("Value") as Label).text = gauge_text(gid, d)


func gauge_text(gid: String, d: Dictionary) -> String:
	match gid:
		"mass":
			return tr("TY_PL_V_MASS") % [roundi(float(d["have"])), roundi(float(d["need"]))]
		"energy":
			var en: Dictionary = d.get("detail", {})
			if not en.get("cold_ok", true):
				return tr("TY_PL_V_COLD")
			if float(en.get("night_margin", 1.0)) < float(en.get("day_margin", 1.0)) and float(en.get("night_need", 0.0)) > 0.0:
				return tr("TY_PL_V_NIGHT") % [roundi(float(en["night_supply"])), roundi(float(en["night_need"]))]
			if en.get("battery_only", false):
				return tr("TY_PL_V_BATTERY") % [roundi(float(en["store"])), roundi(float(en["use"]))]
			return tr("TY_PL_V_ENERGY") % [roundi(float(en.get("day_gen", 0.0))), roundi(float(en.get("use", 0.0)))]
		"data":
			return tr("TY_PL_V_DATA") % [roundi(float(d["have"])), roundi(float(d["need"]))]
		"comms":
			return tr("TY_PL_V_COMMS") % [float(d["have"]), float(d["need"])]
		"budget":
			return cr(float(d["have"]))
		"time":
			if int(d.get("deadline", -1)) < 0:
				return tr("TY_PL_V_NO_DEADLINE") % roundi(float(d["have"]))
			return tr("TY_PL_V_TIME") % [roundi(float(d["have"])), int(d["deadline"])]
	return ""


func _fill_env() -> void:
	%EnvCaption.text = tr("TY_PL_ENV") % tr(String(state.mission_target(target_id).get("name_key", "")))
	%EnvLine.text = Discovery.env_text(state, target_id, briefing_id)


func _fill_info() -> void:
	if info_id == "":
		%InfoName.text = tr("TY_PL_INFO")
		%InfoDesc.text = tr("TY_PL_INFO_DESC")
		%InfoNote.text = ""
		return
	%InfoName.text = tr(PayloadRules.name_key(info_id))
	%InfoDesc.text = tr(PayloadRules.name_key(info_id) + "_DESC")
	if String(PayloadRules.module(info_id).get("kind", "")) == "instrument":
		var r := Discovery.instr_rating(state, type_id, target_id, info_id)
		%InfoNote.text = tr("TY_PL_INFO_RATED") % tr("TY_JN_RATE_" + r.to_upper()) if r != "" else tr("TY_PL_INFO_UNRATED")
	else:
		%InfoNote.text = ""
