@tool
class_name CwStarfield
extends Control
## Night-sky backdrop for the finale (GDD section 22.3: a faint star-chart grid, no blur):
## seeded pinpoint stars on the space colour, a few brighter ones as tiny crosses, and an
## optional engraved coordinate grid. Fully deterministic, so the editor shows the same sky.

@export var star_seed := 25:
	set(v):
		star_seed = v
		queue_redraw()
@export_range(0, 2000) var stars := 420:
	set(v):
		stars = v
		queue_redraw()
@export var grid := false:
	set(v):
		grid = v
		queue_redraw()
@export var background := Color("#1e1d4a"):
	set(v):
		background = v
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)
	if grid:
		var c := Color(CwPalette.HAIRLINE, 0.12)
		var step := 120.0
		var x := fmod(size.x * 0.5, step)
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), c, 1.0)
			x += step
		var y := fmod(size.y * 0.5, step)
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), c, 1.0)
			y += step
	var rng := RandomNumberGenerator.new()
	rng.seed = star_seed
	for i in stars:
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var b := rng.randf()
		var col := CwPalette.ICE.lerp(Color.WHITE, rng.randf())
		col.a = 0.25 + 0.65 * b * b
		if b > 0.96:
			# a chubby four-point twinkle, some of them butter yellow
			if rng.randf() < 0.4:
				col = Color(CwPalette.BUTTER, col.a)
			var r := 4.0 + 3.0 * rng.randf()
			var q := r * 0.3
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(q, -q), p + Vector2(r, 0),
				p + Vector2(q, q), p + Vector2(0, r), p + Vector2(-q, q), p + Vector2(-r, 0), p + Vector2(-q, -q)]), col)
		else:
			draw_circle(p, 1.5 if b > 0.85 else 1.0, col, true, -1.0, true)
