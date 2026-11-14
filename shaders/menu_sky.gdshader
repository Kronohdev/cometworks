shader_type sky;
// Main-menu sky (scenes/menu/shots/*.tscn): a dusk / night gradient with a warm glow where
// the Sun went down, two layers of stars and the Cometlings' home comet Mae-Gelo with its
// aurora tail (teal -> violet -> orange). Every uniform is static, so the radiance map is
// filtered once; tweak the look per shot in the inspector (Environment > Sky > Material).

uniform vec3 zenith_color : source_color = vec3(0.016, 0.027, 0.078);
uniform vec3 mid_color : source_color = vec3(0.075, 0.09, 0.22);
uniform vec3 horizon_color : source_color = vec3(0.42, 0.28, 0.36);
uniform vec3 ground_color : source_color = vec3(0.015, 0.02, 0.035);
// height (EYEDIR.y) where the horizon colour has turned into mid_color
uniform float horizon_height : hint_range(0.01, 1.0) = 0.22;
// warm glow around the set Sun
uniform vec3 sun_dir = vec3(0.0, 0.02, -1.0);
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.22);
uniform float glow_strength : hint_range(0.0, 8.0) = 1.4;
uniform float glow_width : hint_range(0.02, 2.0) = 0.35;

uniform float star_brightness : hint_range(0.0, 8.0) = 1.4;
// stars appear above this height
uniform float star_horizon : hint_range(-0.2, 0.8) = 0.08;

// the comet: head direction, the direction its tail points to (away from the Sun)
uniform bool comet_enabled = true;
uniform vec3 comet_dir = vec3(-0.25, 0.5, -0.83);
uniform vec3 comet_tail_dir = vec3(0.9, 0.35, 0.0);
uniform float comet_length : hint_range(0.02, 2.0) = 0.6;
uniform float comet_width : hint_range(0.001, 0.1) = 0.010;
uniform float comet_curve : hint_range(-2.0, 2.0) = 0.35;
uniform float comet_brightness : hint_range(0.0, 8.0) = 1.6;
uniform vec3 aurora_teal : source_color = vec3(0.247, 0.878, 0.773);
uniform vec3 aurora_violet : source_color = vec3(0.557, 0.486, 1.0);
uniform vec3 ignition : source_color = vec3(1.0, 0.541, 0.239);

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

vec3 star_layer(vec3 dir, float scale, float keep, float size) {
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
	float t = (h - keep) / (1.0 - keep);
	vec3 c = mix(vec3(1.0, 0.82, 0.62), vec3(0.72, 0.84, 1.0), hash13(cell * 2.7 + 3.1));
	return c * b * (0.25 + 2.2 * t * t);
}

vec3 aurora(float s) {
	return s < 0.5 ? mix(aurora_teal, aurora_violet, s * 2.0) : mix(aurora_violet, ignition, s * 2.0 - 1.0);
}

// premultiplied colour (rgb) and coverage (a): the comet is composited "over" the sky, so its
// aurora colours stay saturated on bright dusk skies instead of washing out to white
vec4 comet(vec3 d) {
	vec3 c = normalize(comet_dir);
	vec3 t = normalize(comet_tail_dir - dot(comet_tail_dir, c) * c);
	vec3 b = cross(c, t);
	float z = dot(d, c);
	if (z <= 0.0) {
		return vec4(0.0);
	}
	float x = atan(dot(d, t), z);
	float y = atan(dot(d, b), z);
	float w = comet_width;
	float r2 = x * x + y * y;
	float head_a = exp(-r2 / (w * w * 0.12)) * 4.0 + exp(-r2 / (w * w * 2.5)) * 0.45;
	vec3 head = vec3(0.85, 0.96, 1.0);
	vec3 col = head * head_a;
	float a = head_a;
	if (x > 0.0) {
		float s = x / comet_length;
		float fade = pow(clamp(1.0 - s, 0.0, 1.0), 1.5);
		// ion tail: straight and narrow
		float w1 = w * (0.35 + s * 2.2);
		float ion = exp(-(y * y) / (w1 * w1)) * fade * 0.6;
		// dust tail: curved and wider
		float yc = y - comet_curve * x * x;
		float w2 = w * (0.6 + s * 6.0);
		float dust = exp(-(yc * yc) / (w2 * w2)) * fade * 0.85;
		col += ion * mix(head, mix(aurora_teal, aurora_violet, clamp(s * 1.5, 0.0, 1.0)), smoothstep(0.0, 0.12, s))
				+ dust * mix(head, aurora(clamp(s * 1.4, 0.0, 1.0)), smoothstep(0.0, 0.08, s));
		a += ion + dust;
	}
	return vec4(col * comet_brightness, clamp(a * comet_brightness, 0.0, 1.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = d.y;
	vec3 col;
	if (e >= 0.0) {
		col = mix(horizon_color, mid_color, smoothstep(0.0, horizon_height, e));
		col = mix(col, zenith_color, smoothstep(horizon_height * 0.7, 0.95, e));
	} else {
		col = mix(horizon_color * 0.55, ground_color, smoothstep(0.0, 0.12, -e));
	}
	vec3 sd = normalize(sun_dir);
	float g = exp((dot(d, sd) - 1.0) / glow_width) * exp(-abs(e) / (horizon_height * 0.9));
	col += glow_color * g * glow_strength;
	if (!AT_CUBEMAP_PASS) {
		float vis = smoothstep(star_horizon, star_horizon + 0.3, e) * (1.0 - clamp(g * 2.0, 0.0, 1.0));
		if (vis > 0.0) {
			vec3 s = star_layer(d, 240.0, 0.9, 0.11) + star_layer(d, 95.0, 0.965, 0.07) * 1.4;
			col += s * star_brightness * vis;
		}
	}
	if (comet_enabled) {
		vec4 cm = comet(d) * smoothstep(-0.02, 0.06, e);
		col = col * (1.0 - cm.a * 0.8) + cm.rgb;
	}
	COLOR = col;
}
