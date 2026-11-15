@tool
class_name SurfaceTerrainFeature
extends Marker3D
## An authored landform placed in a surface scene (scenes/surface/*_surface.tscn, under the
## PlanetSurface's "Features" node): move it in the editor and the voxel terrain is rebuilt
## around it. Its x / z position and y rotation place it; the shape and its sizes are below.
## The PlanetSurface collects every feature (in tree order, FLAT ones level the ground for the
## ones after them) and hands them to VoxelTerrainGenerator.set_features().
##   CRATER  a named fresh crater: radius, depth, rim height; `material` = bright rim and rays
##   RILLE   a sinuous channel: length, width, depth, meander amplitude / wavelength
##   MESA    a flat-topped butte (layered by the profile's strata): radii, height
##   RIDGE   a wrinkle ridge (single) or a Europa double ridge with a dark central trough
##   MOUND   a round hill, optionally terraced (a layered mound)
##   CHAOS   Europa chaos terrain: tilted ice blocks in a darker matrix
##   RAMP    a wedge to jump from (challenges); `material` paints it
##   FLAT    levels a disc to the height at its centre (+ offset) for a set piece
##   DUNES   a field of dune rows (radius, wavelength, crest height); `material` = the sand

enum Shape { CRATER, RILLE, MESA, RIDGE, MOUND, CHAOS, RAMP, FLAT, DUNES }
## Palette material painted by the feature (see PlanetSurfaceProfile.Mat); NONE = the terrain's.
enum Paint { NONE = -1, SURFACE, SURFACE_ALT, SUBSURFACE, ROCK, ROCK_STRATA, SAND, ICE, ACCENT, SEABED, PAD }

@export var shape: Shape = Shape.CRATER:
	set(v):
		shape = v
		_changed()
## CRATER / MOUND / CHAOS / FLAT / DUNES: radius. RILLE / RIDGE / RAMP: half length. MESA: radius along x.
@export var size_a: float = 40.0:
	set(v):
		size_a = v
		_changed()
## RILLE / RIDGE / RAMP: half width. MESA: radius along z. CHAOS: block size. FLAT: blend.
## DUNES: wavelength.
@export var size_b: float = 8.0:
	set(v):
		size_b = v
		_changed()
## CRATER / RILLE: depth. MESA / RIDGE / MOUND / RAMP / DUNES: height. CHAOS: block relief. FLAT: offset.
@export var height: float = 8.0:
	set(v):
		height = v
		_changed()
## CRATER: rim height. RILLE: meander amplitude. MESA: edge roughness (0..1). RIDGE: 1 = double.
## MOUND: terrace step (m). CHAOS: matrix depth.
@export var param_1: float = 1.5:
	set(v):
		param_1 = v
		_changed()
## RILLE: meander wavelength (m).
@export var param_2: float = 120.0:
	set(v):
		param_2 = v
		_changed()
@export var material: Paint = Paint.NONE:
	set(v):
		material = v
		_changed()
## Shade of the painted material (0 dark, 1 mid, 2 light).
@export_range(0, 2) var material_shade: int = 2:
	set(v):
		material_shade = v
		_changed()
## Varies the rays / chaos blocks / meanders.
@export var variant: int = 1:
	set(v):
		variant = v
		_changed()


func _ready() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_changed()


func to_feature() -> Dictionary:
	var p := global_position if is_inside_tree() else position
	var yaw := global_rotation.y if is_inside_tree() else rotation.y
	var m := -1
	if material != Paint.NONE:
		m = int(material) * PlanetSurfaceProfile.SHADES + material_shade
	# Godot's yaw turns -z toward -x; the generator's u axis is +x turned by yaw toward +z
	return {"shape": int(shape), "x": p.x, "z": p.z, "yaw": -yaw, "a": size_a, "b": size_b, "h": height,
		"p1": param_1, "p2": param_2, "mat": m, "seed": variant}


func _changed() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	var n := get_parent()
	while n and not (n is PlanetSurface):
		n = n.get_parent()
	if n:
		(n as PlanetSurface).request_feature_rebuild()
