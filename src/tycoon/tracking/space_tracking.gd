class_name SpaceTracking
extends RefCounted
## Every launch as a tracked object in space (the solar-system map of the campus, the launch
## watch): pure data and rules on TycoonState.tracking, no scene access, so it runs headless.
##
## A track is saved as data: {"id", "owner" ("player" or a rival id), "code", "type", "target",
## "outcome", "launch_t" (campaign seconds), "lost_t" (-1 = not lost), "status", "legs": [...]}.
## Campaign time is the tycoon calendar in seconds: weeks x WEEK (week 0 = the mission epoch of
## FlightSolar, 2026-10-28), so a track and the planets of FlightSolar share one clock.
## Each leg is a piece of the path around one body, in the flight's inertial axes (PCI):
##   {"kind": "orbit" | "transfer" | "ballistic" | "fixed", "body": FlightSolar id,
##    "t0", "t1" (-1 = open), "r": [x, y, z] and "v" (m, m/s, relative to the body at t0),
##    "status": "flight" | "orbit" | "arrived", "spin": the fixed point turns with the Moon}
## Positions are exact two-body conics (FlightConic, Kepler), built once at launch so the path is
## continuous: a parking orbit, the departure burn when the phase is right (the Moon is there
## when the craft gets there), the transfer, then the orbit, the landing site or the flyby loop.
## Status at time t: "lost" from lost_t on, "flight" during the ascent, else the leg's.
##
## Tracks come from the player's launches (mission_launched; ProjectDesk's history fills the gaps,
## so an old save gets its missions back), from the rivals' milestones (RaceDirector.claims, their
## failures through rival_failed) and from mission ops (a mission lost in operation is lost here
## too). Nothing here draws from the campaign RNG: the same campaign keeps the same future.

const WEEK := 604800.0
## seconds from liftoff to the parking orbit (the launch watch's auto-ascent takes about this)
const ASCENT_S := 540.0
const PLAYER := "player"
const STATUSES: Array[String] = ["flight", "orbit", "arrived", "lost"]
## the comet comes from here (PCI, same as the mission map's comet_from)
const COMET_DIR := Vector3(-0.8, 0.22, -0.55)
## rival milestones whose conditions name no target
const RIVAL_TARGETS := {"cometling_space": "leo", "base_module": "lunar_surface", "lunar_propellant": "lunar_pole"}
const RIVAL_TYPES := {"cometling_space": "crewed_flight"}
## targets the 3D view can follow (the flight models the Earth and the Moon)
const FOLLOW_BODIES: Array[String] = ["earth", "moon"]


# ------------------------------------------------------------ store
static func store(state: TycoonState) -> Dictionary:
	if not state.tracking.has("missions") or not state.tracking["missions"] is Array:
		state.tracking["missions"] = []
	return state.tracking


static func missions(state: TycoonState) -> Array:
	return store(state)["missions"]


static func find(state: TycoonState, id: String) -> Dictionary:
	for t: Dictionary in missions(state):
		if String(t["id"]) == id:
			return t
	return {}


## The track of a player's project ({} if none).
static func for_project(state: TycoonState, project_id: String) -> Dictionary:
	return find(state, "p:" + project_id)


## Campaign time (s) of the state's calendar, `frac` of the current week elapsed.
static func now(state: TycoonState, frac := 0.0) -> float:
	return (float(state.weeks) + clampf(frac, 0.0, 1.0)) * WEEK


# ------------------------------------------------------------ wiring
## Listens to the launches (player and rivals). Idempotent; TycoonState calls it when a campaign
## starts or loads.
static func attach(state: TycoonState) -> void:
	if state.has_meta("space_tracking"):
		return
	state.set_meta("space_tracking", true)
	var ref: WeakRef = weakref(state)
	state.mission_launched.connect(func(r: Dictionary) -> void:
		var s := ref.get_ref() as TycoonState
		if s:
			add_player(s, r, s.weeks))
	if state.race:
		state.race.rival_failed.connect(func(rival_id: String, milestone_id: String) -> void:
			var s := ref.get_ref() as TycoonState
			if s:
				add_rival(s, rival_id, milestone_id, s.weeks, true))


## Once a week (TycoonState.advance_week): new tracks from the history and the race, losses in
## operation, statuses.
static func advance_week(state: TycoonState) -> void:
	sync(state)
	var t := now(state)
	for tr: Dictionary in missions(state):
		if String(tr["owner"]) == PLAYER and float(tr["lost_t"]) < 0.0:
			var lost_week := _ops_lost_week(state, String(tr.get("project_id", "")))
			if lost_week >= 0:
				tr["lost_t"] = maxf(float(lost_week) * WEEK, float(tr["launch_t"]) + ASCENT_S)
		tr["status"] = status_at(tr, t)


## Builds the tracks the store misses: the player's launched projects (ProjectDesk history) and
## the rivals' milestones. Idempotent; an old save gets plausible tracks this way.
static func sync(state: TycoonState) -> void:
	for h: Dictionary in state.project_history:
		var id := String(h.get("id", ""))
		if id != "" and find(state, "p:" + id).is_empty():
			add_player(state, h, int(h.get("week", state.weeks)))
	if state.race:
		for ms_id: String in state.race.claims:
			for c: Dictionary in state.race.claims[ms_id]:
				var by := String(c.get("by", ""))
				if by != "" and by != PLAYER:
					var tid := "r:%s:%s" % [by, ms_id]
					if find(state, tid).is_empty():
						add_rival(state, by, ms_id, int(c.get("week", state.weeks)), false)


static func _ops_lost_week(state: TycoonState, project_id: String) -> int:
	if project_id == "":
		return -1
	for m: Dictionary in state.active_missions:
		if String(m.get("id", "")) == project_id and String(m.get("status", "")) == "lost" \
				and String(m.get("cause", "")) != "TY_OPS_CAUSE_LAUNCH":
			return state.weeks
	for m: Dictionary in state.mission_archive:
		if String(m.get("id", "")) == project_id and String(m.get("status", "")) == "lost" \
				and String(m.get("cause", "")) != "TY_OPS_CAUSE_LAUNCH":
			return int(m.get("end_week", state.weeks))
	return -1


## A player's launch (a mission_launched result or a history entry) becomes a track.
static func add_player(state: TycoonState, r: Dictionary, week: int) -> Dictionary:
	var pid := String(r.get("project_id", r.get("id", "")))
	var id := "p:" + pid if pid != "" else "p:#%d" % missions(state).size()
	if not find(state, id).is_empty():
		return find(state, id)
	var outcome := String(r.get("outcome", "full" if bool(r.get("success", true)) else "fail"))
	if r.has("success") and not bool(r["success"]):
		outcome = "fail"
	var tr := build(PLAYER, id, String(r.get("code", "")), String(r.get("type", "")), String(r.get("target", "leo")),
		outcome, float(week) * WEEK)
	tr["project_id"] = pid
	missions(state).append(tr)
	return tr


## A rival's milestone mission (or its failure) becomes a track in the rival's colour.
static func add_rival(state: TycoonState, rival_id: String, milestone_id: String, week: int, failed: bool) -> Dictionary:
	var id := ("rf:%s:%s:%d" % [rival_id, milestone_id, week]) if failed else ("r:%s:%s" % [rival_id, milestone_id])
	if not find(state, id).is_empty():
		return find(state, id)
	var target := String(RIVAL_TARGETS.get(milestone_id, "leo"))
	var type_id := String(RIVAL_TYPES.get(milestone_id, "orbiter"))
	if state.race:
		for c: Dictionary in state.race.milestone(milestone_id).get("conditions", []):
			var tg: Array = c.get("targets", [])
			var ty: Array = c.get("types", [])
			if not tg.is_empty():
				target = String(tg[0])
			if not ty.is_empty():
				type_id = String(ty[0])
			break
	var code := ""
	if state.race:
		var agency := TranslationServer.translate(state.race.agency_name(rival_id))
		code = "%s-%02d" % [agency.substr(0, 3).to_upper(), state.race.milestone_index(milestone_id) + 1]
	var tr := build(rival_id, id, code, type_id, target, "fail" if failed else "full", float(week) * WEEK)
	tr["milestone"] = milestone_id
	missions(state).append(tr)
	return tr


# ------------------------------------------------------------ building a path
## Deterministic 0..1 from a string (no RNG: tracks never move the campaign's luck).
static func hash01(s: String, salt := 0) -> float:
	return float(absi(hash("%s#%d" % [s, salt])) % 100003) / 100003.0


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _p(v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([v.x, v.y, v.z])


static func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _leg(kind: String, body: String, t0: float, r: PackedFloat64Array, v: PackedFloat64Array, status: String) -> Dictionary:
	return {"kind": kind, "body": body, "t0": t0, "t1": -1.0, "r": [r[0], r[1], r[2]], "v": [v[0], v[1], v[2]],
		"status": status}


## Seconds after liftoff at which a failed launch breaks up (the watch fails there too).
static func fail_time(id: String) -> float:
	return lerpf(42.0, 168.0, hash01(id, 7))


## The track of a launch: the legs of its whole path from t0 (campaign seconds).
static func build(owner: String, id: String, code: String, type_id: String, target: String, outcome: String,
		t0: float) -> Dictionary:
	var sys := FlightSolar.get_system()
	var tr := {"id": id, "owner": owner, "code": code, "type": type_id, "target": target, "outcome": outcome,
		"launch_t": t0, "lost_t": -1.0, "status": "flight", "legs": []}
	var legs: Array = []
	var e := sys.earth
	var mu := sys.mu[e]
	var re := sys.radius[e]
	var up := Vector3.UP
	var east := FlightWorld.EAST.normalized()
	if outcome == "fail":
		# breaks up over the range, a few km downrange of the pad
		var fs := fail_time(id)
		var p := (up * re + east * fs * 30.0).normalized() * re
		legs.append(_leg("fixed", "earth", t0, _p(p), _p(Vector3.ZERO), "flight"))
		tr["lost_t"] = t0 + fs
		tr["legs"] = legs
		return tr
	if target == "suborbital":
		var r0 := up * (re + 2000.0)
		var v0 := up * 1550.0 + east * 220.0
		var c := FlightConic.from_state(_p(r0), _p(v0), mu, t0)
		var t_land := c.time_to_radius(re, t0 + 1.0, false)
		if t_land == INF:
			t_land = t0 + 600.0
		var l0 := _leg("ballistic", "earth", t0, _p(r0), _p(v0), "flight")
		l0["t1"] = t_land
		legs.append(l0)
		var land := c.state_at(t_land)
		var lp := Vector3(land[0], land[1], land[2]).normalized() * re
		legs.append(_leg("fixed", "earth", t_land, _p(lp), _p(Vector3.ZERO), "arrived"))
		tr["legs"] = legs
		return tr
	# --- the parking orbit (the Moon's plane, which is the launch plane: eastward from the pad)
	var n := FlightSolar.LAUNCH_NORMAL.normalized()
	var alt := 200000.0
	match target:
		"leo":
			alt = lerpf(280000.0, 520000.0, hash01(id, 1))
			n = n.rotated(up, deg_to_rad(lerpf(-12.0, 12.0, hash01(id, 2))))
		"sso":
			alt = lerpf(600000.0, 820000.0, hash01(id, 1))
			n = east
	if owner != PLAYER and target in ["leo", "sso", "geo"]:
		# a rival flies from its own range: another plane through the same sky
		n = n.rotated(up, deg_to_rad(lerpf(25.0, 150.0, hash01(owner, 3)))).normalized()
	if outcome == "partial" and target in ["leo", "sso"]:
		alt = 165000.0
	var rp := re + alt
	# where the ascent puts it: about 18 degrees downrange, ASCENT_S after liftoff
	var u0 := n.cross(up).normalized()
	var ins_dir := (up * cos(deg_to_rad(18.0)) + u0 * sin(deg_to_rad(18.0))).normalized()
	var vc := sqrt(mu / rp)
	var v_ins := n.cross(ins_dir).normalized() * vc
	if outcome == "partial" and target in ["leo", "sso"]:
		v_ins *= 1.035   # a lopsided orbit: low perigee, high apogee
	var t_ins := t0 + ASCENT_S
	var back := FlightOrbit.propagate(_p(ins_dir * rp), _p(v_ins), -ASCENT_S, mu)
	var park := _leg("orbit", "earth", t0, PackedFloat64Array([back[0], back[1], back[2]]),
		PackedFloat64Array([back[3], back[4], back[5]]), "orbit")
	legs.append(park)
	var park_c := FlightConic.from_state(_p(ins_dir * rp), _p(v_ins), mu, t_ins)
	var n_p := TAU / park_c.period
	match target:
		"leo", "sso":
			pass
		"geo":
			var t_burn := t_ins + park_c.period * 0.4
			var s := park_c.state_at(t_burn)
			var r := Vector3(s[0], s[1], s[2])
			var ra := re + 35786000.0
			var a := (r.length() + ra) * 0.5
			var vt := Vector3(s[3], s[4], s[5]).normalized() * sqrt(mu * (2.0 / r.length() - 1.0 / a))
			var t_arr := t_burn + PI * sqrt(a * a * a / mu)
			_close(park, t_burn)
			var gto := _leg("transfer", "earth", t_burn, _p(r), _p(vt), "flight")
			legs.append(gto)
			var gc := FlightConic.from_state(_p(r), _p(vt), mu, t_burn)
			var sa := gc.state_at(t_arr)
			_close(gto, t_arr)
			var ra_v := Vector3(sa[0], sa[1], sa[2])
			var va := Vector3(sa[3], sa[4], sa[5])
			if outcome != "partial":
				va = va.normalized() * sqrt(mu / ra_v.length())
			legs.append(_leg("orbit", "earth", t_arr, _p(ra_v), _p(va), "orbit"))
		"comet":
			_add_comet(legs, park, park_c, n, t_ins, n_p, sys, id)
		_:
			if target.begins_with("lunar"):
				_add_lunar(legs, park, park_c, n, target, outcome, t_ins, n_p, sys)
	tr["legs"] = legs
	return tr


static func _close(leg: Dictionary, t1: float) -> void:
	leg["t1"] = t1


## Angle of a direction in the Moon's orbit basis (FlightSolar plane_p / plane_q).
static func _angle(sys: FlightSolar, d: Vector3) -> float:
	var bp := sys.plane_p[sys.moon]
	var bq := sys.plane_q[sys.moon]
	return atan2(d.dot(Vector3(bq[0], bq[1], bq[2])), d.dot(Vector3(bp[0], bp[1], bp[2])))


## Trans-lunar injection when the phase is right: a Hohmann ellipse whose apogee is where the Moon
## will be (FlightSolar's Moon runs on a circle in the parking plane), then the target's ending.
static func _add_lunar(legs: Array, park: Dictionary, park_c: FlightConic, n: Vector3, target: String,
		outcome: String, t_ins: float, n_p: float, sys: FlightSolar) -> void:
	var e := sys.earth
	var m := sys.moon
	var mu := sys.mu[e]
	var rp := park_c.rp
	var rm := sys.sma[m]
	var a := (rp + rm) * 0.5
	var tof := PI * sqrt(a * a * a / mu)
	var t_s := t_ins + park_c.period * 0.25
	var s0 := park_c.state_at(t_s)
	var theta0 := _angle(sys, Vector3(s0[0], s0[1], s0[2]))
	var g := theta0 + PI - (sys.phase[m] + sys.rate[m] * (t_s + tof))
	var t_d := t_s + fposmod(-g, TAU) / (n_p - sys.rate[m])
	var sd := park_c.state_at(t_d)
	var r := Vector3(sd[0], sd[1], sd[2])
	var vt := Vector3(sd[3], sd[4], sd[5]).normalized() * sqrt(mu * (2.0 / r.length() - 1.0 / a))
	_close(park, t_d)
	var tli := _leg("transfer", "earth", t_d, _p(r), _p(vt), "flight")
	legs.append(tli)
	var t_arr := t_d + tof
	var tc := FlightConic.from_state(_p(r), _p(vt), mu, t_d)
	var sa := tc.state_at(t_arr)
	if target == "lunar_flyby":
		_close(tli, t_arr)
		legs.append(_leg("transfer", "earth", t_arr, PackedFloat64Array([sa[0], sa[1], sa[2]]),
			PackedFloat64Array([sa[3], sa[4], sa[5]]), "arrived"))
		return
	_close(tli, t_arr)
	var mr := sys.radius[m]
	var mmu := sys.mu[m]
	var moon_rel := sys.pos_rel(m, e, t_arr)
	var to_earth := -Vector3(moon_rel[0], moon_rel[1], moon_rel[2]).normalized()
	match target:
		"lunar_orbit":
			var r_lo := mr + 100000.0
			var d := Vector3(sa[3], sa[4], sa[5]).normalized()
			var v := n.cross(d).normalized() * sqrt(mmu / r_lo)
			if outcome == "partial":
				v *= 1.12   # a loose capture: an elliptical lunar orbit
			legs.append(_leg("orbit", "moon", t_arr, _p(d * r_lo), _p(v), "orbit"))
		"lunar_pole":
			var lg := _leg("fixed", "moon", t_arr, _p(n * mr), _p(Vector3.ZERO), "arrived")
			lg["spin"] = true
			legs.append(lg)
		_:
			# lunar_surface: the near side, facing the Earth (the Moon keeps that face to us)
			var lg := _leg("fixed", "moon", t_arr, _p((to_earth + n * 0.2).normalized() * mr), _p(Vector3.ZERO), "arrived")
			lg["spin"] = true
			legs.append(lg)


## The comet: a hyperbolic departure whose asymptote points at the comet, then the rendezvous
## point (data/tycoon/ops.json distance_km, cruise_weeks).
static func _add_comet(legs: Array, park: Dictionary, park_c: FlightConic, n: Vector3, t_ins: float, n_p: float,
		sys: FlightSolar, _id: String) -> void:
	var e := sys.earth
	var mu := sys.mu[e]
	var tops := MissionOps.target_ops("comet")
	var d := float(tops.get("distance_km", 4500000.0)) * 1000.0
	var cruise := maxf(float(tops.get("cruise_weeks", 6)), 1.0) * WEEK
	var u := (COMET_DIR - n * COMET_DIR.dot(n)).normalized()
	var v_inf := d / cruise
	var rp := park_c.rp
	var ecc := 1.0 + rp * v_inf * v_inf / mu
	var nu_inf := acos(-1.0 / ecc)
	var p_hat := u.rotated(n, -nu_inf)
	# wait in the parking orbit until the craft is over the periapsis direction
	var t_s := t_ins + park_c.period * 0.25
	var s0 := park_c.state_at(t_s)
	var r0 := Vector3(s0[0], s0[1], s0[2])
	var ang := atan2(n.dot(r0.cross(p_hat)), r0.dot(p_hat))
	var t_d := t_s + fposmod(ang, TAU) / n_p
	var sd := park_c.state_at(t_d)
	var r := Vector3(sd[0], sd[1], sd[2])
	var v := n.cross(r).normalized() * sqrt(v_inf * v_inf + 2.0 * mu / r.length())
	_close(park, t_d)
	var dep := _leg("transfer", "earth", t_d, _p(r), _p(v), "flight")
	legs.append(dep)
	var c := FlightConic.from_state(_p(r), _p(v), mu, t_d)
	var t_arr := c.time_to_radius(d, t_d, true)
	if t_arr == INF:
		t_arr = t_d + cruise
	_close(dep, t_arr)
	var sa := c.state_at(t_arr)
	legs.append(_leg("fixed", "earth", t_arr, PackedFloat64Array([sa[0], sa[1], sa[2]]), _p(Vector3.ZERO), "arrived"))


# ------------------------------------------------------------ reading a track
## Index of the leg flying at time t (the first before the launch, the last after the end).
static func leg_index(tr: Dictionary, t: float) -> int:
	var legs: Array = tr["legs"]
	for i in legs.size():
		var l: Dictionary = legs[i]
		var t1 := float(l["t1"])
		if t1 < 0.0 or t < t1:
			return i
	return legs.size() - 1


static func status_at(tr: Dictionary, t: float) -> String:
	var lost := float(tr.get("lost_t", -1.0))
	if lost >= 0.0 and t >= lost:
		return "lost"
	if t < float(tr["launch_t"]) + ASCENT_S:
		return "flight"
	var legs: Array = tr["legs"]
	if legs.is_empty():
		return "flight"
	return String(legs[leg_index(tr, t)]["status"])


## Where the craft is at time t: {"body": FlightSolar index, "body_id", "pos" and "vel"
## (PackedFloat64Array, m and m/s, relative to the body), "leg", "kind", "status"}.
static func state_at(tr: Dictionary, t: float) -> Dictionary:
	var sys := FlightSolar.get_system()
	var legs: Array = tr["legs"]
	var i := leg_index(tr, t)
	var l: Dictionary = legs[i]
	var body := sys.index_of(String(l["body"]))
	var r := PackedFloat64Array([float(l["r"][0]), float(l["r"][1]), float(l["r"][2])])
	var v := PackedFloat64Array([float(l["v"][0]), float(l["v"][1]), float(l["v"][2])])
	var lost := float(tr.get("lost_t", -1.0))
	var tt := t
	if String(l["kind"]) != "fixed" and lost >= 0.0 and t > lost and String(tr.get("outcome", "")) == "fail":
		tt = lost
	var pos := r
	var vel := v
	match String(l["kind"]):
		"fixed":
			vel = PackedFloat64Array([0.0, 0.0, 0.0])
			if l.get("spin", false) and body >= 0:
				var ax := sys.orbit_normal(body)
				var p := Vector3(r[0], r[1], r[2]).rotated(ax, sys.rate[body] * (tt - float(l["t0"])))
				pos = _p(p)
		_:
			var s := FlightOrbit.propagate(r, v, tt - float(l["t0"]), sys.mu[body])
			pos = PackedFloat64Array([s[0], s[1], s[2]])
			vel = PackedFloat64Array([s[3], s[4], s[5]])
	return {"body": body, "body_id": String(l["body"]), "pos": pos, "vel": vel, "leg": i, "kind": String(l["kind"]),
		"status": status_at(tr, t)}


## The conic of leg i (null for a fixed point).
static func leg_conic(tr: Dictionary, i: int) -> FlightConic:
	var sys := FlightSolar.get_system()
	var l: Dictionary = tr["legs"][i]
	if String(l["kind"]) == "fixed":
		return null
	var body := sys.index_of(String(l["body"]))
	return FlightConic.from_state(PackedFloat64Array([float(l["r"][0]), float(l["r"][1]), float(l["r"][2])]),
		PackedFloat64Array([float(l["v"][0]), float(l["v"][1]), float(l["v"][2])]), sys.mu[body], float(l["t0"]))


## Points (x, y, z triplets, m, relative to the leg's body) of the path leg i draws: a closed orbit
## all the way round, a transfer from its start to its end (an open one a few days ahead).
static func leg_points(tr: Dictionary, i: int, n := 160) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var c := leg_conic(tr, i)
	if c == null:
		return out
	var l: Dictionary = tr["legs"][i]
	var t0 := float(l["t0"])
	var t1 := float(l["t1"])
	var closed := c.e < 1.0 and (t1 < 0.0 or t1 - t0 >= c.period * 0.98)
	if closed:
		t1 = t0 + c.period
	elif t1 < 0.0:
		t1 = t0 + (c.period if c.e < 1.0 else 30.0 * 86400.0)
	if String(l["kind"]) == "ballistic":
		closed = false
	var steps := n if closed else maxi(n / 2, 24)
	out.resize((steps + 1) * 3)
	for k in steps + 1:
		var p := c.position_at(lerpf(t0, t1, float(k) / steps))
		out[k * 3] = p[0]
		out[k * 3 + 1] = p[1]
		out[k * 3 + 2] = p[2]
	return out


## Can the 3D flight show this craft now (in flight or orbit around the Earth or the Moon)?
static func can_follow(tr: Dictionary, t: float) -> bool:
	var st := state_at(tr, t)
	if String(st["status"]) == "lost" or String(st["kind"]) in ["fixed", "ballistic"]:
		return false
	if not String(st["body_id"]) in FOLLOW_BODIES:
		return false
	var sys := FlightSolar.get_system()
	var b := int(st["body"])
	var r := FlightOrbit.length(st["pos"])
	return r > sys.radius[b] + sys.atmo_top[b] and r < sys.soi[b] * 0.9


## Seconds of the transfer left before arrival (0 when there is none).
static func arrival_in(tr: Dictionary, t: float) -> float:
	var legs: Array = tr["legs"]
	for l: Dictionary in legs:
		if String(l["kind"]) == "transfer" and String(l["status"]) == "flight" and float(l["t1"]) > t:
			return float(l["t1"]) - t
	return 0.0


## The body a track is at now (its leg's body) by FlightSolar index.
static func body_of(tr: Dictionary, t: float) -> int:
	return int(state_at(tr, t)["body"])


## The colour of a track on the map: the player's agency colour, a rival's own.
static func color_of(state: TycoonState, tr: Dictionary) -> Color:
	var owner := String(tr.get("owner", PLAYER))
	if owner == PLAYER:
		return TycoonLeader.agency_color(state, CwPalette.IGNITION)
	if state.race:
		return state.race.agency_color(owner)
	return CwPalette.TEXT_DIM


## Translation key of a status.
static func status_key(status: String) -> String:
	return "TY_TRK_ST_" + status.to_upper()


# ------------------------------------------------------------ the launch watch
## The departure burn of a watched launch from its parking orbit (state r, v around the Earth at
## flight time t, FlightSolar's clock): {"t": burn time, "dv": Vector3 (m/s, PCI), "to": body id},
## {} for a target in Earth orbit. Same rules as the track: GEO raises its apogee, the Moon is met
## at the transfer's apogee, the comet leaves on its asymptote.
static func departure(target: String, r: PackedFloat64Array, v: PackedFloat64Array, t: float) -> Dictionary:
	var sys := FlightSolar.get_system()
	var e := sys.earth
	var mu := sys.mu[e]
	var c := FlightConic.from_state(r, v, mu, t)
	if c.e >= 1.0 or c.period == INF:
		return {}
	var n_p := TAU / c.period
	var n := Vector3(c.wx, c.wy, c.wz)
	var t_d := t + 45.0
	var r_new := 0.0
	var v_new := -1.0
	var to := "earth"
	if target == "geo":
		r_new = sys.radius[e] + 35786000.0
	elif target.begins_with("lunar"):
		var m := sys.moon
		var rm := sys.sma[m]
		var r0 := FlightOrbit.length(r)
		var a := (r0 + rm) * 0.5
		var tof := PI * sqrt(a * a * a / mu)
		var t_s := t + 45.0
		var s0 := c.state_at(t_s)
		var theta0 := _angle(sys, Vector3(s0[0], s0[1], s0[2]))
		var g := theta0 + PI - (sys.phase[m] + sys.rate[m] * (t_s + tof))
		t_d = t_s + fposmod(-g, TAU) / (n_p - sys.rate[m])
		# an orbiter or a flyby aims a little inside the Moon's path (a pass, not a hit); landers hit it
		r_new = rm - (6.0e6 if target in ["lunar_orbit", "lunar_flyby"] else 0.0)
		to = "moon"
	elif target == "comet":
		var tops := MissionOps.target_ops("comet")
		var d := float(tops.get("distance_km", 4500000.0)) * 1000.0
		var v_inf := d / (maxf(float(tops.get("cruise_weeks", 6)), 1.0) * WEEK)
		var rp := FlightOrbit.length(r)
		var ecc := 1.0 + rp * v_inf * v_inf / mu
		var u := (COMET_DIR - n * COMET_DIR.dot(n)).normalized()
		var p_hat := u.rotated(n, -acos(-1.0 / ecc))
		var s0 := c.state_at(t + 45.0)
		var r0 := Vector3(s0[0], s0[1], s0[2])
		t_d = t + 45.0 + fposmod(atan2(n.dot(r0.cross(p_hat)), r0.dot(p_hat)), TAU) / n_p
		v_new = sqrt(v_inf * v_inf + 2.0 * mu / rp)
		to = "comet"
	else:
		return {}
	var sd := c.state_at(t_d)
	var rd := Vector3(sd[0], sd[1], sd[2])
	var vd := Vector3(sd[3], sd[4], sd[5])
	if v_new < 0.0:
		var a2 := (rd.length() + r_new) * 0.5
		v_new = sqrt(mu * (2.0 / rd.length() - 1.0 / a2))
	return {"t": t_d, "dv": vd.normalized() * (v_new - vd.length()), "to": to}
