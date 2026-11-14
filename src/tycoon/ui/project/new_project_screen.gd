extends Control
## New project screen (scenes/tycoon/ui/screens/new_project.tscn, GDD 6.2): objective first
## (target, then mission type, with the compatibility once the agency has flown it and the
## ideal balance of the 4 bars), accepted contracts as quick picks, the team by profession,
## the cost / weeks estimate (with the default rocket) and "Choose the rocket", which opens the
## rocket designer (rocket_designer.tscn, E2) where the project starts. Everything visual is in the scene; lists are filled by
## duplicating its hidden templates (TargetTemplate, TypeTemplate, ContractTemplate,
## StaffTemplate) with TycoonHUD._copies().

const TIER_COLORS := {"great": CwPalette.AURORA_TEAL, "good": CwPalette.COMET_ICE, "poor": CwPalette.WARNING,
	"impossible": CwPalette.DANGER}

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var target_id := ""
var type_id := ""
var contract_id := ""
## staff id -> true for the Cometlings picked for the team
var picked := {}
## once the player toggles someone, the team is theirs (no more automatic picks)
var _team_touched := false


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


## args: {"contract_id"} picks an accepted contract; {"target", "type"} preselects;
## {"staff"} brings back a team (the rocket designer's Back).
func open_with(args: Dictionary) -> void:
	if args.has("staff"):
		picked.clear()
		for sid in args["staff"]:
			picked[String(sid)] = true
		_team_touched = true
	if String(args.get("contract_id", "")) != "":
		contract_id = ""
		_pick_contract(String(args["contract_id"]))
		return
	target_id = String(args.get("target", target_id))
	type_id = String(args.get("type", type_id))
	refresh()


func _close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


## Next step: the rocket designer, which starts the project.
func _start() -> void:
	var ids: Array[String] = []
	for m in state.staff:
		if picked.get(String(m["id"]), false) and String(m.get("assigned", "")) == "":
			ids.append(String(m["id"]))
	if ProjectDesk.start_error(state, type_id, target_id, ids) != "":
		return
	if hud:
		hud.open_screen("rocket_designer", {"type": type_id, "target": target_id, "contract_id": contract_id, "staff": ids})


func _pick_target(id: String) -> void:
	target_id = id
	var c := ProjectDesk.contract(state, contract_id)
	if not c.is_empty() and String(c.get("target", "")) != id:
		contract_id = ""
	if ProjectRules.compat(state.mission_type(type_id), target_id) <= 0.0:
		_pick_first_type()
	refresh()


func _pick_type(id: String) -> void:
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


## Suggests a team: the ideal number of free Cometlings, best suited first (affinity of their
## profession for the type's ideal balance, times skill).
func _auto_team() -> void:
	picked.clear()
	if type_id == "":
		return
	var probe := MissionProject.new()
	probe.type_id = type_id
	var ratio := probe.ideal(state)
	var scored: Array = []
	for m in ProjectDesk.free_staff(state):
		var prof := state.profession(String(m.get("profession", "")))
		var fit := 0.0
		for b in 4:
			fit += ratio[b] * ProjectRules.affinity(prof, ProjectRules.BARS[b], state.pdata)
		scored.append([fit * (0.4 + 0.6 * float(m.get("skill", 0.5))), String(m["id"])])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for i in mini(probe.ideal_team(state), scored.size()):
		picked[scored[i][1]] = true


# ------------------------------------------------------------ fill
func refresh() -> void:
	if state == null:
		return
	if not _team_touched:
		_auto_team()
	_fill_targets()
	_fill_types()
	_fill_ideal()
	_fill_contracts()
	_fill_team()
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
		if mult > 0.0 and not ProjectDesk.compat_known(state, id, target_id):
			tag.text = "?"
			tag.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
		else:
			tag.text = tr("TY_PJ_COMPAT_" + tier.to_upper())
			tag.add_theme_color_override("font_color", TIER_COLORS[tier])
	%TypeHint.visible = target_id == ""
	%TypesLocked.visible = locked > 0 and target_id != ""
	%TypesLocked.text = tr("TY_PJ_LOCKED_MORE") % locked


func _fill_ideal() -> void:
	var mt := state.mission_type(type_id)
	var ratio: Array = mt.get("ratio", [0.0, 0.0, 0.0, 0.0])
	var rows: Array[Node] = [%IdealEng, %IdealSci, %IdealOps, %IdealRel]
	for b in 4:
		var v := float(ratio[b]) if not mt.is_empty() else 0.0
		(rows[b].get_node("Bar") as CwSegmentBar).value = v / 0.5  # 50% fills the meter
		(rows[b].get_node("Value") as Label).text = "%d%%" % roundi(v * 100.0) if not mt.is_empty() else "—"
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
	if mult > 0.0 and not ProjectDesk.compat_known(state, type_id, target_id):
		cv.text = tr("TY_PJ_COMPAT_UNKNOWN")
		cv.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
	else:
		cv.text = "%s  ×%.2f" % [tr("TY_PJ_COMPAT_" + tier.to_upper()), mult]
		cv.add_theme_color_override("font_color", TIER_COLORS[tier])


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
	%ProjectKind.text = tr("TY_PJ_FOR_CONTRACT") % contract_id if contract_id != "" else tr("TY_PJ_FREE_PROJECT")


func _fill_team() -> void:
	var rows := TycoonHUD._copies(%StaffTemplate, state.staff.size())
	for i in state.staff.size():
		var m: Dictionary = state.staff[i]
		var b := rows[i] as Button
		var id := String(m["id"])
		b.set_meta("id", id)
		_wire(b, _toggle_staff)
		var prof := state.profession(String(m.get("profession", "")))
		var busy := String(m.get("assigned", ""))
		b.disabled = busy != ""
		b.set_pressed_no_signal(picked.get(id, false) and busy == "")
		(b.get_node("Row/Tab") as ColorRect).color = CwPalette.BARS.get(String(prof.get("primary", "eng")), CwPalette.LINE)
		(b.get_node("Row/Names/Name") as Label).text = String(m.get("name", id))
		(b.get_node("Row/Names/Prof") as Label).text = tr(String(prof.get("name_key", "")))
		(b.get_node("Row/Level") as Label).text = tr("TY_PJ_LEVEL_SHORT") % int(m.get("level", 1)) \
			if busy == "" else tr("TY_PJ_BUSY_ON") % busy


func _toggle_staff(id: String) -> void:
	_team_touched = true
	picked[id] = not picked.get(id, false)
	refresh()


func _fill_estimate() -> void:
	var ids: Array[String] = []
	for m in state.staff:
		if picked.get(String(m["id"]), false) and String(m.get("assigned", "")) == "":
			ids.append(String(m["id"]))
	var err := "TY_PJ_ERR_PICK" if type_id == "" or target_id == "" else ProjectDesk.start_error(state, type_id, target_id, ids)
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
	%TeamCount.text = "%d / %d" % [ids.size(), ProjectDesk.free_staff(state).size()]
	%CashNow.text = TycoonHUD.fmt_cr(state.cash)
	%TeamIdeal.visible = type_id != ""
	if type_id != "":
		var probe := MissionProject.new()
		probe.type_id = type_id
		%TeamIdeal.text = tr("TY_PJ_TEAM_IDEAL") % probe.ideal_team(state)
	%Error.text = tr(err) if err != "" else ""
	%Start.disabled = err != ""
