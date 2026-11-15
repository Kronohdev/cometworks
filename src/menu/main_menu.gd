class_name MainMenu
extends Node
## Cometworks title screen (scenes/menu/main_menu.tscn). Behind: the attract loop of shots
## (Background, src/menu/menu_director.gd), each with its own soft ambience; the menu theme
## comes from the MusicCue node (CwMusicCue). In front: the logo, the menu panel, the options
## panel, the observatory readout and the footer, all authored in the scene with the
## Cometworks theme (GDD section 22). This script only wires the buttons, plays the entry
## motion (panel slides 8 px and fades in over 140 ms), fills the readout and changes scene.
##   New campaign  -> the leader creator, then scenes/tycoon/tycoon_main.tscn (the opening
##                    cutscene plays first, src/cutscene/)
##   Continue      -> the newest save (TycoonSave), the same scene with TycoonMain.load_slot set
##   Fair mode     -> the same scene with TycoonMain.fair_mode = true (set before it enters the tree)
##                    and the 15 s opening
##   Demonstration -> the Demonstração panel (MenuDemoPanel): a ready save at the start of
##                    each era and a fair-mode start (TycoonSave.DEMOS), opened like Continue
##   Rocket workshop -> scenes/hangar.tscn
##   Solar System  -> scenes/solar_system/solar_system.tscn (the campaign's map on its own, today's sky)
##   Surfaces      -> the surface picker (SurfacePicker): free play on any planet surface, with
##                    the rover when the rover side exists, else the body's drone (SurfaceFreePlay)
##   Options       -> language, fullscreen, master volume (MenuSettings)
##   Achievements  -> the badge book of the profile (scenes/tycoon/ui/screens/achievements.tscn,
##                    AchievementsScreen, opened over the menu without a campaign)

const TYCOON := "res://scenes/tycoon/tycoon_main.tscn"
const HANGAR := "res://scenes/hangar.tscn"
const SOLAR := "res://scenes/solar_system/solar_system.tscn"
## New campaign first makes the player's leader Cometling (LeaderCreator opens the tycoon)
const LEADER_CREATOR := "res://scenes/tycoon/ui/screens/leader_creator.tscn"
## the badge book, opened over the menu (Achievements)
const ACHIEVEMENTS := "res://scenes/tycoon/ui/screens/achievements.tscn"
const PANEL_SLIDE := 8.0
const PANEL_FADE := 0.14

var _leaving := false
var _pending := ""
var _pending_fair := false
var _pending_slot := ""   # TycoonSave slot for Continue
var _caption_key := ""
var _shot_index := 0
var _menu_focus: Dictionary = {}   # Button -> focus_mode, while the options panel is open
var _options_home := Vector2.ZERO
var _demo_home := Vector2.ZERO

@onready var director: MenuDirector = $Background
@onready var logo_anim: AnimationPlayer = $UI/Root/Logo/AnimationPlayer
@onready var panel: Control = %MenuPanel
@onready var new_campaign: Button = %NewCampaign
@onready var continue_button: Button = %Continue
@onready var fair: Button = %Fair
@onready var demo: Button = %Demo
@onready var workshop: Button = %Workshop
@onready var solar: Button = %SolarSystem
@onready var surfaces: Button = %Surfaces
@onready var surface_picker: SurfacePicker = %SurfacePicker
@onready var options_button: Button = %Options
@onready var quit_button: Button = %Quit
@onready var achievements_button: Button = get_node_or_null("%Achievements")
@onready var options: MenuOptionsPanel = %OptionsPanel
@onready var demo_panel: MenuDemoPanel = %DemoPanel
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
	new_campaign.pressed.connect(_go.bind(LEADER_CREATOR, false, "TY_LEADER_PREPARING"))
	fair.pressed.connect(_go.bind(TYCOON, true, "MENU_LOADING_FAIR"))
	workshop.pressed.connect(_go.bind(HANGAR, false, "MENU_LOADING_HANGAR"))
	solar.pressed.connect(_go.bind(SOLAR, false, "SSM_LOADING"))
	surfaces.pressed.connect(surface_picker.open)
	surface_picker.chosen.connect(open_surface)
	options_button.pressed.connect(open_options)
	demo.pressed.connect(open_demos)
	demo_panel.closed.connect(close_demos)
	demo_panel.chosen.connect(open_demo)
	demo_panel.visible = false
	_demo_home = demo_panel.position
	demo.disabled = TycoonSave.demos().is_empty()
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	if achievements_button:
		achievements_button.pressed.connect(open_achievements)
	_setup_continue()
	new_campaign.mouse_entered.connect(new_campaign.grab_focus)
	new_campaign.focus_entered.connect(peek.peek)
	new_campaign.focus_exited.connect(peek.unpeek)
	options.closed.connect(close_options)
	options.visible = false
	_options_home = options.position
	# the options grow with their page (Access lists the keys): keep them inside the view
	options.resized.connect(func() -> void:
		if options.visible:
			options.position = _options_target())
	fit_layout()
	fit_layout.call_deferred()   # once the card has its final size
	get_viewport().size_changed.connect(fit_layout)
	transition.visible = false
	if director.current:
		_on_shot_started(director.current, director.index)
	_intro()


## Text sizes above 100 % (CwAccess) shrink the logical view: the logo, the Cometling peeking
## behind the card and the menu card scale down together around the logo's corner until the
## card ends above the footer (at 100 % nothing changes).
func fit_layout() -> void:
	var col: Array[Control] = [$UI/Root/Logo, peek, panel]
	for c in col:
		if c.has_meta(&"_menu_fit"):
			c.position = c.get_meta(&"_menu_fit")
			c.scale = Vector2.ONE
			c.remove_meta(&"_menu_fit")
	var origin := ($UI/Root/Logo as Control).position
	var floor_y := ($UI/Root/Footer as Control).get_global_rect().position.y - CwUiFit.MARGIN
	var need := panel.position.y + maxf(panel.size.y, panel.get_combined_minimum_size().y) - origin.y
	var s := minf(1.0, (floor_y - origin.y) / maxf(need, 1.0))
	if s >= 1.0:
		return
	for c in col:
		c.set_meta(&"_menu_fit", c.position)
		c.scale = Vector2(s, s)
		c.position = origin + (c.position - origin) * s


## Where the options panel opens: its home, scaled and lifted to stay inside the view.
func _options_target() -> Vector2:
	var view := CwUiFit.view_of(options)
	var sz := options.size
	var s := minf(1.0, minf(view.size.y / maxf(sz.y, 1.0), (view.end.x - _options_home.x) / maxf(sz.x, 1.0)))
	options.scale = Vector2(s, s)
	return Vector2(_options_home.x, clampf(_options_home.y, view.position.y, view.end.y - sz.y * s))


func _intro() -> void:
	logo_anim.play("intro")
	logo_anim.queue("idle")
	panel.modulate.a = 0.0
	# the slide is drawn (a CwMotion channel), so the card's place stays fit_layout()'s
	CwMotion.set_channel(panel, &"intro", Vector2(0, PANEL_SLIDE))
	readout.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 1.0, PANEL_FADE).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(y: float) -> void: CwMotion.set_channel(panel, &"intro", Vector2(0, y)),
		PANEL_SLIDE, 0.0, PANEL_FADE).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
	if demo_panel.visible:
		close_demos()
	options.sync()
	CwSfx.play(&"ui_open")
	options.visible = true
	options.modulate.a = 0.0
	var home := _options_target()
	options.position = home + Vector2(0, PANEL_SLIDE)
	var tw := create_tween().set_parallel()
	tw.tween_property(options, "modulate:a", 1.0, PANEL_FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(options, "position", home, PANEL_FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# keep the keyboard inside the options while they are open
	_lock_menu()
	options.focus_first()


## Keeps the keyboard inside an open side panel (options, demonstration).
func _lock_menu() -> void:
	if not _menu_focus.is_empty():
		return
	for b: Button in [new_campaign, continue_button, fair, demo, workshop, solar, surfaces, options_button, quit_button,
			achievements_button]:
		if b == null:
			continue
		_menu_focus[b] = b.focus_mode
		b.focus_mode = Control.FOCUS_NONE


func close_options() -> void:
	if not options.visible:
		return
	CwSfx.play(&"ui_close")
	_unlock_menu()
	var tw := create_tween()
	tw.tween_property(options, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func() -> void: options.visible = false)
	options_button.grab_focus()


func _unlock_menu() -> void:
	for b: Button in _menu_focus:
		b.focus_mode = _menu_focus[b]
	_menu_focus.clear()


# ------------------------------------------------------------------ achievements
## The profile's badge book over the menu (its own × or Esc closes it).
func open_achievements() -> void:
	var root := $UI/Root as Control
	if root.get_node_or_null("Achievements"):
		return
	if options.visible:
		close_options()
	if demo_panel.visible:
		close_demos()
	CwSfx.play(&"ui_open")
	var scr := (load(ACHIEVEMENTS) as PackedScene).instantiate() as Control
	scr.name = "Achievements"
	root.add_child(scr)
	root.move_child(scr, transition.get_index())   # under the scene change's fade
	scr.tree_exited.connect(func() -> void:
		if is_inside_tree() and achievements_button:
			achievements_button.grab_focus())


# ------------------------------------------------------------------ demonstration saves
func open_demos() -> void:
	if demo_panel.visible:
		return
	if options.visible:
		close_options()
	demo_panel.fill()
	CwSfx.play(&"ui_open")
	demo_panel.visible = true
	demo_panel.modulate.a = 0.0
	demo_panel.position = _demo_home + Vector2(0, PANEL_SLIDE)
	var tw := create_tween().set_parallel()
	tw.tween_property(demo_panel, "modulate:a", 1.0, PANEL_FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(demo_panel, "position", _demo_home, PANEL_FADE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_lock_menu()
	demo_panel.focus_first()


func close_demos() -> void:
	if not demo_panel.visible:
		return
	CwSfx.play(&"ui_close")
	_unlock_menu()
	var tw := create_tween()
	tw.tween_property(demo_panel, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func() -> void: demo_panel.visible = false)
	demo.grab_focus()


## Opens a demonstration save (a TycoonSave slot "demo_*"), the same way as Continue.
func open_demo(slot: String) -> void:
	if not TycoonSave.exists(slot):
		return
	_pending_slot = slot
	_go(TYCOON, false, "MENU_LOADING_DEMO")


## Free play on a planet surface (the picker's choice).
func open_surface(body: StringName) -> void:
	_go(SurfaceFreePlay.prepare_from_menu(body), false, "TY_SX_LOADING")


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
		scene.set("intro_cutscene", Cutscenes.OPENING_SHORT)   # the 15 s story
	if _pending_slot != "" and "load_slot" in scene:
		scene.set("load_slot", _pending_slot)
		scene.set("fair_mode", bool(TycoonSave.read(_pending_slot).get("extra", {}).get("fair_mode", false)))
	get_tree().change_scene_to_node(scene)


## Continue: the newest TycoonSave slot, enabled only when there is one.
func _setup_continue() -> void:
	var slot := TycoonSave.latest_slot()
	continue_button.disabled = slot == ""
	continue_button.focus_mode = Control.FOCUS_NONE if slot == "" else Control.FOCUS_ALL
	if slot == "":
		return
	var sm: Dictionary = TycoonSave.read(slot).get("summary", {})
	continue_button.hint_key = tr("TY_SAVE_CONTINUE_HINT") % [int(sm.get("year", 1)), int(sm.get("week", 1))]
	continue_button.tooltip_text = "TY_SAVE_CONTINUE_TIP"
	continue_button.pressed.connect(func() -> void:
		_pending_slot = slot
		_go(TYCOON, false, "TY_SAVE_LOADING"))


# ------------------------------------------------------------------ screenshot helpers
func debug_hover_new_campaign() -> void:
	fair.grab_focus()
	await get_tree().create_timer(0.4).timeout
	new_campaign.grab_focus()


func debug_unhover() -> void:
	fair.grab_focus()
