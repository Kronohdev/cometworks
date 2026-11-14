@tool
class_name CwTechLinks
extends Control
## Connection lines of the tech tree (scenes/tycoon/ui/screens/research.tscn): a soft S-curve
## from the right edge of each prerequisite to the left edge of the tech that needs it.
## States: "done" (both done: engraved teal), "open" (prerequisite done, tech not yet: hairline),
## "active" (into the research being funded: the aurora thread), "locked" (dim, dotted).
## The screen fills `links` = [{"a": Rect2, "b": Rect2, "state", "ya", "yb" (socket offsets
## along the node edges, so parallel lines stay apart)}] in this control's space.

@export var done_color := Color(0.1843, 0.6431, 0.5255, 0.9):
	set(v):
		done_color = v
		queue_redraw()
@export var open_color := Color("#8c89b3"):
	set(v):
		open_color = v
		queue_redraw()
@export var locked_color := Color("#ddcfb6"):
	set(v):
		locked_color = v
		queue_redraw()
@export var width := 2.5:
	set(v):
		width = v
		queue_redraw()

var links: Array = []:
	set(v):
		links = v
		queue_redraw()


func _curve(a: Vector2, b: Vector2, n := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var dx := maxf((b.x - a.x) * 0.5, 18.0)
	var c1 := a + Vector2(dx, 0)
	var c2 := b - Vector2(dx, 0)
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		pts.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	return pts


func _draw() -> void:
	# locked first, the aurora thread last (on top)
	for pass_state: String in ["locked", "open", "done", "active"]:
		for l: Dictionary in links:
			if String(l.get("state", "")) != pass_state:
				continue
			var ra: Rect2 = l["a"]
			var rb: Rect2 = l["b"]
			var a := Vector2(ra.end.x, ra.get_center().y + float(l.get("ya", 0.0)))
			var b := Vector2(rb.position.x, rb.get_center().y + float(l.get("yb", 0.0)))
			var pts := _curve(a, b)
			match pass_state:
				"locked":
					for i in range(0, pts.size() - 1, 2):
						draw_line(pts[i], pts[i + 1], locked_color, 1.0, true)
				"open":
					draw_polyline(pts, open_color, width, true)
				"done":
					draw_polyline(pts, done_color, width, true)
				"active":
					for i in pts.size() - 1:
						draw_line(pts[i], pts[i + 1], CwPalette.aurora_at(float(i) / (pts.size() - 1)), 2.0, true)
			# a small engraved socket where the line meets each node
			var sc := done_color if pass_state == "done" else (CwPalette.IGNITION if pass_state == "active" else open_color)
			if pass_state != "locked":
				draw_rect(Rect2(a - Vector2(0, 2), Vector2(3, 4)), sc)
				draw_rect(Rect2(b - Vector2(3, 2), Vector2(3, 4)), sc)
