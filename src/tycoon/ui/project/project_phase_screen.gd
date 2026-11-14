extends Control
## Phase screen (scenes/tycoon/ui/screens/project_phase.tscn, GDD 6.4 / 22.4): pops at the
## start of each phase of a project (the clock is paused by ProjectFlow). Three throttle
## levers split the team's time (moving one pulls the others, the total stays 100%); under
## each, what it feeds. On the right, a live preview of the 4 bars at the end of the phase
## with the ideal ratio engraved on each meter, the balance match and the defects.
## The levers, rows and colours are in the scene; this script only fills data.

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var project: MissionProject
var values: Array[int] = [34, 33, 33]
var _levers: Array[Control] = []


func _ready() -> void:
	_levers = [%Lever0, %Lever1, %Lever2]
	for i in 3:
		var sl := _levers[i].get_node("Slider") as VSlider
		sl.value_changed.connect(func(v: float) -> void: _on_lever(i, roundi(v)))
	%Confirm.pressed.connect(_confirm)


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h


## args: {"project_id"}
func open_with(args: Dictionary) -> void:
	project = ProjectDesk.find(state, String(args.get("project_id", "")))
	if project == null:
		_close()
		return
	var cur: Array = project.phase_values()
	values = [int(cur[0]), int(cur[1]), int(cur[2])]
	_fill_static()
	_update()


func _close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


func _confirm() -> void:
	if project:
		ProjectDesk.set_sliders(state, project.id, values)
	_close()


func _on_lever(i: int, v: int) -> void:
	values = ProjectRules.rebalance(values, i, v)
	_update()


# ------------------------------------------------------------ fill
func _fill_static() -> void:
	var mt := project.mission_type(state)
	var k := project.phase
	%ProjectLine.text = "%s · %s · %s" % [project.code, tr(String(mt.get("name_key", ""))),
		tr(String(state.mission_target(project.target_id).get("name_key", "")))]
	%PhaseTitle.text = "%s · %s" % [tr("TY_PJ_PHASE_OF") % (k + 1), tr(String(ProjectRules.phase(k).get("name_key", "")))]
	(%Pips as CwSegmentBar).value = float(k + 1) / 3.0
	%TeamWeeks.text = tr("TY_PJ_PHASE_WEEKS") % [project.staff_ids.size(), project.phase_weeks_left()]
	var sliders := ProjectRules.sliders(k)
	for i in 3:
		var sd: Dictionary = sliders[i] if i < sliders.size() else {}
		var lever := _levers[i]
		(lever.get_node("Name") as Label).text = tr(String(sd.get("name_key", "")))
		var feeds: Dictionary = sd.get("feeds", {})
		var keys: Array = feeds.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return float(feeds[a]) > float(feeds[b]))
		var rows := TycoonHUD._copies(lever.get_node("Feeds/FeedTemplate"), keys.size())
		for j in keys.size():
			var bar := String(keys[j])
			(rows[j].get_node("Chip") as ColorRect).color = CwPalette.BARS.get(bar, CwPalette.TEXT_DIM)
			(rows[j].get_node("Text") as Label).text = "%s %.1f" % [tr("TY_BAR_" + bar.to_upper()), float(feeds[bar])]
		var extra := lever.get_node("Extra") as Label
		extra.visible = sd.get("removes_defects", false) or sd.get("extra_xp", false)
		extra.text = tr("TY_PJ_REMOVES_DEFECTS") if sd.get("removes_defects", false) else tr("TY_PJ_EXTRA_XP")
		# the lever's fill takes the colour of the bar it feeds most
		var sl := lever.get_node("Slider") as VSlider
		var fill := sl.get_theme_stylebox("grabber_area").duplicate() as StyleBoxFlat
		if fill and not keys.is_empty():
			fill.bg_color = CwPalette.BARS.get(String(keys[0]), CwPalette.IGNITION)
			sl.add_theme_stylebox_override("grabber_area", fill)
			sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	%ExpectedValue.text = "%d" % roundi(MissionProject.expected_points(state, project.type_id, state.project_history))
	var ideal := project.ideal(state)
	var rows: Array[Node] = [%PrevEng, %PrevSci, %PrevOps, %PrevRel]
	for b in 4:
		(rows[b].get_node("Bar") as CwSegmentBar).marker = ideal[b] / 0.6
		(rows[b].get_node("Ideal") as Label).text = "%d%%" % roundi(ideal[b] * 100.0)


func _update() -> void:
	for i in 3:
		var sl := _levers[i].get_node("Slider") as VSlider
		sl.set_value_no_signal(values[i])
		(_levers[i].get_node("Value") as Label).text = "%d%%" % values[i]
	%TotalValue.text = "%d%%" % (values[0] + values[1] + values[2])
	var sim := project.simulate_phase(state, values)
	var frac := sim.fractions()
	var rows: Array[Node] = [%PrevEng, %PrevSci, %PrevOps, %PrevRel]
	for b in 4:
		# the meter spans 0..60% so the ideal ticks sit well apart
		(rows[b].get_node("Bar") as CwSegmentBar).value = frac[b] / 0.6
		(rows[b].get_node("Value") as Label).text = "%d%%" % roundi(frac[b] * 100.0)
	var m := MissionProject.ratio_match(frac, project.ideal(state))
	%MatchValue.text = "%d%%" % roundi(m * 100.0)
	%MatchValue.add_theme_color_override("font_color", CwPalette.AURORA_TEAL if m >= 0.85
		else (CwPalette.WARNING if m >= 0.65 else CwPalette.DANGER))
	%DefectsValue.text = "%.1f" % sim.defects
	%DefectsValue.add_theme_color_override("font_color", CwPalette.COMET_ICE if sim.defects < 1.0
		else (CwPalette.WARNING if sim.defects < 3.0 else CwPalette.DANGER))
	%PointsValue.text = "%d" % roundi(sim.total_points())
