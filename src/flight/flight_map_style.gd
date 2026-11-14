@tool
class_name FlightMapStyle
extends Resource
## Colours of the flight map (orbit and trajectory lines, markers, labels) in the Cometworks
## look: bright candy conics on a soft navy sky, paper label pills with ink text. One shared
## resource (scenes/flight/map_style.tres) so every map view - the flight's and any other that
## draws vessels, conics or markers - looks the same; tune it in the inspector.
## Line colours are candy fills (they glow on the dark sky); label colours must read as text
## on the paper pills of scenes/flight/map_marker.tscn (deep enough, like CwPalette's accents).

## trajectory colour per sphere-of-influence body id
@export var soi_colors := {"earth": Color("#7cc8ff"), "moon": Color("#ffd25c"), "sun": Color("#ff9a5c"),
	"mars": Color("#ff8fb8"), "venus": Color("#6fe0be")}
## trajectory colour around any other body
@export var soi_other := Color("#b39cff")
## maneuver identity: node markers, the gizmo centre, the burn arrow, the "add node" hover
@export var node_color := Color("#ff8fb8")
## the planned path after a node, and its second shade
@export var plan_color := Color("#ff8fb8")
@export var plan_color_2 := Color("#ffc2d9")
## marker icons (candy, on the sky)
@export var apsis_icon := Color("#fff6e6")
@export var closest_icon := Color("#ffd25c")
@export var impact_icon := Color("#ff6b8a")
@export var line_icon := Color("#e6defc")
## marker label text (ink-readable on the paper pill)
@export var label_text := Color("#2b2a5c")
@export var label_dim := Color("#5d5b8c")
@export var label_warning := Color("#c27400")
@export var label_danger := Color("#d93a5c")
@export var label_node := Color("#d6407e")
@export var label_encounter := Color("#178a57")
## body names (cream with an ink outline, straight on the sky)
@export var body_name := Color("#e6defc")
@export var body_name_focus := Color("#fff6e6")
@export var body_name_target := Color("#ffd25c")


func soi_color(body_id: String) -> Color:
	return soi_colors.get(body_id, soi_other)


## A colour deep enough to read on a paper pill (encounter labels take the body's line colour).
static func on_paper(c: Color) -> Color:
	return CwPalette.ink(c)
