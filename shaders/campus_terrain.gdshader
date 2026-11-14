shader_type spatial;
// Campus ground (scenes/tycoon/campus.tscn: Plateau, Terrace, Steps, Cliff, Beach). World-space,
// so the box meshes need no UVs:
//   top faces   grass in voxel-sized cells (cell_size) with lush / dry / clover patches at
//               two scales, a little per-cell jitter like the voxel buildings, worn earth
//               patches, and optional mowing stripes (the campus gets tidier with the eras:
//               src/tycoon/campus.gd sets `tidy`).
//   side faces  layered earth and rock strata with a grass lip at the top edge.
// Set `rock_top` for surfaces that should read as rock / sand from above (cliff, beach).

group_uniforms grass;
uniform vec3 grass_a : source_color = vec3(0.235, 0.380, 0.255);
uniform vec3 grass_b : source_color = vec3(0.300, 0.450, 0.270);
uniform vec3 grass_dry : source_color = vec3(0.470, 0.470, 0.290);
uniform vec3 clover : source_color = vec3(0.180, 0.330, 0.240);
uniform vec3 earth : source_color = vec3(0.360, 0.290, 0.220);
// overall multiplier, e.g. darker for the lower terrace
uniform float brightness : hint_range(0.2, 2.0) = 1.0;
// grass cell size (m); the buildings use 0.1 m voxels, the ground a coarser pixel
uniform float cell_size : hint_range(0.05, 2.0) = 0.25;
uniform float jitter : hint_range(0.0, 0.5) = 0.07;
uniform float dry_amount : hint_range(0.0, 1.0) = 0.35;
uniform float earth_amount : hint_range(0.0, 1.0) = 0.12;
// 0 = wild meadow, 1 = mowed lawn with stripes
uniform float tidy : hint_range(0.0, 1.0) = 0.0;
uniform float stripe_width : hint_range(0.5, 10.0) = 3.0;

group_uniforms rock;
uniform bool rock_top = false;
uniform vec3 rock_a : source_color = vec3(0.150, 0.165, 0.190);
uniform vec3 rock_b : source_color = vec3(0.230, 0.220, 0.230);
uniform vec3 soil : source_color = vec3(0.290, 0.225, 0.170);
uniform float strata_scale : hint_range(0.1, 4.0) = 0.6;
// grass lip on the side faces: metres below this height are earth / rock
uniform float lip_height = 0.0;
uniform float lip_depth : hint_range(0.0, 2.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;

varying vec3 wpos;
varying vec3 wnrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 grass_color(vec2 p) {
	// sample at the cell centre: the ground reads in square "pixels" like the voxel props
	vec2 cell = floor(p / cell_size);
	vec2 c = (cell + 0.5) * cell_size;
	float big = fbm(c * 0.035);
	float mid = fbm(c * 0.16 + 4.0);
	float fine = vnoise(c * 0.9);
	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.7, big));
	col = mix(col, clover, smoothstep(0.62, 0.78, mid) * 0.7);
	col = mix(col, grass_dry, smoothstep(0.55, 0.85, big * 0.6 + fine * 0.4) * dry_amount * (1.0 - tidy * 0.7));
	float bare = smoothstep(0.80, 0.92, fbm(c * 0.09 + 21.0)) * earth_amount * (1.0 - tidy);
	col = mix(col, earth, bare);
	// mowing stripes (diagonal to the camera's usual view)
	float st = step(0.5, fract((c.x + c.y * 0.35) / (stripe_width * 2.0)));
	col *= 1.0 + (st - 0.5) * 0.10 * tidy;
	col *= 1.0 + (hash12(cell + 17.0) - 0.5) * jitter * 2.0;
	return col;
}

vec3 rock_color(vec3 p, vec3 n) {
	float along = abs(n.x) > abs(n.z) ? p.z : p.x;
	float band = p.y * strata_scale + fbm(vec2(along * 0.08, p.y * 0.3)) * 1.6;
	float layer = floor(band);
	float h = hash12(vec2(layer, 3.0));
	vec3 col = mix(rock_a, rock_b, h);
	// blocky voxel cracks
	vec2 cell = floor(vec2(along, p.y) / (cell_size * 2.0));
	col *= 1.0 + (hash12(cell) - 0.5) * jitter * 3.0;
	col *= 0.85 + 0.15 * smoothstep(0.0, 0.15, fract(band));
	return col;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 col;
	if (n.y > 0.5) {
		col = rock_top ? rock_color(wpos, vec3(1.0, 0.0, 0.0)) : grass_color(wpos.xz);
	} else {
		col = rock_color(wpos, n);
		// earth band, then a grass lip along the top edge
		float depth = lip_height - wpos.y;
		float soil_band = 1.0 - smoothstep(lip_depth, lip_depth + 0.9 + vnoise(wpos.xz * 0.7) * 0.6, depth);
		col = mix(col, soil, soil_band);
		float lip = 1.0 - smoothstep(lip_depth * 0.6, lip_depth, depth + vnoise(wpos.xz * 2.1) * 0.12);
		if (!rock_top) {
			col = mix(col, grass_a * 0.85, lip);
		}
	}
	ALBEDO = col * brightness;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
}
