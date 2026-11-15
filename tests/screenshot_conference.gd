extends SceneTree
## Windowed screenshots of the Conferência dos Cometinhos (src/tycoon/conference/):
##   conf_01_invite     the invitation screen on the campus
##   conf_02_arrival    the fair from the gate, over the leader's shoulder
##   conf_03_stand      a rival's stand with its leader and live board
##   conf_04_talk       the rival leader's report in the dialogue box
##   conf_05_host       the host's kiosk
##   conf_06_duo        two Lendas trading their exchange in bubbles
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_conference.gd -- <out_dir>

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
	if main.hud.current_screen() != "":
		main.hud.close_screen()
	main.state.race.pending_pages.clear()
	var s := main.state
	s.weeks = 17 * s.weeks_per_year() + 21   # year 18
	for rid in ["aurora", "nimbo", "quietude"]:
		for ms in ["suborbital", "first_satellite", "long_signal"]:
			s.race.claim(ms, rid)
	s.race.pending_pages.clear()
	await _frames(5)
	main.hud.open_screen("conference")
	await _wait(1.2)
	await _shot("conf_01_invite")
	main.hud.close_screen()
	await _frames(5)
	main.conference.dev_open()
	main.chatter.force_enabled = 1
	var fair := main.conference.fair
	fair.player.enabled = false   # no mouse drift in the shots
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(1.5)
	await _shot("conf_02_arrival")
	var leader: Dictionary = {}
	for e in fair.npcs:
		if String(e["role"]) == ConferenceBook.ROLE_RIVAL:
			leader = e
			break
	var ln: Node3D = leader["node"]
	_stand_before(fair, ln, 4.5)
	await _wait(1.5)
	await _shot("conf_03_stand")
	_stand_before(fair, ln, 2.2)
	await _wait(0.5)
	fair.talk_to(leader)
	await _wait(0.6)
	for i in main.talk.shown_choices.size():
		if String(main.talk.shown_choices[i]["text"]) == tr("TY_CONF_ASK_NEWS"):
			main.talk.choose(i)
			break
	await _wait(3.0)
	await _shot("conf_04_talk")
	main.talk.close()
	await _frames(2)
	fair.player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for e in fair.npcs:
		if String(e["role"]) == ConferenceBook.ROLE_HOST:
			_stand_before(fair, e["node"], 4.0)
	await _wait(1.5)
	await _shot("conf_05_host")
	if not fair.duo_nodes.is_empty():
		var d: Dictionary = fair.duo_nodes[0]
		var mid := ((d["a"] as Node3D).position + (d["b"] as Node3D).position) * 0.5
		_stand_at(fair, mid, 6.0)
		await _wait(3.0)
		await _shot("conf_06_duo")
	quit()


## Puts the leader `dist` m in front of a Lenda, the camera behind looking at her.
func _stand_before(fair: ConferenceFair, n: Node3D, dist: float) -> void:
	var fwd := n.basis.z
	var at := n.position + fwd * dist
	fair.player.place(at, atan2(-fwd.x, -fwd.z))


func _stand_at(fair: ConferenceFair, target: Vector3, dist: float) -> void:
	var dir := (Vector3(0, 0, 0) - target)
	dir.y = 0
	dir = dir.normalized()
	fair.player.place(target + dir * dist, atan2(-dir.x, -dir.z))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0):
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_root().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
