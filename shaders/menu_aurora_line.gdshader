shader_type canvas_item;
// Draw-in of an aurora thread (the logo's comet tail, scenes/menu/logo.tscn): a Line2D with
// texture_mode Stretch, so UV.x runs from 0 at its first point to 1 at its last. `reveal`
// (animated by the logo's AnimationPlayer) shows the line up to that fraction, soft-edged.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float softness : hint_range(0.0, 0.5) = 0.06;

void fragment() {
	float a = 1.0 - smoothstep(reveal - softness, reveal, UV.x);
	COLOR.a *= reveal >= 1.0 ? 1.0 : a;
}
