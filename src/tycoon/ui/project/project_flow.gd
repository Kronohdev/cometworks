class_name ProjectFlow
extends Node
## Routes mission project events to the HUD screens (E1, E2; a new project goes briefing board ->
## objective -> payload planner -> team -> rocket designer): a phase that starts opens the
## phase screen (scenes/tycoon/ui/screens/project_phase.tscn), a project that ends its
## development opens its Design Review (design_review.tscn: it turns TycoonState.review_gate
## on, so projects wait for the player there; the rocket designer, rocket_designer.tscn, opens
## from New project and from the review), a launch plays the launch
## sequence (screen "launch": scenes/tycoon/launch/launch_sequence.tscn, unless turned off in
## the settings) and then opens the review (project_review.tscn). While one of the project screens (or New project) is up the clock
## is paused, and it resumes at the old speed when the last one closes. Decisions never
## interrupt each other: events that arrive while one is on screen wait in a queue.
## A launch always comes first: a waiting launch (and then its review) goes ahead of the other
## waiting project screens, and the race's newspaper (TycoonRaceFlow.wait_for) waits for it,
## so the paper never reports a launch the player has not seen yet.
## A rocket built in the hangar stops on the pad first (TycoonState.pilot_gate, turned on here):
## the launch choice (launch_choice.tscn) asks to fly it (the flight mode inside the campus,
## TycoonModes) or simulate it; a piloted launch skips the launch sequence (the player just
## flew it) and goes straight to its review.
## tycoon_main adds one of these and calls bind().

const PROJECT_SCREENS: Array[String] = ["new_project", "project_phase", "project_review", "launch", "rocket_designer",
	"design_review", "briefings", "payload_planner", "project_team", "launch_choice"]
## screens a project screen waits behind (the race's newspaper and finale included)
const DECISIONS: Array[String] = ["project_phase", "project_review", "newspaper", "finale", "final_score", "launch",
	"design_review", "rocket_designer", "launch_choice"]
const REVIEW := "design_review"
const LAUNCH := "launch"
const PAD := "launch_choice"
## screens that jump the queue, in this order: the launch, then its review
const FIRST: Array[String] = ["launch", "project_review"]

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var _queue: Array[Dictionary] = []
var _resume_speed := 1
var _paused_by_us := false
var _switching := false
## play the launch sequence before the review (also needs LaunchSequence.enabled())
var launch_cinematic := true


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	state.project_phase_started.connect(func(id: String, _k: int) -> void:
		show_screen("project_phase", {"project_id": id}))
	# E2: development ends in the Design Review, which waits for the player
	state.review_gate = true
	state.project_review_ready.connect(func(id: String) -> void:
		if not _showing(REVIEW, id):
			show_screen(REVIEW, {"project_id": id}))
	# a rocket built in the hangar waits on the pad: fly it or simulate it
	state.pilot_gate = true
	state.launch_pad_ready.connect(func(id: String) -> void:
		if not _showing(PAD, id):
			show_screen(PAD, {"project_id": id}))
	state.mission_launching.connect(func(r: Dictionary) -> void:
		if launch_cinematic and LaunchSequence.enabled() and not r.get("piloted", false):
			show_screen(LAUNCH, {"result": r}))
	state.mission_launched.connect(func(r: Dictionary) -> void:
		show_screen("project_review", {"project_id": String(r.get("project_id", ""))}))
	hud.screen_opened.connect(func(n: String) -> void:
		if n in PROJECT_SCREENS:
			_pause())
	hud.screen_closed.connect(_on_closed)
	# the newspaper waits while a launch (or its review) waits here
	var main := h.owner as TycoonMain
	if main and main.race_flow:
		main.race_flow.wait_for = has_waiting_launch
	# a loaded game: reviews that were waiting come back
	for p in ProjectDesk.waiting_review(state):
		show_screen.call_deferred(REVIEW, {"project_id": p.id})
	for p in ProjectDesk.waiting_pad(state):
		show_screen.call_deferred(PAD, {"project_id": p.id})


## Is this screen (for this project) on show or waiting already?
func _showing(screen_name: String, project_id: String) -> bool:
	if hud.current_screen() == screen_name:
		var scr := hud.get_node("%Screens").get_child(0) if hud.get_node("%Screens").get_child_count() > 0 else null
		if scr and String(scr.get("project_id") if "project_id" in scr else "") == project_id:
			return true
	for n in _queue:
		if String(n["name"]) == screen_name and String(n["args"].get("project_id", "")) == project_id:
			return true
	return false


## Opens a project screen now, or queues it behind the decision on show.
func show_screen(screen_name: String, args: Dictionary) -> void:
	_pause()
	if hud.current_screen() in DECISIONS:
		_enqueue({"name": screen_name, "args": args})
		return
	_open(screen_name, args)


## True while a launch or its review waits in the queue (they go before anything else).
func has_waiting_launch() -> bool:
	for n in _queue:
		if String(n["name"]) in FIRST:
			return true
	return false


## The names waiting, in the order they will open (for tests and debugging).
func queued() -> Array[String]:
	var out: Array[String] = []
	for n in _queue:
		out.append(String(n["name"]))
	return out


## Dev only (src/dev/cw_dev.gd skips phases): forgets the phase screens of a project, waiting or
## on show, so the next screen (its next phase, its Design Review) comes up at once.
func dev_drop_phases(project_id: String) -> void:
	_queue.assign(_queue.filter(func(n: Dictionary) -> bool:
		return not (String(n["name"]) == "project_phase" and String(n["args"].get("project_id", "")) == project_id)))
	if hud.current_screen() == "project_phase":
		hud.close_screen()


func _enqueue(entry: Dictionary) -> void:
	if String(entry["name"]) not in FIRST:
		_queue.append(entry)
		return
	# after the launches and reviews already waiting, before everything else
	var at := 0
	while at < _queue.size() and String(_queue[at]["name"]) in FIRST:
		at += 1
	_queue.insert(at, entry)


func _open(screen_name: String, args: Dictionary) -> void:
	_switching = true
	hud.open_screen(screen_name, args)
	_switching = false


func _on_closed(screen_name: String) -> void:
	if _switching or (screen_name not in PROJECT_SCREENS and screen_name not in DECISIONS):
		return
	_next.call_deferred()


func _next() -> void:
	if hud.current_screen() != "":
		return
	while not _queue.is_empty():
		var n: Dictionary = _queue.pop_front()
		# a phase decision for a project that already launched is moot, a review too once decided
		if n["name"] == "project_phase" and ProjectDesk.find(state, String(n["args"].get("project_id", ""))) == null:
			continue
		if n["name"] == REVIEW:
			var rp := ProjectDesk.find(state, String(n["args"].get("project_id", "")))
			if rp == null or rp.review_state != "waiting":
				continue
		if n["name"] == PAD:
			var pp := ProjectDesk.find(state, String(n["args"].get("project_id", "")))
			if pp == null or pp.review_state != "pad":
				continue
		_open(String(n["name"]), n["args"])
		return
	_resume()


func _pause() -> void:
	if clock == null or clock.speed == 0:
		return
	_resume_speed = clock.speed
	_paused_by_us = true
	clock.set_speed(0)


func _resume() -> void:
	if _paused_by_us and clock and clock.speed == 0:
		clock.set_speed(_resume_speed)
	_paused_by_us = false
