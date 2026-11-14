@tool
class_name CwCometArt
extends Control
## The Mother-Ice as candy line art: a chubby four-point star with an ink outline for the
## nucleus and a fan of soft tail ribbons running from mint to lilac to peach, fading out. Draws centred on `head` (0..1 of the control) with the
## tail along `direction`. paint() is shared with the race track.

@export var head := Vector2(0.8, 0.3):
	set(v):
		head = v
		queue_redraw()
@export var direction := Vector2(-1.0, -0.15):
	set(v):
		direction = v
		queue_redraw()
@export var length := 420.0:
	set(v):
		length = v
		queue_redraw()
@export var art_scale := 2.0:
	set(v):
		art_scale = v
		queue_redraw()


func _draw() -> void:
	paint(self, head * size, direction.normalized(), length, art_scale)


static func paint(ci: CanvasItem, at: Vector2, dir: Vector2, tail: float, k: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	# tail threads: a narrow fan, each a run of short segments fading along its length
	var threads := [[0.0, 1.0, 1.0], [0.07, 0.86, 0.8], [-0.06, 0.78, 0.8], [0.15, 0.62, 0.6], [-0.13, 0.55, 0.6],
		[0.24, 0.42, 0.45], [0.03, 0.95, 0.55]]
	for t: Array in threads:
		var spread := float(t[0])
		var len_k := float(t[1])
		var alpha := float(t[2])
		var n := 28
		var prev := at
		for i in range(1, n + 1):
			var f := float(i) / n
			var p := at + dir * tail * len_k * f + side * spread * tail * len_k * f * f
			var col := CwPalette.aurora_at(f)
			col.a = alpha * pow(1.0 - f, 0.75)
			ci.draw_line(prev, p, col, 2.2 * k if i < n / 3 else 2.0, true)
			prev = p
	# coma: two faint rings, then the four-point nucleus
	ci.draw_circle(at, 14.0 * k, Color(CwPalette.LILAC, 0.22), true, -1.0, true)
	ci.draw_circle(at, 9.0 * k, Color(CwPalette.ICE, 0.3), true, -1.0, true)
	var r := 8.0 * k
	var q := r * 0.34
	var star := PackedVector2Array([at + Vector2(0, -r), at + Vector2(q, -q), at + Vector2(r, 0), at + Vector2(q, q),
		at + Vector2(0, r), at + Vector2(-q, q), at + Vector2(-r, 0), at + Vector2(-q, -q)])
	ci.draw_colored_polygon(star, CwPalette.BUTTER)
	star.append(star[0])
	ci.draw_polyline(star, CwPalette.INK, maxf(1.5, 1.2 * k), true)
	ci.draw_circle(at + Vector2(-0.18, -0.18) * r, 1.4 * k, Color.WHITE)
