@tool
class_name CwPanelStyle
extends StyleBox
## Cometworks "sticker" panel: a soft paper face (optionally a vertical gradient, bg_color ->
## bg_color_bottom), big rounded corners, a chunky anti-aliased ink outline, a solid "lip" under
## it (the sticker's thickness, like the candy keys), a soft drop shadow, faint polka dots, an
## inner highlight, an optional colour wash under the top edge and a coloured tab on the left.
## Older looks (chamfer, corner ticks, grain, the aurora thread) are still available but off in
## the theme. Usable in themes like any StyleBox; every look parameter is exported so it can be
## tuned in the inspector.

const GRAIN_TEX := preload("res://ui/cometworks/theme/grain.png")

var _shadow_box := StyleBoxFlat.new()

@export var bg_color := Color("#0e1524"):
	set(v):
		bg_color = v
		emit_changed()
## gradient end colour at the bottom edge; alpha 0 = flat bg_color
@export var bg_color_bottom := Color(0, 0, 0, 0):
	set(v):
		bg_color_bottom = v
		emit_changed()
@export var border_color := Color("#24324d"):
	set(v):
		border_color = v
		emit_changed()
@export_range(1.0, 6.0, 0.5) var border_width := 1.0:
	set(v):
		border_width = v
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
## blur of the drop shadow (px); 0 = the hard offset shadow
@export_range(0, 40, 1) var shadow_blur := 0:
	set(v):
		shadow_blur = v
		emit_changed()
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.45):
	set(v):
		shadow_color = v
		emit_changed()
## solid lip under the panel (the sticker's thickness), drawn in lip_color; 0 = none
@export_range(0.0, 12.0, 1.0) var lip := 0.0:
	set(v):
		lip = v
		emit_changed()
@export var lip_color := Color(0, 0, 0, 0):
	set(v):
		lip_color = v
		emit_changed()
## faint polka dots over the face (alpha 0 = none)
@export var pattern_color := Color(0, 0, 0, 0):
	set(v):
		pattern_color = v
		emit_changed()
@export_range(8.0, 64.0, 1.0) var pattern_spacing := 22.0:
	set(v):
		pattern_spacing = v
		emit_changed()
@export_range(0.5, 6.0, 0.5) var pattern_radius := 2.0:
	set(v):
		pattern_radius = v
		emit_changed()
## soft light just inside the border (glass edge), brightest along the top; alpha 0 = none
@export var rim_color := Color(0, 0, 0, 0):
	set(v):
		rim_color = v
		emit_changed()
## a wash of colour fading down from the top edge (aurora glow behind a title); alpha 0 = none
@export var top_glow := Color(0, 0, 0, 0):
	set(v):
		top_glow = v
		emit_changed()
@export_range(4.0, 200.0, 1.0) var top_glow_height := 48.0:
	set(v):
		top_glow_height = v
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
	var steps := clampi(int(k / 2.0) + 1, 1, 6)
	# top-left arc, top edge, chamfer (or a rounded top-right), right edge, bottom arcs
	_arc(p, r.position + Vector2(k, k), k, PI, steps)
	if c > 0.5:
		p.append(Vector2(r.end.x - c, r.position.y))
		p.append(Vector2(r.end.x, r.position.y + c))
	else:
		_arc(p, Vector2(r.end.x - k, r.position.y + k), k, -PI * 0.5, steps)
	_arc(p, r.end - Vector2(k, k), k, 0.0, steps)
	_arc(p, Vector2(r.position.x + k, r.end.y - k), k, PI * 0.5, steps)
	return p


## Appends a quarter arc (from `from` clockwise on screen) around `centre`; a single corner
## point when the radius is ~0.
static func _arc(p: PackedVector2Array, centre: Vector2, k: float, from: float, steps: int) -> void:
	if k <= 0.5:
		p.append(centre)
		return
	for i in steps + 1:
		var ang := from + PI * 0.5 * float(i) / steps
		p.append(centre + Vector2(cos(ang), sin(ang)) * k)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var poly := _outline(rect)
	if shadow_blur > 0:
		_draw_soft_shadow(to_canvas_item, rect)
	elif shadow_offset > 0.0:
		var sh := PackedVector2Array()
		for v in poly:
			sh.append(v + Vector2(shadow_offset, shadow_offset))
		rs.canvas_item_add_polygon(to_canvas_item, sh, PackedColorArray([shadow_color]))
	if lip > 0.0 and lip_color.a > 0.0:
		var lp := _outline(Rect2(rect.position + Vector2(0.0, lip), rect.size))
		rs.canvas_item_add_polygon(to_canvas_item, lp, PackedColorArray([lip_color]))
		lp.append(lp[0])
		rs.canvas_item_add_polyline(to_canvas_item, lp, PackedColorArray([lip_color]), 1.0, true)
	if bg_color_bottom.a > 0.0:
		var cols := PackedColorArray()
		cols.resize(poly.size())
		for i in poly.size():
			cols[i] = bg_color.lerp(bg_color_bottom, clampf((poly[i].y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0))
		rs.canvas_item_add_polygon(to_canvas_item, poly, cols)
	else:
		rs.canvas_item_add_polygon(to_canvas_item, poly, PackedColorArray([bg_color]))
	if top_glow.a > 0.0 and rect.size.y > 12.0:
		var h := minf(top_glow_height, rect.size.y)
		var gp := PackedVector2Array()
		for v in poly:
			gp.append(Vector2(v.x, minf(v.y, rect.position.y + h)))
		var gc := PackedColorArray()
		gc.resize(gp.size())
		for i in gp.size():
			var t := clampf((gp[i].y - rect.position.y) / h, 0.0, 1.0)
			gc[i] = Color(top_glow, top_glow.a * (1.0 - t) * (1.0 - t))
		rs.canvas_item_add_polygon(to_canvas_item, gp, gc)
	if grain > 0.0:
		_draw_grain(to_canvas_item, poly, rect)
	if pattern_color.a > 0.0:
		_draw_dots(to_canvas_item, rect)
	var kr := minf(corner_radius, minf(rect.size.x, rect.size.y) * 0.25)
	if bevel_color.a > 0.0 and rect.size.y > 6.0:
		var cx := minf(chamfer, minf(rect.size.x, rect.size.y) * 0.5)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x + kr + 1.0, rect.position.y + 1.0,
			maxf(0.0, rect.size.x - maxf(cx, kr) - kr - 2.0), 1.0), bevel_color)
	if tab_color.a > 0.0:
		# a rounded candy tab just inside the outline
		var tw := 5.0
		var tr := Rect2(rect.position + Vector2(border_width + 4.0, border_width + 7.0),
			Vector2(tw, maxf(0.0, rect.size.y - 2.0 * border_width - 14.0)))
		if tr.size.y > tw:
			rs.canvas_item_add_polygon(to_canvas_item, CwButtonStyle.rounded_rect(tr, tw * 0.5, 3),
				PackedColorArray([tab_color]))
	if rim_color.a > 0.0 and rect.size.x > 8.0 and rect.size.y > 8.0:
		var inner := _outline(rect.grow(-1.5))
		inner.append(inner[0])
		var rc := PackedColorArray()
		rc.resize(inner.size())
		for i in inner.size():
			# brighter along the top, fading towards the bottom (light from above)
			var t := clampf((inner[i].y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
			rc[i] = Color(rim_color, rim_color.a * lerpf(1.0, 0.2, sqrt(t)))
		rs.canvas_item_add_polyline(to_canvas_item, inner, rc, 1.0, true)
	# border (closed polyline, anti-aliased so the rounded corners stay smooth)
	if border_color.a > 0.0:
		var b := poly.duplicate()
		b.append(poly[0])
		if border_width > 1.0:
			# a thick border sits inside the outline so it never spills over the shadow
			b = _outline(rect.grow(-border_width * 0.5))
			b.append(b[0])
		rs.canvas_item_add_polyline(to_canvas_item, b, PackedColorArray([border_color]), border_width, true)
	# corner ticks: little L marks inside the three rounded corners
	if tick_length > 0.0 and rect.size.x > tick_length * 4.0 and rect.size.y > tick_length * 4.0:
		var t := tick_length
		var i := 3.0 + kr * 0.35
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
		_draw_aurora(to_canvas_item, rect.position.x + kr + 1.0, rect.end.x - maxf(cut, kr) - 1.0, rect.position.y)
	if aurora_bottom:
		_draw_aurora(to_canvas_item, rect.position.x + kr + 1.0, rect.end.x - kr - 1.0, rect.end.y - aurora_width)


## Staggered polka dots, kept clear of the rounded corners and the border.
func _draw_dots(ci: RID, rect: Rect2) -> void:
	var k := minf(corner_radius, minf(rect.size.x, rect.size.y) * 0.25)
	var inner := rect.grow(-(border_width + pattern_radius + 3.0))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var sp := pattern_spacing
	var row := 0
	var y := inner.position.y + sp * 0.5
	while y < inner.end.y:
		var x := inner.position.x + (sp * 0.5 if row % 2 == 1 else 0.0) + sp * 0.25
		while x < inner.end.x:
			var p := Vector2(x, y)
			# skip the dots in the rounded corners
			var cx := clampf(p.x, rect.position.x + k, rect.end.x - k)
			var cy := clampf(p.y, rect.position.y + k, rect.end.y - k)
			if p.distance_to(Vector2(cx, cy)) <= k - border_width - pattern_radius - 3.0 or (cx == p.x or cy == p.y):
				RenderingServer.canvas_item_add_circle(ci, p, pattern_radius, pattern_color, true)
			x += sp
		y += sp * 0.5
		row += 1


func _draw_soft_shadow(ci: RID, rect: Rect2) -> void:
	_shadow_box.bg_color = Color(shadow_color, 0.0)
	_shadow_box.draw_center = false
	_shadow_box.set_border_width_all(1)
	_shadow_box.border_color = Color(shadow_color, 0.0)
	_shadow_box.set_corner_radius_all(int(corner_radius))
	_shadow_box.shadow_color = shadow_color
	_shadow_box.shadow_size = shadow_blur
	_shadow_box.shadow_offset = Vector2(0.0, shadow_offset)
	_shadow_box.draw(ci, rect)


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
	var rad := minf(corner_radius, minf(rect.size.x, rect.size.y) * 0.25) + 1.0
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x
		while x < rect.end.x:
			var tile := Rect2(x, y, minf(ts.x, rect.end.x - x), minf(ts.y, rect.end.y - y))
			var near_x := tile.position.x < rect.position.x + rad or tile.end.x > rect.end.x - rad
			var near_y := tile.position.y < rect.position.y + rad or tile.end.y > rect.end.y - rad
			var near_cut := (tile.end.x > rect.end.x - cut and tile.position.y < rect.position.y + cut) \
				or (near_x and near_y)
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
	if shadow_blur > 0:
		return rect.grow(float(shadow_blur) + maxf(shadow_offset, lip) + 2.0)
	return rect.grow_individual(1, 1, shadow_offset + 1.0, maxf(shadow_offset, lip) + 1.0)
