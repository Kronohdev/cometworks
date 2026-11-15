class_name CwBackground
extends Node
## The game away from the player (alt-tab, minimized): the frame rate drops to BACKGROUND_FPS
## until the window has the focus again. A Windows swap chain that is occluded or minimized stops
## pacing the loop (no vsync wait), so the whole campus kept rendering flat out behind an open
## screen while nobody looked; this keeps the GPU and the driver quiet in the background.
## A child of the CwAudio autoload (CwSfx._ready), so it lives in every scene.

## frames per second while the window has no focus
const BACKGROUND_FPS := 15

var _saved_fps := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			enter_background()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			leave_background()


func enter_background() -> void:
	if _saved_fps >= 0:
		return
	_saved_fps = Engine.max_fps
	if Engine.max_fps == 0 or Engine.max_fps > BACKGROUND_FPS:
		Engine.max_fps = BACKGROUND_FPS


func leave_background() -> void:
	if _saved_fps < 0:
		return
	Engine.max_fps = _saved_fps
	_saved_fps = -1


func in_background() -> bool:
	return _saved_fps >= 0
