class_name TycoonState
extends RefCounted
## Serializable state of one Cometworks campaign (GDD section 19): calendar, the player's
## agency (cash, reputation, hype, staff), the rival agencies and the shared world. Pure data
## + rules, no scene access, so it runs headless in tests. Every random draw comes from `rng`
## seeded with `campaign_seed`: the same seed and the same commands give the same campaign.

signal changed
signal week_passed(year: int, week: int)
signal month_passed(year: int, month: int)
signal year_passed(year: int)
signal era_changed(era: int)
signal building_finished(lot_id: String, level: int)
## A mission project left the pad. `result`: {"project_id", "code", "type", "target", "grade",
## "success" (bool), "outcome" ("fail" | "partial" | "full" | "exceptional"), "contract_id"}
signal mission_launched(result: Dictionary)
## A mission ended its operations (or was lost), same keys as mission_launched plus "science".
signal mission_completed(result: Dictionary)
## The player or a rival took a race milestone (GDD section 13).
signal milestone_claimed(milestone_id: String, by: String)

const RULES_PATH := "res://data/tycoon/rules.json"
const BUILDINGS_PATH := "res://data/tycoon/buildings.json"
const PROFESSIONS_PATH := "res://data/tycoon/professions.json"
const MISSIONS_PATH := "res://data/tycoon/missions.json"

var rules: Dictionary = {}
## data/tycoon/buildings.json
var bdata: Dictionary = {}
## data/tycoon/professions.json (the 7 professions, GDD section 9)
var pdata: Dictionary = {}
## data/tycoon/missions.json (mission targets and types, GDD section 6)
var mdata: Dictionary = {}
var campaign_seed := 0
var rng := RandomNumberGenerator.new()
## weeks since the start of the campaign (0 = year 1, week 1)
var weeks := 0
var cash := 0.0
var reputation := 0.0
var hype := 0.0
var agency_name := "Cometworks"
## staff: [{"id", "name", "profession", "level" 1..6, "xp", "skill" 0..1, "curiosity" 0..1,
## "courage" 0..1, "morale" 0..100, "variant", "assigned" (project id or "")}], see normalize_staff()
var staff: Array[Dictionary] = []
## rivals: [{"id", "name_key", "color", "capacity", "milestones"}]
var rivals: Array[Dictionary] = []
var milestones := 0
## active mission projects (E1 fills these): [{"code", "kind", "phase", "progress", "color"}]
var projects: Array[Dictionary] = []
## contract offers and accepted contracts (owned by the contract board):
## [{"id", "type", "target", "sponsor_key", "reward", "bonus", "penalty", "deadline_week",
##   "min_bars": {"sci": 6.0, ...}, "status": "offer" | "accepted" | "done" | "failed"}]
var contracts: Array[Dictionary] = []
## missions in space (owned by mission ops): [{"id", "code", "type", "target", "start_week",
##   "weeks_total", "data_stored", "data_down", "science", "status": "cruise" | "ops" | "done" | "lost"}]
var active_missions: Array[Dictionary] = []
## research points waiting to be spent (owned by research)
var research_points := 0.0
## unlocked research: tech id -> true (owned by research)
var unlocked: Dictionary = {}
## news ticker lines (translation key + args), newest first
var news: Array[Dictionary] = []
## campus: lot id -> {"kind", "level" (built), "target" (level being built), "weeks_left"}
var buildings: Dictionary = {}


static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("TycoonState: cannot read %s" % path)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func load_rules() -> Dictionary:
	return load_json(RULES_PATH)


func _load_data() -> void:
	rules = load_rules()
	bdata = load_json(BUILDINGS_PATH)
	pdata = load_json(PROFESSIONS_PATH)
	mdata = load_json(MISSIONS_PATH)


static func new_campaign(p_seed: int, roster_staff: Array[Dictionary] = []) -> TycoonState:
	var s := TycoonState.new()
	s._load_data()
	s.campaign_seed = p_seed
	s.rng.seed = p_seed
	var st: Dictionary = s.rules.get("start", {})
	s.cash = float(st.get("cash", 300000))
	s.reputation = float(st.get("reputation", 20))
	s.hype = float(st.get("hype", 5))
	s.agency_name = String(st.get("agency_name", "Cometworks"))
	s.staff = roster_staff.duplicate(true)
	for i in s.staff.size():
		s.staff[i] = s.normalize_staff(s.staff[i], i)
	for r: Dictionary in s.rules.get("rivals", []):
		var rv := r.duplicate()
		rv["milestones"] = 0
		s.rivals.append(rv)
	for lot_id: String in s.bdata.get("lots", {}):
		var lot: Dictionary = s.bdata["lots"][lot_id]
		if lot.get("start", false):
			s.buildings[lot_id] = {"kind": lot["kind"], "level": 1, "target": 1, "weeks_left": 0}
	s.news.append({"key": "TY_NEWS_WELCOME", "args": []})
	return s


# ------------------------------------------------------------ calendar
func weeks_per_year() -> int:
	return int(rules.get("weeks_per_year", 52))


func year() -> int:
	return weeks / weeks_per_year() + 1


func week() -> int:
	return weeks % weeks_per_year() + 1


## Month 1..12 of week index w (0-based within the year).
func _month_of(w: int) -> int:
	return int(float(w % weeks_per_year()) / weeks_per_year() * 12.0) + 1


func campaign_weeks() -> int:
	return int(rules.get("campaign_years", 25)) * weeks_per_year()


## Weeks left until the comet passes (end of the last campaign year).
func comet_weeks_left() -> int:
	return maxi(campaign_weeks() - weeks, 0)


func is_over() -> bool:
	return weeks >= campaign_weeks()


## Era 1..5: five years each (GDD section 4).
func era() -> int:
	return clampi((year() - 1) / 5 + 1, 1, 5)


# ------------------------------------------------------------ campus (lots and buildings)
func lot_ids() -> Array:
	return bdata.get("lots", {}).keys()


func lot_kind(lot_id: String) -> String:
	return String(bdata.get("lots", {}).get(lot_id, {}).get("kind", ""))


func building(lot_id: String) -> Dictionary:
	return buildings.get(lot_id, {})


func building_type(kind: String) -> Dictionary:
	return bdata.get("types", {}).get(kind, {})


## Cost and weeks of the next level on a lot (level 1 includes the lot price):
## {"cost", "weeks", "level"}; {} when the lot is at the top level or building.
func next_level(lot_id: String) -> Dictionary:
	var lot: Dictionary = bdata.get("lots", {}).get(lot_id, {})
	if lot.is_empty():
		return {}
	var b := building(lot_id)
	if int(b.get("weeks_left", 0)) > 0:
		return {}
	var lv := int(b.get("level", 0))
	var levels: Array = building_type(lot["kind"]).get("levels", [])
	if lv >= levels.size():
		return {}
	var cost := float(levels[lv]["cost"])
	var wk := int(levels[lv]["weeks"])
	if lv == 0:
		cost = float(lot.get("first_level_cost", cost)) + float(lot.get("price", 0))
		wk = int(lot.get("first_level_weeks", wk))
	return {"cost": cost, "weeks": maxi(wk, 1), "level": lv + 1}


func can_build(lot_id: String) -> bool:
	var nx := next_level(lot_id)
	return not nx.is_empty() and cash >= float(nx["cost"])


## Starts building the next level on a lot (pays now). Returns false if not possible.
func build(lot_id: String) -> bool:
	if not can_build(lot_id):
		return false
	var nx := next_level(lot_id)
	cash -= float(nx["cost"])
	var b := building(lot_id).duplicate()
	if b.is_empty():
		b = {"kind": lot_kind(lot_id), "level": 0}
	b["target"] = nx["level"]
	b["weeks_left"] = nx["weeks"]
	b["total_weeks"] = nx["weeks"]
	buildings[lot_id] = b
	changed.emit()
	return true


func monthly_upkeep() -> float:
	var f := float(bdata.get("upkeep_month_fraction", 0.02))
	var total := 0.0
	for lot_id: String in buildings:
		var b: Dictionary = buildings[lot_id]
		var levels: Array = building_type(b["kind"]).get("levels", [])
		for i in mini(int(b.get("level", 0)), levels.size()):
			total += float(levels[i]["cost"]) * f
	return total


func _advance_construction() -> void:
	for lot_id: String in buildings:
		var b: Dictionary = buildings[lot_id]
		if int(b.get("weeks_left", 0)) <= 0:
			continue
		b["weeks_left"] = int(b["weeks_left"]) - 1
		if b["weeks_left"] == 0:
			b["level"] = b["target"]
			news.push_front({"key": "TY_NEWS_BUILT", "args": [building_type(b["kind"]).get("name_key", ""), b["level"]]})
			building_finished.emit(lot_id, int(b["level"]))


# ------------------------------------------------------------ economy (E0: salaries, hype)
func monthly_salaries() -> float:
	var base := float(rules.get("salary_month_base", 4000))
	var step := float(rules.get("salary_level_step", 0.25))
	var total := 0.0
	for m in staff:
		var mult := float(profession(String(m.get("profession", ""))).get("salary_mult", 1.0))
		total += base * (1.0 + step * (int(m.get("level", 1)) - 1)) * mult
	return total


# ------------------------------------------------------------ staff and mission vocabulary
func profession(id: String) -> Dictionary:
	for p: Dictionary in pdata.get("professions", []):
		if p["id"] == id:
			return p
	return {}


func mission_type(id: String) -> Dictionary:
	for t: Dictionary in mdata.get("types", []):
		if t["id"] == id:
			return t
	return {}


func mission_target(id: String) -> Dictionary:
	for t: Dictionary in mdata.get("targets", []):
		if t["id"] == id:
			return t
	return {}


## Can a new project use this mission type / target? (The research module refines this
## with its tech tree; until then the era gates it.)
func mission_type_available(id: String) -> bool:
	var t := mission_type(id)
	return not t.is_empty() and era() >= int(t.get("era", 1))


func mission_target_available(id: String) -> bool:
	var t := mission_target(id)
	return not t.is_empty() and era() >= int(t.get("era", 1))


## A mission project tied to a contract ended (owned by the contract board: pays the reward
## and bonus, or the penalty). Stub until the contract board lands.
func complete_contract(_contract_id: String, _grade: float, _success: bool) -> void:
	pass


## Fills the staff fields every system relies on (see `staff`), mapping the crew roster's
## pilot / engineer / scientist roles to professions. Values already set are kept.
func normalize_staff(m: Dictionary, index := 0) -> Dictionary:
	var out := m.duplicate(true)
	if not out.has("profession"):
		var map: Dictionary = pdata.get("roster_role_map", {})
		out["profession"] = String(map.get(String(out.get("role", "")), "systems_engineer"))
	if not out.has("id"):
		out["id"] = "s%d" % index
	var defaults := {"name": "Cometling", "level": 1, "xp": 0.0, "skill": 0.5, "curiosity": 0.5, "courage": 0.5,
		"morale": 70.0, "variant": 0, "assigned": ""}
	for k: String in defaults:
		if not out.has(k):
			out[k] = defaults[k]
	out["level"] = int(out["level"])
	out["variant"] = int(out["variant"])
	return out


## One week of simulation. Monthly bills and hype decay on month changes.
func advance_week() -> void:
	if is_over():
		return
	var m0 := _month_of(weeks)
	var era0 := era()
	weeks += 1
	_advance_construction()
	week_passed.emit(year(), week())
	var m1 := _month_of(weeks)
	if m1 != m0:
		cash -= monthly_salaries() + monthly_upkeep()
		hype = maxf(hype * (1.0 - float(rules.get("hype_decay_month", 0.03))), 0.0)
		month_passed.emit(year(), m1)
	if week() == 1:
		year_passed.emit(year())
	if era() != era0:
		news.push_front({"key": "TY_NEWS_ERA", "args": [era()]})
		era_changed.emit(era())
	changed.emit()


# ------------------------------------------------------------ race
func milestones_total() -> int:
	return int(rules.get("milestones_total", 15))


## Race standing: [{"name_key" or "name", "color", "progress" 0..1, "player"}], player first.
func race_board() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"name": agency_name, "color": CwPalette.IGNITION,
		"progress": float(milestones) / milestones_total(), "player": true}]
	for r in rivals:
		out.append({"name_key": r["name_key"], "color": Color(String(r["color"])),
			"progress": float(r["milestones"]) / milestones_total(), "player": false})
	return out


# ------------------------------------------------------------ save / load
func to_dict() -> Dictionary:
	return {"version": 1, "seed": campaign_seed, "rng_state": rng.state, "weeks": weeks, "cash": cash,
		"reputation": reputation, "hype": hype, "agency_name": agency_name, "staff": staff, "rivals": rivals,
		"milestones": milestones, "projects": projects, "news": news, "buildings": buildings,
		"contracts": contracts, "active_missions": active_missions, "research_points": research_points,
		"unlocked": unlocked}


static func from_dict(d: Dictionary) -> TycoonState:
	var s := TycoonState.new()
	s._load_data()
	s.campaign_seed = int(d.get("seed", 0))
	s.rng.seed = s.campaign_seed
	s.rng.state = int(d.get("rng_state", s.rng.state))
	s.weeks = int(d.get("weeks", 0))
	s.cash = float(d.get("cash", 0.0))
	s.reputation = float(d.get("reputation", 0.0))
	s.hype = float(d.get("hype", 0.0))
	s.agency_name = String(d.get("agency_name", "Cometworks"))
	s.staff.assign(d.get("staff", []))
	for i in s.staff.size():
		s.staff[i] = s.normalize_staff(s.staff[i], i)
	s.rivals.assign(d.get("rivals", []))
	s.milestones = int(d.get("milestones", 0))
	s.projects.assign(d.get("projects", []))
	s.news.assign(d.get("news", []))
	s.contracts.assign(d.get("contracts", []))
	s.active_missions.assign(d.get("active_missions", []))
	s.research_points = float(d.get("research_points", 0.0))
	s.unlocked = d.get("unlocked", {})
	s.buildings = d.get("buildings", {})
	for lot_id: String in s.buildings:  # JSON numbers come back as floats
		var b: Dictionary = s.buildings[lot_id]
		for k in ["level", "target", "weeks_left"]:
			b[k] = int(b.get(k, 0))
	return s
