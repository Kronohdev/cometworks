class_name CwAmbiencePlayer
extends AudioStreamPlayer
## An ambience bed that fades in when it starts and, inside a main-menu shot (MenuShot), fades
## out before the shot ends, so the attract loop's cuts never click. Set the stream, bus and
## volume in the inspector as on any AudioStreamPlayer; `volume_db` is the level it fades to.

@export_range(0.0, 10.0, 0.05, "suffix:s") var fade_in := 1.5
@export_range(0.0, 10.0, 0.05, "suffix:s") var fade_out := 1.0
## start on ready (else call start())
@export var play_on_ready := true
## extra level 0..1 a driver script sets (the campus day / night crossfade, ducking)
@export_range(0.0, 1.0, 0.01) var mix := 1.0

var _level_db := 0.0
var _gain := 0.0
var _target := 0.0


func _ready() -> void:
	_level_db = volume_db
	volume_db = -80.0
	if play_on_ready:
		start()


func start() -> void:
	_target = 1.0
	if not playing and CwSfx.audible():
		play(randf() * _length() * 0.9)


func stop_soft() -> void:
	_target = 0.0


func _length() -> float:
	return stream.get_length() if stream else 0.0


func _process(delta: float) -> void:
	var target := _target
	var shot := get_parent()
	if shot is MenuShot:
		var left := (shot as MenuShot).duration - (shot as MenuShot).time
		if fade_out > 0.0 and left < fade_out:
			target = minf(target, clampf(left / fade_out, 0.0, 1.0))
	var speed := 1.0 / maxf(fade_in if target > _gain else fade_out, 0.01)
	_gain = move_toward(_gain, target, delta * speed)
	volume_db = _level_db + linear_to_db(maxf(sin(_gain * PI * 0.5) * mix, 0.0001))
	if _gain <= 0.0 and _target <= 0.0 and playing:
		stop()
