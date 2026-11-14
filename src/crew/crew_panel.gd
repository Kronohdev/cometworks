class_name CrewPanel
extends PanelContainer
## Crew panel (scenes/ui/crew_panel.tscn): the Cometling roster with live 3D portraits,
## role badges, stat bars, hire / rename, and the crew seats of the current vessel.
## Seat crew by dragging a card onto a seat, by selecting a card and clicking a seat,
## or with the card's seat button (first free seat).
##
## Embedding (e.g. in the hangar HUD's CrewSlot container):
##     var panel := preload("res://scenes/ui/crew_panel.tscn").instantiate() as CrewPanel
##     crew_slot.add_child(panel)
##     panel.set_vessel(hangar.vessel)          # or set vessel_path in the inspector
##     panel.crew_assigned.connect(func(m, part, seat): ...)
## All strings come from i18n/crew_strings.csv (registered at runtime, EN + PT).

signal member_selected(member: CrewMember)
signal crew_assigned(member: CrewMember, part: Node, seat: int)
signal crew_unassigned(member: CrewMember)
signal member_hired(member: CrewMember)
signal roster_changed
signal close_requested

@export var card_scene: PackedScene
@export var seat_scene: PackedScene
## Optional: the Vessel node to seat crew in (otherwise call set_vessel).
@export var vessel_path: NodePath
## Shows the × button that emits close_requested.
@export var show_close_button := false

var roster: CrewRoster
var vessel: Node
var selected: CrewMember

var _cards: Dictionary = {}     # member id -> CrewCard
var _dirty := true

@onready var title: Label = $Margin/VBox/Header/Titles/Title
@onready var subtitle: Label = $Margin/VBox/Header/Titles/Subtitle
@onready var hire_btn: Button = $Margin/VBox/Header/HireBtn
@onready var close_btn: Button = $Margin/VBox/Header/CloseBtn
@onready var seats_title: Label = $Margin/VBox/SeatsTitle
@onready var seats_box: HFlowContainer = $Margin/VBox/Seats
@onready var no_seats: Label = $Margin/VBox/NoSeats
@onready var roster_title: Label = $Margin/VBox/RosterTitle
@onready var list: VBoxContainer = $Margin/VBox/Scroll/List
@onready var hint: Label = $Margin/VBox/Hint
@onready var mod_att: Label = $Margin/VBox/Mods/Attitude
@onready var mod_rel: Label = $Margin/VBox/Mods/Reliability
@onready var mod_sci: Label = $Margin/VBox/Mods/Science


func _ready() -> void:
	ensure_translations()
	close_btn.visible = show_close_button
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	hire_btn.pressed.connect(_on_hire)
	if roster == null:
		set_roster(CrewRoster.shared())
	if vessel == null and vessel_path != NodePath():
		set_vessel(get_node_or_null(vessel_path))
	_apply_texts()
	refresh()


static var _translations_done := false


## Registers i18n/crew_strings.* with the TranslationServer once (no project setting needed).
static func ensure_translations() -> void:
	if _translations_done:
		return
	_translations_done = true
	for loc in ["en", "pt"]:
		var path := "res://i18n/crew_strings.%s.translation" % loc
		if ResourceLoader.exists(path):
			TranslationServer.add_translation(load(path) as Translation)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_texts()
		refresh()


func _apply_texts() -> void:
	title.text = tr("CREW_TITLE")
	subtitle.text = tr("CREW_SUBTITLE")
	hire_btn.text = tr("CREW_HIRE")
	hire_btn.tooltip_text = tr("CREW_HIRE_TIP")
	seats_title.text = tr("CREW_SEATS")
	roster_title.text = tr("CREW_ROSTER")
	hint.text = tr("CREW_DRAG_HINT")


func set_roster(r: CrewRoster) -> void:
	if roster and roster.changed.is_connected(_on_roster_changed):
		roster.changed.disconnect(_on_roster_changed)
	roster = r
	roster.changed.connect(_on_roster_changed)
	_dirty = true
	if is_node_ready():
		refresh()


func set_vessel(v: Node) -> void:
	if vessel and is_instance_valid(vessel) and vessel.is_connected("changed", _on_vessel_changed):
		vessel.disconnect("changed", _on_vessel_changed)
	vessel = v
	if vessel and vessel.has_signal("changed"):
		vessel.connect("changed", _on_vessel_changed)
		if roster:
			roster.bind_vessel(vessel)
	if is_node_ready():
		refresh()


func _on_roster_changed() -> void:
	_dirty = true
	_queue_refresh()
	roster_changed.emit()


func _on_vessel_changed() -> void:
	_queue_refresh()


var _refresh_queued := false


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	(func() -> void:
		_refresh_queued = false
		if is_inside_tree():
			refresh()).call_deferred()


## Rebuilds the seat strip and updates every card.
func refresh() -> void:
	if roster == null:
		return
	if vessel and is_instance_valid(vessel):
		roster.prune(vessel)
	_sync_cards()
	_build_seats()
	_update_mods()


func _part_title(part: Node) -> String:
	var id: String = String(part.get("part_id")) if part.get("part_id") != null else String(part.name)
	return PartDB.part_name(id) if id != "" else String(part.name)


func _seat_desc(m: CrewMember) -> String:
	if not m.is_assigned():
		return ""
	var title_txt := m.assigned_part.get_file()
	if vessel and is_instance_valid(vessel):
		var p := vessel.get_node_or_null(NodePath(m.assigned_part))
		if p:
			title_txt = _part_title(p)
	return "%s · %s" % [title_txt, tr("CREW_SEAT_N") % (m.assigned_seat + 1)]


func _sync_cards() -> void:
	var ids := {}
	for m in roster.members:
		ids[m.id] = true
		var card: CrewCard = _cards.get(m.id)
		if card == null:
			card = card_scene.instantiate() as CrewCard
			list.add_child(card)
			card.selected.connect(_on_card_selected)
			card.seat_requested.connect(_on_seat_requested)
			card.rename_requested.connect(func(mem: CrewMember, n: String) -> void: roster.rename(mem, n))
			_cards[m.id] = card
			card.set_member(m, _seat_desc(m))
		else:
			card.seat_text = _seat_desc(m)
			card.refresh()
		card.set_selected(m == selected)
	for id in _cards.keys():
		if not ids.has(id):
			(_cards[id] as Node).queue_free()
			_cards.erase(id)
	# keep roster order
	for i in roster.members.size():
		var c: Node = _cards[roster.members[i].id]
		list.move_child(c, i)


func _build_seats() -> void:
	for c in seats_box.get_children():
		c.queue_free()
	var seats: Array[Dictionary] = []
	if vessel and is_instance_valid(vessel):
		seats = CrewRoster.seats_for_vessel(vessel, roster)
	no_seats.visible = seats.is_empty()
	no_seats.text = tr("CREW_NO_SEATS") if vessel else tr("CREW_NO_VESSEL")
	for s in seats:
		var slot := seat_scene.instantiate() as CrewSeatSlot
		seats_box.add_child(slot)
		slot.setup(s["part"], int(s["seat"]), s["member"], _part_title(s["part"]))
		slot.clicked.connect(_on_slot_clicked)
		slot.dropped.connect(_on_slot_dropped)
		slot.unseat_requested.connect(func(sl: CrewSeatSlot) -> void:
			if sl.member:
				_unassign(sl.member))


func _update_mods() -> void:
	var mods := roster.mission_modifiers(vessel) if vessel and is_instance_valid(vessel) else {"attitude_control": 1.0, "reliability": 1.0, "science_return": 1.0}
	mod_att.text = tr("CREW_MOD_ATTITUDE") % roundi((float(mods["attitude_control"]) - 1.0) * 100.0)
	mod_rel.text = tr("CREW_MOD_RELIABILITY") % roundi((float(mods["reliability"]) - 1.0) * 100.0)
	mod_sci.text = tr("CREW_MOD_SCIENCE") % roundi((float(mods["science_return"]) - 1.0) * 100.0)
	for pair in [[mod_att, mods["attitude_control"]], [mod_rel, mods["reliability"]], [mod_sci, mods["science_return"]]]:
		var l := pair[0] as Label
		if float(pair[1]) > 1.0:
			l.add_theme_color_override("font_color", Color("#7ee08a"))
		else:
			l.remove_theme_color_override("font_color")


# ------------------------------------------------------------------ interaction
func select_member(m: CrewMember) -> void:
	selected = m
	for id in _cards:
		(_cards[id] as CrewCard).set_selected(m != null and id == m.id)
	if m:
		member_selected.emit(m)


func _on_card_selected(card: CrewCard) -> void:
	select_member(card.member if selected != card.member else null)


func _on_seat_requested(m: CrewMember) -> void:
	if m.is_assigned():
		_unassign(m)
		return
	if vessel == null or not is_instance_valid(vessel):
		_flash(tr("CREW_NO_VESSEL"))
		return
	var before := m.is_assigned()
	if roster.assign_auto(m, vessel):
		_after_assign(m)
	elif not before:
		_flash(tr("CREW_SEATS_FULL") if not CrewRoster.seats_for_vessel(vessel, roster).is_empty() else tr("CREW_NO_SEATS"))


func _on_slot_clicked(slot: CrewSeatSlot) -> void:
	if selected:
		_assign(selected, slot)
	elif slot.member:
		select_member(slot.member)


func _on_slot_dropped(slot: CrewSeatSlot, member_id: String) -> void:
	var m := roster.find(member_id)
	if m:
		_assign(m, slot)


## Seats `m` in the slot's seat; a member already there swaps out.
func _assign(m: CrewMember, slot: CrewSeatSlot) -> void:
	if roster.assign(m, slot.part, slot.seat, true):
		_after_assign(m)


func _after_assign(m: CrewMember) -> void:
	var card: CrewCard = _cards.get(m.id)
	if card:
		card.portrait.play("cheer")
	var part: Node = null
	if vessel:
		part = vessel.get_node_or_null(NodePath(m.assigned_part))
	crew_assigned.emit(m, part, m.assigned_seat)
	NpcEvents.emit("staged", {"stagger": 0.6})
	select_member(null)
	refresh()


func _unassign(m: CrewMember) -> void:
	roster.unassign(m)
	var card: CrewCard = _cards.get(m.id)
	if card:
		card.portrait.play("nod")
	crew_unassigned.emit(m)
	refresh()


func _on_hire() -> void:
	var m := roster.hire()
	member_hired.emit(m)
	refresh()
	var card: CrewCard = _cards.get(m.id)
	if card:
		card.portrait.play("wave")
		await get_tree().process_frame
		($Margin/VBox/Scroll as ScrollContainer).ensure_control_visible(card)
	NpcEvents.emit("hello", {"stagger": 0.8})


func _flash(msg: String) -> void:
	hint.text = msg
	hint.add_theme_color_override("font_color", Color("#ffcc55"))
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		if is_inside_tree():
			hint.remove_theme_color_override("font_color")
			hint.text = tr("CREW_DRAG_HINT"))
