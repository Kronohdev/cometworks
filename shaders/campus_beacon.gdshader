shader_type spatial;
render_mode unshaded, shadows_disabled;
// Blinking obstruction / pad lights on the campus masts (scenes/tycoon/campus_dressing.tscn).
// A short flash every `period` seconds; set the instance parameter `phase` (0..1) so the
// lights of different masts do not blink together.

uniform vec3 color : source_color = vec3(1.0, 0.36, 0.42);
uniform float energy : hint_range(0.0, 32.0) = 9.0;
uniform float period : hint_range(0.2, 10.0) = 1.6;
// fraction of the period the light is on
uniform float duty : hint_range(0.02, 1.0) = 0.28;
// brightness while off (a dim glass)
uniform float idle : hint_range(0.0, 1.0) = 0.08;
instance uniform float phase = 0.0;

void fragment() {
	float t = fract(TIME / period + phase);
	float on = smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(duty, duty + 0.06, t));
	ALBEDO = color * energy * mix(idle, 1.0, on);
}
