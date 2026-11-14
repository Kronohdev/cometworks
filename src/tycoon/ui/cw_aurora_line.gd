@tool
class_name CwAuroraLine
extends Control
## The aurora thread (GDD section 22.3): a thin teal -> violet -> ignition line, with a faint
## glint that drifts along it every few seconds so the instrument feels alive without ever
## becoming a "glow". Size it as a 2 px tall Control (or use `vertical` for a 2 px wide one).
## sweep() runs a brighter glint once (e.g. when a week ticks or a panel opens).

## seconds between glints (0 = no idle glint)
@export_range(0.0, 60.0, 0.5) var glint_period := 7.0
## how long a glint takes to cross the line
@export_range(0.2, 10.0, 0.1) var glint_seconds := 2.4
## glint strength (added whiteness at its peak)
@export_range(0.0, 1.0, 0.01) var glint_strength := 0.45
## glint width as a fraction of the line
@export_range(0.02, 0.6, 0.01) var glint_width := 0.12
## overall opacity
@export_range(0.0, 1.0, 0.01) var intensity := 1.0:
	set(v):
		intensity = v
		queue_redraw()
@export var vertical := false:
	set(v):
		vertical = v
		queue_redraw()
## segments of the gradient (more = smoother)
@export_range(4, 128, 1) var steps := 48

var _t := 0.0
var _sweep := -1.0     # position of a requested glint (0..1 travel), < 0 = none


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t = randf() * glint_period


func sweep() -> void:
	_sweep = 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if _sweep >= 0.0:
		_sweep += delta / glint_seconds
		if _sweep > 1.3:
			_sweep = -1.0
	queue_redraw()


## Where the glint is along the line (-1 = none) and its strength.
func _glint() -> Vector2:
	if _sweep >= 0.0:
		return Vector2(_sweep * 1.3 - 0.15, minf(1.0, glint_strength * 1.6))
	if glint_period <= 0.0 or Engine.is_editor_hint() and not is_inside_tree():
		return Vector2(-1.0, 0.0)
	var cycle := fmod(_t, glint_period) / glint_seconds
	if cycle > 1.3:
		return Vector2(-1.0, 0.0)
	return Vector2(cycle * 1.3 - 0.15, glint_strength)


func _draw() -> void:
	var length := size.y if vertical else size.x
	var thick := size.x if vertical else size.y
	if length <= 0.0 or thick <= 0.0:
		return
	var g := _glint()
	var n := steps
	for k in n:
		var u := (float(k) + 0.5) / n
		var c := CwPalette.aurora_at(u)
		if g.x > -0.5:
			var d := absf(u - g.x) / glint_width
			if d < 1.0:
				var w := (1.0 - d * d) * g.y
				c = c.lerp(Color.WHITE, w * 0.6)
		c.a = intensity
		var a := length * float(k) / n
		var b := length * float(k + 1) / n
		var r := Rect2(0.0, a, thick, b - a + 0.5) if vertical else Rect2(a, 0.0, b - a + 0.5, thick)
		draw_rect(r, c)


func _get_minimum_size() -> Vector2:
	return Vector2(2, 0) if vertical else Vector2(0, 2)
