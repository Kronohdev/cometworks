extends SceneTree
## Screenshots of the rover workshop (scenes/tycoon/ui/screens/rover_builder.tscn, opens a window):
## for a rover mission on the lunar surface in a career with the rover research done (chassis
## tab, instruments tab with a too-heavy rover, Mars with a drone) and the sandbox (no career).
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_rover_builder.gd -- <out_dir> [en]

var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("en" if "en" in args else "pt")
	var s := TycoonState.new_campaign(2026)
	for t in ["rover_mobility", "guided_descent", "multispectral_imaging", "radio_tracking", "sun_sync_orbits", "high_gain_antenna"]:
		TycoonResearch.complete(s, t)
	var scr := (load("res://scenes/tycoon/ui/screens/rover_builder.tscn") as PackedScene).instantiate()
	get_root().add_child(scr)
	scr.bind(s, null, null)
	var payload := RoverDesign.payload_ids(RoverDesign.make("Tatu", "wheels6", ["solar_wing", "battery", "camera", "spectrometer", "omni"]))
	scr.open_with({"type": "rover", "target": "lunar_surface", "payload": payload})
	await _frames(30)
	_shot("rover_builder_chassis")
	scr.set_tab("instrument")
	scr.toggle_part("drill")
	scr.toggle_part("arm")
	scr.toggle_part("rtg")
	await _frames(20)
	_shot("rover_builder_heavy")
	scr.toggle_part("rtg")
	scr.toggle_part("arm")
	scr.set_tab("power")
	await _frames(20)
	_shot("rover_builder_power")
	scr.queue_free()
	await _frames(4)
	var sand := (load("res://scenes/tycoon/ui/screens/rover_builder.tscn") as PackedScene).instantiate()
	get_root().add_child(sand)
	await _frames(4)
	sand.open_with({"design": RoverDesign.make("Libélula", "wheels6", ["rtg", "camera", "drone", "weather", "hga"]), "body": "mars"})
	sand.set_tab("instrument")
	await _frames(30)
	_shot("rover_builder_mars")
	print("SHOTS DONE")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)
