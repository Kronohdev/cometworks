class_name Cutscene
extends CanvasLayer
## A story cutscene (scenes/cutscenes/<id>.tscn, an inherited scene of cutscene.tscn): the
## shots in `shots` play one after another in their own 3D world (the SubViewport %Stage, so
## the campus behind stays untouched), dipping through the night colour between them, under a
## storybook frame: letterbox bars, the line typed out in the bottom bar, title cards, and
## the skip key. Like the main menu's attract loop (MenuDirector) each shot is loaded when
## it is needed and freed when it ends.
## Everything you see is in cutscene.tscn (bars, caption, card, skip, fade) and its
## AnimationPlayer ("intro": bars and fade in, "outro": bars out); each shot keys its own
## lines, cards, sounds and Cometlings (src/cutscene/cutscene_shot.gd).
## While it plays the game is paused (the tree; this layer keeps running) and the 3D of the
## viewport behind is switched off. Controls:
##   Esc / Space / Enter / click   finish typing the line, then the next line (or shot)
##   hold one of them              skip the whole cutscene (`hold_to_skip` seconds)
##   the "Skip" key                skip the whole cutscene
## Cutscenes.play() starts one; `finished` fires after the last shot or a skip.

signal finished(skipped: bool)
## a line came up (translation key), for tests and tools
signal line_shown(key: String)
signal shot_started(shot: CutsceneShot, index: int)

## the shot scenes in order
@export_file("*.tscn") var shots: PackedStringArray = []
## the animation each shot plays ("shot"; the quick versions use "short")
@export var shot_animation := &"shot"
## music while it plays (a library track; empty keeps what plays). The music that was playing
## comes back at the end.
@export var music: StringName = &"music_menu"
## seconds of the dip out of a shot into the night colour
@export_range(0.0, 3.0, 0.05) var dip_out := 0.55
## letters per second of the typed line
@export_range(5.0, 200.0, 1.0) var type_speed := 42.0
## seconds a key or the mouse is held to skip the whole cutscene
@export_range(0.2, 5.0, 0.05) var hold_to_skip := 1.1
## seconds held before the skip ring shows (a tap never flashes it)
@export_range(0.0, 1.0, 0.05) var hold_grace := 0.18
## pause the game while it plays
@export var pause_game := true
## letterbox: 0 = no bars, 1 = the bars in (keyed by the AnimationPlayer)
@export_range(0.0, 1.0, 0.01) var bars := 0.0:
	set(v):
		bars = v
		_apply_bars()
## height of each letterbox bar at 1600x900 (scaled with the window)
@export var bar_height := 104.0

## Cutscenes id ("opening", "ending_comet"...)
var id := ""
## the player's leader (TycoonLeader format, {} = the authored Cometlings) and agency name
var leader: Dictionary = {}
var agency := "Cometworks"
var state: TycoonState
var shot: CutsceneShot
var index := -1
var skipped := false
var playing := false

var _was_paused := false
var _host_3d: Viewport
var _prev_music: StringName = &""
var _ending := false
var _busy := false
var _typing := false
var _type_t := 0.0
var _line_key := ""
var _held := false
var _hold_t := 0.0
var _requested := {}
var _fade_tw: Tween

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var frame: Control = %Frame
@onready var stage: Node3D = %Stage
@onready var view: SubViewportContainer = %View
@onready var fade: ColorRect = %Fade
@onready var bar_top: Control = %BarTop
@onready var bar_bottom: Control = %BarBottom
@onready var line_label: Label = %Line
@onready var card_box: Control = %Card
@onready var card_title: Label = %CardTitle
@onready var card_kicker: Label = %CardKicker
@onready var skip_button: Button = %Skip
@onready var hold_fill: Control = %HoldFill


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	skip_button.pressed.connect(skip_all)
	frame.gui_input.connect(_on_frame_input)
	line_label.text = ""
	line_label.visible_characters = 0
	card_box.modulate.a = 0.0
	hold_fill.scale.x = 0.0
	_apply_bars()
	get_viewport().size_changed.connect(_apply_bars)


## Sets who the cutscene is about: the leader and the agency of the campaign (none: the
## authored Cometlings and "Cometworks").
func bind_state(s: TycoonState) -> void:
	state = s
	if s:
		leader = s.leader.duplicate() if not s.leader.is_empty() else {}
		agency = s.agency_name


## Starts playing (pauses the game, the intro, the first shot; tools may start further on).
func start(from := 0) -> void:
	if playing:
		return
	playing = true
	if pause_game:
		_was_paused = get_tree().paused
		get_tree().paused = true
	if music != &"":
		_prev_music = _current_music()
		CwSfx.music(music)
	fade.modulate.a = 0.0
	view.visible = false
	if from < shots.size():
		_request(shots[from])
	anim.play("intro")
	await anim.animation_finished
	if _ending:
		return
	# the 3D of the screen behind goes dark while the cutscene's own world plays
	_host_3d = get_viewport()
	if _host_3d and not _host_3d.disable_3d:
		_host_3d.disable_3d = true
	else:
		_host_3d = null
	view.visible = true
	show_shot(from)


## Cuts to shot i (dipping through the night colour first when a shot is on).
func show_shot(i: int) -> void:
	if _busy or _ending:
		return
	if i >= shots.size():
		end()
		return
	_busy = true
	if shot:
		await _fade_to(1.0, dip_out)
		if _ending:
			_busy = false
			return
	hush()
	uncard()
	if shot:
		stage.remove_child(shot)
		shot.free()
		shot = null
	index = i
	var ps := _take(shots[i])
	if ps:
		shot = ps.instantiate() as CutsceneShot
	if shot == null:
		push_warning("Cutscene: %s is not a CutsceneShot" % shots[i])
		_busy = false
		show_shot.call_deferred(i + 1)
		return
	stage.add_child(shot)
	shot.setup(leader, state)
	shot.line.connect(say)
	shot.hushed.connect(hush)
	shot.carded.connect(card)
	shot.uncarded.connect(uncard)
	shot.finished.connect(_on_shot_finished)
	shot.play_cut(shot_animation)
	shot_started.emit(shot, index)
	if i + 1 < shots.size():
		_request(shots[i + 1])
	_busy = false
	_fade_to(0.0, shot.dip_in)


func _on_shot_finished() -> void:
	show_shot(index + 1)


## Ends the cutscene: the picture dips out, the screen behind comes back, the game goes on.
func end() -> void:
	if _ending:
		return
	_ending = true
	_typing = false
	_held = false
	hold_fill.scale.x = 0.0
	if playing:
		await _fade_to(1.0, dip_out)
	if shot:
		shot.queue_free()
		shot = null
	view.visible = false
	hush()
	card_box.modulate.a = 0.0
	if _host_3d:
		_host_3d.disable_3d = false
		_host_3d = null
	if music != &"" and playing:
		CwSfx.music(_prev_music)
	if pause_game and playing:
		get_tree().paused = _was_paused
	if playing:
		anim.play("outro")
		await anim.animation_finished
	playing = false
	finished.emit(skipped)
	queue_free()


## Skips the whole cutscene.
func skip_all() -> void:
	if _ending:
		return
	skipped = true
	CwSfx.play(&"ui_back")
	end()


## A tap: finishes typing the line, else jumps to the next line (or the next shot).
func advance() -> void:
	if _ending or _busy or shot == null:
		return
	if _typing:
		_typing = false
		line_label.visible_characters = -1
		return
	var t := shot.next_line_time()
	if t >= 0.0:
		shot.jump_to(t)
	else:
		show_shot(index + 1)


# ------------------------------------------------------------ the frame
func say(key: String) -> void:
	_line_key = key
	line_label.text = fill(tr(key))
	line_label.visible_characters = 0
	line_label.modulate.a = 1.0
	_type_t = 0.0
	_typing = true
	line_shown.emit(key)


func hush() -> void:
	_typing = false
	_line_key = ""
	line_label.text = ""
	line_label.visible_characters = 0


func card(key: String, kicker := "") -> void:
	card_title.text = fill(tr(key))
	card_kicker.text = fill(tr(kicker)) if kicker != "" else ""
	card_kicker.visible = kicker != ""
	var tw := create_tween()
	tw.tween_property(card_box, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func uncard() -> void:
	if card_box.modulate.a <= 0.0:
		return
	var tw := create_tween()
	tw.tween_property(card_box, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)


## The text of a line with the player's names in it ({leader}, {agency}).
func fill(text: String) -> String:
	var nm := String(leader.get("name", "")).strip_edges()
	if nm == "":
		nm = tr("CS_LEADER_FALLBACK")
	return text.format({"leader": nm, "agency": agency if agency.strip_edges() != "" else "Cometworks"})


## The line on screen (translation key, "" when none).
func current_line() -> String:
	return _line_key


func _apply_bars() -> void:
	if not is_node_ready():
		return
	var s := 1.0
	var vp := get_viewport()
	if vp:
		s = vp.get_visible_rect().size.y / 900.0
	var h := bar_height * s
	bar_top.offset_top = -h + h * bars
	bar_top.offset_bottom = h * bars
	bar_bottom.offset_top = -h * bars
	bar_bottom.offset_bottom = h - h * bars


func _fade_to(a: float, seconds: float) -> void:
	if _fade_tw:
		_fade_tw.kill()   # one fade at a time (a tap can cut a fade-in short)
		_fade_tw = null
	if seconds <= 0.0:
		fade.modulate.a = a
		return
	var tw := create_tween()
	_fade_tw = tw
	tw.tween_property(fade, "modulate:a", a, seconds).set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN if a > 0.5 else Tween.EASE_OUT)
	await tw.finished


func _process(delta: float) -> void:
	if _typing:
		_type_t += delta
		var n := int(_type_t * type_speed)
		if n >= line_label.get_total_character_count():
			_typing = false
			line_label.visible_characters = -1
		else:
			line_label.visible_characters = n
	if _held:
		_hold_t += delta
		var p := clampf((_hold_t - hold_grace) / maxf(hold_to_skip - hold_grace, 0.01), 0.0, 1.0)
		hold_fill.scale.x = p
		if _hold_t >= hold_to_skip:
			_held = false
			skip_all()


# ------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not playing or _ending:
		return
	if event is InputEventKey and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if not event.echo:
			_press(event.pressed)


## Freed while playing (the scene behind went away): the game must not stay paused.
func _exit_tree() -> void:
	if not playing:
		return
	playing = false
	if _host_3d and is_instance_valid(_host_3d):
		_host_3d.disable_3d = false
	if pause_game and is_inside_tree():
		get_tree().paused = _was_paused


func _on_frame_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_press(event.pressed)
		frame.accept_event()


func _press(down: bool) -> void:
	if down:
		if not _held:
			_held = true
			_hold_t = 0.0
	elif _held:
		_held = false
		hold_fill.scale.x = 0.0
		if _hold_t < hold_to_skip:
			advance()


# ------------------------------------------------------------ loading
func _request(path: String) -> void:
	if _requested.has(path) or ResourceLoader.has_cached(path):
		return
	if ResourceLoader.load_threaded_request(path, "PackedScene", true) == OK:
		_requested[path] = true


func _take(path: String) -> PackedScene:
	if _requested.has(path):
		_requested.erase(path)
		var ps := ResourceLoader.load_threaded_get(path) as PackedScene
		if ps:
			return ps
	return load(path) as PackedScene


static func _current_music() -> StringName:
	var inst := CwSfx.get_instance()
	return inst.current_music() if inst else &""
