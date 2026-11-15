class_name TycoonBankruptcyFlow
extends RefCounted
## Wires Bankruptcy into the tycoon scene (TycoonMain keeps one): the emergency loan's screen
## ("emergency_loan", once, when the campus is free: it waits for the screen on show to close)
## and the game over ("bankrupt": the clock stops, any screen closes, the final record is saved;
## closing any screen brings it back, like the final score after the comet). A save of a
## bankrupt campaign opens on its game over.

const LOAN := "emergency_loan"
const OVER := "bankrupt"

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
## the final record is written once per campaign (tests turn it off)
var save_records := true
var _resume_speed := 0
var _busy := false
var _recorded := false


func _init(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	state.emergency_loan.connect(func(_i: Dictionary) -> void: _show_loan.call_deferred())
	state.bankrupt.connect(func(_i: Dictionary) -> void: _game_over.call_deferred())
	hud.screen_closed.connect(_on_screen_closed)
	if Bankruptcy.is_bankrupt(state):
		_game_over.call_deferred()
	elif bool(Bankruptcy.bk(state).get("show_loan", false)):
		_show_loan.call_deferred()


func _show_loan() -> void:
	if Bankruptcy.is_bankrupt(state) or not bool(Bankruptcy.bk(state).get("show_loan", false)):
		return
	if hud.current_screen() != "":
		return   # after the screen on show (_on_screen_closed)
	if clock.speed > 0:
		_resume_speed = clock.speed
	clock.set_speed(0)
	Bankruptcy.loan_shown(state)
	_open(LOAN)


func _game_over() -> void:
	clock.set_speed(0)
	if save_records and not _recorded:
		_recorded = true
		Bankruptcy.save_record(state)
	if hud.current_screen() != OVER:
		_open(OVER)


func _on_screen_closed(screen_name: String) -> void:
	if _busy:
		return
	if Bankruptcy.is_bankrupt(state):
		_reopen.call_deferred()
		return
	if screen_name == LOAN and _resume_speed > 0:
		clock.set_speed(_resume_speed)
		_resume_speed = 0
	if bool(Bankruptcy.bk(state).get("show_loan", false)):
		_show_loan.call_deferred()


func _reopen() -> void:
	if hud.current_screen() == "":
		_open(OVER)


func _open(screen_name: String) -> void:
	_busy = true
	hud.open_screen(screen_name)
	_busy = false
