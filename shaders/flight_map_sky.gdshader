shader_type sky;
// Map view star sky (the look of solar_sky / flight_sky's space background), split for
// speed: the Milky Way, dust lanes and nebulae (four fBm lookups per pixel) are computed
// in the quarter-resolution pass, the sharp stars at full resolution. The radiance map
// is static (no per-frame uniforms), so it is filtered once.
render_mode use_quarter_res_pass;

uniform float star_brightness = 2.0;
uniform float milky_way = 0.7;
uniform vec3 galactic_pole = vec3(0.38, 0.86, -0.34);
uniform vec3 space_color : source_color = vec3(0.003, 0.004, 0.009);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

vec3 star_color(float t) {
	vec3 c = mix(vec3(1.0, 0.62, 0.38), vec3(1.0, 0.9, 0.75), smoothstep(0.0, 0.3, t));
	c = mix(c, vec3(0.95, 0.97, 1.0), smoothstep(0.3, 0.6, t));
	return mix(c, vec3(0.62, 0.75, 1.0), smoothstep(0.65, 1.0, t));
}

vec3 star_layer(vec3 dir, float scale, float keep, float size, float boost) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = p - cell;
	float h = hash13(cell + 0.5);
	if (h < keep) {
		return vec3(0.0);
	}
	vec3 sp = 0.3 + 0.4 * hash33(cell * 1.31 + 7.0);
	float d = length(f - sp);
	float b = pow((h - keep) / (1.0 - keep), 2.2);
	float core = smoothstep(size, 0.0, d);
	float halo = exp(-d / size * 2.2) * 0.25 * b;
	return star_color(hash13(cell + 3.7)) * (core * core + halo) * b * boost;
}

vec3 galaxy(vec3 dir) {
	vec3 gp = normalize(galactic_pole);
	float g = dot(dir, gp);
	float band = exp(-g * g / 0.035);
	float wide = exp(-g * g / 0.16);
	float n1 = fbm3(dir * 3.0 + 4.0);
	float n2 = fbm3(dir * 9.0 + 1.3);
	float dust = smoothstep(0.42, 0.68, fbm3(dir * 6.0 + 11.0)) * exp(-g * g / 0.008);
	float mw = (band * (0.55 + 0.9 * n1 * n2) + wide * 0.25 * n1) * (1.0 - 0.75 * dust);
	vec3 col = mix(vec3(0.16, 0.17, 0.27), vec3(0.34, 0.29, 0.25), n2) * mw * milky_way * 0.2;
	float neb = smoothstep(0.55, 0.85, fbm3(dir * 2.2 + 21.0));
	col += vec3(0.2, 0.06, 0.26) * neb * 0.045;
	col += vec3(0.05, 0.09, 0.16) * smoothstep(0.6, 0.9, n1) * wide * 0.06;
	return col;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	if (AT_CUBEMAP_PASS) {
		COLOR = space_color + galaxy(dir) * 0.5;
	} else if (AT_QUARTER_RES_PASS) {
		COLOR = galaxy(dir);
		ALPHA = 1.0;
	} else {
		float band = exp(-pow(dot(dir, normalize(galactic_pole)), 2.0) / 0.035);
		float dens = band * 0.04;
		vec3 s = star_layer(dir, 70.0, 0.965 - dens, 0.16, 1.6);
		s += star_layer(dir, 150.0, 0.95 - dens, 0.2, 0.9);
		s += star_layer(dir, 320.0, 0.9 - dens * 2.0, 0.26, 0.45);
		COLOR = space_color + QUARTER_RES_COLOR.rgb + s * star_brightness;
	}
}
