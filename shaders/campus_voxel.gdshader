shader_type spatial;
// Material of the campus buildings (tools/build_campus_buildings.py, tools/campus_voxel.py):
// vertex COLOR = palette colour with baked ambient occlusion (linear); vertex alpha < 1
// marks emissive voxels (windows, screens, bulbs): emission = colour * (1 - alpha) * 8.
// A subtle per-voxel brightness jitter is rebuilt from the model-space position so merged
// quads still read as 10 cm voxels.

uniform float jitter = 0.06;
uniform float voxels_per_metre = 10.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.86;
uniform float glow_scale = 8.0;
uniform float glow_gain : hint_range(0.0, 4.0) = 1.0;

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
}

void fragment() {
	vec3 cell = floor(model_pos * voxels_per_metre - model_nrm * 0.5 + vec3(1e-3));
	float h = hash3(cell + vec3(17.0));
	float glow = (1.0 - COLOR.a) * glow_scale;
	ALBEDO = COLOR.rgb * (1.0 + (h - 0.5) * jitter);
	ROUGHNESS = roughness_value;
	EMISSION = COLOR.rgb * glow * glow_gain * (1.0 + (h - 0.5) * 0.25);
}
