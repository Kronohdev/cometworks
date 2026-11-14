class_name TycoonRaceFlow
extends RefCounted
## Wires the race into the tycoon scene (TycoonMain keeps one): shows the newspaper front
## pages the RaceDirector prints (one at a time, pausing the clock, waiting while another
## screen is open), opens the finale when the Mother-Ice passes, and autosaves every month
## to TycoonSave's "auto" slot (at the end of the week, so the save is a whole week).

const PAPER := "newspaper"
const FINALE := "finale"
const SCORE := "final_score"

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var autosave := true
## optional: returns true while another flow has screens that must come before the paper
## (ProjectFlow.has_waiting_launch: a launch and its review always come first)
var wait_for := Callable()
## optional: called with a Callable that opens the finale before it opens; returns true when
## something plays first (the ending cutscene, TycoonMain) and will call it when done
var before_finale := Callable()
var _resume_speed := 0
var _busy := false
var _autosave_due := false


func _init(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	state.race.front_page.connect(func(_p: Dictionary) -> void: _next_page())
	state.race.campaign_finished.connect(func(_r: Dictionary) -> void: show_finale())
	state.month_passed.connect(func(_y: int, _m: int) -> void: _autosave_due = true)
	state.changed.connect(_on_changed)
	hud.screen_closed.connect(_on_screen_closed)
	if state.race.finished:
		show_finale.call_deferred()
	else:
		_next_page.call_deferred()


func _on_changed() -> void:
	if _autosave_due and autosave:
		_autosave_due = false
		TycoonSave.save(state, TycoonSave.AUTO, {"fair_mode": clock.fair_mode})


## Shows the oldest pending front page when the campus is on screen.
func _next_page() -> void:
	if _busy or state.race.finished or hud.current_screen() != "" or state.race.pending_pages.is_empty():
		return
	if wait_for.is_valid() and bool(wait_for.call()):
		return  # the launch first; this is called again when its screens close
	var page := state.race.pop_page()
	if clock.speed > 0:
		_resume_speed = clock.speed
	clock.set_speed(0)
	_busy = true
	hud.open_screen(PAPER, {"page": page})
	_busy = false


func _on_screen_closed(screen_name: String) -> void:
	if _busy:
		return
	if state.race.finished:
		# after the comet the report stays up: closing any screen brings it back
		_reopen_score.call_deferred()
		return
	if screen_name == PAPER:
		if state.race.pending_pages.is_empty():
			if _resume_speed > 0:
				clock.set_speed(_resume_speed)
			_resume_speed = 0
		else:
			_next_page.call_deferred()
	else:
		_next_page.call_deferred()


func show_finale() -> void:
	clock.set_speed(0)
	state.race.pending_pages.clear()
	if before_finale.is_valid() and bool(before_finale.call(_open.bind(FINALE))):
		return
	_open(FINALE)


func _reopen_score() -> void:
	if hud.current_screen() == "":
		_open(SCORE)


func _open(screen_name: String) -> void:
	if hud.current_screen() == screen_name:
		return
	_busy = true
	hud.open_screen(screen_name)
	_busy = false
