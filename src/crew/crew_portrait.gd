class_name CrewPortrait
extends SubViewportContainer
## Live 3D portrait of a crew member (scenes/ui/crew_portrait.tscn): a Cometling in
## its own small World3D, idling and blinking. To stay cheap on integrated GPUs the
## viewport is re-rendered only every `frame_interval` frames (staggered between
## portraits) and not at all while hidden.

## Re-render every N frames (1 = every frame). 3 ~ 20 fps at 60 fps.
@export_range(1, 10) var frame_interval := 3

static var _counter := 0

var _phase := 0
var _frame := 0
var _member: CrewMember

@onready var viewport: SubViewport = $Viewport
@onready var creature: Cometling = $Viewport/Creature


func _ready() -> void:
	_phase = _counter % frame_interval
	_counter += 1
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	visibility_changed.connect(_on_visibility)


func set_member(m: CrewMember) -> void:
	_member = m
	if not is_node_ready():
		await ready
	creature.personality_seed = m.portrait_seed
	CometlingLooks.apply(creature, m.variant, m.role)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Plays a reaction on the portrait (wave, cheer, jump, nod, surprise...).
func play(action: String) -> void:
	creature.play(action)


func emote(e: String) -> void:
	creature.show_emote(e, 1.4)


func _on_visibility() -> void:
	if is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_frame += 1
	if (_frame + _phase) % frame_interval == 0:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
