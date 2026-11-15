class_name SurfacePicker
extends CanvasLayer
## "Superfícies": pick a world for free play (scenes/surface/explore/surface_picker.tscn), from the
## main menu (every body open, the free-play log) or the campus (the bodies the career has landed
## on, SurfaceLog.unlocked_bodies; the others show "Land there first"). One row per body of
## data/surface_explore.json, duplicated from the hidden %BodyTemplate; the row shows the field
## log's progress. Emits chosen(body) / closed.

signal chosen(body: StringName)
signal closed

## body order on the list
const ORDER := ["moon", "mars", "europa", "mercury", "earth"]

var state: TycoonState


func _ready() -> void:
	visible = false
	%Close.pressed.connect(close)
	%Backdrop.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())


## Shows the list; `p_state` null = the main menu's free play.
func open(p_state: TycoonState = null) -> void:
	state = p_state
	fill()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func fill() -> void:
	%Lead.text = tr("TY_SX_PICK_LEAD") if state else tr("TY_SX_PICK_LEAD_MENU")
	var flog := SurfaceLog.open(state)
	var bodies: Array = []
	for id: String in ORDER:
		if not SurfaceExplore.body_data(id).is_empty():
			bodies.append(id)
	var rows := TycoonHUD._copies(%BodyTemplate, bodies.size())
	for i in bodies.size():
		var id: String = bodies[i]
		var bd := SurfaceExplore.body_data(id)
		var row := rows[i] as Button
		var open := SurfaceLog.is_unlocked(state, id)
		(row.get_node("HBox/Text/Name") as Label).text = _cap(tr(String(bd.get("name_key", ""))))
		var info := row.get_node("HBox/Text/Info") as Label
		if open:
			info.text = tr("TY_SX_PICK_PROGRESS") % [flog.found_count(id), (bd.get("pois", []) as Array).size(), flog.collected_count(id)]
		else:
			info.text = tr("TY_SX_PICK_LOCKED")
		row.disabled = not open
		row.tooltip_text = "" if open else "TY_SX_PICK_LOCKED_TIP"
		(row.get_node("HBox/Lock") as Control).visible = not open
		row.set_meta("body", id)
		for c in row.pressed.get_connections():
			row.pressed.disconnect(c["callable"])
		row.pressed.connect(_pick.bind(id))


func _pick(id: String) -> void:
	visible = false
	chosen.emit(StringName(id))


func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
