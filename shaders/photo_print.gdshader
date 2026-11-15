shader_type canvas_item;
// The look of a photo a probe sends home (scenes/tycoon/photos/photo_studio.tscn, over the
// rendered shot): a soft vignette, a little sensor grain, the camera's corner brackets and
// centre ticks, and for the infrared camera ("ir" = 1) false colours from the brightness.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette : hint_range(0.0, 1.5) = 0.55;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
uniform float ir : hint_range(0.0, 1.0) = 0.0;
uniform float grain_seed = 0.0;
uniform vec4 mark_color : source_color = vec4(0.92, 0.96, 1.0, 0.75);
uniform float mark_px = 1.5;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 ir_palette(float t) {
	// black-violet -> magenta -> orange -> butter -> white
	vec3 a = mix(vec3(0.05, 0.02, 0.15), vec3(0.55, 0.08, 0.55), smoothstep(0.0, 0.3, t));
	a = mix(a, vec3(0.98, 0.42, 0.16), smoothstep(0.25, 0.6, t));
	a = mix(a, vec3(1.0, 0.86, 0.35), smoothstep(0.55, 0.85, t));
	return mix(a, vec3(1.0), smoothstep(0.85, 1.0, t));
}

// distance-based line: 1 on a line `px` wide
float line_px(float d, float px) {
	return 1.0 - smoothstep(px * 0.5, px * 0.5 + 1.0, abs(d));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	if (ir > 0.5) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		c = ir_palette(clamp(pow(l, 0.8) * 1.15, 0.0, 1.0));
	}
	// vignette
	vec2 q = UV - 0.5;
	q.x *= 1.2;
	float v = 1.0 - vignette * smoothstep(0.25, 0.85, length(q) * 1.25);
	c *= v;
	// grain
	float n = hash12(FRAGCOORD.xy + grain_seed * 17.0) - 0.5;
	c += n * grain;
	// corner brackets and centre ticks, in pixels
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = UV * size;
	float m = 0.0;
	float inset = 14.0;
	float arm = 22.0;
	vec2 corners[4] = vec2[](vec2(inset, inset), vec2(size.x - inset, inset), vec2(inset, size.y - inset), vec2(size.x - inset, size.y - inset));
	for (int i = 0; i < 4; i++) {
		vec2 k = corners[i];
		vec2 dir = vec2(i % 2 == 0 ? 1.0 : -1.0, i < 2 ? 1.0 : -1.0);
		vec2 r = (p - k) * dir;
		if (r.x >= -1.0 && r.x <= arm && r.y >= -1.0 && r.y <= arm) {
			m = max(m, line_px(r.y, mark_px) * step(r.x, arm));
			m = max(m, line_px(r.x, mark_px) * step(r.y, arm));
		}
	}
	vec2 cc = p - size * 0.5;
	float tick = 7.0;
	float gap = 5.0;
	if (abs(cc.y) < 2.0 && abs(cc.x) > gap && abs(cc.x) < gap + tick) m = max(m, line_px(cc.y, mark_px));
	if (abs(cc.x) < 2.0 && abs(cc.y) > gap && abs(cc.y) < gap + tick) m = max(m, line_px(cc.x, mark_px));
	c = mix(c, mark_color.rgb, m * mark_color.a);
	COLOR = vec4(c, 1.0);
}
