shader_type spatial;
// Mãe-Gelo's coma (scenes/menu/props/comet_mae_gelo.tscn > Coma): the glowing cloud round the
// nucleus. A camera-facing QuadMesh of size (2, 2); the node scale is the radius. The glow is
// not round: it bulges a little towards the Sun (a soft parabolic hood, local -X of the node)
// and stretches back into the tails (+X). Teal-green inside (the colour real comae get from
// carbon gas), sky blue outside, a white-hot heart, and a slow shimmer. `bands` posterises the
// falloff into soft storybook rings (0 = smooth). Additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.98, 0.9);
uniform vec3 inner_color : source_color = vec3(0.45, 1.0, 0.82);
uniform vec3 outer_color : source_color = vec3(0.3, 0.6, 1.0);
uniform float intensity : hint_range(0.0, 16.0) = 1.0;
// falloff of the cloud (higher = tighter) and size of the white heart (fraction of the radius)
uniform float falloff : hint_range(0.5, 16.0) = 3.4;
uniform float core : hint_range(0.0, 0.5) = 0.06;
uniform float core_strength : hint_range(0.0, 8.0) = 1.6;
// how much the cloud leans to the Sun (hood) and trails into the tail (stretch)
uniform float hood : hint_range(0.0, 1.0) = 0.35;
uniform float stretch : hint_range(0.0, 2.0) = 0.8;
uniform float bands : hint_range(0.0, 10.0) = 0.0;
uniform float shimmer : hint_range(0.0, 1.0) = 0.18;

varying vec2 v_tail;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1, 0)), f.x), mix(h12(i + vec2(0, 1)), h12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float s = length(MODEL_MATRIX[0].xyz);
	center.xy += VERTEX.xy * s;
	POSITION = PROJECTION_MATRIX * center;
	// the tail direction (node +X) as seen on screen; its length says how side-on we look
	vec3 tv = (VIEW_MATRIX * vec4(normalize(MODEL_MATRIX[0].xyz), 0.0)).xyz;
	v_tail = tv.xy;
}

float posterise(float v) {
	if (bands <= 0.0) {
		return v;
	}
	float x = v * bands;
	return (floor(x) + smoothstep(0.35, 0.65, fract(x))) / bands;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float side = clamp(length(v_tail), 0.0, 1.0);
	vec2 t = side > 1e-3 ? v_tail / length(v_tail) : vec2(1.0, 0.0);
	vec2 b = vec2(-t.y, t.x);
	float along = dot(p, t);    // + towards the tail
	float across = dot(p, b);
	// compress sunward (hood), stretch tailward
	float k = along > 0.0 ? 1.0 / (1.0 + stretch * side) : 1.0 + hood * 1.6 * side;
	float r = length(vec2(across, along * k));
	float win = clamp(1.0 - dot(p, p), 0.0, 1.0);
	float g = exp(-max(r - core, 0.0) * falloff) * win * win;
	if (shimmer > 0.0) {
		float a = atan(p.y, p.x);
		float sh = n2(vec2(a * 3.0, r * 4.0 - TIME * 0.25)) * 0.6 + n2(vec2(a * 7.0 + 3.0, r * 9.0 - TIME * 0.4)) * 0.4;
		g *= 1.0 - shimmer + shimmer * 2.0 * sh;
	}
	g = posterise(clamp(g, 0.0, 1.0));
	vec3 c = mix(outer_color, inner_color, smoothstep(0.05, 0.6, g));
	float heart = smoothstep(core * 1.8, core * 0.3, length(p - t * 0.0));
	ALBEDO = (c * g + core_color * heart * core_strength) * intensity;
}
