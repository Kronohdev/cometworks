class_name TycoonFinance
extends RefCounted
## Agency money (GDD section 12): a monthly ledger of income and expense categories (the last
## 24 closed months kept in the state), hype donations, the government's yearly budget, the
## loan offered when the government steps in, and a balance projection. Pure rules on a
## TycoonState. Sub-state lives in `TycoonState.finance`:
##   {"open": month, "ledger": [closed months, oldest first], "neg_months": int,
##    "intervention": bool, "loan": {} or {"principal", "left", "payment", "months_left"}}
## month = {"key": year*12 + month-1, "y", "m", "cash_start", "cash_end", "in": {cat: cr},
##          "out": {cat: cr}}
## Money that moves through `add()` lands in its category; whatever else changed the cash in
## a month (projects, launches, construction, systems that pay directly) is reconciled at the
## month's end into "projects" (or "other" income), so the ledger always adds up.

const PATH := "res://data/tycoon/economy.json"

static var _db: Dictionary = {}


static func db() -> Dictionary:
	if _db.is_empty():
		_db = TycoonState.load_json(PATH)
	return _db


static func fs(s: TycoonState) -> Dictionary:
	if s.finance.is_empty():
		s.finance = {"open": {}, "ledger": [], "neg_months": 0, "intervention": false, "loan": {}}
	return s.finance


static func month_key(s: TycoonState) -> int:
	return (s.year() - 1) * 12 + s._month_of(s.weeks) - 1


static func income_cats() -> Array:
	return db().get("income", [])


static func expense_cats() -> Array:
	return db().get("expense", [])


## The month being written (opened on first use).
static func open_month(s: TycoonState) -> Dictionary:
	var f := fs(s)
	var o: Dictionary = f["open"]
	if o.is_empty():
		var k := month_key(s)
		o = {"key": k, "y": k / 12 + 1, "m": k % 12 + 1, "cash_start": s.cash, "cash_end": s.cash, "in": {}, "out": {}}
		f["open"] = o
	return o


## Moves money and books it: amount > 0 is income, < 0 an expense, in category `cat`.
static func add(s: TycoonState, cat: String, amount: float) -> void:
	s.cash += amount
	note(s, cat, amount)


## Books money that already moved (the cash itself is not touched).
static func note(s: TycoonState, cat: String, amount: float) -> void:
	var o := open_month(s)
	var side: Dictionary = o["in"] if amount >= 0.0 else o["out"]
	side[cat] = float(side.get(cat, 0.0)) + absf(amount)


static func total(side: Dictionary) -> float:
	var t := 0.0
	for k: String in side:
		t += float(side[k])
	return t


## Month end: books the bills TycoonState paid at the turn of the month, reconciles the rest,
## closes the month into the ledger and opens the next one.
static func close_month(s: TycoonState, salaries: float, upkeep: float) -> void:
	var f := fs(s)
	var o := open_month(s)
	note(s, "salaries", -salaries)
	note(s, "upkeep", -upkeep)
	var booked := total(o["in"]) - total(o["out"])
	var rest := (s.cash - float(o["cash_start"])) - booked
	if absf(rest) > 0.5:
		note(s, "other" if rest > 0.0 else "projects", rest)
	o["cash_end"] = s.cash
	var ledger: Array = f["ledger"]
	ledger.append(o)
	while ledger.size() > int(db().get("ledger_months", 24)):
		ledger.pop_front()
	# three month-ends in the red: the government steps in (GDD section 12)
	f["neg_months"] = int(f["neg_months"]) + 1 if s.cash < 0.0 else 0
	if int(f["neg_months"]) >= int(db().get("intervention_months", 3)) and not bool(f["intervention"]):
		f["intervention"] = true
		s.news.push_front({"key": "TY_NEWS_INTERVENTION", "args": []})
	elif s.cash >= 0.0:
		f["intervention"] = false
	f["open"] = {}
	open_month(s)


## Start of a month: hype donations and the loan instalment.
static func monthly(s: TycoonState) -> void:
	var don := s.hype * float(db().get("donations_per_hype", 400))
	if don > 0.5:
		add(s, "donations", don)
	var loan: Dictionary = fs(s)["loan"]
	if not loan.is_empty():
		add(s, "loan_repay", -float(loan["payment"]))
		loan["months_left"] = int(loan["months_left"]) - 1
		if int(loan["months_left"]) <= 0:
			fs(s)["loan"] = {}
			s.news.push_front({"key": "TY_NEWS_LOAN_PAID", "args": []})


## Government budget for a year: G_era * (0.5 + reputation/100) * (1 + step * milestones).
static func grant_amount(s: TycoonState) -> float:
	var g: Array = db().get("gov_budget", [400000])
	var base := float(g[clampi(s.era() - 1, 0, g.size() - 1)])
	return base * (0.5 + clampf(s.reputation, 0.0, 100.0) / 100.0) \
		* (1.0 + float(db().get("gov_milestone_step", 0.05)) * s.milestones)


## Paid at the start of every year from year 2 (year 1 runs on the start capital).
static func yearly(s: TycoonState) -> void:
	var g := grant_amount(s)
	add(s, "grant", g)
	s.news.push_front({"key": "TY_NEWS_GRANT", "args": [TycoonHUD.fmt_cr(g)]})


# ------------------------------------------------------------ loan
static func loan_amount(s: TycoonState) -> float:
	var m: Array = db().get("loan_era_mult", [1.0])
	return float(db().get("loan_base", 200000)) * float(m[clampi(s.era() - 1, 0, m.size() - 1)])


static func loan_payment(principal: float) -> float:
	var r := float(db().get("loan_rate_month", 0.01))
	var n := int(db().get("loan_months", 24))
	return principal * r / (1.0 - pow(1.0 + r, -n)) if r > 0.0 else principal / n


static func has_loan(s: TycoonState) -> bool:
	return not (fs(s)["loan"] as Dictionary).is_empty()


## The loan is on the table once the government stepped in (or whenever cash is negative).
static func can_take_loan(s: TycoonState) -> bool:
	return not has_loan(s) and (bool(fs(s)["intervention"]) or s.cash < 0.0)


static func take_loan(s: TycoonState) -> bool:
	if not can_take_loan(s):
		return false
	var p := loan_amount(s)
	fs(s)["loan"] = {"principal": p, "payment": loan_payment(p), "months_left": int(db().get("loan_months", 24))}
	add(s, "loan", p)
	fs(s)["intervention"] = false
	s.news.push_front({"key": "TY_NEWS_LOAN", "args": [TycoonHUD.fmt_cr(p)]})
	s.changed.emit()
	return true


# ------------------------------------------------------------ reading
## Closed months, oldest first, plus the open one at the end.
static func history(s: TycoonState) -> Array:
	var out: Array = (fs(s)["ledger"] as Array).duplicate()
	var o := open_month(s).duplicate()
	o["cash_end"] = s.cash
	o["open"] = true
	out.append(o)
	return out


## Recurring monthly flow today (donations - salaries - upkeep - loan instalment).
static func monthly_net(s: TycoonState) -> float:
	var net := s.hype * float(db().get("donations_per_hype", 400)) - s.monthly_salaries() - s.monthly_upkeep()
	var loan: Dictionary = fs(s)["loan"]
	if not loan.is_empty():
		net -= float(loan["payment"])
	return net


## Cash at the end of each of the next `months` months: recurring flow, the yearly grant at
## today's reputation, and the rewards of accepted contracts at their deadlines.
static func projection(s: TycoonState, months := -1) -> Array[float]:
	if months < 0:
		months = int(db().get("projection_months", 12))
	var out: Array[float] = []
	var cash := s.cash
	var k0 := month_key(s)
	var wpm := float(s.weeks_per_year()) / 12.0
	var loan: Dictionary = fs(s)["loan"]
	var loan_left := int(loan.get("months_left", 0))
	for i in months:
		var k := k0 + i + 1
		cash += s.hype * float(db().get("donations_per_hype", 400)) - s.monthly_salaries() - s.monthly_upkeep()
		if loan_left > 0:
			cash -= float(loan["payment"])
			loan_left -= 1
		if k % 12 == 0:
			cash += grant_amount(s)
		for c in s.contracts:
			if String(c.get("status", "")) == "accepted":
				var due := int(float(c.get("deadline_week", 0)) / wpm)
				if due == k:
					cash += float(c.get("reward", 0.0))
		out.append(cash)
	return out
