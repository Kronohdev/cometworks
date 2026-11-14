@tool
class_name CwRaceTrack
extends Control
## The race to the Moon drawn as an engraved instrument chart (GDD sections 13 and 22): the
## home world rising at the left, the Moon behind the robotic / crewed stations, the
## Mother-Ice at the far end, a faint star-chart grid, era separators, and the line of the
## 15 milestones. The stretch already taken by someone glows as the aurora thread; the rest
## is an engraved rail. Stations, labels and markers are scene nodes placed with
## station_pos() by the race screen; this control only paints the backdrop.

@export_range(2, 30) var count := 15:
	set(v):
		count = v
		queue_redraw()
## px kept free on the left (the agency column of the lanes below lines up with it)
@export var left_margin := 240.0:
	set(v):
		left_margin = v
		queue_redraw()
@export var right_margin := 70.0:
	set(v):
		right_margin = v
		queue_redraw()
## height of the line, 0..1 of the control
@export_range(0.0, 1.0) var baseline := 0.6:
	set(v):
		baseline = v
		queue_redraw()
## last station index of eras 1..4 (era 5 runs to the end)
@export var era_breaks := PackedInt32Array([1, 4, 8, 10]):
	set(v):
		era_breaks = v
		queue_redraw()
## stations drawn over the Moon (first, last)
@export var moon_span := Vector2i(5, 10):
	set(v):
		moon_span = v
		queue_redraw()
## stations already taken from the start (the aurora thread runs to the last of them)
@export_range(0, 30) var reached := 4:
	set(v):
		reached = v
		queue_redraw()

const EARTH_FILL := Color("#bfe4ff")
const MOON_FILL := Color("#ece6f7")


func station_pos(i: int) -> Vector2:
	var x0 := left_margin
	var x1 := size.x - right_margin
	return Vector2(x0 + (x1 - x0) * float(i) / maxf(count - 1, 1), size.y * baseline)


## x range of era k (0-based) between the separators, for its label.
func era_span(k: int) -> Vector2:
	var first := 0 if k == 0 else era_breaks[k - 1] + 1
	var last := era_breaks[k] if k < era_breaks.size() else count - 1
	var half := (station_pos(1).x - station_pos(0).x) * 0.5
	return Vector2(station_pos(first).x - half, station_pos(last).x + half)


func earth_center() -> Vector2:
	return Vector2(-70.0, size.y + 130.0)


func earth_radius() -> float:
	return size.y * 0.5 + 200.0


func moon_center() -> Vector2:
	var a := station_pos(moon_span.x)
	var b := station_pos(moon_span.y)
	return Vector2((a.x + b.x) * 0.5, a.y + 6.0)


func moon_radius() -> float:
	return size.y * 0.36


func comet_head() -> Vector2:
	return station_pos(count - 1) + Vector2(26.0, -size.y * 0.36)


func _draw() -> void:
	var y := size.y * baseline
	_draw_grid()
	_draw_earth()
	_draw_moon()
	# era separators: dashed hairlines between the eras
	for k in era_breaks.size():
		var x := (station_pos(era_breaks[k]).x + station_pos(era_breaks[k] + 1).x) * 0.5
		draw_dashed_line(Vector2(x, 26.0), Vector2(x, size.y - 6.0), Color(CwPalette.INK_SOFT, 0.3), 1.5, 5.0)
	# the rail, from the home world's horizon to the last station
	var start := Vector2(_earth_x_at(y), y)
	var end := station_pos(count - 1)
	draw_line(start, end, Color("#d9c29c"), 6.0, true)
	draw_line(start + Vector2(0, -1.5), end + Vector2(0, -1.5), Color(1, 1, 1, 0.6), 1.5, true)
	# minor ticks between stations, like the scale of an instrument
	var step := (station_pos(1).x - station_pos(0).x) / 4.0
	for i in count - 1:
		for k in range(1, 4):
			var x := station_pos(i).x + step * k
			draw_line(Vector2(x, y + 5.0), Vector2(x, y + (9.0 if k == 2 else 7.0)), Color(CwPalette.INK_SOFT, 0.35), 1.5)
	# the aurora thread over the stretch already taken
	if reached > 0:
		var stop := station_pos(mini(reached, count) - 1).x
		var n := 64
		for k in n:
			var a := start.x + (stop - start.x) * float(k) / n
			var b := start.x + (stop - start.x) * float(k + 1) / n
			draw_line(Vector2(a, y), Vector2(b + 0.5, y), CwPalette.aurora_at(b / maxf(size.x, 1.0)), 4.0)
	_draw_comet()


func _draw_grid() -> void:
	var c := Color(CwPalette.HAIRLINE, 0.3)
	var gx := 32.0
	var gy := 32.0
	var x := fmod(left_margin, gx)
	while x < size.x:
		var yy := 16.0
		while yy < size.y:
			draw_rect(Rect2(x, yy, 1.0, 1.0), c)
			yy += gy
		x += gx


func _earth_x_at(y: float) -> float:
	var c := earth_center()
	var r := earth_radius()
	var dy := c.y - y
	return c.x + sqrt(maxf(r * r - dy * dy, 0.0))


func _draw_earth() -> void:
	var c := earth_center()
	var r := earth_radius()
	draw_circle(c, r + 12.0, Color(CwPalette.ICE, 0.18))
	draw_circle(c, r, EARTH_FILL)
	# soft meridians and parallels, and a couple of mint continents
	for k in range(1, 5):
		draw_arc(c, r * (1.0 - 0.17 * k), -PI * 0.5, 0.0, 48, Color(1, 1, 1, 0.45), 1.5, true)
	for blob in [Vector3(0.62, -0.42, 0.16), Vector3(0.35, -0.72, 0.12), Vector3(0.8, -0.15, 0.1)]:
		draw_circle(c + Vector2(blob.x, blob.y) * r, blob.z * r, Color(CwPalette.MINT, 0.85), true, -1.0, true)
	draw_arc(c, r, -PI * 0.5, 0.0, 96, CwPalette.INK, 3.0, true)


func _draw_moon() -> void:
	var c := moon_center()
	var r := moon_radius()
	draw_circle(c + Vector2(0, 4), r, Color(CwPalette.INK, 0.12), true, -1.0, true)
	draw_circle(c, r, MOON_FILL, true, -1.0, true)
	# craters, then a sleepy little face
	for cr in [Vector3(-0.42, -0.38, 0.14), Vector3(0.36, -0.46, 0.1), Vector3(0.5, 0.3, 0.13), Vector3(-0.5, 0.36, 0.09)]:
		draw_circle(c + Vector2(cr.x, cr.y) * r, cr.z * r, Color("#d6cbea"), true, -1.0, true)
	var e := r * 0.2
	draw_arc(c + Vector2(-e, -r * 0.02), r * 0.07, 0.15 * PI, 0.85 * PI, 10, CwPalette.INK, 2.0, true)
	draw_arc(c + Vector2(e, -r * 0.02), r * 0.07, 0.15 * PI, 0.85 * PI, 10, CwPalette.INK, 2.0, true)
	draw_circle(c + Vector2(-e * 1.7, r * 0.14), r * 0.06, Color(CwPalette.PINK, 0.7), true, -1.0, true)
	draw_circle(c + Vector2(e * 1.7, r * 0.14), r * 0.06, Color(CwPalette.PINK, 0.7), true, -1.0, true)
	draw_arc(c + Vector2(0, r * 0.12), r * 0.06, 0.1 * PI, 0.9 * PI, 10, CwPalette.INK, 2.0, true)
	draw_arc(c, r, 0.0, TAU, 96, CwPalette.INK, 3.0, true)


func _draw_comet() -> void:
	var head := comet_head()
	var last := station_pos(count - 1)
	draw_dashed_line(last + Vector2(4, -8), head + Vector2(-3, 8), Color(CwPalette.LILAC, 0.8), 2.0, 4.0)
	CwCometArt.paint(self, head, Vector2(-1.0, -0.12).normalized(), 190.0, 1.0)
