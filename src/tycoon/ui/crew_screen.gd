class_name CrewScreen
extends Control
## Crew screen (scenes/tycoon/ui/screens/crew.tscn), opened by the HUD's Crew rail button:
## the staff roster (profession antenna tag, level, XP, traits, morale, salary, what they are
## doing), a card for the selected Cometling with a live 3D portrait in a round visor and
## their specialisation slots, and the hiring market (3 candidates a month, hidden traits as
## "?"). Everything visual is in the scene; rows, candidates, spec slots and their options are
## copies of hidden templates there. Rules come from TycoonCrew.

var state: TycoonState
var clock: TycoonClock
var hud: Node
## "roster" | "hire"
var tab := "roster"
var selected := ""
var selected_cand := ""
var _fire_armed := ""
var _note := ""
var _shown_look := ""

@onready var creature: Cometling = $Layout/Body/Card/CardBox/CardScroll/Pad/VBox/Top/Visor/Portrait/Viewport/Creature


func _ready() -> void:
	%RosterTab.pressed.connect(func() -> void: show_tab("roster"))
	%HireTab.pressed.connect(func() -> void: show_tab("hire"))
	%CloseButton.pressed.connect(close)
	%FireButton.pressed.connect(_on_fire)
	%HireButton.pressed.connect(_on_hire)
	%EditLeader.pressed.connect(func() -> void:   # the leader creator, in edit mode
		if hud and hud.has_method("open_screen"):
			hud.call("open_screen", "leader_creator"))


func bind(s: TycoonState, c: TycoonClock, h: Node) -> void:
	state = s
	clock = c
	hud = h
	TycoonCrew.ensure(state)
	state.changed.connect(refresh)
	if not state.staff.is_empty():
		selected = String(state.staff[0]["id"])
	refresh()


## args: {"tab": "roster" | "hire", "staff_id": id}
func open_with(args: Dictionary) -> void:
	selected = String(args.get("staff_id", selected))
	show_tab(String(args.get("tab", tab)))


func close() -> void:
	if hud and hud.has_method("close_screen"):
		hud.call("close_screen")
	else:
		queue_free()


func show_tab(t: String) -> void:
	tab = t
	_note = ""
	_fire_armed = ""
	refresh()


func select_member(id: String) -> void:
	selected = id
	_note = ""
	_fire_armed = ""
	refresh()


func select_candidate(id: String) -> void:
	selected_cand = id
	_note = ""
	refresh()


# ------------------------------------------------------------ refresh
func refresh() -> void:
	if state == null or not is_inside_tree():
		return
	var cands := TycoonCrew.candidates(state)
	%StaffValue.text = "%d / %d" % [state.staff.size(), TycoonCrew.staff_limit(state)]
	%PayrollValue.text = TycoonHUD.fmt_cr(state.monthly_salaries())
	var avg := TycoonCrew.average_morale(state)
	%AvgMoraleValue.text = "%d" % roundi(avg)
	%AvgMoraleValue.add_theme_color_override("font_color", _morale_color(avg))
	%MarketValue.text = tr("TY_CREW_MARKET_VALUE") % [cands.size(), TycoonCrew.weeks_to_market(state)]
	%RosterTab.set_pressed_no_signal(tab == "roster")
	%HireTab.set_pressed_no_signal(tab == "hire")
	%RosterPage.visible = tab == "roster"
	%HirePage.visible = tab == "hire"
	if tab == "roster":
		if TycoonCrew.find(state, selected).is_empty() and not state.staff.is_empty():
			selected = String(state.staff[0]["id"])
		_fill_roster()
		_show_member(TycoonCrew.find(state, selected))
	else:
		if TycoonCrew.find_candidate(state, selected_cand).is_empty() and not cands.is_empty():
			selected_cand = String(cands[0]["id"])
		_fill_market(cands)
		_show_candidate(TycoonCrew.find_candidate(state, selected_cand))
	_fill_composition()


## Footer: a chip per profession with how many Cometlings have it and the project bar it
## favours, in full words (the chips flow onto a second line when the row is full).
func _fill_composition() -> void:
	var profs: Array = state.pdata.get("professions", [])
	var cells := TycoonHUD._copies(%ProfTemplate, profs.size())
	for i in profs.size():
		var p: Dictionary = profs[i]
		var n := 0
		for m in state.staff:
			n += 1 if m.get("profession", "") == p["id"] else 0
		var col := Color(String(p.get("color", "#8c9ab5")))
		var cell := cells[i].get_node("HBox")
		(cell.get_node("Bulb") as TextureRect).self_modulate = col if n > 0 else CwPalette.LINE
		var count := cell.get_node("Count") as Label
		count.text = str(n)
		count.add_theme_color_override("font_color", CwPalette.COMET_ICE if n > 0 else CwPalette.TEXT_DIM)
		var name_l := cell.get_node("Name") as Label
		name_l.text = tr(String(p.get("name_key", "")))
		name_l.add_theme_color_override("font_color", CwPalette.TEXT if n > 0 else CwPalette.TEXT_DIM)
		var bar := String(p.get("primary", "eng"))
		var bar_l := cell.get_node("Bar") as Label
		bar_l.text = tr("TY_BAR_" + bar.to_upper())
		bar_l.add_theme_color_override("font_color", CwPalette.ink(CwPalette.BARS.get(bar, CwPalette.TEXT_DIM)))


func _fill_roster() -> void:
	var rows := TycoonHUD._copies(%RowTemplate, state.staff.size())
	for i in state.staff.size():
		var m: Dictionary = state.staff[i]
		var row := rows[i] as Button
		var id := String(m["id"])
		row.set_meta("id", id)
		if not row.has_meta("wired"):
			row.set_meta("wired", true)
			row.pressed.connect(func() -> void: select_member(String(row.get_meta("id"))))
		row.set_pressed_no_signal(id == selected)
		var col := TycoonCrew.profession_color(state, String(m["profession"]))
		(row.get_node("HBox/Tab") as ColorRect).color = col
		(row.get_node("HBox/Bulb") as TextureRect).self_modulate = col
		(row.get_node("HBox/Bulb/Leader") as Control).visible = TycoonLeader.is_leader(m)
		(row.get_node("HBox/Who/Name") as Label).text = String(m["name"])
		(row.get_node("HBox/Who/Prof") as Label).text = _prof_name(m)
		(row.get_node("HBox/Level") as Label).text = str(int(m["level"]))
		(row.get_node("HBox/XP/Bar") as CwSegmentBar).value = TycoonCrew.level_progress(m)
		(row.get_node("HBox/XP/Text") as Label).text = "%d XP" % roundi(float(m["xp"]))
		for t: String in TycoonCrew.TRAITS:
			_trait(row.get_node("HBox/" + t.capitalize()), m, t)
		var mo := float(m["morale"])
		var mb := row.get_node("HBox/Morale/Bar") as CwSegmentBar
		mb.value = mo / 100.0
		mb.color = _morale_color(mo)
		(row.get_node("HBox/Morale/Text") as Label).text = "%d · %s" % [roundi(mo), tr(_mood_key(mo))]
		(row.get_node("HBox/Salary") as Label).text = TycoonHUD.fmt_cr(TycoonCrew.salary(state, m))
		var task := row.get_node("HBox/Doing/Task") as Label
		task.text = _project_name(String(m["assigned"]))
		task.add_theme_color_override("font_color", CwPalette.TEXT if String(m["assigned"]) != "" else CwPalette.TEXT_DIM)
		var chip := row.get_node("HBox/Doing/Chip") as Label
		var st := _status(m)
		chip.text = st[0]
		chip.add_theme_color_override("font_color", CwPalette.ink(st[1]))


## A trait cell (Value label + Bar) of a roster row: "?" while hidden.
func _trait(cell: Node, m: Dictionary, t: String) -> void:
	var known := TycoonCrew.trait_known(m, t)
	var v := float(m.get(t, 0.0))
	var lbl := cell.get_node("Value") as Label
	lbl.text = "%d" % roundi(v * 100.0) if known else "?"
	lbl.add_theme_color_override("font_color", CwPalette.COMET_ICE if known else CwPalette.TEXT_DIM)
	(cell.get_node("Bar") as CwSegmentBar).value = v if known else 0.0


func _fill_market(cands: Array) -> void:
	%MarketNext.text = tr("TY_CREW_MARKET_NEXT") % TycoonCrew.weeks_to_market(state)
	%MarketLimit.text = tr("TY_CREW_MARKET_LIMIT") % [state.staff.size(), TycoonCrew.staff_limit(state),
		TycoonCrew.building_level(state, "hq")]
	%MarketLimit.add_theme_color_override("font_color",
		CwPalette.WARNING if state.staff.size() >= TycoonCrew.staff_limit(state) else CwPalette.TEXT_DIM)
	%EmptyMarket.visible = cands.is_empty()
	var rows := TycoonHUD._copies(%CandTemplate, cands.size())
	for i in cands.size():
		var c: Dictionary = cands[i]
		var row := rows[i] as Button
		row.set_meta("id", String(c["id"]))
		if not row.has_meta("wired"):
			row.set_meta("wired", true)
			row.pressed.connect(func() -> void: select_candidate(String(row.get_meta("id"))))
		row.set_pressed_no_signal(String(c["id"]) == selected_cand)
		var col := TycoonCrew.profession_color(state, String(c["profession"]))
		(row.get_node("HBox/Tab") as ColorRect).color = col
		(row.get_node("HBox/Bulb") as TextureRect).self_modulate = col
		(row.get_node("HBox/Who/Name") as Label).text = String(c["name"])
		var prof := row.get_node("HBox/Who/Prof") as Label
		prof.text = _prof_name(c)
		prof.add_theme_color_override("font_color", CwPalette.ink(col))
		(row.get_node("HBox/Who/Level") as Label).text = "%s %d · %d XP" % [tr("TY_CREW_LEVEL"), int(c["level"]),
			roundi(float(c["xp"]))]
		for t: String in TycoonCrew.TRAITS:
			_trait(row.get_node("HBox/Traits/" + t.capitalize()), c, t)
		(row.get_node("HBox/Money/Ask") as Label).text = tr("TY_CREW_SALARY_MONTH") % TycoonHUD.fmt_cr(TycoonCrew.salary(state, c))
		var fee := TycoonCrew.hire_fee(state, c)
		var fee_l := row.get_node("HBox/Money/Fee") as Label
		fee_l.text = TycoonHUD.fmt_cr(fee)
		fee_l.add_theme_color_override("font_color", CwPalette.DANGER if state.cash < fee else CwPalette.COMET_ICE)
		var hidden: Array = c.get("hidden", [])
		(row.get_node("HBox/Reveal") as Label).text = tr("TY_CREW_ALL_KNOWN") if hidden.is_empty() \
			else tr("TY_CREW_HIDDEN_LEFT") % hidden.size()


# ------------------------------------------------------------ card
func _show_member(m: Dictionary) -> void:
	%Card.visible = not m.is_empty()
	if m.is_empty():
		return
	_card_common(m)
	var mo := float(m["morale"])
	for n in [%MoraleLabel, %MoraleBar, %MoraleValue]:
		(n as Control).visible = true
	%MoraleBar.value = mo / 100.0
	%MoraleBar.color = _morale_color(mo)
	%MoraleValue.text = "%d" % roundi(mo)
	%MoraleValue.add_theme_color_override("font_color", _morale_color(mo))
	%Mood.text = _mood_line(m)
	%Cap1.text = tr("TY_CREW_COL_SALARY")
	%Val1.text = tr("TY_CREW_SALARY_MONTH") % TycoonHUD.fmt_cr(TycoonCrew.salary(state, m))
	%Cap2.text = tr("TY_CREW_ASSIGNED")
	%Val2.text = _project_name(String(m["assigned"]))
	%Cap3.text = tr("TY_CREW_HIRED")
	var hw := int(m.get("hired_week", 0))
	%Val3.text = tr("TY_CREW_FOUNDER") if hw == 0 and not String(m["id"]).begins_with("h") \
		else tr("TY_CREW_HIRED_VALUE") % [hw / state.weeks_per_year() + 1, hw % state.weeks_per_year() + 1]
	%SpecSection.visible = true
	_fill_specs(m)
	%FireButton.visible = not TycoonLeader.is_leader(m)
	%FireButton.text = tr("TY_CREW_FIRE_CONFIRM") % String(m["name"]) if _fire_armed == String(m["id"]) else tr("TY_CREW_FIRE")
	%HireButton.visible = false
	%Note.text = _note
	%Note.visible = _note != ""
	var look := "%s/%s/%s" % [m["id"], TycoonCrew.status(m), m["profession"]]
	if look != _shown_look:
		var first := not _shown_look.begins_with(String(m["id"]) + "/")
		_shown_look = look
		if bool(m.get("napping", false)):
			creature.play("sit")
		else:
			creature.play("idle")
			if first:
				creature.play_sequence(["wave"])


func _show_candidate(c: Dictionary) -> void:
	%Card.visible = not c.is_empty()
	if c.is_empty():
		return
	_card_common(c)
	for n in [%MoraleLabel, %MoraleBar, %MoraleValue]:
		(n as Control).visible = false
	var hidden: Array = c.get("hidden", [])
	%Mood.text = tr("TY_CREW_ALL_KNOWN") if hidden.is_empty() else tr("TY_CREW_HIDDEN_LEFT") % hidden.size()
	var fee := TycoonCrew.hire_fee(state, c)
	%Cap1.text = tr("TY_CREW_ASK")
	%Val1.text = tr("TY_CREW_SALARY_MONTH") % TycoonHUD.fmt_cr(TycoonCrew.salary(state, c))
	%Cap2.text = tr("TY_CREW_FEE")
	%Val2.text = TycoonHUD.fmt_cr(fee)
	%Cap3.text = tr("TY_CREW_STAFF")
	%Val3.text = "%d / %d" % [state.staff.size(), TycoonCrew.staff_limit(state)]
	%SpecSection.visible = false
	%FireButton.visible = false
	%HireButton.visible = true
	%HireButton.text = tr("TY_CREW_HIRE") % TycoonHUD.fmt_cr(fee)
	var err := TycoonCrew.can_hire(state, String(c["id"]))
	%HireButton.disabled = err != ""
	%Note.text = tr(err) if err != "" else _note
	%Note.visible = %Note.text != ""
	var look := "cand/%s" % c["id"]
	if look != _shown_look:
		_shown_look = look
		creature.play("idle")
		creature.play_sequence(["nod"])


## Name, profession, colours, level and XP, traits and portrait: the same for staff and candidates.
func _card_common(m: Dictionary) -> void:
	var col := TycoonCrew.profession_color(state, String(m["profession"]))
	%CardName.text = String(m["name"])
	%CardProf.text = _prof_name(m)
	%CardProf.add_theme_color_override("font_color", CwPalette.ink(col))
	%ProfBulb.self_modulate = col
	%Glow.self_modulate = col
	%CardLook.text = "%s: %s" % [tr("TY_CREW_LOOK"), CometlingLooks.variant_name(int(m["variant"]))]
	%LeaderRow.visible = TycoonLeader.is_leader(m)
	%CardLook.visible = not TycoonLeader.is_leader(m)   # the leader has their own colours
	var lv := int(m["level"])
	%CardLevel.text = str(lv)
	%CardXPBar.value = TycoonCrew.level_progress(m)
	if lv >= TycoonCrew.max_level():
		%CardXP.text = tr("TY_CREW_XP_MAX")
	else:
		var into := float(m["xp"]) - (lv - 1) * TycoonCrew.xp_per_level()
		%CardXP.text = tr("TY_CREW_XP_NEXT") % [roundi(into), roundi(TycoonCrew.xp_per_level()), lv + 1]
	var bars := {"skill": [%SkillBar, %SkillValue], "curiosity": [%CuriosityBar, %CuriosityValue],
		"courage": [%CourageBar, %CourageValue]}
	for t: String in bars:
		var known := TycoonCrew.trait_known(m, t)
		var v := float(m.get(t, 0.0))
		(bars[t][0] as CwSegmentBar).value = v if known else 0.0
		var lbl := bars[t][1] as Label
		lbl.text = "%d" % roundi(v * 100.0) if known else "?"
		lbl.add_theme_color_override("font_color", CwPalette.COMET_ICE if known else CwPalette.TEXT_DIM)
	TycoonLeader.dress(creature, m)   # variant colours, or the leader's own look and hat
	creature.glow_color = col


func _fill_specs(m: Dictionary) -> void:
	var slots := TycoonCrew.spec_slots(state, m)
	var nodes := TycoonHUD._copies(%SlotTemplate, slots.size())
	for i in slots.size():
		var slot := slots[i]
		var n := nodes[i]
		var lv := int(slot["level"])
		(n.get_node("Head/Tier") as Label).text = tr("TY_CREW_SPEC_TIER") % ["I" if slot["tier"] == 1 else "II", lv]
		var value := n.get_node("Head/Value") as Label
		var desc := n.get_node("Desc") as Label
		var chosen := String(slot["chosen"])
		var options: Array[Dictionary] = []
		if chosen != "":
			value.text = tr("TY_CREW_SPEC_" + chosen.to_upper())
			value.add_theme_color_override("font_color", CwPalette.TEXT)
			desc.text = tr("TY_CREW_SPEC_" + chosen.to_upper() + "_DESC")
		else:
			value.text = tr("TY_CREW_SPEC_EMPTY")
			value.add_theme_color_override("font_color", CwPalette.IGNITION if slot["can_choose"] else CwPalette.TEXT_DIM)
			match String(slot["reason"]):
				"TY_CREW_SPEC_LOCKED":
					desc.text = tr("TY_CREW_SPEC_LOCKED") % lv
				"TY_CREW_SPEC_NEED_TRAINING":
					desc.text = tr("TY_CREW_SPEC_NEED_TRAINING") % int(slot["training_needed"])
				"":
					desc.text = tr("TY_CREW_SPEC_CHOOSE") % [TycoonHUD.fmt_cr(TycoonCrew.spec_cost(state, m)),
						int(TycoonCrew.data().get("spec_weeks", 2))]
					options = TycoonCrew.spec_options(m, int(slot["tier"]))
				_:
					desc.text = tr(String(slot["reason"]))
		var opts := TycoonHUD._copies(n.get_node("Options/OptionTemplate"), options.size())
		(n.get_node("Options") as Control).visible = not options.is_empty()
		for k in options.size():
			var b := opts[k] as Button
			var sid := String(options[k]["id"])
			b.set_meta("spec", sid)
			b.text = tr("TY_CREW_SPEC_" + sid.to_upper())
			b.tooltip_text = tr("TY_CREW_SPEC_" + sid.to_upper() + "_DESC")
			if not b.has_meta("wired"):
				b.set_meta("wired", true)
				b.pressed.connect(func() -> void: _on_spec(String(b.get_meta("spec"))))


# ------------------------------------------------------------ actions
func _on_hire() -> void:
	var err := TycoonCrew.hire(state, selected_cand)
	_note = tr(err) if err != "" else ""
	if err == "":
		selected = String(state.staff[state.staff.size() - 1]["id"])
		creature.play_sequence(["cheer", "jump"])
	refresh()


func _on_fire() -> void:
	var m := TycoonCrew.find(state, selected)
	if m.is_empty():
		return
	if _fire_armed != selected:
		_fire_armed = selected
		_note = ""
		refresh()
		return
	_fire_armed = ""
	var err := TycoonCrew.fire(state, selected)
	_note = tr(err) if err != "" else ""
	refresh()


func _on_spec(spec_id: String) -> void:
	var err := TycoonCrew.choose_spec(state, selected, spec_id)
	_note = tr(err) if err != "" else ""
	if err == "":
		creature.play_sequence(["cheer"])
	refresh()


# ------------------------------------------------------------ text helpers
func _prof_name(m: Dictionary) -> String:
	return tr(String(state.profession(String(m.get("profession", ""))).get("name_key", "")))


## What a project id is called on screen (its code when the project system knows it).
func _project_name(pid: String) -> String:
	if pid == "":
		return "—"
	for p in state.projects:
		if String(p.get("id", "")) == pid:
			return String(p.get("code", pid))
	return pid


## [chip text, chip colour] for a roster row.
func _status(m: Dictionary) -> Array:
	match TycoonCrew.status(m):
		"nap":
			return [tr("TY_CREW_ST_NAP"), CwPalette.WARNING]
		"adapting":
			return [tr("TY_CREW_ST_ADAPTING") % int(m["adapt_weeks"]), CwPalette.AURORA_VIOLET]
		"training":
			return [tr("TY_CREW_ST_TRAINING") % int(m["train_weeks"]), CwPalette.AURORA_VIOLET]
	if TycoonCrew.spec_pending(state, m):
		for slot in TycoonCrew.spec_slots(state, m):
			if slot["can_choose"]:
				return [tr("TY_CREW_ST_SPEC"), CwPalette.IGNITION]
	if TycoonCrew.status(m) == "busy":
		return [tr("TY_CREW_ST_BUSY"), CwPalette.AURORA_TEAL]
	return [tr("TY_CREW_ST_IDLE"), CwPalette.TEXT_DIM]


func _mood_line(m: Dictionary) -> String:
	match TycoonCrew.status(m):
		"nap":
			return tr("TY_CREW_LINE_NAP")
		"adapting":
			return tr("TY_CREW_LINE_ADAPTING") % int(m["adapt_weeks"])
		"training":
			return tr("TY_CREW_LINE_TRAINING") % int(m["train_weeks"])
		"busy":
			var limit := TycoonCrew.morale_rule("overwork_weeks", 8.0) + TycoonCrew.spec_effect(m, "overwork_weeks")
			if int(m["busy_weeks"]) > limit:
				return tr("TY_CREW_LINE_OVERWORK") % int(m["busy_weeks"])
			return tr("TY_CREW_LINE_BUSY") % _project_name(String(m["assigned"]))
	return tr("TY_CREW_LINE_IDLE")


static func _mood_key(mo: float) -> String:
	if mo >= 80.0:
		return "TY_CREW_MOOD_GREAT"
	if mo >= 50.0:
		return "TY_CREW_MOOD_GOOD"
	if mo >= 30.0:
		return "TY_CREW_MOOD_TIRED"
	return "TY_CREW_MOOD_LOW"


static func _morale_color(mo: float) -> Color:
	if mo < 30.0:
		return CwPalette.DANGER
	if mo < 50.0:
		return CwPalette.WARNING
	return CwPalette.AURORA_TEAL
