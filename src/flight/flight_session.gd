class_name FlightSession
extends RefCounted
## Static hand-off between the hangar and the flight scene (no autoload needed, so it
## also works from `--script` test runs). The hangar stores the assembled vessel as a
## PackedScene (Vessel.to_packed_scene()) plus its predicted ascent Δv; the flight scene
## builds the rocket from it, and "Revert to hangar" brings the same vessel back.

const FLIGHT_SCENE := "res://scenes/flight/flight.tscn"
const HANGAR_SCENE := "res://scenes/hangar.tscn"

static var vessel_scene: PackedScene = null
static var vessel_name := ""
## Hangar prediction (VesselMath.analyze ascent Δv, m/s) shown in the flight report.
static var predicted_dv := 0.0
## Set by the flight scene when the player asks to go back: the hangar restores the vessel.
static var return_to_hangar := false
## Optional: start the flight with the auto-ascent engaged (screenshots / demo).
static var auto_ascent := false
## Loose subassemblies left floating in the hangar (packed part trees), restored on return.
static var hangar_loose: Array = []
## Optional tycoon mission the hangar builds for (empty in the free workshop):
## {"title": String, "target": String, "dv_needed": float (m/s), "payload_kg": float,
##  "budget_musd": float, "crewed": bool}
static var mission: Dictionary = {}


static func has_vessel() -> bool:
	return vessel_scene != null


static func set_vessel(ps: PackedScene, display_name := "", dv := 0.0) -> void:
	vessel_scene = ps
	vessel_name = display_name
	predicted_dv = dv


static func clear() -> void:
	vessel_scene = null
	vessel_name = ""
	predicted_dv = 0.0
	return_to_hangar = false
	hangar_loose = []
