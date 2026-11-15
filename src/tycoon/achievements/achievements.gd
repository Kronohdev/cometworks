class_name Achievements
extends RefCounted
## Conquistas: the badges of data/tycoon/achievements.json, read from the real state of a
## campaign (TycoonState) and its events. Pure data + rules, no scene access (runs headless):
##   - stats(s): the numbers the conditions read (launches, firsts, photos, the best rover
##     drive, the Lendas hired...), all from state the game already keeps, plus the few events
##     no state remembers (flags: "Simular até o fim" pressed, a first taken after the fair's
##     tip, the bankruptcy)
##   - check(s): unlocks every achievement whose condition holds now. Hooked on the campaign
##     (attach: the state's changed, month_passed, milestone_claimed and bankrupt signals), so
##     nothing else calls it; note(s, flag) records an event and checks
##   - kept twice: per profile in user://achievements.cfg (across campaigns: when, the agency
##     and the campaign year) and per campaign in TycoonState.achievements ("unlocked": {id:
##     week}), so a save remembers what it earned; old saves start empty and earn what their
##     state already shows on load
##   - Achievements.events.unlocked(id, first_time) tells the HUD's toast (AchievementToast)
##   - campaign_stats(s): the Estatísticas page (StatsScreen): launches by outcome and era, Δv
##     flown, money in and out, reputation and hype over time, firsts, crew, photos, conferences
## Sub-state TycoonState.achievements = {"unlocked": {id: week}, "flags": {flag: count},
##   "samples": [[week, reputation, hype], ...] monthly, "earned", "spent" (ledger months
##   counted so far), "ledger_key" (the last ledger month counted), "since_week", "hired": {staff
##   id: true} (every Cometling hired, the ones let go too)}.
## Test scripts keep the profile in memory unless profile_path names a file.

## (id, first_time): first_time is true when the profile had not earned it before
class Events:
	extends RefCounted
	signal unlocked(id: String, first_time: bool)
	signal reset


const DATA_PATH := "res://data/tycoon/achievements.json"
const DEFAULT_PROFILE := "user://achievements.cfg"
const ICONS := "res://ui/cometworks/icons/%s.svg"
const SECTION := "unlocked"
const BEST := "best"
## monthly samples kept for the chart (25 years of months)
const KEEP_SAMPLES := 320

static var events: Events = Events.new()
## the profile file; "" = user://achievements.cfg in the game, memory only under test scripts
static var profile_path := ""
static var _data: Dictionary = {}
static var _profile: ConfigFile = null
static var _profile_from := "-"
static var _checking := false


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(DATA_PATH)
	return _data


static func all() -> Array:
	return data().get("achievements", [])


static func find(id: String) -> Dictionary:
	for a: Dictionary in all():
		if String(a.get("id", "")) == id:
			return a
	return {}


static func icon(a: Dictionary) -> Texture2D:
	var p := ICONS % String(a.get("icon", "star"))
	return load(p) as Texture2D if ResourceLoader.exists(p) else load(ICONS % "star") as Texture2D


static func color(a: Dictionary) -> Color:
	return Color(String(a.get("color", "#ffd25c")))


# ------------------------------------------------------------ the profile (across campaigns)
static func _scripted() -> bool:
	var ml := Engine.get_main_loop()
	return ml != null and ml.get_script() != null


static func _path() -> String:
	if profile_path != "":
		return profile_path
	return "" if _scripted() else DEFAULT_PROFILE


static func profile() -> ConfigFile:
	var p := _path()
	if _profile == null or _profile_from != p:
		_profile = ConfigFile.new()
		_profile_from = p
		if p != "" and FileAccess.file_exists(p):
			_profile.load(p)
	return _profile


static func _save_profile() -> void:
	var p := _path()
	if p != "":
		profile().save(p)


## The profile's record of an achievement: {"t" (unix time), "agency", "year"}; {} when locked.
static func profile_record(id: String) -> Dictionary:
	var v: Variant = profile().get_value(SECTION, id, {})
	return v if v is Dictionary else {}


static func is_unlocked(id: String) -> bool:
	return profile().has_section_key(SECTION, id)


## The best value the profile ever reached on an achievement's progress stat.
static func profile_best(id: String) -> float:
	return float(profile().get_value(BEST, id, 0.0))


static func unlocked_count() -> int:
	var n := 0
	for a: Dictionary in all():
		if is_unlocked(String(a["id"])):
			n += 1
	return n


## Forgets every achievement of the profile (the dev menu; campaigns keep their own notes
## unless `s` is given).
static func reset_profile(s: TycoonState = null) -> void:
	var cfg := profile()
	for sec in [SECTION, BEST]:
		if cfg.has_section(sec):
			cfg.erase_section(sec)
	_save_profile()
	if s:
		store(s)["unlocked"] = {}
	events.reset.emit()


# ------------------------------------------------------------ the campaign's notes
static func store(s: TycoonState) -> Dictionary:
	var st := s.achievements
	if not st.get("unlocked") is Dictionary:
		st["unlocked"] = {}
	if not st.get("flags") is Dictionary:
		st["flags"] = {}
	if not st.get("samples") is Array:
		st["samples"] = []
	for k in ["earned", "spent"]:
		st[k] = float(st.get(k, 0.0))
	st["ledger_key"] = int(st.get("ledger_key", -1))
	st["since_week"] = int(st.get("since_week", s.weeks))
	return st


static func campaign_unlocked(s: TycoonState) -> Dictionary:
	return store(s)["unlocked"]


static func flag(s: TycoonState, name: String) -> int:
	return int((store(s)["flags"] as Dictionary).get(name, 0))


## Hooks the campaign (TycoonState.new_campaign / from_dict; twice is harmless).
static func attach(s: TycoonState) -> void:
	if s.has_meta("achievements_hooked"):
		return
	s.set_meta("achievements_hooked", true)
	if (store(s)["samples"] as Array).is_empty():
		_sample(s)   # a new campaign (or a save from before): the first point of the chart
	var wr: WeakRef = weakref(s)
	s.changed.connect(func() -> void:
		var st := wr.get_ref() as TycoonState
		if st:
			check(st))
	s.month_passed.connect(func(_y: int, _m: int) -> void:
		var st := wr.get_ref() as TycoonState
		if st:
			_sample(st))
	s.milestone_claimed.connect(func(ms_id: String, by: String) -> void:
		var st := wr.get_ref() as TycoonState
		if st:
			_on_claim(st, ms_id, by))
	s.bankrupt.connect(func(_info: Dictionary) -> void:
		var st := wr.get_ref() as TycoonState
		if st:
			note(st, "bankrupt"))
	check(s)   # a save from before earns what its state already shows


## An event no state remembers ("sim_to_end", "tip_first", "bankrupt"): counted, then checked.
static func note(s: TycoonState, name: String) -> void:
	if s == null:
		return
	var f: Dictionary = store(s)["flags"]
	f[name] = int(f.get(name, 0)) + 1
	check(s)


## A first taken by the player on the milestone the fair's host tipped off (ConferenceTriennium
## grant_tip): the agency beat that rival to it.
static func _on_claim(s: TycoonState, ms_id: String, by: String) -> void:
	if by != RaceDirector.PLAYER or s.race == null:
		return
	var tip := ConferenceTriennium.tip_record(s)
	if tip.is_empty() or String(tip.get("milestone", "")) != ms_id:
		return
	if String(s.race.first_of(ms_id).get("by", "")) == RaceDirector.PLAYER:
		note(s, "tip_first")


## Once a month: reputation and hype for the chart, and the closed ledger months into the
## campaign's money in / out.
static func _sample(s: TycoonState) -> void:
	var st := store(s)
	var smp: Array = st["samples"]
	if smp.is_empty() or int(smp[-1][0]) != s.weeks:
		smp.append([s.weeks, snappedf(s.reputation, 0.1), snappedf(s.hype, 0.1)])
	while smp.size() > KEEP_SAMPLES:
		smp.pop_front()
	var key := int(st["ledger_key"])
	for mo: Dictionary in (TycoonFinance.fs(s)["ledger"] as Array):
		var k := int(mo.get("key", -1))
		if k <= key:
			continue
		st["earned"] = float(st["earned"]) + TycoonFinance.total(mo.get("in", {}))
		st["spent"] = float(st["spent"]) + TycoonFinance.total(mo.get("out", {}))
		key = k
	st["ledger_key"] = key


# ------------------------------------------------------------ the numbers
## Every stat the conditions read, from the campaign's state.
static func stats(s: TycoonState) -> Dictionary:
	var out := {"launches": 0, "successes": 0, "full": 0, "partials": 0, "failures": 0, "exceptional": 0,
		"piloted": 0, "max_cml": 0, "phoenix": 0}
	var streak := 0
	var fails_by_year := {}
	var first_year := -1
	var wpy := s.weeks_per_year()
	for e: Dictionary in s.project_history:
		out["launches"] += 1
		var ok := bool(e.get("success", false))
		var oc := String(e.get("outcome", "fail"))
		var y := int(e.get("week", 0)) / wpy + 1
		if first_year < 0 or y < first_year:
			first_year = y
		if not ok:
			out["failures"] += 1
			fails_by_year[y] = int(fails_by_year.get(y, 0)) + 1
			streak += 1
		else:
			out["successes"] += 1
			if oc == "partial":
				out["partials"] += 1
			else:
				out["full"] += 1
			if oc == "exceptional":
				out["exceptional"] += 1
			if streak >= 3:
				out["phoenix"] = 1
			streak = 0
		if bool(e.get("piloted", false)):
			out["piloted"] += 1
		out["max_cml"] = maxi(int(out["max_cml"]), int(e.get("cml", 0)))
	# the longest run of whole campaign years without a failed launch, from the first launch on
	var best := 0
	var run := 0
	if first_year > 0:
		for y in range(first_year, s.weeks / wpy + 1):
			run = 0 if fails_by_year.has(y) else run + 1
			best = maxi(best, run)
	out["flawless_years"] = best
	var race := s.race
	out["firsts_won"] = race.firsts_of(RaceDirector.PLAYER) if race else 0
	var lost := 0
	var held := 0
	if race:
		for m: Dictionary in race.milestones:
			var by := String(race.first_of(m["id"]).get("by", ""))
			if by != "" and by != RaceDirector.PLAYER:
				lost += 1
			if race.has_claimed(m["id"], RaceDirector.PLAYER):
				held += 1
	out["firsts_lost"] = lost
	out["milestones"] = held
	out["comet"] = 1 if race and race.met_comet(RaceDirector.PLAYER) else 0
	out["campaign_over"] = 1 if s.is_over() or (race and race.finished) else 0
	out["era"] = s.era()
	out["year"] = s.year()
	out["cash"] = s.cash
	out["reputation"] = s.reputation
	out["hype"] = s.hype
	out["photos"] = s.photos.size()
	out["staff"] = s.staff.size()
	out["hires"] = hired_ids(s).size()
	out["research"] = s.unlocked.size()
	var vet := 0
	for m in s.staff:
		var mem: Variant = m.get("memory", {})
		if mem is Dictionary and (mem as Dictionary).get("n") is Dictionary:
			vet = maxi(vet, int(mem["n"].get("missions", 0)))
	out["veteran"] = vet
	var hired := 0
	var total := 0
	var lg: Dictionary = (s.crew.get("legends", {}) as Dictionary).get("hired", {}) if s.crew.get("legends") is Dictionary else {}
	for l in TycoonLegends.of_kind("hire"):
		total += 1
		if lg.has(String(l["id"])):
			hired += 1
	out["legends_hired"] = hired
	out["legends_total"] = total
	var conf: Dictionary = s.conference
	out["conferences"] = (conf.get("attended", []) as Array).size() if conf.get("attended") is Array else 0
	out["trophies"] = (conf.get("trophies", []) as Array).size() if conf.get("trophies") is Array else 0
	var drives: Dictionary = s.rovers.get("drives", {}) if s.rovers.get("drives") is Dictionary else {}
	var rover_best := 0.0
	var rover_total := 0.0
	var rover_n := 0
	for mid: Variant in drives:
		var rec: Variant = drives[mid]
		if not rec is Dictionary:
			continue
		rover_best = maxf(rover_best, float(rec.get("distance", 0.0)))
		rover_total += float(rec.get("distance", 0.0))
		rover_n += int(rec.get("drives", 0))
	out["rover_best_m"] = rover_best
	out["rover_total_m"] = rover_total
	out["rover_drives"] = rover_n
	var bk: Dictionary = s.finance.get("bk", {}) if s.finance.get("bk") is Dictionary else {}
	var used := bool(bk.get("used", false))
	var loan_open := bk.get("loan") is Dictionary and not (bk.get("loan") as Dictionary).is_empty()
	var broke := bk.get("bankrupt") is Dictionary and not (bk.get("bankrupt") as Dictionary).is_empty()
	out["survived_bankruptcy"] = 1 if used and not loan_open and not broke else 0
	out["bankrupt"] = maxi(1 if broke else 0, flag(s, "bankrupt"))
	out["sim_to_end"] = flag(s, "sim_to_end")
	out["tip_firsts"] = flag(s, "tip_first")
	return out


## The Cometlings the agency hired this campaign (TycoonCrew.hire gives them "h..." ids): the
## ones noted so far (check() keeps them, so those let go still count) and the ones on the team.
static func hired_ids(s: TycoonState) -> Dictionary:
	var out: Dictionary = (store(s).get("hired", {}) as Dictionary).duplicate() if store(s).get("hired") is Dictionary else {}
	for m in s.staff:
		var id := String(m.get("id", ""))
		if id.begins_with("h"):
			out[id] = true
	return out


## The goal of a condition's "min": a number, or the name of another stat.
static func goal(a: Dictionary, st: Dictionary) -> float:
	var w: Dictionary = a.get("when", {})
	var m: Variant = w.get("min", 1)
	if m is String:
		return maxf(float(st.get(m, 1)), 1.0)
	return float(m)


## Does the achievement's condition hold for these stats (and this race)?
static func holds(a: Dictionary, st: Dictionary, s: TycoonState) -> bool:
	var w: Dictionary = a.get("when", {})
	if w.is_empty():
		return false
	if w.has("stat") and float(st.get(String(w["stat"]), 0.0)) < goal(a, st):
		return false
	if w.has("milestone"):
		if s == null or s.race == null:
			return false
		var ids: Array = w["milestone"] if w["milestone"] is Array else [w["milestone"]]
		var any := false
		for id in ids:
			if s.race.has_claimed(String(id), RaceDirector.PLAYER):
				any = true
		if not any:
			return false
	return true


## [value, goal] of an achievement with progress (value capped at the goal); [] without.
static func progress(a: Dictionary, st: Dictionary) -> Array:
	if not bool(a.get("progress", false)):
		return []
	var w: Dictionary = a.get("when", {})
	var g := goal(a, st)
	return [minf(float(st.get(String(w.get("stat", "")), 0.0)), g), g]


## Unlocks every achievement whose condition holds now. Returns the ids unlocked just now (for
## this campaign; the profile's first time is in events.unlocked).
static func check(s: TycoonState) -> Array[String]:
	var got: Array[String] = []
	if s == null or _checking:
		return got
	_checking = true
	store(s)["hired"] = hired_ids(s)
	var st := stats(s)
	var mine := campaign_unlocked(s)
	var cfg := profile()
	var dirty := false
	for a: Dictionary in all():
		var id := String(a.get("id", ""))
		var pg := progress(a, st)
		if not pg.is_empty() and float(pg[0]) > profile_best(id):
			cfg.set_value(BEST, id, float(pg[0]))
			dirty = true
		if mine.has(id) or not holds(a, st, s):
			continue
		got.append(id)
		var first := unlock(s, id, false)
		dirty = dirty or first
	if dirty:
		_save_profile()
	_checking = false
	return got


## Marks an achievement earned in campaign `s` (may be null: the profile only) and in the
## profile. Returns true when the profile had not earned it before. Emits events.unlocked.
static func unlock(s: TycoonState, id: String, save := true) -> bool:
	if find(id).is_empty():
		return false
	if s:
		campaign_unlocked(s)[id] = s.weeks
	var first := not is_unlocked(id)
	if first:
		profile().set_value(SECTION, id, {"t": int(Time.get_unix_time_from_system()),
			"agency": s.agency_name if s else "", "year": s.year() if s else 0})
		if save:
			_save_profile()
	events.unlocked.emit(id, first)
	return first


## Every achievement unlocked at once (the dev menu).
static func unlock_all(s: TycoonState) -> int:
	var n := 0
	for a: Dictionary in all():
		var id := String(a["id"])
		if not is_unlocked(id) or (s and not campaign_unlocked(s).has(id)):
			unlock(s, id, false)
			n += 1
	_save_profile()
	return n


# ------------------------------------------------------------ the Estatísticas page
## The campaign's numbers for StatsScreen: stats() plus
##   "by_era": [{"era", "launches", "ok", "rate" 0..1 or -1}] for the five eras,
##   "dv_kms": Δv flown (km/s, every launch that got there, from each target's need),
##   "rover_km": km driven on other worlds, "earned" / "spent": money in / out since
##   "since_week", "samples": [[week, rep, hype], ...] with today's at the end.
static func campaign_stats(s: TycoonState) -> Dictionary:
	var out := stats(s)
	var st := store(s)
	var wpy := s.weeks_per_year()
	var eras: Array[Dictionary] = []
	for e in 5:
		eras.append({"era": e + 1, "launches": 0, "ok": 0, "rate": -1.0})
	var dv := 0.0
	for e: Dictionary in s.project_history:
		var era := clampi((int(e.get("week", 0)) / wpy) / 5, 0, 4)
		eras[era]["launches"] = int(eras[era]["launches"]) + 1
		if bool(e.get("success", false)):
			eras[era]["ok"] = int(eras[era]["ok"]) + 1
			dv += float(RocketDesigner.need(s, String(e.get("type", "")), String(e.get("target", "")))["dv"])
	for r in eras:
		if int(r["launches"]) > 0:
			r["rate"] = float(r["ok"]) / float(r["launches"])
	out["by_era"] = eras
	out["dv_kms"] = dv
	out["rover_km"] = float(out["rover_total_m"]) / 1000.0
	# money: the months counted so far, the closed months after them and the month under way
	var earned := float(st["earned"])
	var spent := float(st["spent"])
	var key := int(st["ledger_key"])
	for mo: Dictionary in TycoonFinance.history(s):
		if int(mo.get("key", -1)) <= key and not bool(mo.get("open", false)):
			continue
		earned += TycoonFinance.total(mo.get("in", {}))
		spent += TycoonFinance.total(mo.get("out", {}))
	out["earned"] = earned
	out["spent"] = spent
	out["since_week"] = int(st["since_week"])
	var smp: Array = (st["samples"] as Array).duplicate()
	if smp.is_empty() or int(smp[-1][0]) != s.weeks:
		smp.append([s.weeks, s.reputation, s.hype])
	out["samples"] = smp
	out["unlocked_here"] = campaign_unlocked(s).size()
	return out
