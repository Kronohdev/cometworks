class_name SurfaceDemo
extends Node
## scenes/surface/surface_demo.tscn: fly over every planet surface, switch the
## profile from the HUD and watch streaming/LOD/meshing stats.
## F1 = LOD colors · F2 = hide HUD · L = language.

@export var profiles: Array[PlanetSurfaceProfile] = []
@export var start_index: int = 0
## Camera start offset from the landing site (m).
@export var spawn_offset: Vector3 = Vector3(-70.0, 38.0, 90.0)

@onready var planet: PlanetSurface = $PlanetSurface
@onready var camera: SurfaceFlyCamera = $FlyCamera
@onready var hud: SurfaceHUD = $HUD

var current_index := 0
var _stat_timer := 0.0
var _fps_frames := 0
var _fps_time := 0.0
var _fps := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0


func _ready() -> void:
	SurfaceHUD.ensure_translations()
	TranslationServer.set_locale("pt" if OS.get_locale_language() == "pt" else "en")
	planet.set_focus(camera)
	camera.set_terrain(planet.terrain)
	hud.planet_selected.connect(select_planet)
	hud.lod_view_toggled.connect(set_lod_view)
	hud.set_profiles(profiles, start_index)
	select_planet(start_index)


func select_planet(i: int) -> void:
	if profiles.is_empty():
		return
	current_index = clampi(i, 0, profiles.size() - 1)
	var p := profiles[current_index]
	planet.profile = p
	hud.show_profile(p, current_index)
	var site := planet.landing_site.global_position
	var ground := planet.ground_height(site.x, site.z)
	camera.global_position = Vector3(site.x + spawn_offset.x, ground + spawn_offset.y, site.z + spawn_offset.z)
	camera.look_toward(Vector3(site.x, ground + 4.0, site.z))
	_last_pos = camera.global_position


func set_lod_view(on: bool) -> void:
	var m := planet.terrain.material as ShaderMaterial
	if m:
		m.set_shader_parameter(&"debug_lod", on)
	hud.set_lod_view(on)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_F1:
				var m := planet.terrain.material as ShaderMaterial
				set_lod_view(not bool(m.get_shader_parameter(&"debug_lod")) if m else false)
			KEY_F2:
				hud.visible = not hud.visible
			KEY_L:
				TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("pt") else "pt")
			KEY_PAGEUP:
				select_planet((current_index + 1) % profiles.size())
			KEY_PAGEDOWN:
				select_planet((current_index + profiles.size() - 1) % profiles.size())


func _process(delta: float) -> void:
	_fps_frames += 1
	_fps_time += delta
	if delta > 0.0:
		_speed = lerpf(_speed, camera.global_position.distance_to(_last_pos) / delta, 0.1)
	_last_pos = camera.global_position
	_stat_timer += delta
	if _stat_timer < 0.25:
		return
	_fps = _fps_frames / maxf(_fps_time, 0.0001)
	_fps_frames = 0
	_fps_time = 0.0
	_stat_timer = 0.0
	hud.update_stats(collect_stats())


func collect_stats() -> Dictionary:
	var st := planet.terrain.get_stats()
	st["fps"] = _fps
	st["mem_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	st["vram_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var p := camera.global_position
	st["alt"] = p.y - planet.ground_height(p.x, p.z)
	st["speed"] = _speed
	return st
