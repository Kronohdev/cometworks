extends CwScreen
## Discovery journal ("Caderno de descobertas", scenes/tycoon/ui/screens/journal.tscn, opened
## from the rail and from the review): what the agency has learned by flying (Discovery).
## Left: the mission types (flights, a star for a great combo). Middle: the chosen type's ideal
## balance and the lever split that hits it (once revealed: after a few flights or a tech), the
## targets tried with their compat tier, best grade and stars, the best team. Right: the
## instruments rated on that type at the chosen target, the target's environment, and the
## latest discoveries. Everything visual is in the scene; rows are copies of hidden templates.

const TIER_COLORS := {"great": CwPalette.AURORA_TEAL, "good": CwPalette.COMET_ICE, "poor": CwPalette.WARNING,
	"impossible": CwPalette.DANGER}
const RATING_COLORS := {"great": CwPalette.AURORA_TEAL, "good": CwPalette.COMET_ICE, "useless": CwPalette.WARNING,
	"bad": CwPalette.DANGER}

var type_id := ""
var target_id := ""


func _bound() -> void:
	var types := _types()
	for t: Dictionary in types:
		if Discovery.attempts(state, String(t["id"])) > 0:
			type_id = String(t["id"])
			break
	if type_id == "" and not types.is_empty():
		type_id = String(types[0]["id"])


## args: {"type", "target"} opens on a type (and target): the review's "open the journal".
func open_with(args: Dictionary) -> void:
	type_id = String(args.get("type", type_id))
	target_id = String(args.get("target", ""))
	refresh()


## The types the journal has a page for: those the agency can fly or has flown.
func _types() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in state.mdata.get("types", []):
		var id := String(t["id"])
		if state.mission_type_available(id) or Discovery.attempts(state, id) > 0:
			out.append(t)
	return out


func _targets() -> Array[String]:
	var out: Array[String] = []
	var cmp: Dictionary = state.mission_type(type_id).get("compat", {})
	for t: Dictionary in state.mdata.get("targets", []):
		var id := String(t["id"])
		if cmp.has(id) and (state.mission_target_available(id) or not Discovery.combo(state, type_id, id).is_empty()):
			out.append(id)
	return out


func _pick_type(id: String) -> void:
	type_id = id
	target_id = ""
	refresh()


func _pick_target(id: String) -> void:
	target_id = id
	refresh()


func refresh() -> void:
	if state == null:
		return
	%Count.text = "%d" % Discovery.count(state)
	_fill_types()
	var targets := _targets()
	if not target_id in targets:
		target_id = ""
		for t in targets:
			if not Discovery.combo(state, type_id, t).is_empty():
				target_id = t
				break
		if target_id == "" and not targets.is_empty():
			target_id = targets[0]
	_fill_type()
	_fill_targets(targets)
	_fill_right()
	_fill_notes()


func _fill_types() -> void:
	var types := _types()
	var rows := copies(%TypeTemplate, types.size())
	for i in types.size():
		var t: Dictionary = types[i]
		var id := String(t["id"])
		var b := rows[i] as Button
		b.set_meta("id", id)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: _pick_type(String(b.get_meta("id", ""))))
		b.text = tr(String(t.get("name_key", id)))
		b.set_pressed_no_signal(id == type_id)
		var great := false
		for tg: String in t.get("compat", {}):
			great = great or bool(Discovery.combo(state, id, tg).get("great", false))
		var n := Discovery.attempts(state, id)
		(b.get_node("Tag") as Label).text = (tr("TY_JN_FLIGHTS") % n if n > 0 else "—") + (" ★" if great else "")


func _fill_type() -> void:
	var mt := state.mission_type(type_id)
	%TypeName.text = tr(String(mt.get("name_key", type_id)))
	var n := Discovery.attempts(state, type_id)
	var best := 0.0
	for tg: String in mt.get("compat", {}):
		best = maxf(best, float(Discovery.combo(state, type_id, tg).get("best", 0.0)))
	%TypeFacts.text = tr("TY_JN_FACTS") % [n, "%.1f" % best] if n > 0 else tr("TY_JN_NEVER")
	var known := Discovery.ratio_known(state, type_id)
	var ratio: Array = mt.get("ratio", [0.25, 0.25, 0.25, 0.25])
	var rows: Array[Node] = [%RatioEng, %RatioSci, %RatioOps, %RatioRel]
	for b in 4:
		var bar := rows[b].get_node("Bar") as CwSegmentBar
		bar.color = CwPalette.BARS[ProjectRules.BARS[b]]
		bar.value = float(ratio[b]) / 0.5 if known else 0.0
		(rows[b].get_node("Value") as Label).text = "%d%%" % roundi(float(ratio[b]) * 100.0) if known else "?"
	%RatioNote.text = tr("TY_JN_RATIO_KNOWN") if known else tr("TY_JN_RATIO_HIDDEN") % [n, int(BriefingDesk.disc().get("reveal_ratio_after", 2))]
	var levers: Array[Node] = [%Lever0, %Lever1, %Lever2]
	var ranges := Discovery.lever_ranges(ratio) if known else []
	for k in 3:
		var l := levers[k] as Label
		l.visible = known
		if not known:
			continue
		var parts: Array[String] = []
		var sl := ProjectRules.sliders(k)
		for i in 3:
			var r: Array = ranges[k][i]
			parts.append("%s %d–%d%%" % [tr(String((sl[i] as Dictionary).get("name_key", ""))), int(r[0]), int(r[1])])
		l.text = "%s: %s" % [tr(String(ProjectRules.phase(k).get("name_key", ""))), " · ".join(parts)]
	%LeversCaption.visible = known
	var tn := Discovery.team_note(state, type_id)
	%TeamNote.visible = not tn.is_empty()
	if not tn.is_empty():
		var parts2: Array[String] = []
		var profs: Dictionary = tn.get("profs", {})
		for p: String in profs:
			parts2.append("%d %s" % [int(profs[p]), tr(String(state.profession(p).get("name_key", p)))])
		%TeamNote.text = tr("TY_TM_BEST") % ["%.1f" % float(tn.get("grade", 0.0)), ", ".join(parts2)]


func _fill_targets(targets: Array[String]) -> void:
	var rows := copies(%TargetTemplate, targets.size())
	for i in targets.size():
		var id := targets[i]
		var b := rows[i] as Button
		b.set_meta("id", id)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: _pick_target(String(b.get_meta("id", ""))))
		b.text = tr(String(state.mission_target(id).get("name_key", id)))
		b.set_pressed_no_signal(id == target_id)
		var c := Discovery.combo(state, type_id, id)
		var tag := b.get_node("Tag") as Label
		if c.is_empty():
			tag.text = "?"
			tag.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
		else:
			var tier := String(c.get("tier", "good"))
			var best := float(c.get("best", 0.0))
			tag.text = "%s%s%s" % [tr("TY_PJ_COMPAT_" + tier.to_upper()), (" · %.1f" % best) if int(c.get("n", 0)) > 0 else "",
				" ★" if c.get("great", false) else ""]
			tag.add_theme_color_override("font_color", TIER_COLORS.get(tier, CwPalette.TEXT))
	%NoTargets.visible = targets.is_empty()


func _fill_right() -> void:
	var tname := tr(String(state.mission_target(target_id).get("name_key", target_id))) if target_id != "" else "—"
	%InstrCaption.text = tr("TY_JN_INSTR") % tname
	var rated: Array[Array] = []
	for m: Dictionary in PayloadRules.modules_of("instrument"):
		var r := Discovery.instr_rating(state, type_id, target_id, String(m["id"])) if target_id != "" else ""
		if r != "":
			rated.append([String(m["id"]), r])
	var order := {"great": 0, "good": 1, "useless": 2, "bad": 3}
	rated.sort_custom(func(a: Array, b: Array) -> bool: return int(order[a[1]]) < int(order[b[1]]))
	var rows := copies(%InstrTemplate, rated.size())
	for i in rated.size():
		(rows[i].get_node("Name") as Label).text = tr(PayloadRules.name_key(String(rated[i][0])))
		var rl := rows[i].get_node("Rating") as Label
		rl.text = tr("TY_JN_RATE_" + String(rated[i][1]).to_upper())
		rl.add_theme_color_override("font_color", RATING_COLORS.get(String(rated[i][1]), CwPalette.TEXT))
	%NoInstr.visible = rated.is_empty()
	%EnvCaption.text = tr("TY_JN_ENV") % tname
	%EnvLine.text = Discovery.env_text(state, target_id) if target_id != "" else "—"


func _fill_notes() -> void:
	var notes := Discovery.notes(state)
	var n := mini(notes.size(), 12)
	var rows := copies(%NoteTemplate, n)
	for i in n:
		(rows[i] as Label).text = "• " + TycoonHUD.news_text(notes[i])
	%NoNotes.visible = notes.is_empty()
