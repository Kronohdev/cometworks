extends SceneTree
## Windowed screenshots of the UI motion (src/tycoon/ui/motion/) caught mid-animation. Time
## runs in slow motion (Engine.time_scale = SLOW) so each frame lands where it is asked:
##   motion_hud_in_<t>          the HUD coming in (strip, rail cascade, race board, bottom)
##   motion_screen_<name>_<k>   a screen opening at 0 / 50 / 100 % (research, project_phase)
##   motion_screen_out_<k>      the research screen leaving
##   motion_hover_<k>           "Novo projeto" hovered (lift, glow, sweep) and a rail icon wiggling
##   motion_tick_<k>            cash and hype counting up with the green flash
##   motion_menu_<t>            the main menu items cascading in
##   motion_menu_glide_<k>      the selection marker gliding to another item
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_ui_motion.gd -- <out_dir> [menu|hud]

const SLOW := 0.2

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	CwMotion.set_reduced(false)
	var only := String(args[1]) if args.size() > 1 else ""
	if only != "menu":
		await _hud()
	if only != "hud":
		await _menu()
	Engine.time_scale = 1.0
	print("UI MOTION SCREENSHOTS DONE")
	quit()


func _hud() -> void:
	Engine.time_scale = SLOW
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	await process_frame
	main.clock.set_speed(0)
	await _at(0.12)
	await _shot("motion_hud_in_012")
	await _at(0.3)
	await _shot("motion_hud_in_030")
	await _at(1.4)
	await _shot("motion_hud_in_done")
	# a screen opening, then leaving
	var hud := main.hud
	hud.open_screen("research")
	await _at(0.0)
	await _shot("motion_screen_research_000")
	await _at(0.13)
	await _shot("motion_screen_research_050")
	await _at(0.8)
	await _shot("motion_screen_research_100")
	hud.close_screen()
	await _at(0.07)
	await _shot("motion_screen_out_050")
	await _at(0.4)
	# a modal with overshoot
	var s := main.state
	hud.open_screen("crew")
	await _at(0.15)
	await _shot("motion_screen_crew_050")
	await _at(0.8)
	await _shot("motion_screen_crew_100")
	hud.close_screen()
	await _at(0.5)
	# hover: the primary call to action and a rail icon
	var np := hud.get_node("%NewProject") as Button
	np.mouse_entered.emit()
	await _at(0.06)
	await _shot("motion_hover_cta_050")
	await _at(0.3)
	await _shot("motion_hover_cta_100")
	np.mouse_exited.emit()
	var rail := hud.get_node("Rail/VBox/Research") as Button
	rail.mouse_entered.emit()
	await _at(0.1)
	await _shot("motion_hover_rail_wiggle")
	rail.mouse_exited.emit()
	await _at(0.5)
	# numbers: cash and hype go up
	s.cash += 1.5e6
	s.hype += 12.0
	s.changed.emit()
	await _at(0.12)
	await _shot("motion_tick_020")
	await _at(0.3)
	await _shot("motion_tick_060")
	await _at(1.0)
	await _shot("motion_tick_done")
	main.queue_free()
	main = null
	Engine.time_scale = 1.0
	await _frames(5)


func _menu() -> void:
	Engine.time_scale = SLOW
	var menu := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	current_scene = menu
	await process_frame
	await _at(0.5)
	await _shot("motion_menu_050")
	await _at(0.14)
	await _shot("motion_menu_064")
	await _at(1.4)
	await _shot("motion_menu_done")
	(menu.get_node("%Fair") as Button).grab_focus()
	await _at(0.3)
	(menu.get_node("%Options") as Button).grab_focus()
	await _at(0.08)
	await _shot("motion_menu_glide_040")
	await _at(0.4)
	await _shot("motion_menu_glide_100")
	Engine.time_scale = 1.0
	# a real mouse over "Modo feira": hover slide, marker, and its tooltip fading in
	var fair := menu.get_node("%Fair") as Control
	var mm := InputEventMouseMotion.new()
	mm.position = fair.get_global_rect().get_center()
	mm.global_position = mm.position
	get_root().push_input(mm)
	await create_timer(0.9).timeout
	await _shot("motion_menu_tooltip")
	var faded := false
	for n in get_root().find_children("*", "PopupPanel", true, false):
		for c in n.get_children(true):
			faded = faded or c.has_meta(CwMotion.META)
	print("tooltip faded in by CwTooltipFade: %s" % faded)
	# the options panel with the motion row
	(menu as MainMenu).open_options()
	await create_timer(0.6).timeout
	await _shot("motion_menu_options")
	menu.queue_free()
	await _frames(5)


## Waits `t` seconds of animation time.
func _at(t: float) -> void:
	if t <= 0.0:
		await process_frame
		return
	await create_timer(t / Engine.time_scale, true, false, true).timeout


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved %s" % path)
