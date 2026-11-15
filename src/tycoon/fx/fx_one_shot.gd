class_name FxOneShot
extends Node3D
## A one-off flourish authored in its own scene (scenes/tycoon/fx/: a building's level-up pop,
## fireworks over the campus, a confetti burst): play() restarts every GPUParticles3D under it
## (except those with metadata `keyed` = true: the animation starts them, e.g. a firework shell
## that bursts at the top of its climb) and plays the AnimationPlayer's "play" animation (if
## there is one), then the node frees
## itself (or hides, see `free_when_done`) after `lifetime` seconds.
## Reduce motion (MenuSettings): children with metadata `flashy` = true (flashes, big bursts)
## stay hidden, so only the gentle part plays.

signal done

@export var lifetime := 4.0
@export var free_when_done := true
@export var autoplay := false

var playing := false
var _left := 0.0


func _ready() -> void:
	if autoplay:
		play.call_deferred()


func play() -> void:
	visible = true
	playing = true
	_left = lifetime
	var reduced := CwMotion.reduced()
	for n in find_children("*", "Node3D", true, false):
		if n.get_meta("flashy", false):
			(n as Node3D).visible = not reduced
	for n in find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		if p.is_visible_in_tree() and not p.get_meta("keyed", false):
			p.restart()
			p.emitting = true
	var ap := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation("play"):
		ap.play("play")
	set_process(true)


func _process(delta: float) -> void:
	if not playing:
		set_process(false)
		return
	_left -= delta
	if _left <= 0.0:
		playing = false
		done.emit()
		if free_when_done:
			queue_free()
		else:
			visible = false
