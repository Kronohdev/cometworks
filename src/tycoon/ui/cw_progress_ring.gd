@tool
class_name CwProgressRing
extends Control
## A round progress gauge around a research card's badge (the research tree, research.tscn): a
## faint track, the done part in `color` from twelve o'clock clockwise and, when `spark` is on, a
## bright spark at `spin` radians past the top (the card's AnimationPlayer turns it while the tech
## is being researched).

@export_range(0.0, 1.0) var value := 0.35:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var color := Color("#7652e8"):
	set(v):
		color = v
		queue_redraw()
@export var track_color := Color(0.1686, 0.1647, 0.3608, 0.14):
	set(v):
		track_color = v
		queue_redraw()
@export var width := 4.0:
	set(v):
		width = v
		queue_redraw()
@export var spark := true:
	set(v):
		spark = v
		queue_redraw()
@export var spark_color := Color("#ff9a5c"):
	set(v):
		spark_color = v
		queue_redraw()
@export var spin := 0.0:
	set(v):
		spin = v
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - width * 0.5
	if r <= 1.0:
		return
	draw_arc(c, r, 0.0, TAU, 48, track_color, width, true)
	if value > 0.001:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * value, maxi(int(48 * value), 6), color, width, true)
	if spark:
		var a := -PI * 0.5 + spin
		draw_circle(c + Vector2(cos(a), sin(a)) * r, width * 0.95, spark_color)
		draw_circle(c + Vector2(cos(a), sin(a)) * r, width * 0.45, Color.WHITE)
