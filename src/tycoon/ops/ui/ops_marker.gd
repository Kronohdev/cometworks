@tool
class_name OpsMarker
extends Control
## Map marker of a mission (or a ground station): a small engraved diamond in the mission's
## colour, a ring when selected, a slow pulse when a decision waits. Size, colours and
## stroke are exported so the look is tuned on the template in the editor; the screen
## script only sets colour, state and position.

@export var color := Color("#3fe0c5"):
	set(v):
		color = v
		queue_redraw()
@export var fill := Color("#070b14"):
	set(v):
		fill = v
		queue_redraw()
@export var radius := 6.0:
	set(v):
		radius = v
		queue_redraw()
@export var selected := false:
	set(v):
		selected = v
		queue_redraw()
@export var alert := false:
	set(v):
		alert = v
		queue_redraw()
## square instead of diamond (ground stations)
@export var square := false:
	set(v):
		square = v
		queue_redraw()

var _t := 0.0


func _process(delta: float) -> void:
	if alert or selected:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := radius
	var pts := PackedVector2Array()
	if square:
		pts = PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])
	else:
		pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, color, 1.5, true)
	draw_circle(c, r * 0.32, color)
	if alert:
		var k := fmod(_t, 1.4) / 1.4
		draw_arc(c, r + 3.0 + k * 10.0, 0.0, TAU, 32, Color(CwPalette.PEACH, 0.9 * (1.0 - k)), 1.5, true)
	if selected:
		var rr := r + 6.0
		var a := _t * 0.8
		for i in 4:
			var a0 := a + i * TAU / 4.0
			draw_arc(c, rr, a0, a0 + 0.9, 8, CwPalette.ICE, 2.0, true)
