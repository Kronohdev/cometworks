extends SceneTree
## The research tree (TechTreeLayout + the research screen's tree page):
##   layout   every tech placed, no two cards overlap, era 1 at the roots and each era above the
##            last, every prerequisite has an edge, techs with none grow from the trunk; the
##            same with extra techs in any era / an unknown branch / a pinned tech (other work
##            adds techs to research.json)
##   screen   one card per tech, one branch line per prerequisite (and one per root), the cards
##            where the layout put them, hover lights the path of prerequisites, a click selects
##            and the inspector shows the tech, Fund funds it, zoom / pan stay in bounds and the
##            fitted tree is whole in the view, a finished tech grows its branches
## Run: godot --headless --path . --script res://tests/test_research_tree.gd

var _fails := 0
var _checks := 0


func _initialize() -> void:
	CwMotion.set_reduced(true)
	_layout_real()
	_layout_extra()
	await _screen()
	print("%d checks" % _checks)
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _frames(k: int) -> void:
	for i in k:
		await process_frame


# ------------------------------------------------------------ layout
func _layout_checks(techs: Array, o: Dictionary, tag: String) -> Dictionary:
	var lay := TechTreeLayout.compute(techs, o)
	var rects: Dictionary = lay["rects"]
	var missing: Array = []
	for t: Dictionary in techs:
		if not rects.has(String(t["id"])):
			missing.append(t["id"])
	_check(missing.is_empty(), "%s: every tech placed (%d of %d) %s" % [tag, rects.size(), techs.size(), missing])
	var overlaps: Array = []
	var ids := rects.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if (rects[ids[i]] as Rect2).grow(-1.0).intersects((rects[ids[j]] as Rect2).grow(-1.0)):
				overlaps.append("%s/%s" % [ids[i], ids[j]])
	_check(overlaps.is_empty(), "%s: no overlapping cards %s" % [tag, overlaps])
	var size: Vector2 = lay["size"]
	var inside := true
	for id in ids:
		inside = inside and Rect2(Vector2.ZERO, size).encloses(rects[id])
	_check(inside, "%s: every card inside the tree (%s)" % [tag, size])
	# eras: roots at the bottom, each era above the one before
	var by_id := {}
	for t: Dictionary in techs:
		by_id[String(t["id"])] = t
	var order := true
	for t: Dictionary in techs:
		if t.has("tree_pos"):
			continue
		for p in t.get("prereq", []):
			if int(by_id[String(p)]["era"]) < int(t["era"]):
				order = order and (rects[String(p)] as Rect2).position.y > (rects[String(t["id"])] as Rect2).position.y
	_check(order, "%s: a later era grows above its prerequisites" % tag)
	var n_pre := 0
	var roots := 0
	for t: Dictionary in techs:
		n_pre += (t.get("prereq", []) as Array).size()
		roots += 1 if (t.get("prereq", []) as Array).is_empty() else 0
	_check((lay["edges"] as Array).size() == n_pre, "%s: one edge per prerequisite (%d / %d)" % [tag, (lay["edges"] as Array).size(), n_pre])
	_check((lay["roots"] as Array).size() == roots, "%s: techs with no prerequisite grow from the trunk (%d)" % [tag, roots])
	return lay


func _layout_real() -> void:
	print("layout (research.json)")
	var techs := TycoonResearch.techs()
	var o := TechTreeLayout.opts_from(TycoonResearch.db())
	var lay := _layout_checks(techs, o, "data")
	var size: Vector2 = lay["size"]
	print("    tree %.0f x %.0f px" % [size.x, size.y])
	_check(size.x <= 1200.0 and size.y <= 760.0, "data: the whole tree fits a docked screen near 1:1 (%s)" % size)
	# every branch has a limb and an icon that exists
	var icons: Dictionary = o.get("icons", {})
	var bad: Array = []
	for b: String in TycoonResearch.db().get("branches", {}):
		if not ResourceLoader.exists("res://ui/cometworks/icons/%s.svg" % String(icons.get(b, "research"))):
			bad.append(b)
	_check(bad.is_empty(), "every branch has a card icon %s" % str(bad))
	# spread(): least squares under the gap
	var xs := TechTreeLayout.spread([1.0, 1.0, 1.0, 4.0], 1.0)
	_check(xs.size() == 4 and is_equal_approx(xs[0], 0.0) and is_equal_approx(xs[2], 2.0) and is_equal_approx(xs[3], 4.0),
		"spread keeps one lane between neighbours around their wish (%s)" % str(xs))


func _layout_extra() -> void:
	print("layout (extra techs)")
	var techs: Array = TycoonResearch.techs().duplicate(true)
	techs.append({"id": "rover_a", "era": 3, "branch": "struct", "cost": 300, "weeks": 6, "prereq": ["rover_mobility"]})
	techs.append({"id": "rover_b", "era": 3, "branch": "struct", "cost": 300, "weeks": 6, "prereq": []})
	techs.append({"id": "rover_c", "era": 4, "branch": "mobility", "cost": 300, "weeks": 6, "prereq": ["rover_a", "rover_b"]})
	techs.append({"id": "rover_d", "era": 4, "branch": "struct", "cost": 300, "weeks": 6, "prereq": ["rover_c"]})
	techs.append({"id": "rover_e", "era": 2, "branch": "struct", "cost": 300, "weeks": 6, "prereq": ["small_sat_bus"]})
	techs.append({"id": "pinned", "era": 5, "branch": "ops", "cost": 300, "weeks": 6, "prereq": ["lab_complex"], "tree_pos": [7.0, 4.0]})
	_layout_checks(techs, TechTreeLayout.opts_from(TycoonResearch.db()), "extra")
	_layout_checks(techs, TechTreeLayout.DEFAULTS, "no tree section")


# ------------------------------------------------------------ screen
func _screen() -> void:
	print("screen")
	var s := TycoonState.new_campaign(7, [{"name": "R", "profession": "researcher", "skill": 0.7}])
	var clock := TycoonClock.new(s.rules)
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	var ps := load("res://scenes/tycoon/ui/screens/research.tscn") as PackedScene
	var scr := ps.instantiate() as Control
	get_root().size = Vector2i(1600, 900)
	get_root().add_child(scr)
	await process_frame
	scr.call("bind", s, clock, null)
	await _frames(4)
	_check(scr.get_script().resource_path.ends_with("research_screen.gd"), "the research screen script is loaded")
	var techs := TycoonResearch.techs()
	var cards: Dictionary = scr.get("cards")
	_check(cards.size() == techs.size(), "one card per tech (%d / %d)" % [cards.size(), techs.size()])
	var shown := 0
	for id: String in cards:
		shown += 1 if (cards[id] as Control).visible and (cards[id] as Control).has_meta("from_template") else 0
	_check(shown == techs.size(), "the cards are visible copies of the template (%d)" % shown)
	var lay: Dictionary = scr.get("layout")
	var placed := true
	for id: String in cards:
		placed = placed and (cards[id] as Control).position.is_equal_approx((lay["rects"][id] as Rect2).position)
	_check(placed, "every card sits where the layout put it")
	var edges: Dictionary = scr.get("edges")
	var missing: Array = []
	for t: Dictionary in techs:
		for p in t.get("prereq", []):
			var k := "%s>%s" % [p, t["id"]]
			if not edges.has(k) or not is_instance_valid(edges[k]) or ((edges[k] as Node2D).get_node("Fill") as Line2D).points.size() < 2:
				missing.append(k)
	_check(missing.is_empty(), "every prerequisite has its branch drawn %s" % [missing])
	var roots := 0
	for k: String in edges:
		roots += 1 if k.begins_with(">") else 0
	_check(roots == (lay["roots"] as Array).size(), "every root tech grows from the trunk (%d)" % roots)
	# states
	_check(String((edges["orbital_rocketry>upper_stage"] as Node).get_meta("state", "")) == "open",
		"a branch out of a finished tech is open")
	_check(String((edges["upper_stage>lunar_stage"] as Node).get_meta("state", "")) == "locked", "a far branch is locked")
	# hover: the path of prerequisites lights up
	scr.call("hover_tech", "guided_descent")
	var path: Dictionary = scr.get("hover_path")
	_check(path.has("upper_stage") and path.has("orbital_rocketry") and path.has("small_sat_bus") and not path.has("radio_tracking"),
		"hover lights the whole path of prerequisites (%s)" % str(path.keys()))
	_check((edges["orbital_rocketry>upper_stage"] as CanvasItem).modulate.a > 0.9
		and (edges["radio_tracking>high_gain_antenna"] as CanvasItem).modulate.a < 0.6
		and ((cards["radio_tracking"] as Control).get_node("Veil") as Control).visible
		and not ((cards["upper_stage"] as Control).get_node("Veil") as Control).visible, "...and veils the other branches and cards")
	scr.call("hover_tech", "")
	_check((edges["radio_tracking>high_gain_antenna"] as CanvasItem).modulate.a > 0.9, "leaving the card brings them back")
	# click: select, the inspector shows it, Fund funds it
	scr.call("select", "radio_tracking")
	await _frames(2)
	_check(String(scr.get_node("%IName").text) == tr("TY_TECH_RADIO_TRACKING"), "the inspector shows the selected tech")
	_check(String(scr.get_node("%ICost").text).contains("70"), "...with its cost in PP")
	(scr.get_node("%IFund") as Button).pressed.emit()
	_check(TycoonResearch.active(s) == "radio_tracking", "the inspector's button funds the tech")
	await _frames(2)
	_check(((cards["radio_tracking"] as Control).get_node("Card/HBox/Badge/Progress") as Control).visible, "the tech being researched shows its progress ring")
	# zoom and pan
	var world := scr.get_node("%World") as Control
	var canvas := scr.get_node("%Canvas") as Control
	scr.call("fit_view")
	var fit := world.scale.x
	var wr := Rect2(world.position, (lay["size"] as Vector2) * world.scale)
	_check(Rect2(Vector2.ZERO, canvas.size).grow(1.0).encloses(wr), "the fitted tree is whole in the view (%s in %s)" % [wr, canvas.size])
	_check(fit >= 0.8, "the fitted tree is readable at 1600x900 (scale %.2f)" % fit)
	scr.call("zoom_at", canvas.size * 0.5, 10.0)
	_check(world.scale.x <= float(scr.get("max_zoom")) + 0.001, "zoom in stops at the limit (%.2f)" % world.scale.x)
	scr.call("pan_by", Vector2(5000, 5000))
	var r2 := Rect2(world.position, (lay["size"] as Vector2) * world.scale)
	_check(r2.intersects(Rect2(Vector2.ZERO, canvas.size)), "panning never loses the tree")
	scr.call("zoom_at", canvas.size * 0.5, 0.01)
	_check(world.scale.x >= float(scr.get("min_zoom")) - 0.001, "zoom out stops at the limit (%.2f)" % world.scale.x)
	# a finished tech grows its branches (state change animates)
	TycoonResearch.complete(s, "radio_tracking")
	s.changed.emit()
	await _frames(2)
	_check(String((edges[">radio_tracking"] as Node).get_meta("state", "")) == "done", "a finished root's branch lights up")
	_check(String((edges["radio_tracking>high_gain_antenna"] as Node).get_meta("state", "")) == "open", "...and the next branch opens")
	# with motion on, a tech that finishes grows its branches from the prerequisite up
	CwMotion.set_reduced(false)
	TycoonResearch.fund(s, "high_gain_antenna")
	s.changed.emit()
	await _frames(2)
	TycoonResearch.complete(s, "high_gain_antenna")
	s.changed.emit()
	var e: Node2D = edges["radio_tracking>high_gain_antenna"]
	var full := (scr.get("_curves")["radio_tracking>high_gain_antenna"] as PackedVector2Array).size()
	await _frames(3)
	var part := (e.get_node("Fill") as Line2D).points.size()
	_check(part >= 2 and part < full, "a finished tech's branch grows (%d of %d points a few frames in)" % [part, full])
	_check(((cards["high_gain_antenna"] as Control).get_node("Anim") as AnimationPlayer).current_animation == "pop",
		"...and its card pops")
	await create_timer(1.0).timeout
	_check((e.get_node("Fill") as Line2D).points.size() == full, "...until it reaches the card")
	CwMotion.set_reduced(true)
	scr.queue_free()
	await _frames(2)
