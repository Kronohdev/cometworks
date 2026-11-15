class_name FlightLog
extends RefCounted
## The story of one career flight (CareerFlight), written down while it is simulated, for the
## comic recap narrated by Vovô Edmundo (FlightComic) and the post-mission report (FlightReport).
## Nothing here invents: every event is something the run went through.
##   watched   the launch watch calls observe() each frame, whatever the speed
##   skipped   "Simular até o fim": finish() flies the same run on to its final objective at once
##             (small physics chunks while the engines or the guide work, whole coasts on rails),
##             observing as it goes. The physics always steps FlightSim.DT, so the outcome does
##             not depend on the speed (and the career decided it anyway: CareerFlight).
## Sources, in flight order:
##   the run's log     liftoff, max-Q, boosters, stages, fairing, space, orbit, landing, break-up
##   the hop's top     a sounding rocket's apogee (it starts falling above 50 km)
##   the track's legs  once the track follows the flight (rebase, or a replay / a followed craft
##                     whose track is the flight that already happened): the departure burn, the
##                     high orbit, the lunar capture, the landing, the flyby, the comet rendezvous,
##                     the splashdown, each recorded when the run's clock passes it
## An event: {"kind", "t" (campaign s), "met" (s from liftoff), "alt" (m), "speed" (m/s), "body",
## "stage", "stages", "data"}.

const SIM_KINDS := {"EV_LIFTOFF": "liftoff", "EV_MAXQ": "maxq", "EV_BOOSTER_SEP": "booster_sep",
	"EV_STAGE_SEP": "stage_sep", "EV_FAIRING": "fairing", "EV_SPACE": "space", "EV_ORBIT": "orbit",
	"EV_LANDED": "landed", "EV_CRASH": "crash"}
## kinds that happen once (a second report of the same is the simulation repeating itself)
const ONCE: Array[String] = ["liftoff", "maxq", "fairing", "space", "orbit", "landed", "crash", "apogee"]
## flight seconds per advance while the physics runs (the watch's 1x is a frame, 1/60 s)
const CHUNK := 0.5
const CHUNK_STEPS := 200
## a coast on rails goes at most this far per advance (it stops at the guide's events anyway)
const COAST := 21600.0
const COAST_STEPS := 4000
## the longest flight finish() flies (s): beyond it the track's own end is far off anyway
const MAX_FLIGHT := 200.0 * 86400.0
const MAX_EVENTS := 40

var run: CareerFlight
var events: Array = []
var _log_seen := 0
var _legs_seen := {}


func _init(r: CareerFlight = null) -> void:
	run = r
	if run:
		observe()


## Reads what happened since the last call (the run's new log entries, the hop's top, the track
## legs the run's clock passed).
func observe() -> void:
	if run == null:
		return
	var s := run.sim
	while _log_seen < run.log.size():
		var e: Array = run.log[_log_seen]
		_log_seen += 1
		var kind := String(SIM_KINDS.get(String(e[0]), ""))
		if kind == "":
			continue
		var met := float(e[2])
		var data: Dictionary = (e[1] as Dictionary).duplicate() if e[1] is Dictionary else {}
		if kind == "crash":
			data["reason"] = s.crash_reason
			data["cause_key"] = run.cause_key
		if kind == "orbit" and run.target == "suborbital":
			continue
		_add(kind, (s.t_liftoff + met) if s.t_liftoff >= 0.0 else s.t, met, data)
	if run.target == "suborbital" and s.launched and not has("apogee") and s.vertical_speed() < 0.0 \
			and s.altitude() > 50000.0:
		var top := float(s.stats.get("max_alt", s.altitude()))
		_add("apogee", s.t, s.met(), {"alt": top}, {"alt": top})
	if run._rebased or run.replay:
		_record_legs(s.t)


## Flies the run on to its final objective (or its loss) within `budget_ms` of wall clock.
## Returns true when it got there.
func finish(budget_ms := 20000.0) -> bool:
	if run == null:
		return true
	var wall_end := Time.get_ticks_msec() + int(budget_ms)
	var cap := run.sim.t + MAX_FLIGHT
	while not done() and Time.get_ticks_msec() < wall_end and run.sim.t < cap:
		step()
	observe()
	if run.replay and done():
		# a launch seen again stops at its orbit: the rest is its track, the flight that went on
		_record_legs(INF)
	return done()


## One advance of finish(): a short physics chunk while anything flies by thrust or by guide,
## a long coast once the craft rides its track or coasts on rails.
func step() -> void:
	var s := run.sim
	var dt := CHUNK
	var steps := CHUNK_STEPS
	if run.settled():
		dt = maxf(end_time() - s.t + 1.0, 1.0)
		steps = COAST_STEPS
	elif s.on_rails:
		dt = COAST
		steps = COAST_STEPS
	run.advance(dt, steps)
	observe()


## The time the flight's final objective is reached: the track's last leg (arrival, high orbit,
## landing), else now.
func end_time() -> float:
	var tr := run.track()
	var legs: Array = tr.get("legs", [])
	if legs.is_empty():
		return run.sim.t
	return float((legs[-1] as Dictionary)["t0"])


## Has the flight reached its end: lost, landed / arrived, or riding its track past its last leg
## (a replay: once in orbit).
func done() -> bool:
	if run == null:
		return true
	var s := run.sim
	if s.crashed or run.phase == "arrived" or run.result in ["landed", "arrived"]:
		return true
	if run.replay:
		return s.in_orbit
	if not run.settled():
		return false
	return run.track().is_empty() or s.t >= end_time() - 0.5


## How it ended, in the career's words: {"lost", "status", "phase", "body", "in_orbit"}.
func outcome() -> Dictionary:
	var s := run.sim
	return {"lost": s.crashed, "status": run.status(), "phase": run.phase, "body": String(s.sys.ids[s.body]),
		"in_orbit": s.in_orbit}


func has(kind: String) -> bool:
	for e: Dictionary in events:
		if String(e["kind"]) == kind:
			return true
	return false


func kinds() -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in events:
		out.append(String(e["kind"]))
	return out


func _add(kind: String, t: float, met: float, data := {}, over := {}) -> void:
	if kind in ONCE and has(kind):
		return
	if events.size() >= MAX_EVENTS:
		return
	# boosters let go in pairs a moment apart: one separation
	if kind == "booster_sep" and events.any(func(x: Dictionary) -> bool: return String(x["kind"]) == kind \
			and absf(float(x["t"]) - t) < 5.0):
		return
	var s := run.sim
	var e := {"kind": kind, "t": t, "met": met, "alt": s.altitude(), "speed": s.speed(),
		"body": String(s.sys.ids[s.body]), "stage": s.craft.current_stage, "stages": s.craft.stage_count, "data": data}
	e.merge(over, true)
	# keep the order by time (a leg recorded late by a long coast still lands in its place)
	var at := events.size()
	while at > 0 and float(events[at - 1]["t"]) > t:
		at -= 1
	events.insert(at, e)


## The track's legs the clock passed, as events (see the class doc).
func _record_legs(until: float) -> void:
	var tr := run.track()
	var legs: Array = tr.get("legs", [])
	for i in range(1, legs.size()):
		var l: Dictionary = legs[i]
		var t0 := float(l["t0"])
		var key := "%d@%.0f" % [i, t0]
		if t0 > until or _legs_seen.has(key):
			continue
		_legs_seen[key] = true
		var kind := leg_kind(legs[i - 1], l, run.target)
		if kind == "":
			continue
		var met := t0 - run.sim.t_liftoff if run.sim.t_liftoff >= 0.0 else 0.0
		var r := Vector3(float(l["r"][0]), float(l["r"][1]), float(l["r"][2]))
		var v := Vector3(float(l["v"][0]), float(l["v"][1]), float(l["v"][2]))
		var sys := run.sim.sys
		var b := sys.ids.find(String(l["body"]))
		_add(kind, t0, met, {"target": run.target, "body": String(l["body"])},
			{"alt": r.length() - (sys.radius[b] if b >= 0 else 0.0), "speed": v.length(), "body": String(l["body"])})


## The story a track alone keeps of a flight nobody watched nor skipped (an old launch: its
## launch, its loss, its orbit insertion and its legs; no stage details, they were never
## recorded): {"events", "outcome"} like a recorded log's.
static func from_track(tr: Dictionary, cause_key := "") -> Dictionary:
	var sys := FlightSolar.get_system()
	var t0 := float(tr.get("launch_t", 0.0))
	var target := String(tr.get("target", "leo"))
	var events: Array = []
	var mk := func(kind: String, t: float, alt: float, body: String, data: Dictionary) -> Dictionary:
		return {"kind": kind, "t": t, "met": t - t0, "alt": alt, "speed": 0.0, "body": body, "stage": 0, "stages": 2,
			"data": data}
	events.append(mk.call("liftoff", t0, 0.0, "earth", {}))
	var lost := float(tr.get("lost_t", -1.0))
	if lost >= 0.0 and lost - t0 < SpaceTracking.ASCENT_S * 2.0:
		events.append(mk.call("crash", lost, 30000.0, "earth", {"cause_key": cause_key}))
		return {"events": events, "outcome": {"lost": true, "status": "lost", "phase": "lost", "body": "earth",
			"in_orbit": false}}
	var legs: Array = tr.get("legs", [])
	if target != "suborbital" and not legs.is_empty():
		var ins := float(tr.get("ins_t", t0 + SpaceTracking.ASCENT_S))
		var st := SpaceTracking.state_at(tr, ins)
		var p: Array = st["pos"]
		var alt := Vector3(float(p[0]), float(p[1]), float(p[2])).length() - sys.radius[sys.earth]
		events.append(mk.call("orbit", ins, alt, "earth", {}))
	for i in range(1, legs.size()):
		var l: Dictionary = legs[i]
		var kind := leg_kind(legs[i - 1], l, target)
		if kind != "":
			var r := Vector3(float(l["r"][0]), float(l["r"][1]), float(l["r"][2]))
			var b := sys.ids.find(String(l["body"]))
			events.append(mk.call(kind, float(l["t0"]), r.length() - (sys.radius[b] if b >= 0 else 0.0), String(l["body"]),
				{"target": target}))
	var last: Dictionary = legs[-1] if not legs.is_empty() else {}
	var status := String(last.get("status", "orbit"))
	return {"events": events, "outcome": {"lost": false, "status": status,
		"phase": status, "body": String(last.get("body", "earth")), "in_orbit": status == "orbit"}}


## What a change of leg was (prev -> l): "burn", "high_orbit", "capture", "landing", "flyby",
## "rendezvous", "splashdown" or "" (nothing to tell).
static func leg_kind(prev: Dictionary, l: Dictionary, target: String) -> String:
	var kind := String(l["kind"])
	var body := String(l["body"])
	var status := String(l.get("status", ""))
	if body != "earth":
		return "landing" if kind == "fixed" else ("capture" if kind == "orbit" else "")
	if kind == "transfer" and status == "arrived":
		return "flyby"
	if kind == "transfer" and String(prev["kind"]) == "orbit":
		return "burn"
	if kind == "orbit" and String(prev["kind"]) == "transfer":
		return "high_orbit"
	if kind == "fixed" and status == "arrived":
		return "splashdown" if target == "suborbital" else "rendezvous"
	return ""
