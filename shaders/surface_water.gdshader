shader_type spatial;
// Sea / lake surface (Earth ocean, Titan methane lakes). A large plane that
// follows the camera; all patterns are in world space so it never swims.
// Color by water depth (depth buffer), fresnel toward the sky, animated
// normals, shoreline foam with voxel-sized steps to match the terrain look.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.16, 0.55, 0.6);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.24);
uniform float depth_scale = 6.0;
uniform float clarity = 2.5;
uniform float foam_width = 0.9;
uniform vec3 foam_color : source_color = vec3(0.9, 0.95, 0.97);
uniform float wave_strength = 0.35;
uniform float wave_speed = 0.6;
uniform float roughness_value = 0.06;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 v_world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float waves(vec2 p, float t) {
	float h = 0.0;
	h += vnoise(p * 0.18 + vec2(t * 0.30, t * 0.11)) * 0.55;
	h += vnoise(p * 0.47 - vec2(t * 0.21, -t * 0.33)) * 0.30;
	h += vnoise(p * 1.30 + vec2(-t * 0.5, t * 0.4)) * 0.15;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = v_world.xz;
	float e = 0.25;
	float h0 = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	vec3 n_world = normalize(vec3(-(hx - h0) / e * wave_strength, 1.0, -(hz - h0) / e * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float water_depth = max(-view.z - (-VERTEX.z), 0.0);
	// vertical depth approximation (view ray is slanted)
	float k = clamp(dot(normalize(-VERTEX), mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0)), 0.15, 1.0);
	float vd = water_depth * k;

	float tdeep = 1.0 - exp(-vd / depth_scale);
	vec3 col = mix(shallow_color, deep_color, tdeep);
	float foam = 1.0 - smoothstep(0.0, foam_width, vd + (h0 - 0.5) * 0.6);
	foam *= step(0.45, vnoise(floor(p * 1.0) + floor(t * 2.0)) * 0.6 + 0.4);
	col = mix(col, foam_color, foam * 0.85);
	ALBEDO = col;
	ALPHA = clamp(1.0 - exp(-vd / clarity) + foam * 0.6, 0.0, 0.97);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
