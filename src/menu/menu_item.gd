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

const INDEX_ON := Color("#7652e8")
const INDEX_OFF := Color("#5d5b8c")


func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		return
	mouse_entered.connect(func() -> void:
		if not disabled and focus_mode != FOCUS_NONE:
			grab_focus())
	focus_entered.connect(_light.bind(true))
	focus_exited.connect(_light.bind(false))
	resized.connect(_fit_hint)
	# the menu enables Continue after loading the save: relight the hint when the row redraws
	draw.connect(func() -> void: _light(has_focus()))
	_light(false)


func _refresh() -> void:
	if not is_node_ready():
		return
	($Index as Label).text = index_text
	($Hint as Label).text = hint_key
	_fit_hint()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_fit_hint.call_deferred()


## Keeps the dim hint clear of the entry's own text: its left edge starts past the label
## (icon + text + a gap) and the row drops the hint when too little room is left.
func _fit_hint() -> void:
	if not is_node_ready():
		return
	var hint := $Hint as Label
	if hint_key == "":
		hint.visible = false
		return
	var font := get_theme_font("font")
	var fsize := get_theme_font_size("font_size")
	var x := 0.0
	var box := get_theme_stylebox("normal")
	if box:
		x += box.get_margin(SIDE_LEFT)
	if icon:
		var iw := get_theme_constant("icon_max_width")
		x += float(iw if iw > 0 else icon.get_width()) + float(get_theme_constant("h_separation"))
	x += font.get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + 16.0
	var room := size.x + hint.offset_right - x
	hint.visible = room >= 70.0
	hint.offset_left = hint.offset_right - minf(room, 236.0)


func _light(on: bool) -> void:
	($Index as Label).add_theme_color_override("font_color", INDEX_ON if on and not disabled else INDEX_OFF)
	($Hint as Label).modulate.a = 1.0 if on else (0.5 if disabled else 1.0)
