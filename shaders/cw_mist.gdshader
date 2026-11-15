shader_type canvas_item;
// Soft drifting mist over the eras of the research tree that are still out of reach
// (research.tscn, MistTemplate). Two layers of value-noise clouds slide sideways; the band's top
// and bottom fade out so the mist has no hard edge.

uniform vec4 tint : source_color = vec4(0.97, 0.94, 1.0, 0.86);
uniform vec2 stretch = vec2(9.0, 1.0);
uniform float scale = 1.6;
uniform float speed = 0.035;
uniform float base = 0.62;
uniform float contrast = 0.85;
uniform float edge = 0.16;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * stretch * scale;
	float n1 = fbm(p + vec2(TIME * speed, 0.0));
	float n2 = fbm(p * 1.7 + vec2(-TIME * speed * 0.7, TIME * speed * 0.2) + 3.1);
	float a = base + ((n1 * 0.6 + n2 * 0.4) - 0.5) * contrast;
	float fade = smoothstep(0.0, edge, UV.y) * smoothstep(0.0, edge, 1.0 - UV.y);
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 1.0) * tint.a * fade);
}
