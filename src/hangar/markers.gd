class_name HangarMarkers
extends Node3D
## KSP-style overlay markers (meshes and materials live in scenes/hangar.tscn):
## yellow = Center of Mass (wet, with a darker dry-mass dot), magenta = Center of
## Thrust with thrust arrow, cyan = Center of Lift / Pressure.

const COLOR_COM := Color(1.0, 0.85, 0.1)
const COLOR_COT := Color(0.95, 0.2, 0.85)
const COLOR_COL := Color(0.2, 0.75, 1.0)

var show_com := true
var show_cot := true
var show_col := true

@onready var _com: MeshInstance3D = $CoM
@onready var _com_dry: MeshInstance3D = $CoMDry
@onready var _cot: MeshInstance3D = $CoT
@onready var _cot_arrow: Node3D = $CoTArrow
@onready var _col: MeshInstance3D = $CoL


func update_from(m: Dictionary, vessel_size: float) -> void:
	var r := clampf(vessel_size * 0.035, 0.18, 2.0)
	_com.visible = show_com and m["has_com"]
	_com_dry.visible = _com.visible
	_cot.visible = show_cot and m["has_cot"]
	_cot_arrow.visible = _cot.visible
	_col.visible = show_col and m["has_col"]
	_com.position = m["com"]
	_com.scale = Vector3.ONE * r * 2.0
	_com_dry.position = m["com_dry"]
	_com_dry.scale = Vector3.ONE * r * 0.9
	_cot.position = m["cot"]
	_cot.scale = Vector3.ONE * r * 1.6
	_col.position = m["col"]
	_col.scale = Vector3.ONE * r * 1.6
	var dir: Vector3 = m["thrust_dir"]
	_cot_arrow.position = m["cot"]
	_cot_arrow.basis = Basis(_rotation_to(Vector3.UP, dir)) * Basis.from_scale(Vector3.ONE * r * 3.0)


static func _rotation_to(a: Vector3, b: Vector3) -> Quaternion:
	if a.dot(b) > 0.9999:
		return Quaternion.IDENTITY
	if a.dot(b) < -0.9999:
		return Quaternion(Vector3.RIGHT, PI)
	return Quaternion(a, b)
