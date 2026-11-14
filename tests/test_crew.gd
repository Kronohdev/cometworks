extends SceneTree
## Headless tests for the crew system and the Cometling rig:
##   - roster persistence (save -> load round trip, assignments included)
##   - assignment rules: seats per part, one member per seat, one seat per member,
##     never more crew than seats, replace/move semantics
##   - members are unseated when their part leaves the vessel (detach, clear)
##   - mission modifiers, name generator, NpcEvents bus
##   - Cometling smoke test: every action and reaction runs with finite transforms
## Run: godot --headless --path . --script res://tests/test_crew.gd

const TEST_PATH := "user://crew_roster_test.json"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	_test_persistence()
	await _test_assignment()
	await _test_prune()
	_test_misc()
	await _test_events()
	await _test_creature()
	print("RESULT: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL (%d)" % _failures, _checks])
	quit(1 if _failures else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  FAIL: ", what)


func _roster() -> CrewRoster:
	var r := CrewRoster.new()
	r.autosave = false
	r.save_path = TEST_PATH
	r.seed_default(6, 7)
	return r


func _vessel_with(ids: Array) -> Vessel:
	## Vessel whose root is ids[0]; every next part is stacked on the previous one's top.
	var v := Vessel.new()
	get_root().add_child(v)
	var prev: PartInstance = null
	for id in ids:
		var p := PartInstance.create(String(id))
		if prev == null:
			v.set_root(p)
		else:
			v.attach(prev, p, Vessel.local_for_node(prev, "top", p, "bottom"), "top", "bottom")
		prev = p
	return v


# ------------------------------------------------------------------ persistence
func _test_persistence() -> void:
	print("persistence")
	var r := _roster()
	_ok(r.members.size() == 6, "seed_default makes 6 members")
	var roles := {}
	for m in r.members:
		roles[m.role] = int(roles.get(m.role, 0)) + 1
	_ok(roles.get("pilot", 0) == 2 and roles.get("engineer", 0) == 2 and roles.get("scientist", 0) == 2, "two of each role")
	r.members[0].experience = 135.0
	r.members[0].missions = 2
	r.members[1].assigned_part = "tank/crew_capsule"
	r.members[1].assigned_seat = 2
	r.members[1].status = "assigned"
	r.rename(r.members[2], "Zuzu Starbean")
	_ok(r.save(TEST_PATH), "save")
	var r2 := CrewRoster.new()
	r2.autosave = false
	_ok(r2.load_from(TEST_PATH), "load")
	_ok(r2.members.size() == r.members.size(), "same member count after load")
	var same := true
	for i in r.members.size():
		var a := r.members[i].to_dict()
		var b := r2.members[i].to_dict()
		if JSON.stringify(a) != JSON.stringify(b):
			same = false
			print("    differs: ", a, " vs ", b)
	_ok(same, "every member identical after the round trip")
	_ok(r2.members[0].level() == 1 and is_equal_approx(r2.members[0].level_progress(), 0.35), "level from XP")
	_ok(r2.members[1].is_assigned() and r2.members[1].assigned_seat == 2, "assignment persisted")
	_ok(r2.find_by_name("Zuzu Starbean") != null, "rename persisted")
	var m := r2.hire("scientist")
	_ok(m.id != "" and r2.find(m.id) == m and m.role == "scientist", "hire with role")
	_ok(r2.find(m.id).id != r2.members[0].id, "unique ids")
	_ok(not r2.load_from("user://does_not_exist.json"), "missing file -> false")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


# ------------------------------------------------------------------ assignment rules
func _test_assignment() -> void:
	print("assignment rules")
	var r := _roster()
	var v := _vessel_with(["crew_capsule"])
	await process_frame
	var cap: PartInstance = v.root
	var seats := CrewRoster.seats_for_vessel(v, r)
	var expected_seats := int(cap.data.get("crew_seats", 3))
	_ok(seats.size() == expected_seats, "capsule has %d seats (got %d)" % [expected_seats, seats.size()])
	var a := r.members[0]
	var b := r.members[1]
	var c := r.members[2]
	var d := r.members[3]
	_ok(r.assign(a, cap, 0), "assign a -> seat 0")
	_ok(a.is_assigned() and a.status == "assigned", "a is assigned")
	_ok(not r.assign(b, cap, 0), "seat 0 is taken: b refused")
	_ok(not b.is_assigned(), "b still available")
	_ok(not r.assign(b, cap, expected_seats), "seat index out of range refused")
	_ok(not r.assign(b, cap, -1), "negative seat refused")
	_ok(r.assign(b, cap, 1), "assign b -> seat 1")
	_ok(r.assign(b, cap, 2), "b moves to seat 2")
	_ok(r.member_at(CrewRoster.part_path(v, cap), 1) == null, "seat 1 freed after the move")
	_ok(r.assign(c, cap, 1), "assign c -> seat 1")
	# capsule full: nobody else fits
	_ok(not r.assign_auto(d, v), "assign_auto refuses when every seat is taken")
	_ok(r.crew_of(v).size() == expected_seats, "never more crew than seats")
	# replace: d takes seat 0, a is unseated
	_ok(r.assign(d, cap, 0, true), "replace seat 0 with d")
	_ok(not a.is_assigned(), "a unseated by the replace")
	var occupied := {}
	var unique := true
	for s in CrewRoster.seats_for_vessel(v, r):
		if s["member"] != null:
			if occupied.has(s["member"]):
				unique = false
			occupied[s["member"]] = true
	_ok(unique, "each member sits in only one seat")
	r.unassign(c)
	_ok(not c.is_assigned() and r.member_at(CrewRoster.part_path(v, cap), 1) == null, "unassign frees the seat")
	_ok(r.assign_auto(a, v), "assign_auto finds the free seat")
	var mods := r.mission_modifiers(v)
	_ok(int(mods["crew_count"]) == 3 and int(mods["seats"]) == expected_seats, "modifiers report crew and seats")
	_ok(float(mods["attitude_control"]) >= 1.0 and float(mods["reliability"]) >= 1.0 and float(mods["science_return"]) >= 1.0,
		"modifiers are >= 1")
	# a part without seats and a part outside any vessel
	var tank := PartInstance.create("tank_kerolox_s2") if not PartDB.get_part("tank_kerolox_s2").is_empty() else PartInstance.create(PartDB.part_order[0])
	_ok(CrewRoster.crew_seats(tank) == 0 or PartDB.is_command(tank.data), "non-crewed part has no seats")
	_ok(not r.assign(b, tank, 0), "cannot seat into a part outside the vessel")
	tank.free()
	_ok(CrewRoster.crew_seats({"id": "future_lander", "crew_seats": 2}) == 2, "crew_seats field is honoured")
	_ok(CrewRoster.crew_seats({"id": "crew_capsule"}) == 3, "fallback: crew_capsule has 3 seats")
	v.queue_free()
	await process_frame


# ------------------------------------------------------------------ unassign on removal
func _test_prune() -> void:
	print("unassign on part removal")
	var r := _roster()
	var base := _first_part_with_top()
	var v := _vessel_with([base, "crew_capsule"])
	await process_frame
	var cap: PartInstance = null
	for p in v.all_parts():
		if p.part_id == "crew_capsule":
			cap = p
	_ok(cap != null and cap != v.root, "capsule stacked on %s" % base)
	_ok(r.assign(r.members[0], cap, 0) and r.assign(r.members[1], cap, 1), "two seated")
	r.bind_vessel(v)
	var held := v.detach(cap)
	await process_frame     # bind_vessel prunes deferred
	await process_frame
	_ok(not r.members[0].is_assigned() and not r.members[1].is_assigned(), "detaching the capsule unseats its crew")
	held.free()
	# re-attach a capsule, seat, then clear the vessel
	var cap2 := PartInstance.create("crew_capsule")
	v.attach(v.root, cap2, Vessel.local_for_node(v.root, "top", cap2, "bottom"), "top", "bottom")
	_ok(r.assign(r.members[2], cap2, 2), "seat in the new capsule")
	_ok(r.prune(v) == 0, "prune keeps valid seats")
	v.clear()
	_ok(r.prune(v) == 1 and not r.members[2].is_assigned(), "clearing the vessel unseats everyone")
	v.queue_free()
	await process_frame


func _first_part_with_top() -> String:
	for id in PartDB.part_order:
		var p := PartDB.get_part(id)
		if p.get("category", "") == "tank" and p.get("size", "") == "M":
			return id
	return PartDB.part_order[0]


# ------------------------------------------------------------------ misc
func _test_misc() -> void:
	print("names and looks")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var names := {}
	for i in 200:
		var n := CrewRoster.generate_name(rng)
		if i < 5:
			_ok(n.length() >= 5 and n.contains(" "), "name '%s' has a first and last part" % n)
		names[n] = true
	_ok(names.size() > 150, "names are varied (%d unique of 200)" % names.size())
	var r := _roster()
	var variants := {}
	for m in r.members:
		variants[m.variant] = true
	_ok(variants.size() == r.members.size(), "default roster wears distinct colours")
	_ok(CometlingLooks.count() >= 8, "at least 8 colour variants")


func _test_events() -> void:
	print("event bus")
	var got: Array = []
	var cb := func(e: String, data: Dictionary) -> void: got.append([e, data])
	NpcEvents.bus().event.connect(cb)
	NpcEvents.emit("part_placed", {"stagger": 0.0})
	NpcEvents.emit("launch")
	_ok(got.size() == 2 and got[0][0] == "part_placed" and got[1][0] == "launch", "NpcEvents delivers events")
	NpcEvents.bus().event.disconnect(cb)
	await process_frame


# ------------------------------------------------------------------ the creature
func _finite_tree(n: Node) -> bool:
	if n is Node3D:
		var t := (n as Node3D).transform
		if not (t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite()):
			print("    non-finite: ", n.get_path())
			return false
	for c in n.get_children():
		if not _finite_tree(c):
			return false
	return true


func _test_creature() -> void:
	print("cometling rig")
	var c := (load("res://scenes/npc/creature.tscn") as PackedScene).instantiate() as Cometling
	c.listen_to_events = false
	get_root().add_child(c)
	await process_frame
	for role in Cometling.ROLES:
		c.role = role
		var hat := {"pilot": "Helmet", "engineer": "HardHat", "scientist": "Goggles", "ground": "Vest"}[role] as String
		_ok((c.find_child(hat, true, false) as Node3D).visible, "%s wears %s" % [role, hat])
	c.paused = true
	var all_ok := true
	for a in Cometling.LOOP_ACTIONS + Cometling.ONESHOTS.keys():
		c.play(a)
		c.set_move_velocity(Vector3(0, 0, 1.0) if a in ["carry", "idle"] else Vector3.ZERO)
		for i in 90:
			c.advance(1.0 / 60.0)
		# long frames (distance LOD) must stay stable too
		for i in 10:
			c.advance(0.1)
		if not _finite_tree(c):
			all_ok = false
			print("    action %s produced NaN" % a)
	_ok(all_ok, "every action keeps finite transforms")
	for e in ["part_placed", "part_removed", "vessel_cleared", "launch", "hello", "staged", "whatever"]:
		c.react(e)
		for i in 40:
			c.advance(1.0 / 60.0)
	_ok(_finite_tree(c), "reactions keep finite transforms")
	c.play("cheer")
	c.advance(0.5)
	_ok(c.current_action() == "cheer", "one-shot is current")
	for i in 200:
		c.advance(1.0 / 60.0)
	_ok(c.current_action() != "cheer", "one-shot ends")
	c.queue_free()
	await process_frame
