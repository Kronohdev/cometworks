class_name FlightExplosion
extends Node3D
## One-shot explosion (scenes/flight/explosion.tscn): starts the authored particle
## systems, fades the flash light and frees itself.

@export var life := 9.0
@export var flash_time := 0.9

var _t := 0.0
var _flash0 := 1.0

@onready var _flash: OmniLight3D = $Flash


func _ready() -> void:
	_flash0 = _flash.light_energy * scale.x
	for c in get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).restart()
			(c as GPUParticles3D).emitting = true


func _process(delta: float) -> void:
	_t += delta
	_flash.light_energy = _flash0 * clampf(1.0 - _t / flash_time, 0.0, 1.0)
	if _t > life:
		queue_free()
