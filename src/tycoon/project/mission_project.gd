class_name MissionProject
extends RefCounted
## One mission project in development (GDD section 6): a target x a mission type, optionally
## for an accepted contract, worked on by a team of Cometlings through 3 phases (concept,
## build and integration, flight preparation), each a third of the weeks. At the start of
## each phase the player splits the team's time between 3 sliders (percents summing to 100);
## every week each Cometling turns that time into points on the 4 bars (GDD 6.5), plus
## defects. When the weeks run out the project gets its grade (0..10) and goes to launch
## (ProjectDesk). Pure data + rules: the state is passed in, nothing here touches a scene.

var id := ""
var code := ""
var type_id := ""
var target_id := ""
var contract_id := ""
var staff_ids: Array[String] = []
var start_week := 0
var weeks_total := 3
var weeks_done := 0
## 0..2 (concept, build, flight prep)
var phase := 0
## 3 phases x 3 sliders, integer percents summing to 100
var sliders: Array = [[34, 33, 33], [34, 33, 33], [34, 33, 33]]
## points on eng / sci / ops / rel
var pts: Array[float] = [0.0, 0.0, 0.0, 0.0]
var defects := 0.0
var cost_spent := 0.0
## extra XP from the ground-crew training slider, per assigned Cometling
var training_xp := 0.0
## the phase screen has not confirmed this phase's sliders yet
var awaiting_sliders := true
## the rocket (E2, RocketDesigner / RocketFamilies): {"family": family id, "parts": {slot: component}}
var rocket: Dictionary = {}
## the Design Review after development (DesignReview): "" developing, "waiting" for the
## player's decision, "fixing" (the chosen fixes, then the launch), "rebuild" (a new rocket is
## being built, then the review again), "pad" (a rocket built in the hangar waits on the pad for
## the player's launch choice: pilot it or simulate it, ProjectDesk.launch)
var review_state := ""
## weeks left of "fixing" or "rebuild"
var review_weeks := 0
## the risks fixed in the review (DesignReview risk ids)
var review_fixes: Array[String] = []
## the briefing this project answers ("" for a free project or a contract; BriefingDesk) and the
## offer's terms it took: {"reward", "budget", "deadline", "client"}
var briefing_id := ""
var briefing_terms: Dictionary = {}
## the modules it carries (PayloadRules ids: instruments, power, comms, heater, recorder)
var payload: Array[String] = []


# ------------------------------------------------------------ queries
func mission_type(state: TycoonState) -> Dictionary:
	return state.mission_type(type_id)


## The ideal balance of the bars: the briefing client's own when it has one, else the type's.
## Hidden from the player until the journal reveals it (Discovery.ratio_known).
func ideal(state: TycoonState) -> Array[float]:
	var r: Array = mission_type(state).get("ratio", [0.25, 0.25, 0.25, 0.25])
	var br := BriefingDesk.ratio(BriefingDesk.briefing(briefing_id))
	if br.size() == 4:
		r = br
	var out: Array[float] = [0.25, 0.25, 0.25, 0.25]
	for b in mini(4, r.size()):
		out[b] = float(r[b])
	return out


## The payload, or the Cometlings' starter kit for projects that have none (old saves, tests).
func payload_or_default(state: TycoonState) -> Array[String]:
	if not payload.is_empty():
		return payload
	return PayloadRules.default_payload(state, type_id, target_id)


func total_points() -> float:
	return pts[0] + pts[1] + pts[2] + pts[3]


func fractions() -> Array[float]:
	return fractions_of(pts)


static func fractions_of(p: Array) -> Array[float]:
	var t := 0.0
	for v in p:
		t += float(v)
	var out: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if t <= 0.0:
		return out
	for b in 4:
		out[b] = float(p[b]) / t
	return out


func progress() -> float:
	return clampf(float(weeks_done) / maxi(weeks_total, 1), 0.0, 1.0)


func is_done() -> bool:
	return weeks_done >= weeks_total


func phase_values(k := -1) -> Array:
	return sliders[clampi(phase if k < 0 else k, 0, 2)]


func compat(state: TycoonState) -> float:
	return ProjectRules.compat(mission_type(state), target_id)


func team(state: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in state.staff:
		if String(m.get("id", "")) in staff_ids:
			out.append(m)
	return out


# ------------------------------------------------------------ weekly points (GDD 6.5)
## Points one Cometling makes in a week on each bar with the given slider percents of phase k:
## 10 * (0.4 + 0.6 skill) * (0.6 + 0.4 morale) * (1 + 0.08 level) * affinity(prof, b)
##    * focus(b, phase, sliders) * building bonus. A Cometling below 30 morale naps: 0.
static func member_points(state: TycoonState, m: Dictionary, k: int, values: Array) -> Array[float]:
	var out: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var p := ProjectRules.section("points")
	var morale := float(m.get("morale", 70.0))
	if morale < float(p.get("nap_morale", 30.0)) or not TycoonCrew.is_working(m):
		return out
	var sf := float(p.get("skill_floor", 0.4))
	var mf := float(p.get("morale_floor", 0.6))
	var base := float(p.get("base", 10.0)) * (sf + (1.0 - sf) * float(m.get("skill", 0.5))) \
		* (mf + (1.0 - mf) * morale / 100.0) * (1.0 + float(p.get("level_step", 0.08)) * int(m.get("level", 1))) \
		* float(p.get("building_bonus", 1.0))
	var fractions_k: Array = []
	for v in values:
		fractions_k.append(float(v) / 100.0)
	var f := ProjectRules.focus(k, fractions_k)
	var prof := state.profession(String(m.get("profession", "")))
	for b in 4:
		out[b] = base * ProjectRules.affinity(prof, ProjectRules.BARS[b], state.pdata) * f[b] \
			* TycoonCrew.points_mult(m, ProjectRules.BARS[b])
	return out


## Ideal team size for this mission type: ceil(size * team_per_size), at least 1.
func ideal_team(state: TycoonState) -> int:
	return maxi(ceili(float(mission_type(state).get("size", 1.0)) * ProjectRules.num("points", "team_per_size", 4.0) - 0.001), 1)


## Share of a full member's work each Cometling gives when the team is bigger than the
## project needs (too many cooks): (ideal + extra * 0.4) / n; 1.0 up to the ideal size.
func team_efficiency(state: TycoonState) -> float:
	var n := staff_ids.size()
	var ideal_n := ideal_team(state)
	if n <= ideal_n:
		return 1.0
	return (ideal_n + (n - ideal_n) * ProjectRules.num("points", "overstaff_efficiency", 0.4)) / n


## Points the team would make in one week of phase k with these sliders (no side effects).
func week_points(state: TycoonState, k: int, values: Array) -> Array[float]:
	var out: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var eff := team_efficiency(state)
	for m in team(state):
		var mp := member_points(state, m, k, values)
		for b in 4:
			out[b] += mp[b] * eff
	return out


## A copy of this project run to the end of its current phase with these sliders (the phase
## screen's live preview: bars and defects). Work is deterministic, so this is exact; the
## state is only read.
func simulate_phase(state: TycoonState, values: Array) -> MissionProject:
	var sim := MissionProject.from_dict(to_dict())
	sim.sliders[sim.phase] = [int(values[0]), int(values[1]), int(values[2])]
	var k := sim.phase
	while not sim.is_done() and sim.phase == k:
		sim.work_week(state)
	return sim


## Weeks of the current phase not yet worked.
func phase_weeks_left() -> int:
	return maxi(ProjectRules.phase_end(weeks_total, phase) - weeks_done, 0)


## One week of work: points, defects, training XP. Returns true when the phase changed
## (the caller asks the player for the new sliders).
func work_week(state: TycoonState) -> bool:
	var values: Array = phase_values()
	var d := ProjectRules.section("defects")
	var week: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var removing := 0.0
	var tester := String(d.get("tester_profession", "test_technician"))
	var eff := team_efficiency(state)
	for m in team(state):
		var mp := member_points(state, m, phase, values)
		for b in 4:
			mp[b] *= eff
			week[b] += mp[b]
		removing += mp[ProjectRules.REL] * (float(d.get("tester_removal_mult", 2.0))
			if String(m.get("profession", "")) == tester else 1.0)
	var week_total := week[0] + week[1] + week[2] + week[3]
	for b in 4:
		pts[b] += week[b]
	var rel_frac := fractions()[ProjectRules.REL]
	# defeitos += 0.04 * soma(pts da semana) * (1 - 0.5 * fracao_conf)
	defects += float(d.get("per_point", 0.04)) * week_total * (1.0 - float(d.get("rel_fraction_relief", 0.5)) * rel_frac)
	# defeitos -= 0.10 * pts[Conf] da semana * (slider de testes ativo ? 1 : 0.3)
	defects -= float(d.get("removal_per_rel_point", 0.10)) * removing \
		* (1.0 if tests_active(phase, values) else float(d.get("removal_without_tests", 0.3)))
	defects = maxf(defects, 0.0)
	var sl := ProjectRules.sliders(phase)
	for s in mini(sl.size(), values.size()):
		if (sl[s] as Dictionary).get("extra_xp", false):
			training_xp += ProjectRules.num("rewards", "training_xp_per_week", 8.0) * float(values[s]) / 100.0
	weeks_done += 1
	if not is_done() and weeks_done >= ProjectRules.phase_end(weeks_total, phase):
		phase = mini(phase + 1, 2)
		awaiting_sliders = true
		return true
	return false


## Is a defect-removing slider (environmental tests, readiness review) on in phase k?
static func tests_active(k: int, values: Array) -> bool:
	var sl := ProjectRules.sliders(k)
	for s in mini(sl.size(), values.size()):
		if (sl[s] as Dictionary).get("removes_defects", false) and float(values[s]) > 0.0:
			return true
	return false


# ------------------------------------------------------------ grade (GDD 6.5)
## Points the agency is expected to put into this kind of project now: E_era * size *
## (1 + 0.1 * recent projects of the same type) * (1 + 0.03 per grade point of the best
## recent grade above 5). The expectation rises with the eras and with repeats.
static func expected_points(state: TycoonState, p_type_id: String, history: Array) -> float:
	var g := ProjectRules.section("grade")
	var window := int(g.get("repeat_window_weeks", 104))
	var repeats := 0
	var best := 0.0
	for h: Dictionary in history:
		if state.weeks - int(h.get("week", 0)) > window:
			continue
		if String(h.get("type", "")) == p_type_id:
			repeats += 1
		# the project grade, not the mission's: a rocket failure does not lower what is expected
		best = maxf(best, ProjectDesk.project_grade(h))
	var size := float(state.mission_type(p_type_id).get("size", 1.0))
	return ProjectRules.expectation_era(state.era()) * size * (1.0 + float(g.get("repeat_step", 0.1)) * repeats) \
		* (1.0 + float(g.get("best_grade_step", 0.03)) * maxf(best - float(g.get("best_grade_pivot", 5.0)), 0.0))


## Ratio match m = 1 - 0.5 * sum_b |fraction_b - ideal_b| (1 = the ideal balance).
static func ratio_match(frac: Array, ideal_r: Array) -> float:
	var s := 0.0
	for b in 4:
		s += absf(float(frac[b]) - float(ideal_r[b]))
	return clampf(1.0 - ProjectRules.num("grade", "match_penalty", 0.5) * s, 0.0, 1.0)


## The grade formula of GDD 6.5 on raw numbers (kept separate so the test covers it):
##   q = min(total / expected, 1.5);  m = ratio match
##   grade = 10 * clamp(0.55 * q / 1.5 + 0.45 * m, 0, 1) * compat - 0.6 * defects / max(total / 100, 1)
## The GDD writes the first term as 0.55*q/1.5*1.5; read literally that is 0.55*q, which caps
## every competent project at 10, so q is normalised by its cap (q / 1.5) as the comment
## "volume de trabalho vs expectativa" intends. Weights live in data/tycoon/projects.json.
static func grade_of(points: Array, ideal_r: Array, expected: float, compat_mult: float, residual_defects: float) -> float:
	var g := ProjectRules.section("grade")
	var total := 0.0
	for v in points:
		total += float(v)
	if total <= 0.0 or compat_mult <= 0.0:
		return 0.0
	var cap := float(g.get("q_cap", 1.5))
	var q := minf(total / maxf(expected, 0.001), cap)
	var m := ratio_match(fractions_of(points), ideal_r)
	var core := clampf(float(g.get("q_weight", 0.55)) * q / cap + float(g.get("match_weight", 0.45)) * m, 0.0, 1.0)
	var grade := 10.0 * core * compat_mult - float(g.get("defect_penalty", 0.6)) * residual_defects / maxf(total / 100.0, 1.0)
	return clampf(grade, 0.0, 10.0)


func grade(state: TycoonState, history: Array) -> float:
	return grade_of(pts, ideal(state), expected_points(state, type_id, history), compat(state), residual_defects())


## The defects left at launch: the Design Review's extra readiness review (fix "payload")
## cuts them to rockets.json review.payload_fix_defects.
func residual_defects() -> float:
	if "payload" in review_fixes:
		return defects * float(RocketDesigner.section("review").get("payload_fix_defects", 0.4))
	return defects


## Each bar on the 0..10 scale (contracts ask for minimums like Science >= 6): the bar's
## points against what the expectation asks of it with the ideal ratio, with 25% headroom.
func bar_scores(state: TycoonState, history: Array) -> Array[float]:
	var e := expected_points(state, type_id, history)
	var idl := ideal(state)
	var head := ProjectRules.num("grade", "bar_score_headroom", 1.25)
	var out: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for b in 4:
		out[b] = clampf(10.0 * pts[b] / maxf(e * idl[b] * head, 0.001), 0.0, 10.0)
	return out


# ------------------------------------------------------------ save / load
func to_dict() -> Dictionary:
	return {"id": id, "code": code, "type": type_id, "target": target_id, "contract_id": contract_id,
		"staff_ids": staff_ids, "start_week": start_week, "weeks_total": weeks_total, "weeks_done": weeks_done,
		"phase": phase, "sliders": sliders, "pts": pts, "defects": defects, "cost_spent": cost_spent,
		"training_xp": training_xp, "awaiting_sliders": awaiting_sliders, "rocket": rocket,
		"review_state": review_state, "review_weeks": review_weeks, "review_fixes": review_fixes,
		"briefing_id": briefing_id, "briefing_terms": briefing_terms, "payload": payload}


static func from_dict(d: Dictionary) -> MissionProject:
	var p := MissionProject.new()
	p.id = String(d.get("id", ""))
	p.code = String(d.get("code", p.id))
	p.type_id = String(d.get("type", ""))
	p.target_id = String(d.get("target", ""))
	p.contract_id = String(d.get("contract_id", ""))
	for s in d.get("staff_ids", []):
		p.staff_ids.append(String(s))
	p.start_week = int(d.get("start_week", 0))
	p.weeks_total = int(d.get("weeks_total", 3))
	p.weeks_done = int(d.get("weeks_done", 0))
	p.phase = int(d.get("phase", 0))
	var sl: Array = d.get("sliders", [])
	for k in mini(sl.size(), 3):
		var row: Array = sl[k]
		p.sliders[k] = [int(row[0]), int(row[1]), int(row[2])]
	var pp: Array = d.get("pts", [])
	for b in mini(pp.size(), 4):
		p.pts[b] = float(pp[b])
	p.defects = float(d.get("defects", 0.0))
	p.cost_spent = float(d.get("cost_spent", 0.0))
	p.training_xp = float(d.get("training_xp", 0.0))
	p.awaiting_sliders = bool(d.get("awaiting_sliders", false))
	var rk: Dictionary = d.get("rocket", {})
	if not rk.is_empty():
		p.rocket = {"family": String(rk.get("family", "")), "parts": (rk.get("parts", {}) as Dictionary).duplicate()}
	p.review_state = String(d.get("review_state", ""))
	p.review_weeks = int(d.get("review_weeks", 0))
	for f in d.get("review_fixes", []):
		p.review_fixes.append(String(f))
	p.briefing_id = String(d.get("briefing_id", ""))
	p.briefing_terms = (d.get("briefing_terms", {}) as Dictionary).duplicate()
	for m in d.get("payload", []):
		p.payload.append(String(m))
	return p
