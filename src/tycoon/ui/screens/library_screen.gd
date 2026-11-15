class_name LibraryScreen
extends CwScreen
## "Biblioteca do Vovô" (scenes/tycoon/ui/screens/library.tscn, opened from the pause menu and
## the discovery journal): every one of Vovô Edmundo's lessons (TutorialBook), heard or not in
## this campaign, with a key to hear it again. Hearing one closes the library, opens the screen
## the lesson talks about when it opens on its own (the lesson's "replay") and plays it there
## (TycoonTutorial.start with replay on). The side has his live portrait, the lessons on/off
## switch and "start the lessons over" for this campaign, the "menus one at a time" switch for
## new careers (MenuUnlocks) and "Já sei jogar", which puts every HUD menu up in this career.
## Rows are copies of the hidden RowTemplate; the look is the scene's. The game holds still
## while the library is open, like the pause menu.

const ICONS := "res://ui/cometworks/icons/%s.svg"

var _resume_speed := 1


func _ready() -> void:
	super._ready()
	CwIcon.sharpen_all(self)   # the header's book at 40 px
	%Toggle.button_pressed = TutorialBook.enabled()
	%Toggle.toggled.connect(TutorialBook.set_enabled)
	%Reset.pressed.connect(reset_lessons)
	%MenusGradual.button_pressed = MenuUnlocks.enabled_for_new()
	%MenusGradual.toggled.connect(MenuUnlocks.set_enabled_for_new)
	%KnowHow.pressed.connect(unlock_all_menus)
	%Status.text = ""


func _bound() -> void:
	_resume_speed = clock.speed
	clock.set_speed(0)
	hud.screen_closed.connect(_on_screen_closed)


func _on_screen_closed(screen_name: String) -> void:
	if screen_name != "library":
		return
	hud.screen_closed.disconnect(_on_screen_closed)
	if clock and clock.speed == 0:
		clock.set_speed(_resume_speed)


func refresh() -> void:
	var lessons := TutorialBook.lessons()
	var rows := copies(%RowTemplate, lessons.size())
	for i in lessons.size():
		var l: Dictionary = lessons[i]
		var id := String(l.get("id", ""))
		var row := rows[i]
		var seen := TutorialBook.seen(state, id)
		row.set_meta("lesson", id)
		var icon := ICONS % String(l.get("icon", "book"))
		(row.get_node("HBox/Icon") as TextureRect).texture = load(icon) if ResourceLoader.exists(icon) else null
		(row.get_node("HBox/Text/Title") as Label).text = tr(String(l.get("title", "")))
		(row.get_node("HBox/Text/Desc") as Label).text = tr(String(l.get("desc", "")))
		var st := row.get_node("HBox/Side/State") as Label
		st.text = tr("TUT_LIB_SEEN") if seen else tr("TUT_LIB_NEW")
		st.add_theme_color_override("font_color", CwPalette.SUCCESS if seen else CwPalette.TEXT_DIM)
		var b := row.get_node("HBox/Side/Replay") as Button
		b.text = tr("TUT_LIB_REPLAY") if seen else tr("TUT_LIB_LISTEN")
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: replay(String(row.get_meta("lesson", ""))))
	%Count.text = tr("TUT_LIB_COUNT") % [TutorialBook.seen_count(state), lessons.size()]
	%KnowHow.disabled = not MenuUnlocks.gradual(state)
	%KnowHow.tooltip_text = "%s\n%s" % [tr("TY_UNL_ALL_TIP"), tr("TY_UNL_COUNT") % [MenuUnlocks.open_count(state),
		MenuUnlocks.items().size()]] if MenuUnlocks.gradual(state) else tr("TY_UNL_ALL_ALREADY")


## Plays lesson `id` again: the library closes, the lesson's screen opens (if it has one) and
## Vovô Edmundo tells it there.
func replay(id: String) -> void:
	var l := TutorialBook.lesson(id)
	var main := hud.owner as TycoonMain if hud else null
	if l.is_empty() or main == null or main.tutorial == null:
		return
	var h := hud
	var tut := main.tutorial
	close_screen()
	var screen := String(l.get("replay", ""))
	if screen != "":
		h.open_screen(screen)
	tut.start(id, true)


## "Já sei jogar": every HUD menu of this career appears now (HudUnlocker.unlock_all).
func unlock_all_menus() -> void:
	if not MenuUnlocks.gradual(state):
		%Status.text = tr("TY_UNL_ALL_ALREADY")
		return
	var main := hud.owner as TycoonMain if hud else null
	if main and main.unlocks:
		main.unlocks.unlock_all()
	else:
		MenuUnlocks.unlock_all(state)
	%Status.text = tr("TY_UNL_ALL_DONE")
	refresh()


## Every lesson of this campaign starts again the first time its moment comes.
func reset_lessons() -> void:
	TutorialBook.reset(state)
	TutorialBook.mark_seen(state, "library")
	%Status.text = tr("TUT_LIB_RESET_DONE")
	refresh()
