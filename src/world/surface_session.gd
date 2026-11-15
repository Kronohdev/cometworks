class_name SurfaceSession
extends RefCounted
## The contract between the rover side (vehicle, controller, chase camera, HUD, mission hooks:
## src/rover/) and the surface world side (terrain, points of interest, collectibles:
## scenes/surface/*_surface.tscn). One session = one rover on one body with a list of
## objectives; pure data (no scene access), so it runs headless.
##
## Starting a surface:
##   var s := SurfaceSession.start(&"moon", design_dict, objectives, {"mission_id": "ROV-01"})
##   get_tree().change_scene_to_file(SurfaceSession.DRIVE_SCENE)   # or TycoonModes.open_surface()
## The drive scene (scenes/surface/rover_drive.tscn, RoverDrive) reads SurfaceSession.current,
## instances surface_scene_path() (the world side's scene for the body), disables the cameras it
## brings (except those in group "surface_keep_camera"), puts the rover on the node in group
## "surface_spawn" (else the PlanetSurface's LandingSite) and binds every node in GROUP.
##
## Objectives: Dictionaries, {"id": StringName, "kind": action the rover must do there
## ("reach" | "photo" | "panorama" | "drill" | "scan" | "drone" | "sample" | "weather" | "drive"),
## "label_key": i18n key shown on the HUD, "poi_kind": the SurfaceInteractable.kind that answers
## it ("" = anywhere, e.g. a panorama or a drive), "poi": an exact SurfaceInteractable.objective_id
## (optional), "science": points when done, "amount": metres for "drive" / shots for "panorama",
## "offset": [x, z] metres from the landing site where the rover side puts a fallback marker when
## the world has no matching interactable, "need": rover tool id the objective needs ("drill"...)}.
## The session fills "done" (bool).
##
## World side (POIs): extend SurfaceInteractable (src/world/surface_interactable.gd), set its
## `kind` / `objective_id`, and either call `SurfaceSession.current.report_objective(id)` yourself
## or just let SurfaceInteractable.interact() do it (it asks objective_for()).

## an objective became done (also emitted by SurfaceInteractable for its own listeners)
signal objective_reached(id: StringName)
## science points credited on the surface (source: an interactable id, an objective id, an action)
signal science_gained(amount: float, source: StringName)
## a rover action happened ({"action", "ok", "message_key", "science", "objective"})
signal action_done(action: StringName, result: Dictionary)
## the player left the surface: result() of the session
signal finished(result: Dictionary)

const GROUP := &"surface_interactable"
const SPAWN_GROUP := &"surface_spawn"
const KEEP_CAMERA_GROUP := &"surface_keep_camera"
const DRIVE_SCENE := "res://scenes/surface/rover_drive.tscn"
const ACTIONS: Array[StringName] = [&"reach", &"photo", &"panorama", &"drill", &"scan", &"drone", &"sample",
	&"weather", &"drive"]
## body id -> the world side's scene of that surface
const SURFACES := {
	&"earth": "res://scenes/surface/earth_surface.tscn",
	&"moon": "res://scenes/surface/moon_surface.tscn",
	&"mars": "res://scenes/surface/mars_surface.tscn",
	&"mercury": "res://scenes/surface/mercury_surface.tscn",
	&"europa": "res://scenes/surface/europa_surface.tscn",
	&"titan": "res://scenes/surface/titan_surface.tscn",
}
## campaign target -> surface body
const TARGET_BODIES := {"lunar_surface": &"moon", "lunar_pole": &"moon", "mars_surface": &"mars"}

## the session the drive scene picks up (null when none)
static var current: SurfaceSession = null
## the result of the last finished session (the tycoon reads it when the surface closes)
static var last_result: Dictionary = {}

var body: StringName = &"moon"
## the rover design (RoverDesign.to_dict(): {"name", "chassis", "parts": [...]})
var rover: Dictionary = {}
var objectives: Array[Dictionary] = []
## {"mission_id", "project_id", "code", "target", "return": "tycoon" | "dev" | "menu", "pole": bool}
var context: Dictionary = {}
var science := 0.0
var distance := 0.0
var photos := 0
var samples := 0
var events: Array[Dictionary] = []
var ended := false
## interactable id + action -> true (credited once)
var _credited := {}


## Makes and registers the session the drive scene will use.
static func start(body_id: StringName, rover_design: Dictionary, objective_list: Array, ctx := {}) -> SurfaceSession:
	var s := SurfaceSession.new()
	s.body = body_id if SURFACES.has(body_id) else &"moon"
	s.rover = rover_design.duplicate(true)
	for o in objective_list:
		var od := (o as Dictionary).duplicate(true)
		od["id"] = StringName(od.get("id", "obj%d" % s.objectives.size()))
		od["kind"] = StringName(od.get("kind", "reach"))
		od["done"] = bool(od.get("done", false))
		s.objectives.append(od)
	s.context = (ctx as Dictionary).duplicate(true)
	current = s
	return s


static func body_for_target(target_id: String) -> StringName:
	return TARGET_BODIES.get(target_id, &"")


func surface_scene_path() -> String:
	return String(SURFACES.get(body, SURFACES[&"moon"]))


func objective(id: StringName) -> Dictionary:
	for o in objectives:
		if o["id"] == id:
			return o
	return {}


## The first open objective an interactable answers with this action ({} if none).
## Matches by poi == node.objective_id, else poi_kind == node.kind; "reach" objectives
## answer the "reach" action only.
func objective_for(node: Node, action: StringName) -> Dictionary:
	var oid := StringName(node.get("objective_id")) if node else &""
	var nkind := StringName(node.get("kind")) if node else &""
	for o in objectives:
		if o["done"] or o["kind"] != action:
			continue
		var poi := StringName(o.get("poi", ""))
		var pk := StringName(o.get("poi_kind", ""))
		if (poi != &"" and poi == oid) or (oid != &"" and o["id"] == oid) or (poi == &"" and pk != &"" and pk == nkind):
			return o
	return {}


## Open objectives that need no interactable (a panorama anywhere, a drive, the weather).
func free_objective(action: StringName) -> Dictionary:
	for o in objectives:
		if not o["done"] and o["kind"] == action and String(o.get("poi_kind", "")) == "" and String(o.get("poi", "")) == "":
			return o
	return {}


## Marks an objective done (its science credited once). False if unknown or already done.
func report_objective(id: StringName, info := {}) -> bool:
	var o := objective(id)
	if o.is_empty() or o["done"] or ended:
		return false
	o["done"] = true
	events.append({"what": "objective", "id": String(id), "info": info})
	add_science(float(o.get("science", 0.0)), id)
	objective_reached.emit(id)
	return true


## Science once per (source, action); returns what was credited.
func credit_once(source: StringName, action: StringName, amount: float) -> float:
	var k := "%s|%s" % [source, action]
	if _credited.has(k) or amount <= 0.0:
		return 0.0
	_credited[k] = true
	add_science(amount, source)
	return amount


func add_science(amount: float, source: StringName = &"") -> void:
	if amount <= 0.0 or ended:
		return
	science += amount
	science_gained.emit(amount, source)


func note_action(action: StringName, res: Dictionary) -> void:
	if action == &"photo" or action == &"panorama":
		photos += 1
	elif action == &"sample" or action == &"drill":
		samples += 1 if bool(res.get("ok", false)) else 0
	action_done.emit(action, res)


func done_ids() -> Array[String]:
	var out: Array[String] = []
	for o in objectives:
		if o["done"]:
			out.append(String(o["id"]))
	return out


func done_count() -> int:
	return done_ids().size()


func is_complete() -> bool:
	return not objectives.is_empty() and done_count() == objectives.size()


## {"body", "rover", "context", "objectives_done": [ids], "objectives_total", "science",
##  "distance", "photos", "samples", "complete", "driven": true}
func result() -> Dictionary:
	return {"body": String(body), "rover": String(rover.get("name", "")), "context": context.duplicate(true),
		"objectives_done": done_ids(), "objectives_total": objectives.size(), "science": science,
		"distance": distance, "photos": photos, "samples": samples, "complete": is_complete(), "driven": true}


## Ends the session (the player leaves the surface): emits finished, stores last_result.
func finish() -> Dictionary:
	var r := result()
	if not ended:
		ended = true
		last_result = r
		finished.emit(r)
	if current == self:
		current = null
	return r
