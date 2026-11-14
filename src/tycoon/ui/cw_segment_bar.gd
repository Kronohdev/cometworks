@tool
class_name CwSegmentBar
extends Control
## Segmented LED meter (GDD section 22.4): `segments` cells, the first value*segments lit in
## `color`, the rest in the track colour. An optional engraved marker shows an ideal value.
## Lit cells carry a 1 px highlight and the leading cell burns a little brighter; when `value`
## changes the cells light up (or go out) one after another (GDD 22.6), at `cells_per_second`.

@export_range(0.0, 1.0) var value := 0.5:
	set(v):
		value = clampf(v, 0.0, 1.0)
		if not animate or not is_inside_tree() or Engine.is_editor_hint():
			_shown = value
		set_process(not is_equal_approx(_shown, value))
		queue_redraw()
@export var color := Color("#ff8a3d"):
	set(v):
		color = v
		queue_redraw()
@export var track_color := Color("#24324d"):
	set(v):
		track_color = v
		queue_redraw()
@export_range(2, 60) var segments := 15:
	set(v):
		segments = v
		queue_redraw()
@export var gap := 2.0:
	set(v):
		gap = v
		queue_redraw()
## ideal value marker (engraved tick); < 0 = none
@export_range(-1.0, 1.0) var marker := -1.0:
	set(v):
		marker = v
		queue_redraw()
## light the cells one after another when the value changes
@export var animate := true
@export_range(1.0, 200.0, 1.0) var cells_per_second := 40.0
## brighter top edge on lit cells (alpha 0 = flat)
@export var highlight := Color(1, 1, 1, 0.22):
	set(v):
		highlight = v
		queue_redraw()

var _shown := 0.5


func _ready() -> void:
	_shown = value
	set_process(false)


func _process(delta: float) -> void:
	var step := cells_per_second * delta / float(maxi(segments, 1))
	_shown = move_toward(_shown, value, step)
	if is_equal_approx(_shown, value):
		_shown = value
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var w := (size.x - gap * (segments - 1)) / segments
	if w <= 0.0:
		return
	var lit := _shown * segments
	var lead := int(ceil(lit)) - 1
	for i in segments:
		var x := i * (w + gap)
		var c := track_color
		var on := 0.0
		if float(i) + 1.0 <= lit:
			on = 1.0
		elif float(i) < lit:
			on = lit - float(i)
		if on > 0.0:
			c = track_color.lerp(color, on)
			if i == lead and lit < float(segments):
				c = c.lerp(Color.WHITE, 0.18 * on)
		draw_rect(Rect2(x, 0.0, w, size.y), c)
		if on > 0.0 and highlight.a > 0.0 and size.y > 3.0:
			draw_rect(Rect2(x, 0.0, w, 1.0), Color(highlight, highlight.a * on))
	if marker >= 0.0:
		var mx := marker * size.x
		draw_line(Vector2(mx, -3.0), Vector2(mx, size.y + 3.0), CwPalette.TEXT, 1.0)


func _get_minimum_size() -> Vector2:
	return Vector2(segments * 3.0, 4.0)
