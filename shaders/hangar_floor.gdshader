shader_type spatial;
// Hangar floor: light polished concrete slabs (expansion joints, soft mottling, a
// slight sheen) with a painted measurement grid (1 m cells, stronger every 5 m) that
// fades out with distance from the launch platform. Colours follow the MARGIN palette
// (docs/art/palette.md). The grid is paint (darker albedo); line_glow / major_glow only
// add an optional faint emission on top.

uniform vec4 base_color : source_color = vec4(0.62, 0.64, 0.66, 1.0);
uniform vec4 line_color : source_color = vec4(0.42, 0.45, 0.49, 1.0);
uniform vec4 major_color : source_color = vec4(0.30, 0.33, 0.37, 1.0);
uniform float cell_size = 1.0;
uniform float major_every = 5.0;
uniform float line_glow = 0.0;
uniform float major_glow = 0.0;
uniform float fade_start = 18.0;
uniform float fade_end = 70.0;
// concrete slabs
uniform float slab_size = 6.0;
uniform vec4 joint_color : source_color = vec4(0.40, 0.42, 0.45, 1.0);
uniform float mottling = 0.06;
uniform float roughness_base = 0.38;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float width_px) {
	vec2 g = abs(fract(p - 0.5) - 0.5) / (fwidth(p) * width_px);
	return 1.0 - min(min(g.x, g.y), 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 xz = world_pos.xz;
	float dist = length(xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	vec2 p = xz / cell_size;
	float minor = grid_line(p, 1.0) * 0.55;
	float major = grid_line(p / major_every, 1.6);
	float joint = grid_line(xz / slab_size, 1.2);
	// per-slab tone + large-scale mottling (troweled concrete)
	vec2 slab = floor(xz / slab_size);
	float tone = (hash(slab) - 0.5) * 0.05;
	float mot = (vnoise(xz * 0.35) * 0.6 + vnoise(xz * 1.7) * 0.4 - 0.5) * mottling;
	vec3 col = base_color.rgb * (1.0 + tone + mot);
	col = mix(col, joint_color.rgb, joint * 0.8);
	col = mix(col, line_color.rgb, minor * fade);
	col = mix(col, major_color.rgb, major * fade);
	ALBEDO = col;
	ROUGHNESS = roughness_base + vnoise(xz * 0.8) * 0.18 + joint * 0.3;
	METALLIC = 0.0;
	SPECULAR = 0.45;
	EMISSION = (line_color.rgb * minor * line_glow + major_color.rgb * major * major_glow) * fade;
}
