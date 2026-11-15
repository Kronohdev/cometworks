class_name TycoonSettingsScreen
extends Control
## In-game settings (scenes/tycoon/ui/screens/settings.tscn), four tabs (CwPageStack):
##   Game   language, motion, the launch cinematic, story scenes and Vovô's narration of them,
##          replay the opening,
##          Vovô Edmundo's lessons on / off and his library (library.tscn)
##   Save   the save slots (save, load, the monthly autosave)
##   Image  window / fullscreen, style, outlines
##   Sound  the three volumes
## The options rows come from the main menu's options panel (scenes/menu/options_panel.tscn
## with MenuSettings), instanced once per tab with the other rows hidden in the scene. Back to
## the menu and back to the campus stay at the foot.
## Rows are copies of the hidden SlotTemplate; the look is the scene's. LaunchCinematic turns
## the launch sequence on or off; Cutscenes the story scenes (Cutscenes), and ReplayOpening
## plays the opening again.

const MENU := "res://scenes/menu/main_menu.tscn"
const SLOTS: Array[String] = ["1", "2", "3", "auto"]

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var _resume_speed := 1


func _ready() -> void:
	%Close.pressed.connect(close)
	%Resume.pressed.connect(close)
	%Menu.pressed.connect(back_to_menu)
	# the menu's options panel, once per tab (each shows only that tab's rows)
	for o in [%Options, %OptionsImage, %OptionsSound]:
		(o as MenuOptionsPanel).closed.connect(close)
	# the launch cinematic on/off (src/tycoon/launch/launch_sequence.gd)
	%LaunchCinematic.button_pressed = LaunchSequence.enabled()
	%LaunchCinematic.toggled.connect(LaunchSequence.set_enabled)
	# the story cutscenes on/off, and the opening once more (src/cutscene/cutscenes.gd)
	%Cutscenes.button_pressed = Cutscenes.enabled()
	%Cutscenes.toggled.connect(Cutscenes.set_enabled)
	# Vovô Edmundo narrating the story scenes (his bubble instead of the plain lines)
	%Narration.button_pressed = Cutscenes.narration_enabled()
	%Narration.toggled.connect(Cutscenes.set_narration_enabled)
	%ReplayOpening.pressed.connect(replay_opening)
	# Vovô Edmundo's lessons on/off, and the library to hear any of them again
	%Tutorials.button_pressed = TutorialBook.enabled()
	%Tutorials.toggled.connect(TutorialBook.set_enabled)
	%Library.pressed.connect(open_library)
	%Status.text = ""


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	# the game holds still while this menu is open and picks up its speed when it closes
	_resume_speed = clock.speed
	clock.set_speed(0)
	hud.screen_closed.connect(_on_screen_closed)
	refresh()


## open_screen("settings", {"tab": "Game" | "Save" | "Image" | "Sound"})
func open_with(args: Dictionary) -> void:
	if args.has("tab"):
		(%Pages as CwPageStack).switch_to(StringName(String(args["tab"])))


func _on_screen_closed(screen_name: String) -> void:
	if screen_name != "settings":
		return
	hud.screen_closed.disconnect(_on_screen_closed)
	if clock and clock.speed == 0:
		clock.set_speed(_resume_speed)


func close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


## Closes the menu and plays the opening again (the game stays paused while it plays).
func replay_opening() -> void:
	var h := hud
	var s := state
	close()
	if h:
		Cutscenes.play(h.owner if h.owner else h, Cutscenes.OPENING, s, true)


## Closes the menu and opens Vovô Edmundo's library.
func open_library() -> void:
	var h := hud
	close()
	if h:
		h.open_screen("library")


func refresh() -> void:
	var rows := TycoonHUD._copies(%SlotTemplate, SLOTS.size())
	for i in SLOTS.size():
		var slot := SLOTS[i]
		var row := rows[i]
		var d := TycoonSave.read(slot)
		var info := row.get_node("HBox/Info")
		(info.get_node("Name") as Label).text = tr("TY_SET_AUTO") if slot == TycoonSave.AUTO else tr("TY_SET_SLOT") % slot
		var sum_l := info.get_node("Summary") as Label
		var when_l := info.get_node("When") as Label
		if d.is_empty():
			sum_l.text = tr("TY_SET_EMPTY")
			sum_l.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
			when_l.text = ""
		else:
			var sm: Dictionary = d.get("summary", {})
			sum_l.text = tr("TY_SET_SUMMARY") % [int(sm.get("year", 1)), int(sm.get("week", 1)), TycoonHUD.fmt_cr(float(sm.get("cash", 0.0)))]
			sum_l.remove_theme_color_override("font_color")
			when_l.text = _local_time(int(d.get("saved_at", 0)))
		var save_b := row.get_node("HBox/Save") as Button
		var load_b := row.get_node("HBox/Load") as Button
		save_b.visible = slot != TycoonSave.AUTO and state != null
		load_b.disabled = d.is_empty()
		if not save_b.has_meta("wired"):
			save_b.set_meta("wired", true)
			save_b.pressed.connect(save_to.bind(slot))
			load_b.pressed.connect(load_from.bind(slot))


func save_to(slot: String) -> void:
	if state == null:
		return
	var err := TycoonSave.save(state, slot, {"fair_mode": clock.fair_mode if clock else false})
	%Status.text = tr("TY_SET_SAVED") % slot if err == OK else tr("TY_SET_SAVE_FAILED")
	refresh()


func load_from(slot: String) -> void:
	if TycoonSave.exists(slot):
		TycoonSave.open_in_game(get_tree(), slot)


## Leaves for the title screen; the campaign goes to the autosave first, so Continue finds it.
func back_to_menu() -> void:
	if state and not state.is_over():
		TycoonSave.save(state, TycoonSave.AUTO, {"fair_mode": clock.fair_mode if clock else false})
	get_tree().change_scene_to_file(MENU)


static func _local_time(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%04d-%02d-%02d  %02d:%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"]]
