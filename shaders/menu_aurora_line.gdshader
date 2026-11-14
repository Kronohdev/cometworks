shader_type canvas_item;
// Draw-in of an aurora thread (the logo's comet tail, scenes/menu/logo.tscn): a Line2D with
// texture_mode Stretch, so UV.x runs from 0 at its first point to 1 at its last. `reveal`
// (animated by the logo's AnimationPlayer) shows the line up to that fraction, soft-edged.
// Once drawn, a faint glint runs along the thread every `glint_period` seconds.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float softness : hint_range(0.0, 0.5) = 0.06;
uniform float glint_period : hint_range(0.0, 30.0) = 7.0;
uniform float glint_seconds : hint_range(0.1, 10.0) = 1.8;
uniform float glint_width : hint_range(0.01, 0.5) = 0.09;
uniform float glint_strength : hint_range(0.0, 2.0) = 0.7;

void fragment() {
	float a = 1.0 - smoothstep(reveal - softness, reveal, UV.x);
	COLOR.a *= reveal >= 1.0 ? 1.0 : a;
	if (glint_period > 0.0 && reveal >= 1.0) {
		float t = mod(TIME, glint_period) / glint_seconds;
		float x = t * 1.3 - 0.15;
		float d = (UV.x - x) / glint_width;
		float g = exp(-d * d) * glint_strength * step(t, 1.0);
		COLOR.rgb = mix(COLOR.rgb, vec3(1.0), clamp(g, 0.0, 1.0) * 0.8);
		COLOR.a = min(1.0, COLOR.a * (1.0 + g));
	}
}
