class_name Bankruptcy
extends RefCounted
## The end of the money (GDD section 12, "falência"): an agency can sink only so far.
##   - the bankruptcy line is −X: the difficulty's "bankrupt_line" (data/tycoon/difficulty.json,
##     era 1 credits) times the era's factor (economy.json "bankruptcy.era_mult": budgets grow)
##   - warnings first: past warn_fraction of the line the HUD's cash turns to danger, the Tail
##     Radio says so and Vovô Halleyzinho has a word (TycoonState.cash_warning(2), his lesson
##     "money_trouble"); back in the black they can come again
##   - a month that ends past the line the first time: the government's bank steps in ONCE with
##     an emergency loan (the debt covered plus a cushion), repaid in monthly instalments with
##     interest, with a deadline (its last instalment) and two conditions
##   - a month that ends past the line again, or `default_months` month-ends in a row deep in the
##     red (past the warning line) while the emergency loan is unpaid (the loan defaults):
##     bankruptcy, the campaign ends
## Pure rules on a TycoonState, headless. TycoonAgency.week calls weekly() every week and
## month_end() after each month's books, the yearly grant included. Sub-state in
## TycoonState.finance["bk"] (old saves have none: no emergency loan used):
##   {"used": bool, "loan": {} or {"principal", "payment", "months", "months_left", "rate",
##    "week", "deadline_week", "red_months"}, "warned": level, "bankrupt": {} or {"reason"
##    ("line" | "default"), "week", "cash", "line", "score", "milestones"}, "show_loan": bool}

const DIFF_KEY := "bankrupt_line"
const RECORDS_PATH := "user://saves/records.json"

## danger levels (danger_level())
const SAFE := 0
const RED := 1
const DANGER := 2
const PAST := 3


static func db() -> Dictionary:
	return TycoonFinance.db().get("bankruptcy", {})


static func bk(s: TycoonState) -> Dictionary:
	var f := TycoonFinance.fs(s)
	if not f.has("bk"):
		f["bk"] = {"used": false, "loan": {}, "warned": 0, "bankrupt": {}, "show_loan": false}
	return f["bk"]


# ------------------------------------------------------------ reading
## X of the line −X (positive credits) at the campaign's era and difficulty.
static func threshold(s: TycoonState) -> float:
	var base := float(TycoonDifficulty.level(s.difficulty).get(DIFF_KEY, db().get("default_line", 600000)))
	var m: Array = db().get("era_mult", [1.0])
	return base * float(m[clampi(s.era() - 1, 0, m.size() - 1)])


## The cash under which a warning is up (−warn_fraction × X).
static func warn_line(s: TycoonState) -> float:
	return -threshold(s) * float(db().get("warn_fraction", 0.5))


## SAFE (cash >= 0), RED (below zero), DANGER (past the warning line), PAST (past the line).
static func danger_level(s: TycoonState) -> int:
	if s.cash >= 0.0:
		return SAFE
	if s.cash < -threshold(s):
		return PAST
	if s.cash < warn_line(s):
		return DANGER
	return RED


static func is_bankrupt(s: TycoonState) -> bool:
	return not (bk(s)["bankrupt"] as Dictionary).is_empty()


static func emergency_used(s: TycoonState) -> bool:
	return bool(bk(s)["used"])


static func has_emergency_loan(s: TycoonState) -> bool:
	return not (bk(s)["loan"] as Dictionary).is_empty()


## The emergency loan for the screens: {"principal", "payment", "months", "months_left", "rate",
## "week", "deadline_week", "red_months", "default_months", "line"}; {} when there is none.
static func loan_info(s: TycoonState) -> Dictionary:
	var l: Dictionary = (bk(s)["loan"] as Dictionary).duplicate()
	if l.is_empty():
		return {}
	l["default_months"] = int(db().get("default_months", 6))
	l["line"] = threshold(s)
	l["warn"] = -warn_line(s)
	return l


static func bankrupt_info(s: TycoonState) -> Dictionary:
	return bk(s)["bankrupt"]


# ------------------------------------------------------------ weekly: the warnings
## Warnings when the cash crosses the warning line (once until the agency is back in the black).
static func weekly(s: TycoonState) -> void:
	if is_bankrupt(s):
		return
	var b := bk(s)
	var lvl := danger_level(s)
	if lvl == SAFE:
		b["warned"] = 0
	elif lvl >= DANGER and int(b["warned"]) < DANGER:
		b["warned"] = DANGER
		s.news.push_front({"key": "BK_NEWS_WARN", "args": [TycoonHUD.fmt_cr(-threshold(s))]})
		s.cash_warning.emit(DANGER)


# ------------------------------------------------------------ month end: the loan, the line
## After the month's books (TycoonAgency.week): the emergency loan's instalment, then the line.
static func month_end(s: TycoonState) -> void:
	if is_bankrupt(s):
		return
	var b := bk(s)
	var l: Dictionary = b["loan"]
	if not l.is_empty():
		TycoonFinance.add(s, "loan_repay", -float(l["payment"]))
		l["months_left"] = int(l["months_left"]) - 1
		l["red_months"] = int(l.get("red_months", 0)) + 1 if s.cash < warn_line(s) else 0
		if int(l["months_left"]) <= 0 and s.cash >= -threshold(s):
			b["loan"] = {}
			s.news.push_front({"key": "BK_NEWS_PAID", "args": []})
		elif int(l["red_months"]) >= int(db().get("default_months", 6)):
			declare(s, "default")
			return
	if s.cash < -threshold(s):
		if not bool(b["used"]):
			grant(s)
		else:
			declare(s, "line")


## The emergency loan: the debt past zero covered plus a cushion (cushion × X), repaid in
## `months` instalments at `rate_month`; the deadline is its last instalment.
static func grant(s: TycoonState) -> void:
	var b := bk(s)
	var t := terms(s)
	var amount := float(t["principal"])
	b["used"] = true
	b["loan"] = {"principal": amount, "payment": t["payment"], "months": t["months"], "months_left": t["months"],
		"rate": t["rate"], "week": s.weeks, "deadline_week": t["deadline_week"], "red_months": 0}
	b["show_loan"] = true
	TycoonFinance.add(s, "loan", amount)
	s.news.push_front({"key": "BK_NEWS_LOAN", "args": [TycoonHUD.fmt_cr(amount)]})
	s.emergency_loan.emit(loan_info(s))


## The terms an emergency loan would have now (the same keys as loan_info()).
static func terms(s: TycoonState) -> Dictionary:
	var d := db()
	var x := threshold(s)
	var amount := maxf(-s.cash, 0.0) + x * float(d.get("cushion", 0.4))
	var r := float(d.get("rate_month", 0.015))
	var n := maxi(int(d.get("months", 24)), 1)
	var pay := amount * r / (1.0 - pow(1.0 + r, -n)) if r > 0.0 else amount / n
	return {"principal": amount, "payment": pay, "months": n, "months_left": n, "rate": r, "week": s.weeks,
		"deadline_week": s.weeks + roundi(n * float(s.weeks_per_year()) / 12.0), "red_months": 0,
		"default_months": int(d.get("default_months", 6)), "line": x, "warn": -warn_line(s)}


## The agency goes bankrupt ("line": past the line again; "default": the emergency loan unpaid
## past the warning line for too long). The campaign stops (TycoonState.advance_week does nothing more).
static func declare(s: TycoonState, reason: String) -> void:
	var b := bk(s)
	if is_bankrupt(s):
		return
	var sc := s.race.score() if s.race else {}
	b["bankrupt"] = {"reason": reason, "week": s.weeks, "cash": s.cash, "line": threshold(s),
		"score": int(sc.get("total", 0)), "milestones": s.milestones}
	b["show_loan"] = false
	s.news.push_front({"key": "BK_NEWS_BANKRUPT", "args": [s.agency_name]})
	s.bankrupt.emit(bankrupt_info(s))


## The loan screen was shown (TycoonBankruptcyFlow).
static func loan_shown(s: TycoonState) -> void:
	bk(s)["show_loan"] = false


# ------------------------------------------------------------ the final record
## Appends the career that ended to the records file (newest last; at most 50 kept) and returns
## the entry: {"agency", "difficulty", "year", "week", "score", "milestones", "reason", "cash",
## "saved_at"}.
static func save_record(s: TycoonState, path := RECORDS_PATH) -> Dictionary:
	var info := bankrupt_info(s)
	var e := {"agency": s.agency_name, "difficulty": s.difficulty, "year": s.year(), "week": s.week(),
		"score": int(info.get("score", 0)), "milestones": s.milestones, "reason": String(info.get("reason", "")),
		"cash": s.cash, "end": "bankrupt", "saved_at": int(Time.get_unix_time_from_system())}
	var all := records(path)
	all.append(e)
	while all.size() > 50:
		all.pop_front()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": 1, "records": all}, "\t"))
	return e


static func records(path := RECORDS_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (d as Dictionary).get("records", []) if d is Dictionary else []
