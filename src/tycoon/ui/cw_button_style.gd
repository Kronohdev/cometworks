@tool
class_name CwButtonStyle
extends StyleBox
## Cometworks "candy key" button: a rounded face with a vertical gradient, a darker lip under
## it (the key's thickness, so it reads as something you can press), a soft gloss line along
## the top, an anti-aliased rim and, optionally, a soft glow or drop shadow around it.
## Pressed styles use a thinner lip (and a larger top content margin) so the key sinks.
## `outline_body` wraps the ink outline around the whole key (face + lip, cartoon sticker look)
## and `shine_color` adds a little candy highlight in the face's top-left corner.
## Every look parameter is exported: tune it in the theme editor like any StyleBox.

## face gradient, top -> bottom
@export var face_top := Color("#2c3672"):
	set(v):
		face_top = v
		emit_changed()
@export var face_bottom := Color("#1c2350"):
	set(v):
		face_bottom = v
		emit_changed()
## the key's side, visible under the face (alpha 0 = flat key)
@export var lip_color := Color("#0c1030"):
	set(v):
		lip_color = v
		emit_changed()
## lip thickness (px)
@export_range(0.0, 8.0, 1.0) var lip := 3.0:
	set(v):
		lip = v
		emit_changed()
## 1 px anti-aliased rim around the face (alpha 0 = none)
@export var border_color := Color("#46529a"):
	set(v):
		border_color = v
		emit_changed()
@export_range(0.0, 5.0, 0.5) var border_width := 1.0:
	set(v):
		border_width = v
		emit_changed()
## outline the whole key (face and lip) instead of only the face
@export var outline_body := false:
	set(v):
		outline_body = v
		emit_changed()
## the line between the face and the lip (alpha 0 = none)
@export var seam_color := Color(0, 0, 0, 0):
	set(v):
		seam_color = v
		emit_changed()
## candy highlight: a little rounded dash in the face's top-left corner (alpha 0 = none)
@export var shine_color := Color(1, 1, 1, 0):
	set(v):
		shine_color = v
		emit_changed()
## gloss line under the top edge and a faint sheen over the upper half (alpha 0 = none)
@export var gloss_color := Color(1, 1, 1, 0.16):
	set(v):
		gloss_color = v
		emit_changed()
## the key floats this many px above its rest position (hover "pop"); the lip grows to match
@export_range(0.0, 8.0, 1.0) var lift := 0.0:
	set(v):
		lift = v
		emit_changed()
@export_range(0.0, 40.0, 1.0) var corner_radius := 9.0:
	set(v):
		corner_radius = v
		emit_changed()
## a coloured bar along the left edge, inside the face (selected menu row); alpha 0 = none
@export var accent_color := Color(0, 0, 0, 0):
	set(v):
		accent_color = v
		emit_changed()
@export_range(0.0, 8.0, 1.0) var accent_width := 3.0:
	set(v):
		accent_width = v
		emit_changed()
## soft halo around the key (hover glow, primary call to action); alpha 0 = none
@export var glow_color := Color(0, 0, 0, 0):
	set(v):
		glow_color = v
		emit_changed()
@export_range(0, 40, 1) var glow_size := 0:
	set(v):
		glow_size = v
		emit_changed()
## soft drop shadow (drawn under the glow); alpha 0 = none
@export var shadow_color := Color(0, 0, 0, 0.35):
	set(v):
		shadow_color = v
		emit_changed()
@export var shadow_offset := Vector2(0, 3):
	set(v):
		shadow_offset = v
		emit_changed()
@export_range(0, 30, 1) var shadow_size := 4:
	set(v):
		shadow_size = v
		emit_changed()
@export var padding := Vector4(14, 7, 14, 9):  # left, top, right, bottom (bottom includes the lip)
	set(v):
		padding = v
		content_margin_left = v.x
		content_margin_top = v.y
		content_margin_right = v.z
		content_margin_bottom = v.w
		emit_changed()

const ARC_STEPS := 6

var _halo := StyleBoxFlat.new()


func _init() -> void:
	content_margin_left = padding.x
	content_margin_top = padding.y
	content_margin_right = padding.z
	content_margin_bottom = padding.w


static func rounded_rect(r: Rect2, radius: float, steps := ARC_STEPS) -> PackedVector2Array:
	var k := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var p := PackedVector2Array()
	if k <= 0.5:
		p.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		return p
	var centres := [Vector2(r.end.x - k, r.position.y + k), Vector2(r.end.x - k, r.end.y - k),
		Vector2(r.position.x + k, r.end.y - k), Vector2(r.position.x + k, r.position.y + k)]
	var start := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c in 4:
		for s in steps + 1:
			var a: float = start[c] + PI * 0.5 * float(s) / steps
			p.append(centres[c] + Vector2(cos(a), sin(a)) * k)
	return p


func _draw_halo(ci: RID, rect: Rect2, col: Color, size_px: int, offset: Vector2) -> void:
	if col.a <= 0.0 or size_px <= 0:
		return
	_halo.bg_color = Color(col, 0.0)
	_halo.draw_center = false
	_halo.set_corner_radius_all(int(corner_radius))
	_halo.shadow_color = col
	_halo.shadow_size = size_px
	_halo.shadow_offset = offset
	_halo.anti_aliasing = true
	# StyleBoxFlat only draws its shadow when there is something to draw: give it a hairline
	_halo.set_border_width_all(1)
	_halo.border_color = Color(col, 0.0)
	_halo.draw(ci, rect)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	_draw_halo(to_canvas_item, rect, shadow_color, shadow_size, shadow_offset)
	_draw_halo(to_canvas_item, rect, glow_color, glow_size, Vector2.ZERO)
	rect = Rect2(rect.position - Vector2(0.0, lift), rect.size + Vector2(0.0, lift))
	var face := rect
	if lip + lift > 0.0 and lip_color.a > 0.0:
		var body := rounded_rect(rect, corner_radius)
		rs.canvas_item_add_polygon(to_canvas_item, body, PackedColorArray([lip_color]))
		var b := body.duplicate()
		b.append(body[0])
		rs.canvas_item_add_polyline(to_canvas_item, b, PackedColorArray([lip_color]), 1.0, true)
		face = Rect2(rect.position, Vector2(rect.size.x, maxf(2.0, rect.size.y - lip - lift)))
	var poly := rounded_rect(face, corner_radius)
	var cols := PackedColorArray()
	cols.resize(poly.size())
	for i in poly.size():
		var t := clampf((poly[i].y - face.position.y) / maxf(face.size.y, 1.0), 0.0, 1.0)
		cols[i] = face_top.lerp(face_bottom, t)
	rs.canvas_item_add_polygon(to_canvas_item, poly, cols)
	if gloss_color.a > 0.0 and face.size.y > 8.0:
		# sheen over the upper half (fades out downwards) and a crisp gloss line under the top edge
		var top := Rect2(face.position + Vector2(1, 1), Vector2(face.size.x - 2, face.size.y * 0.5))
		var sheen := rounded_rect(Rect2(top.position, Vector2(top.size.x, top.size.y + corner_radius)), corner_radius - 1.0)
		var sc := PackedColorArray()
		sc.resize(sheen.size())
		for i in sheen.size():
			var t := clampf((sheen[i].y - top.position.y) / maxf(top.size.y, 1.0), 0.0, 1.0)
			sc[i] = Color(gloss_color, gloss_color.a * 0.45 * (1.0 - t))
		rs.canvas_item_add_polygon(to_canvas_item, sheen, sc)
		var k := minf(corner_radius, face.size.y * 0.5)
		rs.canvas_item_add_line(to_canvas_item, Vector2(face.position.x + k * 0.8, face.position.y + 1.5),
			Vector2(face.end.x - k * 0.8, face.position.y + 1.5), gloss_color, 1.0, true)
	if accent_color.a > 0.0 and accent_width > 0.0:
		var k2 := minf(corner_radius, face.size.y * 0.5)
		var bar := rounded_rect(Rect2(face.position + Vector2(3.0, k2 * 0.5 + 3.0),
			Vector2(accent_width, maxf(2.0, face.size.y - k2 - 6.0))), accent_width * 0.5, 3)
		rs.canvas_item_add_polygon(to_canvas_item, bar, PackedColorArray([accent_color]))
	if shine_color.a > 0.0 and face.size.y > 14.0 and face.size.x > 30.0:
		# a little candy highlight: a short dash and a dot in the top-left of the face
		var k3 := minf(corner_radius, face.size.y * 0.5)
		var sh := clampf(face.size.y * 0.12, 3.0, 4.5)
		var sw := clampf(face.size.x * 0.06, 6.0, 12.0)
		var at := face.position + Vector2(maxf(k3 * 0.85, 7.0) + border_width, 3.0 + border_width)
		rs.canvas_item_add_polygon(to_canvas_item, rounded_rect(Rect2(at, Vector2(sw, sh)), sh * 0.5, 3),
			PackedColorArray([shine_color]))
		rs.canvas_item_add_circle(to_canvas_item, at + Vector2(sw + sh * 1.2, sh * 0.5), sh * 0.45, shine_color, true)
	if seam_color.a > 0.0 and face.size.y < rect.size.y - 0.5:
		var k4 := minf(corner_radius, face.size.y * 0.5)
		rs.canvas_item_add_line(to_canvas_item, Vector2(face.position.x + k4 * 0.4, face.end.y),
			Vector2(face.end.x - k4 * 0.4, face.end.y), seam_color, 1.5, true)
	var rim := border_color if border_color.a > 0.0 else face_bottom
	var w := border_width if border_color.a > 0.0 else 1.0
	if outline_body and border_color.a > 0.0:
		var body2 := rounded_rect(rect.grow(-w * 0.5), corner_radius)
		body2.append(body2[0])
		rs.canvas_item_add_polyline(to_canvas_item, body2, PackedColorArray([rim]), w, true)
	else:
		var line := poly.duplicate()
		line.append(poly[0])
		rs.canvas_item_add_polyline(to_canvas_item, line, PackedColorArray([rim]), w, true)


func _get_draw_rect(rect: Rect2) -> Rect2:
	var g := float(maxi(glow_size, shadow_size)) + maxf(absf(shadow_offset.x), absf(shadow_offset.y))
	return rect.grow_individual(g + 2.0, g + 2.0 + lift, g + 2.0, g + 2.0)
