class_name PhotoMural
extends Node3D
## The photo mural by the headquarters (scenes/tycoon/photos/photo_mural.tscn, placed on the
## campus in tycoon_main.tscn): a cork board on two posts with up to three prints pinned on it,
## the agency's best photos (MissionPhotos.mural: the ones pinned in the album first, then the
## best results). It stands only once a mission has sent a photo home, and a print waits empty
## until the studio has rendered its picture. Cheap: three quads whose textures change only
## when the chosen photos (or their pictures) change.

var state: TycoonState
var _shown := ""


func _ready() -> void:
	visible = false


func bind(s: TycoonState, studio: MissionPhotoStudio = null) -> void:
	state = s
	state.changed.connect(refresh)
	if studio:
		studio.photo_ready.connect(func(_id: String, _p: String) -> void:
			_shown = ""
			refresh())
	refresh()


func refresh() -> void:
	if state == null:
		return
	visible = not state.photos.is_empty()
	if not visible:
		return
	var list := MissionPhotos.mural(state)
	var sig := ""
	for ph in list:
		sig += "%s:%s;" % [ph["id"], MissionPhotos.has_image(ph)]
	if sig == _shown:
		return
	_shown = sig
	var slots := $Board/Photos.get_children()
	for i in slots.size():
		var slot := slots[i] as Node3D
		var ph: Dictionary = list[i] if i < list.size() else {}
		slot.visible = not ph.is_empty()
		if ph.is_empty():
			continue
		var tex := MissionPhotos.texture(ph)
		var mat := (slot.get_node("Pic") as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		mat.albedo_texture = tex
		mat.emission_texture = tex
		mat.albedo_color = Color.WHITE if tex else Color(0.12, 0.12, 0.2)
		mat.emission = Color.WHITE if tex else Color.BLACK
