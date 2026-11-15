class_name ConferenceFlow
extends Node
## Wires the Conferência dos Cometinhos into the tycoon scene (TycoonMain keeps one, as a child
## named "Conference"; ConferenceBook has the rules):
##   - when this year's invitation is due (ConferenceBook.due) and the campus is free (no screen,
##     no hangar / flight, no cutscene, lesson or conversation), the "conference" screen opens and
##     the clock holds; "Ir à feira" or "Fica para a próxima" answer it (closing it with Esc is a
##     "no")
##   - going: the campus sleeps like it does under the hangar (hidden, not processed, the HUD
##     hidden, the campus camera asleep), the fair (scenes/tycoon/conference/conference_fair.tscn)
##     opens with its own camera, which the speech bubbles borrow, and the newspaper waits
##     (TycoonRaceFlow.wait_for) until the player is back
##   - "Sair da feira" (the gate, the pause card) brings everything back, gives the clock its
##     speed again and says what the visit gave
## dev_open() (the dev menu) goes to the fair right away, whatever the calendar says.

const SCREEN := "conference"
const FAIR_SCENE := "res://scenes/tycoon/conference/conference_fair.tscn"

var main: TycoonMain
var fair: ConferenceFair
var _resume_speed := 0
var _inviting := false
var _want_enter := false
var _hidden: Array[Dictionary] = []
var _old_chatter_cam: Camera3D
var _old_wait := Callable()
var _closed_frame := -1


func _init() -> void:
	name = "Conference"


func bind(m: TycoonMain) -> void:
	main = m
	add_to_group(&"conference_flow")
	m.state.week_passed.connect(func(_y: int, _w: int) -> void: _check.call_deferred())
	m.hud.screen_closed.connect(_on_screen_closed)
	_check.call_deferred()


func is_open() -> bool:
	return fair != null


## Left the fair during this frame: the key that did it must not reach the campus too.
func just_closed() -> bool:
	return _closed_frame == Engine.get_process_frames()


func _on_screen_closed(screen_name: String) -> void:
	if screen_name == SCREEN and _inviting:
		answer(false)   # closed without an answer: maybe next time
	_check.call_deferred()


## Is the campus free for the invitation or the fair?
func _free() -> bool:
	if main == null or main.hud.current_screen() != "" or Cutscenes.is_playing():
		return false
	if main.modes and main.modes.is_open():
		return false
	if main.tutorial and main.tutorial.is_showing():
		return false
	if main.talk and main.talk.is_open():
		return false
	return not main.state.race.finished and not Bankruptcy.is_bankrupt(main.state)


func _check() -> void:
	if main == null or is_open() or _inviting:
		return
	if _want_enter:
		if _free():
			_enter()
		return
	if main.fair_mode and not bool(ConferenceBook.cfg("invite_in_fair_mode", true)):
		return
	if ConferenceBook.due(main.state) and _free():
		invite()


## Opens this year's invitation (the "conference" screen) and holds the clock.
func invite() -> bool:
	_hold_clock()
	_inviting = true
	if not main.hud.open_screen(SCREEN):
		_inviting = false
		_release_clock()
		return false
	return true


## The invitation's answer (the screen calls it before it closes).
func answer(go: bool) -> void:
	var was_inviting := _inviting
	_inviting = false
	if not was_inviting and not ConferenceBook.due(main.state) and not go:
		return   # the dev menu opened the screen out of season: "no" changes nothing
	ConferenceBook.answer(main.state, go)
	if go:
		_hold_clock()
		_want_enter = true
		_check.call_deferred()
	else:
		_release_clock()


## Dev menu: straight to the fair (this year's invitation counts as answered).
func dev_open() -> bool:
	if is_open() or main == null:
		return false
	if main.hud.current_screen() != "":
		_inviting = false
		main.hud.close_screen()
	if main.modes and main.modes.is_open():
		main.modes.close_mode()
	ConferenceBook.answer(main.state, true)
	_hold_clock()
	_enter()
	return true


func _enter() -> void:
	_want_enter = false
	if main.talk and main.talk.is_open():
		main.talk.close()
	_hidden.clear()
	for n: Node in [main.campus, main.camera, main.get_node_or_null("Audio"), main.get_node_or_null("DayCycle"),
			main.get_node_or_null("Effects"), main.get_node_or_null("Halley")]:
		if n == null:
			continue
		var e := {"node": n, "mode": n.process_mode}
		if n is Node3D:
			e["visible"] = (n as Node3D).visible
			(n as Node3D).visible = false
		n.process_mode = Node.PROCESS_MODE_DISABLED
		_hidden.append(e)
	var ui := main.get_node_or_null("UI") as CanvasLayer
	if ui:
		ui.visible = false
	main.camera.release()
	fair = (load(FAIR_SCENE) as PackedScene).instantiate() as ConferenceFair
	main.add_child(fair)
	if main.chatter:
		main.chatter.clear()
		_old_chatter_cam = main.chatter.camera
		main.chatter.camera = fair.camera
	if main.race_flow:
		_old_wait = main.race_flow.wait_for
		var prev := _old_wait
		main.race_flow.wait_for = func() -> bool:
			return is_open() or (prev.is_valid() and bool(prev.call()))
	fair.leave_requested.connect(leave, CONNECT_DEFERRED)
	fair.match_sky(main.campus.get_node_or_null("Lights"))
	fair.open(main.state, main.talk, main.chatter)
	CwSfx.play(&"ui_open")


## Back to the campus.
func leave() -> void:
	if not is_open():
		return
	if main.talk and main.talk.is_open():
		main.talk.close()
	var st := ConferenceBook.store(main.state)
	var talked := (st["talked"] as Array).size()
	var heard := (st["heard"] as Array).size()
	fair.close()
	if main.chatter:
		main.chatter.clear()
		main.chatter.camera = _old_chatter_cam if is_instance_valid(_old_chatter_cam) else main.camera
	fair.queue_free()
	fair = null
	for e in _hidden:
		var n: Node = e["node"]
		if not is_instance_valid(n):
			continue
		n.process_mode = e["mode"]
		if n is Node3D:
			(n as Node3D).visible = bool(e.get("visible", true))
	_hidden.clear()
	var ui := main.get_node_or_null("UI") as CanvasLayer
	if ui:
		ui.visible = true
	main.camera.make_current()
	if main.race_flow:
		main.race_flow.wait_for = _old_wait
		_old_wait = Callable()
	_closed_frame = Engine.get_process_frames()
	_release_clock()
	main.hud.flash_hint(tr("TY_CONF_BACK_HINT").format({"n": talked, "heard": heard}), 5.0)
	CwSfx.play(&"ui_back")
	if main.race_flow and main.race_flow.has_method("_next_page"):
		main.race_flow.call_deferred("_next_page")   # a front page that waited for us


func _hold_clock() -> void:
	if main.clock.speed > 0:
		_resume_speed = main.clock.speed
		main.clock.set_speed(0)


func _release_clock() -> void:
	if _resume_speed > 0 and main.clock.speed == 0:
		main.clock.set_speed(_resume_speed)
	_resume_speed = 0
