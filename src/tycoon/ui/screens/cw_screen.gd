class_name CwScreen
extends Control
## Base of the full screens the HUD opens in its Screens layer (TycoonHUD.open_screen): keeps
## the state / clock / HUD, refreshes when the state changes and closes with the scene's
## %Close button. Everything visual is in the screen's .tscn; subclasses only fill data,
## duplicating hidden templates with `copies()`.

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	if not state.changed.is_connected(_on_changed):
		state.changed.connect(_on_changed)
	_bound()
	refresh()
	# panels slide in 8 px with a short fade (GDD 22.6), unless the scene has its own
	# CwScreenTransition (src/tycoon/ui/motion/)
	var frame := get_node_or_null("%Frame") as Control
	if frame and CwScreenTransition.of(self) == null:
		frame.modulate.a = 0.0
		var y := frame.position.y
		frame.position.y = y + 8.0
		var tw := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(frame, "modulate:a", 1.0, 0.14)
		tw.tween_property(frame, "position:y", y, 0.14)


func _ready() -> void:
	var close := get_node_or_null("%Close") as Button
	if close:
		close.pressed.connect(close_screen)


func _exit_tree() -> void:
	if state and state.changed.is_connected(_on_changed):
		state.changed.disconnect(_on_changed)


func _on_changed() -> void:
	if is_inside_tree():
		refresh()


## Called once after bind, before the first refresh.
func _bound() -> void:
	pass


func refresh() -> void:
	pass


func close_screen() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


static func copies(template: Control, count: int) -> Array[Control]:
	return TycoonHUD._copies(template, count)


static func cr(v: float) -> String:
	return TycoonHUD.fmt_cr(v)


## 1284000 -> "1.28M", 45000 -> "45k" (chart axes).
static func short_cr(v: float) -> String:
	var a := absf(v)
	var sgn := "−" if v < 0.0 else ""
	if a >= 1.0e6:
		return "%s%.2fM" % [sgn, a / 1.0e6]
	if a >= 1.0e3:
		return "%s%dk" % [sgn, roundi(a / 1.0e3)]
	return "%s%d" % [sgn, roundi(a)]
