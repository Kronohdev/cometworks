class_name NpcEvents
extends RefCounted
## Singleton-free event bus for the Cometling NPCs (no autoload).
## Anything in the game can broadcast a hangar event and every Cometling that has
## listen_to_events on reacts (Cometling.react):
##
##     NpcEvents.emit("part_placed", {"position": part.global_position, "radius": 40.0})
##     NpcEvents.emit("launch")
##
## Known events: part_placed, part_removed, vessel_cleared, launch, success, failure,
## hello, staged. Optional data keys: position (Vector3) + radius (float) limit the
## reaction to creatures near that point; stagger (s, default 0.35) spreads the
## reactions over time so a crowd does not move in lockstep.
##
## The bus object is a lazily created RefCounted held in a static variable: it lives
## as long as the game runs and needs no node in the scene tree.

signal event(name: String, data: Dictionary)

static var _bus: NpcEvents


static func bus() -> NpcEvents:
	if _bus == null:
		_bus = NpcEvents.new()
	return _bus


static func emit(name: String, data: Dictionary = {}) -> void:
	bus().event.emit(name, data)
