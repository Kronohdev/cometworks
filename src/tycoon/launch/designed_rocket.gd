class_name DesignedRocket
extends Node3D
## The voxel look of a designed rocket (scenes/tycoon/launch/designed_rocket.tscn, E2): the
## launch sequence, the pad and the rollout show the rocket the project really flies.
## build(parts) maps a RocketDesigner design onto the era rocket models:
##   the main stage picks the model (its "model" 1..5 in rockets.json -> `models`),
##   the launch class sizes it (`class_scale`), the tanks stretch or shorten it (their
##   "height", plus the upper stage's),
##   side boosters are copies of `booster_models` standing at the Boosters/Slot* markers
##   (turn or move the markers in the editor; their distance from the axis is scaled to hug the
##   core), `booster_length` of the core's height.
## Everything is authored in the scene: the default Core model (era 1) is what the editor shows.

## the rocket model per main-stage "model" (1..5)
@export var models: Array[PackedScene] = []
## booster models: [0] for small solid boosters, [1] for big ones (boosters "size" >= big_size)
@export var booster_models: Array[PackedScene] = []
@export var big_size := 0.45
## rocket size per launch class (rockets.json classes)
@export var class_scale := {"sounding": 0.85, "light": 1.0, "medium": 1.08, "heavy": 1.15, "lunar": 1.22}
## a booster's height, times the core's
@export_range(0.2, 1.0, 0.01) var booster_length := 0.55
## a booster's width, times the core's ("size" of the boosters component scales it too)
@export_range(0.1, 1.0, 0.01) var booster_girth := 1.0
## how far into the core a booster sits (0 = touching, in booster widths)
@export_range(0.0, 0.5, 0.01) var booster_tuck := 0.12
## where along the core the boosters stand (0 = on the ground, 1 = at the top), in core heights
@export_range(0.0, 0.5, 0.01) var booster_base := 0.0

## the parts shown ({} = the authored look)
var parts: Dictionary = {}
## width (x) and height (y) of the core as shown, metres
var core_size := Vector2(1.4, 7.0)
## the scene of the authored core model (shown again for an empty design)
var _authored := ""

@onready var core: Node3D = $Core
@onready var boosters: Node3D = $Boosters


func _ready() -> void:
	for c in core.get_children():
		if c.scene_file_path != "":
			_authored = c.scene_file_path
	var raw0 := _raw_size(core)
	core_size = Vector2(raw0.x * core.scale.x, raw0.y * core.scale.y)
	for s in boosters.get_children():
		for c in s.get_children():
			c.queue_free()


## Shows a design (RocketDesigner parts). {} keeps the authored look.
func build(p_parts: Dictionary) -> void:
	if not is_node_ready():
		await ready
	parts = RocketDesigner.normalize(p_parts) if not p_parts.is_empty() else {}
	for s in boosters.get_children():
		for c in s.get_children():
			s.remove_child(c)
			c.queue_free()
	if parts.is_empty():
		if _authored != "" and (core.get_child_count() == 0 or core.get_child(0).scene_file_path != _authored):
			for c in core.get_children():
				core.remove_child(c)
				c.queue_free()
			core.add_child((load(_authored) as PackedScene).instantiate())
		core.scale = Vector3.ONE
		core_size = _raw_size(core)
		return
	var st := RocketDesigner.stats(parts)
	var mi := clampi(int(st["model"]), 1, maxi(models.size(), 1)) - 1
	if mi < models.size() and models[mi] != null:
		for c in core.get_children():
			core.remove_child(c)
			c.queue_free()
		core.add_child(models[mi].instantiate())
	var k := float(class_scale.get(String(st["class"]), 1.0))
	core.scale = Vector3(k, k * float(st["height"]), k)
	var raw := _raw_size(core)
	core_size = Vector2(raw.x * k, raw.y * k * float(st["height"]))
	var n := int(st["boosters"])
	if n <= 0 or booster_models.is_empty():
		return
	var big := float(st["booster_size"]) >= big_size and booster_models.size() > 1
	var ps: PackedScene = booster_models[1 if big else 0]
	if ps == null:
		return
	var probe := ps.instantiate() as Node3D
	var b_raw := _raw_size(probe)
	probe.free()
	var h := core_size.y * booster_length
	var sy := h / maxf(b_raw.y, 0.01)
	var w := core_size.x * booster_girth * clampf(float(st["booster_size"]) / 0.32, 0.6, 1.6) * 0.5
	var sx := w / maxf(b_raw.x, 0.01)
	var radius := core_size.x * 0.5 + w * (0.5 - booster_tuck)
	var slots := boosters.get_children()
	for i in mini(n, slots.size()):
		var slot := slots[i] as Node3D
		var dir := Vector3(slot.position.x, 0.0, slot.position.z)
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.RIGHT
		slot.position = dir * radius + Vector3(0, core_size.y * booster_base, 0)
		slot.rotation = Vector3.ZERO
		slot.visible = true
		var b := ps.instantiate() as Node3D
		b.scale = Vector3(sx, sy, sx)
		slot.add_child(b)


## The side boosters let go: they drift out and down from the core and vanish over `seconds`
## (the launch sequence calls it at the stage separation).
func drop_boosters(seconds := 1.4) -> void:
	for s in boosters.get_children():
		var slot := s as Node3D
		if slot == null or slot.get_child_count() == 0:
			continue
		var out := Vector3(slot.position.x, 0.0, slot.position.z).normalized()
		var tw := create_tween().set_parallel()
		tw.tween_property(slot, "position", slot.position + out * core_size.x * 1.6 + Vector3(0, -core_size.y * 0.9, 0), seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(slot, "rotation", Vector3(out.z, 0.0, -out.x) * 0.6, seconds)
		tw.chain().tween_callback(func() -> void: slot.visible = false)


## The bounds of what is shown (core and boosters), in this node's space.
func bounds() -> AABB:
	return local_bounds(self)


## Bounds of the meshes under `n`, in `n`'s own space (its own transform left out); works
## outside the tree.
static func local_bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var c: Node = mi
		while c != null and c != n:
			if c is Node3D:
				xf = (c as Node3D).transform * xf
			c = c.get_parent()
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Width / height of the meshes under `n` before its own scale.
static func _raw_size(n: Node3D) -> Vector2:
	var box := local_bounds(n)
	return Vector2(box.size.x, box.size.y)
