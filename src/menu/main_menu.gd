class_name MainMenu
extends Node
## Cometworks title screen (scenes/menu/main_menu.tscn). Behind: the attract loop of shots
## (Background, src/menu/menu_director.gd). In front: the logo, the menu panel, the options
## panel, the observatory readout and the footer, all authored in the scene with the
## Cometworks theme (GDD section 22). This script only wires the buttons, plays the entry
## motion (panel slides 8 px and fades in over 140 ms), fills the readout and changes scene.
##   New campaign  -> scenes/tycoon/tycoon_main.tscn
##   Continue      -> disabled until there is a save system
##   Fair mode     -> the same scene with TycoonMain.fair_mode = true (set before it enters the tree)
##   Rocket workshop -> scenes/hangar.tscn
##   Options       -> language, fullscreen, master volume (MenuSettings)

const TYCOON := "res://scenes/tycoon/tycoon_main.tscn"
const HANGAR := "res://scenes/hangar.tscn"
const PANEL_SLIDE := 8.0
const PANEL_FADE := 0.14

var _leaving := false
var _pending := ""
var _pending_fair := false
var _caption_key := ""
var _shot_index := 0
var _menu_focus: Dictionary = {}   # Button -> focus_mode, while the options panel is open
var _options_home := Vector2.ZERO

@onready var director: MenuDirector = $Background
@onready var logo_anim: AnimationPlayer = $UI/Root/Logo/AnimationPlayer
@onready var panel: Control = %MenuPanel
@onready var new_campaign: Button = %NewCampaign
@onready var continue_button: Button = %Continue
@onready var fair: Button = %Fair
@onready var workshop: Button = %Workshop
@onready var options_button: Button = %Options
@onready var quit_button: Button = %Quit
@onready var options: MenuOptionsPanel = %OptionsPanel
@onready var peek: PeekCometling = %Peek
@onready var cam_label: Label = %CamLabel
@onready var caption: Label = %Caption
@onready var shot_bar: Control = %ShotBar
@onready var readout: Control = %Readout
@onready var transition: Control = %Transition
@onready var loading: Label = %Loading


func _ready() -> void:
	MenuSettings.apply()
	director.shot_started.connect(_on_shot_started)
	new_campaign.pressed.connect(_go.bind(TYCOON, false, "MENU_LOADING_CAMPUS"))
	fair.pressed.connect(_go.bind(TYCOON, true, "MENU_LOADING_FAIR"))
	workshop.pressed.connect(_go.bind(HANGAR, false, "MENU_LOADING_HANGAR"))
	options_button.pressed.connect(open_options)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	continue_button.disabled = true
	continue_button.focus_mode = Control.FOCUS_NONE
	new_campaign.mouse_entered.connect(new_campaign.grab_focus)
	new_campaign.focus_entered.connect(peek.peek)
	new_campaign.focus_exited.connect(peek.unpeek)
	options.closed.connect(close_options)
	options.visible = false
	_options_home = options.position
	transition.visible = false
	if director.current:
		_on_shot_started(director.current, director.index)
	_intro()


func _intro() -> void:
	logo_anim.play("intro")
	logo_anim.queue("idle")
	var home := panel.position
	panel.modulate.a = 0.0
	panel.position.y = home.y + PANEL_SLIDE
	readout.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 1.0, PANEL_FADE).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "position:y", home.y, PANEL_FADE).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(readout, "modulate:a", 1.0, 0.4).set_delay(0.8)
	tw.chain().tween_callback(new_campaign.grab_focus)


func _process(_delta: float) -> void:
	if director.current:
		shot_bar.set("value", director.current.progress())
	if _pending != "" and transition.modulate.a >= 0.999:
		var st := ResourceLoader.load_threaded_get_status(_pending)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED \
				or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_switch()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill_readout()


# ------------------------------------------------------------------ readout
func _on_shot_started(shot: MenuShot, index: int) -> void:
	_caption_key = shot.caption_key
	_shot_index = index
	_fill_readout()
	caption.modulate.a = 0.0
	create_tween().tween_property(caption, "modulate:a", 1.0, 0.6).set_delay(0.3)


func _fill_readout() -> void:
	cam_label.text = tr("MENU_CAM") % (_shot_index + 1)
	caption.text = tr(_caption_key) if _caption_key != "" else ""


# ------------------------------------------------------------------ options
func open_options() -> void:
	if options.visible:
		return
	options.sync()
	options.visible = true
	options.modulate.a = 0.0
	options.position = _options_home + Vector2(0, PANEL_SLIDE)
	var tw := create_tween().set_parallel()
	tw.tween_property(options, "modulate:a", 1.0, PANEL_FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(options, "position", _options_home, PANEL_FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# keep the keyboard inside the options while they are open
	for b: Button in [new_campaign, fair, workshop, options_button, quit_button]:
		_menu_focus[b] = b.focus_mode
		b.focus_mode = Control.FOCUS_NONE
	options.focus_first()


func close_options() -> void:
	if not options.visible:
		return
	for b: Button in _menu_focus:
		b.focus_mode = _menu_focus[b]
	_menu_focus.clear()
	var tw := create_tween()
	tw.tween_property(options, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func() -> void: options.visible = false)
	options_button.grab_focus()


# ------------------------------------------------------------------ leaving
func _go(path: String, fair_mode: bool, loading_key: String) -> void:
	if _leaving:
		return
	_leaving = true
	peek.unpeek()
	loading.text = tr(loading_key)
	transition.visible = true
	transition.modulate.a = 0.0
	create_tween().tween_property(transition, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	if ResourceLoader.load_threaded_request(path) != OK:
		push_warning("MainMenu: could not start loading %s" % path)
	_pending = path
	_pending_fair = fair_mode


func _switch() -> void:
	var path := _pending
	_pending = ""
	var ps := ResourceLoader.load_threaded_get(path) as PackedScene
	if ps == null:
		ps = load(path) as PackedScene
	if ps == null:
		push_error("MainMenu: cannot load %s" % path)
		_leaving = false
		transition.visible = false
		return
	var scene := ps.instantiate()
	# fair mode: TycoonMain reads its export in _ready, so set it before the scene enters the tree
	if _pending_fair and "fair_mode" in scene:
		scene.set("fair_mode", true)
	get_tree().change_scene_to_node(scene)


# ------------------------------------------------------------------ screenshot helpers
func debug_hover_new_campaign() -> void:
	fair.grab_focus()
	await get_tree().create_timer(0.4).timeout
	new_campaign.grab_focus()


func debug_unhover() -> void:
	fair.grab_focus()
