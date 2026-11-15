extends SceneTree
## Windowed screenshots of talks with the Lendas (CometlingDialogue, "lenda_<id>" trees) on the
## Cometworks main screen:
##   lenda_katia_campus     Kátia hired, walking the campus, telling who inspired her
##   lenda_sali_briefing    a mentor answering from her bubble on the mission board (her tip)
##   lenda_gagarinho_race   the Aurora Rubra leader on the race board, teasing: Aurora is ahead
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_lenda_talk.gd -- <out_dir> [pt|en]

var out_dir := "user://lenda_talk"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	TranslationServer.set_locale(args[1] if args.size() > 1 else "pt")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await process_frame
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(8)
	main.race_flow.autosave = false
	main.clock.set_speed(0)
	var s := main.state
	var talk := main.talk
	talk.type_speed = 10000.0
	# Kátia on the campus
	s.cash = 1.0e8
	var cand := TycoonLegends.dev_spawn(s, "katia")
	TycoonCrew.hire(s, String(cand.get("id", "")))
	await _frames(20)
	for w in main.campus.cometlings():
		if String(main.campus.cometling_member(w).get("legend", "")) == "katia":
			main.camera.follow(w)
			await _seconds(2.0)
			talk.open(w)
			_pick(talk, "who")
			await _seconds(1.2)
			await _shot("lenda_katia_campus")
			talk.close()
			main.camera.release()
			break
	# Sali from a briefing
	TycoonLegends.dev_mentors = true
	s.weeks = 3 * 5 * s.weeks_per_year() + 12
	var bid := ""
	for b: Dictionary in BriefingDesk.briefings():
		for h in TycoonLegends.mentor_hints(s, b, Discovery.briefing_hints(s, b).is_empty()):
			if String(h["legend"]) == "sali":
				bid = String(b["id"])
		if bid != "":
			break
	if bid != "":
		BriefingDesk.spawn(s, bid)
	main.hud.open_screen("briefings", {"briefing_id": bid})
	await _seconds(0.6)
	main.hud.talk_to_legend("sali", "briefing")
	_pick(talk, "tip")
	await _seconds(1.2)
	await _shot("lenda_sali_briefing")
	main.hud.close_screen()
	await _frames(4)
	# Gagarinho on the race board, Aurora ahead
	s.race.claim("suborbital", "aurora")
	s.race.claim("first_satellite", "aurora")
	main.hud.open_screen("race")
	await _frames(4)
	var race := main.hud.get_node("%Screens").get_child(0)
	race.call("open_agency", "aurora")
	await _seconds(0.6)
	(race.get_node("%LeaderTalk") as LinkButton).pressed.emit()
	_pick(talk, "race")
	await _seconds(1.2)
	await _shot("lenda_gagarinho_race")
	print("LENDA TALK SCREENSHOTS DONE")
	quit()


## Picks the choice that goes to node `node_id` (if the talk offers it).
func _pick(talk: CometlingDialogue, node_id: String) -> void:
	if talk.run == null:
		return
	for i in talk.shown_choices.size():
		var c: Dictionary = talk.run._choice_list()[int(talk.shown_choices[i]["index"])]
		if String(c.get("goto", "")) == node_id:
			talk.choose(i)
			return


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _seconds(t: float) -> void:
	await create_timer(t, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
