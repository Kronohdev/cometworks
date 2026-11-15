class_name FlightIsland
extends Node3D
## The Cometlings' island under a flight (scenes/flight/flight_island.tscn): the campus scene
## (island, sea, roads, lots) with a launch pad standing on the pad lots, so a flight that does
## not come from the campus (the hangar's test flight, the dev menu) still leaves from home.
## Inside the tycoon TycoonModes lends the live campus instead (lend()): its buildings, its
## Cometlings, its era; FlightWorld scales either one to the rocket and lays the pad deck under it.
## The campus' own sky and lights stay out while it is under the flight's sky (the flight has
## its own); give_back() returns them with the campus.

## the campus under the flight (the scene's own, or the lent one)
var campus: Node3D
## the lent campus's sky and lights, kept aside meanwhile
var _env: Node = null
var _env_index := -1
var _lights_visible := true
var _held_pad: Node = null
var lent := false


## A FlightIsland around a campus that lives elsewhere (the tycoon's): the campus is moved under
## it by the caller (TycoonModes) and handed back with give_back().
static func lend(c: Node3D) -> FlightIsland:
	var fi := FlightIsland.new()
	fi.name = "LentIsland"
	fi.lent = true
	fi.campus = c
	return fi


func _ready() -> void:
	if campus == null:
		campus = get_node_or_null("Campus") as Node3D
	if lent and campus and campus.get_parent() != self:
		if campus.get_parent():
			campus.get_parent().remove_child(campus)
		add_child(campus)
	if campus:
		campus.transform = Transform3D.IDENTITY
		_strip()


## The campus' own environment and lights would fight the flight's sky.
func _strip() -> void:
	var we := campus.get_node_or_null("WorldEnvironment")
	if we:
		_env = we
		_env_index = we.get_index()
		campus.remove_child(we)
		if not lent:
			we.queue_free()
			_env = null
	var lights := campus.get_node_or_null("Lights") as Node3D
	if lights:
		_lights_visible = lights.visible
		lights.visible = false
	# the campus' low clouds and gulls are model-village sized: the flight has its own sky
	var sky_life := campus.get_node_or_null("Terrain/SkyLife") as Node3D
	if sky_life:
		sky_life.visible = false
	_particles_local(true)


## The campus' fx (chimney smoke, lab puffs, antenna rings, fireflies, foot dust, pad steam) are
## world-space GPUParticles3D: their particles keep the frame they were emitted in. Under a flight
## the island is turned, scaled to the rocket and moved every frame around the floating origin
## (and a lent campus is asleep, so its particles are frozen), so those particles end up drawn
## away from their buildings: white puffs and rings scattered over the sea, seen from above.
## While the campus is the island they live in their emitter's frame (moving and scaling with it);
## restart() drops the ones emitted in the campus frame. give_back() undoes it.
func _particles_local(on: bool) -> void:
	for n in campus.find_children("*", "GPUParticles3D", true, false):
		var g := n as GPUParticles3D
		if on == g.local_coords or (not on and not g.has_meta("flight_world_coords")):
			continue
		if on:
			g.set_meta("flight_world_coords", true)
		else:
			g.remove_meta("flight_world_coords")
		g.local_coords = on
		var was_emitting := g.emitting
		g.restart()   # (restart() also switches emitting on: an idle one-shot stays idle)
		g.emitting = was_emitting


## Gets the pad of `lot` ready for the flight: the scene's own pad building shows its first era
## (it is always there), a lent campus's pad hides the rocket it holds (the flying one stands there).
func prepare(lot: String) -> void:
	var b := pad_building(lot)
	if b == null:
		return
	if not lent and b.has_method("set_look"):
		b.call("set_look", 1, 1, false)
	if b.has_method("hold_rocket") and not bool(b.get("rocket_held")):
		b.call("hold_rocket", true)
		_held_pad = b


## Seen from high up the campus' own sea (a finite plane) gives way to the planet's.
func set_far(far: bool) -> void:
	if campus == null:
		return
	for path in ["Terrain/Sea", "Terrain/FarCoast", "Terrain/NeighbourIsland"]:
		var n := campus.get_node_or_null(path) as Node3D
		if n and n.visible == far:
			n.visible = not far


func pad_building(lot: String) -> Node:
	if campus == null:
		return null
	var l := campus.get_node_or_null("Lots/" + lot)
	if l == null:
		return null
	for c in l.get_children():
		if c is CampusBuilding:
			return c
	return null


func _lot(lot: String) -> Node3D:
	if campus == null:
		return null
	var l := campus.get_node_or_null("Lots/" + lot) as Node3D
	return l if l else campus.get_node_or_null("Lots/pad") as Node3D


## The deck the rocket stands on, in this node's frame (campus units).
func pad_point(lot: String) -> Vector3:
	var l := _lot(lot)
	if l == null:
		return Vector3(0, FlightRun.CAMPUS_DECK_ABOVE_SEA - 9.0, 0)
	return l.position + Vector3(0, FlightRun.CAMPUS_DECK_ABOVE_SEA - 9.0, 0)


## Which way the pad faces (its lot's "face", radians about up).
func pad_face(lot: String) -> float:
	var l := _lot(lot)
	return float(l.get_meta("face", 0.0)) if l else 0.0


## The campus' own sky, kept aside while it was lent, back on it (call once it is home).
static func restore_env(c: Node) -> void:
	if c == null or not c.has_meta("flight_env"):
		return
	var kept: Array = c.get_meta("flight_env")
	c.remove_meta("flight_env")
	var env := kept[0] as Node
	if env and is_instance_valid(env) and env.get_parent() == null:
		c.add_child(env)
		c.move_child(env, clampi(int(kept[1]), 0, c.get_child_count() - 1))


## Hands the lent campus back (its sky, lights and pad rocket as they were). Returns it, out of
## the tree, for the caller to put back where it lives.
func give_back() -> Node3D:
	if not lent or campus == null:
		return null
	if _held_pad and is_instance_valid(_held_pad) and _held_pad.has_method("hold_rocket"):
		_held_pad.call("hold_rocket", false)
	var lights := campus.get_node_or_null("Lights") as Node3D
	if lights:
		lights.visible = _lights_visible
	# its sky goes back once the campus is home (restore_env): added here it would enter the
	# flight's world, which has a sky of its own
	if _env and is_instance_valid(_env):
		campus.set_meta("flight_env", [_env, _env_index])
	_env = null
	set_far(false)
	var sky_life := campus.get_node_or_null("Terrain/SkyLife") as Node3D
	if sky_life:
		sky_life.visible = true
	_particles_local(false)
	var c := campus
	if c.get_parent() == self:
		remove_child(c)
	campus = null
	return c
