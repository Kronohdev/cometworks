shader_type spatial;
// Material for greedy-meshed voxel parts (tools/voxel_gen.py mesh_greedy):
// vertex COLOR carries the palette color with baked ambient occlusion, UV holds the
// voxel coordinates on the face plane and UV2 = (slice, face id), so the subtle
// per-voxel brightness jitter is reconstructed here even on merged quads.
// Lighting: the Cometworks toon light (shaders/include/cw_toon.gdshaderinc).

#include "res://shaders/include/cw_toon.gdshaderinc"

uniform float jitter = 0.07;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec2 cell = floor(UV + vec2(1e-3));
	float h = hash3(vec3(cell, UV2.x * 7.0 + UV2.y * 131.0));
	ALBEDO = COLOR.rgb * (1.0 + (h - 0.5) * jitter);
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	EMISSION = cw_toon_rim(NORMAL, VIEW, ALBEDO, VERTEX, INV_VIEW_MATRIX);
}
