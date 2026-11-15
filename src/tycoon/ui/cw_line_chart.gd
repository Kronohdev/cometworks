@tool
class_name CwLineChart
extends Control
## A light line chart for values on a fixed range (reputation and hype, 0..100) over the
## campaign: the Estatísticas page (scenes/tycoon/ui/screens/stats.tscn). Engraved grid every
## `grid_step`, the year ticks the screen gives in `ticks` ({x 0..1: label}), one rounded line
## per series with a soft fill under the first and a dot on each line's last value. The screen
## fills `series` ([{"values": PackedFloat32Array, "color": Color}]); the look is the exports.

@export var min_value := 0.0:
	set(v):
		min_value = v
		queue_redraw()
@export var max_value := 100.0:
	set(v):
		max_value = v
		queue_redraw()
@export var grid_step := 25.0:
	set(v):
		grid_step = v
		queue_redraw()
@export var grid_color := Color("#ecdcc0"):
	set(v):
		grid_color = v
		queue_redraw()
@export var label_color := Color("#5d5b8c"):
	set(v):
		label_color = v
		queue_redraw()
@export var font_size := 12:
	set(v):
		font_size = v
		queue_redraw()
@export var line_width := 3.0:
	set(v):
		line_width = v
		queue_redraw()
## room for the value labels (left) and the year ticks (bottom)
@export var margin := Vector2(34, 20):
	set(v):
		margin = v
		queue_redraw()

var series: Array = [
	{"values": PackedFloat32Array([20, 24, 22, 30, 38, 41, 47, 52]), "color": Color("#2f78cc")},
	{"values": PackedFloat32Array([5, 18, 12, 9, 30, 22, 40, 33]), "color": Color("#d6407e")}]:
	set(v):
		series = v
		queue_redraw()
## {x (0..1 along the chart): label}
var ticks: Dictionary = {}:
	set(v):
		ticks = v
		queue_redraw()


func plot_rect() -> Rect2:
	return Rect2(margin.x, 8.0, maxf(size.x - margin.x - 10.0, 1.0), maxf(size.y - margin.y - 12.0, 1.0))


func _draw() -> void:
	var font := get_theme_default_font()
	var plot := plot_rect()
	var span := maxf(max_value - min_value, 0.001)
	var to_y := func(v: float) -> float: return plot.end.y - (clampf(v, min_value, max_value) - min_value) / span * plot.size.y
	var g := min_value
	while g <= max_value + 0.001:
		var y: float = to_y.call(g)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid_color, 1.0)
		draw_string(font, Vector2(0, y + font_size * 0.35), "%d" % roundi(g), HORIZONTAL_ALIGNMENT_RIGHT, margin.x - 8.0,
			font_size, label_color)
		g += maxf(grid_step, 1.0)
	for x: Variant in ticks:
		var px := plot.position.x + clampf(float(x), 0.0, 1.0) * plot.size.x
		draw_line(Vector2(px, plot.position.y), Vector2(px, plot.end.y), grid_color.darkened(0.06), 1.0)
		draw_string(font, Vector2(px - 30.0, size.y - 3.0), String(ticks[x]), HORIZONTAL_ALIGNMENT_CENTER, 60.0,
			font_size, label_color)
	for i in series.size():
		var sr: Dictionary = series[i]
		var vals: PackedFloat32Array = sr.get("values", PackedFloat32Array())
		var col: Color = sr.get("color", Color.WHITE)
		if vals.is_empty():
			continue
		var pts := PackedVector2Array()
		var n := vals.size()
		for k in n:
			var x := plot.position.x + (float(k) / float(maxi(n - 1, 1))) * plot.size.x
			pts.append(Vector2(x, to_y.call(vals[k])))
		if n == 1:
			pts.append(Vector2(plot.end.x, pts[0].y))
		if i == 0:
			var poly := pts.duplicate()
			poly.append(Vector2(pts[-1].x, plot.end.y))
			poly.append(Vector2(pts[0].x, plot.end.y))
			var fill := col
			fill.a = 0.12
			draw_colored_polygon(poly, fill)
		draw_polyline(pts, col, line_width, true)
		draw_circle(pts[-1], line_width + 2.5, CwPalette.INK)
		draw_circle(pts[-1], line_width + 1.0, col)
