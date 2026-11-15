extends CwScreen
## The emergency loan (scenes/tycoon/ui/screens/emergency_loan.tscn): opened once by
## TycoonBankruptcyFlow when a month ends past the bankruptcy line for the first time. It says
## what happened, the loan's terms (what came in, the instalment, the interest, the deadline)
## and the two conditions that end the career, with a word from Vovô Halleyzinho. The loan is
## already in the cash; Entendi closes, Ver as finanças opens the finance screen. Opened with no
## loan (the dev menu, tests) it shows the terms a loan would have now (Bankruptcy.terms()).

func _ready() -> void:
	super()
	%Ok.pressed.connect(close_screen)
	%ToFinance.pressed.connect(func() -> void:
		if hud:
			hud.open_screen("finance")
		else:
			close_screen())
	var halley := %Portrait.get_node_or_null("Viewport/Halley") as Halleyzinho
	if halley:
		halley.play.call_deferred("nod")


func refresh() -> void:
	if state == null:
		return
	var l := Bankruptcy.loan_info(state)
	if l.is_empty():
		l = Bankruptcy.terms(state)
	var line := float(l.get("line", Bankruptcy.threshold(state)))
	%Body.text = tr("BK_LOAN_BODY") % cr(-line)
	%Amount.text = cr(float(l["principal"]))
	%Payment.text = tr("BK_LOAN_PAYMENT_V") % cr(float(l["payment"]))
	%Rate.text = tr("BK_LOAN_RATE_V") % (float(l["rate"]) * 100.0)
	var dw := int(l["deadline_week"])
	%Deadline.text = tr("BK_LOAN_DEADLINE_V") % [int(l["months"]), dw / state.weeks_per_year() + 1,
		dw % state.weeks_per_year() + 1]
	%RuleLine.text = tr("BK_LOAN_RULE_LINE") % cr(-line)
	%RuleRed.text = tr("BK_LOAN_RULE_RED") % [int(l["default_months"]), cr(-float(l.get("warn", -Bankruptcy.warn_line(state))))]
