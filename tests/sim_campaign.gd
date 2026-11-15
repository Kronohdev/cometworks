extends SceneTree
## Headless campaign simulation for the balancing pass: a bot plays whole 25-year campaigns
## through the same commands the screens use (research, buildings, hiring, specialisations,
## contracts, briefings, mission projects with their sliders, loans) and prints what the team
## asked to look at in docs/equipe/cometworks_equipe.md, "Balanceamento":
##   money per era, the press expectation against the points teams really make, the rivals'
##   milestone timings (Aurora's failures, Quietude at the comet), and how long a fair-mode
##   ("modo feira") campaign runs on a presentation.
## Not a pass / fail test: a report. It always ends with "RESULT: PASS" unless a campaign
## breaks (a script error stops it first), so it can run with the others.
##
## Bots (all play the race: milestones first, then briefings and contracts that pay):
##   good     the sliders with the best projected grade, up to 3 projects at once, avoids
##            repeating a mission type the press is tired of
##   average  a random slider set among the better quarter, up to 2 projects at once
##   fair     the "average" player at the fair: one project at a time, acts only when the game
##            would pause anyway (every 4 weeks of 1 s, and at every phase screen)
##   grinder  the greedy exploit check: any contract that pays, as many projects as people allow
##   spender  the loan abuser: spends down to nothing (no reserve), builds and hires on credit,
##            as many projects as people allow, takes every loan (checks Bankruptcy bites)
## Run: godot --headless --path . --script res://tests/sim_campaign.gd [-- seeds=4 bots=good,average,fair diff=normal]
##   seeds=N        campaigns per bot (seeds 1..N, default 4); seed0=K starts at seed K
##   bots=a,b       which bots (default good,average,fair,grinder,spender)
##   diff=a,b       difficulty levels (default normal; easy,normal,hard for all three)
##   verbose=1      one line per launch
## Bankruptcy (src/tycoon/finance/bankruptcy.gd) is on: a campaign can end early. The report
## counts the warnings, emergency loans and bankruptcies, and how close each bot came to the line.

const PLAYER := "player"
## techs whose research year the report shows
const TRACK_TECHS := ["upper_stage", "crew_capsule", "lunar_stage", "life_support", "crewed_lander", "comet_rendezvous"]
## real seconds the fair-mode presenter spends on each kind of stop (estimates for the report)
const STOP_SECONDS := {"phase": 12.0, "review": 10.0, "launch": 14.0, "front_page": 6.0, "ops": 8.0,
	"new_project": 25.0, "research": 6.0, "hire": 8.0, "build": 5.0, "contract": 6.0}
## building order of the bot: [lot, level]
const BUILD_ORDER := [["lab", 1], ["training", 1], ["hq", 2], ["antenna", 1], ["lab", 2], ["factory", 1],
	["control", 1], ["training", 2], ["antenna", 2], ["hq", 3], ["workshop", 2], ["factory", 2], ["lab", 3],
	["pad", 2], ["antenna", 3], ["control", 2], ["pad2", 1], ["workshop", 3], ["factory", 3], ["training", 3]]

var _seeds := 4
var _seed0 := 1
var _bots: Array[String] = ["good", "average", "fair", "grinder", "spender"]
var _diffs: Array[String] = ["normal"]
var _verbose := false
var _bot := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"seeds":
				_seeds = maxi(int(kv[1]), 1)
			"seed0":
				_seed0 = int(kv[1])
			"bots":
				_bots.assign(kv[1].split(","))
			"diff":
				_diffs.assign(kv[1].split(","))
			"verbose":
				_verbose = kv[1] == "1"
	var t0 := Time.get_ticks_msec()
	for diff in _diffs:
		for bot in _bots:
			var runs: Array[Dictionary] = []
			for sd in range(_seed0, _seed0 + _seeds):
				runs.append(play(sd, bot, diff))
			report(bot, diff, runs)
	print("\n(%d campaigns in %.1f s)" % [_seeds * _bots.size() * _diffs.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	print("RESULT: PASS")
	quit(0)


# ------------------------------------------------------------ one campaign
func play(seed_value: int, bot: String, diff: String) -> Dictionary:
	var roster := CrewRoster.new()
	roster.autosave = false
	roster.seed_default(CrewRoster.DEFAULT_SIZE, 2026 + seed_value)
	var staff: Array[Dictionary] = []
	for m in roster.members:
		staff.append({"id": m.id, "name": m.display_name, "role": m.role, "variant": m.variant,
			"level": int(m.experience / 100.0) + 1, "xp": m.experience, "skill": m.skill,
			"curiosity": m.curiosity, "courage": m.courage})
	var s := _new_campaign(seed_value, staff, diff)
	var lr := RandomNumberGenerator.new()
	lr.seed = seed_value
	TycoonLeader.found(s, TycoonLeader.make_default(lr))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bot:%d:%s" % [seed_value, bot])
	_bot = bot
	var ctx := {"bot": bot, "rng": rng, "stops": {}, "projects": 0, "neg_weeks": 0, "min_cash": s.cash,
		"loans": 0, "era_cash": [], "era_rows": [], "launches": [], "tech_weeks": {}, "line_ratio": 0.0, "month_ratio": 0.0,
		"warnings": 0, "emergency_year": 0, "bankrupt_year": 0, "bankrupt_reason": ""}
	s.cash_warning.connect(func(_l: int) -> void: ctx["warnings"] = int(ctx["warnings"]) + 1)
	s.emergency_loan.connect(func(_i: Dictionary) -> void: ctx["emergency_year"] = s.year())
	s.bankrupt.connect(func(i: Dictionary) -> void:
		ctx["bankrupt_year"] = s.year()
		ctx["bankrupt_reason"] = String(i.get("reason", "")))
	var every := 4 if bot == "fair" else 1
	var era0 := s.era()
	while not s.is_over() and not Bankruptcy.is_bankrupt(s):
		if s.weeks % every == 0:
			_manage(s, ctx)
		_sliders(s, ctx)
		var n_hist := s.project_history.size()
		var issue0 := _issue(s)
		var month0 := s._month_of(s.weeks)
		s.advance_week()
		if s._month_of(s.weeks) != month0:   # a month end: what the bankruptcy line looks at
			ctx["month_ratio"] = minf(float(ctx["month_ratio"]), s.cash / Bankruptcy.threshold(s))
		for i in range(n_hist, s.project_history.size()):
			var h: Dictionary = s.project_history[i]
			_stop(ctx, "review")
			_stop(ctx, "launch")
			(ctx["launches"] as Array).append(h)
			if _verbose:
				print("    y%02d %-14s %-13s grade %.1f q %.2f %s" % [s.year(), h["type"], h["target"], float(h["grade_project"]),
					_total(h["pts"]) / maxf(float(h["expected"]), 0.001), h["outcome"]])
		for i in _issue(s) - issue0:
			_stop(ctx, "front_page")
		s.race.pending_pages.clear()
		if s.cash < 0.0:
			ctx["neg_weeks"] = int(ctx["neg_weeks"]) + 1
		ctx["min_cash"] = minf(float(ctx["min_cash"]), s.cash)
		ctx["line_ratio"] = minf(float(ctx["line_ratio"]), s.cash / Bankruptcy.threshold(s))
		for tid in TRACK_TECHS:
			if not (ctx["tech_weeks"] as Dictionary).has(tid) and TycoonResearch.is_done(s, tid):
				ctx["tech_weeks"][tid] = s.weeks
		if _verbose and s.week() == 1:
			_year_ledger(s)
		if s.era() != era0 or s.is_over() or Bankruptcy.is_bankrupt(s):
			_era_row(s, ctx, era0)
			era0 = s.era()
	for m in s.mission_archive:
		if String(m.get("event", "")) != "":
			_stop(ctx, "ops")
	ctx["state"] = s
	ctx["score"] = s.race.score() if s.race.final_result.is_empty() else s.race.final_result
	return ctx


func _new_campaign(seed_value: int, staff: Array[Dictionary], diff: String) -> TycoonState:
	return TycoonState.new_campaign(seed_value, staff, diff)


## Number of the newest front page printed (0 before the first).
static func _issue(s: TycoonState) -> int:
	return int(s.race.pages[0].get("issue", 0)) if not s.race.pages.is_empty() else 0


func _era_row(s: TycoonState, ctx: Dictionary, era: int) -> void:
	var rivals := {}
	for r in s.rivals:
		rivals[String(r["id"])] = int(r["milestones"])
	var lv := 0.0
	for m in s.staff:
		lv += int(m.get("level", 1))
	(ctx["era_rows"] as Array).append({"era": era, "level": lv / maxf(s.staff.size(), 1.0), "cash": s.cash, "staff": s.staff.size(), "rep": s.reputation,
		"hype": s.hype, "milestones": s.milestones, "rivals": rivals, "loan": TycoonFinance.has_loan(s)})


func _year_ledger(s: TycoonState) -> void:
	var ledger: Array = TycoonFinance.fs(s)["ledger"]
	var ins := {}
	var outs := {}
	for i in range(maxi(ledger.size() - 12, 0), ledger.size()):
		var mo: Dictionary = ledger[i]
		for k: String in mo["in"]:
			ins[k] = float(ins.get(k, 0.0)) + float(mo["in"][k])
		for k: String in mo["out"]:
			outs[k] = float(outs.get(k, 0.0)) + float(mo["out"][k])
	var line := "  year %2d cash %s rep %.0f staff %d |" % [s.year() - 1, _cr(s.cash), s.reputation, s.staff.size()]
	for k: String in ins:
		line += " +%s %s" % [k, _cr(float(ins[k]))]
	line += " |"
	for k: String in outs:
		line += " -%s %s" % [k, _cr(float(outs[k]))]
	print(line)


func _stop(ctx: Dictionary, kind: String) -> void:
	var st: Dictionary = ctx["stops"]
	st[kind] = int(st.get(kind, 0)) + 1


static func _total(pts: Variant) -> float:
	var t := 0.0
	for v in pts:
		t += float(v)
	return t


# ------------------------------------------------------------ the bot
func _manage(s: TycoonState, ctx: Dictionary) -> void:
	if TycoonFinance.can_take_loan(s) and s.cash < 0.0:
		if TycoonFinance.take_loan(s):
			ctx["loans"] = int(ctx["loans"]) + 1
	_research(s, ctx)
	_specs(s)
	_build(s, ctx)
	_hire(s, ctx)
	_contracts(s, ctx)
	_projects(s, ctx)


func _reserve(s: TycoonState) -> float:
	if _bot == "spender":
		return 0.0   # no cushion at all: the loans will sort it out
	return 4.0 * (s.monthly_salaries() + s.monthly_upkeep()) + 60000.0


## The milestones the player can still take (requirements held), with the value of taking them.
func _open_milestones(s: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var share := float(s.race.mdata.get("second_share", 0.3))
	for m: Dictionary in s.race.milestones:
		if s.race.has_claimed(m["id"], PLAYER) or not s.race._requires_met(m, PLAYER):
			continue
		var first := s.race.first_of(m["id"]).is_empty()
		var v := float(m.get("prize", 0)) * (1.0 if first else share) + float(m.get("rep", 0)) * 15000.0 + float(m.get("hype", 0)) * 4000.0
		if bool(m.get("victory", false)):
			v += 5000000.0
		out.append({"m": m, "value": v})
	return out


func _research(s: TycoonState, ctx: Dictionary) -> void:
	if TycoonResearch.active(s) != "" or not TycoonResearch.queue(s).is_empty():
		return
	var wanted := {}
	for om in _open_milestones(s):
		for c: Dictionary in (om["m"] as Dictionary).get("conditions", []):
			for t in c.get("types", []):
				wanted["type:" + String(t)] = true
			for t in c.get("targets", []):
				wanted["target:" + String(t)] = true
	var best := ""
	var best_score := -INF
	for t: Dictionary in TycoonResearch.techs():
		var id := String(t["id"])
		if not TycoonResearch.can_research(s, id):
			continue
		var score := -float(t["era"]) * 400.0 - float(t["cost"])
		var u: Dictionary = t.get("unlocks", {})
		for k in ["types", "targets"]:
			for x in u.get(k, []):
				if wanted.has(("type:" if k == "types" else "target:") + String(x)):
					score += 900.0  # the race: what opens an open milestone comes first
		if (t.get("effects", {}) as Dictionary).has("pp_mult"):
			score += 200.0
		if score > best_score:
			best_score = score
			best = id
	if best != "" and TycoonResearch.fund(s, best):
		_stop(ctx, "research")


func _specs(s: TycoonState) -> void:
	for m in s.staff:
		for slot in TycoonCrew.spec_slots(s, m):
			if not slot["can_choose"]:
				continue
			var opts := _spec_options(s, m, int(slot["tier"]))
			if opts.is_empty() or s.cash < TycoonCrew.spec_cost(s, m) + _reserve(s):
				continue
			# the newest specialisation the research opened first (they come later and are stronger)
			var pick: Dictionary = opts[opts.size() - 1]
			TycoonCrew.choose_spec(s, String(m["id"]), String(pick["id"]))


func _spec_options(s: TycoonState, m: Dictionary, tier: int) -> Array[Dictionary]:
	return TycoonCrew.spec_options(m, tier, s)


func _build(s: TycoonState, ctx: Dictionary) -> void:
	for lot_id: String in s.buildings:
		if int(s.buildings[lot_id].get("weeks_left", 0)) > 0:
			return  # one construction at a time
	for e in BUILD_ORDER:
		var lot := String(e[0])
		var lv := int(e[1])
		if int(s.building(lot).get("level", 0)) >= lv:
			continue
		var nx := s.next_level(lot)
		if nx.is_empty() or int(nx["level"]) != lv:
			continue
		if s.cash - float(nx["cost"]) > _reserve(s) * 2.0 + 100000.0:
			if s.build(lot):
				_stop(ctx, "build")
		return


func _hire(s: TycoonState, ctx: Dictionary) -> void:
	if s.staff.size() >= TycoonCrew.staff_limit(s):
		return
	var want := mini(TycoonCrew.staff_limit(s), 5 + 3 * s.era())
	if s.staff.size() >= want:
		return
	var have := {}
	for m in s.staff:
		var p := String(m.get("profession", ""))
		have[p] = int(have.get(p, 0)) + 1
	var target := {"researcher": TycoonResearch.lab_seats(s), "pilot": 1 if s.era() < 2 else 2,
		"systems_engineer": 2, "propulsion_engineer": 1 + s.era() / 3, "scientist": 2, "flight_controller": 1 + s.era() / 3,
		"test_technician": 1 + s.era() / 3}
	var best := ""
	var best_gap := -99
	for c: Dictionary in TycoonCrew.candidates(s):
		var p := String(c["profession"])
		var gap := int(target.get(p, 1)) - int(have.get(p, 0))
		if gap > best_gap:
			best_gap = gap
			best = String(c["id"])
	if best == "" or best_gap <= 0 and s.cash < 3000000.0:
		return
	var c := TycoonCrew.find_candidate(s, best)
	if s.cash - TycoonCrew.hire_fee(s, c) < _reserve(s) * 2.0:
		return
	if TycoonCrew.hire(s, best) == "":
		_stop(ctx, "hire")


## Contract offers are accepted when a project starts for them (_projects): a player takes
## only the work they can begin now.
func _contracts(_s: TycoonState, _ctx: Dictionary) -> void:
	pass


func _has_free(s: TycoonState, profession: String) -> bool:
	for m in ProjectDesk.free_staff(s):
		if String(m.get("profession", "")) == profession and TycoonCrew.is_working(m):
			return true
	return false


## Picks the best mission it can start now and starts it (as long as people are free).
func _projects(s: TycoonState, ctx: Dictionary) -> void:
	for attempt in 3:
		var free := _free_workers(s)
		var cap := maxi(1, s.staff.size() / 4)
		match String(ctx["bot"]):
			"fair":
				cap = 1
			"average":
				cap = mini(cap, 2)
			"good":
				cap = mini(cap, 3)
		if free.size() < 2 or s.mission_projects.size() >= cap:
			return
		var best := {}
		var best_score := -INF
		for cand in _candidates(s):
			if float(cand["score"]) > best_score:
				best_score = float(cand["score"])
				best = cand
		if best.is_empty() or best_score <= 0.0:
			return
		var team := _team(s, String(best["type"]), free)
		if team.is_empty():
			return
		if String(best.get("offer", "")) != "":
			if not TycoonContracts.accept(s, String(best["offer"])):
				return
			best["contract"] = String(best["offer"])
			_stop(ctx, "contract")
		var plan := {}
		if String(best.get("briefing", "")) != "":
			plan = {"briefing_id": String(best["briefing"]), "payload": _briefing_payload(s, String(best["briefing"]),
				String(best["type"]), String(best["target"]))}
		var p := ProjectDesk.start_project(s, String(best["type"]), String(best["target"]), team, String(best.get("contract", "")), {}, plan)
		if p == null and not plan.is_empty():
			plan["payload"] = []
			p = ProjectDesk.start_project(s, String(best["type"]), String(best["target"]), team, String(best.get("contract", "")), {}, plan)
		if p == null:
			return
		ctx["projects"] = int(ctx["projects"]) + 1
		_stop(ctx, "new_project")
		_set_sliders(s, p, ctx)


func _free_workers(s: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seats := TycoonResearch.lab_seats(s) if int(s.building("lab").get("level", 0)) > 0 else 0
	var kept := 0
	for m in ProjectDesk.free_staff(s):
		if not TycoonCrew.is_working(m) or float(m.get("morale", 70.0)) < 50.0 or int(m.get("busy_weeks", 0)) >= 6:
			continue  # tired: a player lets them rest
		if String(m.get("profession", "")) == "researcher" and kept < seats:
			kept += 1  # the lab keeps its researchers
			continue
		out.append(m)
	return out


func _candidates(s: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var open := _open_milestones(s)
	var busy_contracts := {}
	for p: MissionProject in s.mission_projects:
		busy_contracts[p.contract_id] = true
	var briefs := {}
	for o in BriefingDesk.offers(s):
		var b := BriefingDesk.briefing(String(o["id"]))
		briefs["%s|%s" % [BriefingDesk.best_type(b), BriefingDesk.best_target(b)]] = o
	var flying := {}
	for p: MissionProject in s.mission_projects:
		flying[p.type_id + "|" + p.target_id] = true
	var reserve := _reserve(s)
	var fair := String(_bot) == "fair"
	var grinder := String(_bot) in ["grinder", "spender"]
	# how often each type flew in the press's memory (the expectation rises with repeats)
	var repeats := {}
	var window := int(ProjectRules.section("grade").get("repeat_window_weeks", 104))
	for h: Dictionary in s.project_history:
		if s.weeks - int(h.get("week", 0)) <= window:
			repeats[String(h["type"])] = int(repeats.get(String(h["type"]), 0)) + 1
	for p: MissionProject in s.mission_projects:
		repeats[p.type_id] = int(repeats.get(p.type_id, 0)) + 1
	for t: Dictionary in s.mdata.get("types", []):
		var ty := String(t["id"])
		if not s.mission_type_available(ty):
			continue
		for tg: String in t.get("compat", {}):
			if not s.mission_target_available(tg) or float(t["compat"][tg]) <= 0.0:
				continue
			if not RocketDesigner.reachable(s, ty, tg):
				continue
			var est := ProjectDesk.estimate(s, ty, {}, tg)
			var cost := float(est["total"]) + PayloadRules.cost(PayloadRules.default_payload(s, ty, tg))
			if s.cash - cost < reserve:
				continue
			var key := ty + "|" + tg
			var value := 0.0
			var contract := ""
			for c in TycoonContracts.accepted(s):
				if String(c["type"]) == ty and String(c["target"]) == tg and not busy_contracts.has(String(c["id"])):
					value += float(c["reward"]) * 1.3   # plus the bonus and the penalty avoided
					contract = String(c["id"])
					break
			var offer := ""
			if contract == "" and (not fair or s.cash < reserve * 3.0):
				for c in TycoonContracts.offers(s):
					if String(c["type"]) == ty and String(c["target"]) == tg and TycoonContracts.can_accept(s, String(c["id"])) 							and float(c["reward"]) * 1.2 > value:
						value = float(c["reward"]) * 1.2
						offer = String(c["id"])
			var briefing := ""
			if briefs.has(key) and contract == "" and offer == "":
				value += float(briefs[key]["reward"])
				briefing = String(briefs[key]["id"])
			if not flying.has(key):
				for om in open:
					for c: Dictionary in (om["m"] as Dictionary).get("conditions", []):
						var types: Array = c.get("types", [])
						var targets: Array = c.get("targets", [])
						if (types.is_empty() or ty in types) and (targets.is_empty() or tg in targets):
							value += float(om["value"]) * (0.6 if String(c.get("on", "")) == "completed" else 0.8)
							break
			if value <= 0.0:
				continue
			if not grinder:
				value *= pow(0.6, int(repeats.get(ty, 0)))  # a player avoids what the press finds stale
			out.append({"type": ty, "target": tg, "score": value - cost * 0.9, "contract": contract, "briefing": briefing,
				"offer": offer})
	return out


func _team(s: TycoonState, type_id: String, free: Array[Dictionary]) -> Array:
	var mt := s.mission_type(type_id)
	var ratio: Array = mt.get("ratio", [0.25, 0.25, 0.25, 0.25])
	var scored: Array = []
	for m in free:
		var prof := s.profession(String(m.get("profession", "")))
		var v := 0.0
		for b in 4:
			v += float(ratio[b]) * ProjectRules.affinity(prof, ProjectRules.BARS[b], s.pdata)
		v *= 0.4 + 0.6 * float(m.get("skill", 0.5))
		scored.append({"id": String(m["id"]), "v": v, "pilot": String(m.get("profession", "")) == "pilot"})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["v"]) > float(b["v"]))
	var n := maxi(ceili(float(mt.get("size", 1.0)) * ProjectRules.num("points", "team_per_size", 4.0) - 0.001), 1)
	var out: Array = []
	if ProjectRules.is_crewed(type_id):
		for e in scored:
			if e["pilot"]:
				out.append(e["id"])
				break
		if out.is_empty():
			return []
	for e in scored:
		if out.size() >= n:
			break
		if not (e["id"] in out):
			out.append(e["id"])
	return out


func _briefing_payload(s: TycoonState, briefing_id: String, ty: String, tg: String) -> Array:
	var out: Array = PayloadRules.default_payload(s, ty, tg)
	for m in BriefingDesk.needs(BriefingDesk.briefing(briefing_id)):
		if not (String(m) in out) and PayloadRules.is_available(s, String(m)):
			out = PayloadRules.toggle(out, String(m))
	return out


# ------------------------------------------------------------ sliders
func _sliders(s: TycoonState, ctx: Dictionary) -> void:
	for p: MissionProject in s.mission_projects:
		if p.awaiting_sliders and p.review_state == "":
			_set_sliders(s, p, ctx)


func _set_sliders(s: TycoonState, p: MissionProject, ctx: Dictionary) -> void:
	_stop(ctx, "phase")
	var seen := {}
	var ranked: Array = []
	# a coarse pass (steps of 20), then the neighbours of the best (steps of 10)
	for a in range(0, 101, 20):
		for b in range(0, 101 - a, 20):
			_try(s, p, [a, b, 100 - a - b], seen, ranked)
	ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["g"]) > float(y["g"]))
	var top: Array = ranked[0]["v"]
	for d in [[10, -10, 0], [-10, 10, 0], [10, 0, -10], [-10, 0, 10], [0, 10, -10], [0, -10, 10]]:
		var v := [int(top[0]) + d[0], int(top[1]) + d[1], int(top[2]) + d[2]]
		if v.min() >= 0:
			_try(s, p, v, seen, ranked)
	ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["g"]) > float(y["g"]))
	var pick: Array = ranked[0]["v"]
	if String(ctx["bot"]) != "good":
		var rng: RandomNumberGenerator = ctx["rng"]
		pick = ranked[rng.randi_range(0, maxi(ranked.size() / 4 - 1, 0))]["v"]
	ProjectDesk.set_sliders(s, p.id, pick)


func _try(s: TycoonState, p: MissionProject, v: Array, seen: Dictionary, ranked: Array) -> void:
	var k := "%d/%d/%d" % v
	if seen.has(k):
		return
	seen[k] = true
	var sim := p.simulate_to_end(s, v)
	ranked.append({"v": v, "g": sim.grade(s, s.project_history) + 4.0 * DesignReview.payload_chance(s, sim)})


# ------------------------------------------------------------ report
func report(bot: String, diff: String, runs: Array[Dictionary]) -> void:
	print("\n================ bot %s · difficulty %s · %d campaigns ================" % [bot, diff, runs.size()])
	# money per era
	print("money at the end of each era (median of the campaigns), staff, reputation, milestones player / rivals:")
	for e in 5:
		var cash: Array[float] = []
		var staff: Array[float] = []
		var rep: Array[float] = []
		var ms: Array[float] = []
		var rv: Array[float] = []
		var lvl: Array[float] = []
		for r in runs:
			var rows: Array = r["era_rows"]
			if e < rows.size():
				var row: Dictionary = rows[e]
				cash.append(float(row["cash"]))
				staff.append(float(row["staff"]))
				lvl.append(float(row["level"]))
				rep.append(float(row["rep"]))
				ms.append(float(row["milestones"]))
				var best_r := 0
				for id: String in row["rivals"]:
					best_r = maxi(best_r, int(row["rivals"][id]))
				rv.append(best_r)
		print("  era %d: cash %s (min %s)  staff %.0f (level %.1f)  rep %.0f  milestones %.1f / best rival %.1f" % [e + 1,
			_cr(_median(cash)), _cr(_min(cash)), _median(staff), _median(lvl), _median(rep), _median(ms), _median(rv)])
	var min_cash: Array[float] = []
	var neg: Array[float] = []
	var loans := 0
	for r in runs:
		min_cash.append(float(r["min_cash"]))
		neg.append(float(r["neg_weeks"]))
		loans += int(r["loans"])
	print("  lowest cash: median %s, worst %s · weeks in the red: median %.0f · loans taken: %d" % [
		_cr(_median(min_cash)), _cr(_min(min_cash)), _median(neg), loans])
	var ratio: Array[float] = []
	var mratio: Array[float] = []
	var warned := 0
	var emerg: Array[String] = []
	var broke: Array[String] = []
	for r in runs:
		ratio.append(float(r["line_ratio"]))
		mratio.append(float(r["month_ratio"]))
		warned += 1 if int(r["warnings"]) > 0 else 0
		if int(r["emergency_year"]) > 0:
			emerg.append("y%d" % int(r["emergency_year"]))
		if int(r["bankrupt_year"]) > 0:
			broke.append("y%d %s" % [int(r["bankrupt_year"]), r["bankrupt_reason"]])
	print("  bankruptcy: closest to the line (cash / X; -1 = on it) any week median %.2f worst %.2f, at month ends median %.2f worst %.2f · warned in %d of %d · emergency loans %d %s · bankrupt %d %s" % [
		_median(ratio), _min(ratio), _median(mratio), _min(mratio), warned, runs.size(), emerg.size(), str(emerg), broke.size(), str(broke)])
	# press expectation vs points
	print("press expectation vs the points teams made (per era, all launches):")
	for e in range(1, 6):
		var q: Array[float] = []
		var gd: Array[float] = []
		var ok := 0
		var n := 0
		var team: Array[float] = []
		var pmw: Array[float] = []
		var emw: Array[float] = []
		for r in runs:
			for h: Dictionary in r["launches"]:
				var era := clampi((int(h["week"]) / 52) / 5 + 1, 1, 5)
				if era != e:
					continue
				n += 1
				q.append(_total(h["pts"]) / maxf(float(h["expected"]), 0.001))
				gd.append(float(h["grade_project"]))
				team.append((h["staff"] as Array).size())
				var tw := maxf((h["staff"] as Array).size() * float(h["weeks"]), 1.0)
				pmw.append(_total(h["pts"]) / tw)
				var ideal := maxf(ceilf(float(r["state"].mission_type(String(h["type"])).get("size", 1.0)) * 4.0 - 0.001), 1.0)
				emw.append(float(h["expected"]) / (ideal * float(h["weeks"])))
				if bool(h["success"]):
					ok += 1
		if n == 0:
			print("  era %d: no launches" % e)
			continue
		print("  era %d: %3d launches (%.1f / campaign)  q = points / expected: median %.2f  grade %.1f  team %.1f  success %d%%" % [
			e, n, float(n) / runs.size(), _median(q), _median(gd), _median(team), roundi(100.0 * ok / n)])
		print("         points per member-week %.2f, the expectation asks %.2f of an ideal team" % [_median(pmw), _median(emw)])
	# milestones
	print("race milestones: median year of the first claim, by whom (P = player, A/N/Q rivals), player median year:")
	var ms0: Array = runs[0]["state"].race.milestones
	for m: Dictionary in ms0:
		var first_years: Array[float] = []
		var who := {}
		var py: Array[float] = []
		for r in runs:
			var race: RaceDirector = (r["state"] as TycoonState).race
			var f := race.first_of(m["id"])
			if not f.is_empty():
				first_years.append(int(f["week"]) / 52 + 1)
				var by := String(f["by"])
				who[by] = int(who.get(by, 0)) + 1
			for c: Dictionary in race.claims[m["id"]]:
				if String(c["by"]) == PLAYER:
					py.append(int(c["week"]) / 52 + 1)
		var who_s := ""
		for by: String in who:
			who_s += "%s%d " % ["P" if by == PLAYER else by.substr(0, 1).to_upper(), int(who[by])]
		print("  %-18s plausible %2d-%2d  first: y%s  %-14s player: %d/%d took it, y%s" % [m["id"], int(m["years"][0]),
			int(m["years"][1]), _yr(_median(first_years)), who_s, py.size(), runs.size(), _yr(_median(py))])
	var tl := "research done (median year):"
	for tid in TRACK_TECHS:
		var ys: Array[float] = []
		for r in runs:
			if (r["tech_weeks"] as Dictionary).has(tid):
				ys.append(int(r["tech_weeks"][tid]) / 52 + 1)
		tl += "  %s y%s (%d/%d)" % [tid, _yr(_median(ys)), ys.size(), runs.size()]
	print(tl)
	# rivals
	var tries := {}
	var fails := {}
	for r in runs:
		var race: RaceDirector = (r["state"] as TycoonState).race
		for id: String in race.ai:
			fails[id] = int(fails.get(id, 0)) + int(race.ai[id]["fails"])
			tries[id] = int(tries.get(id, 0)) + int(race.ai[id]["fails"]) + race.claims_of(id).size()
	var line := "rival attempts that failed:"
	for id: String in tries:
		line += "  %s %d/%d (%d%%)" % [id, int(fails[id]), int(tries[id]), roundi(100.0 * int(fails[id]) / maxi(int(tries[id]), 1))]
	print(line)
	var qy: Array[float] = []
	var pcy: Array[float] = []
	var q_before := 0
	for r in runs:
		var race: RaceDirector = (r["state"] as TycoonState).race
		var qw := -1
		var pw := -1
		for c: Dictionary in race.claims["comet_rendezvous"]:
			if String(c["by"]) == "quietude":
				qw = int(c["week"])
			if String(c["by"]) == PLAYER:
				pw = int(c["week"])
		if qw >= 0:
			qy.append(qw / 52 + 1)
		if pw >= 0:
			pcy.append(pw / 52 + 1)
		if qw >= 0 and (pw < 0 or qw < pw):
			q_before += 1
	print("comet: Quietude got there in %d/%d (median y%s), the player in %d/%d (median y%s); Quietude first in %d/%d" % [
		qy.size(), runs.size(), _yr(_median(qy)), pcy.size(), runs.size(), _yr(_median(pcy)), q_before, runs.size()])
	# score
	var tot: Array[float] = []
	var rank: Array[float] = []
	for r in runs:
		tot.append(float(r["score"]["total"]))
		rank.append(float(r["score"]["rank"]))
	print("final score: median %.0f (min %.0f, max %.0f) · rank median %.0f of 4" % [_median(tot), _min(tot), _max(tot), _median(rank)])
	# fair-mode timing
	var secs: Array[float] = []
	var stops_total := {}
	for r in runs:
		var t := 1300.0  # 25 years x 52 weeks x 1 s
		for k: String in r["stops"]:
			t += float(STOP_SECONDS.get(k, 5.0)) * int(r["stops"][k])
			stops_total[k] = int(stops_total.get(k, 0)) + int(r["stops"][k])
		secs.append(t)
	var stop_line := ""
	for k: String in stops_total:
		stop_line += "%s %.0f  " % [k, float(stops_total[k]) / runs.size()]
	print("stops per campaign: %s" % stop_line)
	print("fair-mode wall time estimate (1 s per week + stops): median %.0f min (min %.0f, max %.0f)" % [
		_median(secs) / 60.0, _min(secs) / 60.0, _max(secs) / 60.0])


static func _cr(v: float) -> String:
	if absf(v) >= 1000000.0:
		return "%.2fM" % (v / 1000000.0)
	return "%.0fk" % (v / 1000.0)


static func _yr(v: float) -> String:
	return "--" if is_nan(v) else "%02d" % roundi(v)


static func _median(a: Array[float]) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	var n := b.size()
	return b[n / 2] if n % 2 == 1 else (b[n / 2 - 1] + b[n / 2]) * 0.5


static func _min(a: Array[float]) -> float:
	return NAN if a.is_empty() else a.min()


static func _max(a: Array[float]) -> float:
	return NAN if a.is_empty() else a.max()
