// Mãe-Gelo in a sky shader (shaders/campus_sky.gdshader, shaders/menu_sky.gdshader): include it
// after the shader's own comet uniforms (comet_dir, comet_tail_dir, comet_length, comet_width,
// comet_curve, comet_brightness, comet_striae) and composite comet(d, detail) over the sky:
//   vec4 cm = comet(d, !AT_CUBEMAP_PASS);  col = col * (1.0 - cm.a * 0.8) + cm.rgb;
// It brings the comet's colours as uniforms of their own (same names in both skies).
// #define CW_SKY_COMET_STATIC before the include keeps TIME out (a sky whose radiance is
// filtered once, like the menu's): the comet then stands still.
#ifdef CW_SKY_COMET_STATIC
#define CW_COMET_TIME 0.0
#else
#define CW_COMET_TIME TIME
#endif

uniform vec3 comet_head_color : source_color = vec3(0.92, 0.98, 1.0);
uniform vec3 comet_coma_color : source_color = vec3(0.45, 1.0, 0.85);
uniform vec3 comet_dust_color : source_color = vec3(1.0, 0.9, 0.62);
uniform vec3 comet_dust_far : source_color = vec3(1.0, 0.62, 0.36);
uniform vec3 comet_ion_color : source_color = vec3(0.45, 0.8, 1.0);
uniform vec3 comet_ion_far : source_color = vec3(0.32, 0.42, 1.0);
// the little four-point twinkle on the head
uniform float comet_sparkle : hint_range(0.0, 2.0) = 0.8;

// premultiplied colour (rgb) and coverage (a): the comet is composited "over" the sky, so its
// colours stay saturated on bright dusk skies instead of washing out to white.
// Mãe-Gelo as the campus sees her: a white-hot head with a little four-point twinkle, a
// teal-green coma leaning to the Sun, a straight blue ion tail of fine streamers and a wide,
// curved, creamy-gold dust tail fanned by synchrone rays and brighter on its outer edge.
// comet_length and comet_brightness grow era after era (CampusWeather drives them).
vec4 comet(vec3 d, bool detail) {
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
	// coma: compressed towards the Sun (x < 0), a hot point in the middle
	float xh = x < 0.0 ? x * 1.6 : x * 0.75;
	float r2 = xh * xh + y * y;
	float point = exp(-(x * x + y * y) / (w * w * 0.05));
	float coma = exp(-r2 / (w * w * 1.1)) * 0.9 + exp(-r2 / (w * w * 9.0)) * 0.22;
	vec3 col = comet_head_color * point * 5.0 + mix(comet_coma_color, comet_head_color, clamp(point * 2.0, 0.0, 1.0)) * coma;
	float a = point * 5.0 + coma;
	if (detail && comet_sparkle > 0.0) {
		// a soft four-point twinkle on the head (rotated with the tail, so it reads as a star)
		float ax = abs(x) / w;
		float ay = abs(y) / w;
		float tw = 0.75 + 0.25 * sin(CW_COMET_TIME * 1.7);
		float cross_ = (exp(-ay * 9.0) * exp(-ax * 0.9) + exp(-ax * 9.0) * exp(-ay * 0.9)) * tw * comet_sparkle;
		col += comet_head_color * cross_ * 0.7;
		a += cross_ * 0.5;
	}
	if (x > -w) {
		float xs = max(x, 0.0);
		float s = xs / comet_length;
		float fade = pow(clamp(1.0 - s, 0.0, 1.0), 1.3) * smoothstep(-w, w * 2.5, x);
		// ion tail: straight, narrow, blue, a little longer than the dust tail
		float si = xs / (comet_length * 1.15);
		float fi = pow(clamp(1.0 - si, 0.0, 1.0), 1.1) * smoothstep(-w, w * 2.5, x);
		float yi = y - 0.015 * sin(xs * 7.0 - CW_COMET_TIME * 0.2) * si;
		float w1 = w * (0.28 + si * 1.6);
		float ion = exp(-(yi * yi) / (w1 * w1)) * fi * 0.8;
		if (detail) {
			float st = 0.55 + 0.45 * sin(yi / w1 * 5.0 + xs * 2.0) * sin(yi / w1 * 2.3 - xs * 30.0 + CW_COMET_TIME * 0.6);
			ion *= mix(1.0, st, smoothstep(0.05, 0.3, si) * 0.8);
		}
		// dust tail: curved, wide, warm, brighter along its outer (leading) edge
		float yc = y - comet_curve * xs * xs;
		float w2 = w * (0.55 + s * 6.5);
		float across = yc / w2;
		float dust = exp(-across * across) * fade * 0.85;
		float lead = -sign(comet_curve) * across;
		dust *= 1.0 + 0.7 * smoothstep(-0.2, 0.9, lead) * smoothstep(1.7, 0.6, abs(across));
		if (detail) {
			float ang = yc / max(xs + w * 2.0, 1e-4);
			float st = 0.62 + 0.38 * sin(ang * 70.0 + sin(ang * 23.0) * 2.0);
			dust *= mix(1.0, st, comet_striae * smoothstep(0.05, 0.35, s));
		}
		vec3 dust_c = s < 0.45 ? mix(comet_dust_color, comet_dust_far, s / 0.45 * 0.5) : mix(mix(comet_dust_color, comet_dust_far, 0.5), comet_dust_far, (s - 0.45) / 0.55);
		vec3 ion_c = mix(comet_ion_color, comet_ion_far, clamp(si * 1.4, 0.0, 1.0));
		col += ion * mix(comet_head_color, ion_c, smoothstep(0.0, 0.08, si))
				+ dust * mix(comet_head_color, dust_c, smoothstep(0.0, 0.07, s));
		a += ion + dust;
	}
	return vec4(col * comet_brightness, clamp(a * comet_brightness, 0.0, 1.0));
}

