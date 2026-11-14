shader_type spatial;
// Soft camera-facing glow for the main-menu shots: the comet's coma, the Sun, lanterns,
// the launch flare. QuadMesh of size (2, 2); the node scale is the glow radius. Additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 glow_color : source_color = vec3(1.0, 0.8, 0.5);
uniform float intensity : hint_range(0.0, 16.0) = 1.0;
// a bright core (fraction of the radius) and the softness of the falloff
uniform float core : hint_range(0.0, 1.0) = 0.06;
uniform float falloff : hint_range(0.5, 16.0) = 4.0;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float s = length(MODEL_MATRIX[0].xyz);
	center.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * center;
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float win = clamp(1.0 - r * r, 0.0, 1.0);
	float g = exp(-max(r - core, 0.0) * falloff) * win * win;
	float c = smoothstep(core * 1.6, core * 0.4, r);
	ALBEDO = (glow_color * g + vec3(c) * 1.5) * intensity;
}
