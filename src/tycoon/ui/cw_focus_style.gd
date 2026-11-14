@tool
class_name CwFocusStyle
extends StyleBox
## Keyboard focus / field focus for the Cometworks theme: a crisp 1 px ring (no glow) a little
## outside the control and, for text fields, the aurora thread along the bottom edge (GDD 22.3:
## the aurora appears "no foco de um campo"). Drawn on top of the normal style.

@export var ring_color := Color("#3fe0c5"):
	set(v):
		ring_color = v
		emit_changed()
## how far outside the control the ring sits (px)
@export var ring_offset := 2.0:
	set(v):
		ring_offset = v
		emit_changed()
@export var aurora := false:
	set(v):
		aurora = v
		emit_changed()
@export_range(1.0, 4.0, 1.0) var aurora_width := 2.0:
	set(v):
		aurora_width = v
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if ring_color.a > 0.0:
		var r := rect.grow(ring_offset)
		var p := PackedVector2Array([r.position + Vector2(0.5, 0.5), Vector2(r.end.x - 0.5, r.position.y + 0.5),
			r.end - Vector2(0.5, 0.5), Vector2(r.position.x + 0.5, r.end.y - 0.5), r.position + Vector2(0.5, 0.5)])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, p, PackedColorArray([ring_color]), 1.0, false)
	if aurora:
		var n := clampi(int(rect.size.x / 10.0), 4, 48)
		for k in n:
			var a := rect.position.x + rect.size.x * float(k) / n
			var b := rect.position.x + rect.size.x * float(k + 1) / n
			RenderingServer.canvas_item_add_rect(to_canvas_item,
				Rect2(a, rect.end.y - aurora_width, b - a + 0.5, aurora_width), CwPalette.aurora_at((float(k) + 0.5) / n))


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(ring_offset + 1.0)
