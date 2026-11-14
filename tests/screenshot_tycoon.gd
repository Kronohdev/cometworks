extends SceneTree
## Windowed screenshots of the Cometworks main screen (scenes/tycoon/tycoon_main.tscn):
##   tycoon_01_start      year 1: workshop, HQ, sounding-rocket pad, empty lots
##   tycoon_02_lot        the lot panel of an empty lot
##   tycoon_03_works      several buildings under construction (scaffolds, works strips)
##   tycoon_04_era1 .. tycoon_08_era5   the full campus in each era (levels grow with the eras)
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_tycoon.gd -- <out_dir>

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(10)
	main.clock.set_speed(0)
	await _frames(120)
	await _shot("tycoon_01_start")
	main.hud.show_lot("lab")
	await _frames(10)
	await _shot("tycoon_02_lot")
	main.hud.close_lot()
	var s := main.state
	s.cash = 9.0e6
	for lot in ["lab", "control", "antenna", "factory", "training"]:
		s.build(lot)
	for i in 3:
		s.advance_week()
	await _frames(60)
	await _shot("tycoon_03_works")
	var era_levels := {1: 1, 2: 2, 3: 3, 4: 3, 5: 3}
	for era in range(1, 6):
		s.weeks = (era - 1) * 5 * 52 + 10
		for lot: String in s.lot_ids():
			s.buildings[lot] = {"kind": s.lot_kind(lot), "level": era_levels[era], "target": era_levels[era], "weeks_left": 0}
		s.changed.emit()
		await _frames(90)
		await _shot("tycoon_%02d_era%d" % [3 + era, era])
	print("TYCOON SCREENSHOTS DONE")
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved %s" % path)
