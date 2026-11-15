class_name CampusSigns
extends Node3D
## The story signs standing around the campus island (scenes/tycoon/campus_signs.tscn, the
## "Signs" node of scenes/tycoon/campus.tscn): every child is a CampusSign placed by hand in the
## editor, with its sign_id in data/tycoon/story_signs.json (StorySigns). This script covers the
## signs that have not uncovered yet, stars the unread ones, shows the hover tag (TagLayer/Tag,
## the sticker of scenes/tycoon/ui/sign_tag.tscn: the kind's disc and icon, the title and a
## nudge to read it, or what uncovers it; it floats over the sign and stays on screen) and tells
## TycoonMain which sign is under the mouse. Lots always win: a sign is only hovered or picked
## where the ground under the mouse is not a lot (Campus.lot_at), so signs never steal a click
## meant for a building.

signal sign_uncovered(sign_id: String)

## how close (screen pixels at the reference distance) the mouse must come to a board
@export var pick_radius := 34.0
## the camera distance (m) at which pick_radius applies; nearer signs are easier to hit
@export var pick_reference_distance := 60.0
## the smallest and largest pick radius (px) whatever the distance
@export var pick_radius_range := Vector2(12.0, 70.0)
## space (px) the hover tag keeps from the screen edges
@export var tag_margin := 12.0
## the HUD's top strip and left rail (px of the 1600x900 canvas): the tag stays clear of them
@export var tag_safe_top := 92.0
@export var tag_safe_left := 86.0

const ICONS := "res://ui/cometworks/icons/%s.svg"
const KIND_KEYS := {"lore": "SIGN_KIND_LORE", "history": "SIGN_KIND_HISTORY", "joke": "SIGN_KIND_JOKE"}

var state: TycoonState
var hovered := ""
var _known_open := {}
var _bound := false

## the hover tag (a hidden sticker in the scene; null in a scene without it)
@onready var tag: Control = get_node_or_null("TagLayer/Tag")


func bind(s: TycoonState) -> void:
	state = s
	if not state.changed.is_connected(refresh):
		state.changed.connect(refresh)
	refresh()
	_bound = true


## The signs (CampusSign children) of the island.
func signs() -> Array[CampusSign]:
	var out: Array[CampusSign] = []
	for c in get_children():
		if c is CampusSign:
			out.append(c)
	return out


func sign_node(id: String) -> CampusSign:
	for s in signs():
		if s.sign_id == id:
			return s
	return null


## Covers, uncovers and stars every sign from the campaign; signs that just uncovered are
## announced once (sign_uncovered), not on the first refresh after loading.
func refresh() -> void:
	for s in signs():
		var d := StorySigns.find(s.sign_id)
		s.set_kind(String(d.get("kind", "lore")))
		var open := StorySigns.is_unlocked(state, s.sign_id)
		s.set_state(open, StorySigns.is_read(state, s.sign_id))
		if open and _bound and not _known_open.has(s.sign_id):
			sign_uncovered.emit(s.sign_id)
		if open:
			_known_open[s.sign_id] = true
	if hovered != "":
		_hover(hovered)


## The sign under a screen point, "" if none (or if a lot is under the point).
func sign_at(camera: Camera3D, screen: Vector2) -> String:
	if camera == null or not is_visible_in_tree():
		return ""
	var campus := get_parent() as Campus
	if campus and campus.lot_at(camera, screen) != "":
		return ""
	var best := ""
	var best_d := INF
	for s in signs():
		if not s.is_visible_in_tree():
			continue
		var p := s.pick_point()
		if camera.is_position_behind(p):
			continue
		var dist := camera.global_position.distance_to(p)
		var r := clampf(pick_radius * pick_reference_distance / maxf(dist, 1.0), pick_radius_range.x, pick_radius_range.y)
		var d := camera.unproject_position(p).distance_to(screen)
		if d <= r and d < best_d:
			best_d = d
			best = s.sign_id
	return best


## The hover label of a sign: its title (and a nudge to read it), or what uncovers it.
func hover_text(id: String) -> String:
	var d := StorySigns.find(id)
	if not StorySigns.is_unlocked(state, id):
		return "%s\n%s" % [tr("SIGN_COVERED"), StorySigns.lock_text(state, id)]
	var hint := tr("SIGN_HOVER_READ") if StorySigns.is_read(state, id) else tr("SIGN_HOVER_NEW")
	return "%s\n%s" % [tr(String(d.get("title_key", ""))), hint]


func _hover(id: String) -> void:
	hovered = id
	for s in signs():
		s.set_hover(s.sign_id == id and id != "")
	_fill_tag(id)


## Fills the hover tag for sign `id` (hides it for "").
func _fill_tag(id: String) -> void:
	if tag == null:
		return
	tag.visible = id != ""
	if id == "":
		return
	var d := StorySigns.find(id)
	var open := StorySigns.is_unlocked(state, id)
	var kind := String(d.get("kind", "lore")) if open else "covered"
	for k in ["lore", "history", "joke", "covered"]:
		var disc := tag.get_node_or_null("%%Disc%s" % String(k).capitalize()) as Control
		if disc:
			disc.visible = k == kind
	var icon := ICONS % (String(d.get("icon", "star")) if open else "calendar")
	(tag.get_node("%Icon") as TextureRect).texture = load(icon) if ResourceLoader.exists(icon) else null
	(tag.get_node("%Kicker") as Label).text = tr(String(KIND_KEYS.get(kind, "SIGN_COVERED")))
	var lines := hover_text(id).split("\n")
	if open:
		(tag.get_node("%Title") as Label).text = lines[0]
		(tag.get_node("%Hint") as Label).text = lines[1] if lines.size() > 1 else ""
	else:   # covered: the kicker says so, the title says what uncovers it
		(tag.get_node("%Title") as Label).text = StorySigns.lock_text(state, id)
		(tag.get_node("%Hint") as Label).text = ""
	(tag.get_node("%Hint") as Label).visible = (tag.get_node("%Hint") as Label).text != ""
	tag.reset_size()
	_place_tag()


## Puts the tag over the hovered sign, its tip on the sign, inside the screen.
func _place_tag() -> void:
	if tag == null or not tag.visible:
		return
	var s := sign_node(hovered)
	var cam := get_viewport().get_camera_3d()
	if s == null or cam == null or cam.is_position_behind(s.tag_point()):
		tag.visible = false
		return
	var view := tag.get_viewport_rect().size
	var p := cam.unproject_position(s.tag_point())
	var pos := Vector2(p.x - tag.size.x * 0.5, p.y - tag.size.y)
	var lo := Vector2(maxf(tag_margin, tag_safe_left), maxf(tag_margin, tag_safe_top))
	tag.position = pos.clamp(lo, (view - tag.size - Vector2(tag_margin, tag_margin)).max(lo))


func _process(_delta: float) -> void:
	if hovered != "":
		_place_tag()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and state != null and is_visible_in_tree():
		var cam := get_viewport().get_camera_3d()
		var id := sign_at(cam, (event as InputEventMouseMotion).position)
		if id != hovered:
			_hover(id)


## The mouse left the campus (a screen opened, the hangar): no sign stays hovered.
func clear_hover() -> void:
	if hovered != "":
		_hover("")
