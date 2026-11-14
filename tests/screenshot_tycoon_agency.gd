extends SceneTree
## Windowed screenshots of the E3 agency screens over the Cometworks main screen:
##   agency_01_research      tech tree in year 3 (era 1): done, researching, queued, available, locked
##   agency_02_contracts     contract board with government, commercial and Space Apps offers
##   agency_03_finance       24-month ledger, cash chart with projection, bills and loan
##   agency_04_research_en   the tech tree in English, era 3
##   agency_05_contracts_en  the board in English
##   agency_06_finance_loan  finance after the government stepped in (loan on the table)
##   agency_07_campus_news   the campus HUD with the agency news on the Tail Radio
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_agency.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt")
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	var s := main.state
	s.staff.append(s.normalize_staff({"name": "Lyra", "profession": "researcher", "skill": 0.75, "level": 2}, s.staff.size()))
	_play(s, 2 * 52 + 30)
	# something waiting in the queue behind the funded research
	for t: Dictionary in TycoonResearch.techs():
		if TycoonResearch.node_state(s, String(t["id"])) == "available":
			TycoonResearch.fund(s, String(t["id"]))
			break
	await _frames(30)
	main.hud.open_screen("research")
	await _frames(20)
	await _shot("agency_01_research")
	_play(s, 4 * 52 + 42)
	# one mission just came home: a free slot on the board
	var signed := TycoonContracts.accepted(s)
	if not signed.is_empty():
		s.complete_contract(String(signed[0]["id"]), 8.4, true)
	main.hud.open_screen("contracts")
	await _frames(20)
	await _shot("agency_02_contracts")
	main.hud.open_screen("finance")
	await _frames(20)
	await _shot("agency_03_finance")
	main.hud.close_screen()
	await _frames(20)
	await _shot("agency_07_campus_news")
	TranslationServer.set_locale("en")
	_play(s, 5 * 52)
	main.hud.open_screen("research")
	await _frames(20)
	await _shot("agency_04_research_en")
	main.hud.open_screen("contracts")
	await _frames(20)
	await _shot("agency_05_contracts_en")
	TranslationServer.set_locale("pt")
	# a rough patch: three months in the red
	s.cash = -120000.0
	for i in 14:
		s.cash = minf(s.cash, -120000.0)
		s.advance_week()
	main.hud.open_screen("finance")
	await _frames(20)
	await _shot("agency_06_finance_loan")
	print("AGENCY SCREENSHOTS DONE")
	quit()


## A quick automatic campaign: funds research, builds the lab, signs contracts and completes
## them (project costs paid weekly), so the screens have a lived-in state.
func _play(s: TycoonState, n_weeks: int) -> void:
	var dice := RandomNumberGenerator.new()
	dice.seed = 99
	var jobs := {}
	var era_cost := [1.0, 1.6, 2.4, 3.4, 4.5]
	for w in n_weeks:
		s.advance_week()
		if TycoonResearch.active(s) == "" and TycoonResearch.queue(s).is_empty():
			var best := ""
			var bc := INF
			for t: Dictionary in TycoonResearch.techs():
				if TycoonResearch.can_research(s, String(t["id"])) and float(t["cost"]) < bc:
					best = String(t["id"])
					bc = float(t["cost"])
			if best != "":
				TycoonResearch.fund(s, best)
		var nx := s.next_level("lab")
		if not nx.is_empty() and s.cash > float(nx["cost"]) * 2.5:
			s.build("lab")
		var offers := TycoonContracts.offers(s)
		if not offers.is_empty() and dice.randf() < 0.5:
			var c: Dictionary = offers[dice.randi_range(0, offers.size() - 1)]
			if TycoonContracts.accept(s, String(c["id"])):
				jobs[String(c["id"])] = s.weeks + int(s.mission_type(String(c["type"]))["weeks"]) + 3 + dice.randi_range(0, 6)
		for id: String in jobs.keys():
			var c := TycoonContracts.find(s, id)
			if c.is_empty() or String(c["status"]) != "accepted":
				jobs.erase(id)
				continue
			var size := float(s.mission_type(String(c["type"]))["size"])
			if s.weeks < int(jobs[id]) - 3:
				s.cash -= 6000.0 * size * float(era_cost[s.era() - 1])
			elif s.weeks == int(jobs[id]) - 3:
				s.cash -= 60000.0 * size * float(era_cost[s.era() - 1])
			elif s.weeks >= int(jobs[id]):
				var ok := dice.randf() > 0.12
				s.complete_contract(id, dice.randf_range(5.0, 9.5), ok)
				if ok:
					s.research_points += 12.0 * size * s.era()
				jobs.erase(id)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
