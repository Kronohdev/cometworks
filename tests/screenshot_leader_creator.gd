extends SceneTree
## Windowed screenshots of the leader creator (scenes/tycoon/ui/screens/leader_creator.tscn):
##   leader_01_look         the creator as "Nova campanha" opens it (tab 1, look)
##   leader_02_job          a pilot in coral with a crown, turned on the turntable (tab 2, job)
##   leader_03_way          strength and personality (tab 3)
##   leader_04_agency       the agency's name, race colour and emblem (tab 4)
##   leader_04b_react       right after a change: hop, emote bubble, face and sparkles
##   leader_hat_<id>        close-ups of the preview with each hat
##   leader_05_researcher   a researcher with the propeller cap (and the other language)
##   leader_06_campus       the campaign started: the camera follows the leader on the campus
##   leader_campus_hat_<id> each hat on the campus, with a speech bubble beside the gold star
##   leader_07_crew         the crew screen on the leader (badge, edit button)
##   leader_08_edit         the creator opened from the crew screen (profession locked)
##   leader_09_race         the race screen, the player's lane with the agency emblem
## Every creator shot also checks the fit: no visible control may poke out of the window
## (prints "FIT ok" or "FIT overflow <node> <rect>").
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_leader_creator.gd -- <out_dir> [pt|en] [creator]
## "creator" takes only the four tabs (suffixed with the window size), for checking the
## layout at many sizes.

var out_dir := "user://"
var lang := "pt"
var only_creator := false
var overflows := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		lang = args[1]
	only_creator = args.size() > 2 and args[2] == "creator"
	var other := "en" if lang == "pt" else "pt"
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt_BR" if lang == "pt" else "en")
	var cr := (load(LeaderCreator.SCENE) as PackedScene).instantiate() as LeaderCreator
	cr.preload_campus = false
	get_root().add_child(cr)
	cr.set_leader_name("Pipoca Estelar" if lang == "pt" else "Sprinkle Starling")
	await _frames(70)
	var size_tag := "_%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y] if only_creator else ""
	await _creator_shot(cr, "leader_01_look_" + lang + size_tag)
	cr.pick("profession", "pilot")
	cr.pick("body", "#ffa3a3")
	cr.pick("spot", "#3fe0c5")
	cr.pick("hat", "crown")
	cr.pick("strength", "courage")
	cr.pick("quirk", "dreamer")
	cr.pick("agency_color", "#5bd68e")
	cr.pick("emblem", "rocket")
	cr.leader["agency_name"] = "Cauda Brilhante" if lang == "pt" else "Bright Tail Agency"
	cr.refresh()
	cr.show_page(1)
	cr.set("_yaw", -0.5)
	await _frames(80)
	await _creator_shot(cr, "leader_02_job_" + lang + size_tag)
	cr.show_page(2)
	await _frames(50)
	await _creator_shot(cr, "leader_03_way_" + lang + size_tag)
	cr.show_page(3)
	await _frames(50)
	await _creator_shot(cr, "leader_04_agency_" + lang + size_tag)
	# a change: the Cometling reacts (move, emote bubble, face, sparkle burst)
	cr.show_page(0)
	cr.pick("hat", "flower")
	await _frames(24)
	await _shot("leader_04b_react_" + lang + size_tag)
	if only_creator:
		print("FIT TOTAL: %d overflow(s)" % overflows)
		print("LEADER SCREENSHOTS DONE")
		quit()
		return
	cr.show_page(0)
	for h in ["crown", "propeller", "beanie", "flower", "bow", "none", "role"]:
		cr.pick("hat", h)
		cr.set("_yaw", 0.35)
		await _frames(50)
		await _shot_region("leader_hat_%s" % h, cr.get_node("%Preview") as Control)
	TranslationServer.set_locale("en" if other == "en" else "pt_BR")
	cr.set_leader_name("Mochi Glimmer" if other == "en" else "Mochi Brilhante")
	cr.pick("profession", "researcher")
	cr.pick("body", "#c9b8ff")
	cr.pick("spot", "#ffcc55")
	cr.pick("hat", "propeller")
	cr.pick("strength", "curiosity")
	cr.show_page(1)
	await _frames(80)
	await _creator_shot(cr, "leader_05_researcher_" + other)
	TranslationServer.set_locale("pt_BR" if lang == "pt" else "en")
	var leader := cr.leader.duplicate()
	leader["hat"] = "crown"
	cr.queue_free()
	await _frames(2)
	# the campaign with that leader
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.leader = leader
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	await _frames(60)
	var lw: Node3D = null
	for w in main.campus.cometlings():
		if String(w.get("member_id")) == TycoonLeader.ID:
			main.camera.follow(w)
			lw = w
	await _frames(200)
	await _shot("leader_06_campus_" + lang)
	# each hat as the campus camera sees it (a crop around the followed leader)
	if lw:
		var c := lw.get_node("Creature") as Cometling
		var vs := Vector2(get_root().get_texture().get_size())
		var crop := Rect2(vs.x * 0.3, vs.y * 0.18, vs.x * 0.4, vs.y * 0.55)
		for h in ["crown", "propeller", "beanie", "flower", "bow"]:
			LeaderHat.wear(c, h)
			c.show_emote("heart", 3.0)   # the bubble pops beside the gold star, not over it
			await _frames(40)
			await _shot_rect("leader_campus_hat_%s" % h, Rect2i(crop))
		LeaderHat.wear(c, "crown")
	main.camera.release()
	main.hud.open_screen("crew", {"staff_id": TycoonLeader.ID})
	await _frames(40)
	await _shot("leader_07_crew_" + lang)
	main.hud.open_screen("leader_creator")
	await _frames(30)
	var ed := main.hud.get_node("%Screens").get_child(0) as LeaderCreator
	if ed:
		ed.show_page(1)
	await _frames(40)
	if ed:
		await _creator_shot(ed, "leader_08_edit_" + lang)
	main.hud.open_screen("race")
	await _frames(40)
	await _shot("leader_09_race_" + lang)
	print("FIT TOTAL: %d overflow(s)" % overflows)
	print("LEADER SCREENSHOTS DONE")
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


## A creator shot plus the fit check.
func _creator_shot(cr: Control, shot_name: String) -> void:
	await _shot(shot_name)
	_check_fit(cr, shot_name)


## Every visible control of the creator stays inside the window (the sky and the glow are
## backdrops, they may bleed).
func _check_fit(cr: Control, shot_name: String) -> void:
	var view := Rect2(Vector2.ZERO, cr.get_viewport_rect().size).grow(1.0)
	var bad: Array[String] = []
	var stack: Array[Node] = [cr]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c := n as Control
			if not c.is_visible_in_tree() or c.name in ["Sky", "Comet", "Glow", "Fade"]:
				continue
			if not view.encloses(c.get_global_rect()):
				bad.append("%s %s" % [cr.get_path_to(c), c.get_global_rect()])
			# a control squeezed below its own minimum size overflows its parent
			var min_size := c.get_combined_minimum_size()
			if c.size.x + 1.0 < min_size.x or c.size.y + 1.0 < min_size.y:
				bad.append("%s squeezed %s < %s" % [cr.get_path_to(c), c.size, min_size])
		for k in n.get_children():
			stack.append(k)
	if bad.is_empty():
		print("FIT ok %s" % shot_name)
	else:
		overflows += bad.size()
		for b in bad.slice(0, 8):
			print("FIT overflow %s: %s" % [shot_name, b])


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)


func _shot_region(shot_name: String, c: Control) -> void:
	await _shot_rect(shot_name, Rect2i(c.get_global_rect()))


func _shot_rect(shot_name: String, r: Rect2i) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img = img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
