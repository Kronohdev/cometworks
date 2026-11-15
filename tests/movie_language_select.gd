extends SceneTree
## A scripted run of the language screen for a preview clip (Movie Maker): starts on Português,
## the mouse sweeps left to right so the Cometling runs to the US flag, comes back a little,
## returns and clicks English: the celebration, the labels switch to English, the fade and the
## first second of the main menu. A drawn pointer shows where the mouse is. The player's
## settings file is put back as it was at the end.
## Run (a window opens):
##   godot --path . --write-movie out.avi --fixed-fps 30 --resolution 1600x900 \
##     --script res://tests/movie_language_select.gd

const SCENE := "res://scenes/menu/language_select.tscn"
const SETTINGS := "user://settings.cfg"
## the drawn mouse pointer (an arrow, ink outline on cream)
const ARROW := [Vector2(0, 0), Vector2(0, 30), Vector2(8, 23), Vector2(14, 35), Vector2(20, 32), Vector2(14, 21),
	Vector2(24, 21)]
## [time (s), screen position] of the mouse; between keys it eases
const PATH := [
	[0.0, Vector2(380, 980)], [1.4, Vector2(380, 980)], [2.2, Vector2(470, 560)], [2.8, Vector2(560, 600)],
	[4.6, Vector2(1240, 560)], [5.6, Vector2(1290, 520)], [6.4, Vector2(760, 610)], [7.2, Vector2(700, 600)],
	[8.4, Vector2(1330, 470)], [9.2, Vector2(1330, 450)],
]
const CLICK_AT := 9.4
const LENGTH := 13.0

var _backup := ""
var _had := false
var _pointer: Node2D


func _initialize() -> void:
	_had = FileAccess.file_exists(SETTINGS)
	if _had:
		_backup = FileAccess.get_file_as_string(SETTINGS)
	MenuSettings.set_locale("pt")
	var scene := (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	_pointer = Node2D.new()
	_pointer.scale = Vector2.ONE * 1.1
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array(ARROW)
	fill.color = Color(1, 0.98, 0.93)
	var line := Line2D.new()
	line.points = PackedVector2Array(ARROW)
	line.closed = true
	line.width = 3.0
	line.default_color = Color(0.17, 0.165, 0.36)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	_pointer.add_child(fill)
	_pointer.add_child(line)
	layer.add_child(_pointer)
	_run()


func _run() -> void:
	var t := 0.0
	var clicked := false
	while t < LENGTH:
		await process_frame
		t += 1.0 / 30.0
		if t <= float(PATH[-1][0]):
			_move(_at(t))
		if not clicked and t >= CLICK_AT:
			clicked = true
			_click(_pointer.position)
	if _had:
		var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	quit()


func _at(t: float) -> Vector2:
	for i in range(1, PATH.size()):
		var a: Array = PATH[i - 1]
		var b: Array = PATH[i]
		if t <= float(b[0]):
			var u := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return (a[1] as Vector2).lerp(b[1], ease(u, -1.8))
	return PATH[-1][1]


func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = p - _pointer.position
	_pointer.position = p
	Input.parse_input_event(e)


func _click(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)
	_pointer.scale = Vector2.ONE * 0.85
	create_tween().tween_property(_pointer, "scale", Vector2.ONE * 1.1, 0.25)
