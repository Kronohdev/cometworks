extends SceneTree
## Headless checks for the Concept Maturity Level checklist of the Design Review (CmlChecklist,
## data/tycoon/cml.json): the data and its translations, the level climbing only through fully
## checked levels, items following the real project state (a rocket that does not reach, no cash,
## fixing the high risks, a deadline the fixes break), the modest launch bonus (reputation always,
## hype on a success, written in the history entry) and the Design Review screen drawing one row
## per level with hints only on unchecked items.
## Run: godot --headless --path . --script res://tests/test_cml_checklist.gd

const SOUNDING := {"core": "core_kestrel", "upper": "upper_none", "tank": "tank_m", "boosters": "boost_none",
	"fairing": "fairing_none", "avionics": "avionics_basic", "recovery": "recovery_none"}
const LEO := {"core": "core_falcao", "upper": "upper_kestrel_v", "tank": "tank_m", "boosters": "boost_srb2",
	"fairing": "fairing_s", "avionics": "avionics_basic", "recovery": "recovery_none"}

var _failures := 0


func _initialize() -> void:
	TranslationServer.set_locale("pt")
	_test_data()
	_test_levels()
	_test_items_follow_state()
	_test_bonus()
	_test_launch_bonus()
	await _test_screen()
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


static func _team() -> Array[Dictionary]:
	return [
		{"id": "a", "name": "Ada", "profession": "systems_engineer", "skill": 0.6, "morale": 80.0, "level": 1},
		{"id": "b", "name": "Bel", "profession": "scientist", "skill": 0.5, "morale": 70.0, "level": 2},
		{"id": "c", "name": "Cid", "profession": "test_technician", "skill": 0.5, "morale": 70.0, "level": 1},
		{"id": "d", "name": "Duo", "profession": "flight_controller", "skill": 0.4, "morale": 60.0, "level": 1}]


static func _state(p_seed := 21) -> TycoonState:
	var s := TycoonState.new_campaign(p_seed, _team())
	s.cash = 5.0e6
	return s


## A demo satellite to low orbit, developed to its Design Review.
static func _review_project(s: TycoonState) -> MissionProject:
	s.review_gate = true
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	var p := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b", "c", "d"], "", {"parts": LEO})
	var plan := [[50, 20, 30], [45, 20, 35], [20, 10, 70]]
	ProjectDesk.set_sliders(s, p.id, plan[0])
	for i in 40:
		if ProjectDesk.find(s, p.id) == null or p.review_state != "":
			break
		s.advance_week()
		if p.awaiting_sliders:
			ProjectDesk.set_sliders(s, p.id, plan[p.phase])
	return p


static func _item(c: Dictionary, id: String) -> Dictionary:
	for it: Dictionary in c["items"]:
		if String(it["id"]) == id:
			return it
	return {}


static func _high_fixes(s: TycoonState, p: MissionProject) -> Array[String]:
	var out: Array[String] = []
	for rk in DesignReview.risks(s, p, []):
		if String(rk["fix_key"]) != "" and String(rk["severity"]) == "high":
			out.append(String(rk["id"]))
	return out


# ------------------------------------------------------------ data
func _test_data() -> void:
	print("data and translations")
	var lv := CmlChecklist.levels()
	_check(lv.size() == 6 and CmlChecklist.max_level() == 6, "six levels, CML 1..6")
	var seen := {}
	for i in lv.size():
		var l: Dictionary = lv[i]
		_check(int(l["level"]) == i + 1, "level %d in order" % (i + 1))
		_check(tr(String(l["name_key"])) != String(l["name_key"]), "level %d has a name (%s)" % [i + 1, tr(String(l["name_key"]))])
		_check(not (l["items"] as Array).is_empty(), "level %d has items" % (i + 1))
		for id in l["items"]:
			var d := CmlChecklist.item_def(String(id))
			_check(not d.is_empty() and not seen.has(id), "item %s defined once" % id)
			seen[id] = true
			for k in ["label_key", "hint_key"]:
				var key := String(d.get(k, ""))
				_check(key != "" and tr(key) != key, "item %s %s translated (%s)" % [id, k, tr(key)])
	for id in ["objective", "instruments", "mass_margin", "comms", "budget", "schedule", "risks"]:
		_check(seen.has(id), "the checklist asks for %s" % id)


# ------------------------------------------------------------ levels
func _test_levels() -> void:
	print("the level climbs through fully checked levels")
	var s := _state()
	var p := _review_project(s)
	_check(p.review_state == "waiting", "the project waits in its review")
	var c := CmlChecklist.evaluate(s, p, [])
	var level := int(c["level"])
	_check((c["items"] as Array).size() == 10 and (c["levels"] as Array).size() == 6, "10 items over 6 levels")
	_check(level >= 0 and level <= 6, "level in range (%d)" % level)
	var ok_below := true
	for it: Dictionary in c["items"]:
		if int(it["level"]) <= level and not it["ok"]:
			ok_below = false
	_check(ok_below, "every item up to CML %d is checked" % level)
	if level < 6:
		var lv: Dictionary = c["levels"][level]
		_check(not lv["ok"], "CML %d has an unchecked item: the level stops there" % (level + 1))
	_check(_item(c, "objective")["ok"], "a demo satellite to low orbit is a defined objective")
	_check(_item(c, "reaches")["ok"], "the LEO rocket reaches")


# ------------------------------------------------------------ items follow the project
func _test_items_follow_state() -> void:
	print("items follow the project's state")
	var s := _state()
	var p := _review_project(s)
	# fixing every high fixable risk checks "risks known"
	var high := _high_fixes(s, p)
	var c0 := CmlChecklist.evaluate(s, p, [])
	var c1 := CmlChecklist.evaluate(s, p, high)
	_check(high.is_empty() == bool(_item(c0, "risks")["ok"]), "with high risks unfixed the risks item is open (%s)" % [high])
	_check(_item(c1, "risks")["ok"], "fixing them checks it")
	# no cash: the budget does not fit
	var cash := s.cash
	s.cash = 0.0
	var cb := CmlChecklist.evaluate(s, p, [])
	_check(not _item(cb, "budget")["ok"] and int(cb["level"]) < 5, "no cash for the launch: budget open, below CML 5")
	s.cash = cash
	_check(_item(CmlChecklist.evaluate(s, p, []), "budget")["ok"], "cash back: the budget fits")
	# a client's budget the fixes would break
	p.briefing_terms = {"budget": p.cost_spent + 1.0}
	if not high.is_empty() and float(DesignReview.fix_plan(s, p, high)["cost"]) > 1.0:
		_check(not _item(CmlChecklist.evaluate(s, p, high), "budget")["ok"], "costly fixes break the client's budget")
	p.briefing_terms = {}
	# a deadline: no deadline holds; one this week breaks with any fix weeks
	_check(_item(CmlChecklist.evaluate(s, p, high), "schedule")["ok"], "no deadline: the schedule fits")
	_check(CmlChecklist.deadline_week(s, p) == -1, "a free project has no deadline")
	# a rocket that does not reach: feasibility fails, the level falls to CML 1
	var parts: Dictionary = p.rocket["parts"]
	p.rocket["parts"] = SOUNDING
	var cr := CmlChecklist.evaluate(s, p, [])
	_check(not _item(cr, "reaches")["ok"] and not _item(cr, "mass_margin")["ok"], "a sounding rocket to orbit: not reaching, no margin")
	_check(int(cr["level"]) <= 1, "the concept stays at CML %d" % int(cr["level"]))
	_check(not _item(cr, "risks")["ok"], "a blocked design is not a known risk")
	p.rocket["parts"] = parts
	# the payload: dropping the antenna opens comms
	var pl := p.payload.duplicate()
	var ant := PayloadRules.antenna(p.payload_or_default(s))
	var needs: Array = PayloadRules.type_rules(p.type_id).get("needs_antenna", [])
	if ant != "" and not needs.is_empty():
		p.payload.erase(ant)
		_check(not _item(CmlChecklist.evaluate(s, p, []), "comms")["ok"], "no antenna: comms open")
	p.payload = pl


# ------------------------------------------------------------ bonus
func _test_bonus() -> void:
	print("the launch bonus is modest and grows with the level")
	var prev := -1.0
	for lv in 7:
		var b := CmlChecklist.bonus(lv)
		_check(float(b["hype"]) >= prev, "CML %d bonus does not shrink" % lv)
		prev = float(b["hype"])
	_check(float(CmlChecklist.bonus(3)["hype"]) == 0.0 and float(CmlChecklist.bonus(0)["reputation"]) == 0.0, "no bonus below CML 4")
	var top := CmlChecklist.bonus(6)
	_check(float(top["hype"]) > 0.0 and float(top["hype"]) <= 6.0 and float(top["reputation"]) <= 1.0,
		"CML 6: a modest bonus (+%s hype, +%s rep)" % [top["hype"], top["reputation"]])


## Two identical campaigns launch the same project; one with the bonus zeroed. The difference in
## reputation is the bonus; the hype too on a success. The entry keeps the level.
func _test_launch_bonus() -> void:
	print("the launch pays the bonus")
	var cfg: Dictionary = CmlChecklist.data()["bonus"]
	var saved := cfg.duplicate()
	var res: Array[Dictionary] = []
	var levels: Array[int] = []
	for run in 2:
		cfg["from_level"] = 1
		cfg["hype_per_level"] = 1.5 if run == 0 else 0.0
		cfg["reputation_per_level"] = 0.25 if run == 0 else 0.0
		var s := _state(33)
		s.review_gate = true
		var p := _review_project(s)
		levels.append(int(CmlChecklist.evaluate(s, p, [], false)["level"]))
		ProjectDesk.dev_force_outcome = "success"
		ProjectDesk.confirm_review(s, p.id, [])
		res.append(ProjectDesk.history_entry(s, p.id))
	for k in saved:
		cfg[k] = saved[k]
	var a: Dictionary = res[0]
	var b: Dictionary = res[1]
	_check(not a.is_empty() and not b.is_empty(), "both projects launched")
	if a.is_empty() or b.is_empty():
		return
	_check(int(a.get("cml", -1)) == levels[0], "the history entry keeps the level (CML %d)" % int(a.get("cml", -1)))
	var lv := levels[0]
	var dr := float(a["rewards"]["reputation"]) - float(b["rewards"]["reputation"])
	var dh := float(a["rewards"]["hype"]) - float(b["rewards"]["hype"])
	_check(is_equal_approx(dr, lv * 0.25), "reputation +%.2f for CML %d" % [dr, lv])
	_check(is_equal_approx(dh, lv * 1.5 if a["success"] else 0.0), "hype +%.2f on a success" % dh)


# ------------------------------------------------------------ the screen
func _test_screen() -> void:
	print("the Design Review screen draws the checklist")
	var s := _state()
	var p := _review_project(s)
	var scr := (load("res://scenes/tycoon/ui/screens/design_review.tscn") as PackedScene).instantiate() as CwScreen
	get_root().add_child(scr)
	await process_frame
	scr.bind(s, null, null)
	scr.call("open_with", {"project_id": p.id})
	await process_frame
	var c := CmlChecklist.evaluate(s, p, [])
	var lvl := int(c["level"])
	var level_l := scr.get_node("%CmlLevel") as Label
	_check(level_l.text.begins_with("CML %d" % lvl), "the heading names the level (%s)" % level_l.text)
	var rows: Array[Node] = []
	for r in (scr.get_node("%CmlLevelTemplate") as Node).get_parent().get_children():
		if r.has_meta("from_template") and (r as Control).visible:
			rows.append(r)
	_check(rows.size() == 6, "one row per level (%d)" % rows.size())
	var cells := 0
	var hints_ok := true
	for r in rows:
		for cell in r.get_node("Items").get_children():
			if not cell.has_meta("from_template") or not (cell as Control).visible:
				continue
			cells += 1
			var name_t := (cell.get_node("Texts/Name") as Label).text
			var it: Dictionary = {}
			for x: Dictionary in c["items"]:
				if tr(String(x["label_key"])) == name_t:
					it = x
			if it.is_empty() or (cell.get_node("Texts/Hint") as Label).visible == bool(it["ok"]):
				hints_ok = false
	_check(cells == 10, "every item drawn (%d)" % cells)
	_check(hints_ok, "hints show only on unchecked items")
	var bonus_t := (scr.get_node("%CmlBonus") as Label).text
	_check(bonus_t != "" and not bonus_t.contains("TY_"), "the bonus line reads (%s)" % bonus_t)
	# fixing the high risks updates the checklist live
	for id in _high_fixes(s, p):
		scr.call("_toggle_fix", id, true)
	await process_frame
	var c2 := CmlChecklist.evaluate(s, p, scr.get("fixes"))
	_check(level_l.text.begins_with("CML %d" % int(c2["level"])), "the fixes move the heading (%s)" % level_l.text)
	scr.queue_free()
	await process_frame


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
