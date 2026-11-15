extends SceneTree
## The hangar and the flight inside the main mode (TycoonModes, HangarRocket):
##   rules     a hangar vessel becomes a tycoon design (delta-v with the mission payload,
##             lift, cost, weeks, reliability per real stage), RocketDesigner.check measures it
##             per mission, the vessel survives as data (tree <-> scene), the flight's report
##             becomes an outcome (flight_verdict), the pad gate and a piloted launch in
##             ProjectDesk, save / load of a project with a hangar rocket (and a missing
##             definition degrading to an abstract rocket)
##   campus    the rocket designer's "Montar no hangar" opens the embedded hangar for the
##             mission (FlightSession.mission filled, campus asleep, clock held), the hangar's
##             test flight and its way back, "Usar na missão" puts the vessel on the designer's
##             bench, the project starts with it, the Design Review sends it to the pad, the
##             launch choice opens, a piloted flight (Esc pauses, leaving before liftoff cancels,
##             its report decides) ends in the review with the clock given back; the workshop's
##             hangar opens from the lot panel and Esc brings the campus back; the dev menu's
##             mission_hangar / mission_flight
## Run: godot --headless --path . --script res://tests/test_tycoon_integrated.gd

const SLOT := "integrated_test"

var _failures := 0
var main: TycoonMain


func _initialize() -> void:
	_test_rules()
	_test_verdicts()
	_test_desk()
	_test_save_load()
	await _test_campus()
	await _test_workshop()
	await _test_dev_menu()
	if TycoonSave.exists(SLOT):
		DirAccess.remove_absolute(TycoonSave.path(SLOT))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


static func _team() -> Array[Dictionary]:
	return [
		{"id": "a", "name": "Ada", "profession": "systems_engineer", "skill": 0.6, "morale": 80.0, "level": 1},
		{"id": "b", "name": "Bel", "profession": "scientist", "skill": 0.5, "morale": 70.0, "level": 2},
		{"id": "c", "name": "Cid", "profession": "test_technician", "skill": 0.5, "morale": 70.0, "level": 1},
		{"id": "d", "name": "Duo", "profession": "flight_controller", "skill": 0.4, "morale": 60.0, "level": 1}]


static func _state() -> TycoonState:
	var s := TycoonState.new_campaign(33, _team())
	s.cash = 5.0e6
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	return s


static func _example(id: String) -> PackedScene:
	return load("res://scenes/examples/%s.tscn" % id) as PackedScene


# ------------------------------------------------------------ rules
func _test_rules() -> void:
	print("hangar vessel -> tycoon design")
	var s := _state()
	var m := HangarRocket.mission_for(s, "demo_sat", "leo", 400000.0, "DEM-01")
	for k in ["title", "target", "dv_needed", "payload_kg", "budget_musd", "crewed"]:
		_check(m.has(k), "the mission has %s" % k)
	_check(is_equal_approx(float(m["dv_needed"]), 9400.0), "low orbit needs 9400 m/s (%s)" % m["dv_needed"])
	_check(is_equal_approx(float(m["payload_kg"]), 300.0), "a demo satellite weighs 300 kg (%s)" % m["payload_kg"])
	_check(is_equal_approx(float(m["budget_musd"]), 40.0), "400k cr of budget are US$ 40 M (%s)" % m["budget_musd"])
	_check(m["crewed"] == false and String(m["title"]).begins_with("DEM-01"), "title and crew flag")
	var d := HangarRocket.from_scene(_example("andorinha"), m, "Andorinha")
	_check(not d.is_empty() and String(d["id"]) != "", "a definition comes out of the Andorinha")
	_check(int(d["parts_n"]) == 16 and int(d["stages_n"]) == 2, "16 parts, 2 stages (%d, %d)" % [d["parts_n"], d["stages_n"]])
	var dv_ms := HangarRocket.ascent_dv(d["stages"], float(d["fairing_kg"]), 300.0)
	_check(absf(float(d["dv"]) * 1000.0 - dv_ms) < 1.0, "delta-v is the hangar's ascent delta-v with the payload (%.0f)" % dv_ms)
	_check(float(d["dv0"]) > float(d["dv"]), "an empty rocket goes farther (%.2f > %.2f km/s)" % [d["dv0"], d["dv"]])
	var lift := float(d["lift"])
	_check(lift > 0.2 and HangarRocket.ascent_dv(d["stages"], float(d["fairing_kg"]), lift * 1000.0) >= 9399.0 \
		and HangarRocket.ascent_dv(d["stages"], float(d["fairing_kg"]), lift * 1000.0 + 50.0) < 9400.0,
		"lift is the heaviest payload that still reaches orbit (%.3f t)" % lift)
	_check(is_equal_approx(float(d["cost"]), roundf(11.54 * 10000.0 / 100.0) * 100.0), "cost: US$ 11.54 M x 10k cr (%s)" % d["cost"])
	_check(int(d["weeks"]) == ceili(16 / 5.0) + 2, "weeks: parts / 5 + stages (%d)" % d["weeks"])
	var parts := HangarRocket.adopt(s, d)
	_check(HangarRocket.is_hangar(parts) and parts["upper"] == "hgu_" + String(d["id"]), "the design has hangar slots")
	_check(RocketDesigner.same_parts(RocketDesigner.normalize(parts), parts), "normalize keeps the hangar components")
	_check(RocketDesigner.buildable(s, parts), "a hangar design is buildable")
	var st := RocketDesigner.stats(parts)
	var rel: Dictionary = d["rel"]
	var prod := float(rel["core"]) * float(rel["upper"]) * float(rel["boosters"]) * float(rel["fairing"]) * float(rel["avionics"])
	_check(absf(float(st["rel"]) - prod) < 1e-9 and float(st["rel"]) < 1.0 and float(st["rel"]) > 0.8,
		"reliability is the product of its slots (%.3f)" % st["rel"])
	_check(is_equal_approx(float(st["cost"]), float(d["cost"])) and int(st["weeks"]) == int(d["weeks"]), "stats carry cost and weeks")
	var chk := RocketDesigner.check(s, parts, "demo_sat", "leo")
	_check(not chk["reaches"] and String(chk["dv"]["state"]) == "red",
		"the little Andorinha falls short of orbit with 300 kg (%.2f km/s)" % chk["dv"]["have"])
	var sub := RocketDesigner.check(s, parts, "sounding", "suborbital")
	_check(sub["reaches"] and float(sub["dv"]["have"]) > float(chk["dv"]["have"]),
		"measured per mission: the sounding hop, lighter, gets there")
	var big := HangarRocket.adopt(s, HangarRocket.from_scene(_example("garca"), m, "Garça"))
	_check(RocketDesigner.check(s, big, "demo_sat", "leo")["reaches"], "the Garça takes the demo satellite to orbit")
	var moon := RocketDesigner.check(s, parts, "orbiter", "lunar_orbit")
	_check(not moon["reaches"], "the Andorinha cannot take an orbiter to the Moon")
	var risks := DesignReview.risks(s, _project_with(s, parts), [])
	var ids := risks.map(func(r: Dictionary) -> String: return String(r["id"]))
	_check("stage1" in ids and "stage2" in ids and "avionics" in ids, "the review lists the real stages (%s)" % [ids])
	# the vessel as data
	var ps := HangarRocket.scene_of(d["tree"])
	var back := HangarRocket.tree(ps)
	_check(JSON.stringify(back) == JSON.stringify(d["tree"]), "tree -> scene -> tree is the same vessel")
	var v := Vessel.new()
	v.load_scene(ps)
	_check(v.all_parts().size() == 16, "the rebuilt vessel has its 16 parts")
	v.free()


func _project_with(s: TycoonState, parts: Dictionary) -> MissionProject:
	var p := MissionProject.new()
	p.id = "T"
	p.type_id = "demo_sat"
	p.target_id = "leo"
	p.rocket = {"family": "", "parts": parts}
	return p


func _test_verdicts() -> void:
	print("flight verdicts")
	var s := _state()
	var sub := HangarRocket.mission_for(s, "sounding", "suborbital")
	var leo := HangarRocket.mission_for(s, "demo_sat", "leo")
	var moon := HangarRocket.mission_for(s, "orbiter", "lunar_orbit")
	var v := HangarRocket.flight_verdict({"result": "crash", "max_alt": 130000.0}, sub)
	_check(v["outcome"] == "success" and v["piloted"], "suborbital: space reached, the fall after it is the plan")
	v = HangarRocket.flight_verdict({"result": "crash", "max_alt": 40000.0}, sub)
	_check(v["outcome"] == "fail" and v["cause_key"] == "TY_HG_CAUSE_LOST", "suborbital: lost before space")
	v = HangarRocket.flight_verdict({"result": "orbit", "orbit": true, "max_alt": 200000.0}, leo)
	_check(v["outcome"] == "success" and v["reached"] == "target", "low orbit: an orbit is the goal")
	v = HangarRocket.flight_verdict({"result": "abort", "orbit": false, "max_alt": 150000.0}, leo)
	_check(v["outcome"] == "fail" and v["cause_key"] == "TY_HG_CAUSE_SHORT", "low orbit: space without orbit falls short")
	v = HangarRocket.flight_verdict({"result": "orbit", "orbit": true, "max_alt": 200000.0, "dv_left": 1000.0}, moon)
	_check(v["outcome"] == "partial", "the Moon: an orbit without the delta-v for the trip is partial")
	v = HangarRocket.flight_verdict({"result": "orbit", "orbit": true, "max_alt": 200000.0, "dv_left": 4500.0}, moon)
	_check(v["outcome"] == "success", "the Moon: an orbit with the delta-v left is a success")
	v = HangarRocket.flight_verdict({"result": "abort", "orbit": false, "reached_moon": true, "max_alt": 3.0e8}, moon)
	_check(v["outcome"] == "success", "the Moon: reaching its sphere is a success")


func _test_desk() -> void:
	print("pad gate and piloted launch")
	var s := _state()
	var m := HangarRocket.mission_for(s, "demo_sat", "leo")
	var parts := HangarRocket.adopt(s, HangarRocket.from_scene(_example("garca"), m, "Garça"))
	var p := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b", "c"], "", {"parts": parts, "name": "Garça"})
	_check(p != null and HangarRocket.is_hangar(p.rocket["parts"]), "a project starts with a hangar rocket")
	_check(p.weeks_total >= int(RocketDesigner.stats(parts)["weeks"]), "it lasts at least the rocket's build weeks")
	var asked: Array[String] = []
	s.launch_pad_ready.connect(func(id: String) -> void: asked.append(id))
	s.pilot_gate = true
	var e := ProjectDesk.launch(s, p)
	_check(e.is_empty() and p.review_state == "pad" and asked == [p.id], "with the pilot gate on it stops on the pad")
	_check(ProjectDesk.waiting_pad(s).size() == 1, "waiting_pad lists it")
	s.advance_week()
	_check(asked.size() == 2 and ProjectDesk.find(s, p.id) != null, "a week on the pad reminds the player")
	var launched: Array[Dictionary] = []
	s.mission_launched.connect(func(r: Dictionary) -> void: launched.append(r))
	var verdict := HangarRocket.flight_verdict({"result": "orbit", "orbit": true, "max_alt": 210000.0}, m)
	e = ProjectDesk.launch(s, p, verdict)
	_check(not e.is_empty() and e["piloted"] and e["success"], "the piloted verdict launches it (success)")
	_check(String(e["outcome"]) in ["full", "exceptional", "partial"] and launched.size() == 1 and launched[0]["piloted"],
		"graded as usual, the result says it was piloted (%s)" % e["outcome"])
	_check(float((e["flight"] as Dictionary).get("max_alt", 0.0)) > 200000.0, "the history keeps the flight")
	# a failed piloted flight names its cause
	var p2 := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b", "c"], "", {"parts": parts})
	p2.review_state = "pad"
	e = ProjectDesk.launch(s, p2, HangarRocket.flight_verdict({"result": "crash", "max_alt": 3000.0}, m))
	_check(not e["success"] and e["cause_key"] == "TY_HG_CAUSE_LOST", "a lost vehicle fails with its cause")
	# automatic: the usual roll
	var p3 := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b", "c"], "", {"parts": parts})
	p3.review_state = "pad"
	e = ProjectDesk.launch(s, p3, {"auto": true})
	_check(not e.is_empty() and not e["piloted"], "the automatic simulation rolls")
	# the gate off (headless): straight to the roll
	s.pilot_gate = false
	var p4 := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b", "c"], "", {"parts": parts})
	_check(not ProjectDesk.launch(s, p4).is_empty(), "with the gate off it launches")
	# swap in development
	var p5 := ProjectDesk.start_project(s, "sounding", "suborbital", ["a"])
	var sp := HangarRocket.adopt(s, HangarRocket.from_scene(_example("andorinha"), HangarRocket.mission_for(s, "sounding", "suborbital")))
	_check(ProjectDesk.swap_rocket(s, p5.id, {"parts": sp}) and HangarRocket.is_hangar(p5.rocket["parts"]),
		"a project in development takes a hangar rocket")


func _test_save_load() -> void:
	print("save / load")
	var s := _state()
	var m := HangarRocket.mission_for(s, "demo_sat", "leo")
	var d := HangarRocket.from_scene(_example("garca"), m, "Garça")
	var parts := HangarRocket.adopt(s, d)
	var p := ProjectDesk.start_project(s, "demo_sat", "leo", ["a", "b", "c"], "", {"parts": parts, "name": "Garça"})
	p.review_state = "pad"
	var text := JSON.stringify(TycoonSave.encode(s.to_dict()))
	# a fresh run: the hangar components are not in the catalogue until the save registers them
	for k in parts.values():
		if String(k).begins_with("hg"):
			RocketDesigner._by_id.erase(String(k))
	_check(RocketDesigner.component(String(parts["core"])).is_empty(), "(the catalogue forgot the hangar rocket)")
	var s2 := TycoonState.from_dict(TycoonSave.decode(JSON.parse_string(text)))
	var p2 := ProjectDesk.find(s2, p.id)
	_check(p2 != null and p2.review_state == "pad", "the project comes back on the pad")
	_check(p2 != null and HangarRocket.is_hangar(p2.rocket["parts"]), "with its hangar rocket")
	var ps := HangarRocket.scene_for(s2, p2.rocket["parts"]) if p2 else null
	_check(ps != null and JSON.stringify(HangarRocket.tree(ps)) == JSON.stringify(d["tree"]), "the vessel comes back part by part")
	_check(p2 != null and RocketDesigner.check(s2, p2.rocket["parts"], "demo_sat", "leo")["reaches"], "and still reaches orbit")
	# a save whose definition went missing: an abstract rocket, no crash
	var raw: Dictionary = TycoonSave.decode(JSON.parse_string(text))
	(raw["rockets"] as Dictionary).erase("hangar")
	for k in parts.values():
		if String(k).begins_with("hg"):
			RocketDesigner._by_id.erase(String(k))
	var s3 := TycoonState.from_dict(raw)
	var p3 := ProjectDesk.find(s3, p.id)
	_check(p3 != null and not HangarRocket.is_hangar(RocketDesigner.normalize(p3.rocket["parts"])),
		"a missing definition degrades to an abstract rocket")
	_check(p3 != null and not ProjectDesk.success_chance(s3, p3).is_empty(), "...that still has odds")
	HangarRocket.register(d)


# ------------------------------------------------------------ campus
func _open_main() -> void:
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(4)
	main.race_flow.autosave = false
	main.state.cash = 5.0e6
	TycoonResearch.complete(main.state, "orbital_rocketry")
	TycoonResearch.complete(main.state, "small_sat_bus")
	main.clock.set_speed(2)
	await _frames(2)


func _screen() -> Node:
	var layer := main.hud.get_node("%Screens")
	return layer.get_child(layer.get_child_count() - 1) if layer.get_child_count() > 0 else null


func _flow() -> ProjectFlow:
	for c in main.get_children():
		if c is ProjectFlow:
			return c
	return null


func _test_campus() -> void:
	print("campus: designer -> hangar -> project -> pad -> piloted flight")
	await _open_main()
	var s := main.state
	var modes := main.modes
	_check(modes != null, "tycoon_main has the Modes node")
	if modes == null:
		return
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = [String(free[0]["id"]), String(free[1]["id"]), String(free[2]["id"])]
	main.hud.open_screen("rocket_designer", {"type": "demo_sat", "target": "leo", "staff": team})
	await _frames(4)
	var des := _screen()
	_check(main.clock.speed == 0, "the designer holds the clock (ProjectFlow)")
	des.call("open_hangar")
	await _frames(4)
	_check(modes.is_open() and modes.kind == "hangar", "Montar no hangar opens the embedded hangar")
	_check(modes.mode_node != null and modes.mode_node.get("embedded") == true, "the hangar runs embedded")
	var mm: Dictionary = FlightSession.mission
	_check(is_equal_approx(float(mm.get("dv_needed", 0.0)), 9400.0) and is_equal_approx(float(mm.get("payload_kg", 0.0)), 300.0),
		"FlightSession.mission holds the mission (%s)" % [mm])
	_check(not main.campus.visible and not (main.get_node("UI") as CanvasLayer).visible, "the campus and the HUD are hidden")
	_check(main.campus.process_mode == Node.PROCESS_MODE_DISABLED, "the campus sleeps")
	_check(main.hud.current_screen() == "rocket_designer", "the designer waits underneath")
	var hangar: Node = modes.mode_node
	hangar.call("load_example", "garca")
	await _frames(3)
	modes.refresh_card()
	_check(not (modes.get_node("%Use") as Button).disabled, "Usar na missão is on with a rocket on the bench")
	_check(String((modes.get_node("%Verdict") as Label).text) != "", "the card says if it gets there")
	# one goal display: the hangar HUD's goal card carries the mission and its buttons
	var hui: HangarUI = hangar.get("ui")
	_check(not modes.card.visible and hui.get_node("%GoalActions").visible and hui.get_node("%GoalTitle").text != "",
		"the HUD's goal card shows the mission with Voltar / Usar na missão (the Modes card stays hidden)")
	_check((hui.get_node("%BtnMenu") as Button).text == "TY_HG_CARD_TO_CAMPUS", "the HUD's Back reads Voltar ao campus")
	_check(not (hui.get_node("%BtnUse") as Button).disabled, "the HUD's Usar na missão is on with a rocket")
	var ga: Dictionary = PartAdvisor.evaluate(v_stages(hangar), mm, float((hangar.get("vessel") as Vessel).compute_stages()["fairing_kg"]))
	_check(hui._meter_dv.get_node("Col/Top/Value").text.begins_with(HangarFormat.numk(float(ga["ascent_dv"])).left(2)),
		"the HUD's Δv counts the mission payload (%s)" % hui._meter_dv.get_node("Col/Top/Value").text)
	# the hangar's Launch is a test flight with the mission payload, and comes back
	hangar.call("launch")
	await _frames(4)
	_check(modes.test_flight and modes.mode_node is FlightWorld, "Launch opens a test flight in place of the hangar")
	var fw := modes.mode_node as FlightWorld
	_check(fw != null and is_equal_approx(fw.sim.craft.payload_kg, 300.0), "the flight carries the mission payload")
	_check(fw != null and fw.sim.craft.mass() > 254794.0 + 299.0, "...in its mass (%.0f kg)" % (fw.sim.craft.mass() if fw else 0.0))
	if fw:
		fw.revert_to_hangar()
	await _frames(4)
	_check(modes.kind == "hangar" and not modes.test_flight and modes.mode_node != null and modes.mode_node != fw,
		"Revert to hangar brings the hangar back")
	var v2: Vessel = modes.mode_node.get("vessel") if modes.mode_node else null
	_check(v2 != null and v2.root != null and v2.all_parts().size() == 16, "with the same vessel on the bench")
	var hui2: HangarUI = modes.mode_node.get("ui")
	(hui2.get_node("%BtnUse") as Button).pressed.emit()
	await _frames(3)
	_check(not modes.is_open(), "Usar na missão (the HUD's goal card) closes the hangar")
	_check(main.campus.visible and (main.get_node("UI") as CanvasLayer).visible, "the campus and the HUD come back")
	_check(FlightSession.mission.is_empty(), "FlightSession.mission is cleared")
	_check(HangarRocket.is_hangar(des.get("parts")), "the designer's bench holds the hangar rocket")
	_check(not (des.get_node("%Start") as Button).disabled, "and it can start the project (%s)" % (des.get_node("%Error") as Label).text)
	_check((des.get_node("%HangarQuick") as Button).visible, "Projeto rápido is offered to go back")
	des.call("_start")
	await _frames(4)
	var p: MissionProject = null
	for q: MissionProject in s.mission_projects:
		if HangarRocket.is_hangar(q.rocket["parts"]):
			p = q
	_check(p != null, "the project started with the hangar rocket")
	if p == null:
		return
	var flow := _flow()
	flow.dev_drop_phases(p.id)
	ProjectDesk.dev_finish_development(s, p.id)
	flow.dev_drop_phases(p.id)
	await _frames(4)
	_check(main.hud.current_screen() == "design_review", "the Design Review waits (got '%s')" % main.hud.current_screen())
	ProjectDesk.confirm_review(s, p.id, [])
	main.hud.close_screen()
	await _frames(4)
	_check(p.review_state == "pad", "the review sends it to the pad (%s)" % p.review_state)
	_check(main.hud.current_screen() == "launch_choice", "the launch choice opens (got '%s')" % main.hud.current_screen())
	_check(main.clock.speed == 0, "the clock stays held")
	# save / load of the campaign with the project on the pad
	TycoonSave.save(s, SLOT)
	var loaded := TycoonSave.load_state(SLOT)
	var lp := ProjectDesk.find(loaded, p.id) if loaded else null
	_check(lp != null and lp.review_state == "pad" and HangarRocket.scene_for(loaded, lp.rocket["parts"]) != null,
		"the save keeps the project on the pad with its vessel")
	var choice := _screen()
	_check(choice != null and String(choice.get("project_id")) == p.id, "the choice is for this project")
	# pilot, leave before liftoff: back to the choice
	choice.call("pilot")
	await _frames(4)
	fw = modes.mode_node as FlightWorld
	_check(modes.kind == "flight" and fw != null and fw.mission_mode and fw.embedded, "Pilotar opens the mission flight")
	_check(main.hud.current_screen() == "launch_choice", "the choice waits underneath")
	_check(fw != null and not (fw.hud.get_node("%BtnRevertLaunch") as Control).visible, "no revert in a mission flight")
	_press(KEY_ESCAPE)
	await _frames(2)
	_check(fw != null and fw.paused, "Esc pauses the flight")
	if fw:
		fw._on_hud_action("revert_hangar")
	await _frames(3)
	_check(not modes.is_open() and p.review_state == "pad", "leaving before liftoff cancels: still on the pad")
	_check(main.hud.current_screen() == "launch_choice" and main.clock.speed == 0, "back at the choice, clock held")
	# pilot again: lift off and end the flight short of orbit -> a failure
	choice.call("pilot")
	await _frames(4)
	fw = modes.mode_node as FlightWorld
	if fw:
		fw.stage()
		for i in 30:
			await process_frame
		fw.finish_mission()
	await _frames(6)
	_check(not modes.is_open(), "Finish the mission leaves the flight")
	_check(ProjectDesk.find(s, p.id) == null, "the project launched")
	var e: Dictionary = s.project_history[-1]
	_check(e.get("piloted", false) and String(e["outcome"]) == "fail" and String(e["cause_key"]) == "TY_HG_CAUSE_SHORT",
		"a flight ended short of orbit fails (%s, %s)" % [e.get("outcome"), e.get("cause_key")])
	_check(main.hud.current_screen() == "project_review", "the review comes up (got '%s')" % main.hud.current_screen())
	for i in 4:  # the review, then the race's newspaper on the launch
		if main.hud.current_screen() != "":
			main.hud.close_screen()
		await _frames(4)
	_check(main.hud.current_screen() == "" and main.clock.speed == 2, "the campus gets its clock back (%d, screen '%s', queue %s)" % [
		main.clock.speed, main.hud.current_screen(), _flow().queued()])


func _test_workshop() -> void:
	print("campus: the workshop's hangar and Esc")
	var lot := ""
	for l: String in main.state.lot_ids():
		if main.state.lot_kind(l) == "workshop":
			lot = l
	_check(lot != "", "the campus has a workshop")
	main.hud.show_lot(lot)
	var btn := main.hud.get_node("%HangarButton") as Button
	_check(btn.visible, "its lot panel offers the hangar")
	main.clock.set_speed(3)
	btn.pressed.emit()
	await _frames(4)
	_check(main.modes.is_open() and FlightSession.mission.is_empty(), "no project: the free workshop opens")
	_check(not (main.modes.get_node("%Use") as Control).visible, "...with no mission to use it in")
	var fhui: HangarUI = main.modes.mode_node.get("ui")
	_check(not fhui.get_node("%GoalActions").visible and (fhui.get_node("%BtnMenu") as Button).text == "TY_HG_CARD_TO_CAMPUS",
		"...the HUD shows the free workshop with Voltar ao campus")
	_check(main.clock.speed == 0, "the hangar holds the clock")
	_press(KEY_ESCAPE)
	await _frames(4)
	_check(not main.modes.is_open(), "Esc with empty hands leaves the hangar")
	_check(main.campus.visible and main.clock.speed == 3, "back on the campus with the clock running (%d)" % main.clock.speed)
	_check(main.hud.current_screen() == "", "...and no pause menu")
	# a project in development: the workshop builds its rocket
	var free := ProjectDesk.free_staff(main.state)
	var p := ProjectDesk.start_project(main.state, "sounding", "suborbital", [String(free[0]["id"])])
	await _frames(2)
	if main.hud.current_screen() != "":
		main.hud.close_screen()
	await _frames(2)
	main.modes.open_project_hangar()
	await _frames(4)
	_check(main.modes.is_open() and String(FlightSession.mission.get("target_id", "")) == "suborbital",
		"with a project in development the hangar builds for it")
	main.modes.mode_node.call("load_example", "andorinha")
	await _frames(2)
	main.modes.accept_vessel()
	await _frames(2)
	_check(p != null and HangarRocket.is_hangar(p.rocket["parts"]), "Usar na missão swaps the project's rocket")


func _test_dev_menu() -> void:
	print("dev menu")
	var dev := get_root().get_node_or_null("CwDev") as CwDevMenu
	_check(dev != null, "the CwDev autoload is up")
	if dev == null:
		return
	var msg := dev.run("mission_hangar")
	await _frames(4)
	_check(main.modes.is_open() and main.modes.kind == "hangar", "mission_hangar opens the hangar (%s)" % msg)
	_check(dev.f1_taken(), "F1 belongs to the hangar while it is open")
	main.modes.close_mode()
	await _frames(2)
	msg = dev.run("mission_flight")
	await _frames(4)
	_check(main.modes.is_open() and main.modes.kind == "flight", "mission_flight opens the piloted flight (%s)" % msg)
	_check(dev.context_tags().has("flight"), "the dev menu sees the flight context")
	var fw := main.modes.mode_node as FlightWorld
	if fw:
		fw.finish_mission()  # before liftoff: cancel
	await _frames(3)
	_check(not main.modes.is_open(), "and it closes again")
	main.queue_free()
	await _frames(2)


# ------------------------------------------------------------ helpers
func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)


func v_stages(hangar: Node) -> Array:
	return (hangar.get("vessel") as Vessel).compute_stages()["stages"]
