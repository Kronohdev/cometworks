@tool
class_name CwRaceTrack
extends Control
## The race to the Moon as a calm milestone rail (GDD sections 13 and 22): soft era bands
## (the two Moon eras tinted lilac, the current era in butter), the home world peeking in at
## the left gutter, a little Moon by the first Moon era's name, the Mother-Ice just past the
## last station, and the line of the 15 milestones. The stretch already taken by someone glows
## as the aurora thread; the rest is a plain rail. The art stays in the gutters and the era
## header so it never sits under a label (art_overlaps). Stations, labels and markers are
## scene nodes placed with station_pos() by the race screen; this control only paints.

@export_range(2, 30) var count := 15:
	set(v):
		count = v
		queue_redraw()
## px kept free on the left (the agency column of the lanes below lines up with it)
@export var left_margin := 240.0:
	set(v):
		left_margin = v
		queue_redraw()
## px kept free on the right (the Mother-Ice sits there)
@export var right_margin := 96.0:
	set(v):
		right_margin = v
		queue_redraw()
## height of the line, 0..1 of the control
@export_range(0.0, 1.0) var baseline := 0.54:
	set(v):
		baseline = v
		queue_redraw()
## height of the era name row at the top
@export var header := 22.0:
	set(v):
		header = v
		queue_redraw()
## last station index of eras 1..4 (era 5 runs to the end)
@export var era_breaks := PackedInt32Array([1, 4, 8, 10]):
	set(v):
		era_breaks = v
		queue_redraw()
## eras (1-based) spent on the Moon: their bands are tinted lilac
@export var moon_eras := PackedInt32Array([3, 4]):
	set(v):
		moon_eras = v
		queue_redraw()
## the era on show (1-based): its band is tinted butter
@export_range(0, 5) var current_era := 1:
	set(v):
		current_era = v
		queue_redraw()
## stations already taken from the start (the aurora thread runs to the last of them)
@export_range(0, 30) var reached := 4:
	set(v):
		reached = v
		queue_redraw()

const EARTH_FILL := Color("#bfe4ff")
const MOON_FILL := Color("#ece6f7")
const MOON_R := 9.0


func station_pos(i: int) -> Vector2:
	var x0 := left_margin
	var x1 := size.x - right_margin
	return Vector2(x0 + (x1 - x0) * float(i) / maxf(count - 1, 1), size.y * baseline)


## Horizontal room of one station (the label width that keeps neighbours apart when the
## labels alternate above and below the line).
func station_gap() -> float:
	return (size.x - right_margin - left_margin) / maxf(count - 1, 1)


## x range of era k (0-based) between the separators, for its label.
func era_span(k: int) -> Vector2:
	var first := 0 if k == 0 else era_breaks[k - 1] + 1
	var last := era_breaks[k] if k < era_breaks.size() else count - 1
	var half := station_gap() * 0.5
	return Vector2(station_pos(first).x - half, station_pos(last).x + half)


func earth_center() -> Vector2:
	return Vector2(-40.0, size.y * baseline + 64.0)


func earth_radius() -> float:
	return 150.0


## The little Moon by the name of the first Moon era (left end of its band, in the header).
func moon_center() -> Vector2:
	if moon_eras.is_empty():
		return Vector2(-100, -100)
	var span := era_span(moon_eras[0] - 1)
	return Vector2(span.x + 16.0, header * 0.5 + 1.0)


func moon_radius() -> float:
	return MOON_R


func comet_head() -> Vector2:
	return station_pos(count - 1) + Vector2(34.0, -34.0)


## Does `r` (local rect) sit on the planet, the Moon or the comet's head?
func art_overlaps(r: Rect2) -> bool:
	if _circle_hits(r, earth_center(), earth_radius()):
		return true
	if _circle_hits(r, moon_center(), moon_radius() + 2.0):
		return true
	return _circle_hits(r, comet_head(), 12.0)


static func _circle_hits(r: Rect2, c: Vector2, rad: float) -> bool:
	var nearest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return nearest.distance_to(c) < rad


func _draw() -> void:
	var y := size.y * baseline
	_draw_bands()
	_draw_earth()
	_draw_moon()
	# the rail, from the home world's horizon to the last station
	var start := Vector2(_earth_x_at(y), y)
	var end := station_pos(count - 1)
	draw_line(start, end, Color("#d9c29c"), 6.0, true)
	draw_line(start + Vector2(0, -1.5), end + Vector2(0, -1.5), Color(1, 1, 1, 0.6), 1.5, true)
	# the aurora thread over the stretch already taken
	if reached > 0:
		var stop := station_pos(mini(reached, count) - 1).x
		var n := 64
		for k in n:
			var a := start.x + (stop - start.x) * float(k) / n
			var b := start.x + (stop - start.x) * float(k + 1) / n
			draw_line(Vector2(a, y), Vector2(b + 0.5, y), CwPalette.aurora_at(b / maxf(size.x, 1.0)), 4.0)
	_draw_comet()


## Soft rounded bands behind each era (alternating paper tints; Moon eras lilac, the current
## era butter) - they group the stations without lines through the labels.
func _draw_bands() -> void:
	for k in era_breaks.size() + 1:
		var span := era_span(k)
		var rect := Rect2(span.x + 3.0, 0.0, span.y - span.x - 6.0, size.y)
		var col := Color(CwPalette.INK, 0.03 if k % 2 == 0 else 0.055)
		if moon_eras.has(k + 1):
			col = Color(CwPalette.LILAC, 0.13)
		if current_era == k + 1:
			col = Color(CwPalette.BUTTER, 0.2)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(12)
		sb.anti_aliasing = true
		draw_style_box(sb, rect)


func _earth_x_at(y: float) -> float:
	var c := earth_center()
	var r := earth_radius()
	var dy := c.y - y
	return c.x + sqrt(maxf(r * r - dy * dy, 0.0))


func _draw_earth() -> void:
	var c := earth_center()
	var r := earth_radius()
	draw_circle(c, r + 10.0, Color(CwPalette.ICE, 0.18))
	draw_circle(c, r, EARTH_FILL)
	for k in range(1, 4):
		draw_arc(c, r * (1.0 - 0.2 * k), -PI * 0.5, 0.0, 48, Color(1, 1, 1, 0.45), 1.5, true)
	for blob in [Vector3(0.55, -0.5, 0.16), Vector3(0.25, -0.8, 0.12)]:
		draw_circle(c + Vector2(blob.x, blob.y) * r, blob.z * r, Color(CwPalette.MINT, 0.85), true, -1.0, true)
	draw_arc(c, r, -PI * 0.5, 0.0, 96, CwPalette.INK, 3.0, true)


func _draw_moon() -> void:
	if moon_eras.is_empty():
		return
	var c := moon_center()
	var r := moon_radius()
	draw_circle(c + Vector2(0, 1.5), r, Color(CwPalette.INK, 0.12), true, -1.0, true)
	draw_circle(c, r, MOON_FILL, true, -1.0, true)
	draw_circle(c + Vector2(-0.4, -0.35) * r, 0.2 * r, Color("#d6cbea"), true, -1.0, true)
	draw_circle(c + Vector2(0.45, 0.3) * r, 0.16 * r, Color("#d6cbea"), true, -1.0, true)
	draw_arc(c + Vector2(0, 0.15 * r), 0.22 * r, 0.15 * PI, 0.85 * PI, 8, CwPalette.INK, 1.5, true)
	draw_arc(c, r, 0.0, TAU, 48, CwPalette.INK, 2.0, true)


func _draw_comet() -> void:
	var head := comet_head()
	var last := station_pos(count - 1)
	draw_dashed_line(last + Vector2(6, -6), head + Vector2(-6, 6), Color(CwPalette.LILAC, 0.8), 2.0, 4.0)
	CwCometArt.paint(self, head, Vector2(0.55, -1.0).normalized(), 55.0, 0.7)
