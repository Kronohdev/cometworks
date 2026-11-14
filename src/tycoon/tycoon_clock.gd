class_name TycoonClock
extends RefCounted
## Campaign clock (GDD section 5): real time with pause and 3 speeds (seconds per week from
## data/tycoon/rules.json), plus the fair mode used at the hackathon (1 s per week). The
## clock only counts; `tick` returns how many whole weeks the state must advance.

signal speed_changed(speed: int)

## 0 = paused, 1..3 = speeds
var speed := 1
var fair_mode := false
## dev menu only (src/dev/cw_dev.gd): weeks run this many times faster at any speed (1 = normal)
var dev_turbo := 1.0
var _seconds: Array = [0.0, 6.0, 3.0, 1.0]
var _fair_seconds := 1.0
var _acc := 0.0


func _init(rules: Dictionary = {}) -> void:
	if rules.has("seconds_per_week"):
		_seconds = rules["seconds_per_week"]
	_fair_seconds = float(rules.get("fair_seconds_per_week", 1.0))


func set_speed(s: int) -> void:
	s = clampi(s, 0, _seconds.size() - 1)
	if s == speed:
		return
	speed = s
	speed_changed.emit(speed)


func toggle_pause() -> void:
	set_speed(0 if speed > 0 else 1)


func seconds_per_week() -> float:
	if speed == 0:
		return INF
	return (_fair_seconds if fair_mode else float(_seconds[speed])) / maxf(dev_turbo, 0.01)


## Real seconds elapsed -> whole weeks to simulate now (at most 4 per frame, so a hitch
## never skips a decision).
func tick(delta: float) -> int:
	if speed == 0:
		return 0
	_acc += delta
	var spw := seconds_per_week()
	var n := 0
	while _acc >= spw and n < 4:
		_acc -= spw
		n += 1
	if n == 4:
		_acc = minf(_acc, spw)
	return n


## Fraction of the current week already elapsed (0..1), for smooth UI.
func week_fraction() -> float:
	return 0.0 if speed == 0 else clampf(_acc / seconds_per_week(), 0.0, 1.0)
