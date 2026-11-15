shader_type spatial;
// Voxel terrain material (one material for every chunk).
// Vertex colors already hold palette color x baked AO (VoxelGreedyMesher); this
// adds the subtle per-voxel color jitter of tools/voxel_gen.py by hashing the
// world-space voxel cell, so greedy-merged quads still look per-voxel.
// Lit by the Cometworks toon light (shaders/include/cw_toon.gdshaderinc) like the rest of the
// game: banded faces and tinted, filled shadows (no rim: far terrain stays calm).
render_mode cull_back;

#define CW_TOON_RIM_DEFAULT 0.0
#include "res://shaders/include/cw_toon.gdshaderinc"

instance uniform float voxel_size = 1.0;
instance uniform float lod_level = 0.0;

uniform float jitter_amount : hint_range(0.0, 0.3) = 0.07;
// Extra jitter of the hue (very small) for less flat colors.
uniform float hue_jitter : hint_range(0.0, 0.1) = 0.012;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.86;
uniform float specular_value : hint_range(0.0, 1.0) = 0.25;
// Thin darker voxel edges (0 = off) for crisp voxel readability up close.
uniform float edge_darkening : hint_range(0.0, 0.5) = 0.10;
uniform float edge_fade_distance = 120.0;
// Debug: tint chunks by LOD level.
uniform bool debug_lod = false;

varying vec3 v_world;
varying vec3 v_wnormal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float s = max(voxel_size, 0.001);
	vec3 inside = v_world - v_wnormal * (0.5 * s);
	vec3 cell = floor(inside / s + 1e-4);
	float h = hash13(cell);
	float j = 1.0 + (h - 0.5) * jitter_amount;
	vec3 col = COLOR.rgb * j;
	float hj = (hash13(cell + 17.0) - 0.5) * hue_jitter;
	col *= vec3(1.0 + hj, 1.0, 1.0 - hj);

	// voxel edge darkening: distance to the cell border within the face plane
	if (edge_darkening > 0.0) {
		vec3 f = fract(inside / s);
		vec3 e = min(f, 1.0 - f);
		vec3 an = abs(v_wnormal);
		float d = an.x > 0.5 ? min(e.y, e.z) : (an.y > 0.5 ? min(e.x, e.z) : min(e.x, e.y));
		// voxel size in pixels: lines fade out before they can alias (moire)
		vec3 fw = fwidth(inside) / s;
		float px = max(max(fw.x, fw.y), fw.z);
		float line = 1.0 - smoothstep(0.0, max(px * 1.2, 0.03), d);
		float fade = (1.0 - smoothstep(0.06, 0.14, px)) * (1.0 - smoothstep(edge_fade_distance * 0.6, edge_fade_distance, length(VERTEX)));
		col *= 1.0 - edge_darkening * line * fade;
	}

	if (debug_lod) {
		vec3 lc = 0.5 + 0.5 * cos(6.2831 * (lod_level * 0.17 + vec3(0.0, 0.33, 0.67)));
		col = mix(col, lc * 0.6, 0.55);
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
