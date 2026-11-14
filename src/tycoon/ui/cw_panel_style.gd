@tool
class_name CwPanelStyle
extends StyleBox
## Cometworks instrument panel (GDD section 22.3): opaque fill, 1 px engraved border, one
## chamfered corner (top right), small corner ticks, a hard 2 px shadow, a fine paint grain
## and, optionally, the aurora thread along the top (or bottom) edge. Usable in themes like
## any StyleBox; every look parameter is exported so it can be tuned in the inspector.

const GRAIN_TEX := preload("res://ui/cometworks/theme/grain.png")

@export var bg_color := Color("#0e1524"):
	set(v):
		bg_color = v
		emit_changed()
@export var border_color := Color("#24324d"):
	set(v):
		border_color = v
		emit_changed()
@export var tick_color := Color("#3a4d72"):
	set(v):
		tick_color = v
		emit_changed()
## top-right corner cut (px); 0 = none
@export var chamfer := 10.0:
	set(v):
		chamfer = v
		emit_changed()
@export var corner_radius := 3.0:
	set(v):
		corner_radius = v
		emit_changed()
@export var tick_length := 6.0:
	set(v):
		tick_length = v
		emit_changed()
@export var shadow_offset := 2.0:
	set(v):
		shadow_offset = v
		emit_changed()
@export var aurora_top := false:
	set(v):
		aurora_top = v
		emit_changed()
## the aurora thread along the bottom edge instead (field focus, tab underline)
@export var aurora_bottom := false:
	set(v):
		aurora_bottom = v
		emit_changed()
@export_range(1.0, 4.0, 1.0) var aurora_width := 2.0:
	set(v):
		aurora_width = v
		emit_changed()
## coloured tab along the left edge (project strips); alpha 0 = none
@export var tab_color := Color(0, 0, 0, 0):
	set(v):
		tab_color = v
		emit_changed()
## paint grain over the fill (0 = none; 0.04-0.08 reads as painted metal)
@export_range(0.0, 0.3, 0.005) var grain := 0.035:
	set(v):
		grain = v
		emit_changed()
## 1 px inner highlight under the top edge (engraved plate); alpha 0 = none
@export var bevel_color := Color(1, 1, 1, 0.035):
	set(v):
		bevel_color = v
		emit_changed()
@export var padding := Vector4(12, 10, 12, 10):  # left, top, right, bottom
	set(v):
		padding = v
		content_margin_left = v.x
		content_margin_top = v.y
		content_margin_right = v.z
		content_margin_bottom = v.w
		emit_changed()


func _init() -> void:
	content_margin_left = padding.x
	content_margin_top = padding.y
	content_margin_right = padding.z
	content_margin_bottom = padding.w


func _outline(r: Rect2) -> PackedVector2Array:
	var c := minf(chamfer, minf(r.size.x, r.size.y) * 0.5)
	var k := minf(corner_radius, minf(r.size.x, r.size.y) * 0.25)
	var p := PackedVector2Array()
	# top-left (rounded a little), top edge, chamfer, right edge, bottom corners
	p.append(r.position + Vector2(0, k))
	p.append(r.position + Vector2(k * 0.3, k * 0.3))
	p.append(r.position + Vector2(k, 0))
	p.append(Vector2(r.end.x - c, r.position.y))
	p.append(Vector2(r.end.x, r.position.y + c))
	p.append(Vector2(r.end.x, r.end.y - k))
	p.append(Vector2(r.end.x - k * 0.3, r.end.y - k * 0.3))
	p.append(Vector2(r.end.x - k, r.end.y))
	p.append(Vector2(r.position.x + k, r.end.y))
	p.append(Vector2(r.position.x + k * 0.3, r.end.y - k * 0.3))
	p.append(Vector2(r.position.x, r.end.y - k))
	return p


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var poly := _outline(rect)
	if shadow_offset > 0.0:
		var sh := PackedVector2Array()
		for v in poly:
			sh.append(v + Vector2(shadow_offset, shadow_offset))
		rs.canvas_item_add_polygon(to_canvas_item, sh, PackedColorArray([CwPalette.SHADOW]))
	rs.canvas_item_add_polygon(to_canvas_item, poly, PackedColorArray([bg_color]))
	if grain > 0.0:
		_draw_grain(to_canvas_item, poly, rect)
	if bevel_color.a > 0.0 and rect.size.y > 6.0:
		var cx := minf(chamfer, minf(rect.size.x, rect.size.y) * 0.5)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x + 2.0, rect.position.y + 1.0,
			maxf(0.0, rect.size.x - cx - 3.0), 1.0), bevel_color)
	if tab_color.a > 0.0:
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position + Vector2(0, 2), Vector2(3, rect.size.y - 4)),
			tab_color)
	# engraved border (closed polyline, half-pixel inset so it stays crisp)
	if border_color.a > 0.0:
		var b := poly.duplicate()
		b.append(poly[0])
		rs.canvas_item_add_polyline(to_canvas_item, b, PackedColorArray([border_color]), 1.0, false)
	# corner ticks: little L marks inside the three square corners
	if tick_length > 0.0 and rect.size.x > tick_length * 4.0 and rect.size.y > tick_length * 4.0:
		var t := tick_length
		var i := 3.0
		var tl := rect.position + Vector2(i, i)
		var bl := Vector2(rect.position.x + i, rect.end.y - i)
		var br := rect.end - Vector2(i, i)
		for seg: PackedVector2Array in [
				PackedVector2Array([tl + Vector2(0, t), tl, tl + Vector2(t, 0)]),
				PackedVector2Array([bl + Vector2(0, -t), bl, bl + Vector2(t, 0)]),
				PackedVector2Array([br + Vector2(0, -t), br, br + Vector2(-t, 0)])]:
			rs.canvas_item_add_polyline(to_canvas_item, seg, PackedColorArray([tick_color]), 1.0, false)
	if aurora_top:
		var cut := minf(chamfer, minf(rect.size.x, rect.size.y) * 0.5)
		_draw_aurora(to_canvas_item, rect.position.x + 1.0, rect.end.x - cut - 1.0, rect.position.y)
	if aurora_bottom:
		_draw_aurora(to_canvas_item, rect.position.x + 1.0, rect.end.x - 1.0, rect.end.y - aurora_width)


func _draw_aurora(ci: RID, x0: float, x1: float, y: float) -> void:
	var n := clampi(int((x1 - x0) / 12.0), 6, 48)
	for k in n:
		var a := x0 + (x1 - x0) * float(k) / n
		var bb := x0 + (x1 - x0) * float(k + 1) / n
		RenderingServer.canvas_item_add_rect(ci, Rect2(a, y, bb - a + 0.5, aurora_width),
			CwPalette.aurora_at((float(k) + 0.5) / n))


## Tiles the grain texture over the panel outline without needing texture repeat: each tile is
## clipped to the outline (only the tile on the chamfer actually needs clipping).
func _draw_grain(ci: RID, poly: PackedVector2Array, rect: Rect2) -> void:
	var ts := Vector2(GRAIN_TEX.get_width(), GRAIN_TEX.get_height())
	var tint := Color(1, 1, 1, grain)
	var cut := minf(chamfer, minf(rect.size.x, rect.size.y) * 0.5) + 1.0
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x
		while x < rect.end.x:
			var tile := Rect2(x, y, minf(ts.x, rect.end.x - x), minf(ts.y, rect.end.y - y))
			var near_cut := tile.end.x > rect.end.x - cut and tile.position.y < rect.position.y + cut
			if not near_cut:
				var src := Rect2(Vector2.ZERO, tile.size)
				RenderingServer.canvas_item_add_texture_rect_region(ci, tile, GRAIN_TEX.get_rid(), src, tint)
			else:
				var quad := PackedVector2Array([tile.position, Vector2(tile.end.x, tile.position.y), tile.end,
					Vector2(tile.position.x, tile.end.y)])
				for part in Geometry2D.intersect_polygons(poly, quad):
					var uv := PackedVector2Array()
					for v in part:
						uv.append((v - tile.position) / ts)
					var cols := PackedColorArray()
					cols.resize(part.size())
					cols.fill(tint)
					RenderingServer.canvas_item_add_polygon(ci, part, cols, uv, GRAIN_TEX.get_rid())
			x += ts.x
		y += ts.y


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow_individual(0, 0, shadow_offset, shadow_offset)
