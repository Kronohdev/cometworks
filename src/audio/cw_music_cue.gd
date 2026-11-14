class_name CwMusicCue
extends Node
## Drop it in a scene to say which music plays there: when the node is ready it asks the
## sound player (CwSfx) to crossfade to `track` (a music entry of the sound library; empty =
## fade the music out). The main menu and the campus each carry one.

@export var track: StringName = &"music_menu"
## crossfade seconds (< 0 = the player's default)
@export_range(-1.0, 10.0, 0.1) var fade := -1.0


func _ready() -> void:
	CwSfx.music(track, fade)
