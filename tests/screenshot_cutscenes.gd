extends SceneTree
## Windowed screenshots of the story cutscenes (scenes/cutscenes/, src/cutscene/): each
## cutscene plays for real (letterbox, typed lines, title cards) with a sample leader, and
## every shot is captured at a few moments:
##   cs_<lang>_<cutscene>_<NN>_<pp>   shot NN at pp % of its length
## Optional filters after the language: a cutscene id, then a shot index (starts there and
## captures that shot only), e.g. `-- out pt opening 3`.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_cutscenes.gd -- <out_dir> [pt|en] [id] [shot]

const LEADER := {"name": "Estrela", "body": "#ffa3a3", "spot": "#ffcc55", "hat": "crown", "quirk": "",
	"profession": "pilot", "strength": "courage", "agency_name": "Cauda Brilhante", "agency_color": "#5bd68e",
	"emblem": "comet"}
const FRACTIONS := [0.2, 0.55, 0.9]

var out_dir := "user://cutscenes"
var _host: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var lang := args[1] if args.size() > 1 else "pt"
	var only := args[2] if args.size() > 2 else ""
	var from := int(args[3]) if args.size() > 3 else -1
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale(lang)
	await process_frame
	# a stand-in for the campus behind (the cutscene switches its 3D off while it plays)
	_host = Node3D.new()
	get_root().add_child(_host)
	for id: String in Cutscenes.ALL:
		if only != "" and id != only:
			continue
		await _capture(id, lang, from)
	print("CUTSCENE SCREENSHOTS DONE")
	quit()


func _capture(id: String, lang: String, from: int) -> void:
	var state := TycoonState.new_campaign(7)
	TycoonLeader.found(state, LEADER.duplicate())
	var c := (load(Cutscenes.path(id)) as PackedScene).instantiate() as Cutscene
	c.id = id
	c.bind_state(state)
	_host.add_child(c)
	var done := [false]
	c.finished.connect(func(_s: bool) -> void: done[0] = true)
	var t0 := Time.get_ticks_msec()
	c.start(maxi(from, 0))
	var seen := {}
	Engine.time_scale = 2.0
	while not done[0]:
		await process_frame
		if not is_instance_valid(c):
			break
		var shot := c.shot
		if shot == null or not is_instance_valid(shot):
			continue
		if from >= 0 and c.index > from:
			c.skip_all()
			break
		for f: float in FRACTIONS:
			var key := "%d_%d" % [c.index, int(f * 100)]
			if seen.has(key) or shot.time < shot.duration * f:
				continue
			seen[key] = true
			Engine.time_scale = 1.0
			await _shot("cs_%s_%s_%02d_%02d" % [lang, id, c.index + 1, int(f * 100)])
			Engine.time_scale = 2.0
		if Time.get_ticks_msec() - t0 > 400000:
			push_error("cutscene %s did not end" % id)
			break
	Engine.time_scale = 1.0
	while not done[0]:
		await process_frame
	paused = false
	await _frames(5)


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
