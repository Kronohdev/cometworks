shader_type spatial;
// Mãe-Gelo's gentle face (comet_mae_gelo.tscn > Nucleus/Face, hidden unless a story shot turns
// it on): two closed, smiling eyes, rosy cheeks and a tiny smile drawn on a QuadMesh laid on the
// nucleus. Now and then she opens her eyes for a moment (`awake` > 0 keeps them open, for a
// wink keyed in a shot). Lit softly by its own glow so it reads in the coma.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_back, fog_disabled, shadows_disabled;

uniform vec3 ink : source_color = vec3(0.17, 0.2, 0.42);
uniform vec3 blush : source_color = vec3(1.0, 0.58, 0.7);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// 0 = calm closed eyes (she dozes as she travels), 1 = eyes open
uniform float awake : hint_range(0.0, 1.0) = 0.0;
// seconds between two little peeks (0 = never)
uniform float peek_every : hint_range(0.0, 30.0) = 7.0;
uniform float smile : hint_range(0.0, 1.0) = 1.0;

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return smoothstep(w, w * 0.55, length(pa - ba * h));
}

// a closed-eye arc ("^" turned into a soft smile line) centred at c
float closed_eye(vec2 p, vec2 c) {
	vec2 q = p - c;
	float y = -0.9 * q.x * q.x;   // arc bending down at the ends: a happy closed eye
	float d = abs(q.y - y - 0.02);
	return smoothstep(0.055, 0.03, d) * smoothstep(0.15, 0.13, abs(q.x));
}

float open_eye(vec2 p, vec2 c) {
	vec2 q = (p - c) / vec2(0.07, 0.1);
	return smoothstep(1.0, 0.85, length(q));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float open = awake;
	if (peek_every > 0.0) {
		float t = mod(TIME, peek_every);
		open = max(open, smoothstep(0.0, 0.15, t) * smoothstep(1.4, 1.2, t));
	}
	vec2 le = vec2(-0.32, 0.1);
	vec2 re = vec2(0.32, 0.1);
	float eyes = mix(closed_eye(p, le) + closed_eye(p, re), open_eye(p, le) + open_eye(p, re), step(0.5, open));
	// tiny smile
	float m = 0.0;
	if (smile > 0.0) {
		vec2 q = p - vec2(0.0, -0.16);
		float y = 1.4 * q.x * q.x;
		m = smoothstep(0.048, 0.026, abs(q.y - y)) * smoothstep(0.12, 0.1, abs(q.x)) * smile;
	}
	float ch = exp(-dot(p - vec2(-0.5, -0.1), p - vec2(-0.5, -0.1)) * 30.0) + exp(-dot(p - vec2(0.5, -0.1), p - vec2(0.5, -0.1)) * 30.0);
	float ink_a = clamp(eyes + m, 0.0, 1.0);
	vec3 col = mix(blush, ink, ink_a);
	ALBEDO = col;
	ALPHA = clamp(ink_a + ch * 0.55, 0.0, 1.0) * opacity;
}
