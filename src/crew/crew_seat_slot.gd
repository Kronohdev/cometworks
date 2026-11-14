class_name CrewSeatSlot
extends PanelContainer
## One crew seat of the current vessel in the crew panel (scenes/ui/crew_seat.tscn).
## Drop a CrewCard here, or click it while a card is selected, to seat that member.

signal clicked(slot: CrewSeatSlot)
signal dropped(slot: CrewSeatSlot, member_id: String)
signal unseat_requested(slot: CrewSeatSlot)

var part: Node
var seat := 0
var member: CrewMember

@onready var seat_label: Label = $VBox/Top/SeatLabel
@onready var part_label: Label = $VBox/Part
@onready var dot: Panel = $VBox/Occupant/Dot
@onready var name_label: Label = $VBox/Occupant/Name
@onready var unseat_btn: Button = $VBox/Top/Unseat

var _hover_drop := false


func _ready() -> void:
	unseat_btn.pressed.connect(func() -> void: unseat_requested.emit(self))
	unseat_btn.tooltip_text = tr("CREW_UNASSIGN")


func setup(p: Node, s: int, m: CrewMember, part_title: String) -> void:
	part = p
	seat = s
	member = m
	if not is_node_ready():
		await ready
	seat_label.text = tr("CREW_SEAT_N") % (s + 1)
	part_label.text = part_title
	unseat_btn.visible = m != null
	if m:
		name_label.text = m.display_name
		name_label.remove_theme_color_override("font_color")
		dot.self_modulate = CrewCard.ROLE_COLORS.get(m.role, Color.WHITE)
		dot.visible = true
		tooltip_text = "%s · %s" % [m.display_name, tr("ROLE_" + m.role.to_upper())]
	else:
		name_label.text = tr("CREW_EMPTY_SEAT")
		name_label.add_theme_color_override("font_color", Color("#8c9bb5"))
		dot.visible = false
		tooltip_text = tr("CREW_DRAG_HINT")
	_update_border()


func _update_border() -> void:
	var sb := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if _hover_drop:
		sb.border_color = Color("#f59a36")
	elif member:
		sb.border_color = CrewCard.ROLE_COLORS.get(member.role, Color("#3b4a5c"))
	else:
		sb.border_color = Color("#3b4a5c")
	add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok := data is Dictionary and (data as Dictionary).has("crew_member_id")
	if ok != _hover_drop:
		_hover_drop = ok
		_update_border()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_hover_drop = false
	_update_border()
	dropped.emit(self, String((data as Dictionary)["crew_member_id"]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
		if _hover_drop:
			_hover_drop = false
			_update_border()
