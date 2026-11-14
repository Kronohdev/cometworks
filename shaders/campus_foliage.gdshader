shader_type spatial;
// Trees, bushes, grass and flowers of the campus (assets/campus/nature/*.res in
// MultiMeshInstance3D nodes, scenes/tycoon/campus.tscn: Nature). Same vertex colours as the
// voxel buildings (shaders/campus_voxel.gdshader: palette colour * baked AO, alpha < 1 =
// glow) plus a gentle wind sway that grows with height, phased by world position so a
// meadow ripples instead of nodding in unison. A MultiMesh with use_colors tints each
// instance (Godot multiplies the instance colour into COLOR; keep its alpha at 1).
// Lighting: the Cometworks toon light (shaders/include/cw_toon.gdshaderinc); BACKLIGHT keeps
// the leaves' translucency in both styles.
#include "res://shaders/include/cw_toon.gdshaderinc"

uniform float jitter = 0.06;
uniform float voxels_per_metre = 5.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float glow_scale = 8.0;
// wind: sway amplitude (m at 1 m height), frequency, gust scale
uniform float sway : hint_range(0.0, 0.5) = 0.06;
uniform float sway_speed : hint_range(0.0, 6.0) = 1.3;
uniform float sway_height : hint_range(0.1, 10.0) = 2.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);
// translucency: a little light through the leaves when back-lit by the low sun
uniform float backlight : hint_range(0.0, 1.0) = 0.25;

varying vec3 model_pos;
varying vec3 model_nrm;

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	model_pos = VERTEX;
	model_nrm = NORMAL;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0) / sway_height;
	float bend = h * h;
	float t = TIME * sway_speed + dot(origin.xz, vec2(0.13, 0.17));
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + origin.x * 0.02);
	vec2 w = normalize(wind_dir) * (sin(t) * 0.7 + sin(t * 2.3 + 1.7) * 0.3) * sway * gust * bend;
	// sway in world space, converted back to model space
	vec3 off = (inverse(mat3(MODEL_MATRIX)) * vec3(w.x, 0.0, w.y));
	VERTEX += off;
}

void fragment() {
	vec3 cell = floor(model_pos * voxels_per_metre - model_nrm * 0.5 + vec3(1e-3));
	float h = hash3(cell + vec3(17.0));
	float glow = (1.0 - COLOR.a) * glow_scale;
	ALBEDO = COLOR.rgb * (1.0 + (h - 0.5) * jitter);
	ROUGHNESS = roughness_value;
	BACKLIGHT = vec3(backlight) * COLOR.rgb;
	EMISSION = COLOR.rgb * glow + cw_toon_rim(NORMAL, VIEW, ALBEDO, VERTEX, INV_VIEW_MATRIX);
}
