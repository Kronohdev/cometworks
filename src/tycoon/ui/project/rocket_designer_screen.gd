extends CwScreen
## Rocket designer (scenes/tycoon/ui/screens/rocket_designer.tscn, E2 / GDD 8.2): the step after
## New project (target, type and team chosen) and the Design Review's "change rocket". On the
## left the agency's rocket families (reused with their flight heritage) and the Cometlings'
## three proposals (Barata, Equilibrada, Robusta: RocketDesigner.proposals); in the middle one
## row per slot with the components research has unlocked; on the right the voxel rocket
## turning (a DesignedRocket in a SubViewport), the "pode chegar / não chega" check (delta-v,
## lift, fairing room), cost per flight, build weeks, reliability and the family's name.
## Everything visual is in the scene; rows are copies of its hidden templates.

const STATE_COLORS := {"green": CwPalette.AURORA_TEAL, "yellow": CwPalette.WARNING, "red": CwPalette.DANGER}
const KIND_KEYS := {"cheap": "TY_RK_PROP_CHEAP", "balanced": "TY_RK_PROP_BALANCED", "robust": "TY_RK_PROP_ROBUST"}

## "new" (from New project: Start starts the project) or "change" (from the Design Review)
var mode := "new"
var type_id := ""
var target_id := ""
var contract_id := ""
var staff_ids: Array[String] = []
var project_id := ""
## the design on the bench (slot -> component id)
var parts: Dictionary = {}
## the family these parts are ("" = a new design)
var family_id := ""
var _name_touched := false
var _spin := 0.0

@onready var _preview: DesignedRocket = %PreviewRocket


func _ready() -> void:
	super._ready()
	%Back.pressed.connect(_back)
	%Start.pressed.connect(_start)
	%Save.pressed.connect(_save)
	%FamilyName.text_changed.connect(func(_t: String) -> void:
		_name_touched = true
		_fill_footer())


## args: {"type", "target", "contract_id", "staff"} from New project, or {"project_id"} from the
## Design Review (change the rocket of a waiting project).
func open_with(args: Dictionary) -> void:
	if args.has("project_id"):
		mode = "change"
		project_id = String(args["project_id"])
		var p := ProjectDesk.find(state, project_id)
		if p == null:
			close_screen()
			return
		type_id = p.type_id
		target_id = p.target_id
		parts = RocketDesigner.normalize(p.rocket.get("parts", {}))
		family_id = String(p.rocket.get("family", ""))
	else:
		mode = "new"
		type_id = String(args.get("type", ""))
		target_id = String(args.get("target", ""))
		contract_id = String(args.get("contract_id", ""))
		staff_ids.clear()
		for sid in args.get("staff", []):
			staff_ids.append(String(sid))
		var d := RocketDesigner.default_design(state, type_id, target_id)
		parts = RocketDesigner.normalize(d.get("parts", {}))
		family_id = String(d.get("family", ""))
	_sync_family()
	refresh()


func _process(delta: float) -> void:
	_spin += delta * 0.5
	var tt := get_node_or_null("%Turntable") as Node3D
	if tt:
		tt.rotation.y = _spin


# ------------------------------------------------------------ actions
func _design() -> Dictionary:
	return {"parts": parts.duplicate(), "family": family_id, "name": String(%FamilyName.text).strip_edges()}


func _start() -> void:
	if mode == "change":
		if ProjectDesk.change_rocket(state, project_id, _design()):
			var p := ProjectDesk.find(state, project_id)
			if p and p.review_state == "waiting" and hud:
				hud.open_screen("design_review", {"project_id": project_id})
			else:
				close_screen()
		return
	# start_project emits project_phase_started: ProjectFlow opens the phase screen when this closes
	var p := ProjectDesk.start_project(state, type_id, target_id, staff_ids, contract_id, _design())
	if p and hud and hud.current_screen() == "rocket_designer":
		hud.close_screen()


func _back() -> void:
	if hud == null:
		close_screen()
	elif mode == "change":
		hud.open_screen("design_review", {"project_id": project_id})
	else:
		hud.open_screen("new_project", {"target": target_id, "type": type_id, "contract_id": contract_id, "staff": staff_ids})


func _save() -> void:
	var fam := RocketFamilies.ensure(state, parts, String(%FamilyName.text))
	family_id = String(fam["id"])
	_name_touched = false
	state.changed.emit()


func _pick_family(id: String) -> void:
	var f := RocketFamilies.find(state, id)
	if f.is_empty():
		return
	parts = RocketDesigner.normalize(f["parts"])
	family_id = id
	_name_touched = false
	refresh()


func _pick_proposal(kind: String) -> void:
	for pr in RocketDesigner.proposals(state, type_id, target_id):
		if String(pr["kind"]) == kind:
			parts = RocketDesigner.normalize(pr["parts"])
	_sync_family()
	refresh()


func _pick_part(slot_id: String, comp_id: String) -> void:
	parts[slot_id] = comp_id
	_sync_family()
	refresh()


## The family of the parts on the bench, if they are one.
func _sync_family() -> void:
	var f := RocketFamilies.find_parts(state, parts)
	family_id = String(f.get("id", ""))
	if not _name_touched:
		%FamilyName.text = String(f["name"]) if not f.is_empty() else RocketFamilies.next_name(state)


# ------------------------------------------------------------ fill
func refresh() -> void:
	if state == null or type_id == "":
		return
	var mt := state.mission_type(type_id)
	var tname := tr(String(state.mission_target(target_id).get("name_key", "")))
	var code := ""
	if mode == "change":
		var p := ProjectDesk.find(state, project_id)
		code = p.code if p else ""
	else:
		code = ProjectDesk.next_code(state, type_id)
	%Caption.text = tr("TY_RK_FOR_MISSION") % [code, tr(String(mt.get("name_key", ""))), tname]
	var nd := RocketDesigner.need(state, type_id, target_id)
	var lift := float(nd["lift"])
	%NeedLine.text = tr("TY_RK_NEED_LINE") % [float(nd["dv"]), ("%.2f" if lift < 1.0 else "%.1f") % lift]
	_fill_families()
	_fill_proposals()
	_fill_slots()
	var chk := RocketDesigner.check(state, parts, type_id, target_id)
	_fill_check(chk)
	_fill_stats()
	_fill_footer(chk)
	_preview.build(parts)
	_frame_preview.call_deferred()


static func _wire(b: BaseButton, f: Callable) -> void:
	if not b.has_meta("wired"):
		b.set_meta("wired", true)
		b.pressed.connect(func() -> void: f.call(String(b.get_meta("id", ""))))


func _fill_families() -> void:
	var fams := RocketFamilies.families(state)
	# the ones that reach this mission first, the most reliable first
	var list: Array = fams.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := RocketDesigner.check(state, a["parts"], type_id, target_id)["reaches"] as bool
		var rb := RocketDesigner.check(state, b["parts"], type_id, target_id)["reaches"] as bool
		if ra != rb:
			return ra
		return RocketFamilies.reliability(state, a["parts"]) > RocketFamilies.reliability(state, b["parts"]))
	var rows := copies(%FamilyTemplate, list.size())
	for i in list.size():
		var f: Dictionary = list[i]
		var b := rows[i] as Button
		b.set_meta("id", String(f["id"]))
		_wire(b, _pick_family)
		b.set_pressed_no_signal(String(f["id"]) == family_id)
		var reaches := RocketDesigner.check(state, f["parts"], type_id, target_id)["reaches"] as bool
		(b.get_node("Row/Names/Name") as Label).text = String(f["name"])
		(b.get_node("Row/Names/Meta") as Label).text = "%s · %s" % [
			tr("TY_RK_HERITAGE_N") % [RocketFamilies.flights(f), int(f.get("successes", 0))],
			tr(String(RocketDesigner.component(String(f["parts"].get("core", ""))).get("name_key", "")))]
		var rel := b.get_node("Row/Side/Rel") as Label
		rel.text = "%d%%" % roundi(RocketFamilies.reliability(state, f["parts"]) * 100.0)
		var chip := b.get_node("Row/Side/Reach") as Label
		chip.text = tr("TY_RK_REACHES") if reaches else tr("TY_RK_NOT_REACH")
		chip.add_theme_color_override("font_color", CwPalette.AURORA_TEAL if reaches else CwPalette.DANGER)
	%NoFamilies.visible = list.is_empty()


func _fill_proposals() -> void:
	var props := RocketDesigner.proposals(state, type_id, target_id)
	var rows := copies(%ProposalTemplate, props.size())
	for i in props.size():
		var pr: Dictionary = props[i]
		var b := rows[i] as Button
		var kind := String(pr["kind"])
		b.set_meta("id", kind)
		_wire(b, _pick_proposal)
		b.set_pressed_no_signal(RocketDesigner.same_parts(pr["parts"], parts))
		var fam := RocketFamilies.find_parts(state, pr["parts"])
		var fl := RocketFamilies.flights(fam)
		(b.get_node("Row/Names/Kind") as Label).text = tr(KIND_KEYS.get(kind, kind))
		(b.get_node("Row/Names/Meta") as Label).text = "%s · %s" % [
			cr(RocketDesigner.unit_cost(state, pr["parts"], fl)), tr("TY_RK_WEEKS_N") % RocketDesigner.build_weeks(state, pr["parts"], fl)]
		(b.get_node("Row/Odds") as Label).text = "%d%%" % roundi(float(pr["odds"]) * 100.0)
	%NoProposals.visible = props.is_empty()


func _fill_slots() -> void:
	var slots := RocketDesigner.slots()
	var rows := copies(%SlotTemplate, slots.size())
	for i in slots.size():
		var sd: Dictionary = slots[i]
		var sid := String(sd["id"])
		var row := rows[i]
		var cur := RocketDesigner.component(String(parts.get(sid, "")))
		(row.get_node("Head/Name") as Label).text = tr(String(sd.get("name_key", sid)))
		(row.get_node("Head/Desc") as Label).text = tr(String(cur.get("desc_key", "")))
		var locked := RocketDesigner.locked_count(state, sid)
		var ll := row.get_node("Head/Locked") as Label
		ll.visible = locked > 0
		ll.text = tr("TY_RK_LOCKED_N") % locked
		var opts := RocketDesigner.options(state, sid)
		var buttons := copies(row.get_node("Trough/Options/OptionTemplate"), opts.size())
		for j in opts.size():
			var c: Dictionary = opts[j]
			var b := buttons[j] as Button
			b.set_meta("id", String(c["id"]))
			b.set_meta("slot", sid)
			if not b.has_meta("wired"):
				b.set_meta("wired", true)
				b.pressed.connect(func() -> void: _pick_part(String(b.get_meta("slot")), String(b.get_meta("id"))))
			b.text = tr(String(c.get("name_key", c["id"])))
			b.tooltip_text = tr(String(c.get("desc_key", "")))
			b.set_pressed_no_signal(String(c["id"]) == String(parts.get(sid, "")))


func _fill_check(chk: Dictionary) -> void:
	var meters := {"dv": [%MeterDv, "%.1f / %.1f km/s"], "lift": [%MeterLift, "%.2f / %.2f t"], "size": [%MeterSize, "%.1f / %.1f"]}
	var worst := "green"
	for k: String in meters:
		var m: Dictionary = chk[k]
		var row: Control = meters[k][0]
		var st := String(m["state"])
		if st == "red" or (st == "yellow" and worst == "green"):
			worst = st
		var need := maxf(float(m["need"]), 0.0001)
		var bar := row.get_node("Bar") as CwSegmentBar
		bar.value = clampf(float(m["have"]) / (need * 2.0), 0.0, 1.0)
		bar.marker = 0.5
		bar.color = STATE_COLORS[st]
		var vl := row.get_node("Value") as Label
		vl.text = String(meters[k][1]) % [float(m["have"]), float(m["need"])]
		vl.add_theme_color_override("font_color", STATE_COLORS[st] if st != "green" else CwPalette.TEXT)
	var verdict := %Verdict as Label
	var was := verdict.text
	verdict.text = tr("TY_RK_NOT_REACH") if worst == "red" else (tr("TY_RK_REACHES_THIN") if worst == "yellow" else tr("TY_RK_REACHES"))
	verdict.add_theme_color_override("font_color", STATE_COLORS[worst])
	var pill := %VerdictPill as PanelContainer
	var sb := pill.get_theme_stylebox("panel").duplicate() as StyleBox
	if sb is StyleBoxFlat:
		(sb as StyleBoxFlat).border_color = STATE_COLORS[worst]
		pill.add_theme_stylebox_override("panel", sb)
	if was != verdict.text:
		CwMotion.poke(verdict)


func _fill_stats() -> void:
	var fam := RocketFamilies.find(state, family_id)
	var fl := RocketFamilies.flights(fam)
	CwNumberTicker.show(%CostValue, RocketDesigner.unit_cost(state, parts, fl), func(v: float) -> String: return cr(v))
	%WeeksValue.text = tr("TY_RK_WEEKS_N") % RocketDesigner.build_weeks(state, parts, fl)
	var rel := RocketFamilies.reliability(state, parts)
	CwNumberTicker.show(%RelValue, rel * 100.0, func(v: float) -> String: return "%d%%" % roundi(v))
	%RelValue.add_theme_color_override("font_color", CwPalette.AURORA_TEAL if rel >= 0.9
		else (CwPalette.WARNING if rel >= 0.8 else CwPalette.DANGER))
	%Heritage.text = tr("TY_RK_HERITAGE_N") % [fl, int(fam.get("successes", 0))] if not fam.is_empty() and fl > 0 \
		else tr("TY_RK_HERITAGE_NEW")


func _fill_footer(chk: Dictionary = {}) -> void:
	if state == null or type_id == "":
		return
	if chk.is_empty():
		chk = RocketDesigner.check(state, parts, type_id, target_id)
	var err := ""
	if not chk["reaches"]:
		err = "TY_PJ_ERR_ROCKET"
	elif mode == "new":
		err = ProjectDesk.start_error(state, type_id, target_id, staff_ids, _design())
	%Error.text = tr(err) if err != "" else ""
	%Start.disabled = err != ""
	%Start.text = tr("TY_RK_USE") if mode == "change" else tr("TY_RK_START")
	var fam := RocketFamilies.find(state, family_id)
	var saved := not fam.is_empty() and String(fam["name"]) == String(%FamilyName.text).strip_edges()
	%Save.disabled = saved or String(%FamilyName.text).strip_edges() == ""
	%Save.text = tr("TY_RK_SAVED") if saved else tr("TY_RK_SAVE")


## Frames the preview camera on the rocket (bigger rockets, farther camera).
func _frame_preview() -> void:
	if not is_inside_tree():
		return
	var box := _preview.bounds()
	var h := maxf(box.size.y, 1.0)
	var cam := %PreviewCam as Camera3D
	var mid := h * 0.5
	var dist := h * 1.55 + 3.0
	cam.position = Vector3(0, mid + h * 0.05, dist)
	cam.look_at(Vector3(0, mid, 0), Vector3.UP)
