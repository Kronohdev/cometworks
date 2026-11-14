@tool
class_name MenuCampusShot
extends MenuShot
## The Cometworks campus at dusk as a shot of the menu loop (scenes/menu/shots/shot_campus.tscn).
## The campus scene (scenes/tycoon/campus.tscn) is instanced as is; at runtime this script
## gives it a demo campaign state with every lot built, so buildings, scaffold-free roads
## and the walking Cometlings show up. Pick the look with `era` and `level`.

@export var campus: Node3D
@export_range(1, 5) var era := 3
@export_range(1, 3) var level := 2


func _ready() -> void:
	super()
	if Engine.is_editor_hint() or campus == null or not campus.has_method("bind"):
		return
	var st := TycoonState.new_campaign(2026)
	st.weeks = (era - 1) * 5 * st.weeks_per_year() + 10
	for lot: String in st.lot_ids():
		st.buildings[lot] = {"kind": st.lot_kind(lot), "level": level, "target": level, "weeks_left": 0}
	campus.call("bind", st)
