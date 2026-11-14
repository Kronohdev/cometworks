shader_type canvas_item;
render_mode blend_add, unshaded;
// Idle shimmer of the primary call to action (CwShimmer, src/tycoon/ui/motion/cw_shimmer.gd):
// a slanted band of light crosses the rect once every `period` seconds and rests the rest
// of the time. GPU only: no script runs while the button sits there.
uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float period : hint_range(0.5, 30.0) = 5.0;
uniform float sweep_seconds : hint_range(0.1, 5.0) = 1.1;
uniform float width : hint_range(0.02, 0.8) = 0.16;
uniform float slant : hint_range(-1.0, 1.0) = 0.35;
uniform float strength : hint_range(0.0, 1.0) = 0.22;
uniform float phase = 0.0;
// px-ish softness of the rect edges (keeps the band inside rounded corners)
uniform float edge : hint_range(0.0, 0.5) = 0.06;
// rounded mask: the rect's width / height and the corner radius as a fraction of the height
// (0.5 = a pill), so the band never lights the corners of a candy key
uniform float aspect = 4.0;
uniform float corner : hint_range(0.0, 0.5) = 0.5;

void fragment() {
	float t = mod(TIME + phase, period) / sweep_seconds;
	float on = step(t, 1.0);
	float x = UV.x + (UV.y - 0.5) * slant;
	float c = mix(-width * 2.0, 1.0 + width * 2.0, t);
	float d = (x - c) / width;
	float band = exp(-d * d) * on;
	float ex = smoothstep(0.0, edge, UV.x) * smoothstep(0.0, edge, 1.0 - UV.x);
	float ey = smoothstep(0.0, edge * 2.0, UV.y) * smoothstep(0.0, edge * 2.0, 1.0 - UV.y);
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	vec2 q = abs(p) - vec2(aspect * 0.5 - corner, 0.5 - corner);
	float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	float mask = 1.0 - smoothstep(-0.06, 0.0, sd);
	COLOR = vec4(tint.rgb * band * strength * ex * ey * mask, 1.0);
}
