@tool
class_name OpsLinkOverlay
extends Control
## Radio links of the mission map, drawn over the 3D view: a dashed line from a mission to
## the ground station that sees it. When data is coming down the dashes travel toward the
## ground ("data reaching the ground", GDD section 7). Dash and width are exported.

@export var dash := 7.0
@export var gap := 6.0
@export var width := 1.5
@export var speed := 26.0
@export var idle_alpha := 0.35

## [{"from": Vector2 (mission), "to": Vector2 (station), "color": Color, "flowing": bool}]
var links: Array = []
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	for l: Dictionary in links:
		var a: Vector2 = l["from"]
		var b: Vector2 = l["to"]
		var col: Color = l.get("color", CwPalette.MINT)
		var flowing: bool = l.get("flowing", false)
		var length := a.distance_to(b)
		if length < 2.0:
			continue
		var dir := (b - a) / length
		var period := dash + gap
		var ofs := fmod(_t * speed, period) if flowing else 0.0
		var c := col if flowing else Color(col, col.a * idle_alpha)
		var s := -period + ofs
		while s < length:
			var s0 := maxf(s, 0.0)
			var s1 := minf(s + dash, length)
			if s1 > s0:
				draw_line(a + dir * s0, a + dir * s1, c, width, true)
			s += period
		if flowing:
			draw_circle(b, 2.5, col)
