class_name MissionPhotoStudio
extends Node
## Renders the photos missions send home (MissionPhotos records) off-screen, in the windowed
## game: scenes/tycoon/photos/photo_studio.tscn holds a small 2D SubViewport ("Frame": the
## print with its vignette, grain and corner marks, the mission, agency, date and subject
## stamps) over a 3D SubViewport with its own world ("World/Stage": the space sky and the sets:
## Earth, Moon, Surface, Comet, Saturn, Jupiter, Mars, each with its Sun, a Spin node and
## Poses/<pose> markers whose Look child the camera aims at). Both viewports stay disabled
## (nothing rendered, nothing to pay) except for the few frames a photo takes.
## TycoonMain binds it to the state: it renders every photo whose PNG is missing (new ones on
## each launch, old ones after a cleared user://), one at a time, and emits photo_ready.
## Headless runs (tests, the CI) have no renderer: can_render() is false and the queue waits,
## while the records themselves are still made and saved (MissionPhotos).

signal photo_ready(photo_id: String, path: String)
## the queue emptied after rendering at least one photo
signal batch_done(count: int)

## frames to let a set settle (shader compile, particles, the 2D print reading the 3D shot)
@export var settle_frames := 4

var state: TycoonState
var _queue: Array[Dictionary] = []
var _busy := false
var _done_in_batch := 0

@onready var frame: SubViewport = $Frame
@onready var world: SubViewport = %World
@onready var camera: Camera3D = %Camera
@onready var sets: Node3D = %Sets


func _ready() -> void:
	# the SubViewportContainer "View" switches its viewport to UPDATE_ALWAYS when it enters the
	# tree: put it back, or the studio's 3D world renders every frame (~2 ms of GPU on the
	# campus) while no photo is being taken
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	frame.render_target_update_mode = SubViewport.UPDATE_DISABLED


## True where pictures can be rendered (a real display and renderer, not --headless).
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server")


func bind(s: TycoonState) -> void:
	state = s
	if not state.changed.is_connected(_on_changed):
		state.changed.connect(_on_changed)
	_on_changed.call_deferred()


## Queues the state's photos without a picture (called on every state change; cheap).
func _on_changed() -> void:
	if state == null or not can_render():
		return
	for ph in MissionPhotos.missing(state):
		var queued := false
		for q in _queue:
			if q["id"] == ph["id"]:
				queued = true
				break
		if not queued:
			_queue.append(ph)
	if not _busy and not _queue.is_empty():
		_run()


func _run() -> void:
	_busy = true
	_done_in_batch = 0
	while not _queue.is_empty():
		var ph: Dictionary = _queue.pop_front()
		if MissionPhotos.has_image(ph):
			continue
		var ok := await render(ph, state)
		if ok:
			_done_in_batch += 1
			photo_ready.emit(String(ph["id"]), String(ph["file"]))
	_busy = false
	if _done_in_batch > 0:
		batch_done.emit(_done_in_batch)


## Renders one photo record to its "file" (PNG). Returns false headless or on an unknown shot.
func render(ph: Dictionary, s: TycoonState = null) -> bool:
	if not can_render() or not is_inside_tree():
		return false
	var shot := MissionPhotos.shot(String(ph.get("shot", "")))
	if shot.is_empty() or not _pose(shot):
		return false
	var img := await capture(ph, s)
	if img == null:
		return false
	var path := String(ph.get("file", ""))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	MissionPhotos.forget(path)
	return err == OK


## Frames the shot of `ph` and returns the printed picture (stamps and look included).
func capture(ph: Dictionary, s: TycoonState = null) -> Image:
	var shot := MissionPhotos.shot(String(ph.get("shot", "")))
	if shot.is_empty() or not _pose(shot, int(ph.get("seed", 0))):
		return null
	var size: Array = MissionPhotos.data().get("size", [480, 300])
	frame.size = Vector2i(int(size[0]), int(size[1]))
	_stamp(ph, s)
	var print_mat := (%Print as ColorRect).material as ShaderMaterial
	print_mat.set_shader_parameter("ir", 1.0 if String(ph.get("filter", "")) == "ir" else 0.0)
	print_mat.set_shader_parameter("grain_seed", float(int(ph.get("seed", 0)) % 997))
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in settle_frames:
		await RenderingServer.frame_post_draw
	var img := frame.get_texture().get_image()
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	frame.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return img


## Shows the shot's set alone and puts the camera on its pose, with the photo's small
## variations from its seed (the body turned a little, the camera nudged and rolled).
func _pose(shot: Dictionary, p_seed := 0) -> bool:
	var set_node := sets.get_node_or_null(String(shot.get("set", ""))) as Node3D
	if set_node == null:
		return false
	var pose := set_node.get_node_or_null("Poses/" + String(shot.get("pose", ""))) as Node3D
	if pose == null:
		return false
	for c in sets.get_children():
		(c as Node3D).visible = c == set_node
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var spin := set_node.get_node_or_null("Spin") as Node3D
	if spin:
		if not spin.has_meta("home"):
			spin.set_meta("home", spin.transform)
		var home: Transform3D = spin.get_meta("home")
		spin.transform = home.rotated_local(Vector3.UP, rng.randf_range(-0.6, 0.6))
	var look := pose.get_node_or_null("Look") as Node3D
	var from := pose.global_position
	var to := look.global_position if look else Vector3.ZERO
	var dist := from.distance_to(to)
	from += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * dist * 0.015
	camera.fov = float(shot.get("fov", 40.0))
	camera.look_at_from_position(from, to, Vector3.UP)
	camera.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.05, 0.05))
	return true


func _stamp(ph: Dictionary, s: TycoonState) -> void:
	var type_key := ""
	var agency := "Cometworks"
	var stamp := ""
	if s:
		type_key = String(s.mission_type(String(ph.get("type", ""))).get("name_key", ""))
		agency = s.agency_name
		stamp = MissionPhotos.stamp_text(s, int(ph.get("week", 0)))
	var code := String(ph.get("code", ""))
	(%Mission as Label).text = ("%s · %s" % [code, tr(type_key)] if type_key != "" else code).to_upper()
	(%Agency as Label).text = agency.to_upper()
	(%Date as Label).text = "%s · %04d" % [stamp, int(ph.get("seed", 0)) % 10000]
	var subj := String(MissionPhotos.shot(String(ph.get("shot", ""))).get("subject_key", ""))
	var sub_text := tr(subj)
	if String(ph.get("filter", "")) == "ir":
		sub_text = tr("TY_PH_IR") % sub_text
	(%Subject as Label).text = sub_text.to_upper()
