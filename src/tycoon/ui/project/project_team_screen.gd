extends CwScreen
## Team step (scenes/tycoon/ui/screens/project_team.tscn), after the payload: who builds the
## mission. The Cometlings as toggle rows (busy ones dimmed), the ideal team size, and what the
## mission leans on: what the agency knows of each bar (FocusStudy tiers: "?", most / least,
## levels, the exact share; always "?" for a client with priorities of its own), with how many
## on the team have that bar as their profession's. The journal's best team so far, the staff's hints on the briefing,
## the cost and weeks. Next: the rocket designer, which starts the project.
## Everything visual is in the scene; staff and hint rows are copies of its hidden templates.

var type_id := ""
var target_id := ""
var contract_id := ""
var briefing_id := ""
var payload: Array[String] = []
var picked := {}
var _touched := false


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
	payload.clear()
	for m in args.get("payload", []):
		payload.append(String(m))
	picked.clear()
	for sid in args.get("staff", []):
		picked[String(sid)] = true
	_touched = not picked.is_empty()
	if not _touched:
		_auto_team()
	refresh()


func team_ids() -> Array[String]:
	var ids: Array[String] = []
	for m in state.staff:
		if picked.get(String(m["id"]), false) and String(m.get("assigned", "")) == "":
			ids.append(String(m["id"]))
	return ids


func args_out() -> Dictionary:
	return {"type": type_id, "target": target_id, "contract_id": contract_id, "briefing_id": briefing_id,
		"payload": payload.duplicate(), "staff": team_ids()}


func _next() -> void:
	if error() != "":
		return
	if hud:
		hud.open_screen("rocket_designer", args_out())


func _back() -> void:
	if hud:
		hud.open_screen("payload_planner", args_out())
	else:
		close_screen()


func error() -> String:
	return ProjectDesk.start_error(state, type_id, target_id, team_ids(), {}, {"payload": payload, "briefing_id": briefing_id})


## The Cometlings' suggestion: the ideal number of free Cometlings, a pilot for a crewed flight,
## one of each profession whose bar the agency knows the mission leans on (FocusStudy), then
## the most skilled. (Without that knowledge the hidden balance is the player's call.)
func _auto_team() -> void:
	picked.clear()
	var probe := MissionProject.new()
	probe.type_id = type_id
	var free := ProjectDesk.free_staff(state)
	free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("skill", 0.5)) > float(b.get("skill", 0.5)))
	var crewed := ProjectRules.is_crewed(type_id)
	var n := probe.ideal_team(state)
	if crewed:
		for m in free:
			if String(m.get("profession", "")) == "pilot":
				picked[String(m["id"])] = true
				break
	# what the agency knows the mission leans on: one of each of those professions first
	var client := BriefingDesk.ratio(BriefingDesk.briefing(briefing_id)).size() == 4
	for bi in 4:
		if client or picked.size() >= n or not FocusStudy.known_important(state, type_id, bi):
			continue
		for m in free:
			var primary := String(state.profession(String(m.get("profession", ""))).get("primary", ""))
			if not picked.has(String(m["id"])) and primary == ProjectRules.BARS[bi]:
				picked[String(m["id"])] = true
				break
	for m in free:
		if picked.size() >= n:
			break
		picked[String(m["id"])] = true


func _toggle(id: String) -> void:
	_touched = true
	picked[id] = not picked.get(id, false)
	refresh()


# ------------------------------------------------------------ fill
func refresh() -> void:
	if state == null or type_id == "":
		return
	%Caption.text = "%s · %s → %s" % [tr("TY_TM_CAPTION"), tr(String(state.mission_type(type_id).get("name_key", ""))),
		tr(String(state.mission_target(target_id).get("name_key", "")))]
	%CashNow.text = cr(state.cash)
	_fill_staff()
	_fill_needs()
	_fill_hints()
	_fill_estimate()
	var err := error()
	%Error.text = tr(err) if err != "" else ""
	%Next.disabled = err != ""


func _fill_staff() -> void:
	var rows := copies(%StaffTemplate, state.staff.size())
	for i in state.staff.size():
		var m: Dictionary = state.staff[i]
		var b := rows[i] as Button
		var id := String(m["id"])
		b.set_meta("id", id)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: _toggle(String(b.get_meta("id", ""))))
		var prof := state.profession(String(m.get("profession", "")))
		var busy := String(m.get("assigned", ""))
		b.disabled = busy != ""
		b.set_pressed_no_signal(picked.get(id, false) and busy == "")
		(b.get_node("Row/Tab") as ColorRect).color = CwPalette.BARS.get(String(prof.get("primary", "eng")), CwPalette.LINE)
		(b.get_node("Row/Names/Name") as Label).text = String(m.get("name", id))
		(b.get_node("Row/Names/Prof") as Label).text = tr(String(prof.get("name_key", "")))
		(b.get_node("Row/Level") as Label).text = tr("TY_PJ_LEVEL_SHORT") % int(m.get("level", 1)) \
			if busy == "" else tr("TY_PJ_BUSY_ON") % busy
	var probe := MissionProject.new()
	probe.type_id = type_id
	%TeamIdeal.text = tr("TY_PJ_TEAM_IDEAL") % probe.ideal_team(state)
	%TeamCount.text = "%d / %d" % [team_ids().size(), ProjectDesk.free_staff(state).size()]


func _fill_needs() -> void:
	var client := BriefingDesk.ratio(BriefingDesk.briefing(briefing_id)).size() == 4
	var t := 0 if client else FocusStudy.tier(state, type_id)
	var marks := FocusStudy.bar_marks(state, type_id)
	var team: Array[Dictionary] = []
	for m in state.staff:
		if String(m["id"]) in team_ids():
			team.append(m)
	var rows: Array[Node] = [%NeedEng, %NeedSci, %NeedOps, %NeedRel]
	for bi in 4:
		var bar := ProjectRules.BARS[bi]
		var n := 0
		for m in team:
			if String(state.profession(String(m.get("profession", ""))).get("primary", "")) == bar:
				n += 1
		(rows[bi].get_node("Chip") as ColorRect).color = CwPalette.BARS[bar]
		var mk: Dictionary = marks[bi] if t > 0 else {"tier": 0, "mark": "", "ideal": -1.0}
		var il := rows[bi].get_node("Ideal") as Label
		il.text = FocusView.mark_text(mk)
		il.add_theme_color_override("font_color", FocusView.mark_color(mk))
		var hl := rows[bi].get_node("Have") as Label
		hl.text = tr("TY_TM_HAVE_N") % n
		var short := t > 0 and n == 0 and FocusStudy.known_important(state, type_id, bi)
		hl.add_theme_color_override("font_color", CwPalette.DANGER if short else CwPalette.TEXT)
	if client:
		%NeedsNote.text = tr("TY_TM_NEEDS_CLIENT")
	elif t >= FocusStudy.MAX_TIER:
		%NeedsNote.text = tr("TY_TM_NEEDS_KNOWN")
	elif t > 0:
		%NeedsNote.text = "%s %s" % [FocusView.know_text(state, type_id), FocusView.how_text(state, type_id)]
	else:
		%NeedsNote.text = "%s %s" % [tr("TY_FS_KNOW_0"), FocusView.how_text(state, type_id)]
	var tn := Discovery.team_note(state, type_id)
	%BestTeam.visible = not tn.is_empty()
	if not tn.is_empty():
		var parts: Array[String] = []
		var profs: Dictionary = tn.get("profs", {})
		for p: String in profs:
			parts.append("%d %s" % [int(profs[p]), tr(String(state.profession(p).get("name_key", p)))])
		%BestTeam.text = tr("TY_TM_BEST") % ["%.1f" % float(tn.get("grade", 0.0)), ", ".join(parts)]


func _fill_hints() -> void:
	var hints: Array[Dictionary] = []
	if briefing_id != "":
		hints = Discovery.briefing_hints(state, BriefingDesk.briefing(briefing_id))
	var rows := copies(%HintTemplate, hints.size())
	for i in hints.size():
		(rows[i].get_node("Row/Text") as Label).text = TycoonHUD.news_text(hints[i])
	%HintsCaption.visible = briefing_id != ""
	%NoHints.visible = briefing_id != "" and hints.is_empty()


func _fill_estimate() -> void:
	var e := ProjectDesk.estimate(state, type_id, {}, target_id)
	var pc := PayloadRules.cost(payload)
	%EstWeeks.text = "%d" % int(e["weeks"])
	%EstDev.text = cr(float(e["dev_cost"]))
	%EstPayload.text = cr(pc)
	%EstLaunch.text = cr(float(e["launch_cost"]))
	var total := float(e["total"]) + pc
	%EstTotal.text = cr(total)
	%EstTotal.add_theme_color_override("font_color", CwPalette.DANGER if total > state.cash else CwPalette.COMET_ICE)
	var o := BriefingDesk.offer(state, briefing_id)
	%Deadline.visible = not o.is_empty()
	if not o.is_empty():
		%Deadline.text = tr("TY_TM_DEADLINE") % [int(o.get("deadline", 0)), cr(float(o.get("budget", 0.0)))]
