extends SceneTree
## Screenshots of the rover on the voxel terrain (scenes/surface/rover_drive.tscn, opens a window):
##   rover_step_*    the rover driven onto a 1-block step (the half-block step slabs), seen from the side
##   rover_wall_*    the rover driven at full speed into a wall 2+ blocks tall (it stops at the face)
##   rover_hud_*     the HUD with the mini-map (the arrow points where the rover drives) and a
##                   running "Desafio" card stacked under it
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_rover_terrain.gd -- <out_dir> [tag] [moon]

var out_dir := "user://"
var tag := "after"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		tag = args[1]
	var body := StringName(args[2]) if args.size() > 2 else &"moon"
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("pt")
	var d := await _open(body)
	d.rover.player_input = false
	await _hud(d)
	await _step(d)
	await _wall(d)
	print("SHOTS DONE")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _open(body: StringName) -> RoverDrive:
	SurfaceSession.current = null
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
	var path := out_dir.path_join("%s_%s.png" % [name, tag])
	img.save_png(path)
	print("saved ", path)


func _h(d: RoverDrive, x: int, z: int) -> float:
	return d.planet.terrain.get_height(x + 0.5, z + 0.5)


## A cell (x, z) and a direction (+x, +z, -x, -z) where 5 flat cells lead to a rise of `rise`
## blocks (rise >= 2: at least that), nearest the spawn.
func _find(d: RoverDrive, rise: int) -> Array:
	var o := d.spawn_point()
	var best: Array = []
	var best_d := INF
	for r in range(4, 70):
		for zz in range(-r, r + 1):
			for xx in [-r, r]:
				for pair in [[xx, zz], [zz, xx]]:
					var x := floori(o.x) + int(pair[0])
					var z := floori(o.z) + int(pair[1])
					for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var h0 := _h(d, x, z)
						var ok := true
						for k in range(1, 6):
							var c: Vector2i = Vector2i(x, z) - dir * k
							for side in [-1, 0, 1]:
								var cs: Vector2i = c + Vector2i(dir.y, dir.x) * int(side)
								if absf(_h(d, cs.x, cs.y) - h0) > 0.01:
									ok = false
						var top := _h(d, x + dir.x, z + dir.y)
						var dh := roundi(top - h0)
						if ok and (dh == rise if rise == 1 else dh >= rise):
							var dist := Vector2(x - o.x, z - o.z).length()
							if dist < best_d:
								best_d = dist
								best = [Vector2i(x, z), dir]
		if not best.is_empty():
			return best
	return best


func _drive_at(d: RoverDrive, found: Array, seconds: float, name: String, orbit: float) -> void:
	var cell: Vector2i = found[0]
	var dir: Vector2i = found[1]
	var start := Vector2(cell.x + 0.5, cell.y + 0.5) - Vector2(dir) * 4.5
	# heading: forward = (-sin yaw, -cos yaw)
	var yaw := atan2(-float(dir.x), -float(dir.y))
	d.rover.place(start.x, start.y, yaw)
	d.cam.orbit = orbit
	d.cam.distance = 8.0
	d.cam.snap()
	d.rover.throttle = 1.0
	await _frames(roundi(seconds * 60.0))
	d.rover.throttle = 0.0
	await _frames(20)
	await _shot(name)


func _step(d: RoverDrive) -> void:
	var f := _find(d, 1)
	if f.is_empty():
		print("no 1-block step found")
		return
	print("step at ", f)
	await _drive_at(d, f, 1.2, "rover_step_mid", PI * 0.5)
	await _drive_at(d, f, 3.0, "rover_step_up", PI * 0.42)


func _wall(d: RoverDrive) -> void:
	var f := _find(d, 2)
	if f.is_empty():
		print("no wall found")
		return
	print("wall at ", f)
	await _drive_at(d, f, 4.0, "rover_wall", PI * 0.5)
	print("rover after the wall: ", d.rover.position, " blocked ", d.rover.blocked)


func _hud(d: RoverDrive) -> void:
	# drive a bit with a turn so the arrow is not straight up
	d.rover.throttle = 1.0
	d.rover.steer = 0.6
	await _frames(60)
	d.rover.steer = 0.0
	await _frames(30)
	d.rover.throttle = 0.0
	var ex: SurfaceExplore = null
	for n in d.find_children("*", "SurfaceExplore", true, false):
		ex = n
	if ex:
		for ch in ex.challenges:
			if String(ch["entry"].get("type", "")) == "reach_before":
				ch["phase"] = "running"
				ch["t"] = 12.0
				ex._ch_focus = ch
				break
	await _frames(20)
	await _shot("rover_hud")
