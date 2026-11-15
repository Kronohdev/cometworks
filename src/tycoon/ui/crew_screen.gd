class_name CrewScreen
extends Control
## Crew screen (scenes/tycoon/ui/screens/crew.tscn), opened by the HUD's Crew rail button. Its
## pages (a CwPageStack, with the breadcrumb CwNavBar and the CwPageTabs in the header):
##   Roster  the Cometlings as cards (portrait, name, profession, level, mood, what they are
##           doing), filtered by profession / available / napping and sorted by level, name or
##           mood; a card opens the Cometling's sheet
##   Sheet   one Cometling (or a candidate): big live 3D portrait, level and XP, traits, mood,
##           salary, specialisations, their milestones (CrewMemory), the missions they flew;
##           fire / specialise / hire here
##   Hire    the hiring market (3 candidates a month, hidden traits as "?") as cards; a card
##           opens the candidate's sheet
## The team summary (head count, payroll, average mood) is a strip in the header. Everything
## visual is in the scene; cards, chips, slots and history rows are copies of hidden templates
## there, and card portraits are stills from the scene's CwPortraitStudio. Rules come from
## TycoonCrew.

const SORTS: Array[String] = ["level", "name", "morale"]

var state: TycoonState
var clock: TycoonClock
var hud: Node
## "roster" | "hire" (the tab on show)
var tab := "roster"
## the Cometling on the sheet (or last opened)
var selected := ""
## the candidate on the sheet (or last opened)
var selected_cand := ""
## "staff" | "cand": who the sheet shows
var sheet_kind := "staff"
## roster filters: a profession id ("" = all), "free" / "nap" / ""
var filter_prof := ""
var filter_state := ""
var sort_by := "level"
var _fire_armed := ""
var _note := ""
var _shown_look := ""

@onready var pages: CwPageStack = %Pages
@onready var creature: Cometling = %Creature
@onready var studio: CwPortraitStudio = %Studio


func _ready() -> void:
	%CloseButton.pressed.connect(close)
	%FireButton.pressed.connect(_on_fire)
	%HireButton.pressed.connect(_on_hire)
	%EditLeader.pressed.connect(func() -> void:   # the leader creator, in edit mode
		if hud and hud.has_method("open_screen"):
			hud.call("open_screen", "leader_creator"))
	%WhoInspired.pressed.connect(_open_legend_card)
	%FilterAll.pressed.connect(func() -> void: set_filter("", ""))
	%FilterFree.pressed.connect(func() -> void: set_filter(filter_prof, "" if filter_state == "free" else "free"))
	%FilterNap.pressed.connect(func() -> void: set_filter(filter_prof, "" if filter_state == "nap" else "nap"))
	%SortKey.pressed.connect(func() -> void:
		sort_by = SORTS[(SORTS.find(sort_by) + 1) % SORTS.size()]
		refresh())
	pages.page_changed.connect(_on_page_changed)
	studio.shot.connect(func(_k: String, _t: Texture2D) -> void: _fill_portraits())


func bind(s: TycoonState, c: TycoonClock, h: Node) -> void:
	state = s
	clock = c
	hud = h
	TycoonCrew.ensure(state)
	state.changed.connect(refresh)
	if not state.staff.is_empty():
		selected = String(state.staff[0]["id"])
	refresh()


## args: {"tab": "roster" | "hire", "staff_id": id (opens their sheet), "cand_id": id}
func open_with(args: Dictionary) -> void:
	show_tab(String(args.get("tab", tab)))
	if args.has("staff_id"):
		select_member(String(args["staff_id"]))
	elif args.has("cand_id"):
		select_candidate(String(args["cand_id"]))


func close() -> void:
	if hud and hud.has_method("close_screen"):
		hud.call("close_screen")
	else:
		queue_free()


## Esc / back: the sheet goes back to its list first (TycoonHUD.screen_back).
func go_back() -> bool:
	return pages.back()


## Shows the roster ("roster") or the hiring market ("hire") at their top level.
func show_tab(t: String) -> void:
	tab = "hire" if t == "hire" else "roster"
	_note = ""
	_fire_armed = ""
	pages.switch_to(&"Hire" if tab == "hire" else &"Roster")
	refresh()


## Opens a Cometling's sheet from the roster.
func select_member(id: String) -> void:
	if state == null or TycoonCrew.find(state, id).is_empty():
		return
	selected = id
	sheet_kind = "staff"
	_note = ""
	_fire_armed = ""
	if tab != "roster":
		tab = "roster"
		pages.switch_to(&"Roster")
	pages.push(&"Sheet", String(TycoonCrew.find(state, id)["name"]))
	refresh()


## Opens a candidate's sheet from the hiring market.
func select_candidate(id: String) -> void:
	if state == null or TycoonCrew.find_candidate(state, id).is_empty():
		return
	selected_cand = id
	sheet_kind = "cand"
	_note = ""
	if tab != "hire":
		tab = "hire"
		pages.switch_to(&"Hire")
	pages.push(&"Sheet", String(TycoonCrew.find_candidate(state, id)["name"]))
	refresh()


func set_filter(prof: String, st: String) -> void:
	filter_prof = prof
	filter_state = st
	refresh()
	CwMotion.poke(self)   # the roster cascade (CwRoster, on_poke) plays again


func _on_page_changed(page: StringName, _depth: int) -> void:
	if page != &"Sheet":
		tab = "hire" if pages.root_page() == &"Hire" else "roster"
		_fire_armed = ""
	refresh()


# ------------------------------------------------------------ refresh
func refresh() -> void:
	if state == null or not is_inside_tree():
		return
	%StaffValue.text = "%d / %d" % [state.staff.size(), TycoonCrew.staff_limit(state)]
	%PayrollValue.text = TycoonHUD.fmt_cr(state.monthly_salaries())
	var avg := TycoonCrew.average_morale(state)
	%AvgMoraleValue.text = "%d" % roundi(avg)
	%AvgMoraleValue.add_theme_color_override("font_color", CwPalette.ink(_morale_color(avg)))
	(%AvgFace as CwMoodFace).mood = avg
	var cands := TycoonCrew.candidates(state)
	%HireTab.text = "%s · %d" % [tr("TY_CREW_TAB_HIRE"), cands.size()] if not cands.is_empty() else tr("TY_CREW_TAB_HIRE")
	_fill_filters()
	_fill_roster()
	_fill_market(cands)
	if pages.current() == &"Sheet":
		if sheet_kind == "staff":
			var m := TycoonCrew.find(state, selected)
			if m.is_empty():
				pages.back()   # fired: back to the roster
				return
			_show_member(m)
		else:
			var c := TycoonCrew.find_candidate(state, selected_cand)
			if c.is_empty():
				pages.back()   # hired by someone else / the market renewed
				return
			_show_candidate(c)


## The filter chips: everyone, one chip per profession on the team (with its count), the
## available / napping chips and the sort key.
func _fill_filters() -> void:
	%FilterAll.text = tr("TY_CREW_FILTER_ALL") % state.staff.size()
	%FilterAll.set_pressed_no_signal(filter_prof == "" and filter_state == "")
	%FilterFree.set_pressed_no_signal(filter_state == "free")
	%FilterNap.set_pressed_no_signal(filter_state == "nap")
	%SortKey.text = tr("TY_CREW_SORT_" + sort_by.to_upper())
	var present: Array[Dictionary] = []
	for p: Dictionary in state.pdata.get("professions", []):
		var n := 0
		for m in state.staff:
			n += 1 if m.get("profession", "") == p["id"] else 0
		if n > 0:
			present.append({"p": p, "n": n})
	if filter_prof != "" and not present.any(func(e: Dictionary) -> bool: return e["p"]["id"] == filter_prof):
		filter_prof = ""
	var chips := TycoonHUD._copies(%ProfChipTemplate, present.size())
	for i in present.size():
		var p: Dictionary = present[i]["p"]
		var b := chips[i] as Button
		var col := Color(String(p.get("color", "#8c9ab5")))
		b.text = "%d · %s" % [int(present[i]["n"]), tr(String(p.get("name_key", "")))]
		b.tooltip_text = tr("TY_CREW_FILTER_PROF_TIP") % tr("TY_BAR_" + String(p.get("primary", "eng")).to_upper())
		for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			b.add_theme_color_override(k, col)
		b.set_meta("prof", String(p["id"]))
		b.set_pressed_no_signal(filter_prof == String(p["id"]))
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void:
				var pid := String(b.get_meta("prof"))
				set_filter("" if filter_prof == pid else pid, filter_state))
	# the chips sit right after "everyone"
	for i in chips.size():
		%Filters.move_child(chips[i], %FilterAll.get_index() + 1 + i)


func _passes(m: Dictionary) -> bool:
	if filter_prof != "" and String(m.get("profession", "")) != filter_prof:
		return false
	match filter_state:
		"free":
			return TycoonCrew.status(m) == "idle"
		"nap":
			return TycoonCrew.status(m) == "nap"
	return true


func _roster() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in state.staff:
		if _passes(m):
			out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match sort_by:
			"name":
				return String(a["name"]) < String(b["name"])
			"morale":
				return float(a["morale"]) < float(b["morale"])
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) > int(b["level"])
		return float(a["xp"]) > float(b["xp"]))
	# the leader always leads the list on the default sort
	if sort_by == "level":
		for i in out.size():
			if TycoonLeader.is_leader(out[i]) and i > 0:
				out.push_front(out.pop_at(i))
				break
	return out


func _fill_roster() -> void:
	var list := _roster()
	var cards := TycoonHUD._copies(%CardTemplate, list.size())
	%RosterEmpty.visible = list.is_empty()
	%Grid.move_child(%RosterEmpty, %Grid.get_child_count() - 1)
	for i in list.size():
		var m: Dictionary = list[i]
		var card := cards[i] as Button
		var id := String(m["id"])
		card.set_meta("id", id)
		card.set_meta("member", m)
		if not card.has_meta("wired"):
			card.set_meta("wired", true)
			card.pressed.connect(func() -> void: select_member(String(card.get_meta("id"))))
		var col := TycoonCrew.profession_color(state, String(m["profession"]))
		var box := card.get_node("Box")
		(box.get_node("Name") as Label).text = String(m["name"])
		(box.get_node("Prof/Bulb") as TextureRect).self_modulate = col
		var pl := box.get_node("Prof/Name") as Label
		pl.text = _prof_name(m)
		pl.add_theme_color_override("font_color", CwPalette.ink(col))
		(box.get_node("Visor/Level/Text") as Label).text = tr("TY_CREW_LEVEL_SHORT") % int(m["level"])
		(box.get_node("Visor/Leader") as Control).visible = TycoonLeader.is_leader(m)
		(box.get_node("Visor/Fallback") as TextureRect).self_modulate = col
		var mo := float(m["morale"])
		(box.get_node("Mood/Face") as CwMoodFace).mood = mo
		var bar := box.get_node("Mood/Bar") as CwSegmentBar
		bar.value = mo / 100.0
		bar.color = _morale_color(mo)
		box.get_node("Mood").tooltip_text = "%s · %d" % [tr(_mood_key(mo)), roundi(mo)]
		var st := _status(m)
		var act := box.get_node("Activity/Text") as Label
		act.text = st[0] if TycoonCrew.status(m) != "busy" else "%s · %s" % [st[0], _project_name(String(m["assigned"]))]
		act.add_theme_color_override("font_color", CwPalette.ink(st[1]))
		box.get_node("Activity").tooltip_text = act.text   # the chip may shorten it
	_fill_portraits()


## Card portraits: the studio's stills (cards keep their profession badge until theirs is ready).
func _fill_portraits() -> void:
	for parent: Node in [%CardTemplate.get_parent(), %CandTemplate.get_parent()]:
		for card in parent.get_children():
			if not card.has_meta("from_template") or not card.has_meta("member"):
				continue
			var m: Dictionary = card.get_meta("member")
			var tex := studio.portrait(m, TycoonCrew.profession_color(state, String(m.get("profession", ""))))
			var pr := card.get_node("Box/Visor/Portrait") as TextureRect
			pr.texture = tex
			(card.get_node("Box/Visor/Fallback") as Control).visible = tex == null


func _fill_market(cands: Array) -> void:
	%MarketNext.text = tr("TY_CREW_MARKET_NEXT") % TycoonCrew.weeks_to_market(state)
	%MarketLimit.text = tr("TY_CREW_MARKET_LIMIT") % [state.staff.size(), TycoonCrew.staff_limit(state),
		TycoonCrew.building_level(state, "hq")]
	%MarketLimit.add_theme_color_override("font_color",
		CwPalette.WARNING if state.staff.size() >= TycoonCrew.staff_limit(state) else CwPalette.TEXT_DIM)
	%EmptyMarket.visible = cands.is_empty()
	# the Lendas on golden cards first, then the usual candidates
	var legends: Array = cands.filter(func(c: Dictionary) -> bool: return TycoonLegends.is_legend(c))
	var normal: Array = cands.filter(func(c: Dictionary) -> bool: return not TycoonLegends.is_legend(c))
	var gold := TycoonHUD._copies(%LegendCandTemplate, legends.size())
	for i in gold.size():
		%Cands.move_child(gold[i], i)
		_fill_cand_card(gold[i] as Button, legends[i])
		_fill_legend_card(gold[i] as Button, legends[i])
	var cards := TycoonHUD._copies(%CandTemplate, normal.size())
	for i in normal.size():
		_fill_cand_card(cards[i] as Button, normal[i])
	_fill_portraits()


## What a candidate card shares with the golden one: name, profession, level, salary, fee.
func _fill_cand_card(card: Button, c: Dictionary) -> void:
	card.set_meta("id", String(c["id"]))
	card.set_meta("member", c)
	if not card.has_meta("wired"):
		card.set_meta("wired", true)
		card.pressed.connect(func() -> void: select_candidate(String(card.get_meta("id"))))
	var col := TycoonCrew.profession_color(state, String(c["profession"]))
	var box := card.get_node("Box")
	(box.get_node("Name") as Label).text = String(c["name"])
	(box.get_node("Prof/Bulb") as TextureRect).self_modulate = col
	(box.get_node("Visor/Fallback") as TextureRect).self_modulate = col
	var prof := box.get_node("Prof/Name") as Label
	prof.text = _prof_name(c)
	prof.add_theme_color_override("font_color", CwPalette.ink(col))
	(box.get_node("Level") as Label).text = "%s %d · %d XP" % [tr("TY_CREW_LEVEL"), int(c["level"]), roundi(float(c["xp"]))]
	(box.get_node("Ask") as Label).text = tr("TY_CREW_SALARY_MONTH") % TycoonHUD.fmt_cr(TycoonCrew.salary(state, c))
	var fee := TycoonCrew.hire_fee(state, c)
	var fee_l := box.get_node("Fee") as Label
	fee_l.text = tr("TY_CREW_FEE_LINE") % TycoonHUD.fmt_cr(fee)
	fee_l.add_theme_color_override("font_color", CwPalette.DANGER if state.cash < fee else CwPalette.TEXT_DIM)
	var reveal := box.get_node_or_null("Reveal") as Label
	if reveal:
		var hidden: Array = c.get("hidden", [])
		reveal.text = tr("TY_CREW_ALL_KNOWN") if hidden.is_empty() else tr("TY_CREW_HIDDEN_LEFT") % hidden.size()


## The golden card's own lines: the unique specialisation and how long the Lenda stays.
func _fill_legend_card(card: Button, c: Dictionary) -> void:
	var id := String(c["legend"])
	var box := card.get_node("Box")
	(box.get_node("Spec") as Label).text = "★ " + tr(TycoonLegends.key(id, "SPEC"))
	card.tooltip_text = tr(TycoonLegends.key(id, "SPEC_DESC"))
	(box.get_node("Once") as Label).text = tr("TY_LEG_ONCE") % TycoonLegends.weeks_left(state, id)


# ------------------------------------------------------------ sheet
func _show_member(m: Dictionary) -> void:
	pages.set_title(String(m["name"]))
	_card_common(m)
	var mo := float(m["morale"])
	for n in [%MoraleLabel, %MoraleBar, %MoraleValue, %MoodFace]:
		(n as Control).visible = true
	%MoraleBar.value = mo / 100.0
	%MoraleBar.color = _morale_color(mo)
	%MoraleValue.text = "%d" % roundi(mo)
	%MoraleValue.add_theme_color_override("font_color", CwPalette.ink(_morale_color(mo)))
	(%MoodFace as CwMoodFace).mood = mo
	%Mood.text = _mood_line(m)
	var st := _status(m)
	%SheetStatus.text = st[0] if TycoonCrew.status(m) != "busy" else "%s · %s" % [st[0], _project_name(String(m["assigned"]))]
	%SheetStatus.add_theme_color_override("font_color", CwPalette.ink(st[1]))
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
	%Milestones.visible = true
	_fill_milestones(m)
	%History.visible = true
	_fill_history(m)
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
	pages.set_title(String(c["name"]))
	_card_common(c)
	for n in [%MoraleLabel, %MoraleBar, %MoraleValue, %MoodFace]:
		(n as Control).visible = false
	var hidden: Array = c.get("hidden", [])
	%Mood.text = tr("TY_CREW_ALL_KNOWN") if hidden.is_empty() else tr("TY_CREW_HIDDEN_LEFT") % hidden.size()
	%SheetStatus.text = tr("TY_CREW_CANDIDATE")
	%SheetStatus.add_theme_color_override("font_color", CwPalette.ink(CwPalette.AURORA_VIOLET))
	var fee := TycoonCrew.hire_fee(state, c)
	%Cap1.text = tr("TY_CREW_ASK")
	%Val1.text = tr("TY_CREW_SALARY_MONTH") % TycoonHUD.fmt_cr(TycoonCrew.salary(state, c))
	%Cap2.text = tr("TY_CREW_FEE")
	%Val2.text = TycoonHUD.fmt_cr(fee)
	%Cap3.text = tr("TY_CREW_STAFF")
	%Val3.text = "%d / %d" % [state.staff.size(), TycoonCrew.staff_limit(state)]
	%SpecSection.visible = false
	%Milestones.visible = false
	%History.visible = false
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
	var legend := TycoonLegends.is_legend(m)
	%CardLook.visible = not TycoonLeader.is_leader(m) and not legend   # they have their own colours
	%LegendRow.visible = legend
	%LegendSpec.visible = legend
	if legend:   # the unique specialisation, its effect and the Lenda's way of being
		var id := String(m["legend"])
		%LegendSpecName.text = tr(TycoonLegends.key(id, "SPEC"))
		%LegendSpecDesc.text = tr(TycoonLegends.key(id, "SPEC_DESC"))
		%LegendWay.text = tr(TycoonLegends.key(id, "WAY"))
		%WhoInspired.set_meta("legend", id)
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
	creature = TycoonLeader.dress(creature, m)   # variant colours, the leader's look and hat, a Lenda's own body
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
					options = TycoonCrew.spec_options(m, int(slot["tier"]), state)
					# the ones research has not opened yet, by name ("A pesquisa abre mais: ...")
					var later: Array[String] = []
					for sp in TycoonCrew.spec_locked(m, int(slot["tier"]), state):
						later.append(tr("TY_CREW_SPEC_" + String(sp["id"]).to_upper()))
					if not later.is_empty():
						desc.text += " " + tr("TY_CREW_SPEC_MORE") % ", ".join(later)
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


## The Cometling's milestones (CrewMemory) as chips, in the order earned, with their totals; the
## tooltip tells what it was for and on which mission.
func _fill_milestones(m: Dictionary) -> void:
	var ms := CrewMemory.milestones_of(m)
	var chips := TycoonHUD._copies(%MsTemplate, ms.size())
	%MsEmpty.visible = ms.is_empty()
	%MemSummary.visible = CrewMemory.count(m, "missions") > 0
	%MemSummary.text = tr("TY_MEM_SUMMARY") % [CrewMemory.count(m, "missions"), CrewMemory.count(m, "successes"),
		CrewMemory.count(m, "failures")]
	for i in ms.size():
		var r := ms[i]
		var chip := chips[i] as PanelContainer
		var col: Color = r["color"]
		var sb := chip.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		sb.border_color = col
		chip.add_theme_stylebox_override("panel", sb)
		var icon := chip.get_node("HBox/Icon") as TextureRect
		icon.texture = load(String(r["icon"])) as Texture2D
		icon.self_modulate = col
		(chip.get_node("HBox/Name") as Label).text = tr(String(r["name_key"]))
		var w := int(r.get("w", 0))
		chip.tooltip_text = tr("TY_MEM_MS_TIP") % [tr(String(r["desc_key"])), String(r.get("code", "")),
			w / state.weeks_per_year() + 1]


## The missions the Cometling worked on (launched projects with them on the team), newest first.
func _fill_history(m: Dictionary) -> void:
	var id := String(m["id"])
	var rows: Array[Dictionary] = []
	for i in range(state.project_history.size() - 1, -1, -1):
		var h: Dictionary = state.project_history[i]
		if id in Array(h.get("staff", [])).map(func(x: Variant) -> String: return String(x)):
			rows.append(h)
		if rows.size() >= 8:
			break
	var lines := TycoonHUD._copies(%HistTemplate, rows.size())
	%HistEmpty.visible = rows.is_empty()
	for i in rows.size():
		var h := rows[i]
		(lines[i].get_node("Code") as Label).text = String(h.get("code", ""))
		var ty := tr(String(state.mission_type(String(h.get("type", ""))).get("name_key", "")))
		var tg := tr(String(state.mission_target(String(h.get("target", ""))).get("name_key", "")))
		(lines[i].get_node("What") as Label).text = "%s · %s" % [ty, tg]
		var ok := bool(h.get("success", false))
		var res := lines[i].get_node("Result") as Label
		# how it went, as the crew remembers it: a first for the agency, a success, a partial, a failure
		var o := CrewMemory.outcome_of(h)
		var word: String = {"first": "TY_MEM_HIST_FIRST", "partial": "TY_MEM_HIST_PARTIAL"}.get(o, "TY_CREW_HIST_OK" if ok else "TY_CREW_HIST_FAIL")
		var col := {"first": CwPalette.IGNITION, "partial": CwPalette.WARNING}.get(o, CwPalette.SUCCESS if ok else CwPalette.DANGER) as Color
		res.text = tr(String(word)) + " · %.1f" % float(h.get("grade", 0.0))
		res.add_theme_color_override("font_color", CwPalette.ink(col))


# ------------------------------------------------------------ actions
## The encyclopedia's "Quem inspirou" card of the Lenda on the sheet.
func _open_legend_card() -> void:
	var id := String(%WhoInspired.get_meta("legend", ""))
	if id != "" and hud and hud.has_method("open_screen"):
		hud.call("open_screen", "book", {"legend": id})


func _on_hire() -> void:
	var err := TycoonCrew.hire(state, selected_cand)
	_note = tr(err) if err != "" else ""
	if err == "":
		# the new Cometling's own sheet, from the roster
		var id := String(state.staff[state.staff.size() - 1]["id"])
		select_member(id)
		creature.play_sequence(["cheer", "jump"])
		return
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


## [chip text, chip colour] for a card.
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
