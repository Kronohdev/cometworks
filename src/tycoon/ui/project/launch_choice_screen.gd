extends CwScreen
## The launch choice (scenes/tycoon/ui/screens/launch_choice.tscn): a project whose rocket was
## built in the hangar reaches the pad (ProjectDesk.launch stops it there, review_state "pad")
## and the player picks:
##   Pilotar o lançamento   the flight mode opens inside the campus (TycoonModes) with the
##                          mission's vessel and payload; the flight decides the outcome
##                          (HangarRocket.flight_verdict) and the review follows
##   Simulação automática   the team flies it: the Design Review's odds roll, then the launch
##                          sequence and the review, as for any rocket
##   Decidir depois / Esc   it stays on the pad (it asks again next week)
## ProjectFlow opens it (state.launch_pad_ready) and keeps the clock still while it is up; the
## review it leads to waits behind it. Everything visual is in the scene.

var project_id := ""


func _ready() -> void:
	super._ready()
	%Pilot.pressed.connect(pilot)
	%Auto.pressed.connect(auto)
	%Later.pressed.connect(close_screen)


## args: {"project_id"}.
func open_with(args: Dictionary) -> void:
	project_id = String(args.get("project_id", ""))
	refresh()


func _project() -> MissionProject:
	return ProjectDesk.find(state, project_id) if state else null


func refresh() -> void:
	var p := _project()
	if p == null:
		return
	var fam := RocketFamilies.find(state, String(p.rocket.get("family", "")))
	var tname := tr(String(state.mission_target(p.target_id).get("name_key", "")))
	%Caption.text = tr("TY_HG_CHOICE_CAPTION") % [p.code, tr(String(p.mission_type(state).get("name_key", ""))), tname,
		String(fam.get("name", "—"))]
	%PilotGoal.text = tr("TY_HG_CHOICE_PILOT_GOAL") % HangarRocket.goal_text(HangarRocket.mission_for(state, p.type_id, p.target_id))
	var odds := float(ProjectDesk.success_chance(state, p)["total"])
	%AutoOdds.text = tr("TY_HG_CHOICE_AUTO_ODDS") % roundi(odds * 100.0)
	%Pilot.disabled = HangarRocket.scene_for(state, p.rocket.get("parts", {})) == null


## "Pilotar o lançamento": the flight opens; this screen waits under it.
func pilot() -> void:
	if hud == null or _project() == null:
		return
	var main := hud.owner as TycoonMain
	if main == null or main.modes == null:
		return
	main.modes.open_project_flight(project_id, _flown)


## The flight is over: its verdict is the launch outcome; the review comes up when this closes.
func _flown(verdict: Dictionary) -> void:
	var p := _project()
	if p != null:
		ProjectDesk.launch(state, p, verdict)
	close_screen()


## "Simulação automática": the Design Review's odds decide (the launch sequence plays).
func auto() -> void:
	var p := _project()
	if p != null:
		ProjectDesk.launch(state, p, {"auto": true})
	close_screen()
