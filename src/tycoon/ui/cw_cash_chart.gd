@tool
class_name CwCashChart
extends Control
## Cash chart of the finance screen (scenes/tycoon/ui/screens/finance.tscn): month-end cash
## for the last months as a comet-ice line, the projection as a dashed teal line, monthly net
## as thin LED bars along the bottom, engraved grid, a red zero line when cash dips below it.
## The screen fills `cash` (oldest first), `net`, `labels` (one per month, "" for none) and
## `projection`.

@export var line_color := Color("#2f78cc"):
	set(v):
		line_color = v
		queue_redraw()
@export var projection_color := Color("#0e9077"):
	set(v):
		projection_color = v
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
## space for the axis labels: left, bottom
@export var margin := Vector2(64, 22):
	set(v):
		margin = v
		queue_redraw()
## height of the monthly-net band at the bottom
@export var net_band := 46.0:
	set(v):
		net_band = v
		queue_redraw()

var cash: PackedFloat32Array = PackedFloat32Array([300000, 280000, 260000, 410000, 390000, 520000]):
	set(v):
		cash = v
		queue_redraw()
var net: PackedFloat32Array = PackedFloat32Array([0, -20000, -20000, 150000, -20000, 130000]):
	set(v):
		net = v
		queue_redraw()
var labels: PackedStringArray = PackedStringArray():
	set(v):
		labels = v
		queue_redraw()
var projection: PackedFloat32Array = PackedFloat32Array([500000, 480000, 460000]):
	set(v):
		projection = v
		queue_redraw()


static func _short(v: float) -> String:
	var a := absf(v)
	var sgn := "−" if v < 0.0 else ""
	if a >= 1.0e6:
		return "%s%.1fM" % [sgn, a / 1.0e6]
	if a >= 1.0e3:
		return "%s%dk" % [sgn, roundi(a / 1.0e3)]
	return "%s%d" % [sgn, roundi(a)]


static func _nice_step(span: float) -> float:
	var raw := span / 6.0
	var mag := pow(10.0, floorf(log(maxf(raw, 1.0)) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if raw <= m * mag:
			return m * mag
	return 10.0 * mag


func _draw() -> void:
	var font := get_theme_default_font()
	var n := cash.size() + projection.size()
	if n < 2:
		return
	var plot := Rect2(margin.x, 6.0, size.x - margin.x - 8.0, size.y - margin.y - net_band - 18.0)
	var band := Rect2(plot.position.x, plot.end.y + 14.0, plot.size.x, net_band)
	# value range: the data plus a little air (and zero), gridlines at a round step inside it
	var lo := 0.0
	var hi := 1.0
	for v in cash:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for v in projection:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var pad := (hi - lo) * 0.08 + 1.0
	hi += pad
	if lo < 0.0:
		lo -= pad
	var step := _nice_step(hi - lo)
	var xs := plot.size.x / float(n - 1)
	var to_y := func(v: float) -> float: return plot.end.y - (v - lo) / (hi - lo) * plot.size.y
	# grid and value labels
	var g := ceilf(lo / step) * step
	while g <= hi:
		var y: float = to_y.call(g)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid_color, 1.0)
		var txt := _short(g)
		draw_string(font, Vector2(0, y + font_size * 0.35), txt, HORIZONTAL_ALIGNMENT_RIGHT, margin.x - 10.0,
			font_size, label_color)
		g += step
	if lo < 0.0:
		var zy: float = to_y.call(0.0)
		draw_line(Vector2(plot.position.x, zy), Vector2(plot.end.x, zy), CwPalette.DANGER, 1.0)
	# month ticks and labels (year marks)
	for i in labels.size():
		if labels[i] == "":
			continue
		var x := plot.position.x + i * xs
		draw_line(Vector2(x, plot.position.y), Vector2(x, band.end.y), grid_color.darkened(0.08), 1.0)
		draw_string(font, Vector2(x + 4.0, size.y - 4.0), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
	# "now" divider between history and projection
	var now_x := plot.position.x + (cash.size() - 1) * xs
	if projection.size() > 0:
		draw_rect(Rect2(now_x, plot.position.y, plot.end.x - now_x, plot.size.y), Color(CwPalette.LILAC_LIGHT, 0.6))
		draw_line(Vector2(now_x, plot.position.y), Vector2(now_x, band.end.y), CwPalette.HAIRLINE, 1.0)
	# monthly net, LED bars
	var nmax := 1.0
	for v in net:
		nmax = maxf(nmax, absf(v))
	var mid := band.position.y + band.size.y * 0.5
	draw_line(Vector2(band.position.x, band.position.y - 7.0), Vector2(band.end.x, band.position.y - 7.0),
		CwPalette.LINE, 1.0)
	draw_line(Vector2(band.position.x, mid), Vector2(band.end.x, mid), grid_color, 1.0)
	var bw := clampf(xs * 0.5, 2.0, 14.0)
	for i in net.size():
		var h := net[i] / nmax * band.size.y * 0.5
		var x := plot.position.x + i * xs - bw * 0.5
		var c := CwPalette.AURORA_TEAL if net[i] >= 0.0 else CwPalette.DANGER
		# a rounded candy bar per month
		if absf(h) >= 1.0:
			var r := Rect2(x, mid - h if h >= 0.0 else mid, bw, absf(h))
			_bar.bg_color = Color(c, 0.85)
			_bar.set_corner_radius_all(int(minf(bw * 0.5, absf(h) * 0.5)))
			draw_style_box(_bar, r)
	# cash line
	var pts := PackedVector2Array()
	for i in cash.size():
		pts.append(Vector2(plot.position.x + i * xs, to_y.call(cash[i])))
	if pts.size() >= 2:
		draw_polyline(pts, Color(line_color, 0.25), 6.0, true)
		draw_polyline(pts, line_color, 2.5, true)
	for p in pts:
		draw_circle(p, 2.5, line_color, true, -1.0, true)
	# projection, dashed
	if projection.size() > 0 and not pts.is_empty():
		var prev := pts[-1]
		for i in projection.size():
			var p := Vector2(now_x + (i + 1) * xs, to_y.call(projection[i]))
			var seg := 6
			for k in seg:
				if k % 2 == 0:
					draw_line(prev.lerp(p, float(k) / seg), prev.lerp(p, float(k + 1) / seg), projection_color, 2.5, true)
			prev = p
	# today's marker
	if not pts.is_empty():
		var last := pts[-1]
		draw_circle(last, 6.5, Color.WHITE, true, -1.0, true)
		draw_arc(last, 6.5, 0.0, TAU, 24, CwPalette.INK, 2.0, true)
		draw_circle(last, 3.0, CwPalette.IGNITION, true, -1.0, true)


var _bar := StyleBoxFlat.new()
