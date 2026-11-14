class_name MenuDemoPanel
extends PanelContainer
## The main menu's Demonstração panel (scenes/menu/demo_panel.tscn): the demonstration saves
## that ship with the game (TycoonSave.DEMOS, res://data/demo_saves/): a fair-mode start and
## the start of each of the five eras. Layout and look live in the scene; this script copies
## the hidden Template row (a MenuItem) once per save, fills its name and the year / milestones
## line, and emits `chosen(slot)` (the menu opens the campaign) or `closed` on Back / Esc.

signal chosen(slot: String)
signal closed

@onready var list: VBoxContainer = %List
@onready var template: MenuItem = %Template
@onready var empty: Label = %Empty
@onready var back: Button = %Back

var _rows: Array[MenuItem] = []


func _ready() -> void:
	template.visible = false
	back.pressed.connect(func() -> void: closed.emit())
	fill()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		fill()


## One row per demonstration save found (in TycoonSave.DEMOS order).
func fill() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	var demos := TycoonSave.demos()
	empty.visible = demos.is_empty()
	for i in demos.size():
		var d: Dictionary = demos[i]
		var slot := String(d["slot"])
		var sm: Dictionary = d.get("summary", {})
		var row := template.duplicate() as MenuItem
		row.name = slot
		row.visible = true
		row.text = title_key(slot, int(sm.get("era", 1)))
		row.index_text = "%02d" % (i + 1)
		row.hint_key = tr("MENU_DEMO_DETAIL") % [int(sm.get("year", 1)), int(sm.get("milestones", 0))]
		row.tooltip_text = "MENU_DEMO_FAIR_TIP" if slot == "demo_fair" else "MENU_DEMO_ERA_TIP"
		row.pressed.connect(func() -> void: chosen.emit(slot))
		list.add_child(row)
		list.move_child(row, template.get_index())
		_rows.append(row)


## The row's name: "Modo feira" for the fair start, "Era N · name" for an era start.
func title_key(slot: String, era: int) -> String:
	if slot == "demo_fair":
		return tr("MENU_DEMO_FAIR")
	return tr("MENU_DEMO_ERA") % [era, tr("TY_ERA_%d" % era)]


func rows() -> Array[MenuItem]:
	return _rows


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()
	else:
		back.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
