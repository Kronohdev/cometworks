@tool
class_name CwMoodFace
extends Control
## A little round face for a Cometling's morale (0-100): beaming, smiling, flat or droopy,
## tinted from teal (great) to butter (tired) and coral (low), with an ink outline. Drawn in
## code so it scales with the control; set `mood` from a script.

@export_range(0.0, 100.0, 1.0) var mood := 70.0:
	set(v):
		mood = v
		queue_redraw()
@export var ink := Color(0.1686, 0.1647, 0.3608, 1)
@export_range(0.5, 4.0, 0.1) var outline := 1.6


static func mood_color(mo: float) -> Color:
	if mo < 30.0:
		return Color("#ff8f8f")
	if mo < 50.0:
		return Color("#ffd166")
	if mo < 80.0:
		return Color("#9be8c9")
	return Color("#5fe0b4")


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - outline
	if r <= 1.0:
		return
	var c := size * 0.5
	draw_circle(c, r, mood_color(mood))
	draw_arc(c, r, 0.0, TAU, 32, ink, outline, true)
	# eyes
	var ey := c.y - r * 0.18
	var ex := r * 0.36
	var er := maxf(r * 0.11, 1.0)
	if mood >= 80.0:
		# happy closed eyes: little arcs
		draw_arc(Vector2(c.x - ex, ey + er * 0.6), er * 1.3, PI * 1.1, PI * 1.9, 8, ink, outline, true)
		draw_arc(Vector2(c.x + ex, ey + er * 0.6), er * 1.3, PI * 1.1, PI * 1.9, 8, ink, outline, true)
	else:
		draw_circle(Vector2(c.x - ex, ey), er, ink)
		draw_circle(Vector2(c.x + ex, ey), er, ink)
	# mouth
	var my := c.y + r * 0.28
	var mw := r * 0.42
	if mood >= 50.0:
		var deep := 0.75 if mood >= 80.0 else 0.5
		draw_arc(Vector2(c.x, my - mw * deep), mw, PI * 0.2, PI * 0.8, 10, ink, outline, true)
	elif mood >= 30.0:
		draw_line(Vector2(c.x - mw * 0.7, my), Vector2(c.x + mw * 0.7, my), ink, outline, true)
	else:
		draw_arc(Vector2(c.x, my + mw * 0.7), mw * 0.8, PI * 1.2, PI * 1.8, 10, ink, outline, true)
	# blush on the happy ones
	if mood >= 50.0:
		var blush := Color(1.0, 0.55, 0.6, 0.45)
		draw_circle(Vector2(c.x - r * 0.58, c.y + r * 0.12), r * 0.13, blush)
		draw_circle(Vector2(c.x + r * 0.58, c.y + r * 0.12), r * 0.13, blush)
