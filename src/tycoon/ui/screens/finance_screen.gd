extends CwScreen
## Finance screen (scenes/tycoon/ui/screens/finance.tscn), three tabs (CwPageStack):
##   Overview  the big numbers (cash, monthly net, next budget, runway), month-end cash for the
##             last 24 months with the 12-month projection (CwCashChart) and this month's bills
##   Flow      income and expense categories for the chosen period, and the last months' ledger
##   Budget    the loan and the government budget formula
## Visuals are in the scene; this script fills them.

var period := 12


## open_screen("finance", {"tab": "Overview" | "Flow" | "Budget"})
func open_with(args: Dictionary) -> void:
	if args.has("tab"):
		(%Pages as CwPageStack).switch_to(StringName(String(args["tab"])))


func _ready() -> void:
	super()
	%P1.pressed.connect(func() -> void: _set_period(1))
	%P12.pressed.connect(func() -> void: _set_period(12))
	%P24.pressed.connect(func() -> void: _set_period(24))
	%LoanButton.pressed.connect(func() -> void:
		if state:
			TycoonFinance.take_loan(state))


func _set_period(n: int) -> void:
	period = n
	refresh()


func refresh() -> void:
	if state == null:
		return
	var buttons := {1: %P1, 12: %P12, 24: %P24}
	for k: int in buttons:
		(buttons[k] as Button).set_pressed_no_signal(k == period)
	%CashValue.text = cr(state.cash)
	%CashValue.add_theme_color_override("font_color", CwPalette.DANGER if state.cash < 0.0 else CwPalette.COMET_ICE)
	var net := TycoonFinance.monthly_net(state)
	%NetValue.text = ("+" if net >= 0.0 else "") + cr(net)
	%NetValue.add_theme_color_override("font_color", CwPalette.AURORA_TEAL if net >= 0.0 else CwPalette.WARNING)
	var g := TycoonFinance.grant_amount(state)
	%GrantValue.text = cr(g)
	%RunwayValue.text = tr("TY_FN_RUNWAY_OK") if net >= 0.0 else tr("TY_FN_MONTHS") % maxi(floori(state.cash / -net), 0)
	%Banner.visible = bool(TycoonFinance.fs(state)["intervention"])
	_fill_chart()
	_fill_breakdown()
	_fill_bills(net)
	_fill_grant(g)
	_fill_ledger()
	_fill_loan()


## The last closed months, newest first: net and cash at the month's end.
func _fill_ledger() -> void:
	var ledger: Array = TycoonFinance.fs(state)["ledger"]
	var n := mini(ledger.size(), 6)
	var rows := copies(%MonthTemplate, n)
	for i in n:
		var mo: Dictionary = ledger[ledger.size() - 1 - i]
		var net := TycoonFinance.total(mo["in"]) - TycoonFinance.total(mo["out"])
		(rows[i].get_node("Month") as Label).text = "%s · %02d" % [tr("TY_FN_YEAR_SHORT") % int(mo["y"]), int(mo["m"])]
		var nl := rows[i].get_node("Net") as Label
		nl.text = ("+" if net >= 0.0 else "") + cr(net).trim_suffix(" cr")
		nl.add_theme_color_override("font_color", CwPalette.AURORA_TEAL if net >= 0.0 else CwPalette.DANGER)
		var cl := rows[i].get_node("Cash") as Label
		cl.text = cr(float(mo["cash_end"])).trim_suffix(" cr")
		cl.add_theme_color_override("font_color", CwPalette.DANGER if float(mo["cash_end"]) < 0.0 else CwPalette.COMET_ICE)


func _fill_chart() -> void:
	var hist := TycoonFinance.history(state)
	var proj := TycoonFinance.projection(state)
	var cash := PackedFloat32Array()
	var net := PackedFloat32Array()
	var labels := PackedStringArray()
	for mo: Dictionary in hist:
		cash.append(float(mo["cash_end"]))
		net.append(TycoonFinance.total(mo["in"]) - TycoonFinance.total(mo["out"]))
		labels.append(tr("TY_FN_YEAR_SHORT") % int(mo["y"]) if int(mo["m"]) == 1 else "")
	var k := int(hist[-1]["key"])
	for i in proj.size():
		var kk := k + i + 1
		labels.append(tr("TY_FN_YEAR_SHORT") % (kk / 12 + 1) if kk % 12 == 0 else "")
	var chart := %Chart as CwCashChart
	chart.labels = labels
	chart.net = net
	chart.projection = PackedFloat32Array(proj)
	chart.cash = cash


## Sums of the last `period` months (1 = the month being written).
func _period_sums() -> Array[Dictionary]:
	var hist := TycoonFinance.history(state)
	var months := hist.slice(maxi(hist.size() - period, 0))
	var inc := {}
	var out := {}
	for mo: Dictionary in months:
		for c: String in mo["in"]:
			inc[c] = float(inc.get(c, 0.0)) + float(mo["in"][c])
		for c: String in mo["out"]:
			out[c] = float(out.get(c, 0.0)) + float(mo["out"][c])
	return [inc, out]


func _fill_breakdown() -> void:
	var sums := _period_sums()
	_fill_side(%InTemplate, sums[0], TycoonFinance.income_cats(), CwPalette.AURORA_TEAL, %IncomeTotal, %IncomeEmpty)
	_fill_side(%OutTemplate, sums[1], TycoonFinance.expense_cats(), CwPalette.IGNITION, %ExpenseTotal, %ExpenseEmpty)


func _fill_side(template: Control, sums: Dictionary, order: Array, col: Color, total_l: Label, empty_l: Label) -> void:
	var cats: Array[String] = []
	for c in order:
		if float(sums.get(c, 0.0)) > 0.5:
			cats.append(String(c))
	cats.sort_custom(func(a: String, b: String) -> bool: return float(sums[a]) > float(sums[b]))
	var total := 0.0
	for c in cats:
		total += float(sums[c])
	var rows := copies(template, cats.size())
	for i in cats.size():
		var v := float(sums[cats[i]])
		(rows[i].get_node("Name") as Label).text = tr("TY_FN_C_" + cats[i].to_upper())
		var bar := rows[i].get_node("Bar") as CwSegmentBar
		bar.color = col
		bar.value = v / maxf(total, 1.0)
		(rows[i].get_node("Amount") as Label).text = cr(v)
	total_l.text = cr(total)
	empty_l.visible = cats.is_empty()


func _fill_bills(net: float) -> void:
	%SalValue.text = "−" + cr(state.monthly_salaries())
	%SalNote.text = tr("TY_FN_STAFF") % state.staff.size()
	%UpkValue.text = "−" + cr(state.monthly_upkeep())
	var nb := 0
	for lot: String in state.buildings:
		nb += 1 if int(state.buildings[lot].get("level", 0)) > 0 else 0
	%UpkNote.text = tr("TY_FN_BUILDINGS") % nb
	var don := state.hype * float(TycoonFinance.db().get("donations_per_hype", 400))
	%DonValue.text = "+" + cr(don)
	%DonNote.text = tr("TY_FN_DONATIONS_N") % roundi(state.hype)
	var loan: Dictionary = TycoonFinance.fs(state)["loan"]
	%LoanRow.visible = not loan.is_empty()
	if not loan.is_empty():
		%LoanPayValue.text = "−" + cr(float(loan["payment"]))
	%BillsNet.text = ("+" if net >= 0.0 else "") + cr(net)
	%BillsNet.add_theme_color_override("font_color", CwPalette.AURORA_TEAL if net >= 0.0 else CwPalette.WARNING)


func _fill_grant(g: float) -> void:
	%GrantBig.text = cr(g)
	var gb: Array = TycoonFinance.db().get("gov_budget", [0])
	%GrantFormula.text = tr("TY_FN_GRANT_FORMULA") % [cr(float(gb[clampi(state.era() - 1, 0, gb.size() - 1)])),
		roundi(state.reputation), state.milestones]


func _fill_loan() -> void:
	var loan: Dictionary = TycoonFinance.fs(state)["loan"]
	var btn: Button = %LoanButton
	if loan.is_empty():
		%LoanText.text = tr("TY_FN_LOAN_NONE")
	else:
		%LoanText.text = tr("TY_FN_LOAN_ACTIVE") % [int(loan["months_left"]), cr(float(loan["payment"]))]
	btn.text = tr("TY_FN_LOAN_ASK") % cr(TycoonFinance.loan_amount(state))
	btn.disabled = not TycoonFinance.can_take_loan(state)
