class_name StatsScreen
extends CwScreen
## Estatísticas (scenes/tycoon/ui/screens/stats.tscn): the campaign's logbook, from
## Achievements.campaign_stats(): launches by outcome, the success rate of each era (rows are
## copies of the hidden EraTemplate), the Δv flown and the km rovers drove, the money in and out
## (since the campaign began, or since a save from before this page started counting), the
## reputation and hype over time (CwLineChart, one sample a month), firsts won and lost to the
## rivals, Cometlings hired, photos, conferences, trophies and the badges this campaign earned.
## "Conquistas" opens the badge book (AchievementsScreen).

const REP_COLOR := CwPalette.COMET_ICE
const HYPE_COLOR := CwPalette.AURORA_PINK


func _ready() -> void:
	super._ready()
	%Achs.pressed.connect(func() -> void:
		if hud:
			hud.open_screen("achievements"))


func refresh() -> void:
	if state == null:
		return
	var st := Achievements.campaign_stats(state)
	%Title.text = "%s · %s" % [tr("ST_TITLE"), state.agency_name]
	%LaunchesN.text = str(int(st["launches"]))
	%SuccessesN.text = str(int(st["full"]))
	%PartialsN.text = str(int(st["partials"]))
	%FailuresN.text = str(int(st["failures"]))
	var eras: Array = st["by_era"]
	var rows := copies(%EraTemplate, eras.size())
	for i in eras.size():
		var e: Dictionary = eras[i]
		var row := rows[i]
		(row.get_node("Name") as Label).text = tr("TY_ERA_%d" % int(e["era"]))
		var bar := row.get_node("Bar") as CwSegmentBar
		var rate := float(e["rate"])
		bar.value = maxf(rate, 0.0)
		bar.color = CwPalette.AURORA_TEAL if rate >= 0.75 else (CwPalette.WARNING if rate >= 0.5 else CwPalette.DANGER)
		var v := row.get_node("Value") as Label
		v.text = tr("ST_ERA_NONE") if rate < 0.0 else tr("ST_ERA_RATE") % [roundi(rate * 100.0), int(e["ok"]), int(e["launches"])]
		row.modulate = Color(1, 1, 1, 0.55) if int(e["era"]) > state.era() else Color.WHITE
	%Dv.text = "%.1f km/s" % float(st["dv_kms"])
	%Rover.text = "%.2f km" % float(st["rover_km"])
	%Earned.text = cr(float(st["earned"]))
	%Spent.text = cr(-float(st["spent"]))
	var since_year := int(st["since_week"]) / state.weeks_per_year() + 1
	%Since.text = tr("ST_MONEY_SINCE") % since_year
	%Won.text = str(int(st["firsts_won"]))
	%Lost.text = str(int(st["firsts_lost"]))
	%Hired.text = str(int(st["hires"]))
	%Team.text = str(int(st["staff"]))
	%Photos.text = str(int(st["photos"]))
	%Confs.text = str(int(st["conferences"]))
	%Trophies.text = str(int(st["trophies"]))
	%Badges.text = "%d / %d" % [int(st["unlocked_here"]), Achievements.all().size()]
	_fill_chart(st["samples"])


## Reputation and hype, one point a month, with a tick at the start of each campaign year
## (every year while they fit, else every five).
func _fill_chart(samples: Array) -> void:
	var rep := PackedFloat32Array()
	var hype := PackedFloat32Array()
	for smp: Array in samples:
		rep.append(float(smp[1]))
		hype.append(float(smp[2]))
	var chart := %Chart as CwLineChart
	chart.series = [{"values": rep, "color": REP_COLOR}, {"values": hype, "color": HYPE_COLOR}]
	%RepSwatch.color = REP_COLOR
	%HypeSwatch.color = HYPE_COLOR
	var ticks := {}
	if samples.size() >= 2:
		var w0 := float(samples[0][0])
		var w1 := float(samples[-1][0])
		var wpy := state.weeks_per_year()
		var y0 := int(w0) / wpy + 1
		var y1 := int(w1) / wpy + 1
		var every := 1 if y1 - y0 <= 8 else 5
		for y in range(y0, y1 + 1):
			if y % every != 0 and every > 1:
				continue
			var wk := float((y - 1) * wpy)
			if wk < w0 or w1 <= w0:
				continue
			ticks[(wk - w0) / (w1 - w0)] = tr("ST_YEAR_TICK") % y
	chart.ticks = ticks
