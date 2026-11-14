@tool
class_name MenuItem
extends Button
## One row of the main menu (scenes/menu/menu_item.tscn): the Button's own text is the
## entry, the Index label shows its number in mono on the left and the Hint label a short
## dim line on the right. Both labels are authored in the scene; this script only fills
## their text from the exports and lights the index when the row is selected.
## Hovering a row moves the keyboard focus to it, so mouse and keys share one highlight.

@export var index_text := "01":
	set(v):
		index_text = v
		_refresh()
## Translation key of the dim hint on the right.
@export var hint_key := "":
	set(v):
		hint_key = v
		_refresh()

const INDEX_ON := Color("#3fe0c5")
const INDEX_OFF := Color("#3a4d72")


func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		return
	mouse_entered.connect(func() -> void:
		if not disabled and focus_mode != FOCUS_NONE:
			grab_focus())
	focus_entered.connect(_light.bind(true))
	focus_exited.connect(_light.bind(false))
	_light(false)


func _refresh() -> void:
	if not is_node_ready():
		return
	($Index as Label).text = index_text
	($Hint as Label).text = hint_key


func _light(on: bool) -> void:
	($Index as Label).add_theme_color_override("font_color", INDEX_ON if on and not disabled else INDEX_OFF)
	($Hint as Label).modulate.a = 1.0 if on else (0.55 if disabled else 0.8)
