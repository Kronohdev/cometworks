shader_type spatial;
// Map dots (the asteroid belt and the Trojans, MultiMesh of a 2x2 quad): each instance is a soft
// round dot `px` pixels wide whatever its distance, in its instance colour. `fade` (set by
// FlightMap) dims the whole cloud when the camera is close to a planet.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float px : hint_range(0.5, 8.0) = 2.2;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float px_world = -c.z * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	c.xy += VERTEX.xy * 0.5 * px * px_world;
	POSITION = PROJECTION_MATRIX * c;
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = COLOR.rgb;
	ALPHA = smoothstep(1.0, 0.35, r) * COLOR.a * fade;
}
