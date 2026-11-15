class_name LaunchWatchAudio
extends Node
## The launch watch's sounds (LaunchWatch, src/tycoon/tracking/launch_watch.gd): a child the
## watch adds to itself, that only watches it:
##   - the speed key (or V, or a warp picked with , / .): a short rising whoosh and tick, a step
##     higher for each speed, and a falling one back to 1x (the key's own click is muted so the
##     two do not stack)
##   - "Simular até o fim": a gentle ticking loop while the rest of the flight is simulated,
##     faded out when the comic takes over (CwSfx.loop under LOOP_KEY)

const LOOP_KEY := &"flight_skip"

@export var up_sound: StringName = &"warp_up"
@export var down_sound: StringName = &"warp_down"
@export var loop_sound: StringName = &"sim_loop"
## pitch added per speed step (1x 2x 4x 10x 100x)
@export_range(0.0, 0.3, 0.01) var pitch_per_step := 0.07

var watch: LaunchWatch
## warp changes heard (tests)
var warp_changes := 0
var _warp := -1
var _skipping := false


func _init() -> void:
	name = "WatchAudio"


func _ready() -> void:
	watch = get_parent() as LaunchWatch
	var key := watch.get_node_or_null("%Speed") if watch else null
	if key:
		key.set_meta("cw_sfx_press", "")


func _exit_tree() -> void:
	CwSfx.end_loop(LOOP_KEY)


func _process(_delta: float) -> void:
	if watch == null or watch.world == null:
		return
	var skipping := bool(watch.get("_skipping"))
	if skipping != _skipping:
		_skipping = skipping
		if skipping:
			CwSfx.loop(loop_sound, LOOP_KEY)
		else:
			CwSfx.end_loop(LOOP_KEY)
	var w := int(watch.world.warp)
	if _warp < 0 or skipping or watch.skipped:
		_warp = w   # the skip sets its own warp: not the player's choice
		return
	if w == _warp:
		return
	var up := w > _warp
	_warp = w
	warp_changes += 1
	var i := LaunchWatch.SPEEDS.find(w)
	if up:
		CwSfx.play(up_sound, 1.0 + pitch_per_step * maxf(i, 1))
	else:
		CwSfx.play(down_sound)
