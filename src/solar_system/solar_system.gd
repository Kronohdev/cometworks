class_name SolarSystem
extends Node
## The standalone Solar System (main menu > Sistema Solar; scenes/solar_system/solar_system.tscn):
## the very map the campus' Solar System map shows (the flight scene in its map-only mode,
## FlightMap on the real ephemeris: exact orbits, the bodies on their real axes, the asteroid
## belt, the comet and its tails), here on its own with today's date running, plus the panels of
## scenes/solar_system/solar_system_overlay.tscn (date and speed, the bodies, a body's card).
## Both live in the scene; this only wires them and leaves for the main menu.

const MENU := "res://scenes/menu/main_menu.tscn"

## leave for the main menu on Esc / Back (off in tests and screenshots)
@export var leave_to_menu := true

var _leaving := false

@onready var world: FlightWorld = $Flight
@onready var overlay: SolarSystemOverlay = %Overlay


func _ready() -> void:
	var lang := OS.get_locale_language()
	if not TranslationServer.get_locale().begins_with("pt") and not TranslationServer.get_locale().begins_with("en"):
		TranslationServer.set_locale("pt" if lang == "pt" else "en")
	world.exit_requested.connect(func(_what: String, _report: Dictionary) -> void: leave())
	overlay.leave_requested.connect(leave)
	overlay.bind(world)


func leave() -> void:
	if _leaving or not leave_to_menu:
		return
	_leaving = true
	get_tree().change_scene_to_file.call_deferred(MENU)


# ------------------------------------------------------------ for tests and screenshots
func focus_body(id: String) -> void:
	overlay.focus_body(id)


func show_info(id: String) -> void:
	overlay.show_info(id)


func refresh_texts() -> void:
	overlay.show_info(overlay.selected)


func _on_pause_toggled(on: bool) -> void:
	overlay.set_speed(0 if on else 2)
