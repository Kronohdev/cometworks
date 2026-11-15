class_name SurfaceFreePlay
extends RefCounted
## Opens a planet surface for free play, from the main menu or from the campus.
## With the rover side present (SurfaceSession.DRIVE_SCENE, src/rover/), the player drives the
## sandbox rover of that body (RoverMissions.sandbox_design / sandbox_objectives) in the drive
## scene; without it, the body's own scene opens with its fly camera as a little drone. Either
## way the body's Explore layer (SurfaceExplore) runs the places, finds, challenges and log.
##   main menu  open_from_menu(): the drive scene (or the body scene) replaces the menu; "Voltar
##              à Terra" / Esc lead back to the menu
##   campus     open_in_campus(): TycoonModes.open_surface() when it exists, else the campus
##              viewer (scenes/surface/explore/surface_viewer.tscn) over the sleeping campus

const ROVER_MISSIONS := "res://src/rover/rover_missions.gd"
const VIEWER := "res://scenes/surface/explore/surface_viewer.tscn"


## The rover side is in the build (the drive scene exists).
static func has_rover() -> bool:
	return ResourceLoader.exists(SurfaceSession.DRIVE_SCENE)


## The scene free play opens for `body`: the drive scene (rover) or the body's surface (drone).
static func scene_path(body: StringName) -> String:
	if has_rover():
		return SurfaceSession.DRIVE_SCENE
	return String(SurfaceSession.SURFACES.get(body, SurfaceSession.SURFACES[&"moon"]))


## A sandbox SurfaceSession for `body` with the rover side's sandbox rover and objectives (empty
## without the rover side). ctx: {"return": "menu" | "tycoon", ...}; "sandbox" and "free_play" are set.
static func make_session(body: StringName, ctx := {}) -> SurfaceSession:
	var design: Dictionary = {}
	var objectives: Array = []
	if ResourceLoader.exists(ROVER_MISSIONS):
		var rm: Script = load(ROVER_MISSIONS)
		if _has_static(rm, "sandbox_design"):
			design = rm.call("sandbox_design", body)
		if _has_static(rm, "sandbox_objectives"):
			objectives = rm.call("sandbox_objectives", body)
	var c := (ctx as Dictionary).duplicate()
	c["sandbox"] = true
	c["free_play"] = true
	return SurfaceSession.start(body, design, objectives, c)


static func _has_static(s: Script, method: String) -> bool:
	if s == null:
		return false
	for m: Dictionary in s.get_script_method_list():
		if String(m.get("name", "")) == method:
			return true
	return false


## Main menu: starts the session (rover) and returns the scene to change to.
static func prepare_from_menu(body: StringName) -> String:
	if has_rover():
		make_session(body, {"return": "menu"})
	else:
		SurfaceSession.current = null
	return scene_path(body)


## Campus: a rover drive inside TycoonModes when it can, else the campus viewer (drone).
## Returns the node that shows the surface (the viewer) or the modes node.
static func open_in_campus(main: Node, body: StringName) -> Node:
	var modes: Node = main.get_node_or_null("Modes")
	if has_rover() and modes and modes.has_method("open_surface"):
		var s := make_session(body, {"return": "tycoon"})
		if bool(modes.call("open_surface", s, Callable())):
			return modes
	SurfaceSession.current = null
	var v := (load(VIEWER) as PackedScene).instantiate()
	main.add_child(v)
	v.call("open", main, body)
	return v
