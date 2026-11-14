shader_type spatial;
// Ground of the launch site outside the hangar door: voxel-pixel grass (square cells in
// a few greens, like the voxel parts), a sandy beach and the ocean, split by the same
// coastline function used by tools/build_vab_scene.py for the voxel terrain blocks
// (s = dot(p - coast_origin, coast_normal) + two sine wiggles along the coast).

uniform vec2 coast_origin = vec2(350.0, -200.0);
uniform vec2 coast_normal = vec2(0.894, -0.447);
uniform vec2 coast_dir = vec2(-0.447, -0.894);
uniform float beach_width = 45.0;
uniform vec4 grass_a : source_color = vec4(0.49, 0.67, 0.35, 1.0);
uniform vec4 grass_b : source_color = vec4(0.42, 0.60, 0.31, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.64, 0.68, 0.42, 1.0);
uniform vec4 sand_color : source_color = vec4(0.86, 0.80, 0.64, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.33, 0.70, 0.74, 1.0);
uniform vec4 deep_color : source_color = vec4(0.10, 0.33, 0.52, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.97, 0.98, 1.0);
uniform float cell = 6.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float coast(vec2 p) {
	float t = dot(p, coast_dir);
	return dot(p - coast_origin, coast_normal) + 40.0 * sin(t * 0.004) + 25.0 * sin(t * 0.011 + 1.3);
}

void fragment() {
	vec2 p = wpos.xz;
	float s = coast(p);
	float px = length(fwidth(p));             // metres per pixel
	float detail = 1.0 - smoothstep(cell * 0.35, cell * 1.2, px);
	// grass: per-cell colour, larger patches of darker / dry grass
	vec2 id = floor(p / cell);
	float h = hash(id);
	float patches = vnoise(p * 0.012);
	float dry = smoothstep(0.62, 0.8, vnoise(p * 0.006 + 7.0)) * 0.55;
	vec3 g_avg = mix(mix(grass_a.rgb, grass_b.rgb, 0.5), grass_dry.rgb, dry);
	vec3 g = mix(grass_a.rgb, grass_b.rgb, step(0.5, h));
	g *= 0.94 + 0.12 * fract(h * 7.3);
	g = mix(g, grass_b.rgb * 0.85, smoothstep(0.55, 0.75, patches) * 0.6);
	g = mix(g, grass_dry.rgb, dry);
	g = mix(g_avg, g, detail);
	vec3 col = g;
	float rough = 0.92;
	float spec = 0.3;
	vec3 nrm = NORMAL;
	if (s > -beach_width) {
		float sand_n = 0.95 + 0.08 * hash(floor(p / 3.0)) * detail;
		vec3 sand = sand_color.rgb * sand_n;
		float wet = smoothstep(-12.0, 0.0, s);
		sand = mix(sand, sand_color.rgb * 0.72, wet);
		col = mix(g, sand, smoothstep(-beach_width, -beach_width + 6.0, s));
	}
	if (s > 0.0) {
		float depth = smoothstep(0.0, 160.0, s);
		vec3 w = mix(shallow_color.rgb, deep_color.rgb, depth);
		float waves = vnoise(p * 0.08 + TIME * 0.05) * 0.6 + vnoise(p * 0.31 - TIME * 0.08) * 0.4;
		float foam = (1.0 - smoothstep(0.0, 7.0, s)) * (0.6 + 0.4 * sin(s * 1.4 - TIME * 1.3));
		w = mix(w, foam_color.rgb, clamp(foam, 0.0, 1.0) * 0.85);
		col = w;
		rough = mix(0.06, 0.22, waves * detail);
		spec = 0.6;
		vec2 e = vec2(1.5, 0.0);
		float hx = vnoise((p + e.xy) * 0.31 - TIME * 0.08) - vnoise((p - e.xy) * 0.31 - TIME * 0.08);
		float hz = vnoise((p + e.yx) * 0.31 - TIME * 0.08) - vnoise((p - e.yx) * 0.31 - TIME * 0.08);
		vec3 wn = normalize(vec3(-hx * 0.25 * detail, 1.0, -hz * 0.25 * detail));
		nrm = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	NORMAL = nrm;
}
