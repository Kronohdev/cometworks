@tool
class_name CwMarker
extends Control
## Race marker (GDD section 22.4): a small diamond centred in the control, filled with
## `fill` (alpha 0 = hollow), 1 px `outline`, and an optional engraved `ring` around it
## for the milestone being chased. Used on the race track, the agency lanes and legends.

@export var fill := Color(0, 0, 0, 0):
	set(v):
		fill = v
		queue_redraw()
@export var outline := Color("#8c89b3"):
	set(v):
		outline = v
		queue_redraw()
## half diagonal of the diamond in px; 0 = fit the control
@export var radius := 0.0:
	set(v):
		radius = v
		queue_redraw()
@export var ring := false:
	set(v):
		ring = v
		queue_redraw()
@export var ring_color := Color("#7652e8"):
	set(v):
		ring_color = v
		queue_redraw()
## a cut through the diamond: the milestone is the comet / the victory
@export var star := false:
	set(v):
		star = v
		queue_redraw()


func _ready() -> void:
	add_to_group(CwAccess.CUE_GROUP)   # redrawn when the colour-blind mode changes


func _draw() -> void:
	var c := size * 0.5
	var r := radius if radius > 0.0 else minf(size.x, size.y) * 0.5 - 1.0
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	if star:
		var k := r * 0.32
		pts = PackedVector2Array([c + Vector2(0, -r * 1.25), c + Vector2(k, -k), c + Vector2(r * 1.25, 0), c + Vector2(k, k),
			c + Vector2(0, r * 1.25), c + Vector2(-k, k), c + Vector2(-r * 1.25, 0), c + Vector2(-k, -k)])
	if fill.a > 0.0:
		draw_colored_polygon(pts, fill)
		# colour-blind mode: the agency's shape cue inside (CwPalette.cue_of)
		CwPalette.draw_cue(self, CwPalette.cue_of(fill), c, r * 0.62, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, outline, 1.0, true)
	if ring:
		var rr := r + 4.0
		var ring_pts := PackedVector2Array([c + Vector2(0, -rr), c + Vector2(rr, 0), c + Vector2(0, rr), c + Vector2(-rr, 0), c + Vector2(0, -rr)])
		draw_polyline(ring_pts, ring_color, 1.0, true)
