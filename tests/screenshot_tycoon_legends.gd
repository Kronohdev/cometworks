extends SceneTree
## Windowed screenshots of As Lendas (TycoonLegends):
##   legends_01_market     the hiring market with a Lenda on its golden card
##   legends_02_sheet      the Lenda's sheet: unique specialisation and the Quem inspirou key
##   legends_03_mentor     the briefing board with a mentor's line, portrait and name
##   legends_04_race       the race board: the rival leaders' faces on the agency tiles
##   legends_05_agency     a rival agency's page with its leader
##   legends_06_shelf      the encyclopedia shelf with the Quem inspirou tile
##   legends_07_cards      the Quem inspirou cards
##   legends_08_card       one Quem inspirou card (Albertinho / Santos-Dumont)
##   legends_09_card_en    a rival leader's card in English
##   legends_10_hats       the leader creator's hats, the Lendas' new ones included
##   legends_11_hat_*      the leader wearing each new hat
##   legends_hat_*         the new hats on their Lendas' cards
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon_legends.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt_BR")
	CwMotion.set_reduced(true)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	var s := main.state
	TycoonCrew.ensure(s)
	s.cash = 3.0e6
	# year 7, era 2: a few rival firsts for the race board
	s.weeks = 6 * s.weeks_per_year() + 3
	s.race.claim("suborbital", "aurora")
	s.race.claim("first_satellite", "nimbo")
	s.race.claim("suborbital", "quietude")
	s.race.pending_pages.clear()
	var c := TycoonLegends.dev_spawn(s, "albertinho")
	main.hud.close_screen()
	await _frames(20)
	main.hud.open_screen("crew", {"tab": "hire"})
	var crew := main.hud.get_node("%Screens").get_child(0) as CrewScreen
	await _frames(90)
	await _shot("legends_01_market")
	crew.select_candidate(String(c["id"]))
	await _frames(60)
	await _shot("legends_02_sheet")
	TycoonLegends.dev_mentors = true
	BriefingDesk.spawn(s, "crop_health")
	main.hud.open_screen("briefings", {"briefing_id": "crop_health"})
	await _frames(90)
	await _shot("legends_03_mentor")
	main.hud.open_screen("race")
	var race := main.hud.get_node("%Screens").get_child(0) as RaceScreen
	await _frames(90)
	await _shot("legends_04_race")
	race.open_agency("aurora")
	await _frames(60)
	await _shot("legends_05_agency")
	for l in TycoonLegends.of_kind("hire"):
		(TycoonLegends.st(s)["seen"] as Dictionary)[String(l["id"])] = s.weeks
	main.hud.open_screen("book")
	var book := main.hud.get_node("%Screens").get_child(0) as OpsBookScreen
	await _frames(50)
	await _shot("legends_06_shelf")
	book.show_page("legends")
	await _frames(90)
	await _shot("legends_07_cards")
	book.open_legend("albertinho")
	await _frames(60)
	await _shot("legends_08_card")
	TranslationServer.set_locale("en")
	main.hud.open_screen("book", {"legend": "herschelinha"})
	await _frames(60)
	await _shot("legends_09_card_en")
	TranslationServer.set_locale("pt_BR")
	# the new hats up close, on their Lendas' cards
	for id in ["katia", "cesinha", "pontinha", "dora", "cifrinha"]:
		main.hud.open_screen("book", {"legend": id})
		await _frames(45)
		await _shot("legends_hat_" + id)
	main.hud.open_screen("leader_creator")
	await _frames(60)
	await _shot("legends_10_hats")
	# the leader wearing the new hats in the creator's big preview
	var creator := main.hud.get_node("%Screens").get_child(0)
	for h in ["aviator", "headset", "glasses", "mortarboard", "coin"]:
		creator.call("pick", "hat", h)
		await _frames(40)
		await _shot("legends_11_hat_" + h)
	print("LEGENDS SCREENSHOTS DONE")
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
