extends Control
## New project, the objective step (scenes/tycoon/ui/screens/new_project.tscn, GDD 6.2): the
## target, then the mission type, with the compatibility once the agency has flown it and the
## ideal balance of the 4 bars once the journal has revealed it ("?" before: Discovery). It
## comes after the briefing board (briefings.tscn) with the briefing's goal on the right, or as
## a free project; accepted contracts are quick picks. Next: the payload planner
## (payload_planner.tscn), then the team (project_team.tscn) and the rocket designer, which
## starts the project. Everything visual is in the scene; lists are filled by duplicating its
## hidden templates (TargetTemplate, TypeTemplate, ContractTemplate) with TycoonHUD._copies().

const TIER_COLORS := {"great": CwPalette.AURORA_TEAL, "good": CwPalette.COMET_ICE, "poor": CwPalette.WARNING,
	"impossible": CwPalette.DANGER}

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var target_id := ""
var type_id := ""
var contract_id := ""
var briefing_id := ""
## carried through Back from the later steps
var payload: Array = []
var staff: Array = []


func _ready() -> void:
	%Close.pressed.connect(_close)
	%Cancel.pressed.connect(_close)
	%Start.pressed.connect(_start)


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	for t: Dictionary in state.mdata.get("targets", []):
		if state.mission_target_available(String(t["id"])):
			target_id = String(t["id"])
			break
	_pick_first_type()
	refresh()


## args: {"briefing_id"} plans a briefing (from the board); {"contract_id"} picks an accepted
## contract; {"target", "type", "payload", "staff"} come back from the later steps.
func open_with(args: Dictionary) -> void:
	briefing_id = String(args.get("briefing_id", briefing_id))
	payload = (args.get("payload", []) as Array).duplicate()
	staff = (args.get("staff", []) as Array).duplicate()
	if String(args.get("contract_id", "")) != "":
		contract_id = ""
		_pick_contract(String(args["contract_id"]))
		return
	target_id = String(args.get("target", target_id))
	type_id = String(args.get("type", type_id))
	if ProjectRules.compat(state.mission_type(type_id), target_id) <= 0.0:
		_pick_first_type()
	refresh()


func _close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


func args_out() -> Dictionary:
	return {"type": type_id, "target": target_id, "contract_id": contract_id, "briefing_id": briefing_id,
		"payload": payload if _same_plan() else [], "staff": staff}


## The payload carried back still fits this objective (the same type and target).
var _plan_of := ""


func _same_plan() -> bool:
	return _plan_of == "" or _plan_of == "%s|%s" % [type_id, target_id]


## Next step: the payload planner.
func _start() -> void:
	if objective_error() != "":
		return
	if hud:
		hud.open_screen("payload_planner", args_out())


## Why the objective cannot go ahead ("" when it can): a translation key.
func objective_error() -> String:
	if type_id == "" or target_id == "":
		return "TY_PJ_ERR_PICK"
	if not state.mission_target_available(target_id):
		return "TY_PJ_ERR_TARGET"
	if not state.mission_type_available(type_id):
		return "TY_PJ_ERR_TYPE"
	if ProjectRules.compat(state.mission_type(type_id), target_id) <= 0.0:
		return "TY_PJ_ERR_IMPOSSIBLE"
	if RocketDesigner.default_design(state, type_id, target_id).is_empty():
		return "TY_PJ_ERR_NO_ROCKET"
	return ""


func _pick_target(id: String) -> void:
	if _plan_of == "":
		_plan_of = "%s|%s" % [type_id, target_id]
	target_id = id
	var c := ProjectDesk.contract(state, contract_id)
	if not c.is_empty() and String(c.get("target", "")) != id:
		contract_id = ""
	if ProjectRules.compat(state.mission_type(type_id), target_id) <= 0.0:
		_pick_first_type()
	refresh()


func _pick_type(id: String) -> void:
	if _plan_of == "":
		_plan_of = "%s|%s" % [type_id, target_id]
	type_id = id
	var c := ProjectDesk.contract(state, contract_id)
	if not c.is_empty() and String(c.get("type", "")) != id:
		contract_id = ""
	refresh()


func _pick_contract(id: String) -> void:
	if contract_id == id:
		contract_id = ""
	else:
		var c := ProjectDesk.contract(state, id)
		contract_id = id
		briefing_id = ""  # a contract is its own client
		target_id = String(c.get("target", target_id))
		type_id = String(c.get("type", type_id))
	refresh()


## The first available type that can fly to the target, "" if none.
func _pick_first_type() -> void:
	type_id = ""
	for t: Dictionary in state.mdata.get("types", []):
		if state.mission_type_available(String(t["id"])) and ProjectRules.compat(t, target_id) > 0.0:
			type_id = String(t["id"])
			return


# ------------------------------------------------------------ fill
func refresh() -> void:
	if state == null:
		return
	_fill_targets()
	_fill_types()
	_fill_ideal()
	_fill_brief()
	_fill_contracts()
	_fill_estimate()


## Hooks a list button once (copies are reused between refreshes).
static func _wire(b: BaseButton, f: Callable) -> void:
	if not b.has_meta("wired"):
		b.set_meta("wired", true)
		b.pressed.connect(func() -> void: f.call(String(b.get_meta("id", ""))))


func _fill_targets() -> void:
	var avail: Array[Dictionary] = []
	var locked := 0
	for t: Dictionary in state.mdata.get("targets", []):
		if state.mission_target_available(String(t["id"])):
			avail.append(t)
		else:
			locked += 1
	var rows := TycoonHUD._copies(%TargetTemplate, avail.size())
	for i in avail.size():
		var b := rows[i] as Button
		var id := String(avail[i]["id"])
		b.set_meta("id", id)
		_wire(b, _pick_target)
		b.text = tr(String(avail[i].get("name_key", id)))
		b.set_pressed_no_signal(id == target_id)
		var n := 0
		for t: Dictionary in state.mdata.get("types", []):
			if state.mission_type_available(String(t["id"])) and ProjectRules.compat(t, id) > 0.0:
				n += 1
		(b.get_node("Tag") as Label).text = tr("TY_PJ_N_TYPES") % n
	%TargetsLocked.visible = locked > 0
	%TargetsLocked.text = tr("TY_PJ_LOCKED_MORE") % locked


func _fill_types() -> void:
	var avail: Array[Dictionary] = []
	var locked := 0
	for t: Dictionary in state.mdata.get("types", []):
		if state.mission_type_available(String(t["id"])):
			avail.append(t)
		else:
			locked += 1
	if target_id == "":
		avail.clear()
	var rows := TycoonHUD._copies(%TypeTemplate, avail.size())
	for i in avail.size():
		var t: Dictionary = avail[i]
		var b := rows[i] as Button
		var id := String(t["id"])
		b.set_meta("id", id)
		_wire(b, _pick_type)
		b.text = tr(String(t.get("name_key", id)))
		var mult := ProjectRules.compat(t, target_id)
		var tier := ProjectRules.compat_tier(mult)
		b.disabled = mult <= 0.0
		b.set_pressed_no_signal(id == type_id and not b.disabled)
		var tag := b.get_node("Tag") as Label
		if mult > 0.0 and not Discovery.compat_known(state, id, target_id):
			tag.text = "?"
			tag.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
		else:
			var star := " ★" if Discovery.combo(state, id, target_id).get("great", false) else ""
			tag.text = tr("TY_PJ_COMPAT_" + tier.to_upper()) + star
			tag.add_theme_color_override("font_color", TIER_COLORS[tier])
	%TypeHint.visible = target_id == ""
	%TypesLocked.visible = locked > 0 and target_id != ""
	%TypesLocked.text = tr("TY_PJ_LOCKED_MORE") % locked


func _fill_ideal() -> void:
	var mt := state.mission_type(type_id)
	var ratio: Array = mt.get("ratio", [0.0, 0.0, 0.0, 0.0])
	var client := BriefingDesk.ratio(BriefingDesk.briefing(briefing_id)).size() == 4
	var known := not mt.is_empty() and Discovery.ratio_known(state, type_id) and not client
	var rows: Array[Node] = [%IdealEng, %IdealSci, %IdealOps, %IdealRel]
	for b in 4:
		var v := float(ratio[b]) if known else 0.0
		(rows[b].get_node("Bar") as CwSegmentBar).value = v / 0.5  # 50% fills the meter
		(rows[b].get_node("Value") as Label).text = "%d%%" % roundi(v * 100.0) if known else "?"
	%IdealHint.visible = not mt.is_empty() and not known
	if client:
		%IdealHint.text = tr("TY_PJ_IDEAL_CLIENT")
	elif not known and not mt.is_empty():
		%IdealHint.text = tr("TY_PJ_IDEAL_HIDDEN") % [Discovery.attempts(state, type_id), int(BriefingDesk.disc().get("reveal_ratio_after", 2))]
	var cv := %CompatValue as Label
	if mt.is_empty() or target_id == "":
		cv.text = "—"
		cv.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
		%TypeName.text = tr("TY_PJ_ERR_PICK")
		%TypeFacts.text = ""
		return
	%TypeName.text = "%s · %s" % [tr(String(mt.get("name_key", ""))), tr(String(state.mission_target(target_id).get("name_key", "")))]
	%TypeFacts.text = "%s · %s" % [String(mt.get("code", "")), tr("TY_WEEKS") % int(mt.get("weeks", 3))]
	var mult := ProjectRules.compat(mt, target_id)
	var tier := ProjectRules.compat_tier(mult)
	if mult > 0.0 and not Discovery.compat_known(state, type_id, target_id):
		cv.text = tr("TY_PJ_COMPAT_UNKNOWN")
		cv.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
	else:
		cv.text = "%s  ×%.2f" % [tr("TY_PJ_COMPAT_" + tier.to_upper()), mult]
		cv.add_theme_color_override("font_color", TIER_COLORS[tier])


func _fill_brief() -> void:
	var o := BriefingDesk.offer(state, briefing_id)
	%BriefBox.visible = briefing_id != "" and not o.is_empty()
	if %BriefBox.visible:
		%BriefGoal.text = tr(BriefingDesk.goal_key(briefing_id))
		%BriefTerms.text = "%s · %s" % [tr("TY_WEEKS") % int(o.get("deadline", 0)), TycoonHUD.fmt_cr(float(o.get("budget", 0.0)))]


func _fill_contracts() -> void:
	var list := ProjectDesk.open_contracts(state)
	var rows := TycoonHUD._copies(%ContractTemplate, list.size())
	for i in list.size():
		var c: Dictionary = list[i]
		var b := rows[i] as Button
		b.set_meta("id", String(c.get("id", "")))
		_wire(b, _pick_contract)
		var sponsor := tr(String(c.get("sponsor_key", ""))) if c.has("sponsor_key") else String(c.get("id", ""))
		b.text = "%s · %s · %s" % [sponsor, tr(String(state.mission_type(String(c.get("type", ""))).get("name_key", ""))),
			tr(String(state.mission_target(String(c.get("target", ""))).get("name_key", "")))]
		(b.get_node("Tag") as Label).text = TycoonHUD.fmt_cr(float(c.get("reward", 0.0)))
		b.set_pressed_no_signal(String(c.get("id", "")) == contract_id)
	%NoContracts.visible = list.is_empty()
	if briefing_id != "":
		%ProjectKind.text = tr(BriefingDesk.title_key(briefing_id))
	else:
		%ProjectKind.text = tr("TY_PJ_FOR_CONTRACT") % contract_id if contract_id != "" else tr("TY_PJ_FREE_PROJECT")


func _fill_estimate() -> void:
	var err := objective_error()
	if type_id == "":
		for l: Label in [%EstWeeks, %EstDev, %EstLaunch, %EstTotal]:
			l.text = "—"
	else:
		var e := ProjectDesk.estimate(state, type_id, {}, target_id)
		%EstWeeks.text = "%d" % int(e["weeks"])
		%EstDev.text = TycoonHUD.fmt_cr(float(e["dev_cost"]))
		%EstLaunch.text = TycoonHUD.fmt_cr(float(e["launch_cost"]))
		%EstTotal.text = TycoonHUD.fmt_cr(float(e["total"]))
		%EstTotal.add_theme_color_override("font_color", CwPalette.DANGER if float(e["total"]) > state.cash else CwPalette.COMET_ICE)
	%CashNow.text = TycoonHUD.fmt_cr(state.cash)
	%Error.text = tr(err) if err != "" else ""
	%Start.disabled = err != ""
