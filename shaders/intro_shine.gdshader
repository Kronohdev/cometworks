shader_type canvas_item;
render_mode blend_add;
// A light sweep across the finished emblem in the intro: a soft diagonal band masked by the
// emblem's own alpha.

uniform float pos = -0.6;                   // band centre along the diagonal (0..1 crosses the art)
uniform float width : hint_range(0.01, 0.5) = 0.12;
uniform float strength : hint_range(0.0, 2.0) = 0.7;
uniform vec4 tint : source_color = vec4(1.0, 0.96, 0.82, 1.0);

void fragment() {
	float d = (UV.x + UV.y) * 0.5;
	float b = 1.0 - smoothstep(0.0, width, abs(d - pos));
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(tint.rgb, b * a * strength);
}
