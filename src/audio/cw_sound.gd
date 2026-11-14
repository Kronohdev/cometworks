@tool
class_name CwSound
extends Resource
## One named sound of the sound library (assets/audio/cw_sound_library.tres): one or more
## streams (a variant is picked at random each time), its level, pitch variance, bus and
## anti-spam limits. Edit it in the inspector; CwSfx.play(name) plays it.

## the name scripts ask for (CwSfx.play(&"ui_click"))
@export var name: StringName
## variants; one is picked at random (never the same one twice in a row when there are more)
@export var streams: Array[AudioStream] = []
@export_range(-60.0, 12.0, 0.1, "suffix:dB") var volume_db := 0.0
## random pitch between the two (1 = as recorded)
@export_range(0.25, 4.0, 0.01) var pitch_min := 1.0
@export_range(0.25, 4.0, 0.01) var pitch_max := 1.0
## Music, SFX, UI or Ambience (default_bus_layout.tres)
@export var bus: StringName = &"SFX"
## the same sound does not start again sooner than this
@export_range(0.0, 10.0, 0.01, "suffix:s") var cooldown := 0.0
## at most this many copies at once
@export_range(1, 16) var max_voices := 2
## odds that a request really plays (Cometling chirps: rare on purpose)
@export_range(0.0, 1.0, 0.01) var chance := 1.0

var _last_pick := -1


func pick(rng: RandomNumberGenerator) -> AudioStream:
	if streams.is_empty():
		return null
	if streams.size() == 1:
		return streams[0]
	var i := rng.randi_range(0, streams.size() - 1)
	if i == _last_pick:
		i = (i + 1 + rng.randi_range(0, streams.size() - 2)) % streams.size()
	_last_pick = i
	return streams[i]


func pitch(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
