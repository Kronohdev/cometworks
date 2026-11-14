@tool
class_name CwLedStyle
extends StyleBox
## Segmented LED meter as a StyleBox (GDD section 22.4 "barras de qualidade"), so a plain
## ProgressBar reads as an instrument: the theme uses one for the track (unlit cells) and one
## for the fill (lit cells). Cells are laid out from the left edge with a fixed pitch, so the
## fill's cells sit exactly on the track's. `lit_top` adds a 1 px highlight on lit cells.

@export var color := Color("#3fe0c5"):
	set(v):
		color = v
		emit_changed()
## cell width and gap (px)
@export var cell := 6.0:
	set(v):
		cell = maxf(1.0, v)
		emit_changed()
@export var gap := 2.0:
	set(v):
		gap = maxf(0.0, v)
		emit_changed()
## brighter top line on each cell (lit look); alpha 0 = none
@export var highlight := Color(1, 1, 1, 0.0):
	set(v):
		highlight = v
		emit_changed()
## 1 px frame drawn around the whole meter (track only); alpha 0 = none
@export var frame_color := Color(0, 0, 0, 0):
	set(v):
		frame_color = v
		emit_changed()
## minimum height so a bare ProgressBar gets a sensible size
@export var min_height := 8.0:
	set(v):
		min_height = v
		emit_changed()


func _get_minimum_size() -> Vector2:
	return Vector2(cell, min_height)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if frame_color.a > 0.0:
		rs.canvas_item_add_rect(to_canvas_item, rect.grow(2.0), frame_color)
		rs.canvas_item_add_rect(to_canvas_item, rect.grow(1.0), Color("#070b14"))
	var pitch := cell + gap
	var x := rect.position.x
	while x < rect.end.x - 0.5:
		var w := minf(cell, rect.end.x - x)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(x, rect.position.y, w, rect.size.y), color)
		if highlight.a > 0.0 and rect.size.y > 3.0:
			rs.canvas_item_add_rect(to_canvas_item, Rect2(x, rect.position.y, w, 1.0), highlight)
		x += pitch
