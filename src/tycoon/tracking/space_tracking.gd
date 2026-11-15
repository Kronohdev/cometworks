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
## the comet's direction when the system has no comet body (PCI); otherwise comet_dir() points at
## Mae-Gelo's real place (FlightSolar.comet, its Halley-type orbit)
const COMET_DIR := Vector3(-0.8, 0.22, -0.55)
## rival milestones whose conditions name no target
const RIVAL_TARGETS := {"cometling_space": "leo", "base_module": "lunar_surface", "lunar_propellant": "lunar_pole"}
const RIVAL_TYPES := {"cometling_space": "crewed_flight"}
## targets the 3D view can follow (the flight models the Earth and the Moon)
const FOLLOW_BODIES: Array[String] = ["earth", "moon"]
## the angle a trans-lunar transfer sweeps from the burn to the Moon (deg; 180 = Hohmann)
const TLI_SWEEP_DEG := 170.0


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
	_after_park(legs, park, park_c, n, target, outcome, t_ins, sys, id)
	tr["legs"] = legs
	return tr


## The path after the parking orbit (the departure, the transfer and the ending of the target).
static func _after_park(legs: Array, park: Dictionary, park_c: FlightConic, n: Vector3, target: String, outcome: String,
		t_ins: float, sys: FlightSolar, id: String) -> void:
	var e := sys.earth
	var mu := sys.mu[e]
	var re := sys.radius[e]
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


static func _close(leg: Dictionary, t1: float) -> void:
	leg["t1"] = t1


## The Moon's position (Vector3, m, Earth-centred PCI) at time t.
static func _moon_at(sys: FlightSolar, t: float) -> Vector3:
	var p := sys.pos_rel_parent(sys.moon, t)
	return Vector3(p[0], p[1], p[2])


## The next trans-lunar injection from a parking orbit, from t_from on (real Moon: inclined,
## elliptical). The Moon only lies in the parking plane twice a month, so the craft waits for the
## arrival when it is there (its node), leaves TLI_SWEEP_DEG before that place, and the transfer ellipse
## (periapsis at the burn, its plane through the Moon's exact place) meets the Moon on arrival: at its
## centre, or `aim_in` metres off it across the approach for a pass: {"t": burn time, "r", "v"
## (transfer state at the burn, Vector3 PCI), "t_arr"}.
static func lunar_injection(sys: FlightSolar, park_c: FlightConic, t_from: float, aim_in := 0.0) -> Dictionary:
	var mu := sys.mu[sys.earth]
	var n := Vector3(park_c.wx, park_c.wy, park_c.wz).normalized()
	var rp := park_c.rp
	var sweep := deg_to_rad(TLI_SWEEP_DEG)
	var tof0 := _sweep_time(mu, rp, sys.sma[sys.moon] - aim_in, sweep)
	# 1. the first arrival at a node of the parking plane (the Moon's latitude above it == 0)
	var step := 3600.0
	var t := t_from
	var prev := _moon_at(sys, t + tof0).normalized().dot(n)
	var t_node := -1.0
	while t < t_from + 40.0 * 86400.0:
		var t2 := t + step
		var cur := _moon_at(sys, t2 + tof0).normalized().dot(n)
		if signf(cur) != signf(prev):
			var lo := t
			var hi := t2
			for _k in 30:
				var mid := (lo + hi) * 0.5
				if signf(_moon_at(sys, mid + tof0).normalized().dot(n)) == signf(prev):
					lo = mid
				else:
					hi = mid
			t_node = (lo + hi) * 0.5
			break
		prev = cur
		t = t2
	if t_node < 0.0:
		t_node = t_from
	# 2. the craft passes the point TLI_SWEEP_DEG behind the Moon's arrival place (nearest pass, not
	# before t_from): short of 180 deg, so the transfer plane only tilts a little to meet the Moon
	var n_p := TAU / park_c.period
	var t_d := t_node
	var tof_s := tof0
	for _it in 5:
		var mt := _moon_at(sys, t_d + tof_s)
		tof_s = _sweep_time(mu, rp, mt.length() - aim_in, sweep)
		var um := (mt - n * mt.dot(n)).normalized()
		var aim := um.rotated(n, -sweep)
		var s0 := park_c.state_at(t_d)
		var r0 := Vector3(s0[0], s0[1], s0[2])
		var dth := wrapf(atan2(n.dot(r0.cross(aim)), r0.dot(aim)), -PI, PI)
		t_d += dth / n_p
	while t_d < t_from:
		t_d += park_c.period
	# 3. the transfer: periapsis at the burn, plane through the Moon's place, reaching it on time
	var sd := park_c.state_at(t_d)
	var r := Vector3(sd[0], sd[1], sd[2])
	var rhat := r.normalized()
	var r_len := r.length()
	# arrival: first at the Moon's centre; a pass (aim_in > 0) then aims aim_in off it, across the
	# approach (perpendicular to the velocity relative to the Moon, on the Earth's side)
	var aim_off := Vector3.ZERO
	var res := _solve_arrival(sys, rhat, r_len, n, aim_off, t_d, tof_s)
	if aim_in > 0.0:
		var h0: Vector3 = res["h"]
		var v0 := h0.cross(rhat).normalized() * sqrt(sys.mu[sys.earth] * (1.0 + float(res["e"])) / r_len)
		var c0 := FlightConic.from_state(_p(r), _p(v0), sys.mu[sys.earth], t_d)
		var t_a := float(res["t_arr"])
		var sc := c0.state_at(t_a)
		var ms := sys.state_rel_parent(sys.moon, t_a)
		var v_rel := (Vector3(sc[3], sc[4], sc[5]) - Vector3(ms[3], ms[4], ms[5])).normalized()
		var to_earth := -Vector3(ms[0], ms[1], ms[2]).normalized()
		aim_off = (to_earth - v_rel * to_earth.dot(v_rel)).normalized() * aim_in
		res = _solve_arrival(sys, rhat, r_len, n, aim_off, t_d, float(res["t_arr"]) - t_d)
	var h_dir: Vector3 = res["h"]
	var v := h_dir.cross(rhat).normalized() * sqrt(sys.mu[sys.earth] * (1.0 + float(res["e"])) / r_len)
	return {"t": t_d, "r": r, "v": v, "t_arr": float(res["t_arr"])}


## The arrival time of a shot from the burn (rhat, r_len) at t_d to the Moon's place + aim_off:
## root of (time along the ellipse to that place at ta) - (ta - t_d), near t_d + tof_guess.
## {"t_arr", "e", "h"}.
static func _solve_arrival(sys: FlightSolar, rhat: Vector3, r_len: float, n: Vector3, aim_off: Vector3, t_d: float,
		tof_guess: float) -> Dictionary:
	var lo := t_d + tof_guess * 0.5
	var g_lo := float(_shot(sys, rhat, r_len, n, aim_off, lo)["tof"]) - (lo - t_d)
	var hi := lo
	var g_hi := g_lo
	var ta := lo
	while ta < t_d + tof_guess * 2.0:
		ta += 3600.0
		var g := float(_shot(sys, rhat, r_len, n, aim_off, ta)["tof"]) - (ta - t_d)
		if signf(g) != signf(g_lo):
			hi = ta
			g_hi = g
			lo = ta - 3600.0
			break
		g_lo = g
	if signf(g_hi) == signf(g_lo):
		hi = t_d + tof_guess
		lo = hi
	for _k in 40:
		var mid := (lo + hi) * 0.5
		var g := float(_shot(sys, rhat, r_len, n, aim_off, mid)["tof"]) - (mid - t_d)
		if signf(g) == signf(g_lo):
			lo = mid
		else:
			hi = mid
	var shot := _shot(sys, rhat, r_len, n, aim_off, (lo + hi) * 0.5)
	return {"t_arr": t_d + float(shot["tof"]), "e": shot["e"], "h": shot["h"]}


## Time (s) along an ellipse with periapsis r_p to sweep `sweep` rad and reach radius r_t.
static func _sweep_time(mu: float, r_p: float, r_t: float, sweep: float) -> float:
	var e := clampf((r_t - r_p) / (r_p - r_t * cos(sweep)), 0.0, 0.999)
	var a := r_p / (1.0 - e)
	var big_e := 2.0 * atan(sqrt((1.0 - e) / (1.0 + e)) * tan(sweep * 0.5))
	return (big_e - e * sin(big_e)) / sqrt(mu / (a * a * a))


## The ellipse with its periapsis at the burn (rhat, r_len) through the Moon's place at time ta
## (+ aim_off): {"tof": time from the burn to that place, "e", "h": plane normal}.
static func _shot(sys: FlightSolar, rhat: Vector3, r_len: float, n: Vector3, aim_off: Vector3, ta: float) -> Dictionary:
	var mu := sys.mu[sys.earth]
	var target := _moon_at(sys, ta) + aim_off
	var rt := maxf(target.length(), r_len * 2.0)
	var th := target.normalized()
	var h_dir := rhat.cross(th).normalized()
	if h_dir.dot(n) < 0.0:
		h_dir = -h_dir
	var dnu := fposmod(atan2(h_dir.dot(rhat.cross(th)), rhat.dot(th)), TAU)
	var e := clampf((rt - r_len) / (r_len - rt * cos(dnu)), 0.0, 0.999)
	var a := r_len / (1.0 - e)
	var big_e := 2.0 * atan(sqrt((1.0 - e) / (1.0 + e)) * tan(dnu * 0.5))
	if big_e < 0.0:
		big_e += TAU
	return {"tof": (big_e - e * sin(big_e)) / sqrt(mu / (a * a * a)), "e": e, "h": h_dir}


## Trans-lunar injection when the Moon will be in the parking plane (lunar_injection), then the
## target's ending.
static func _add_lunar(legs: Array, park: Dictionary, park_c: FlightConic, _n: Vector3, target: String,
		outcome: String, t_ins: float, _n_p: float, sys: FlightSolar) -> void:
	var e := sys.earth
	var m := sys.moon
	var mu := sys.mu[e]
	# the transfer arrives at the height it ends at (its low orbit, or the surface for a lander),
	# across its approach, so the path runs on into the Moon's frame unbroken
	var r_aim := sys.radius[m] + (100000.0 if target in ["lunar_orbit", "lunar_flyby"] else 0.0)
	var inj := lunar_injection(sys, park_c, t_ins + park_c.period * 0.25, r_aim)
	var t_d := float(inj["t"])
	var r: Vector3 = inj["r"]
	var vt: Vector3 = inj["v"]
	_close(park, t_d)
	var tli := _leg("transfer", "earth", t_d, _p(r), _p(vt), "flight")
	legs.append(tli)
	var t_arr := float(inj["t_arr"])
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
	var mn := sys.orbit_normal_at(m, t_arr)
	match target:
		"lunar_orbit":
			# where the transfer arrives, seen from the Moon (about r_aim from its centre)
			var rel := Vector3(sa[0] - moon_rel[0], sa[1] - moon_rel[1], sa[2] - moon_rel[2])
			var r_lo := maxf(rel.length(), mr + 20000.0)
			var d := rel.normalized()
			var v := mn.cross(d).normalized() * sqrt(mmu / r_lo)
			if outcome == "partial":
				v *= 1.12   # a loose capture: an elliptical lunar orbit
			legs.append(_leg("orbit", "moon", t_arr, _p(d * r_lo), _p(v), "orbit"))
		"lunar_pole":
			var lg := _leg("fixed", "moon", t_arr, _p(sys.pole(m) * mr), _p(Vector3.ZERO), "arrived")
			lg["spin"] = true
			legs.append(lg)
		_:
			# lunar_surface: where the transfer touches down (on the near side: it comes from the Earth)
			var rel := Vector3(sa[0] - moon_rel[0], sa[1] - moon_rel[1], sa[2] - moon_rel[2])
			var site := rel.normalized() if rel.length() > 1.0 else (to_earth + mn * 0.2).normalized()
			var lg := _leg("fixed", "moon", t_arr, _p(site * mr), _p(Vector3.ZERO), "arrived")
			lg["spin"] = true
			legs.append(lg)


## Unit vector (PCI) from the Earth to the comet Mae-Gelo at time t.
static func comet_dir(sys: FlightSolar, t: float) -> Vector3:
	if sys.comet < 0:
		return COMET_DIR.normalized()
	var p := sys.pos_rel(sys.comet, sys.earth, t)
	return Vector3(p[0], p[1], p[2]).normalized()


## The comet: a hyperbolic departure whose asymptote points at the comet, then the rendezvous
## point (data/tycoon/ops.json distance_km, cruise_weeks).
static func _add_comet(legs: Array, park: Dictionary, park_c: FlightConic, n: Vector3, t_ins: float, n_p: float,
		sys: FlightSolar, _id: String) -> void:
	var e := sys.earth
	var mu := sys.mu[e]
	var tops := MissionOps.target_ops("comet")
	var d := float(tops.get("distance_km", 4500000.0)) * 1000.0
	var cruise := maxf(float(tops.get("cruise_weeks", 6)), 1.0) * WEEK
	var cd := comet_dir(sys, t_ins + cruise)
	var u := (cd - n * cd.dot(n)).normalized()
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


## Moves a track's launch to time t0 (its path rebuilt by the same rules from there): a live
## launch leaves at the calendar's moment, not at the start of its week.
static func retime(tr: Dictionary, t0: float) -> void:
	if tr.has("ins_t") or is_equal_approx(float(tr.get("launch_t", 0.0)), t0):
		return
	var nb := build(String(tr["owner"]), String(tr["id"]), String(tr.get("code", "")), String(tr.get("type", "")),
		String(tr.get("target", "leo")), String(tr.get("outcome", "full")), t0)
	tr["launch_t"] = nb["launch_t"]
	tr["lost_t"] = nb["lost_t"]
	tr["legs"] = nb["legs"]


## The flight really flown (FlightSim, a CareerFlight) puts the track on its own path: from the
## state (r, v around the Earth at time t) where the ascent ended, the parking orbit and what
## follows are rebuilt with the same rules, so the map and the 3D view share one path. A
## suborbital hop falls from where its engines stopped.
static func rebase(tr: Dictionary, r: PackedFloat64Array, v: PackedFloat64Array, t: float) -> void:
	var sys := FlightSolar.get_system()
	var e := sys.earth
	var mu := sys.mu[e]
	var re := sys.radius[e]
	var target := String(tr.get("target", "leo"))
	var legs: Array = []
	tr["ins_t"] = t
	if target == "suborbital":
		var c := FlightConic.from_state(r, v, mu, t)
		var t_land := c.time_to_radius(re, t + 1.0, false)
		if t_land == INF:
			t_land = t + 600.0
		var l0 := _leg("ballistic", "earth", t, r, v, "flight")
		l0["t1"] = t_land
		legs.append(l0)
		var land := c.state_at(t_land)
		var lp := Vector3(land[0], land[1], land[2]).normalized() * re
		legs.append(_leg("fixed", "earth", t_land, _p(lp), _p(Vector3.ZERO), "arrived"))
		tr["legs"] = legs
		return
	var park := _leg("orbit", "earth", t, r, v, "orbit")
	legs.append(park)
	var park_c := FlightConic.from_state(r, v, mu, t)
	var n := Vector3(park_c.wx, park_c.wy, park_c.wz).normalized()
	if park_c.e < 1.0:
		_after_park(legs, park, park_c, n, target, String(tr.get("outcome", "full")), t, sys, String(tr.get("id", "")))
	tr["legs"] = legs


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
	if t < float(tr.get("ins_t", float(tr["launch_t"]) + ASCENT_S)):
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
	# a transfer starts at its periapsis (the burn): samples bunch up there, where it turns fastest
	var ease := 2.6 if String(l["kind"]) == "transfer" and not closed else 1.0
	out.resize((steps + 1) * 3)
	for k in steps + 1:
		var p := c.position_at(lerpf(t0, t1, pow(float(k) / steps, ease)))
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
		# an orbiter or a flyby aims a little inside the Moon's path (a pass, not a hit); landers hit it
		var inj := lunar_injection(sys, c, t + 45.0, 6.0e6 if target in ["lunar_orbit", "lunar_flyby"] else 0.0)
		var sd0 := c.state_at(float(inj["t"]))
		var vt: Vector3 = inj["v"]
		return {"t": float(inj["t"]), "dv": vt - Vector3(sd0[3], sd0[4], sd0[5]), "to": "moon"}
	elif target == "comet":
		var tops := MissionOps.target_ops("comet")
		var d := float(tops.get("distance_km", 4500000.0)) * 1000.0
		var v_inf := d / (maxf(float(tops.get("cruise_weeks", 6)), 1.0) * WEEK)
		var rp := FlightOrbit.length(r)
		var ecc := 1.0 + rp * v_inf * v_inf / mu
		var cd := comet_dir(sys, t + maxf(float(tops.get("cruise_weeks", 6)), 1.0) * WEEK)
		var u := (cd - n * cd.dot(n)).normalized()
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
