shader_type canvas_item;
// The emblem ring drawn by the comet's tail in the intro (scenes/menu/intro.tscn): only the
// part of the ring the comet has swept (clockwise from start_angle) is shown, with a glowing edge.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float start_angle = 1.5708;          // radians, screen space (y down): PI/2 = bottom
uniform float feather : hint_range(0.0, 0.2) = 0.025;
uniform vec4 edge_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float a = mod(atan(d.y, d.x) - start_angle + TAU * 4.0, TAU) / TAU;
	float shown = 1.0 - smoothstep(progress - feather, progress, a);
	float edge = smoothstep(progress - feather * 3.0, progress - feather * 0.5, a) * shown;
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb, edge_color.rgb, edge * 0.85);
	c.a *= shown;
	if (progress >= 0.999) { c = texture(TEXTURE, UV); }
	COLOR = c;
}
