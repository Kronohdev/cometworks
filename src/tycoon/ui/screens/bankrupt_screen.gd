extends CwScreen
## The game over of a bankrupt agency (scenes/tycoon/ui/screens/bankrupt.tscn), opened by
## TycoonBankruptcyFlow: what happened (the line crossed again, or the emergency loan's default),
## the score counted up, when, the milestones, the final cash, launches and techs, and Vovô
## Halleyzinho consoling the player. "Tentar de novo" starts a new career with the same leader and
## difficulty; "Menu principal" goes back to the menu. The final record is saved by the flow.

const MENU := "res://scenes/menu/main_menu.tscn"
const HALLEY_LINES := 3


func _ready() -> void:
	super()
	%Retry.pressed.connect(retry)
	%Menu.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU))
	var halley := %Portrait.get_node_or_null("Viewport/Halley") as Halleyzinho
	if halley:
		halley.play.call_deferred("shrug")


func refresh() -> void:
	if state == null:
		return
	var b := Bankruptcy.bankrupt_info(state)
	var week := int(b.get("week", state.weeks))
	var year := week / state.weeks_per_year() + 1
	if String(b.get("reason", "line")) == "default":
		%Reason.text = tr("BK_REASON_DEFAULT") % [year, int(Bankruptcy.db().get("default_months", 6)),
			cr(-float(b.get("line", Bankruptcy.threshold(state))) * float(Bankruptcy.db().get("warn_fraction", 0.5)))]
	else:
		%Reason.text = tr("BK_REASON_LINE") % [year, cr(-float(b.get("line", Bankruptcy.threshold(state))))]
	var score := int(b.get("score", state.race.score().get("total", 0)))
	if CwMotion.reduced():
		%Score.text = "%d" % score
	else:
		create_tween().tween_method(func(v: float) -> void: %Score.text = "%d" % roundi(v), 0.0, float(score), 1.2) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	%When.text = "%02d · %02d" % [year, week % state.weeks_per_year() + 1]
	%Milestones.text = "%d/%d" % [state.milestones, state.milestones_total()]
	%Cash.text = cr(float(b.get("cash", state.cash)))
	%Launches.text = "%d" % state.project_history.size()
	var done := 0
	for t: Dictionary in TycoonResearch.techs():
		done += 1 if TycoonResearch.is_done(state, String(t["id"])) else 0
	%Techs.text = "%d/%d" % [done, TycoonResearch.techs().size()]
	%HalleyLine.text = tr("BK_OVER_HALLEY_%d" % (absi(state.campaign_seed + week) % HALLEY_LINES + 1))


## A new career with the same leader and difficulty (a fresh campaign seed).
func retry() -> void:
	var scene := (load(TycoonSave.TYCOON_SCENE) as PackedScene).instantiate()
	scene.set("leader", state.leader.duplicate(true))
	scene.set("difficulty", state.difficulty)
	scene.set("campaign_seed", randi())
	if clock and "fair_mode" in scene:
		scene.set("fair_mode", clock.fair_mode)
	get_tree().change_scene_to_node(scene)
