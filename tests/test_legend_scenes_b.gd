extends SceneTree
## The mentor and rival-leader Lendas as their own Cometlings (scenes/npc/legends/<id>.tscn):
##   - data/tycoon/legends.json points each of them at its scene
##   - every scene loads, is a LegendCometling with its legend_id, and has its outfit parts
##   - the outfit keeps its own toon materials and is not tinted like skin (only the Cometling's
##     own meshes take the per-instance tints), the head still wears the skin, no profession gear
##   - every habit listed in the scene plays, runs to the end and leaves the Lenda idle again;
##     the held props stay with the paw; talk(on) works for the portraits
##   - a few signature behaviours: Keplerino's planet runs faster near the Sun, Cifrinha's coin
##     replaces the bulb, Herschelinha raises the telescope to her eye, Sali's ball leaves her paw
## Run: godot --headless --path . --script res://tests/test_legend_scenes_b.gd

const PARTS := {
	"dora": ["Rig/Hips/Neck/Hair", "Rig/Hips/Neck/HairPencil", "Rig/Hips/Cardigan", "Rig/Hips/Pearls",
		"Rig/Hips/ArmL/Sleeve", "Rig/Hips/ArmL/HandL/Manual", "Rig/Hips/ArmL/HandL/Manual/Front",
		"Rig/Hips/ArmR/HandR/PunchCard"],
	"berta": ["Rig/Hips/Neck/Hair", "Rig/Hips/Neck/Flower", "Rig/Hips/Suit", "Rig/Hips/Bow", "Rig/Hips/Frog",
		"Rig/Hips/ArmL/HandL/Notebook", "Rig/Hips/ArmR/HandR/Pencil"],
	"keplerino": ["Rig/Hips/Neck/Hair", "Rig/Hips/Neck/Beard", "Rig/Hips/Ruff", "Rig/Hips/Doublet",
		"Rig/Hips/ArmL/HandL/OrbitModel", "Rig/Hips/ArmL/HandL/OrbitModel/Sun", "Rig/Hips/ArmL/HandL/OrbitModel/Planet"],
	"dulinha": ["Rig/Hips/Neck/Hair", "Rig/Hips/Blazer", "Rig/Hips/StarScarf", "Rig/Hips/ArmL/HandL/Tablet",
		"Rig/Hips/ArmL/HandL/Tablet/Screen"],
	"sagao": ["Rig/Hips/Neck/Hair", "Rig/Hips/Neck/BrowL", "Rig/Hips/Neck/BrowR", "Rig/Hips/Turtleneck",
		"Rig/Hips/Jacket", "Rig/Hips/ArmL/HandL/Record", "Rig/Hips/ArmR/HandR/PaleBlueDot"],
	"sali": ["Rig/Hips/Neck/Hair", "Rig/Hips/Neck/Headset", "Rig/Hips/FlightSuit", "Rig/Hips/FlightSuit/Patch",
		"Rig/Hips/ArmL/HandL/Ball"],
	"gagarinho": ["Rig/Hips/Neck/SpaceHelmet", "Rig/Hips/NeckSeal", "Rig/Hips/PressureSuit", "Rig/Hips/ArmL/Sleeve"],
	"cifrinha": ["Rig/Hips/Neck/Hair", "Rig/Hips/Neck/Antenna/Bulb/Coin", "Rig/Hips/Blazer",
		"Rig/Hips/ArmL/HandL/Calculator", "Rig/Hips/ArmR/HandR/FlipCoin"],
	"herschelinha": ["Rig/Hips/Neck/Bonnet", "Rig/Hips/Neck/Curls", "Rig/Hips/Dress",
		"Rig/Hips/ArmL/HandL/Telescope", "Rig/Hips/ArmR/HandR/Notebook"],
}
## held prop of each Lenda (it follows the paw)
const HELD := {
	"dora": ["Rig/Hips/ArmL/HandL/Manual", "Rig/Hips/ArmL/HandL"],
	"berta": ["Rig/Hips/ArmL/HandL/Notebook", "Rig/Hips/ArmL/HandL"],
	"keplerino": ["Rig/Hips/ArmL/HandL/OrbitModel", "Rig/Hips/ArmL/HandL"],
	"dulinha": ["Rig/Hips/ArmL/HandL/Tablet", "Rig/Hips/ArmL/HandL"],
	"sagao": ["Rig/Hips/ArmL/HandL/Record", "Rig/Hips/ArmL/HandL"],
	"sali": ["Rig/Hips/ArmL/HandL/Ball", "Rig/Hips/ArmL/HandL"],
	"cifrinha": ["Rig/Hips/ArmL/HandL/Calculator", "Rig/Hips/ArmL/HandL"],
	"herschelinha": ["Rig/Hips/ArmL/HandL/Telescope", "Rig/Hips/ArmL/HandL"],
}
## outfit boxes per scene: keep the draw calls in the same range as Halleyzinho's
const MAX_PARTS := 950

var _failures := 0


func _initialize() -> void:
	var legends := {}
	for l: Dictionary in TycoonLegends.all():
		legends[String(l.get("id", ""))] = l
	for id: String in PARTS:
		await _lenda(id, legends.get(id, {}))
	await _signatures()
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _spawn(id: String) -> LegendCometling:
	var ps := load("res://scenes/npc/legends/%s.tscn" % id) as PackedScene
	if ps == null:
		return null
	var c := ps.instantiate() as LegendCometling
	if c == null:
		return null
	c.listen_to_events = false
	c.habits = false
	c.paused = true
	get_root().add_child(c)
	return c


func _lenda(id: String, data: Dictionary) -> void:
	var path := "res://scenes/npc/legends/%s.tscn" % id
	_check(String(data.get("scene", "")) == path, "%s: legends.json points at %s" % [id, path])
	var c := _spawn(id)
	_check(c != null, "%s: the scene loads as a LegendCometling" % id)
	if c == null:
		return
	await _frames(2)
	_check(c is Cometling and c.get_script() != load("res://src/npc/legend_cometling.gd"),
		"%s: a Cometling with its own character script" % id)
	_check(c.legend_id == id, "%s: legend_id is set" % id)
	for p: String in PARTS[id]:
		_check(c.get_node_or_null(p) != null, "%s has %s" % [id, p])
	# the outfit's materials and tints
	var own := 0
	var tinted := 0
	var not_toon := 0
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if c._own.has(m):
			own += 1
			if c._meshes.has(m):
				tinted += 1
			var sm := m.material_override as ShaderMaterial
			if sm == null or sm.shader.resource_path != "res://shaders/cw_toon_solid.gdshader":
				not_toon += 1
	_check(own >= 40 and own <= MAX_PARTS, "%s: %d outfit boxes (40..%d)" % [id, own, MAX_PARTS])
	_check(not_toon == 0, "%s: every outfit box keeps a cw_toon_solid material (%d do not)" % [id, not_toon])
	_check(tinted == 0, "%s: the outfit is not tinted like skin" % id)
	_check(c._meshes.size() > 10 and c._meshes.size() < 60, "%s: only the Cometling's own %d meshes take tints" % [id, c._meshes.size()])
	var head := c.get_node("Rig/Hips/Neck/Mesh").get_child(0) as MeshInstance3D \
		if c.get_node("Rig/Hips/Neck/Mesh").get_child_count() > 0 else null
	if head:
		_check(head.material_override == c.body_material, "%s: the head still wears the Cometling skin" % id)
	_check(not c.get_node("Rig/Hips/Vest").visible and not c.get_node("Rig/Hips/Neck/HardHat").visible
		and not c.get_node("Rig/Hips/Neck/Helmet").visible, "%s: no profession gear" % id)
	# habits
	_check(c.habit_names.size() >= 3 and c.habit_lengths.size() == c.habit_names.size(),
		"%s: %d habits with their lengths" % [id, c.habit_names.size()])
	for h: String in c.habit_names:
		var ok := c.play_habit(h) and c.current_habit() == h
		var mid := false
		var steps := int(ceil(c._h_len / 0.05)) + 4
		for i in steps:
			c.advance(0.05)
			if i == steps / 2:
				mid = c.current_habit() == h
		_check(ok and mid and c.current_habit() == "" and c.current_action() == "idle",
			"%s: habit %s plays to its end" % [id, h])
	_check(not c.play_habit("nope"), "%s: an unknown habit is refused" % id)
	if HELD.has(id):
		var prop := c.get_node(HELD[id][0]) as Node3D
		var hand := c.get_node(HELD[id][1]) as Node3D
		c.set_move_velocity(Vector3(0, 0, 0.4))
		for i in 12:
			c.advance(0.05)
		c.set_move_velocity(Vector3.ZERO)
		_check(prop.global_position.distance_to(hand.global_position) < 0.12,
			"%s: the held prop stays with the paw while walking" % id)
		for i in 20:
			c.advance(0.05)
	c.talk(true)
	_check(c.current_action() == "talk", "%s: talks for the portrait" % id)
	c.talk(false)
	_check(c.current_action() == "idle", "%s: and stops" % id)
	c.queue_free()
	await _frames(2)


func _signatures() -> void:
	# Keplerino: the planet sweeps equal areas, so it moves faster near the Sun
	var k := _spawn("keplerino")
	await _frames(1)
	var planet := k.get_node("Rig/Hips/ArmL/HandL/OrbitModel/Planet") as Node3D
	var sun := k.get_node("Rig/Hips/ArmL/HandL/OrbitModel/Sun") as Node3D
	var near_speed := 0.0
	var far_speed := 0.0
	var prev := planet.position
	for i in 240:
		k.advance(0.033)
		var v := planet.position.distance_to(prev) / 0.033
		prev = planet.position
		var d := planet.position.distance_to(sun.position)
		if d < 0.06:
			near_speed = maxf(near_speed, v)
		elif d > 0.15:
			far_speed = maxf(far_speed, v)
	_check(near_speed > far_speed * 2.0 and far_speed > 0.0,
		"Keplerino's planet is faster near the Sun (%.3f vs %.3f m/s)" % [near_speed, far_speed])
	k.queue_free()
	# Cifrinha: a coin instead of the glowing bulb
	var c := _spawn("cifrinha")
	await _frames(1)
	_check(not (c.get_node("Rig/Hips/Neck/Antenna/Bulb/Mesh") as Node3D).visible
		and (c.get_node("Rig/Hips/Neck/Antenna/Bulb/Coin") as Node3D).visible, "Cifrinha has a coin on her antenna")
	c.play_habit("coin_flip")
	for i in int(c._h_len * 0.45 / 0.05):
		c.advance(0.05)
	var coin := c.get_node("Rig/Hips/ArmR/HandR/FlipCoin") as Node3D
	var hand := c.get_node("Rig/Hips/ArmR/HandR") as Node3D
	_check(coin.visible and coin.global_position.y > hand.global_position.y + 0.2, "her flipped coin goes up")
	c.queue_free()
	# Herschelinha: the telescope at her eye during the sweep
	var h := _spawn("herschelinha")
	await _frames(1)
	h.play_habit("sweep")
	for i in int(h._h_len * 0.5 / 0.05):
		h.advance(0.05)
	var tel := h.get_node("Rig/Hips/ArmL/HandL/Telescope") as Node3D
	var eye := h.get_node("Rig/Hips/Neck/EyeL") as Node3D
	_check(tel.global_position.distance_to(eye.global_position) < 0.2 and tel.global_basis.y.normalized().y > 0.3,
		"Herschelinha raises the telescope to her eye, pointing at the sky")
	h.queue_free()
	# Sali: the ball leaves her paw when she juggles
	var s := _spawn("sali")
	await _frames(1)
	s.play_habit("juggle")
	var top := -10.0
	var ball := s.get_node("Rig/Hips/ArmL/HandL/Ball") as Node3D
	for i in int(s._h_len * 0.8 / 0.05):
		s.advance(0.05)
		top = maxf(top, ball.global_position.y)
	_check(top > 0.3, "Sali's ball flies up from her foot (%.2f m)" % top)
	s.queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)
