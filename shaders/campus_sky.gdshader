shader_type sky;
// Campus sky (scenes/tycoon/campus.tscn, Environment > Sky > Material): a dusk gradient with a
// warm band where the Sun is going down, two layers of twinkling stars, a faint aurora
// curtain (teal -> violet, the art direction's thread as a natural phenomenon), two layers of
// distant mountain silhouettes in the haze, a small moon, and the Cometlings' home comet
// Mae-Gelo with a glowing nucleus and green coma, a straight blue ion tail and a curved,
// golden dust tail fanned by fine rays.
// Everything lives at infinity, so the comet never clips or turns into a flat card.
// The radiance pass (AT_CUBEMAP_PASS) skips the fine detail; keep Sky.radiance_size small and
// process_mode Real-time so the slow aurora drift stays cheap.

group_uniforms gradient;
uniform vec3 zenith_color : source_color = vec3(0.020, 0.035, 0.100);
uniform vec3 mid_color : source_color = vec3(0.090, 0.110, 0.260);
uniform vec3 horizon_color : source_color = vec3(0.520, 0.360, 0.420);
uniform vec3 ground_color : source_color = vec3(0.020, 0.028, 0.050);
// height (EYEDIR.y) where the horizon colour has turned into mid_color
uniform float horizon_height : hint_range(0.01, 1.0) = 0.20;
// the side of the sky away from the Sun is cooler and darker by this much
uniform float anti_sun_cool : hint_range(0.0, 1.0) = 0.45;

group_uniforms sun;
// direction towards the (low) Sun; match the key DirectionalLight3D
uniform vec3 sun_dir = vec3(0.62, 0.30, -0.73);
uniform vec3 glow_color : source_color = vec3(1.0, 0.50, 0.24);
uniform float glow_strength : hint_range(0.0, 8.0) = 1.6;
uniform float glow_width : hint_range(0.02, 2.0) = 0.30;
// a tight hot core right around the Sun disc
uniform float sun_core : hint_range(0.0, 20.0) = 3.0;

group_uniforms stars;
uniform float star_brightness : hint_range(0.0, 8.0) = 1.5;
// stars appear above this height
uniform float star_horizon : hint_range(-0.2, 0.8) = 0.10;
uniform float twinkle : hint_range(0.0, 1.0) = 0.35;

group_uniforms aurora;
uniform float aurora_strength : hint_range(0.0, 4.0) = 0.55;
// azimuth (radians, 0 = -Z, positive towards +X) the curtain is centred on, and its spread
uniform float aurora_azimuth = -2.2;
uniform float aurora_spread : hint_range(0.1, 3.2) = 1.3;
uniform float aurora_low : hint_range(0.0, 1.0) = 0.12;
uniform float aurora_high : hint_range(0.0, 1.0) = 0.55;
uniform float aurora_speed : hint_range(0.0, 1.0) = 0.03;

group_uniforms mountains;
uniform bool mountains_enabled = true;
uniform vec3 far_range_color : source_color = vec3(0.20, 0.20, 0.33);
uniform vec3 near_range_color : source_color = vec3(0.07, 0.08, 0.15);
uniform float far_range_height : hint_range(0.0, 0.3) = 0.065;
uniform float near_range_height : hint_range(0.0, 0.3) = 0.040;

group_uniforms moon;
uniform vec3 moon_dir = vec3(-0.55, 0.45, 0.70);
uniform float moon_size : hint_range(0.001, 0.2) = 0.025;
uniform vec3 moon_color : source_color = vec3(0.86, 0.90, 1.0);
uniform float moon_brightness : hint_range(0.0, 8.0) = 2.2;

group_uniforms comet;
// the comet: head direction, the direction its tail points to (away from the Sun)
uniform bool comet_enabled = true;
uniform vec3 comet_dir = vec3(-0.50, 0.42, -0.76);
uniform vec3 comet_tail_dir = vec3(-0.85, 0.45, 0.25);
uniform float comet_length : hint_range(0.02, 2.0) = 0.62;
uniform float comet_width : hint_range(0.001, 0.1) = 0.012;
uniform float comet_curve : hint_range(-2.0, 2.0) = 0.45;
uniform float comet_brightness : hint_range(0.0, 8.0) = 1.7;
// fine streamers along the dust tail
uniform float comet_striae : hint_range(0.0, 1.0) = 0.45;
uniform vec3 aurora_teal : source_color = vec3(0.247, 0.878, 0.773);
uniform vec3 aurora_violet : source_color = vec3(0.557, 0.486, 1.0);
uniform vec3 ignition : source_color = vec3(1.0, 0.541, 0.239);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

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

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), u);
}

float fbm1(float x) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise1(x);
		x = x * 2.03 + 11.7;
		a *= 0.5;
	}
	return v;
}

vec3 star_layer(vec3 dir, float scale, float keep, float size, float t) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = p - cell;
	float h = hash13(cell + 0.5);
	if (h < keep) {
		return vec3(0.0);
	}
	vec3 sp = 0.25 + 0.5 * hash33(cell * 1.31 + 7.0);
	float d = length(f - sp);
	float b = smoothstep(size, 0.0, d);
	float k = (h - keep) / (1.0 - keep);
	vec3 c = mix(vec3(1.0, 0.82, 0.62), vec3(0.72, 0.84, 1.0), hash13(cell * 2.7 + 3.1));
	float tw = 1.0 - twinkle * (0.5 + 0.5 * sin(t * (1.5 + 3.0 * h) + h * 40.0));
	return c * b * (0.25 + 2.2 * k * k) * tw;
}

vec3 aurora_ramp(float s) {
	return s < 0.5 ? mix(aurora_teal, aurora_violet, s * 2.0) : mix(aurora_violet, ignition, s * 2.0 - 1.0);
}

#include "res://shaders/include/cw_sky_comet.gdshaderinc"

// height of a mountain range at azimuth az (radians)
float range_height(float az, float seed, float h) {
	float r = fbm1(az * 4.0 + seed) * 0.75 + fbm1(az * 13.0 + seed * 3.1) * 0.25;
	return h * (0.25 + 1.1 * r * r);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = d.y;
	float az = atan(d.x, -d.z);
	vec3 sd = normalize(sun_dir);
	// how much this part of the sky faces the Sun (0 = opposite side)
	vec2 hz = normalize(d.xz + vec2(1e-5));
	vec2 shz = normalize(sd.xz + vec2(1e-5));
	float facing = dot(hz, shz) * 0.5 + 0.5;
	vec3 hcol = mix(mix(horizon_color, mid_color * 1.3, anti_sun_cool), horizon_color, smoothstep(0.1, 0.9, facing));
	vec3 col;
	if (e >= 0.0) {
		col = mix(hcol, mid_color, smoothstep(0.0, horizon_height, e));
		col = mix(col, zenith_color, smoothstep(horizon_height * 0.7, 0.95, e));
	} else {
		col = mix(hcol * 0.55, ground_color, smoothstep(0.0, 0.12, -e));
	}
	float g = exp((dot(d, sd) - 1.0) / glow_width) * exp(-abs(e - max(sd.y, 0.0) * 0.4) / (horizon_height * 0.9));
	col += glow_color * g * glow_strength;
	col += glow_color * exp((dot(d, sd) - 1.0) / 0.004) * sun_core;
	bool detail = !AT_CUBEMAP_PASS;
	if (detail) {
		float vis = smoothstep(star_horizon, star_horizon + 0.3, e) * (1.0 - clamp(g * 2.0, 0.0, 1.0));
		if (vis > 0.0) {
			vec3 s = star_layer(d, 240.0, 0.9, 0.11, TIME) + star_layer(d, 95.0, 0.965, 0.07, TIME * 0.7) * 1.4;
			col += s * star_brightness * vis;
		}
	}
	// aurora curtain: vertical rays, slowly drifting folds, teal at the foot, violet above
	if (aurora_strength > 0.0 && e > 0.0) {
		float da = az - aurora_azimuth;
		da = mod(da + PI, TAU) - PI;
		float band = exp(-da * da / (aurora_spread * aurora_spread));
		float fold = sin(az * 3.0 + TIME * aurora_speed * 6.0 + 2.0 * sin(az * 1.7 - TIME * aurora_speed * 3.0));
		float foot = aurora_low + 0.05 * fold;
		float hgt = (e - foot) / max(aurora_high - foot, 0.01);
		float v = smoothstep(0.0, 0.08, hgt) * exp(-max(hgt, 0.0) * 2.4) * step(0.0, hgt);
		float rays = 1.0;
		if (detail) {
			rays = 0.45 + 0.55 * fbm1(az * 60.0 + TIME * aurora_speed * 20.0);
			rays *= 0.7 + 0.3 * fbm1(az * 7.0 - TIME * aurora_speed * 9.0);
		}
		vec3 ac = mix(aurora_teal, aurora_violet, smoothstep(0.05, 0.8, hgt));
		col += ac * v * band * rays * aurora_strength * smoothstep(0.0, 0.15, e);
	}
	// moon
	vec3 md = normalize(moon_dir);
	float mdot = dot(d, md);
	if (mdot > 0.9) {
		float r = sqrt(max(0.0, 2.0 - 2.0 * mdot));
		float disc = smoothstep(moon_size, moon_size * 0.92, r);
		float mare = 0.82 + 0.18 * hash13(floor(d * 900.0));
		col = mix(col, moon_color * moon_brightness * mare, disc);
		col += moon_color * exp(-r / (moon_size * 2.5)) * 0.12 * moon_brightness;
	}
	if (comet_enabled) {
		vec4 cm = comet(d, detail) * smoothstep(-0.02, 0.06, e);
		col = col * (1.0 - cm.a * 0.8) + cm.rgb;
	}
	// distant ranges in the haze, in front of everything but the ground
	if (mountains_enabled && e > -0.05) {
		float hf = range_height(az, 3.0, far_range_height);
		float hn = range_height(az + 1.3, 17.0, near_range_height);
		vec3 haze = mix(hcol, far_range_color, 0.75);
		float lit = smoothstep(0.2, 1.0, facing);
		vec3 far_c = mix(far_range_color, far_range_color + glow_color * 0.06, lit);
		if (e < hf) {
			col = mix(far_c, haze, smoothstep(hf - 0.03, hf, e) * 0.35);
		}
		if (e < hn) {
			col = mix(near_range_color, near_range_color * 1.4, smoothstep(hn - 0.04, hn, e) * lit);
		}
	}
	COLOR = col;
}
