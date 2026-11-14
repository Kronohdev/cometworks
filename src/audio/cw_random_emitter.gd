class_name CwRandomEmitter
extends AudioStreamPlayer3D
## A spot in the world that makes a sound now and then (the workshop's distant clanks): every
## `interval` seconds (random in the range) it plays a variant of the library sound `sound`
## from where it stands. Distance, attenuation, bus and level are this player's own settings
## in the inspector; `activity` (0..1, set by a driver such as CampusAudio) thins it out.

## library sound (CwSoundLibrary) the variants and pitch come from
@export var sound: StringName = &"workshop_clank"
## seconds between two sounds, random between x and y
@export var interval := Vector2(6.0, 16.0)
## 0..1: odds that a turn really sounds (night shifts are quieter)
@export_range(0.0, 1.0, 0.01) var activity := 1.0
@export var enabled := true

var _rng := RandomNumberGenerator.new()
var _wait := 0.0
## times it sounded (tests)
var count := 0


func _ready() -> void:
	_rng.randomize()
	_wait = _rng.randf_range(interval.x * 0.3, interval.y)


func _process(delta: float) -> void:
	if not enabled:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = _rng.randf_range(minf(interval.x, interval.y), maxf(interval.x, interval.y))
	if _rng.randf() > activity:
		return
	emit_once()


## Plays one variant now (if the library has the sound).
func emit_once() -> void:
	var sfx := CwSfx.get_instance()
	var s := sfx.sound(sound) if sfx and sfx.library else null
	if s == null or s.streams.is_empty():
		return
	stream = s.pick(_rng)
	pitch_scale = s.pitch(_rng)
	if CwSfx.audible():
		play()
	count += 1
