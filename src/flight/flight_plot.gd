class_name FlightPlot
extends Control
## Altitude / speed plot of the flight report (sized and placed in flight_hud.tscn).
## Draws a light grid, the altitude curve (Signal Orange, left axis) and the speed curve
## (Mission Blue, right axis), with tick marks for the stage events.

@export var alt_color := Color(0.961, 0.604, 0.212)
@export var speed_color := Color(0.373, 0.69, 0.847)
@export var grid_color := Color(0.231, 0.29, 0.361, 0.6)
@export var text_color := Color(0.549, 0.608, 0.71)
@export var line_width := 2.5

var _t := PackedFloat32Array()
var _alt := PackedFloat32Array()
var _v := PackedFloat32Array()
var _events: Array = []


func set_data(t: PackedFloat32Array, alt: PackedFloat32Array, v: PackedFloat32Array, events: Array) -> void:
	_t = t
	_alt = alt
	_v = v
	_events = events
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(70, 8), size - Vector2(146, 30))
	var font := get_theme_default_font()
	var fs := 11
	for i in 5:
		var y := r.position.y + r.size.y * float(i) / 4.0
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), grid_color, 1.0)
	draw_line(r.position + Vector2(0, r.size.y), r.end, grid_color.lightened(0.2), 1.0)
	if _t.size() < 2:
		draw_string(font, r.get_center() - Vector2(40, 0), "—", HORIZONTAL_ALIGNMENT_CENTER, -1, fs, text_color)
		return
	var t1: float = maxf(_t[_t.size() - 1], 1.0)
	var a1 := 1.0
	var v1 := 1.0
	for i in _t.size():
		a1 = maxf(a1, _alt[i])
		v1 = maxf(v1, _v[i])
	a1 = _nice(a1)
	v1 = _nice(v1)
	var pa := PackedVector2Array()
	var pv := PackedVector2Array()
	for i in _t.size():
		var x := r.position.x + r.size.x * _t[i] / t1
		pa.append(Vector2(x, r.end.y - r.size.y * _alt[i] / a1))
		pv.append(Vector2(x, r.end.y - r.size.y * _v[i] / v1))
	for e in _events:
		if String(e["key"]) in ["EV_BOOSTER_SEP", "EV_STAGE_SEP", "EV_MAXQ", "EV_ORBIT", "EV_FAIRING"]:
			var x := r.position.x + r.size.x * clampf(float(e["t"]) / t1, 0.0, 1.0)
			draw_dashed_line(Vector2(x, r.position.y), Vector2(x, r.end.y), text_color * Color(1, 1, 1, 0.5), 1.0, 4.0)
	draw_polyline(pv, speed_color, line_width, true)
	draw_polyline(pa, alt_color, line_width, true)
	# axes labels
	draw_string(font, Vector2(0, r.position.y + 10), FlightHUD.fmt_dist(a1), HORIZONTAL_ALIGNMENT_RIGHT, 64, fs, alt_color)
	draw_string(font, Vector2(0, r.end.y), "0", HORIZONTAL_ALIGNMENT_RIGHT, 64, fs, text_color)
	draw_string(font, Vector2(r.end.x + 6, r.position.y + 10), FlightHUD.fmt_speed(v1), HORIZONTAL_ALIGNMENT_LEFT, 74, fs, speed_color)
	draw_string(font, Vector2(r.end.x - 60, r.end.y + 16), "T+" + FlightHUD.fmt_time(t1), HORIZONTAL_ALIGNMENT_RIGHT, 60, fs, text_color)
	draw_string(font, Vector2(r.position.x, r.end.y + 16), "T+00:00", HORIZONTAL_ALIGNMENT_LEFT, 60, fs, text_color)


static func _nice(v: float) -> float:
	var e := pow(10.0, floor(log(v) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if v <= m * e:
			return m * e
	return v
