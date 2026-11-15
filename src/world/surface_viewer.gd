class_name SurfaceViewer
extends CanvasLayer
## The campus' window onto a planet surface when the rover side is not there
## (scenes/surface/explore/surface_viewer.tscn, SurfaceFreePlay.open_in_campus): the body's
## surface scene runs in its own 3D world inside %Port while the campus sleeps (hidden, its
## processing off, the clock held, its HUD hidden), the way TycoonModes shows the hangar. The
## surface's Explore layer calls surface_leave() (Esc / Voltar) and the campus comes back.

signal closed

var main: Node
var surface: PlanetSurface
var _held_speed := 0
var _hidden: Array[Node] = []

@onready var port: SubViewport = %Port


func open(p_main: Node, body: StringName) -> void:
	main = p_main
	var clock: Variant = main.get("clock")
	if clock and int(clock.get("speed")) > 0:
		_held_speed = int(clock.get("speed"))
		clock.call("set_speed", 0)
	for n in [main.get_node_or_null("Campus"), main.get_node_or_null("Audio"), main.get_node_or_null("DayCycle"),
			main.get_node_or_null("Effects"), main.get_node_or_null("Camera")]:
		if n:
			_hidden.append(n)
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var campus := main.get_node_or_null("Campus") as Node3D
	if campus:
		campus.visible = false
	var ui := main.get_node_or_null("UI") as CanvasLayer
	if ui:
		ui.visible = false
	main.get_viewport().disable_3d = true
	var path := String(SurfaceSession.SURFACES.get(body, SurfaceSession.SURFACES[&"moon"]))
	surface = (load(path) as PackedScene).instantiate() as PlanetSurface
	port.add_child(surface)
	visible = true


## The Explore layer's way back (Esc / Voltar).
func surface_leave() -> void:
	close()


func close() -> void:
	if surface and is_instance_valid(surface):
		surface.process_mode = Node.PROCESS_MODE_DISABLED
		surface.queue_free()
	surface = null
	for n in _hidden:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT
	_hidden.clear()
	if main and is_instance_valid(main):
		var campus := main.get_node_or_null("Campus") as Node3D
		if campus:
			campus.visible = true
		var ui := main.get_node_or_null("UI") as CanvasLayer
		if ui:
			ui.visible = true
		main.get_viewport().disable_3d = false
		var clock: Variant = main.get("clock")
		if clock and _held_speed > 0:
			clock.call("set_speed", _held_speed)
	closed.emit()
	queue_free()


## Keys the surface did not take stay away from the campus underneath (pause, speeds, map...).
## (the SubViewportContainer below has already handed them to the surface in its own _input).
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()
