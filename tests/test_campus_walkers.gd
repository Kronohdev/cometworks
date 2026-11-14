extends SceneTree
## The campus Cometlings never walk into things nor into each other
## (src/tycoon/campus_walker.gd, src/tycoon/campus_nav.gd): a crowd walks a fully built
## campus (scenes/tycoon/campus.tscn, every lot built, a demo campaign state like
## src/menu/menu_campus_shot.gd) for a few simulated minutes per era, and every step
##   - no Cometling's centre is inside a footprint: a building's walls and furniture (its
##     walk mask), a lamp, a dressing prop, a tree, a bush, a rock or a fence,
##   - no two Cometlings are closer than two body radii,
## while they keep reaching their spots. A lot that starts building mid-walk (scaffold) must
## not trap anyone either. Also checks that nothing solid is scattered on the roads or lots.
## Run: godot --headless --path . --script res://tests/test_campus_walkers.gd

const DT := 1.0 / 30.0
const STAFF := 24

var _fails := 0


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() >= 3:
		# one run only: -- <era> <level> <seconds> [lot that starts building]
		await _run(int(args[0]), int(args[1]), float(args[2]), args[3] if args.size() > 3 else "")
		print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
		quit(1 if _fails else 0)
		return
	await _run(1, 1, 75.0, "")
	await _run(3, 3, 150.0, "lab")
	await _run(5, 3, 75.0, "")
	await _scatter_check()
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _staff() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var roles := ["engineer", "pilot", "scientist", "ground"]
	for i in STAFF:
		out.append({"id": "w%d" % i, "name": "Walker %d" % i, "role": roles[i % roles.size()], "variant": i % 9})
	return out


## Walks the crowd for `seconds` in `era` with every lot at `level`; when `build_lot` is set,
## that lot starts an upgrade halfway (its scaffold goes up around whoever stands there).
func _run(era: int, level: int, seconds: float, build_lot: String) -> void:
	print("era %d, level %d, %d s%s" % [era, level, int(seconds), (", %s starts building halfway" % build_lot) if build_lot != "" else ""])
	var campus := (load("res://scenes/tycoon/campus.tscn") as PackedScene).instantiate() as Campus
	get_root().add_child(campus)
	await process_frame
	var st := TycoonState.new_campaign(2026, _staff())
	st.weeks = (era - 1) * 5 * st.weeks_per_year() + 10
	for lot: String in st.lot_ids():
		st.buildings[lot] = {"kind": st.lot_kind(lot), "level": level, "target": level, "weeks_left": 0}
	var t0 := Time.get_ticks_usec()
	campus.bind(st)
	print("  bind + walk grid: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var walkers := campus.cometlings()
	_check(walkers.size() == STAFF, "%d Cometlings on the campus" % walkers.size())
	for w in walkers:
		w.set_process(false)
	var radius := float(walkers[0].get("body_radius"))
	var inside := 0
	var inside_first := ""
	var overlap := 0
	var overlap_min := INF
	var steps := int(seconds / DT)
	var path_us := 0
	t0 = Time.get_ticks_usec()
	for s in steps:
		if build_lot != "" and s == steps / 2:
			var b: Dictionary = st.buildings[build_lot]
			b["target"] = mini(level + 1, 3) if level < 3 else 3
			b["weeks_left"] = 3
			if level >= 3:
				b["level"] = 2
			st.changed.emit()
		for w in walkers:
			var t1 := Time.get_ticks_usec()
			w.call("step", DT)
			path_us = maxi(path_us, Time.get_ticks_usec() - t1)
		for i in walkers.size():
			var p := Vector2(walkers[i].position.x, walkers[i].position.z)
			var hit := campus.nav.footprint_at(p)
			if hit != "":
				inside += 1
				if inside_first == "":
					inside_first = "%s at (%.2f, %.2f), step %d" % [hit, p.x, p.y, s]
			for j in range(i + 1, walkers.size()):
				var q := Vector2(walkers[j].position.x, walkers[j].position.z)
				var d := p.distance_to(q)
				overlap_min = minf(overlap_min, d)
				if d < radius * 2.0 - 0.02:
					overlap += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var arrivals := 0
	var walked := 0.0
	var idle := 0
	var give_ups := 0
	var replans := 0
	for w in walkers:
		give_ups += int(w.get("give_ups"))
		replans += int(w.get("replans"))
		arrivals += int(w.get("arrivals"))
		walked += float(w.get("walked"))
		if int(w.get("arrivals")) == 0:
			idle += 1
	print("  %d steps in %.0f ms (slowest walker step %.1f ms); %d arrivals, %.0f m walked, closest pair %.2f m, %d replans, %d given up" % [
		steps, ms, path_us / 1000.0, arrivals, walked, overlap_min, replans, give_ups])
	var ns: Dictionary = campus.nav.stats
	print("  path searches: %d, average %.1f ms, longest %.1f ms, %d found nothing" % [ns["searches"],
		ns["us"] / 1000.0 / maxf(1.0, ns["searches"]), ns["max_us"] / 1000.0, ns["failed"]])
	t0 = Time.get_ticks_usec()
	campus.build_nav()
	print("  walk grid rebuild: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_check(inside == 0, "no Cometling inside a footprint (%d step hits%s)" % [inside, ("; first: " + inside_first) if inside_first != "" else ""])
	_check(overlap == 0, "no two Cometlings closer than %.2f m (%d pair-steps)" % [radius * 2.0, overlap])
	_check(arrivals >= walkers.size(), "they keep reaching spots (%d arrivals)" % arrivals)
	_check(idle <= walkers.size() / 4, "most of them got somewhere (%d never arrived)" % idle)
	campus.queue_free()
	await process_frame


## Trees, bushes, rocks and flowers are not scattered on the roads, the plaza or the lots.
func _scatter_check() -> void:
	var campus := (load("res://scenes/tycoon/campus.tscn") as PackedScene).instantiate() as Campus
	get_root().add_child(campus)
	await process_frame
	var keep_off: Array[Rect2] = []
	for lot in campus.get_node("Lots").get_children():
		var sz: Vector2 = lot.get_meta("size", Vector2.ZERO)
		var c := (lot as Node3D).position
		keep_off.append(Rect2(c.x - sz.x * 0.5, c.z - sz.y * 0.5, sz.x, sz.y))
	for r in campus.get_node("Roads").get_children():
		if r is MeshInstance3D:
			var a := (r as MeshInstance3D).get_aabb()
			var xf := (r as Node3D).transform
			var p0 := xf * a.position
			var p1 := xf * a.end
			keep_off.append(Rect2(Vector2(minf(p0.x, p1.x), minf(p0.z, p1.z)), (Vector2(p1.x - p0.x, p1.z - p0.z)).abs()))
	var bad := 0
	var first := ""
	for sc in campus.get_node("Nature").find_children("*", "MultiMeshInstance3D", true, false):
		if not sc is CampusScatter:
			continue
		var xf := (sc as Node3D).global_transform
		for t in (sc as CampusScatter).placed():
			var p := xf * t.origin
			for r in keep_off:
				if r.has_point(Vector2(p.x, p.z)):
					bad += 1
					if first == "":
						first = "%s at (%.1f, %.1f)" % [sc.name, p.x, p.z]
					break
	_check(bad == 0, "nothing scattered on the roads or lots (%d%s)" % [bad, (", first " + first) if first != "" else ""])
	campus.queue_free()
	await process_frame
