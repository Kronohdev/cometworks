class_name FinaleScreen
extends Control
## The Mother-Ice passes (scenes/tycoon/ui/screens/finale.tscn, GDD section 16.3): opened by
## TycoonRaceFlow at the end of year 25. The comet crossing the sky and the text sequence
## are the scene's AnimationPlayer ("pass"); this script writes who met the comet and opens
## the final score.

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD


func _ready() -> void:
	%ScoreButton.pressed.connect(_to_score)
	(%Anim as AnimationPlayer).play("pass")


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	fill()


func fill() -> void:
	var r := state.race
	%Message.text = tr("TY_FIN_MET") if r.met_comet(RaceDirector.PLAYER) else tr("TY_FIN_MISSED")
	var ids := r.agencies()
	var rows := TycoonHUD._copies(%ResultTemplate, ids.size())
	var comet_id := ""
	for m: Dictionary in r.milestones:
		if bool(m.get("victory", false)):
			comet_id = String(m["id"])
	for k in ids.size():
		var id := ids[k]
		var row := rows[k]
		var met := r.met_comet(id)
		var mk := row.get_node("Marker") as CwMarker
		mk.fill = r.agency_color(id) if met else Color(0, 0, 0, 0)
		mk.outline = r.agency_color(id)
		mk.star = met
		var nl := row.get_node("Name") as Label
		nl.text = r.agency_name(id) if id == RaceDirector.PLAYER else tr(r.agency_name(id))
		# the finale sits on the night sky: cream and soft lilac text
		nl.add_theme_color_override("font_color", CwPalette.CREAM if met else Color("#cfc3ff"))
		var st := row.get_node("Status") as Label
		st.text = tr("TY_FIN_ROW_MET") if met else tr("TY_FIN_ROW_MISSED")
		st.add_theme_color_override("font_color", CwPalette.MINT if met else Color("#cfc3ff"))
		var when := ""
		for c: Dictionary in r.claims.get(comet_id, []):
			if String(c["by"]) == id:
				var w := int(c["week"])
				when = tr("TY_RACE_WHEN") % [w / state.weeks_per_year() + 1, w % state.weeks_per_year() + 1]
		(row.get_node("When") as Label).text = when


func _to_score() -> void:
	if hud:
		hud.open_screen("final_score")
	else:
		queue_free()
