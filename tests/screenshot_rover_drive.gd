extends SceneTree
## Screenshots of the rover drive (scenes/surface/rover_drive.tscn, opens a window): the sandbox
## session on the Moon and on Mars, the rover driven forward a little, a tool used so a toast and
## the radio delay show, the pause card, and a hopper in the air on the Moon.
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_rover_drive.gd -- <out_dir> [moon,mars,...] [en]

var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bodies := ["moon", "mars"]
	if args.size() > 1 and args[1] != "":
		bodies.assign(args[1].split(","))
	TranslationServer.set_locale("en" if "en" in args else "pt")
	for b in bodies:
		await _drive(StringName(b))
	await _hopper()
	print("SHOTS DONE")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _open(body: StringName, design := {}) -> RoverDrive:
	SurfaceSession.current = null
	if not design.is_empty():
		SurfaceSession.start(body, design, RoverMissions.sandbox_objectives(body), {"sandbox": true})
	var ps := load("res://scenes/surface/rover_drive.tscn") as PackedScene
	var d := ps.instantiate() as RoverDrive
	d.default_body = body
	get_root().add_child(d)
	await _frames(3)
	await _wait_idle(d)
	return d


func _wait_idle(d: RoverDrive, max_s := 25.0) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < max_s:
		await process_frame
		if Time.get_ticks_msec() - t0 > 800 and d.planet.terrain.is_idle():
			break
	await _frames(10)


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


func _drive(body: StringName) -> void:
	var d := await _open(body)
	await _shot("rover_%s_start" % body)
	d.rover.player_input = false
	d.rover.throttle = 1.0
	d.rover.steer = 0.25
	for i in 150:
		await process_frame
	d.rover.throttle = 0.0
	d.rover.steer = 0.0
	for i in 40:
		await process_frame
	d.hud.use_tool("photo")
	await _frames(6)
	await _wait_idle(d, 8.0)
	await _shot("rover_%s_drive" % body)
	d.cam.orbit = 2.4
	d.cam.distance = 14.0
	await _frames(40)
	await _shot("rover_%s_side" % body)
	d.hud.set_paused(true)
	await _frames(4)
	await _shot("rover_%s_pause" % body)
	d.hud.set_paused(false)
	d.queue_free()
	SurfaceSession.current = null
	await _frames(4)


func _hopper() -> void:
	var d := await _open(&"moon", RoverDesign.make("Pulga", "hopper", ["solar", "battery", "camera", "omni"]))
	d.rover.player_input = false
	d.rover.throttle = 1.0
	d.hud.use_tool("hop")
	for i in 70:
		await process_frame
	await _shot("rover_moon_hop")
	d.queue_free()
	SurfaceSession.current = null
	await _frames(4)
