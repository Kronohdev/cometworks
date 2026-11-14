shader_type spatial;
// Map halo: a camera-facing additive glow around a body (the Sun, the focused body) that
// never gets smaller than min_px on screen, so the Sun still reads as a star from the
// edge of the solar system. Its real size is the node scale (quad half-size).
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

instance uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.45, 1.0);
instance uniform float min_px = 40.0;
instance uniform float intensity = 1.0;
// radius of the solid disc as a fraction of the quad (the body itself)
instance uniform float core = 0.12;

varying float v_k;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float s = length(MODEL_MATRIX[0].xyz);
	// world size of min_px at this depth
	float px_world = -center.z * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = max(s, min_px * px_world);
	v_k = s / size;
	center.xy += VERTEX.xy * size;
	POSITION = PROJECTION_MATRIX * center;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float c = core * v_k;
	float g = exp(-max(r - c, 0.0) * 5.5) * 0.7 + exp(-max(r - c, 0.0) * 18.0) * 0.8;
	g *= 1.0 - smoothstep(0.7, 1.0, r);
	ALBEDO = glow_color.rgb * g * intensity;
}
