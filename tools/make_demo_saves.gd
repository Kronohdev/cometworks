extends SceneTree
## Makes the demonstration saves (res://data/demo_saves/tycoon_demo_*.json, TycoonSave.DEMOS)
## from a real campaign: one TycoonState is played week by week with TycoonState.advance_week()
## (rivals, budget, crew, research, projects, operations: the same code as the game) by a
## simple autopilot that plays like a careful player: it hires up to the HQ's limit, builds the
## campus in a sensible order, funds research, picks specialisations, answers mission decisions
## with the default choice and flies the missions of the race (sounding, first satellite, Moon
## probes, crewed flights...) with the default rocket. Launches are forced to succeed
## (ProjectDesk.dev_force_outcome) so the demo agency keeps up with the race; a tech of an era
## already over that the lab did not reach in time is finished when the next era starts.
## A save is written at week 1 of each era (years 1, 6, 11, 16, 21) and a fair-mode start.
##
## Run it again after changing the rules, the data or the save format:
##   godot --headless --path . --script res://tools/make_demo_saves.gd
## then check with: godot --headless --path . --script res://tests/test_demo_saves.gd

const SEED := 2026
const LEADER_SEED := 7
const RESERVE := 150000.0
## The race missions the autopilot flies, in order: [type, target, the milestones it is for].
const PLAN := [
	["sounding", "suborbital", ["suborbital"]],
	["demo_sat", "leo", ["first_satellite"]],
	["earth_obs", "sso", []],
	["comms", "geo", ["long_signal"]],
	["orbiter", "lunar_orbit", ["probe_moon", "far_side"]],
	["lander", "lunar_surface", ["robotic_landing"]],
	["orbiter", "lunar_pole", ["polar_ice"]],
	["rover", "lunar_pole", ["polar_ice"]],
	["crewed_flight", "leo", ["cometling_space", "cometling_orbit"]],
	["crewed_flight", "lunar_flyby", ["crewed_flyby"]],
	["crewed_landing", "lunar_surface", ["crewed_landing"]],
]
## The order a careful player builds in: [lot, level].
const BUILD := [["lab", 1], ["control", 1], ["antenna", 1], ["hq", 2], ["training", 1], ["workshop", 2],
	["lab", 2], ["factory", 1], ["control", 2], ["pad", 2], ["antenna", 2], ["training", 2], ["hq", 3],
	["lab", 3], ["workshop", 3], ["factory", 2], ["pad2", 1], ["control", 3], ["antenna", 3], ["pad", 3],
	["training", 3], ["factory", 3], ["pad2", 2]]

var _flown := {}
var _last_err := {}
var _log: Array[String] = []


func _initialize() -> void:
	TranslationServer.set_locale("pt")   # pt-BR first: Portuguese names for the leader and the crew
	var rng := RandomNumberGenerator.new()
	rng.seed = LEADER_SEED
	var leader := TycoonLeader.make_default(rng)
	leader["name"] = TycoonLeader.random_name(rng, "pt")
	var s := _new_state(leader)
	_write(s, "demo_fair", true)
	_write(s, "demo_era1", false)
	var wpy := s.weeks_per_year()
	for era in range(2, 6):
		var target := (era - 1) * 5 * wpy
		while s.weeks < target:
			_autopilot(s)
			s.advance_week()
		_catch_up(s, era)
		_write(s, "demo_era%d" % era, false)
	ProjectDesk.dev_force_outcome = ""
	for line in _log:
		print(line)
	print("DEMO SAVES DONE")
	quit(0)


func _new_state(leader: Dictionary) -> TycoonState:
	var s := TycoonState.new_campaign(SEED, _first_crew())
	TycoonLeader.found(s, leader)
	TycoonCrew.ensure(s)
	return s


## The agency's first employees from a fresh roster with a fixed seed (the game takes the
## player's own roster, user://crew_roster.json; the demo must not depend on it).
func _first_crew() -> Array[Dictionary]:
	var roster := CrewRoster.new()
	roster.autosave = false
	roster.seed_default(CrewRoster.DEFAULT_SIZE, SEED)
	var out: Array[Dictionary] = []
	for m in roster.members:
		out.append({"id": m.id, "name": m.display_name, "role": m.role, "variant": m.variant,
			"level": int(m.experience / 100.0) + 1, "xp": m.experience, "skill": m.skill,
			"curiosity": m.curiosity, "courage": m.courage})
	return out


## Writes a slot as the player would find it: the newspapers of the past already read and the
## opening story seen.
func _write(s: TycoonState, slot: String, fair: bool) -> void:
	s.race.pending_pages.clear()
	for m in MissionOps.pending_decisions(s):
		MissionOps.decide(s, String(m["id"]), MissionOps.default_choice(String(m["event"])), true)
	if s.weeks > 0:
		s.story[Cutscenes.beat(Cutscenes.OPENING)] = true
	var err := TycoonSave.save(s, slot, {"fair_mode": fair, "demo": slot})
	_log.append("%s: %s, ano %d semana %d, era %d, caixa %d, marcos %d, equipe %d, pesquisas %d, projetos %d (%s)" % [
		slot, s.agency_name, s.year(), s.week(), s.era(), roundi(s.cash), s.milestones, s.staff.size(),
		_techs_done(s), s.project_history.size(), error_string(err)])


# ------------------------------------------------------------ the autopilot
func _autopilot(s: TycoonState) -> void:
	for m in MissionOps.pending_decisions(s):
		MissionOps.decide(s, String(m["id"]), MissionOps.default_choice(String(m["event"])), true)
	for p: MissionProject in s.mission_projects:
		if p.review_state == "waiting":
			ProjectDesk.confirm_review(s, p.id)
	if s.week() % 2 == 0:
		_specs(s)
		_research(s)
	if s.week() % 4 == 1:
		_hire(s)
		_build(s)
	_projects(s)
	_note_research(s)
	ProjectDesk.dev_force_outcome = "success"   # one launch only: set again every week


func _hire(s: TycoonState) -> void:
	for c: Dictionary in TycoonCrew.candidates(s).duplicate():
		if s.staff.size() >= TycoonCrew.staff_limit(s) or s.cash - TycoonCrew.hire_fee(s, c) < RESERVE * 2.0:
			return
		TycoonCrew.hire(s, String(c["id"]))


func _build(s: TycoonState) -> void:
	for step: Array in BUILD:
		var lot := String(step[0])
		var b := s.building(lot)
		if int(b.get("target", b.get("level", 0))) >= int(step[1]):
			continue
		var nx := s.next_level(lot)
		if nx.is_empty():
			return  # this lot is still building: wait for it, in order
		if s.cash - float(nx["cost"]) >= RESERVE * 2.0:
			s.build(lot)
		return


func _research(s: TycoonState) -> void:
	if TycoonResearch.active(s) != "":
		return
	# first what the next race missions need (and their prerequisites), then the cheapest
	for step: Array in PLAN:
		if _done(s, step[2]) and not (step[2] as Array).is_empty():
			continue
		for id in [TycoonResearch.tech_for_type(String(step[0])), TycoonResearch.tech_for_target(String(step[1]))]:
			var next := _researchable_towards(s, String(id))
			if next != "":
				TycoonResearch.fund(s, next)
				return
	var best := ""
	var best_key := 1.0e12
	for t: Dictionary in TycoonResearch.techs():
		var id := String(t["id"])
		if TycoonResearch.can_research(s, id):
			var key := float(t.get("era", 1)) * 10000.0 + float(t.get("cost", 0))
			if key < best_key:
				best_key = key
				best = id
	if best != "":
		TycoonResearch.fund(s, best)


## The tech itself if it can be researched now, else the first of its prerequisites that can.
func _researchable_towards(s: TycoonState, id: String) -> String:
	if id == "" or TycoonResearch.is_done(s, id):
		return ""
	if TycoonResearch.can_research(s, id):
		return id
	for p: String in TycoonResearch.tech(id).get("prereq", []):
		var r := _researchable_towards(s, p)
		if r != "":
			return r
	return ""


func _specs(s: TycoonState) -> void:
	for m in s.staff:
		if not TycoonCrew.spec_pending(s, m):
			continue
		var slots := TycoonCrew.spec_slots(s, m)
		var i: int = (m.get("specs", []) as Array).size()
		if i >= slots.size() or not slots[i]["can_choose"]:
			continue
		var opts := TycoonCrew.spec_options(m, int(slots[i]["tier"]))
		if not opts.is_empty() and s.cash - TycoonCrew.spec_cost(s, m) > RESERVE:
			TycoonCrew.choose_spec(s, String(m["id"]), String(opts[0]["id"]))


func _projects(s: TycoonState) -> void:
	if s.mission_projects.size() >= 2:
		return
	if _race_mission(s):
		return
	_briefing(s)


## The next race mission of PLAN the agency can fly and afford. True when the plan waits for
## money (a briefing would only delay it) or a project started.
func _race_mission(s: TycoonState) -> bool:
	for step: Array in PLAN:
		var key := "%s/%s" % [step[0], step[1]]
		if _flown.has(key) or _busy_with(s, key) or _done(s, step[2]):
			continue
		var team := _team(s, String(step[0]))
		if team.is_empty():
			return false
		var err := ProjectDesk.start_error(s, String(step[0]), String(step[1]), team)
		if err != _last_err.get(key, ""):
			_last_err[key] = err
			if OS.get_environment("DEMO_DEBUG") != "":
				var est0 := ProjectDesk.estimate(s, String(step[0]), {}, String(step[1]))
				_log.append("  ano %d semana %d: %s -> %s (caixa %d, custo %d)" % [s.year(), s.week(), key, err, roundi(s.cash), roundi(float(est0["total"]))])
		if err == "":
			var est := ProjectDesk.estimate(s, String(step[0]), {}, String(step[1]))
			if s.cash - float(est["total"]) < RESERVE:
				return false
			var p := ProjectDesk.start_project(s, String(step[0]), String(step[1]), team)
			if p:
				_flown[key] = true
				_log.append("  ano %d semana %d: %s (%s -> %s)" % [s.year(), s.week(), p.code, step[0], step[1]])
			return true
	return false


## A briefing from the board (the pedidos pay when they launch): its best type and target,
## the default payload plus what it needs.
func _briefing(s: TycoonState) -> void:
	for o: Dictionary in BriefingDesk.offers(s):
		var b := BriefingDesk.briefing(String(o["id"]))
		if b.is_empty() or not BriefingDesk.eligible(s, b):
			continue
		var ty := BriefingDesk.best_type(b)
		var tg := BriefingDesk.best_target(b)
		var team := _team(s, ty)
		if team.is_empty():
			return
		var payload := PayloadRules.default_payload(s, ty, tg)
		for m in BriefingDesk.needs(b):
			if String(m) not in payload:
				payload.append(String(m))
		var plan := {"briefing_id": String(o["id"]), "payload": payload}
		if ProjectDesk.start_error(s, ty, tg, team, {}, plan) != "":
			plan = {"briefing_id": String(o["id"])}
			if ProjectDesk.start_error(s, ty, tg, team, {}, plan) != "":
				continue
		var est := ProjectDesk.estimate(s, ty, {}, tg)
		if s.cash - float(est["total"]) - PayloadRules.cost(plan.get("payload", [])) < RESERVE:
			continue
		var p := ProjectDesk.start_project(s, ty, tg, team, "", {}, plan)
		if p:
			_log.append("  ano %d semana %d: %s pedido %s (%s -> %s)" % [s.year(), s.week(), p.code, o["id"], ty, tg])
			return


func _busy_with(s: TycoonState, key: String) -> bool:
	for p: MissionProject in s.mission_projects:
		if "%s/%s" % [p.type_id, p.target_id] == key:
			return true
	return false


func _done(s: TycoonState, milestones: Array) -> bool:
	if milestones.is_empty():
		return false
	for id: String in milestones:
		if not s.race.has_claimed(id, RaceDirector.PLAYER):
			return false
	return true


## Up to four free Cometlings who can work (a pilot first on crewed flights).
func _team(s: TycoonState, type_id: String) -> Array[String]:
	var free := ProjectDesk.free_staff(s).filter(func(m: Dictionary) -> bool: return TycoonCrew.is_working(m))
	var out: Array[String] = []
	if ProjectRules.is_crewed(type_id):
		for m: Dictionary in free:
			if String(m.get("profession", "")) == "pilot":
				out.append(String(m["id"]))
				break
		if out.is_empty():
			return out
	for m: Dictionary in free:
		if out.size() >= 4:
			break
		if String(m["id"]) not in out:
			out.append(String(m["id"]))
	return out


## The techs of the eras already over that the lab did not reach in time.
func _catch_up(s: TycoonState, era: int) -> void:
	var n := 0
	for pass_i in 4:   # prerequisites first
		for t: Dictionary in TycoonResearch.techs():
			var id := String(t["id"])
			if int(t.get("era", 1)) < era and not TycoonResearch.is_done(s, id) and TycoonResearch.prereqs_done(s, id):
				TycoonResearch.complete(s, id)
				n += 1
	if n > 0:
		_log.append("  era %d: %d pesquisa(s) de eras passadas concluídas na virada" % [era, n])


var _known_techs := {}


func _note_research(s: TycoonState) -> void:
	for t: Dictionary in TycoonResearch.techs():
		var id := String(t["id"])
		if not _known_techs.has(id) and TycoonResearch.is_done(s, id):
			_known_techs[id] = true
			_log.append("  ano %d semana %d: pesquisa %s" % [s.year(), s.week(), id])


func _techs_done(s: TycoonState) -> int:
	var n := 0
	for t: Dictionary in TycoonResearch.techs():
		if TycoonResearch.is_done(s, String(t["id"])):
			n += 1
	return n
