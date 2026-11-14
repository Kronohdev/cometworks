class_name CrewCard
extends PanelContainer
## One roster entry in the crew panel (scenes/ui/crew_card.tscn): live portrait, name
## (click the pencil to rename), role badge, level + XP, stat bars, status and a
## "seat" button. The card can be dragged onto a CrewSeatSlot.

signal selected(card: CrewCard)
signal seat_requested(member: CrewMember)
signal rename_requested(member: CrewMember, new_name: String)

const ROLE_COLORS := {"pilot": Color("#f59a36"), "engineer": Color("#f2b705"), "scientist": Color("#5fb0d8")}
const ROLE_ICONS := {
	"pilot": preload("res://assets/voxel/creatures/ui/role_pilot.svg"),
	"engineer": preload("res://assets/voxel/creatures/ui/role_engineer.svg"),
	"scientist": preload("res://assets/voxel/creatures/ui/role_scientist.svg"),
}

var member: CrewMember
var seat_text := ""

@onready var portrait: CrewPortrait = $HBox/PortraitFrame/Portrait
@onready var portrait_bg: Panel = $HBox/PortraitFrame/Bg
@onready var name_label: Label = $HBox/Info/NameRow/Name
@onready var name_edit: LineEdit = $HBox/Info/NameRow/NameEdit
@onready var rename_btn: Button = $HBox/Info/NameRow/RenameBtn
@onready var badge: PanelContainer = $HBox/Info/BadgeRow/Badge
@onready var role_icon: TextureRect = $HBox/Info/BadgeRow/Badge/HBox/RoleIcon
@onready var role_label: Label = $HBox/Info/BadgeRow/Badge/HBox/RoleLabel
@onready var level_label: Label = $HBox/Info/BadgeRow/Level
@onready var xp_bar: ProgressBar = $HBox/Info/BadgeRow/XP
@onready var courage_bar: ProgressBar = $HBox/Info/Stats/Courage
@onready var skill_bar: ProgressBar = $HBox/Info/Stats/Skill
@onready var curiosity_bar: ProgressBar = $HBox/Info/Stats/Curiosity
@onready var status_label: Label = $HBox/Info/Status
@onready var seat_btn: Button = $HBox/SeatBtn
@onready var select_frame: Panel = $Select


func _ready() -> void:
	rename_btn.pressed.connect(_begin_rename)
	rename_btn.tooltip_text = tr("CREW_RENAME_TIP")
	name_edit.text_submitted.connect(_commit_rename)
	name_edit.focus_exited.connect(func() -> void:
		if name_edit.visible:
			_commit_rename(name_edit.text))
	seat_btn.pressed.connect(func() -> void: seat_requested.emit(member))
	mouse_entered.connect(func() -> void:
		if member:
			portrait.play(["wave", "nod", "jump"][hash(member.id + str(int(Time.get_ticks_msec() / 2000.0))) % 3]))


func set_member(m: CrewMember, seat_desc := "") -> void:
	member = m
	seat_text = seat_desc
	if not is_node_ready():
		await ready
	portrait.set_member(m)
	refresh()


func refresh() -> void:
	if member == null:
		return
	name_label.text = member.display_name
	rename_btn.tooltip_text = tr("CREW_RENAME_TIP")
	$HBox/Info/Stats/CourageLabel.text = tr("STAT_COURAGE")
	$HBox/Info/Stats/SkillLabel.text = tr("STAT_SKILL")
	$HBox/Info/Stats/CuriosityLabel.text = tr("STAT_CURIOSITY")
	var col: Color = ROLE_COLORS.get(member.role, Color.WHITE)
	badge.self_modulate = col
	role_icon.texture = ROLE_ICONS.get(member.role)
	role_label.text = tr("ROLE_" + member.role.to_upper())
	var v := CometlingLooks.get_variant(member.variant)
	portrait_bg.self_modulate = Color(v["body"], 0.5)
	level_label.text = tr("CREW_LEVEL") % (member.level() + 1)
	xp_bar.value = member.level_progress()
	courage_bar.value = member.courage
	skill_bar.value = member.skill
	curiosity_bar.value = member.curiosity
	courage_bar.tooltip_text = "%d%%" % roundi(member.courage * 100)
	skill_bar.tooltip_text = "%d%%" % roundi(member.skill * 100)
	curiosity_bar.tooltip_text = "%d%%" % roundi(member.curiosity * 100)
	if member.is_assigned():
		status_label.text = tr("CREW_STATUS_ASSIGNED") % seat_text
		status_label.add_theme_color_override("font_color", Color("#7ee08a"))
		seat_btn.tooltip_text = tr("CREW_UNASSIGN")
	else:
		status_label.text = tr("CREW_STATUS_AVAILABLE")
		status_label.remove_theme_color_override("font_color")
		seat_btn.tooltip_text = tr("CREW_ASSIGN")
	seat_btn.modulate = Color("#7ee08a") if member.is_assigned() else Color.WHITE
	tooltip_text = "%s · %s\n%s" % [member.display_name, tr("ROLE_" + member.role.to_upper()), tr("ROLE_%s_DESC" % member.role.to_upper())]


func set_selected(on: bool) -> void:
	select_frame.visible = on


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			_begin_rename()
		else:
			selected.emit(self)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if member == null:
		return null
	selected.emit(self)
	var preview := PanelContainer.new()
	preview.theme_type_variation = &"CardPanel"
	var l := Label.new()
	l.text = "  %s  " % member.display_name
	l.add_theme_color_override("font_color", ROLE_COLORS.get(member.role, Color.WHITE))
	preview.add_child(l)
	set_drag_preview(preview)
	portrait.play("jump")
	return {"crew_member_id": member.id}


func _begin_rename() -> void:
	name_edit.text = member.display_name
	name_label.visible = false
	name_edit.visible = true
	name_edit.grab_focus()


func _commit_rename(t: String) -> void:
	name_edit.visible = false
	name_label.visible = true
	if member and t.strip_edges() != member.display_name:
		rename_requested.emit(member, t)
