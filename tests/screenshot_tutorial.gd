extends SceneTree
## Windowed screenshots of Vovô Edmundo's lessons (scenes/tycoon/ui/tutorial/tutorial.tscn):
##   tut_01_welcome      the first campus lesson, his opening line (no highlight)
##   tut_02_comet        the comet clock lit up on the top bar
##   tut_03_crew         the crew screen's lesson, the Hire tab lit up
##   tut_04_payload      the payload planner's lesson, the six gauges lit up
##   tut_05_library      the library screen (Biblioteca do Vovô)
##   tut_06_welcome_en   the welcome lesson in English
##   tut_07_campus_bench Vovô Edmundo sitting on his bench on the campus (first year)
##   tut_08_campus_wave  ...standing up to wave as a lesson starts
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tutorial.gd -- <out_dir>

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
	main.clock.set_speed(1)
	main.race_flow.autosave = false
	var tut := main.tutorial
	await _frames(120)
	tut.start("campus")
	await _wait(2.6)
	await _shot("tut_01_welcome")
	_go_next(tut)
	await _wait(2.6)
	await _shot("tut_02_comet")
	tut.skip()
	main.hud.open_screen("crew")
	await _frames(20)
	tut.start("crew", true)
	_go_next(tut)
	await _wait(2.6)
	await _shot("tut_03_crew")
	tut.skip()
	main.hud.close_screen()
	await _frames(20)
	main.hud.open_screen("payload_planner", {"type": "sounding", "target": "suborbital", "payload": []})
	await _frames(20)
	tut.start("payload", true)
	_go_next(tut)
	await _wait(2.6)
	await _shot("tut_04_payload")
	tut.skip()
	main.hud.close_screen()
	await _frames(20)
	main.hud.open_screen("library")
	await _wait(1.5)
	tut.skip()
	await _frames(10)
	await _shot("tut_05_library")
	main.hud.close_screen()
	await _frames(20)
	# Vovô on his bench by the workshop, then up and waving as a lesson starts
	var bench := main.get_node("Halley") as Node3D
	main.camera.follow(bench)
	await _wait(3.5)
	await _shot("tut_07_campus_bench")
	tut.start("lot", true)
	await _wait(1.0)
	await _shot("tut_08_campus_wave")
	tut.skip()
	main.camera.release()
	await _wait(1.0)
	TranslationServer.set_locale("en")
	tut.start("campus", true)
	await _wait(2.6)
	await _shot("tut_06_welcome_en")
	quit()


## The next step, past the typewriter.
func _go_next(tut: TycoonTutorial) -> void:
	if tut._typing:
		tut.next()
	tut.next()


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
