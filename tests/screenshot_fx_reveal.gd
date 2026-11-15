extends SceneTree
## Windowed screenshots of the reveal flourishes (CwAppear in the screen scenes) caught on the
## way in: the newspaper front page (headline stamp, photo, tape) and the project review
## (critics' papers dealt in, outcome badge stamped), each at a few moments after opening:
##   reveal_paper_<ms> / reveal_review_<ms>
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_fx_reveal.gd -- <out_dir> [en|pt]

const MOMENTS := [0.12, 0.4, 0.7, 1.4]

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		TranslationServer.set_locale(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	for c in main.get_children():
		if c is ProjectFlow:
			(c as ProjectFlow).launch_cinematic = false
	var s := main.state
	await _frames(60)
	# the newspaper: a first for the player
	s.race.claim("crewed_flyby", "player")
	s.race.pending_pages.clear()
	main.hud.close_screen()
	await _frames(10)
	await _reveal("newspaper", {"page": s.race.pages[0]}, "reveal_paper")
	main.hud.close_screen()
	await _frames(10)
	# the review: a sounding rocket project run through its three phases
	BriefingDesk.spawn(s, "first_hop")
	main.hud.open_screen("briefings")
	await _frames(20)
	_screen().call("_accept")
	await _frames(15)
	_screen().call("_start")
	await _frames(15)
	_screen().call("_next")
	await _frames(15)
	_screen().call("_next")
	await _frames(15)
	_screen().call("_start")
	await _frames(15)
	for k in 3:
		_screen().call("_confirm")
		await _frames(5)
		s.advance_week()
		await _frames(20)
	var dr := _screen()
	if dr and dr.has_method("_launch"):
		# catch the review the moment it opens
		dr.call("_launch")
		await _catch("reveal_review")
	print("REVEAL SCREENSHOTS DONE")
	quit()


func _screen() -> Node:
	var screens := main.hud.get_node("%Screens")
	return screens.get_child(0) if screens.get_child_count() > 0 else null


func _reveal(screen: String, args: Dictionary, prefix: String) -> void:
	main.hud.open_screen(screen, args)
	await _catch(prefix)


func _catch(prefix: String) -> void:
	var t0 := Time.get_ticks_msec()
	for m: float in MOMENTS:
		while Time.get_ticks_msec() - t0 < int(m * 1000.0):
			await process_frame
		await _shot("%s_%04d" % [prefix, int(m * 1000.0)])


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
