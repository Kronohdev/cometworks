class_name TycoonTutorial
extends Control
## Vovô Edmundo Halleyzinho's lessons on the main screen (scenes/tycoon/ui/tutorial/tutorial.tscn,
## on its own CanvasLayer above the HUD and its screens in tycoon_main.tscn). Everything visual is
## in the scene: the speech bubble with his live portrait (halley_portrait.tscn), the soft
## Spotlight (shaders/cw_tutorial_spotlight.gdshader), the Ring around the node he talks about,
## the bobbing Pointer and three spots for the bubble (SpotBottom, SpotTop, SpotCenter). This
## script reads the lessons (TutorialBook, data/tycoon/tutorials.json), starts each the first
## time its trigger happens (the campus, a screen, the lot panel, a TycoonState signal), types
## his lines, lights up the step's target and waits for its advance (Próximo, a click on the
## target, a screen, a signal).
##   - the clock holds while a lesson is up on the campus and picks up its speed after
##   - Esc skips the lesson on show (and nothing else: the Esc chain carries on next press)
##   - "Não mostrar mais" turns the lessons off (TutorialBook.set_enabled)
##   - progress is saved with the campaign (TycoonState.tutorials); lessons that trigger while
##     one is up wait in a queue; a screen lesson ends when its screen closes
##   - start(id, true) replays a lesson (the library screen, library_screen.gd)
##   - a HUD menu a new career unlocks (HudUnlocker) calls on_unlocked(item): its "unlock" lesson
## Lessons only start by themselves in the real game: test scripts (a SceneTree script as the
## main loop) turn auto_start off unless TycoonTutorial.allow_in_scripts is set.

signal lesson_started(id: String)
signal lesson_finished(id: String, skipped: bool)
signal step_shown(id: String, index: int)

## lessons start by themselves when their trigger happens
@export var auto_start := true
## letters per second of the typewriter
@export var type_speed := 55.0
## seconds the campus waits before the first lesson (lets the camera settle)
@export var campus_delay := 1.2

## tests that drive the game from a script set this to let lessons start by themselves
static var allow_in_scripts := false

var main: TycoonMain
var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD

var _lesson: Dictionary = {}
var _step := -1
var _replay := false
var _queue: Array[String] = []
var _shown := 0.0
var _typing := false
var _target: Control
var _target_scope := ""
var _click_btn: BaseButton
var _wait_screen := ""
var _wait_signal := ""
var _paused_by_us := false
var _resume_speed := 1
var _campus_wait := 0.0
var _last_lot := ""
var _t := 0.0
var _connected_signals: Array[String] = []

@onready var bubble: PanelContainer = %Bubble
@onready var text_label: Label = %Text
@onready var spotlight: ColorRect = %Spotlight
@onready var ring: Panel = %Ring
@onready var pointer: TextureRect = %Pointer
@onready var halley: Halleyzinho = %Portrait.get_node("Viewport/Halley")


func _ready() -> void:
	%Next.pressed.connect(next)
	%Skip.pressed.connect(skip)
	%NeverAgain.pressed.connect(never_again)
	text_label.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and _typing:
			_finish_typing())
	_hide_all()
	if _scripted() and not allow_in_scripts:
		auto_start = false


## Hooks the lessons to the main screen (TycoonMain calls this once the HUD is bound).
func bind(m: TycoonMain) -> void:
	main = m
	state = m.state
	clock = m.clock
	hud = m.hud
	hud.screen_opened.connect(_on_screen_opened)
	hud.screen_closed.connect(_on_screen_closed)
	for l: Dictionary in TutorialBook.lessons():
		var t: Dictionary = l.get("trigger", {})
		if String(t.get("on", "")) == "signal":
			_listen(String(t.get("signal", "")))
	_campus_wait = campus_delay


static func _scripted() -> bool:
	var ml := Engine.get_main_loop()
	return ml != null and ml.get_script() != null


## True while a bubble is on show.
func is_showing() -> bool:
	return not _lesson.is_empty()


func current_lesson() -> String:
	return String(_lesson.get("id", ""))


func current_step() -> int:
	return _step


## Lessons waiting for the one on show to end.
func queued() -> Array[String]:
	return _queue.duplicate()


## The node the current step lights up (null when none).
func current_target() -> Control:
	return _target if is_instance_valid(_target) else null


## Starts lesson `id` now (or after the one on show). `replay` shows it again even when the
## campaign has seen it and the lessons are off.
func start(id: String, replay := false) -> bool:
	var l := TutorialBook.lesson(id)
	if l.is_empty():
		return false
	if is_showing():
		if current_lesson() == id:
			return true
		if replay:
			_end(true)
		else:
			if not id in _queue:
				_queue.append(id)
			return true
	if not replay:
		TutorialBook.mark_seen(state, id)
	_lesson = l
	_replay = replay
	_step = -1
	_pause_clock()
	lesson_started.emit(id)
	CwSfx.play(&"ui_open")
	_show_step(0)
	return true


## Próximo: completes the line being typed, else goes to the next step (or ends).
func next() -> void:
	if not is_showing():
		return
	if _typing:
		_finish_typing()
		return
	if _step + 1 >= steps().size():
		_end(false)
	else:
		_show_step(_step + 1)


## Pular (and Esc): ends the lesson on show; it stays seen.
func skip() -> void:
	if is_showing():
		CwSfx.play(&"ui_back")
		_end(true)


## Não mostrar mais: no more lessons by themselves (the library still replays them).
func never_again() -> void:
	TutorialBook.set_enabled(false)
	_queue.clear()
	skip()
	if hud:
		hud.flash_hint(tr("TUT_OFF_HINT"), 5.0)


func steps() -> Array:
	return _lesson.get("steps", [])


# ------------------------------------------------------------ triggers
func _can_auto() -> bool:
	return auto_start and state != null and TutorialBook.enabled()


func _try(l: Dictionary) -> void:
	if _can_auto() and TutorialBook.ready_for(state, l):
		start(String(l["id"]))


func _on_screen_opened(screen_name: String) -> void:
	# a step waiting for this screen goes on
	if is_showing() and _wait_screen == screen_name:
		next.call_deferred()
	elif is_showing() and _target_scope == "hud" and String(_lesson.get("trigger", {}).get("on", "")) != "screen":
		# a campus lesson does not talk over a screen the player opened
		_end(true)
	for l in TutorialBook.triggered_by("screen", screen_name):
		_try.call_deferred(l)


## A HUD menu just appeared in a new career (HudUnlocker): its lesson starts (trigger "unlock").
func on_unlocked(item_id: String) -> void:
	for l in TutorialBook.triggered_by("unlock", item_id):
		_try(l)


func _on_screen_closed(screen_name: String) -> void:
	if not is_showing():
		return
	var t: Dictionary = _lesson.get("trigger", {})
	var replay_screen := String(_lesson.get("replay", ""))
	var lesson_screen := String(t.get("screen", replay_screen if _replay else ""))
	if lesson_screen == screen_name and (String(t.get("on", "")) == "screen" or _replay):
		_end(true)


func _listen(sig: String) -> void:
	if sig == "" or sig in _connected_signals or not state.has_signal(sig):
		return
	_connected_signals.append(sig)
	var argc := 0
	for s in state.get_signal_list():
		if String(s["name"]) == sig:
			argc = (s["args"] as Array).size()
	match argc:
		0:
			state.connect(sig, func() -> void: _on_state_signal(sig, null))
		1:
			state.connect(sig, func(a: Variant) -> void: _on_state_signal(sig, a))
		_:
			state.connect(sig, func(a: Variant, _b: Variant) -> void: _on_state_signal(sig, a))


func _on_state_signal(sig: String, arg: Variant) -> void:
	if is_showing() and _wait_signal == sig:
		next.call_deferred()
	for l in TutorialBook.triggered_by("signal", sig):
		var t: Dictionary = l.get("trigger", {})
		if t.has("min") and (arg == null or float(arg) < float(t["min"])):
			continue
		_try.call_deferred(l)


## The campus with nothing on top: no screen, no cutscene, no hangar or flight.
func _campus_free() -> bool:
	if hud == null or hud.current_screen() != "":
		return false
	if Cutscenes.is_playing():
		return false
	if main and main.modes and main.modes.is_open():
		return false
	return true


# ------------------------------------------------------------ frame
func _process(delta: float) -> void:
	_t += delta
	if state == null:
		return
	var on_mode := main != null and main.modes != null and main.modes.is_open()
	visible = not on_mode and not Cutscenes.is_playing()
	if not is_showing():
		if not _queue.is_empty() and (_campus_free() or not hud.current_screen() in ["", "launch"]):
			var id: String = _queue.pop_front()
			var l := TutorialBook.lesson(id)
			var t: Dictionary = l.get("trigger", {})
			# a waiting screen lesson only makes sense on its screen
			if String(t.get("on", "")) != "screen" or hud.current_screen() == String(t.get("screen", "")):
				start(id)
		elif _campus_free() and _can_auto():
			if _campus_wait > 0.0:
				_campus_wait -= delta
			else:
				for l in TutorialBook.triggered_by("campus"):
					_try(l)
		if hud.lot_id != "" and hud.lot_id != _last_lot and _campus_free():
			for l in TutorialBook.triggered_by("lot"):
				_try(l)
		_last_lot = hud.lot_id
		return
	_last_lot = hud.lot_id
	if _typing:
		_shown += delta * type_speed
		var total := text_label.get_total_character_count()
		text_label.visible_characters = int(_shown)
		if int(_shown) >= total:
			_finish_typing()
	_place()


func _input(event: InputEvent) -> void:
	if not is_showing() or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		skip()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ steps
func _show_step(i: int) -> void:
	_disconnect_click()
	_step = i
	var st: Dictionary = steps()[i]
	var n := steps().size()
	%Lesson.text = tr(String(_lesson.get("title", "")))
	%Step.text = tr("TUT_STEP") % [i + 1, n]
	%Next.text = tr("TUT_DONE") if i + 1 >= n else tr("TUT_NEXT")
	%NeverAgain.visible = not _replay
	text_label.text = tr(String(st.get("line", "")))
	_shown = 0.0
	_typing = not CwMotion.reduced()
	text_label.visible_characters = 0 if _typing else -1
	if not _typing:
		_finish_typing()
	else:
		halley.talk(true)
	# the target and how the step goes on
	_resolve_target(st)
	var adv: Dictionary = st.get("advance", {})
	_wait_screen = String(adv.get("screen", "")) if String(adv.get("on", "")) == "screen" else ""
	_wait_signal = String(adv.get("signal", "")) if String(adv.get("on", "")) == "signal" else ""
	if String(adv.get("on", "")) == "signal":
		_listen(_wait_signal)
	if String(adv.get("on", "")) == "click" and _target is BaseButton:
		_click_btn = _target as BaseButton
		_click_btn.pressed.connect(_on_target_pressed)
	var pose := String(st.get("pose", ""))
	if pose != "":
		_pose.call_deferred(pose)
	bubble.visible = true
	CwMotion.poke(bubble)
	CwSfx.play(&"voice_babble", 0.78)
	_place()
	step_shown.emit(current_lesson(), i)


func _pose(pose: String) -> void:
	if not is_instance_valid(halley):
		return
	if pose in Halleyzinho.HABITS:
		halley.talk(false)
		halley.play_habit(pose)
	elif Cometling.ONESHOTS.has(pose):
		halley.play(pose)


func _finish_typing() -> void:
	_typing = false
	text_label.visible_characters = -1
	if is_instance_valid(halley):
		halley.talk(false)


func _on_target_pressed() -> void:
	_disconnect_click()
	next.call_deferred()
	if _typing:
		_finish_typing()


func _disconnect_click() -> void:
	if is_instance_valid(_click_btn) and _click_btn.pressed.is_connected(_on_target_pressed):
		_click_btn.pressed.disconnect(_on_target_pressed)
	_click_btn = null


## The step's target node, from the HUD or the screen on show (null when it is not there).
func _resolve_target(st: Dictionary) -> void:
	_target = null
	var sp := TutorialBook.target_of(_lesson, st)
	_target_scope = String(sp[0])
	var path := String(sp[1])
	if path == "":
		if _target_scope == "":
			_target_scope = "screen" if String(_lesson.get("trigger", {}).get("on", "")) == "screen" else "hud"
		return
	var root: Node = null
	if _target_scope == "hud":
		root = hud
	elif hud and hud.get_node("%Screens").get_child_count() > 0:
		root = hud.get_node("%Screens").get_child(0)
	if root:
		_target = root.get_node_or_null(NodePath(path)) as Control


func _end(skipped: bool) -> void:
	var id := current_lesson()
	_disconnect_click()
	_lesson = {}
	_step = -1
	_typing = false
	_target = null
	_wait_screen = ""
	_wait_signal = ""
	_hide_all()
	if is_instance_valid(halley):
		halley.talk(false)
	_resume_clock()
	if id != "":
		lesson_finished.emit(id, skipped)


func _hide_all() -> void:
	bubble.visible = false
	spotlight.visible = false
	ring.visible = false
	pointer.visible = false


# ------------------------------------------------------------ layout
## Puts the bubble in its spot (away from the target), the ring and the pointer on the target and
## the spotlight's hole around it. Runs every frame: targets move (scrolls, tweens, resizes).
func _place() -> void:
	var t := current_target()
	var has_t := t != null and t.is_visible_in_tree() and t.size.x > 0.0
	var view := get_rect().size
	var r := Rect2()
	if has_t:
		var xf := get_global_transform().affine_inverse() * t.get_global_transform_with_canvas()
		r = Rect2(xf.origin, t.size * xf.get_scale()).grow(6.0)
		r = r.intersection(Rect2(Vector2.ZERO, view))
		has_t = r.size.x > 4.0 and r.size.y > 4.0
	# the bubble's spot
	var st: Dictionary = steps()[_step] if _step >= 0 and _step < steps().size() else {}
	var place := String(st.get("place", "auto"))
	var spot: Control = %SpotBottom
	if place == "top" or (place in ["auto", ""] and has_t and r.get_center().y > view.y * 0.5):
		spot = %SpotTop
	elif place == "center":
		spot = %SpotCenter
	elif place in ["auto", ""] and has_t and r.intersects(Rect2(%SpotBottom.position, %SpotBottom.size)):
		spot = %SpotTop
	var bs := bubble.get_combined_minimum_size()
	bubble.size = Vector2(maxf(bs.x, spot.size.x), bs.y)
	var bp := spot.position + Vector2((spot.size.x - bubble.size.x) * 0.5, (spot.size.y - bubble.size.y) * 0.5)
	if spot == %SpotBottom:
		bp.y = spot.position.y + spot.size.y - bubble.size.y
	elif spot == %SpotTop:
		bp.y = spot.position.y
	bubble.position = bp.clamp(Vector2(8, 8), (view - bubble.size - Vector2(8, 8)).max(Vector2(8, 8)))
	# spotlight, ring and pointer
	spotlight.visible = has_t
	ring.visible = has_t
	pointer.visible = has_t
	if not has_t:
		return
	var mat := spotlight.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", view)
	mat.set_shader_parameter("hole", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	var pulse := 0.0 if CwMotion.reduced() else sin(_t * 4.0) * 2.0
	ring.position = r.position - Vector2(pulse, pulse)
	ring.size = r.size + Vector2(pulse, pulse) * 2.0
	var bob := 0.0 if CwMotion.reduced() else absf(sin(_t * 3.2)) * 8.0
	var below := r.position.y < pointer.size.y + 24.0
	pointer.rotation = PI if below else 0.0
	var px := clampf(r.get_center().x - pointer.size.x * 0.5, 4.0, view.x - pointer.size.x - 4.0)
	if below:
		pointer.position = Vector2(px, r.end.y + 4.0 + bob)
	else:
		pointer.position = Vector2(px, r.position.y - pointer.size.y - 4.0 - bob)


# ------------------------------------------------------------ clock
func _pause_clock() -> void:
	if clock == null or clock.speed == 0 or _paused_by_us:
		return
	_resume_speed = clock.speed
	_paused_by_us = true
	clock.set_speed(0)


func _resume_clock() -> void:
	if not _paused_by_us:
		return
	_paused_by_us = false
	if clock == null or clock.speed != 0:
		return
	# a screen that holds the game still (the project screens, the pause menu) takes over the
	# pause and gives the speed back when it closes
	var scr: Node = null
	if hud and hud.get_node("%Screens").get_child_count() > 0:
		scr = hud.get_node("%Screens").get_child(0)
	if scr and hud.current_screen() in ProjectFlow.PROJECT_SCREENS:
		var flow := _project_flow()
		if flow and not flow._paused_by_us:
			flow._paused_by_us = true
			flow._resume_speed = _resume_speed
		return
	if scr and "_resume_speed" in scr:
		if int(scr.get("_resume_speed")) == 0:
			scr.set("_resume_speed", _resume_speed)
		return
	clock.set_speed(_resume_speed)


func _project_flow() -> ProjectFlow:
	if main:
		for c in main.get_children():
			if c is ProjectFlow:
				return c
	return null
