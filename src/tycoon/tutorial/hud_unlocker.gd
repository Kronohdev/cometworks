class_name HudUnlocker
extends Control
## Shows the HUD menus a new career unlocks while it plays (MenuUnlocks,
## data/tycoon/menu_unlocks.json). Lives in scenes/tycoon/ui/tutorial/unlocks.tscn, on the
## TutorialLayer of tycoon_main.tscn under Vovô's bubble. The look is the scene's: the hidden
## BadgeTemplate (unlock_badge.tscn, a ring, sparks and a "NOVO!" sticker with its "pop"
## animation) is copied over each node that appears.
##   - menus not open yet are hidden (TycoonHUD.lock_node); their keys do nothing but hint
##   - an item opens when its conditions hold (checked on every state change) or when its
##     screen opens by another way; it is revealed when the campus is free (no screen, no
##     cutscene, no hangar, no lesson on show): the node pops in, the badge plays and Vovô's
##     lesson for it starts (TycoonTutorial.on_unlocked, trigger "unlock"); one at a time
##   - an item opened by its screen pops in without the lesson (the screen had its own)
##   - unlock_all() ("Já sei jogar") shows every menu at once
## Test scripts (a SceneTree script as the main loop) get every menu open on a new career
## unless HudUnlocker.allow_in_scripts is set, so tests that open screens keep working.

signal revealed(item_id: String)

## seconds between two reveals once the campus is free again
@export var reveal_gap := 0.8
## seconds the badge plays before Vovô starts talking
@export var lesson_delay := 0.9
## seconds the node takes to pop in
@export var pop_seconds := 0.45

## tests that drive the unlocks set this; otherwise scripts start careers with every menu open
static var allow_in_scripts := false

var main: TycoonMain
var state: TycoonState
var hud: TycoonHUD
var tutorial: TycoonTutorial
var fair := false

var _gap := 0.0
## items opened by their screen: they pop in without the lesson
var _quiet := {}

@onready var template: Control = %BadgeTemplate


func _ready() -> void:
	template.visible = false


static func _scripted() -> bool:
	var ml := Engine.get_main_loop()
	return ml != null and ml.get_script() != null


## True when a career started now should unlock its menus gradually.
static func gradual_for_new() -> bool:
	if _scripted() and not allow_in_scripts:
		return false
	return MenuUnlocks.enabled_for_new()


func bind(m: TycoonMain) -> void:
	main = m
	state = m.state
	hud = m.hud
	tutorial = m.tutorial
	fair = m.fair_mode
	state.changed.connect(check)
	hud.screen_opened.connect(_on_screen_opened)
	apply()
	check()


## Hides the nodes of the items not revealed yet, shows the others.
func apply() -> void:
	for it: Dictionary in MenuUnlocks.items():
		var shown := MenuUnlocks.is_shown(state, String(it.get("id", "")))
		for ref in it.get("nodes", []):
			hud.lock_node(String(ref), not shown)


## Opens the items whose conditions hold now (they are revealed when the campus is free).
func check() -> void:
	if state != null:
		MenuUnlocks.check(state, fair)


func _on_screen_opened(screen_name: String) -> void:
	var id := MenuUnlocks.note_screen(state, screen_name)
	if id != "":
		_quiet[id] = true


## "Já sei jogar": every menu now, each with a quick pop, no lessons.
func unlock_all() -> void:
	var hidden: Array[Control] = []
	for it: Dictionary in MenuUnlocks.items():
		if not MenuUnlocks.is_shown(state, String(it.get("id", ""))):
			hidden.append_array(nodes_of(it))
	MenuUnlocks.unlock_all(state)
	apply()
	for n in hidden:
		_pop(n, false)


## The HUD nodes of an item that exist.
func nodes_of(it: Dictionary) -> Array[Control]:
	var out: Array[Control] = []
	for ref in it.get("nodes", []):
		var n := hud.hud_node(String(ref))
		if n:
			out.append(n)
	return out


func is_busy() -> bool:
	return _gap > 0.0


func _campus_free() -> bool:
	if hud == null or hud.current_screen() != "" or Cutscenes.is_playing():
		return false
	if main.modes and main.modes.is_open():
		return false
	if tutorial and tutorial.is_showing():
		return false
	return true


func _process(delta: float) -> void:
	if state == null or not MenuUnlocks.gradual(state):
		return
	if _gap > 0.0:
		_gap -= delta
		return
	var next := MenuUnlocks.pending(state)
	if next.is_empty() or not _campus_free():
		return
	reveal(next[0])


## Shows item `id` on the HUD now: its nodes pop in under the badge and Vovô's lesson starts.
func reveal(id: String) -> void:
	var it := MenuUnlocks.item(id)
	if it.is_empty():
		return
	MenuUnlocks.open(state, id)
	MenuUnlocks.mark_shown(state, id)
	apply()
	var lot := String(it.get("lot", ""))
	if lot != "" and hud.current_screen() == "":
		hud.show_lot(lot)
	var nodes := nodes_of(it)
	for n in nodes:
		_pop(n, true)
	_gap = reveal_gap + (lesson_delay if not nodes.is_empty() else 0.0)
	if not nodes.is_empty():
		CwSfx.play(&"news_chime")
		hud.flash_hint(tr("TY_UNL_NEW") % tr(String(it.get("name_key", ""))), 4.0)
	var quiet := bool(_quiet.get(id, false)) or nodes.is_empty()
	_quiet.erase(id)
	if tutorial and not quiet:
		if lesson_delay > 0.0 and is_inside_tree():
			get_tree().create_timer(lesson_delay).timeout.connect(func() -> void:
				if is_instance_valid(tutorial):
					tutorial.on_unlocked(id))
		else:
			tutorial.on_unlocked(id)
	revealed.emit(id)


## The node grows in (a motion channel, so its container keeps its layout) and, with
## `badge`, a copy of the badge plays over it.
func _pop(n: Control, badge: bool) -> void:
	if not n.is_visible_in_tree():
		return
	if not CwMotion.reduced():
		CwMotion.set_channel(n, &"unlock", Vector2.ZERO, Vector2(0.2, 0.2), 0.0, 0.0)
		var tw := n.create_tween()
		tw.tween_method(func(t: float) -> void:
			var s := lerpf(0.2, 1.0, t)
			CwMotion.set_channel(n, &"unlock", Vector2.ZERO, Vector2(s, s), 0.0, clampf(t * 2.0, 0.0, 1.0)),
			0.0, 1.0, pop_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: CwMotion.clear_channel(n, &"unlock"))
	if badge:
		_badge_over.call_deferred(n)


func _badge_over(n: Control) -> void:
	if not is_instance_valid(n) or not n.is_visible_in_tree():
		return
	var b := template.duplicate() as Control
	b.visible = true
	add_child(b)
	var xf := get_global_transform().affine_inverse() * n.get_global_transform_with_canvas()
	var r := Rect2(xf.origin, n.size * xf.get_scale())
	b.position = r.get_center() - b.size * 0.5
	var player := b.get_node("Player") as AnimationPlayer
	player.animation_finished.connect(func(_a: StringName) -> void: b.queue_free())
	player.play(&"pop")
