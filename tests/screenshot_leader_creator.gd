extends SceneTree
## Windowed screenshots of the leader creator (scenes/tycoon/ui/screens/leader_creator.tscn):
##   leader_01_default      the creator as "Nova campanha" opens it
##   leader_02_pilot        a pilot in coral with a crown, turned on the turntable
##   leader_03_researcher   a researcher with the propeller cap (and the other language)
##   leader_hat_<id>        close-ups of the preview with each hat
##   leader_04_campus       the campaign started: the camera follows the leader on the campus
##   leader_05_crew         the crew screen on the leader (badge, edit button)
##   leader_06_edit         the creator opened from the crew screen (profession locked)
##   leader_07_race         the race screen, the player's lane with the agency emblem
##   leader_campus_hat_<id> each hat on the campus, with a speech bubble beside the gold star
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_leader_creator.gd -- <out_dir> [pt|en]

var out_dir := "user://"
var lang := "pt"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		lang = args[1]
	var other := "en" if lang == "pt" else "pt"
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt_BR" if lang == "pt" else "en")
	var cr := (load(LeaderCreator.SCENE) as PackedScene).instantiate() as LeaderCreator
	cr.preload_campus = false
	get_root().add_child(cr)
	cr.set_leader_name("Pipoca Estelar" if lang == "pt" else "Sprinkle Starling")
	await _frames(70)
	await _shot("leader_01_default_" + lang)
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
	cr.set("_yaw", -0.5)
	await _frames(80)
	await _shot("leader_02_pilot_" + lang)
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
	await _frames(80)
	await _shot("leader_03_researcher_" + other)
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
	await _shot("leader_04_campus_" + lang)
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
	await _shot("leader_05_crew_" + lang)
	main.hud.open_screen("leader_creator")
	await _frames(60)
	await _shot("leader_06_edit_" + lang)
	main.hud.open_screen("race")
	await _frames(40)
	await _shot("leader_07_race_" + lang)
	print("LEADER SCREENSHOTS DONE")
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


func _shot_region(shot_name: String, c: Control) -> void:
	await _shot_rect(shot_name, Rect2i(c.get_global_rect()))


func _shot_rect(shot_name: String, r: Rect2i) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img = img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
