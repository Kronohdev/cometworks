@tool
class_name CwProjectSteps
extends HBoxContainer
## The steps of a mission project (scenes/tycoon/ui/cw_project_steps.tscn): briefing,
## objective, payload, team, rocket (the designer, or "Montar no hangar"), launch (the pad's
## choice for a rocket built in the hangar). Each screen of the flow drops one in its header and sets
## `current` in the inspector; the steps before it are ticked, the one on show is lit, the
## rest wait. Every step (its bubble and its name) and the lines between them are authored in
## the scene; this script only picks the bubble's text, the theme variation and the colours.

## index of the step on show (0 = briefing ... 4 = rocket, 5 = launch)
@export_range(0, 5) var current := 0:
	set(v):
		current = v
		_paint()
## lit bubble / name of the step on show
@export var now_color := Color("#e5651c")
## ticked steps
@export var done_color := Color("#0e9077")
## steps still ahead
@export var todo_color := Color("#5d5b8c")


func _ready() -> void:
	_paint()


## The step nodes, in order (children named Step0..Step5).
func steps() -> Array[Control]:
	var out: Array[Control] = []
	for c in get_children():
		if c is Control and String(c.name).begins_with("Step"):
			out.append(c)
	return out


func _paint() -> void:
	if not is_inside_tree():
		return
	var list := steps()
	for i in list.size():
		var st := list[i]
		var num := st.get_node_or_null("Bubble/Num") as Label
		var name_l := st.get_node_or_null("Name") as Label
		var col := now_color if i == current else (done_color if i < current else todo_color)
		if num:
			num.text = "✓" if i < current else str(i + 1)
			num.add_theme_color_override("font_color", col)
		if name_l:
			name_l.add_theme_color_override("font_color", col)
			name_l.theme_type_variation = &"CwCapsAccent" if i == current else &"CwCaps"
		var bubble := st.get_node_or_null("Bubble") as Control
		if bubble:
			bubble.modulate = Color(1, 1, 1, 1.0 if i <= current else 0.55)
	for c in get_children():
		if c is Control and String(c.name).begins_with("Line"):
			var k := String(c.name).trim_prefix("Line").to_int()
			(c as Control).modulate = Color(1, 1, 1, 1.0 if k < current else 0.4)
