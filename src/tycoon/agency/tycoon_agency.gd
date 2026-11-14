class_name TycoonAgency
extends RefCounted
## Weekly driver of the agency systems (E3): research, the contract board and the money.
## TycoonState.advance_week() calls `week(self)` once, after the calendar moved and the
## monthly bills were paid, so this sees the new week. Order inside a week:
##   research (PP in, funded tech draws) -> contracts (deadlines, rivals) -> on a new month:
##   close the ledger month, donations and loan instalment, the yearly government budget,
##   then a fresh contract board.


static func week(s: TycoonState) -> void:
	TycoonFinance.open_month(s)
	TycoonResearch.weekly(s)
	TycoonContracts.weekly(s)
	var o: Dictionary = TycoonFinance.fs(s)["open"]
	if int(o["key"]) != TycoonFinance.month_key(s):
		TycoonFinance.close_month(s, s.monthly_salaries(), s.monthly_upkeep())
		TycoonFinance.monthly(s)
		if s.week() == 1 and s.year() >= 2:
			TycoonFinance.yearly(s)
	TycoonContracts.ensure_offers(s)
