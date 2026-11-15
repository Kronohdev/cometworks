class_name RoverDrive
extends Node
## The rover on a planet surface (scenes/surface/rover_drive.tscn): reads SurfaceSession.current
## (or makes a sandbox one for `default_body`), instances the world side's surface scene for the
## body (SurfaceSession.surface_scene_path), turns off the cameras it brings, puts the rover on its
## spawn (group "surface_spawn", else the PlanetSurface's LandingSite), binds every
## SurfaceInteractable, adds a marker (scenes/rover/objective_marker.tscn) for each objective the
## world has no point of interest for, and runs the chase camera and the HUD.
## Esc opens the pause card; "Voltar à Terra" finishes the session: embedded (inside TycoonModes)
## it emits exit_requested(result), standalone it goes back to `return_scene`.

signal exit_requested(result: Dictionary)

const MARKER := "res://scenes/rover/objective_marker.tscn"
const POLE_SUN_ELEVATION := 5.0

## the body of the sandbox session when nothing started one
@export var default_body: StringName = &"moon"
## standalone: the scene "Voltar à Terra" opens ("" = quit)
@export var return_scene := "res://scenes/menu/main_menu.tscn"
## inside TycoonModes: report instead of changing scenes
@export var embedded := false

@onready var world: Node3D = $World
@onready var rover: RoverController = $Rover
@onready var cam: RoverCamera = $ChaseCamera
@onready var hud: RoverHUD = $HUD

var session: SurfaceSession
var surface: Node
var planet: PlanetSurface
var markers: Array[Node] = []
var _poi_timer := 0.0


func _ready() -> void:
	session = SurfaceSession.current
	if session == null:
		var body := default_body
		session = SurfaceSession.start(body, RoverMissions.sandbox_design(body), RoverMissions.sandbox_objectives(body),
			{"return": "dev", "sandbox": true})
	_load_surface()
	_place_rover()
	_spawn_markers()
	cam.target = rover
	cam.current = true
	cam.snap()
	rover.refresh_interactables()
	hud.bind(rover, session, planet.profile if planet else null)
	hud.leave_requested.connect(leave)
	hud.paused_changed.connect(func(on: bool) -> void: rover.set_physics_process(not on))


func _load_surface() -> void:
	var path := session.surface_scene_path()
	surface = (load(path) as PackedScene).instantiate()
	world.add_child(surface)
	planet = surface as PlanetSurface
	if planet == null:
		for n in surface.find_children("*", "PlanetSurface", true, false):
			planet = n as PlanetSurface
			break
	# the world's own cameras (its fly camera) step aside for the chase camera
	for c in surface.find_children("*", "Camera3D", true, false):
		if not c.is_in_group(SurfaceSession.KEEP_CAMERA_GROUP):
			(c as Camera3D).current = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
	if planet:
		planet.set_focus(rover)


## Sunlight on the panels: the body's sunlight x how high the Sun stands (the lunar pole: low).
func sun_factor() -> float:
	var b := RoverDesign.body(String(session.body))
	var elev := planet.profile.sun_elevation_deg if planet and planet.profile else 30.0
	if bool(session.context.get("pole", false)):
		elev = POLE_SUN_ELEVATION
	return float(b.get("sun", 1.0)) * clampf(0.3 + 0.7 * sin(deg_to_rad(elev)), 0.05, 1.0)


func _place_rover() -> void:
	var prof := planet.profile if planet else null
	var g := prof.gravity if prof else 1.62
	var air := bool(RoverDesign.body(String(session.body)).get("air", false))
	var heights := Callable()
	if planet:
		heights = planet.terrain.get_height
	rover.setup(session.rover, String(session.body), g, sun_factor(), heights, air)
	var spawn := spawn_point()
	rover.place(spawn.x, spawn.z, 0.0)


func spawn_point() -> Vector3:
	for n in get_tree().get_nodes_in_group(SurfaceSession.SPAWN_GROUP):
		if n is Node3D:
			return (n as Node3D).global_position
	if planet:
		return planet.landing_site.global_position
	return Vector3.ZERO


## A marker for every objective that needs a point of interest the world does not have.
func _spawn_markers() -> void:
	var existing := get_tree().get_nodes_in_group(SurfaceSession.GROUP)
	var ps := load(MARKER) as PackedScene
	var origin := spawn_point()
	var i := 0
	for o in session.objectives:
		i += 1
		var pk := String(o.get("poi_kind", ""))
		var poi := String(o.get("poi", ""))
		if pk == "" and poi == "":
			continue
		var found := false
		for n in existing:
			if (poi != "" and String(n.get("objective_id")) == poi) or (poi == "" and String(n.get("kind")) == pk):
				found = true
				break
		if found:
			continue
		var m := ps.instantiate() as SurfaceInteractable
		m.kind = StringName(pk if pk != "" else "objective")
		m.objective_id = StringName(poi if poi != "" else String(o["id"]))
		m.interact_id = StringName("marker_%s" % String(o["id"]))
		m.name_key = "RV_POI_" + m.kind.to_upper()
		# the marker answers its objective's action (a place to reach still makes a nice photo)
		var act := String(o["kind"])
		m.actions = PackedStringArray(["photo"] if act == "reach" else ([act, "photo"] if act != "photo" else ["photo"]))
		var off: Array = o.get("offset", [])
		var dx := float(off[0]) if off.size() > 1 else cos(i * 2.1) * (50.0 + 15.0 * i)
		var dz := float(off[1]) if off.size() > 1 else sin(i * 2.1) * (50.0 + 15.0 * i)
		var x := origin.x + dx
		var z := origin.z + dz
		world.add_child(m)
		m.global_position = Vector3(x, rover.ground(x, z), z)
		markers.append(m)
		existing.append(m)


func _process(delta: float) -> void:
	_poi_timer -= delta
	if _poi_timer <= 0.0:
		_poi_timer = 1.0
		var before := rover.interactables.size()
		rover.refresh_interactables()
		if rover.interactables.size() != before:
			hud.refresh_markers()


## "Voltar à Terra": the session ends with what the rover did.
func leave() -> void:
	rover.flush_replies()
	session.distance = rover.distance
	var result := session.finish()
	if embedded:
		exit_requested.emit(result)
		return
	var back := return_scene
	if back != "" and ResourceLoader.exists(back):
		get_tree().change_scene_to_file(back)
	else:
		get_tree().quit()
