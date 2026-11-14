extends SceneTree
## Headless checks for the leader Cometling (src/tycoon/crew/tycoon_leader.gd and the leader
## creator, scenes/tycoon/ui/screens/leader_creator.tscn): create a leader -> found the agency
## (staff, bonus, agency name and colour) -> save / load roundtrip -> the leader is in the crew,
## on the campus with the star, and in the creator's edit mode. Uses slot "test_leader".
## Run: godot --headless --path . --script res://tests/test_tycoon_leader.gd

const SLOT := "test_leader"

var _failures := 0


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# random leaders are complete and valid
	var all_valid := true
	for i in 20:
		var r := TycoonLeader.make_random(rng)
		all_valid = all_valid and r == TycoonLeader.sanitize(r) and String(r["profession"]) != ""
	_check(all_valid, "random leaders are complete and valid")
	var bad := TycoonLeader.sanitize({"name": "   ", "profession": "wizard", "hat": "tophat", "body": "nope"})
	_check(bad["name"] != "" and bad["profession"] in TycoonLeader.professions() and bad["hat"] == "role"
		and Color.html_is_valid(String(bad["body"])), "sanitize fixes bad choices")
	_check(TycoonLeader.professions().size() == 7, "a founding bonus for each of the 7 professions")
	var pdata := TycoonState.load_json(TycoonState.PROFESSIONS_PATH)
	for p: Dictionary in pdata.get("professions", []):
		var b := TycoonLeader.bonus(String(p["id"]))
		var sp := TycoonCrew.spec(String(b.get("spec", "")))
		_check(not sp.is_empty() and String(p["id"]) in sp.get("professions", []),
			"%s: bonus spec is one of its tier-1 specs" % p["id"])

	# found the agency
	var staff: Array[Dictionary] = [
		{"name": "A", "role": "engineer", "level": 1}, {"name": "B", "role": "scientist", "level": 2}]
	var s := TycoonState.new_campaign(4242, staff)
	var cash0 := s.cash
	var hype0 := s.hype
	var leader := {"name": "Pipoca Estelar", "profession": "pilot", "body": "#ffa3a3", "spot": "#3fe0c5",
		"hat": "crown", "strength": "courage", "quirk": "dreamer", "agency_name": "Cauda Brilhante",
		"agency_color": "#5bd68e", "seed": 1234}
	TycoonLeader.found(s, leader)
	var m := TycoonLeader.member(s)
	_check(not m.is_empty() and s.staff[0] == m and s.staff.size() == 3, "the leader joins the staff first")
	_check(String(m.get("id")) == TycoonLeader.ID and TycoonLeader.is_leader(m), "leader id and flag")
	_check(m["name"] == "Pipoca Estelar" and m["profession"] == "pilot" and m["hat"] == "crown"
		and m["body"] == "#ffa3a3", "name, profession and look on the staff entry")
	_check(float(m["courage"]) > float(m["skill"]) and float(m["courage"]) > float(m["curiosity"]), "strength trait is highest")
	_check("steady_hands" in m["specs"] and TycoonCrew.spec_effect(m, "crew_risk") < 0.0, "pilot leader arrives specialised")
	_check(TycoonCrew.is_working(m) and int(m["level"]) == 2, "the leader works from week 1 at level 2")
	_check(is_equal_approx(s.hype, hype0 + 10.0) and is_equal_approx(s.cash, cash0), "pilot founding bonus: +10 hype")
	_check(s.agency_name == "Cauda Brilhante", "agency name from the creator")
	_check(s.race_board()[0]["color"] == Color("#5bd68e"), "agency colour on the race board")
	_check(String(s.leader["emblem"]) in TycoonLeader.emblems() and TycoonLeader.agency_emblem(s) != null,
		"the agency has an emblem (the first one when the creator gave none)")
	for e in TycoonLeader.emblems():
		_check(TycoonLeader.emblem_icon(String(e)) != null, "emblem icon %s" % e)
	_check(TycoonCrew.fire(s, TycoonLeader.ID) == "TY_LEADER_ERR_FIRE" and TycoonLeader.member(s) != {}, "the leader cannot be fired")
	_check(String(s.news[0]["key"]) == "TY_LEADER_NEWS_FOUNDED", "founding news line")

	# later edits keep the profession and strength
	var edit := s.leader.duplicate()
	edit["name"] = "Pipoca"
	edit["hat"] = "propeller"
	edit["profession"] = "researcher"
	edit["strength"] = "skill"
	TycoonLeader.update(s, edit)
	_check(s.leader["name"] == "Pipoca" and m["name"] == "Pipoca" and m["hat"] == "propeller", "edit renames and re-dresses")
	_check(s.leader["profession"] == "pilot" and m["profession"] == "pilot" and s.leader["strength"] == "courage",
		"edit keeps profession and strength")

	# a few weeks, then save / load
	for i in 9:
		s.advance_week()
	_check(TycoonSave.save(s, SLOT) == OK, "save")
	var l := TycoonSave.load_state(SLOT)
	_check(l != null, "load")
	if l == null:
		_end()
		return
	_check(l.leader == s.leader, "state.leader survives save / load")
	_check(_canon(l.to_dict()) == _canon(s.to_dict()), "whole state equal after load")
	var lm := TycoonLeader.member(l)
	_check(not lm.is_empty() and lm["hat"] == "propeller" and "steady_hands" in lm["specs"], "leader in the loaded crew")
	_check(l.race_board()[0]["color"] == Color("#5bd68e"), "agency colour after load")
	TycoonSave.delete(SLOT)
	_check(TycoonState.from_dict(TycoonState.new_campaign(1).to_dict()).leader.is_empty(), "no leader stays no leader")

	# the tycoon scene with a leader from the creator
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.leader = leader
	get_root().add_child(main)
	await process_frame
	await process_frame
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	var lead := TycoonLeader.member(main.state)
	_check(not lead.is_empty() and main.state.agency_name == "Cauda Brilhante", "new campaign founded with the leader")
	_check((main.hud.get_node("%Mark") as TextureRect).texture == TycoonLeader.agency_emblem(main.state),
		"the HUD shows the agency emblem next to the name")
	var walker: Node3D = null
	for w in main.campus.cometlings():
		if String(w.get("member_id")) == TycoonLeader.ID:
			walker = w
	_check(walker != null, "the leader walks on the campus")
	if walker:
		var mark := walker.get_node_or_null("LeaderMark") as Node3D
		_check(mark != null and mark.visible, "the leader has the star over the head")
		var hat := walker.get_node("Creature/Rig/Hips/Neck").get_node_or_null(LeaderHat.NODE_NAME) as LeaderHat
		_check(hat != null and hat.visible and hat.hat == "crown", "the leader wears the crown")
		var c := walker.get_node("Creature") as Cometling
		_check(c.body_color.is_equal_approx(Color("#ffa3a3")), "the leader has their own body colour")
		var others := 0
		for w in main.campus.cometlings():
			if w != walker and (w.get_node("LeaderMark") as Node3D).visible:
				others += 1
		_check(others == 0, "only the leader has the star")
		var bubble := c.get_node("Emote") as Sprite3D
		_check(bubble.offset != Vector2.ZERO, "the leader's speech bubble pops beside the star")
		# the propeller cap: tucks the antenna away and spins with the hat scene's AnimationPlayer
		LeaderHat.wear(c, "propeller")
		var anim := hat.get_node("Anim") as AnimationPlayer
		_check(anim.is_playing() and anim.current_animation == "spin", "the propeller spins (AnimationPlayer)")
		_check(not (c.get_node("Rig/Hips/Neck/Antenna") as Node3D).visible, "the propeller cap covers the antenna")
		LeaderHat.wear(c, "crown")
		_check(not anim.is_playing() and (c.get_node("Rig/Hips/Neck/Antenna") as Node3D).visible,
			"the crown stops the propeller and shows the antenna again")
	# crew screen and the creator in edit mode
	main.hud.open_screen("crew", {"staff_id": TycoonLeader.ID})
	await process_frame
	var crew := main.hud.get_node("%Screens").get_child(0) as CrewScreen
	_check(crew != null and crew.get_node("%LeaderRow").visible and not crew.get_node("%FireButton").visible,
		"crew card shows the leader badge, no fire button")
	_check(main.hud.open_screen("leader_creator"), "the creator opens as a screen")
	await process_frame
	var cr := main.hud.get_node("%Screens").get_child(0) as LeaderCreator
	_check(cr != null and cr.mode == "edit" and cr.leader["name"] == "Pipoca Estelar", "creator edits the current leader")
	if cr:
		cr.pick("hat", "beanie")
		cr.set_leader_name("Pipoca Nova")
		cr.confirm()
		await process_frame
		_check(main.state.leader["hat"] == "beanie" and TycoonLeader.member(main.state)["name"] == "Pipoca Nova",
			"saving the creator updates the leader")
		_check(main.hud.current_screen() == "crew", "back to the crew screen after saving")
	main.queue_free()
	await process_frame

	# the creator on its own (new campaign) builds a valid leader
	var solo := (load(LeaderCreator.SCENE) as PackedScene).instantiate() as LeaderCreator
	solo.preload_campus = false
	get_root().add_child(solo)
	await process_frame
	_check(solo.mode == "new" and solo.leader == TycoonLeader.sanitize(solo.leader), "new-campaign creator starts valid")
	solo.pick("profession", "researcher")
	solo.randomize_all()
	_check(solo.leader == TycoonLeader.sanitize(solo.leader), "randomize keeps it valid")
	_check(solo.get_node("%BodySwatches").get_child_count() > TycoonLeader.body_colors().size(), "body swatches copied from the template")
	# each profession card shows its favoured bar as one full-word chip (Eng, Sci, Ops or Rel)
	var chips_ok := true
	for card in solo.get_node("%ProfTemplate").get_parent().get_children():
		if card == solo.get_node("%ProfTemplate"):
			continue
		var shown: Array[String] = []
		for chip in card.get_node("Box/Favours").get_children():
			if chip is PanelContainer and chip.visible:
				shown.append(String(chip.name))
		chips_ok = chips_ok and shown.size() == 1
	_check(chips_ok, "profession cards show exactly one bar chip")
	# one tab on show at a time, the selected choices wear their check badge
	var shown_pages := 0
	for pg in solo.get_node("%Pages").get_children():
		shown_pages += 1 if (pg as Control).visible else 0
	_check(shown_pages == 1 and solo.get_node("%Pages").get_child(0).visible, "the creator opens on the first tab only")
	solo.show_page(2)
	_check(solo.page == 2 and solo.get_node("%Pages").get_child(2).visible and not solo.get_node("%Pages").get_child(0).visible
		and (solo.get_node("%Tabs").get_child(2) as Button).button_pressed, "a tab shows its page and lights its key")
	solo.show_page(9)
	_check(solo.page == 3, "the steps stop at the last tab")
	var checks := 0
	for b in solo.get_node("%HatTemplate").get_parent().get_children():
		if b.has_meta("from_template") and (b.get_node("Check") as CanvasItem).visible:
			checks += 1
			_check(String(b.get_meta("value")) == String(solo.leader["hat"]), "the checked hat is the leader's")
	_check(checks == 1, "exactly one hat tile is checked")
	var quirk_icons := true
	for b in solo.get_node("%QuirkTemplate").get_parent().get_children():
		if b.has_meta("from_template"):
			quirk_icons = quirk_icons and (b.get_node("Box/Emote") as TextureRect).texture != null
	_check(quirk_icons, "personality chips show their emote")
	_check(String(solo.get_node("%SummaryName").text) == String(solo.leader["name"])
		and String(solo.get_node("%SummaryBonus").text) != "", "the summary card names the leader and the founding bonus")
	solo.queue_free()
	_end()


func _end() -> void:
	print("LEADER TESTS: %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	quit(1 if _failures else 0)


## State dict -> canonical text (as in tests/test_tycoon_save.gd).
static func _canon(d: Dictionary) -> String:
	var j: Variant = JSON.parse_string(JSON.stringify(TycoonSave.encode(d), "", true, true))
	return JSON.stringify(j, "", true, true)


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		_failures += 1
		print("  FAIL ", msg)
