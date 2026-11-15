class_name CareerFlight
extends FlightRun
## A career launch flown for real (FlightRun): the project's rocket leaves the campus pad at the
## track's launch time and flies the outcome the launch simulation already gave (the career
## decides, the flight shows it; nothing here draws from the campaign RNG):
##   fail      breaks up at the track's lost time (SpaceTracking.fail_time), the cause named
##   partial   a lower orbit (or a loose capture at the target: the track's own rule)
##   success   to the parking orbit; a rocket that cannot get there by itself gets its last
##             stage topped up (the career says it made it)
## When the ascent ends (orbit, or a hop's engine cut) the track takes the flight's own state
## (SpaceTracking.rebase) and the departure / arrival burns of its legs become the autopilot's
## burns, each snapped onto its leg when done; after the last one the craft follows the track
## itself (FlightSim.rails_source), so the campus map and the 3D view show one path, now and
## whenever the player comes back to it. TycoonModes keeps the run while the player is on the
## campus and advances it with the calendar.

## the parking orbit the ascent aims at (m); the track takes whatever it really reached
const PARK_ALT := 185000.0
const PARTIAL_ALT := 160000.0
const HOP_ALT := 118000.0
## at most this many top-ups of a short rocket
const MAX_TOPUPS := 6

var state: TycoonState
var track_id := ""
var outcome := "full"
var target := "leo"
var cause_key := ""
## "pad", "ascent", "orbit", "burn", "transfer", "arrived", "lost"
var phase := "pad"
## a launch seen again from the pad (the review's "Acompanhar"): the track is not touched
var replay := false
var _topups := 0
var _rebased := false


static func for_track(s: TycoonState, tr: Dictionary, ps: PackedScene, payload := 0.0, display_name := "",
		cause := "") -> CareerFlight:
	var r := CareerFlight.new()
	r.state = s
	r.track_id = String(tr.get("id", ""))
	r.outcome = String(tr.get("outcome", "full"))
	r.target = String(tr.get("target", "leo"))
	r.cause_key = cause
	r.setup(ps, payload, display_name)
	r.sim.t = float(tr.get("launch_t", 0.0))
	r.sim.limits = false
	var alt := PARTIAL_ALT if r.outcome == "partial" and r.target in ["leo", "sso"] else PARK_ALT
	var g := FlightGuide.new(alt, _plane_of(tr))
	r.guide = g
	if r.target == "suborbital":
		g.apo_only = true
		g.target_alt = HOP_ALT
		r.sim.soft_landing = true
	if r.outcome == "fail":
		var lost := float(tr.get("lost_t", -1.0))
		r.sim.fail_met = (lost - float(tr["launch_t"])) if lost >= 0.0 else SpaceTracking.fail_time(r.track_id)
		r.sim.fail_reason = crash_reason_for(cause, r.sim.fail_met)
	return r


## A craft already in space, seen where its track has it at time t (the map's "Acompanhar"):
## its last stage only, on the track's path (the track's own legs drive it, burns included).
static func following(s: TycoonState, tr: Dictionary, t: float, ps: PackedScene, display_name := "") -> CareerFlight:
	var r := CareerFlight.new()
	r.state = s
	r.track_id = String(tr.get("id", ""))
	r.outcome = String(tr.get("outcome", "full"))
	r.target = String(tr.get("target", "leo"))
	r.setup(ps, 0.0, display_name)
	var c := r.sim.craft
	var evs: Array = []
	c.next_stage(evs)
	while c.current_stage < c.stage_count - 1:
		c.next_stage(evs)
	c.throttle = 0.0
	r.sim.limits = false
	r.sim.t = t
	var st := SpaceTracking.state_at(tr, t)
	r.sim.set_orbit_state(int(st["body"]), st["pos"], st["vel"])
	r.sim.in_orbit = true
	r.sim.take_events()
	r.sim.dropped.clear()
	var g := FlightGuide.new(PARK_ALT, _plane_of(tr))
	g.phase = "orbit"
	r.guide = g
	c.sas = FlightCraft.Sas.PROGRADE
	r._rebased = true
	r.phase = "orbit" if String(st["status"]) != "arrived" else "arrived"
	r._plan_burns(tr, t)
	return r


## The plane the track's parking orbit lies in (its first orbit leg), else the Moon's plane.
static func _plane_of(tr: Dictionary) -> Vector3:
	for l: Dictionary in tr.get("legs", []):
		if String(l["kind"]) in ["orbit", "transfer"] and String(l["body"]) == "earth":
			var r := Vector3(float(l["r"][0]), float(l["r"][1]), float(l["r"][2]))
			var v := Vector3(float(l["v"][0]), float(l["v"][1]), float(l["v"][2]))
			var n := r.cross(v)
			if n.length() > 1.0:
				n = n.normalized()
				# keep it through the pad (horizontal at the launch site)
				n = (n - Vector3.UP * n.dot(Vector3.UP)).normalized()
				return n
	return FlightSolar.LAUNCH_NORMAL.normalized()


## What broke, in the flight's words (the Design Review's cause of the failure).
static func crash_reason_for(cause: String, met: float) -> String:
	var c := cause.to_upper()
	if "STAG" in c or "SEP" in c:
		return "TY_TRK_CRASH_STAGE"
	if met < 75.0 or "ENG" in c or "MOTOR" in c or "STAGE1" in c:
		return "TY_TRK_CRASH_ENGINE"
	return "CRASH_Q"


func track() -> Dictionary:
	return SpaceTracking.find(state, track_id) if state else {}


func advance(dt: float, max_steps := 400) -> float:
	var t := super.advance(dt, max_steps)
	_after_step()
	return t


func _after_step() -> void:
	var guide := autopilot()
	if guide == null or sim.crashed:
		return
	if guide.phase in ["ascent", "pad"]:
		phase = "ascent" if sim.launched else "pad"
	# a short rocket on a flight the career says makes it: its last stage gets more to burn
	if guide.short and outcome != "fail" and _topups < MAX_TOPUPS:
		_topups += 1
		guide.short = false
		guide.phase = "ascent"
		var last := sim.craft.stage_count - 1
		if sim.craft.current_stage < last:
			sim.stage()
		for pool: Dictionary in sim.craft.pools:
			if int(pool["stage"]) == last:
				pool["prop"] = float(pool["prop"]) + float(pool["prop0"]) * 0.35
		for e: Dictionary in sim.craft.engines:
			if int(e["stage"]) == last:
				e["restarts"] = maxi(int(e["restarts"]), 1)
	# the hop is over the top: the track takes its fall
	if target == "suborbital" and not _rebased and not replay and guide.phase == "coast" and sim.thrust_n <= 0.0:
		_rebase()


func _on_event(e: Array) -> void:
	super._on_event(e)
	match String(e[0]):
		"EV_CRASH":
			phase = "lost"
		"EV_ORBIT":
			if replay:
				phase = "orbit"
			elif not _rebased and target != "suborbital":
				_rebase()
		"EV_LANDED":
			phase = "arrived"
			result = "arrived"


## The track follows the flight from here; its burns become the autopilot's.
func _rebase() -> void:
	_rebased = true
	var tr := track()
	if tr.is_empty():
		phase = "orbit"
		return
	SpaceTracking.rebase(tr, sim.pos(), sim.vel(), sim.t)
	tr["status"] = SpaceTracking.status_at(tr, sim.t)
	phase = "orbit" if target != "suborbital" else "ascent"
	_plan_burns(tr)


## One burn per change of path around the same body (departure, apogee); the arrival in another
## body's frame is the track's own (rails_source) after the last burn.
func _plan_burns(tr: Dictionary, after := -INF) -> void:
	var guide := autopilot()
	if guide == null:
		return
	var legs: Array = tr["legs"]
	guide.burns.clear()
	for i in range(1, legs.size()):
		var prev: Dictionary = legs[i - 1]
		var l: Dictionary = legs[i]
		if String(l["kind"]) == "fixed" or String(l["body"]) != String(prev["body"]) or String(l["body"]) != "earth":
			continue
		var t0 := float(l["t0"])
		if t0 <= after:
			continue
		var before := SpaceTracking.state_at({"legs": [prev], "launch_t": 0.0, "lost_t": -1.0}, t0)
		var dv := Vector3(float(l["v"][0]) - before["vel"][0], float(l["v"][1]) - before["vel"][1],
			float(l["v"][2]) - before["vel"][2])
		if dv.length() < 1.0:
			continue
		var idx := i
		guide.burns.append({"t": t0, "dv": dv, "snap": func() -> void: _snap(idx)})
	if guide.burns.is_empty() and (legs.size() > 1 or after > -INF):
		sim.rails_source = _track_state


## A burn is done: the craft goes exactly onto its leg (a few m/s of steering error vanish).
func _snap(leg_index: int) -> void:
	var tr := track()
	if tr.is_empty():
		return
	var st := SpaceTracking.state_at(tr, sim.t)
	if int(st["leg"]) >= leg_index and int(st["body"]) == sim.body:
		sim.set_state(st["pos"], st["vel"])
	phase = "transfer"
	var guide := autopilot()
	if guide == null or guide.burns.size() <= 1:
		sim.rails_source = _track_state


func _track_state(t: float) -> Dictionary:
	var tr := track()
	if tr.is_empty():
		return {"body": sim.body, "pos": sim.pos(), "vel": sim.vel()}
	var st := SpaceTracking.state_at(tr, t)
	var s := String(st["status"])
	if s == "arrived" and phase != "arrived":
		phase = "arrived"
		result = "arrived"
	return st


## Where the flight is, in the career's words: the track status at the flight's time.
func status() -> String:
	if sim.crashed:
		return "lost"
	var tr := track()
	return SpaceTracking.status_at(tr, sim.t) if not tr.is_empty() else "flight"


## Nothing left to fly: lost, landed, or riding its track.
func settled() -> bool:
	var guide := autopilot()
	return sim.crashed or phase == "arrived" or (_rebased and (guide == null or (guide.burns.is_empty() and guide.phase != "burn")))
