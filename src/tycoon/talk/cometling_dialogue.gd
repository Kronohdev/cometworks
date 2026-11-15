class_name CometlingDialogue
extends Control
## "Conversar": a conversation with a Cometling on the campus (scenes/tycoon/talk/dialogue_box.tscn,
## on its own CanvasLayer above the HUD in tycoon_main.tscn). Everything visual is in the scene:
## the box with the speaker's live portrait (cometling_portrait.tscn, dressed like the walker;
## Vovô Edmundo has his own, halley_portrait.tscn), name, profession and morale, the typewriter
## text, the reply choices (copies of the hidden ChoiceTemplate) and a note for what the talk
## did. The words and what they do come from a dialogue tree (DialogueRun,
## data/tycoon/dialogues.json).
##   - the player clicks a Cometling (the camera follows it) and presses "Conversar" on the
##     follow tag, or C; the Cometling stops, turns to the camera and the clock holds
##   - a click on the text (or Space / Enter) finishes the line being typed; 1..9 pick a choice
##   - Esc closes the box first (and only it: the Esc chain carries on next press); so do a
##     click on another Cometling or on the ground, a screen opening and a lesson starting
##   - when it closes, the Cometling walks on, the clock picks up its speed again and what the
##     tree asked for happens (a farewell bubble, a lesson replayed by Vovô)
## Any node can be talked to: a campus Cometling (its staff entry picks the tree: default,
## leader or a Lenda's) or a node with metadata talk_tree (and talk_id / talk_name), like Vovô's
## bench (group "talkers").
## The Lendas who are not on the campus talk from where they show up (open_legend): a mentor
## from its bubble on a briefing, a rival leader from its agency's page on the race board (the
## screens ask through TycoonHUD.talk_to_legend). The box opens over the screen, the Lenda's
## own body in the portrait, and closes with that screen.

signal opened(who: Node3D)
signal closed(who: Node3D)

## letters per second of the typewriter
@export var type_speed := 55.0

var main: Node
var hud: TycoonHUD
var state: TycoonState
var clock: TycoonClock
var run: DialogueRun
var speaker: Node3D
## the line choices on show (DialogueRun.choices())
var shown_choices: Array[Dictionary] = []
## the RNG of the lines (never the campaign's)
var rng := RandomNumberGenerator.new()

var _typing := false
var _shown := 0.0
var _paused_by_us := false
var _resume_speed := 1
var _halley := false
## the Lenda talking from a screen (open_legend), "" for a campus talk
var _legend := ""

@onready var box: PanelContainer = %Box
@onready var text_label: Label = %Text
@onready var portrait: SubViewportContainer = %Portrait
@onready var portrait_creature: Cometling = %Portrait.get_node("Viewport/Creature")
@onready var halley_portrait: SubViewportContainer = %HalleyPortrait
@onready var halley: Halleyzinho = %HalleyPortrait.get_node("Viewport/Halley")


func _ready() -> void:
	rng.randomize()
	box.visible = false
	%ChoiceTemplate.visible = false
	_portraits_live(false)
	text_label.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and _typing:
			_finish_typing())


## Hooks the box to the main screen (TycoonMain calls this once the HUD is bound).
func bind(m: Node) -> void:
	main = m
	hud = m.get("hud")
	state = m.get("state")
	clock = m.get("clock")
	if hud:
		hud.talk_requested.connect(func() -> void:
			var cam: Node = m.get("camera")
			open(cam.call("followed") if cam else null))
		hud.screen_opened.connect(func(_n: String) -> void: close())
		hud.screen_closed.connect(func(_n: String) -> void:
			if _legend != "":
				close())
		hud.legend_talk_requested.connect(func(id: String, where: String) -> void: open_legend(id, where))
	var cam2: Node = m.get("camera")
	if cam2 and cam2.has_signal("follow_changed"):
		cam2.connect("follow_changed", func(who: Node3D) -> void:
			if is_open() and who != speaker:
				close())
	var tut: Node = m.get("tutorial")
	if tut:
		tut.connect("lesson_started", func(_id: String) -> void: close())


func is_open() -> bool:
	return run != null


## Can the player talk to `who` now? (someone with a tree, nothing else on top)
func can_talk(who: Node3D) -> bool:
	if who == null or not is_instance_valid(who) or not who.is_visible_in_tree() or state == null:
		return false
	if _tree_of(who) == "" or not DialogueRun.has_tree(_tree_of(who)):
		return false
	if hud and hud.current_screen() != "":
		return false
	var modes: Node = main.get("modes") if main else null
	if modes and bool(modes.call("is_open")):
		return false
	var tut: Node = main.get("tutorial") if main else null
	if tut and bool(tut.call("is_showing")):
		return false
	return not Cutscenes.is_playing()


## Opens a conversation with `who`. False when they cannot talk now.
func open(who: Node3D) -> bool:
	if not can_talk(who):
		return false
	if is_open():
		close()
	speaker = who
	var m := _member(who)
	var act: Dictionary = who.call("activity") if who.has_method("activity") else {}
	var chatter: Node = main.get("chatter") if main else null
	var world: Dictionary = chatter.call("world") if chatter else {}
	var talk_id := String(who.get_meta("talk_id", "")) if who.has_meta("talk_id") else ""
	run = DialogueRun.new(state, m, _tree_of(who), talk_id, world, act)
	if m.is_empty() and who.has_meta("talk_name"):
		run.vars["name"] = tr(String(who.get_meta("talk_name")))
	run.start(rng)
	# the Cometling stops and looks at the player; the camera stays on it
	if who.has_method("hold"):
		who.call("hold", true)
	var c := ChatterBook.find_creature(who)
	var cam := get_viewport().get_camera_3d()
	if c and cam:
		c.look_at_point(cam.global_position, 0.85)
	var camera: Node = main.get("camera") if main else null
	if camera and camera.has_method("followed") and camera.call("followed") != who:
		camera.call("follow", who)
	_fill_head(m)
	_pause_clock()
	if hud:
		hud.set_talking(true)
	box.visible = true
	_portraits_live(true)
	_show_line()
	CwSfx.play(&"ui_open")
	opened.emit(who)
	return true


## Opens a conversation with Lenda `id` where it shows up away from the campus ("briefing",
## "race"): its own tree, its look in the portrait. False when it has no tree or something holds
## the screen (a cutscene, a lesson, the launch).
func open_legend(id: String, where := "briefing") -> bool:
	if state == null or TycoonLegends.legend(id).is_empty() or Cutscenes.is_playing():
		return false
	var tut: Node = main.get("tutorial") if main else null
	if tut and bool(tut.call("is_showing")):
		return false
	var chatter: Node = main.get("chatter") if main else null
	var world: Dictionary = chatter.call("world") if chatter else {}
	var r := DialogueRun.for_legend(state, id, where, world)
	if r.tree.is_empty():
		return false
	if is_open():
		close()
	run = r
	_legend = id
	speaker = null
	run.start(rng)
	_fill_head(run.member if not run.member.is_empty() else TycoonLegends.look(id))
	_pause_clock()
	box.visible = true
	_portraits_live(true)
	_show_line()
	CwSfx.play(&"ui_open")
	opened.emit(null)
	return true


## Opens a conversation that someone else prepared (the Conferência dos Cometinhos' fair,
## ConferenceBook.make_run): `r` is the run (not started yet), `who` the speaker in the world
## (held and turned to the camera while it talks; may be null) and `look` the dressing of the
## portrait (a staff entry or TycoonLegends.look). Like a Lenda's talk from a screen it never
## touches the campus camera or the follow tag. False when something holds the screen.
func open_run(r: DialogueRun, who: Node3D, look: Dictionary) -> bool:
	if r == null or r.tree.is_empty() or state == null or Cutscenes.is_playing():
		return false
	var tut: Node = main.get("tutorial") if main else null
	if tut and bool(tut.call("is_showing")):
		return false
	if is_open():
		close()
	run = r
	_legend = String(look.get("legend", "talk"))
	speaker = who
	run.start(rng)
	if who and who.has_method("hold"):
		who.call("hold", true)
	var c := ChatterBook.find_creature(who) if who else null
	var cam := get_viewport().get_camera_3d()
	if c and cam:
		c.look_at_point(cam.global_position, 0.85)
	_fill_head(run.member if not run.member.is_empty() else look)
	_pause_clock()
	box.visible = true
	_portraits_live(true)
	_show_line()
	CwSfx.play(&"ui_open")
	opened.emit(who)
	return true


## The Lenda talking from a screen ("" for a campus talk or none).
func legend_id() -> String:
	return _legend


## Closes the box; the Cometling walks on and what the tree asked for happens.
func close() -> void:
	if run == null:
		return
	var who := speaker
	var after := run.after.duplicate()
	var from_screen := _legend != ""
	run = null
	speaker = null
	_legend = ""
	_typing = false
	box.visible = false
	_portraits_live(false)
	if is_instance_valid(who):
		if who.has_method("hold"):
			who.call("hold", false)
		var c := ChatterBook.find_creature(who)
		if c:
			c.clear_look()
	_resume_clock()
	if hud and not from_screen:
		hud.set_talking(false, is_instance_valid(who) and can_talk(who))
	for a: Dictionary in after:
		if a.has("say") and is_instance_valid(who):
			var chatter: Node = main.get("chatter") if main else null
			if chatter:
				var v := ChatterBook.vars_for(state, _member(who))
				chatter.call("say", who, ChatterBook.text(String(a["say"]), v), -1.0, String(a["say"]))
			var cr := ChatterBook.find_creature(who)
			if cr and who.get("napping") != true:
				cr.play("wave")
		if a.has("lesson"):
			var tut: Node = main.get("tutorial") if main else null
			if tut:
				tut.call("start", String(a["lesson"]), true)
	CwSfx.play(&"ui_back")
	closed.emit(who)


## Picks the choice at position `i` of the ones on show.
func choose(i: int) -> void:
	if run == null or i < 0 or i >= shown_choices.size():
		return
	if _typing:
		_finish_typing()
	var go_on := run.choose(int(shown_choices[i]["index"]))
	if not go_on:
		close()
		return
	CwSfx.play(&"ui_click")
	_show_line()


func _show_line() -> void:
	text_label.text = run.text()
	_shown = 0.0
	_typing = not CwMotion.reduced()
	text_label.visible_characters = 0 if _typing else -1
	%Note.text = run.note
	_fill_mood()
	_fill_choices()
	_pose(run.pose(), run.face())
	if _typing:
		_talk(true)
		CwSfx.play(&"voice_babble", 0.78)
	else:
		_finish_typing()


func _fill_choices() -> void:
	shown_choices = run.choices()
	var holder: Node = %Choices
	for c in holder.get_children():
		if c != %ChoiceTemplate:
			c.queue_free()
	for i in shown_choices.size():
		var b := %ChoiceTemplate.duplicate() as Button
		b.visible = true
		b.text = "%d · %s" % [i + 1, shown_choices[i]["text"]]
		b.set_meta("from_template", true)
		holder.add_child(b)
		var idx := i
		b.pressed.connect(func() -> void: choose(idx))


func _fill_head(m: Dictionary) -> void:
	var who := speaker
	# Vovô keeps his own portrait, on his bench or from his briefing bubble
	_halley = _legend == "halleyzinho" or (who != null and who.has_meta("talk_id") and String(who.get_meta("talk_id")) == "halleyzinho")
	portrait.visible = not _halley
	halley_portrait.visible = _halley
	%Name.text = String(run.vars.get("name", ""))
	if _halley:
		%Role.text = tr("TY_DLG_TAG_GRANDPA")
		%Mood.visible = false
		return
	var role := String(run.vars.get("profession", ""))
	if TycoonLeader.is_leader(m):
		role = tr("TY_DLG_TAG_LEADER") + (" · " + role if role != "" else "")
	elif TycoonLegends.is_legend(m):
		role = tr(TycoonLegends.key(String(m["legend"]), "ROLE"))
	%Role.text = role
	%Mood.visible = not run.member.is_empty()
	# a Lenda wears her own body: dress() swaps the portrait's Cometling for it
	portrait_creature = TycoonLeader.dress(portrait_creature, m)
	portrait_creature.glow_color = TycoonCrew.profession_color(state, String(m.get("profession", "")))
	portrait_creature.play("idle")


func _fill_mood() -> void:
	if run.member.is_empty():
		return
	%MoodText.text = tr("TY_DLG_MORALE") % roundi(float(run.member.get("morale", 70.0)))


func _member(who: Node3D) -> Dictionary:
	return ChatterBook.member_of(state, main.get("campus") if main else null, who)


func _tree_of(who: Node3D) -> String:
	return DialogueRun.tree_for(_member(who), who)


# ------------------------------------------------------------ portrait
func _portraits_live(on: bool) -> void:
	for vc: SubViewportContainer in [portrait, halley_portrait]:
		var vp := vc.get_node("Viewport") as SubViewport
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on and vc.visible else SubViewport.UPDATE_DISABLED


func _talk(on: bool) -> void:
	if _halley:
		halley.talk(on)
	elif on:
		if not portrait_creature.is_busy():
			portrait_creature.play("talk")
	else:
		if portrait_creature.current_action() == "talk":
			portrait_creature.play("idle")


func _pose(p: String, face: String) -> void:
	var c: Cometling = halley if _halley else portrait_creature
	if face != "":
		c.set_expression(face, 4.0)
	if p == "":
		return
	if _halley and p in Halleyzinho.HABITS:
		halley.play_habit(p)
	elif Cometling.ONESHOTS.has(p) or p in Cometling.LOOP_ACTIONS:
		c.play(p)
	# the walker in the world does the one-shots too
	var w := ChatterBook.find_creature(speaker) if is_instance_valid(speaker) else null
	if w and Cometling.ONESHOTS.has(p) and speaker.get("napping") != true:
		w.play(p)


func _finish_typing() -> void:
	_typing = false
	text_label.visible_characters = -1
	_talk(false)


# ------------------------------------------------------------ frame and keys
func _process(delta: float) -> void:
	if run == null:
		return
	if _legend == "" and (not is_instance_valid(speaker) or not speaker.is_visible_in_tree()):
		close()
		return
	var on_mode := main != null and main.get("modes") != null and bool(main.get("modes").call("is_open"))
	visible = not on_mode and not Cutscenes.is_playing()
	if _typing:
		_shown += delta * type_speed
		var total := text_label.get_total_character_count()
		text_label.visible_characters = int(_shown)
		if int(_shown) >= total:
			_finish_typing()


func _input(event: InputEvent) -> void:
	if run == null or not is_visible_in_tree():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif k >= KEY_1 and k <= KEY_9:
		choose(k - KEY_1)
		get_viewport().set_input_as_handled()
	elif k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if _typing:
			_finish_typing()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	# C talks to the followed Cometling
	if run != null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode != KEY_C or main == null:
		return
	var camera: Node = main.get("camera")
	var who: Node3D = camera.call("followed") if camera and camera.has_method("followed") else null
	if who and open(who):
		get_viewport().set_input_as_handled()


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
	# a screen that holds the game still took over the pause: it gives the speed back itself
	var scr: Node = null
	if hud and hud.get_node("%Screens").get_child_count() > 0:
		scr = hud.get_node("%Screens").get_child(0)
	if scr and "_resume_speed" in scr:
		if int(scr.get("_resume_speed")) == 0:
			scr.set("_resume_speed", _resume_speed)
		return
	var tut: Node = main.get("tutorial") if main else null
	if tut and bool(tut.call("is_showing")) and "_resume_speed" in tut:
		# a lesson starting closed the box: it holds the clock and gives the speed back
		tut.set("_paused_by_us", true)
		tut.set("_resume_speed", _resume_speed)
		return
	clock.set_speed(_resume_speed)
