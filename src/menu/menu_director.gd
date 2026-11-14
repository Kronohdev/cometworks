class_name MenuDirector
extends Node3D
## Background of the main menu (scenes/menu/main_menu.tscn > Background): plays the shot
## scenes in `shots` one after another, dipping through the night colour between them.
## Shots load lazily: the first one when the menu opens, each next one on a background
## thread while the current one plays, and a shot is freed as soon as it ends (one 3D world
## alive at a time).

signal shot_started(shot: MenuShot, index: int)

@export_file("*.tscn") var shots: PackedStringArray = []
## Full-screen overlay (in the UI) faded in and out between shots.
@export var fade: CanvasItem
@export var dip_out := 0.6
@export var dip_in := 0.9
@export var autostart := true
@export var start_index := 0

var current: MenuShot
var index := -1
var _busy := false
var _requested: Dictionary = {}   # path -> true while a threaded load is pending


func _ready() -> void:
	if autostart and not shots.is_empty():
		show_shot(start_index, false)


## Cuts to shot i (dipping to night first when `dip` is true).
func show_shot(i: int, dip := true) -> void:
	if shots.is_empty() or _busy:
		return
	_busy = true
	if dip and current and fade:
		var tw := create_tween()
		tw.tween_property(fade, "modulate:a", 1.0, dip_out).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await tw.finished
	elif fade:
		fade.modulate.a = 1.0
	index = posmod(i, shots.size())
	var ps := _take(shots[index])
	if current:
		remove_child(current)
		current.free()
		current = null
	if ps:
		current = ps.instantiate() as MenuShot
	if current:
		add_child(current)
		current.finished.connect(next)
		current.begin()
		shot_started.emit(current, index)
	_request(shots[posmod(index + 1, shots.size())])
	if fade:
		var tw := create_tween()
		tw.tween_property(fade, "modulate:a", 0.0, dip_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_busy = false


func next() -> void:
	show_shot(index + 1)


func _request(path: String) -> void:
	if _requested.has(path) or ResourceLoader.has_cached(path):
		return
	# one loader thread: sub-threads crashed Godot 4.6 now and then while the shots changed
	if ResourceLoader.load_threaded_request(path, "PackedScene", false) == OK:
		_requested[path] = true


func _take(path: String) -> PackedScene:
	if _requested.has(path):
		_requested.erase(path)
		var ps := ResourceLoader.load_threaded_get(path) as PackedScene
		if ps:
			return ps
	return load(path) as PackedScene
