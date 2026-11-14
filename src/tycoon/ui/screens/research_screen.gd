extends CwScreen
## Research screen (scenes/tycoon/ui/screens/research.tscn): the tech tree laid out by era
## (columns) with connection lines, node states (locked / available / queued / researching /
## done), the lab readouts, the queue and the detail card of the selected tech. The scene
## holds every visual; this script places copies of %NodeTemplate on the era grid and fills
## the texts.

const NODE_STYLE := {"done": &"CwNodeDone", "researching": &"CwNodeActive", "queued": &"CwNodeAvailable",
	"available": &"CwNodeAvailable", "locked": &"CwNodeLocked"}
const KIND_COLOR := {"type": CwPalette.IGNITION, "target": CwPalette.COMET_ICE, "option": CwPalette.AURORA_TEAL,
	"spec": CwPalette.AURORA_VIOLET, "part": CwPalette.TEXT_DIM, "effect": CwPalette.WARNING,
	"rocket": CwPalette.IGNITION}

var selected := ""


func _ready() -> void:
	super()
	%Fund.pressed.connect(_on_fund)
	%License.pressed.connect(func() -> void:
		if state and selected != "":
			TycoonResearch.license(state, selected))
	%Canvas.resized.connect(func() -> void:
		if state:
			_layout())


func _bound() -> void:
	selected = TycoonResearch.active(state)
	if selected == "":
		for t: Dictionary in TycoonResearch.techs():
			if TycoonResearch.can_research(state, String(t["id"])):
				selected = String(t["id"])
				break
	if selected == "":
		for t: Dictionary in TycoonResearch.techs():
			if not TycoonResearch.is_done(state, String(t["id"])):
				selected = String(t["id"])
				break
	if selected == "":
		selected = String(TycoonResearch.techs()[0]["id"])


## Opens with a given tech selected: open_screen("research", {"tech": id}).
func open_with(args: Dictionary) -> void:
	if args.has("tech"):
		select(String(args["tech"]))


func select(id: String) -> void:
	selected = id
	refresh()


func refresh() -> void:
	if state == null:
		return
	%PoolValue.text = "%d PP" % floori(state.research_points)
	%RateValue.text = "+%.1f" % TycoonResearch.pp_per_week(state)
	var seats := TycoonResearch.lab_seats(state)
	var used := TycoonResearch.seated(state).size()
	var lv := TycoonResearch.lab_level(state)
	%LabValue.text = (tr("TY_RS_LAB_BENCH") if lv == 0 else tr("TY_LEVEL") % lv) + " · %d/%d" % [used, seats]
	(%SeatsBar as CwSegmentBar).segments = maxi(seats, 2)
	(%SeatsBar as CwSegmentBar).value = float(used) / maxf(seats, 1)
	_fill_eras()
	_layout()
	_fill_queue()
	_fill_detail()


func _fill_eras() -> void:
	var heads := %EraHeads.get_children()
	var bands := %Bands.get_children()
	var la := int(TycoonResearch.db().get("era_lookahead", 1))
	for i in heads.size():
		var era := i + 1
		var h := heads[i] as Control
		var name_l := h.get_node("Name") as Label
		var years := h.get_node("Years") as Label
		name_l.text = "%s · %s" % [tr("TY_RS_ERA_N") % era, tr("TY_ERA_%d" % era)]
		var y0 := (era - 1) * 5 + 1
		if era == state.era():
			years.text = tr("TY_RS_NOW") % [y0, y0 + 4]
			name_l.add_theme_color_override("font_color", CwPalette.IGNITION)
			years.add_theme_color_override("font_color", CwPalette.TEXT)
		elif era > state.era() + la:
			years.text = tr("TY_RS_OPENS") % ((era - la - 1) * 5 + 1)
			name_l.add_theme_color_override("font_color", Color(CwPalette.INK_SOFT, 0.55))
			years.add_theme_color_override("font_color", Color(CwPalette.INK_SOFT, 0.55))
		else:
			years.text = tr("TY_RS_YEARS") % [y0, y0 + 4]
			name_l.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
			years.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
		if i < bands.size():
			var b := bands[i] as ColorRect
			b.color = Color(CwPalette.LILAC_LIGHT, 0.7) if era == state.era() else Color(0, 0, 0, 0)


## Places one node per tech on the era (column) x row grid and draws the links.
func _layout() -> void:
	var techs := TycoonResearch.techs()
	var nodes := copies(%NodeTemplate, techs.size())
	var area: Vector2 = %Canvas.size
	var tmpl_size: Vector2 = (%NodeTemplate as Control).size
	var col_w := area.x / 5.0
	var row_h := area.y / 6.0
	var nw := minf(tmpl_size.x, col_w - 34.0)
	var rects := {}
	for i in techs.size():
		var t: Dictionary = techs[i]
		var id := String(t["id"])
		var n := nodes[i]
		var col := int(t["era"]) - 1
		var row := int(t["row"])
		n.size = Vector2(nw, tmpl_size.y)
		n.position = Vector2(roundf(col * col_w + (col_w - nw) * 0.5), roundf(row * row_h + (row_h - tmpl_size.y) * 0.5))
		rects[id] = Rect2(n.position, n.size)
		_fill_node(n, t)
	# links, with the sockets of a node spread out so parallel lines do not merge
	var links: Array = []
	var outs := {}
	var ins := {}
	for t: Dictionary in techs:
		var id := String(t["id"])
		var st := TycoonResearch.node_state(state, id)
		for p: String in t.get("prereq", []):
			var ls := "locked"
			if st == "done":
				ls = "done"
			elif st == "researching":
				ls = "active"
			elif TycoonResearch.is_done(state, p):
				ls = "open"
			var l := {"a": rects[p], "b": rects[id], "state": ls, "from": p, "to": id}
			links.append(l)
			outs[p] = outs.get(p, []) + [l]
			ins[id] = ins.get(id, []) + [l]
	for gi in 2:
		var group: Dictionary = outs if gi == 0 else ins
		var key := "ya" if gi == 0 else "yb"
		var other := "b" if gi == 0 else "a"
		for id: String in group:
			var ls: Array = group[id]
			ls.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
				return (x[other] as Rect2).position.y < (y[other] as Rect2).position.y)
			for i in ls.size():
				ls[i][key] = (i - (ls.size() - 1) * 0.5) * 9.0
	(%Links as CwTechLinks).links = links


func _fill_node(n: Control, t: Dictionary) -> void:
	var id := String(t["id"])
	var st := TycoonResearch.node_state(state, id)
	var card := n.get_node("Card") as PanelContainer
	card.theme_type_variation = NODE_STYLE[st]
	var br := TycoonResearch.branch(String(t["branch"]))
	var dot := card.get_node("VBox/Top/DotBox/Dot") as ColorRect
	dot.color = Color(String(br.get("color", "#8c9ab5")))
	var name_l := card.get_node("VBox/Top/Name") as Label
	name_l.text = tr("TY_TECH_" + id.to_upper())
	name_l.add_theme_color_override("font_color", CwPalette.TEXT_DIM if st == "locked" else CwPalette.TEXT)
	var cost := card.get_node("VBox/Bottom/Cost") as Label
	cost.text = "%d PP" % int(t["cost"])
	cost.add_theme_color_override("font_color", Color(CwPalette.INK_SOFT, 0.55) if st == "locked" else CwPalette.COMET_ICE)
	var st_l := card.get_node("VBox/Bottom/State") as Label
	var q := TycoonResearch.queue(state).find(id)
	st_l.text = tr("TY_RS_QUEUED_N") % (q + 1) if st == "queued" else tr("TY_RS_ST_" + st.to_upper())
	var st_col := {"done": CwPalette.AURORA_TEAL, "researching": CwPalette.AURORA_VIOLET, "queued": CwPalette.WARNING,
		"available": CwPalette.COMET_ICE, "locked": Color(CwPalette.INK_SOFT, 0.55)}
	st_l.add_theme_color_override("font_color", CwPalette.ink(st_col[st]))
	var bar := card.get_node("VBox/Bar") as CwSegmentBar
	bar.value = TycoonResearch.fraction(state, id)
	bar.color = CwPalette.AURORA_TEAL if st == "done" else CwPalette.AURORA_VIOLET
	bar.visible = st != "locked"
	(n.get_node("Ring") as Control).visible = id == selected
	n.tooltip_text = tr("TY_TECH_" + id.to_upper())
	if not n.has_meta("wired"):
		n.set_meta("wired", true)
		n.gui_input.connect(_on_node_input.bind(n))
	n.set_meta("tech", id)


func _on_node_input(event: InputEvent, n: Control) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var id := String(n.get_meta("tech", ""))
		if mb.double_click and TycoonResearch.node_state(state, id) in ["available", "queued", "researching"]:
			TycoonResearch.fund(state, id)
		select(id)
		accept_event()


func _fill_queue() -> void:
	var act := TycoonResearch.active(state)
	if act == "":
		%QueueLabel.text = tr("TY_RS_IDLE")
		%QueueLabel.add_theme_color_override("font_color", CwPalette.WARNING)
		return
	%QueueLabel.remove_theme_color_override("font_color")
	var eta := TycoonResearch.weeks_left(state, act)
	var parts: Array[String] = ["%s (%s)" % [tr("TY_TECH_" + act.to_upper()), _eta_text(eta)]]
	for q in TycoonResearch.queue(state):
		parts.append(tr("TY_TECH_" + String(q).to_upper()))
	%QueueLabel.text = "  →  ".join(parts)


func _eta_text(w: int) -> String:
	return tr("TY_RS_NO_PP") if w < 0 else tr("TY_WEEKS") % w


func _fill_detail() -> void:
	var t := TycoonResearch.tech(selected)
	if t.is_empty():
		return
	var id := selected
	var st := TycoonResearch.node_state(state, id)
	var br := TycoonResearch.branch(String(t["branch"]))
	%DBranch.text = tr(String(br.get("name_key", "")))
	%DBranch.add_theme_color_override("font_color", CwPalette.ink(Color(String(br.get("color", "#8c9ab5")))))
	%DName.text = tr("TY_TECH_" + id.to_upper())
	%DState.text = "%s · %s" % [tr("TY_RS_ERA_N") % int(t["era"]), tr("TY_RS_ST_" + st.to_upper())]
	%DDesc.text = tr("TY_TECH_" + id.to_upper() + "_DESC")
	%DCost.text = "%d PP" % int(t["cost"])
	%DTime.text = tr("TY_WEEKS") % int(t["weeks"])
	var eta := TycoonResearch.weeks_left(state, id)
	%DEta.text = "—" if st in ["done", "locked"] else _eta_text(eta)
	(%DBar as CwSegmentBar).value = TycoonResearch.fraction(state, id)
	(%DBar as CwSegmentBar).color = CwPalette.AURORA_TEAL if st == "done" else CwPalette.AURORA_VIOLET
	%DProgress.text = "%d / %d PP" % [floori(TycoonResearch.progress(state, id)), int(t["cost"])]
	# unlocks
	var rows := TycoonResearch.unlock_list(id)
	var lines := copies(%UnlockTemplate, rows.size())
	for i in rows.size():
		var r: Dictionary = rows[i]
		var kind := String(r["kind"])
		var kl := lines[i].get_node("Kind") as Label
		kl.text = tr("TY_RS_K_" + kind.to_upper())
		kl.add_theme_color_override("font_color", CwPalette.ink(KIND_COLOR.get(kind, CwPalette.TEXT_DIM)))
		var nl := lines[i].get_node("Name") as Label
		if kind == "effect":
			nl.text = tr(String(r["key"])) % (float(r["value"]) * 100.0 if String(r["id"]) != "contract_slots" else float(r["value"]))
		elif r.has("name"):
			nl.text = String(r["name"])
		else:
			nl.text = tr(String(r["key"]))
	# prerequisites
	var req: Array[String] = []
	for p: String in t.get("prereq", []):
		req.append(("✓ " if TycoonResearch.is_done(state, p) else "· ") + tr("TY_TECH_" + p.to_upper()))
	var la := int(TycoonResearch.db().get("era_lookahead", 1))
	if int(t["era"]) > state.era() + la:
		req.append(tr("TY_RS_NEEDS_ERA") % ((int(t["era"]) - la - 1) * 5 + 1))
	%Requires.text = "\n".join(req) if not req.is_empty() else tr("TY_RS_NO_REQ")
	_fill_bench()
	# actions: the screen's one primary button
	var fund: Button = %Fund
	fund.disabled = false
	match st:
		"researching":
			fund.text = tr("TY_RS_STOP")
		"queued":
			fund.text = tr("TY_RS_UNQUEUE")
		"available":
			fund.text = tr("TY_RS_FUND") if TycoonResearch.active(state) == "" else tr("TY_RS_QUEUE_IT")
		"done":
			fund.text = tr("TY_RS_ST_DONE")
			fund.disabled = true
		_:
			fund.text = tr("TY_RS_ST_LOCKED")
			fund.disabled = true
	var lic: Button = %License
	lic.visible = st == "done"
	if TycoonResearch.can_license(state, id):
		lic.text = tr("TY_RS_LICENSE") % cr(TycoonResearch.license_value(id))
		lic.disabled = false
	else:
		lic.text = tr("TY_RS_LICENSED")
		lic.disabled = true


func _on_fund() -> void:
	if state and selected != "":
		TycoonResearch.fund(state, selected)


## Who sits in the lab this week and what each adds.
func _fill_bench() -> void:
	var seated := TycoonResearch.seated(state)
	var rows := copies(%SeatTemplate, seated.size())
	var mult := TycoonResearch.lab_mult(state)
	for i in seated.size():
		var m: Dictionary = seated[i]["member"]
		var prof := state.profession(String(m.get("profession", "")))
		(rows[i].get_node("Dot") as ColorRect).color = Color(String(prof.get("color", "#8e7cff")))
		(rows[i].get_node("Name") as Label).text = String(m.get("name", ""))
		(rows[i].get_node("Prof") as Label).text = tr(String(prof.get("name_key", "")))
		(rows[i].get_node("PP") as Label).text = "+%.1f PP" % (float(seated[i]["pp"]) * mult)
	%BenchEmpty.visible = seated.is_empty()
