extends CwScreen
## The agency's photo album (scenes/tycoon/ui/screens/album.tscn, opened from the HUD's photo
## key, next to the Solar System key, once a mission has sent a photo home): every picture our
## missions sent home (MissionPhotos), newest first, as thumbnails on the left (copies of the
## hidden ThumbTemplate; a star marks the ones pinned on the campus mural); the chosen one big on
## the right with its subject, mission, target, arrival date and result, and "Pin on the mural".
## A photo the studio has not rendered yet (MissionPhotoStudio) shows "Developing…" and fills
## in when its picture is ready. Everything visual is in the scene.
## args: {"photo": id} or {"project_id": id} opens on that photo / that mission's first photo.

const OUTCOME_KEYS := {"partial": "TY_PH_OUT_PARTIAL", "full": "TY_PH_OUT_FULL", "exceptional": "TY_PH_OUT_EXCEPTIONAL"}

var selected := ""
var _studio: MissionPhotoStudio


func _bound() -> void:
	%Pin.toggled.connect(func(on: bool) -> void:
		if selected != "":
			MissionPhotos.set_pinned(state, selected, on))
	var main := hud.owner as TycoonMain if hud else null
	_studio = main.photo_studio if main else null
	if _studio and not _studio.photo_ready.is_connected(_on_photo_ready):
		_studio.photo_ready.connect(_on_photo_ready)


func _exit_tree() -> void:
	super._exit_tree()
	if _studio and _studio.photo_ready.is_connected(_on_photo_ready):
		_studio.photo_ready.disconnect(_on_photo_ready)


func _on_photo_ready(_id: String, _path: String) -> void:
	if is_inside_tree():
		refresh()


func open_with(args: Dictionary) -> void:
	if args.has("photo"):
		selected = String(args["photo"])
	elif args.has("project_id"):
		var list := MissionPhotos.photos_for(state, String(args["project_id"]))
		if not list.is_empty():
			selected = String(list[0]["id"])
	refresh()


func select(photo_id: String) -> void:
	selected = photo_id
	refresh()


func refresh() -> void:
	if state == null:
		return
	var list := MissionPhotos.album(state)
	%Count.text = "%d" % list.size()
	%Empty.visible = list.is_empty()
	%Body.visible = not list.is_empty()
	var found := false
	for ph: Dictionary in list:
		if ph["id"] == selected:
			found = true
	if not found:
		selected = String(list[0]["id"]) if not list.is_empty() else ""
	var thumbs := copies(%ThumbTemplate, list.size())
	for i in list.size():
		var ph: Dictionary = list[i]
		var b := thumbs[i] as Button
		b.set_meta("photo", ph["id"])
		var tex := MissionPhotos.texture(ph)
		(b.get_node("VBox/Slot/Pic") as TextureRect).texture = tex
		(b.get_node("VBox/Slot/Wait") as Label).visible = tex == null
		(b.get_node("VBox/Slot/Pin") as Label).visible = bool(ph.get("pinned", false))
		(b.get_node("VBox/Code") as Label).text = String(ph.get("code", ""))
		b.tooltip_text = tr(String(ph.get("subject_key", "")))
		b.set_pressed_no_signal(ph["id"] == selected)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: select(String(b.get_meta("photo", ""))))
	for ph: Dictionary in list:
		if ph["id"] == selected:
			_show(ph)


func _show(ph: Dictionary) -> void:
	var tex := MissionPhotos.texture(ph)
	%Big.texture = tex
	%Developing.visible = tex == null
	var subject := tr(String(ph.get("subject_key", "")))
	if String(ph.get("filter", "")) == "ir":
		subject = tr("TY_PH_IR") % subject
	%Subject.text = subject
	var type_key := String(state.mission_type(String(ph.get("type", ""))).get("name_key", ""))
	%MissionValue.text = "%s · %s" % [String(ph.get("code", "")), tr(type_key)] if type_key != "" else String(ph.get("code", ""))
	%TargetValue.text = tr(String(state.mission_target(String(ph.get("target", ""))).get("name_key", "")))
	%WhenValue.text = String(ph.get("date", ""))
	%OutcomeValue.text = tr(String(OUTCOME_KEYS.get(String(ph.get("outcome", "")), "TY_PH_OUT_PARTIAL")))
	%Pin.set_pressed_no_signal(bool(ph.get("pinned", false)))
