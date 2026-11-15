class_name FlightRun
extends RefCounted
## One flight from start to end, node free: the simulation (FlightSim), its autopilot
## (FlightGuide; null while the player flies) and what happened (the event log). The 3D view
## (FlightWorld) shows a run and advances it with the frame's time; when the view closes the run
## can go on without it (the campus advances a career launch with the calendar, CareerFlight),
## and a view opened again later picks it up where it is: one flight, seen or not.
##   advance(dt)     flight time; events go to `log` and to `pending` (the view takes them)
##   take_pending()  the events the view has not shown yet: [key, data, met]
##   take_dropped()  the groups / fairings that left the craft since the last call
## Subclasses (CareerFlight) react to the events in _on_event().

## the campus deck of a pad above the campus sea (campus units: lot deck 1.15, sea -9)
const CAMPUS_DECK_ABOVE_SEA := 10.15
## a campus rocket on the pad is about this tall (campus units); the island is scaled so the
## flying rocket keeps that size against it
const CAMPUS_ROCKET_H := 9.0
## the horizontal direction the rocket flies towards from the pad (PCI)
const DOWNRANGE := Vector3(0.894, 0.0, -0.447)

var sim: FlightSim
## the autopilot flying it (FlightGuide, or a FlightNodeExecutor burning a node); null = the pilot
var guide: RefCounted = null
var vessel_scene: PackedScene
var vessel_name := ""
## the tycoon mission it flies for ({} for a test flight): FlightSession.mission
var mission: Dictionary = {}
var log: Array = []
var pending: Array = []
var _dropped: Array = []
## "" while flying, else how it ended: "orbit", "crash", "landed", "suborbital", "arrived"
var result := ""


## A run of a packed hangar vessel standing on the pad; `auto` gives it the autopilot to an
## orbit `alt` m high.
static func on_pad(ps: PackedScene, payload := 0.0, display_name := "", auto := false, alt := 200000.0) -> FlightRun:
	var r := FlightRun.new()
	r.setup(ps, payload, display_name)
	if auto:
		r.guide = FlightGuide.new(alt)
	return r


func setup(ps: PackedScene, payload := 0.0, display_name := "") -> void:
	vessel_scene = ps
	vessel_name = display_name
	sim = FlightSim.new(FlightCraft.from_scene(ps, payload))
	sim.place_on_pad(pad_alt(sim.craft.length), Vector3.UP, DOWNRANGE)


## Scale of the campus island under a rocket this long (m): the campus is a model village, the
## rocket is real, so the island grows to keep the rocket at its campus size.
static func island_scale(length: float) -> float:
	return clampf(length / CAMPUS_ROCKET_H, 1.5, 7.0)


## The pad deck's height above the sea (m) for a rocket this long (the scaled island).
static func pad_alt(length: float) -> float:
	return island_scale(length) * CAMPUS_DECK_ABOVE_SEA


## Advances `dt` seconds of flight time (at most `max_steps` physics steps). Returns the time
## reached.
func advance(dt: float, max_steps := 400) -> float:
	var t := sim.advance(dt, guide, max_steps)
	_collect()
	return t


## Advances up to the flight time `t_target` within `budget_ms` of wall clock (background).
func advance_to(t_target: float, budget_ms := 4.0) -> void:
	var end := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	while sim.t < t_target - 1e-6 and Time.get_ticks_usec() < end:
		advance(minf(t_target - sim.t, 600.0), 200)


func _collect() -> void:
	var ev := sim.take_events()
	for e: Array in ev:
		_on_event(e)
	log.append_array(ev)
	pending.append_array(ev)
	if pending.size() > 200:
		pending = pending.slice(pending.size() - 200)
	if not sim.dropped.is_empty():
		_dropped.append_array(sim.dropped)
		sim.dropped.clear()
		if _dropped.size() > 40:
			_dropped = _dropped.slice(_dropped.size() - 40)


func take_pending() -> Array:
	var p := pending
	pending = []
	return p


func take_dropped() -> Array:
	var d := _dropped
	_dropped = []
	return d


## The player takes the controls (the autopilot lets go) or gives them back.
func set_auto(on: bool, alt := 200000.0) -> void:
	if on and autopilot() == null:
		var g := FlightGuide.new(alt)
		if sim.launched:
			g.phase = "ascent" if not sim.in_orbit else "orbit"
			g.pitch_deg = rad_to_deg(asin(clampf(sim.nose().dot(sim.up()), -1.0, 1.0)))
		guide = g
	elif not on and guide != null:
		guide = null
		sim.craft.sas = FlightCraft.Sas.HOLD
		sim.command = sim.nose()


func _on_event(e: Array) -> void:
	match String(e[0]):
		"EV_CRASH":
			result = "crash"
		"EV_ORBIT":
			if result == "":
				result = "orbit"
		"EV_LANDED":
			result = "landed"


## Has it something left to do (a burn, a phase of the ascent)?
func busy() -> bool:
	var g := autopilot()
	if sim.crashed or g == null:
		return false
	return g.phase in ["pad", "ascent", "burn"] or not g.burns.is_empty()


## The ascent / burn autopilot (null when the pilot flies or a node executor burns).
func autopilot() -> FlightGuide:
	return guide as FlightGuide
