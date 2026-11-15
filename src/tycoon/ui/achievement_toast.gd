class_name AchievementToast
extends Control
## The cozy note that pops in under the HUD's top bar when the profile earns an achievement
## (Achievements.events.unlocked): the medal in the badge's colour with two twinkles, "Conquista!",
## its name and description. It pops (scale and fade), holds `hold` seconds and floats away;
## several in a row queue up, and a burst (a save loaded with many already earned) folds into
## one "+N conquistas" note. A click opens the badge book (the HUD's achievements screen). Lives
## in scenes/tycoon/ui/achievement_toast.tscn, on its own CanvasLayer of tycoon_main.tscn; the
## look is the scene's.

## seconds each note stays
@export var hold := 4.0
## more than this many waiting: they fold into one "+N" note
@export var fold_after := 3
## the HUD whose achievements screen a click opens (optional)
@export var hud_path: NodePath

var _queue: Array[String] = []
var _busy := false
var _tween: Tween


func _ready() -> void:
	%Card.visible = false
	%Card.gui_input.connect(_on_card_input)
	Achievements.events.unlocked.connect(_on_unlocked)


func _exit_tree() -> void:
	if Achievements.events.unlocked.is_connected(_on_unlocked):
		Achievements.events.unlocked.disconnect(_on_unlocked)


func _on_unlocked(id: String, first_time: bool) -> void:
	if first_time:
		show_achievement(id)


## Queues the note of achievement `id`.
func show_achievement(id: String) -> void:
	_queue.append(id)
	if not _busy:
		_busy = true
		_next.call_deferred()


func is_showing() -> bool:
	return _busy


func _next() -> void:
	if _queue.is_empty() or not is_inside_tree():
		_busy = false
		return
	_busy = true
	if _queue.size() > fold_after:
		var n := _queue.size()
		var first := _queue[0]
		_queue.clear()
		_fill(Achievements.find(first), n - 1)
	else:
		_fill(Achievements.find(_queue.pop_front()), 0)
	_play()


func _fill(a: Dictionary, more: int) -> void:
	var col := Achievements.color(a)
	%Disc.self_modulate = col.lerp(Color.WHITE, 0.45)
	%Icon.texture = Achievements.icon(a)
	%Caption.text = tr("ACH_TOAST_CAPTION")
	%Name.text = tr(String(a.get("name_key", "")))
	%Desc.text = tr("ACH_TOAST_MORE") % more if more > 0 else tr(String(a.get("desc_key", "")))
	%SparkA.self_modulate = col
	%SparkB.self_modulate = CwPalette.BUTTER


func _play() -> void:
	var card := %Card as Control
	card.visible = true
	card.modulate.a = 0.0
	card.scale = Vector2(0.86, 0.86)
	card.pivot_offset = card.size * 0.5
	var home_y := card.offset_top
	CwSfx.play(&"news_chime")
	if _tween:
		_tween.kill()
	var reduced := CwMotion.reduced()
	_tween = create_tween()
	_tween.set_parallel()
	_tween.tween_property(card, "modulate:a", 1.0, 0.18)
	_tween.tween_property(card, "scale", Vector2.ONE, 0.0 if reduced else 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not reduced:
		for sp: Control in [%SparkA, %SparkB]:
			sp.rotation = 0.0
			sp.scale = Vector2(0.3, 0.3)
			_tween.tween_property(sp, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(sp, "rotation", TAU * 0.25, hold).set_trans(Tween.TRANS_SINE)
		var icon := %Icon as Control
		icon.rotation = -0.25
		_tween.tween_property(icon, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(hold)
	_tween.chain().set_parallel()
	_tween.tween_property(card, "modulate:a", 0.0, 0.3)
	if not reduced:
		_tween.tween_property(card, "offset_top", home_y - 16.0, 0.3)
		_tween.tween_property(card, "offset_bottom", card.offset_bottom - 16.0, 0.3)
	_tween.chain().tween_callback(func() -> void:
		card.visible = false
		card.offset_bottom += home_y - card.offset_top
		card.offset_top = home_y
		_next())


func _on_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var hud := get_node_or_null(hud_path) as TycoonHUD if not hud_path.is_empty() else null
		if hud:
			hud.open_screen("achievements")
		if _tween:
			_tween.kill()
		%Card.visible = false
		_next()
