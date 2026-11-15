class_name SurfaceCampusButton
extends Button
## The campus HUD's "Superfícies" button (scenes/surface/explore/surface_campus_button.tscn, on the
## bottom bar next to the Solar System map). It shows up once the career has landed somewhere
## (SurfaceLog: a lander / rover mission that reached a surface), opens the picker of the
## surfaces the agency has reached and then the chosen one for free play
## (SurfaceFreePlay.open_in_campus: the rover drive, or the campus viewer with the drone).

const CHECK_EVERY := 1.0

var _t := 0.0

@onready var picker: SurfacePicker = $Picker


func _ready() -> void:
	pressed.connect(open_picker)
	picker.chosen.connect(_on_chosen)
	visible = false
	_refresh.call_deferred()


## The TycoonMain this button lives in (a node with the career `state` above it), or null.
func main() -> Node:
	var n := get_parent()
	while n:
		if "state" in n and n.get("state") is TycoonState and n.has_method("open_space_map"):
			return n
		n = n.get_parent()
	return null


func state() -> TycoonState:
	var m := main()
	return m.get("state") if m else null


## Shown once a surface beyond Earth is open for free play.
func _refresh() -> void:
	var s := state()
	var show := false
	if s:
		for id in SurfaceLog.unlocked_bodies(s):
			if not bool(SurfaceExplore.body_data(id).get("always", false)):
				show = true
				break
	visible = show


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = CHECK_EVERY
		_refresh()


func open_picker() -> void:
	picker.open(state())


func _on_chosen(body: StringName) -> void:
	var m := main()
	if m:
		SurfaceFreePlay.open_in_campus(m, body)
