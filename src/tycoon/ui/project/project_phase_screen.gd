extends Control
## Phase screen (scenes/tycoon/ui/screens/project_phase.tscn, GDD 6.4 / 22.4): pops at the
## start of each phase of a project (the clock is paused by ProjectFlow). Three throttle
## levers split the team's time (moving one pulls the others, the total stays 100%); under
## each, what it feeds. On the right, a live preview of the 4 bars at the end of the phase, the
## defects and the work the whole project will have at launch against what the press expects.
## What the agency knows of the type's bars (FocusStudy: lab studies, flights, the journal) shows
## where it is used, by tier:
##   0  "?" everywhere, and how to find out (study it in the lab, or fly it)
##   1  the bar that matters most / least on the meters, the lever to focus on in this phase
##      (the header says "Focus of this phase: ...")
##   2  every bar's weight in words, an arrow on each lever (more / less time), an approximate
##      balance match, and the study's suggested split (a button)
##   3  the ideal engraved on each meter, the green band of the range that hits it on each
##      lever, the exact match
## A briefing client's own priorities never show (the story tells them). A short advice list
## says why a bar runs low (no one of its profession on the team, below what the mission asks,
## many defects). The levers, rows and colours are in the scene; this script only fills data.

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var project: MissionProject
var values: Array[int] = [34, 33, 33]
var _levers: Array[Control] = []
## what the agency knows of this project's balance (FocusStudy tier; 0 for a client's own)
var _tier := 0
var _client := false
## the balance the screen measures against: the real ideal (tier 3), the coarse one (tier 2)
var _known_ideal: Array[float] = []
## team_ranges() of this phase (computed when the screen opens)
var _ranges: Array = []


func _ready() -> void:
	_levers = [%Lever0, %Lever1, %Lever2]
	for i in 3:
		var sl := _levers[i].get_node("Slider") as VSlider
		sl.value_changed.connect(func(v: float) -> void: _on_lever(i, roundi(v)))
		sl.resized.connect(_place_bands)
	%Confirm.pressed.connect(_confirm)
	%Suggest.pressed.connect(apply_suggestion)


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


## The study's split for this phase (tier 2: from the levels, tier 3: the exact best).
func suggestion() -> Array[int]:
	var out: Array[int] = []
	if _ranges.size() == 3:
		for i in 3:
			out.append(int(_ranges[i][2]))
	return out


## The lever ranges that hit the known balance best with THIS team, counting the points the
## project already has: [[lo, hi, best] x 3] in percent (journal lever_step; the splits within
## lever_slack of the best match). [] when the balance is not known (tier < 2, a client's own).
func team_ranges() -> Array:
	if _known_ideal.is_empty():
		return []
	var c := BriefingDesk.disc()
	var step := int(c.get("lever_step", 5))
	var slack := float(c.get("lever_slack", 0.02))
	var combos: Array = []
	var best := -1.0
	for a in range(0, 101, step):
		for b in range(0, 101 - a, step):
			var split := [a, b, 100 - a - b]
			var m := MissionProject.ratio_match(project.simulate_phase(state, split).fractions(), _known_ideal)
			combos.append([m, split])
			best = maxf(best, m)
	var lo := [100, 100, 100]
	var hi := [0, 0, 0]
	var top: Array = []
	for e: Array in combos:
		if float(e[0]) >= best - slack:
			for i in 3:
				lo[i] = mini(lo[i], int(e[1][i]))
				hi[i] = maxi(hi[i], int(e[1][i]))
		if top.is_empty() and float(e[0]) >= best - 1e-6:
			top = e[1]
	var out: Array = []
	for i in 3:
		out.append([lo[i], hi[i], int(top[i])])
	return out


func apply_suggestion() -> void:
	var best := suggestion()
	if best.size() == 3:
		values = [best[0], best[1], best[2]]
		_update()


# ------------------------------------------------------------ fill
func _fill_static() -> void:
	var mt := project.mission_type(state)
	var k := project.phase
	var ty := project.type_id
	%ProjectLine.text = "%s · %s · %s" % [project.code, tr(String(mt.get("name_key", ""))),
		tr(String(state.mission_target(project.target_id).get("name_key", "")))]
	%PhaseTitle.text = "%s · %s" % [tr("TY_PJ_PHASE_OF") % (k + 1), tr(String(ProjectRules.phase(k).get("name_key", "")))]
	(%Pips as CwSegmentBar).value = float(k + 1) / 3.0
	%TeamWeeks.text = tr("TY_PJ_PHASE_WEEKS") % [project.staff_ids.size(), project.phase_weeks_left()]
	_client = BriefingDesk.ratio(BriefingDesk.briefing(project.briefing_id)).size() == 4
	_tier = 0 if _client else FocusStudy.tier(state, ty)
	_known_ideal = []
	if _tier >= FocusStudy.MAX_TIER:
		_known_ideal = project.ideal(state)
	elif _tier == 2:
		_known_ideal = FocusStudy.coarse_ideal(state, ty)
	var sliders := ProjectRules.sliders(k)
	_ranges = team_ranges()
	# tier 2: arrows from the best split for this team (more / less than a third)
	var arrows: Array = []
	if _tier == 2 and _ranges.size() == 3:
		var up := int(FocusStudy.cfg().get("arrow_up", 45))
		var down := int(FocusStudy.cfg().get("arrow_down", 20))
		for i in 3:
			var v := int(_ranges[i][2])
			arrows.append(1 if v >= up else (-1 if v <= down else 0))
	var focus := FocusStudy.focus_lever(state, ty, k) if _tier >= 1 else -1
	var ranges: Array = _ranges if _tier >= FocusStudy.MAX_TIER else []
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
			(rows[j].get_node("Text") as Label).text = tr("TY_FS_FEED") % [roundi(float(feeds[bar]) * 100.0), tr("TY_BAR_" + bar.to_upper())]
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
		# what the study says about this lever
		var rl := lever.get_node("Range") as Label
		if not ranges.is_empty():
			var r: Array = ranges[i]
			rl.text = tr("TY_FS_RANGE") % [int(r[0]), int(r[1])]
			rl.add_theme_color_override("font_color", CwPalette.AURORA_TEAL)
		elif not arrows.is_empty():
			var a := int(arrows[i])
			rl.text = tr("TY_FS_ARROW_UP") if a > 0 else (tr("TY_FS_ARROW_DOWN") if a < 0 else tr("TY_FS_ARROW_EVEN"))
			rl.add_theme_color_override("font_color", CwPalette.IGNITION if a > 0 else (CwPalette.COMET_ICE if a < 0 else CwPalette.TEXT_DIM))
		elif focus == i:
			rl.text = tr("TY_FS_FOCUS_LEVER")
			rl.add_theme_color_override("font_color", CwPalette.IGNITION)
		else:
			rl.text = " "
		var band := sl.get_node("Band") as Control
		band.visible = not ranges.is_empty()
		band.set_meta("range", ranges[i] if not ranges.is_empty() else [])
	_place_bands()
	# the header: the phase's focus, once known
	if _tier >= 1:
		%Hint.text = _phase_focus_text(focus)
		%Hint.add_theme_color_override("font_color", CwPalette.ink(CwPalette.IGNITION))
	else:
		%Hint.text = tr("TY_PJ_PHASE_HINT")
		%Hint.remove_theme_color_override("font_color")
	# the meters' focus column
	var marks := FocusStudy.bar_marks(state, ty)
	var rows2: Array[Node] = [%PrevEng, %PrevSci, %PrevOps, %PrevRel]
	for b in 4:
		var m: Dictionary = marks[b] if not _client else {"tier": 0, "mark": "", "ideal": -1.0}
		(rows2[b].get_node("Bar") as CwSegmentBar).marker = float(m["ideal"]) / 0.6 if float(m["ideal"]) >= 0.0 else -1.0
		var il := rows2[b].get_node("Ideal") as Label
		il.text = FocusView.mark_text(m)
		il.add_theme_color_override("font_color", FocusView.mark_color(m))
	# what we know
	(%TierPips as CwSegmentBar).value = float(_tier) / 3.0
	%TierName.text = FocusView.tier_text(_tier)
	if _client:
		%KnowText.text = tr("TY_PJ_IDEAL_CLIENT")
		%HowText.text = tr("TY_FS_CLIENT_NOTE")
	else:
		%KnowText.text = FocusView.know_text(state, ty)
		%HowText.text = FocusView.how_text(state, ty)
	%HowText.visible = %HowText.text != ""
	%Suggest.visible = suggestion().size() == 3


## "Focus of this phase: Mission architecture (feeds Engineering, what matters most)."
func _phase_focus_text(focus: int) -> String:
	var tops := FocusStudy.top_bars(state, project.type_id)
	var top_name := FocusView.bar_name(tops[0])
	if focus < 0:
		var bottoms := FocusStudy.bottom_bars(state, project.type_id)
		return tr("TY_FS_PHASE_NOFOCUS") % [top_name, FocusView.bar_name(bottoms[0])]
	var sd: Dictionary = ProjectRules.sliders(project.phase)[focus]
	return tr("TY_FS_PHASE_FOCUS") % [tr(String(sd.get("name_key", ""))), top_name]


## The green band of each lever over its slider track: the range that hits the ideal. The
## slider's grabber travels its height minus the grabber, so the band follows that travel.
func _place_bands() -> void:
	for i in _levers.size():
		var sl := _levers[i].get_node("Slider") as VSlider
		var band := sl.get_node("Band") as Control
		var r: Array = band.get_meta("range", [])
		if r.is_empty():
			continue
		var g := sl.get_theme_icon("grabber")
		var gh := float(g.get_height()) if g else 0.0
		var hi := float(r[1]) / 100.0
		var lo := float(r[0]) / 100.0
		band.anchor_top = 1.0 - hi
		band.anchor_bottom = 1.0 - lo
		band.offset_top = gh * (hi - 0.5) - 2.0
		band.offset_bottom = gh * (lo - 0.5) + 2.0


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
	# the balance match against what is known (exact at tier 3, approximate at tier 2)
	var known := not _known_ideal.is_empty()
	var m := MissionProject.ratio_match(frac, _known_ideal) if known else 0.0
	if not known:
		%MatchValue.text = "?"
	elif _tier >= FocusStudy.MAX_TIER:
		%MatchValue.text = "%d%%" % roundi(m * 100.0)
	else:
		%MatchValue.text = tr("TY_FS_MATCH_APPROX") % roundi(m * 100.0)
	%MatchValue.add_theme_color_override("font_color", (CwPalette.AURORA_TEAL if m >= 0.85
		else (CwPalette.WARNING if m >= 0.65 else CwPalette.DANGER)) if known else CwPalette.TEXT_DIM)
	%DefectsValue.text = "%.1f" % sim.defects
	%DefectsValue.add_theme_color_override("font_color", CwPalette.COMET_ICE if sim.defects < 1.0
		else (CwPalette.WARNING if sim.defects < 3.0 else CwPalette.DANGER))
	# the work the whole project will have at launch vs what the press expects
	var end := project.simulate_to_end(state, values)
	var expected := MissionProject.expected_points(state, project.type_id, state.project_history)
	var q := end.total_points() / maxf(expected, 0.001)
	%WorkValue.text = "%d / %d" % [roundi(end.total_points()), roundi(expected)]
	var cap := ProjectRules.num("grade", "q_cap", 1.5)
	(%WorkBar as CwSegmentBar).value = clampf(q / cap, 0.0, 1.0)
	(%WorkBar as CwSegmentBar).color = CwPalette.OPS if q >= 1.0 else (CwPalette.BUTTER if q >= 0.7 else CwPalette.PINK)
	%WorkValue.add_theme_color_override("font_color", CwPalette.AURORA_TEAL if q >= 1.0 else (CwPalette.WARNING if q >= 0.7 else CwPalette.DANGER))
	_fill_advice(frac, sim.defects, q)
	%Suggest.disabled = suggestion() == values


## At most two lines on why a bar runs low or what to change: [[text, good?]].
func advice(frac: Array[float], defects: float, q: float) -> Array[Array]:
	var out: Array[Array] = []
	var ty := project.type_id
	var k := project.phase
	var m := ProjectRules.feed_matrix(k)
	# a known gap: the bar furthest from what the mission asks that this phase can move
	if not _known_ideal.is_empty() and suggestion() == values:
		out.append([tr("TY_FS_ADV_BEST"), true])
	elif not _known_ideal.is_empty():
		var gb := -1
		var gap := 0.0
		for b in 4:
			if _lever_for(m, b) < 0:
				continue
			var g := frac[b] - _known_ideal[b]
			if absf(g) > absf(gap):
				gap = g
				gb = b
		var slack := float(BriefingDesk.disc().get("lever_gap", 0.08)) * (1.0 if _tier >= FocusStudy.MAX_TIER else 1.5)
		if gb >= 0 and absf(gap) >= slack:
			var lever := tr(String(ProjectRules.sliders(k)[_lever_for(m, gb)].get("name_key", "")))
			out.append([tr("TY_FS_ADV_RAISE" if gap < 0.0 else "TY_FS_ADV_LOWER") % [FocusView.bar_name(gb), lever], false])
		elif gb >= 0:
			out.append([tr("TY_FS_ADV_GOOD"), true])
	elif _tier == 1 and not _client:
		var top := FocusStudy.top_bars(state, ty)[0]
		var biggest := 0
		for b in 4:
			if frac[b] > frac[biggest]:
				biggest = b
		if frac[top] < frac[biggest] - 0.001 and _lever_for(m, top) >= 0:
			out.append([tr("TY_FS_ADV_TOP") % [FocusView.bar_name(top),
				tr(String(ProjectRules.sliders(k)[_lever_for(m, top)].get("name_key", "")))], false])
	# a bar no one on the team works in (the ones that matter first)
	var orphans := FocusStudy.orphan_bars(state, project.staff_ids)
	var pick := -1
	for b in orphans:
		if not _client and FocusStudy.known_important(state, ty, b):
			pick = b
			break
	if pick < 0:
		for b in orphans:
			var low_known := not _client and FocusStudy.known_unimportant(state, ty, b)
			if frac[b] < 0.12 and frac[b] < _share_known(b) - 0.04 and not low_known:
				pick = b
				break
	if pick >= 0 and out.size() < 2:
		out.append([tr("TY_FS_ADV_ORPHAN") % FocusView.bar_name(pick), false])
	# defects
	if defects >= 3.0 and out.size() < 2:
		for i in m.size():
			if (ProjectRules.sliders(k)[i] as Dictionary).get("removes_defects", false):
				out.append([tr("TY_FS_ADV_DEFECTS") % tr(String(ProjectRules.sliders(k)[i].get("name_key", ""))), false])
				break
	if q < 0.7 and out.size() < 2:
		out.append([tr("TY_FS_ADV_SHORT"), false])
	return out


## The share the agency believes a bar needs (0.25 when nothing is known).
func _share_known(b: int) -> float:
	return _known_ideal[b] if not _known_ideal.is_empty() else 0.25


## The lever of the phase that feeds bar b most (-1: none feeds it).
static func _lever_for(m: Array, b: int) -> int:
	var best := -1
	var w := 0.0
	for i in m.size():
		if float(m[i][b]) > w + 0.001:
			w = float(m[i][b])
			best = i
	return best


func _fill_advice(frac: Array[float], defects: float, q: float) -> void:
	var lines := advice(frac, defects, q)
	var rows := TycoonHUD._copies(%Advice.get_node("AdviceTemplate"), lines.size())
	for i in lines.size():
		(rows[i].get_node("Text") as Label).text = String(lines[i][0])
		(rows[i].get_node("Dot") as ColorRect).color = CwPalette.OPS if lines[i][1] else CwPalette.BUTTER
