shader_type spatial;
// Smoke / steam puff billboard for FlightSmoke (MultiMesh). INSTANCE_CUSTOM:
// r = opacity, g = age fraction, b = tint (0 white steam .. 1 grey exhaust), a = variation.
// Soft lighting: puffs facing the sun are bright, the rest take the sky ambient; young puffs
// glow with the engine's fire.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 sun_dir = vec3(0.6, 0.5, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.86, 1.0);
uniform vec4 shade_color : source_color = vec4(0.55, 0.62, 0.74, 1.0);
uniform vec4 fire_color : source_color = vec4(1.0, 0.62, 0.28, 1.0);
uniform float brightness = 1.0;

varying vec4 custom;
varying vec3 vdir;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	custom = INSTANCE_CUSTOM;
	float s = length(MODEL_MATRIX[0].xyz);
	// camera-facing billboard keeping the instance scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vdir = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float vr = custom.a;
	float r = length(uv);
	// lumpy edge
	float ang = atan(uv.y, uv.x);
	float lump = 0.82 + 0.18 * vnoise(vec2(ang * 2.2 + vr * 31.0, vr * 7.0 + custom.g * 2.0));
	float m = 1.0 - smoothstep(lump * 0.55, lump, r);
	float n = vnoise(uv * 3.0 + vr * 17.0) * 0.5 + vnoise(uv * 7.0 - vr * 9.0) * 0.5;
	m *= 0.65 + 0.35 * n;
	// pseudo-sphere normal for lighting
	vec3 nrm = normalize(vec3(uv * 0.9, sqrt(max(1.0 - r * r, 0.05))));
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float lit = clamp(dot(nw, normalize(sun_dir)) * 0.6 + 0.5, 0.0, 1.0);
	vec3 base = mix(vec3(0.97, 0.97, 0.96), vec3(0.62, 0.62, 0.64), custom.b);
	vec3 col = base * mix(shade_color.rgb, sun_color.rgb, lit) * brightness;
	col = mix(col, fire_color.rgb * 2.5, (1.0 - smoothstep(0.0, 0.08, custom.g)) * 0.6);
	ALBEDO = col;
	ALPHA = clamp(m * custom.r, 0.0, 1.0);
}
