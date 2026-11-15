extends SceneTree
## Windowed screenshots of the Mission Design Lab stand at the Conferência dos Cometinhos
## (ConferenceFair._build_lab, the DesignLab booth of tools/build_conference_dressing.gd):
##   lab_01_clean      the booth and its team, no HUD and no leader (a trailer shot)
##   lab_02_stand      the booth over the leader's shoulder, with the fair's HUD
##   lab_03_intro      the team's hello in the dialogue box
##   lab_04_trades     the Trade Studies explanation
##   lab_05_cml        the read of the player's last concept (CML 3, from project_history)
##   lab_06_tip        what to work on next
##   lab_07_overview   the back of the plaza from above: the lab between two rival stands
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_design_lab.gd -- <out_dir> [pt|en]
## The files get the language as a suffix (lab_01_clean_en.png).

var out_dir := "user://"
var lang := "pt"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		lang = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt_BR" if lang == "pt" else "en")
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.race_flow.autosave = false
	main.camera.tour_enabled = false
	if main.tutorial:
		main.tutorial.set_process(false)
	if main.hud.current_screen() != "":
		main.hud.close_screen()
	main.state.race.pending_pages.clear()
	var s := main.state
	s.weeks = 5 * s.weeks_per_year() + 21   # year 6
	s.project_history.append({"id": "shot_lab", "code": "CW-03", "week": s.weeks - 30, "success": true, "cml": 3})
	(main.get_node("ToastLayer") as CanvasLayer).visible = false   # no achievement notes in the shots
	var dc := main.get_node_or_null("DayCycle") as CampusDayCycle
	if dc:
		dc.force_phase = 0.04   # golden hour: the fair takes the campus' light when it opens
	await _frames(5)
	main.conference.dev_open()
	var fair := main.conference.fair
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# the clean shot: no HUD, no leader, the camera centred on the booth
	var shoulder := fair.player.shoulder
	fair.player.shoulder = 0.0
	fair.frame_design_lab(4.9, true, 1.75)
	fair.hud.visible = false
	await _wait(3.0)
	await _shot("lab_01_clean")
	# over the leader's shoulder, with the HUD
	fair.hud.visible = true
	fair.player.shoulder = shoulder
	fair.player.camera_height = ConferenceBook.player_cfg("camera_height", 2.15)
	fair.frame_design_lab(2.4)
	fair.get_node("%Flash").visible = false
	await _wait(1.0)
	await _shot("lab_02_stand")
	# the dialogue
	var lead: Dictionary = fair.lab_npcs[0]
	fair.frame_design_lab(3.4)
	await _frames(2)
	fair.talk_to(lead)
	await _wait(2.6)
	await _shot("lab_03_intro")
	_pick("TY_CONF_LAB_ASK_LEVELS")
	await _wait(0.4)
	_pick("TY_CONF_LAB_ASK_TRADES")
	await _wait(3.2)
	await _shot("lab_04_trades")
	_pick("TY_CONF_LAB_ASK_MINE")
	await _wait(3.2)
	await _shot("lab_05_cml")
	_pick("TY_CONF_LAB_ASK_TIP")
	await _wait(3.2)
	await _shot("lab_06_tip")
	main.talk.close()
	await _frames(3)
	# from above: where the lab stands
	fair.set_walking(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fair.hud.visible = false
	fair.player.camera = null   # the camera stays where it is put
	fair.camera.global_position = Vector3(-3.0, 15.0, -2.0)
	fair.camera.look_at(Vector3(-6.0, 0.0, -16.5))
	await _wait(1.0)
	await _shot("lab_07_overview")
	quit()


## Picks the choice of the dialogue box whose text is key `key` (typing skipped first).
func _pick(key: String) -> void:
	for i in main.talk.shown_choices.size():
		if String(main.talk.shown_choices[i]["text"]) == tr(key):
			main.talk.choose(i)
			return
	push_warning("no choice %s among %s" % [key, main.talk.shown_choices])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0):
		await process_frame


func _shot(name: String) -> void:
	if main.talk.is_open() and main.talk._typing:
		main.talk._finish_typing()   # the whole line on show
	await _frames(2)
	var img := get_root().get_texture().get_image()
	img.save_png(out_dir.path_join("%s_%s.png" % [name, lang]))
	print("saved ", name)
