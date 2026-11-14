@tool
class_name CwSegmentBar
extends Control
## Candy meter: `segments` little rounded beads, the first value*segments filled in `color`, the
## rest in the (paper-well) track colour. An optional ink marker shows an ideal value. Filled
## beads carry a soft highlight and the leading one glows a little; when `value` changes the beads
## fill (or empty) one after another, at `cells_per_second`. `pill` draws one rounded gauge
## instead (a well track, a glossy candy fill and faint notches at the segment boundaries).

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
@export var track_color := Color("#efe2cb"):
	set(v):
		track_color = v
		queue_redraw()
## how much the unlit track takes on the bar colour (0 = plain track colour)
@export_range(0.0, 1.0, 0.01) var track_tint := 0.0:
	set(v):
		track_tint = v
		queue_redraw()
## pill only: faint ticks at the segment (milestone) boundaries
@export var pill_ticks := false:
	set(v):
		pill_ticks = v
		queue_redraw()
## one rounded gauge instead of separate cells
@export var pill := false:
	set(v):
		pill = v
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
@export var highlight := Color(1, 1, 1, 0.45):
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
	if pill:
		_draw_pill()
		return
	var w := (size.x - gap * (segments - 1)) / segments
	if w <= 0.0:
		return
	var lit := _shown * segments
	var lead := int(ceil(lit)) - 1
	var rad := int(minf(w, size.y) * 0.5)
	_box.anti_aliasing = true
	_box.set_corner_radius_all(rad)
	for i in segments:
		var x := i * (w + gap)
		var c := track_color.lerp(color, track_tint)
		var on := 0.0
		if float(i) + 1.0 <= lit:
			on = 1.0
		elif float(i) < lit:
			on = lit - float(i)
		if on > 0.0:
			c = track_color.lerp(color, maxf(on, track_tint))
			if i == lead and lit < float(segments):
				c = c.lerp(Color.WHITE, 0.2 * on)
		_box.bg_color = c
		draw_style_box(_box, Rect2(x, 0.0, w, size.y))
		if on > 0.0 and highlight.a > 0.0 and size.y > 5.0 and w > 4.0:
			draw_line(Vector2(x + minf(rad, w * 0.3), 1.5), Vector2(x + w - minf(rad, w * 0.3), 1.5),
				Color(highlight, highlight.a * on), 1.0, true)
	if marker >= 0.0:
		_draw_marker()


func _draw_pill() -> void:
	var r := size.y * 0.5
	var track := track_color.lerp(color, track_tint)
	_box.set_corner_radius_all(int(ceil(r)))
	_box.anti_aliasing = true
	_box.bg_color = track
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var w := size.x * _shown
	if w > 0.5:
		var fw := maxf(w, size.y)
		_box.bg_color = color
		draw_style_box(_box, Rect2(0.0, 0.0, fw, size.y))
		if highlight.a > 0.0 and size.y > 5.0:
			draw_line(Vector2(r, size.y * 0.3), Vector2(maxf(r, fw - r), size.y * 0.3), highlight,
				maxf(1.0, size.y * 0.18), true)
		if _shown < 1.0 and size.y > 6.0:
			# the leading end glows a little
			draw_circle(Vector2(fw - r, r), r * 0.45, color.lerp(Color.WHITE, 0.6), true, -1.0, true)
	# faint notches at the segment (milestone) boundaries
	if pill_ticks and segments > 1 and segments <= 30:
		var tick := Color(1, 1, 1, 0.7)
		for i in range(1, segments):
			var x := roundf(size.x * float(i) / segments) + 0.5
			draw_line(Vector2(x, 2.0), Vector2(x, size.y - 2.0), tick, 1.5)
	if marker >= 0.0:
		_draw_marker()


## The ideal value: a little ink pin through the bar.
func _draw_marker() -> void:
	var mx := marker * size.x
	var ink := Color("#2b2a5c")
	draw_line(Vector2(mx, -4.0), Vector2(mx, size.y + 4.0), ink, 2.0, true)
	draw_circle(Vector2(mx, -4.0), 2.5, ink, true, -1.0, true)


var _box := StyleBoxFlat.new()


func _get_minimum_size() -> Vector2:
	return Vector2(segments * 3.0, 4.0)
