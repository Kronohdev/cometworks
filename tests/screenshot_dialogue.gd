extends SceneTree
## Windowed screenshots of the Cometlings talking (src/tycoon/talk/):
##   dlg_01_bubbles        a group of Cometlings chatting in bubbles (a line, an exchange)
##   dlg_02_bubbles_far    the same from the start view, far out (bubbles shrink)
##   dlg_03_box            "Conversar" open on a Cometling: portrait, name, line, choices
##   dlg_04_box_feel       after "Como você tá?": the morale note
##   dlg_05_box_en         the box in English
##   dlg_06_follow_tag     the follow tag with its Conversar button
##   dlg_07_halley         Vovô Edmundo on his bench, talking
##   dlg_08_settings       the settings' Image tab with Balões de fala and the frequency
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_dialogue.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt_BR")
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.race_flow.autosave = false
	main.camera.tour_enabled = false
	main.clock.set_speed(1)
	var chatter := main.chatter
	chatter.force_enabled = 1
	chatter.force_rate = "many"
	chatter.rng.seed = 7
	chatter.set_process(false)
	await _wait(6.0)   # the Cometlings walk to their spots
	var who := main.campus.cometlings()
	# a group: the Cometling with the most others near it
	var best: Node3D = who[0]
	var best_n := -1
	for w in who:
		var n := 0
		for o in who:
			if o != w and o.global_position.distance_to(w.global_position) < 14.0:
				n += 1
		if n > best_n:
			best_n = n
			best = w
	var group: Array[Node3D] = []
	for o in who:
		if o.global_position.distance_to(best.global_position) < 14.0:
			group.append(o)
	main.camera.frame_area(best.global_position, Vector2(26, 26))
	await _wait(2.5)
	_talk(chatter, group)
	await _step(chatter, 1.0)
	await _shot("dlg_01_bubbles")
	main.camera.reset_view()   # the start view, far out
	await _wait(2.5)
	chatter.clear()
	chatter._cool.clear()
	_talk(chatter, group)
	await _step(chatter, 1.0)
	await _shot("dlg_02_bubbles_far")
	chatter.clear()

	# the box
	main.camera.follow(best)
	await _wait(2.5)
	await _shot("dlg_06_follow_tag")
	main.talk.open(best)
	await _wait(2.5)
	await _shot("dlg_03_box")
	var feel := -1
	for i in main.talk.shown_choices.size():
		if String(main.talk.shown_choices[i]["text"]) == tr("TY_DLG_ASK_FEEL"):
			feel = i
	main.talk.choose(feel)
	await _wait(2.5)
	await _shot("dlg_04_box_feel")
	main.talk.close()
	TranslationServer.set_locale("en")
	await _frames(2)
	main.talk.open(best)
	await _wait(2.5)
	await _shot("dlg_05_box_en")
	main.talk.close()
	TranslationServer.set_locale("pt_BR")
	# Vovô on his bench
	var halley := main.get_node("Halley") as Node3D
	main.camera.follow(halley)
	await _wait(3.0)
	main.talk.open(halley)
	await _wait(3.0)
	await _shot("dlg_07_halley")
	main.talk.close()
	main.camera.release()
	await _wait(1.0)
	main.hud.open_screen("settings")
	await _wait(0.6)
	(main.hud.get_node("%Screens").get_child(0).find_child("ImageTab", true, false) as Button).pressed.emit()
	await _wait(1.0)
	await _shot("dlg_08_settings")
	quit()


## A line or an exchange over the Cometlings of a group.
func _talk(chatter: CampusChatter, group: Array[Node3D]) -> void:
	var used := {}
	if group.size() >= 2:
		chatter.say_pair(group[0], group[1])
		used[group[0]] = true
		used[group[1]] = true
	for g in group:
		if not used.has(g) and chatter.active_count() < 4:
			chatter.say_line(g)


func _step(chatter: CampusChatter, s: float) -> void:
	var t := 0.0
	while t < s:
		chatter.tick(1.0 / 60.0)
		t += 1.0 / 60.0
		await process_frame
	# the answer of the exchange
	chatter._run_queue(2.0)
	for i in 30:
		chatter.tick(1.0 / 60.0)
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	print("saved ", path, " err=", img.save_png(path))


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _frames(k: int) -> void:
	for i in k:
		await process_frame
