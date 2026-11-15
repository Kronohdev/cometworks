class_name CreditsScreen
extends Control
## Créditos (scenes/menu/credits.tscn), opened over the main menu: the team, Cometlings Crew,
## with its emblem, the four developers as Cometlings on a little 3D stage (idling and waving)
## and the other credits: engine, fonts, data sources.
## One developer stands in the spotlight, on the podium in the middle (the lead, Kauã, when the
## screen opens): left / right (arrows, A / D, the gamepad, the ‹ › buttons) or a click on a
## Cometling moves the spotlight. The Cometlings slide between the stage's slots (%SlotCenter,
## %SlotRight, %SlotBack, %SlotLeft); the one arriving in the middle grows and plays their own
## signature (credits.json "signature": a short chain of one-shots and loops with emotes),
## then settles into the idle. The info card under the stage shows the chosen one's name, role
## and bio; the lead keeps a star there and on their name chip.
## Everything visual is authored in the scene (the stage, its lights, slots and Cometlings, the
## name chip template, the info card, a section template); this script fills them from
## data/credits.json, which holds the names, the editable role and bio lines, the signatures and
## the developers' looks (TycoonLeader.apply_look with CometlingStyle keys), and closes on Esc /
## the back button.

signal closed

const DATA_PATH := "res://data/credits.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


## The developers in stage order.
static func developers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Variant in data().get("developers", []):
		if d is Dictionary:
			out.append(d)
	return out


## The credit sections after the team.
static func sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Variant in data().get("credits", []):
		if d is Dictionary:
			out.append(d)
	return out


## Index of the lead developer in developers() (0 when none is marked).
static func lead_index() -> int:
	var devs := developers()
	for i in devs.size():
		if bool(devs[i].get("lead", false)):
			return i
	return 0


## The role line of a developer in the current language.
static func role_text(dev: Dictionary) -> String:
	return _local(dev.get("role", ""))


## The short bio line of a developer in the current language.
static func bio_text(dev: Dictionary) -> String:
	return _local(dev.get("bio", ""))


static func _local(v: Variant) -> String:
	if v is Dictionary:
		var lang := "pt" if TranslationServer.get_locale().begins_with("pt") else "en"
		return String((v as Dictionary).get(lang, (v as Dictionary).get("en", "")))
	return String(v)


## Dresses Cometling `c` as developer `dev` (colours, gear, hat and style from its look).
static func dress(c: Cometling, dev: Dictionary) -> void:
	var look: Dictionary = dev.get("look", {})
	TycoonLeader.apply_look(c, look, String(look.get("role", "ground")))
	if not bool(look.get("gear", true)):   # no profession gear at all (vest, belt, backpack...)
		for n in ["Vest", "Belt", "Backpack", "Scarf", "Goggles"]:
			var g := c.find_child(n, true, false) as Node3D
			if g:
				g.visible = false


## The signature steps of a developer: [{"action", "seconds", "emote"}] (credits.json
## "signature": a list of one-shot names, or {"action": loop or one-shot, "seconds", "emote"}).
static func signature(dev: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for st: Variant in dev.get("signature", ["wave"]):
		var d: Dictionary = st if st is Dictionary else {"action": String(st)}
		var a := String(d.get("action", "wave"))
		if not Cometling.has_action(a):
			continue
		var secs := float(d.get("seconds", Cometling.ONESHOTS.get(a, 2.0)))
		out.append({"action": a, "seconds": secs, "emote": String(d.get("emote", ""))})
	return out


# ------------------------------------------------------------------ screen
const WAVE_EVERY := Vector2(2.4, 4.2)
const EMOTES: Array[String] = ["heart", "star", "happy", "sparkle", "rocket", "note"]
const SLIDE := 0.5
## a click picks the Cometling whose body is this close (pixels in the stage)
const PICK_RADIUS := 90.0

## The developer in the spotlight (index in developers()).
var selected := 0
var _stage: Array[Cometling] = []   # in the order of developers()
var _cards: Array[Control] = []
var _devs: Array[Dictionary] = []
var _slide: Tween
var _show: Tween                     # the signature of the one in the spotlight
var _wave_in := 3.0
var _rng := RandomNumberGenerator.new()
var _leaving := false

@onready var back: Button = %Back
@onready var camera: Camera3D = %Camera3D
@onready var names: Control = %Names
@onready var view: Control = %View
@onready var info_name: Label = %InfoName
@onready var info_role: Label = %InfoRole
@onready var info_bio: Label = %InfoBio
@onready var info_star: Control = %Star


func _ready() -> void:
	_rng.randomize()
	back.pressed.connect(close)
	(%Prev as Button).pressed.connect(select_prev)
	(%Next as Button).pressed.connect(select_next)
	view.gui_input.connect(_on_view_input)
	_devs = developers()
	selected = lead_index()
	_fill_stage()
	_fill_sections()
	_fill_info()
	back.grab_focus.call_deferred()
	# the others say hello, then the one in the spotlight does their signature
	var tw := create_tween()   # dies with the screen
	tw.tween_interval(0.35)
	for i in _stage.size():
		if i != selected:
			tw.tween_callback(_hello.bind(i))
			tw.tween_interval(0.22)
	tw.tween_callback(func() -> void: _signature(selected))


func _hello(i: int) -> void:
	if i < _stage.size():
		_stage[i].play("wave")
		_stage[i].show_emote(EMOTES[i % EMOTES.size()], 1.6)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill_cards()
		_fill_sections()
		_fill_info()


# ------------------------------------------------------------------ the stage
## Dresses %Dev1.. as the developers and puts them in their slots around the spotlight.
func _fill_stage() -> void:
	var bodies: Array[Cometling] = [%Dev1, %Dev2, %Dev3, %Dev4]
	_stage.clear()
	for i in bodies.size():
		var c := bodies[i]
		c.visible = i < _devs.size()
		if i >= _devs.size():
			continue
		c.auto_emotes = false
		dress(c, _devs[i])
		_stage.append(c)
	_place(false)
	_fill_cards()


## The slot of developer `i` with `selected` in the middle: the next one on the right, the one
## before on the left, the rest further back.
func _slot_of(i: int) -> Node3D:
	var n := _stage.size()
	var k := posmod(i - selected, n)
	if k == 0:
		return %SlotCenter
	if k == 1:
		return %SlotRight
	if k == n - 1:
		return %SlotLeft
	return %SlotBack


## Moves every Cometling to its slot (sliding when `animate`).
func _place(animate: bool) -> void:
	if _slide and _slide.is_valid():
		_slide.kill()
	if animate:
		_slide = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in _stage.size():
		var c := _stage[i]
		var to := _slot_of(i).transform
		if animate:
			_slide.tween_property(c, "transform", to, SLIDE)
		else:
			c.transform = to


func _fill_info() -> void:
	if _devs.is_empty():
		return
	var dev := _devs[selected]
	info_name.text = String(dev.get("name", ""))
	info_role.text = role_text(dev)
	info_bio.text = bio_text(dev)
	info_bio.visible = info_bio.text != ""
	info_star.visible = bool(dev.get("lead", false))   # the director keeps his star


## Puts developer `i` in the spotlight (wraps around).
func select(i: int) -> void:
	if _stage.is_empty():
		return
	i = posmod(i, _stage.size())
	if i == selected:
		return
	var was := _stage[selected]
	selected = i
	CwSfx.play(&"menu_hover")
	# the one leaving the middle stops their show and steps back
	_stop_show()
	was.stop_shot()
	was.play("idle")
	_place(true)
	_fill_info()
	_refresh_cards()
	_show = create_tween()
	_show.tween_interval(SLIDE * 0.6)
	_show.tween_callback(_signature.bind(i))


func select_next() -> void:
	select(selected + 1)


func select_prev() -> void:
	select(selected - 1)


func _stop_show() -> void:
	if _show and _show.is_valid():
		_show.kill()
	_show = null


## Plays developer `i`'s signature (one step after another, emotes on the way), then the idle.
func _signature(i: int) -> void:
	if i != selected or i >= _stage.size():
		return
	_stop_show()
	var c := _stage[i]
	c.stop_shot()
	_show = create_tween()
	for st in signature(_devs[i]):
		var a := String(st["action"])
		var secs := float(st["seconds"])
		var emote := String(st["emote"])
		_show.tween_callback(func() -> void:
			c.play(a, secs if Cometling.ONESHOTS.has(a) else -1.0)
			if emote != "":
				c.show_emote(emote, minf(secs, 1.8)))
		_show.tween_interval(secs)
	_show.tween_callback(func() -> void:
		c.stop_shot()
		c.play("idle"))


## Is the signature of the one in the spotlight still playing?
func is_showing() -> bool:
	return _show != null and _show.is_valid() and _show.is_running()


## A click on the stage picks the Cometling under it.
func _on_view_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var best := -1
	var best_d := PICK_RADIUS
	for i in _stage.size():
		var c := _stage[i]
		var p := camera.unproject_position(c.global_position + Vector3(0, 0.55 * c.scale.y, 0))
		var d := p.distance_to(mb.position)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		select(best)
		view.accept_event()


# ------------------------------------------------------------------ name chips
func _fill_cards() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	for i in _stage.size():
		var dev := _devs[i]
		var card := (%NameTemplate as Control).duplicate() as Control
		card.visible = true
		names.add_child(card)
		(card.find_child("Name", true, false) as Label).text = String(dev.get("name", ""))
		(card.find_child("Star", true, false) as Control).visible = bool(dev.get("lead", false))
		_cards.append(card)
	_refresh_cards()
	_place_cards()


## The chip of the one in the spotlight hides (the info card tells about them).
func _refresh_cards() -> void:
	for i in _cards.size():
		_cards[i].visible = i != selected


## The name chips stand under each Cometling's feet on the stage.
func _place_cards() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	for i in mini(_cards.size(), _stage.size()):
		var card := _cards[i]
		var c := _stage[i]
		var p := camera.unproject_position(c.global_position + Vector3(0, -0.02, 0.25))
		var sz := card.get_combined_minimum_size()
		card.size = sz
		card.position = Vector2(p.x - sz.x * 0.5, p.y + 4.0).clamp(Vector2(4, 4), names.size - sz - Vector2(4, 4))


# ------------------------------------------------------------------ the other credits
func _fill_sections() -> void:
	var tmpl := %SectionTemplate as Control
	var list := sections()
	var boxes := TycoonHUD._copies(tmpl, list.size())
	for i in list.size():
		var sec := list[i]
		var box := boxes[i]
		(box.get_node("Title") as Label).text = String(sec.get("title_key", ""))
		var lines: Array = sec.get("lines", [])
		var rows := TycoonHUD._copies(box.get_node("Lines/LineTemplate") as Control, lines.size())
		for k in lines.size():
			var ln: Dictionary = lines[k]
			(rows[k].get_node("Name") as Label).text = String(ln.get("name", ""))
			var detail := tr(String(ln["detail_key"])) if ln.has("detail_key") else _local(ln.get("detail", ""))
			var by := String(ln.get("by", ""))
			if by != "":
				detail = "%s · %s" % [by, detail]
			(rows[k].get_node("Detail") as Label).text = detail
	(%Thanks as Control).move_to_front()


func _process(delta: float) -> void:
	_place_cards()
	if _stage.is_empty():
		return
	# now and then somebody at the sides waves again
	_wave_in -= delta
	if _wave_in <= 0.0:
		_wave_in = _rng.randf_range(WAVE_EVERY.x, WAVE_EVERY.y)
		var i := _rng.randi() % _stage.size()
		var c := _stage[i]
		if i != selected and not c.is_busy():
			c.play(["wave", "wave", "hop", "nod"][_rng.randi() % 4])
			if _rng.randf() < 0.5:
				c.show_emote(EMOTES[_rng.randi() % EMOTES.size()], 1.5)


## Left / right (arrows, A / D, the gamepad's stick and d-pad) move the spotlight.
func _input(event: InputEvent) -> void:
	if _leaving or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	var a_key := key != null and key.pressed and not key.echo and key.physical_keycode == KEY_A
	var d_key := key != null and key.pressed and not key.echo and key.physical_keycode == KEY_D
	var left := event.is_action_pressed(&"ui_left") or a_key
	var right := event.is_action_pressed(&"ui_right") or d_key
	if left or right:
		get_viewport().set_input_as_handled()
		if left:
			select_prev()
		else:
			select_next()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Back to the menu (with the screen's exit animation).
func close() -> void:
	if _leaving:
		return
	_leaving = true
	closed.emit()
	if not CwScreenTransition.leave(self, get_parent(), get_index()):
		queue_free()
