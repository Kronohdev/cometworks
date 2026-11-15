shader_type canvas_item;
// The branch into the technology being researched (research.tscn, EdgeActive): aurora stripes
// (mint, lilac, peach) run along the line towards the card, like sap rising. The Line2D stretches
// its texture along the whole branch, so UV.x goes 0 -> 1 from the prerequisite to the card.

uniform vec4 a_color : source_color = vec4(0.435, 0.878, 0.745, 1.0);
uniform vec4 b_color : source_color = vec4(0.702, 0.612, 1.0, 1.0);
uniform vec4 c_color : source_color = vec4(1.0, 0.604, 0.361, 1.0);
uniform float stripes = 5.0;
uniform float speed = 0.7;

void fragment() {
	float t = fract(UV.x * stripes - TIME * speed);
	vec3 col = mix(mix(a_color.rgb, b_color.rgb, smoothstep(0.0, 0.5, t)), c_color.rgb, smoothstep(0.5, 1.0, t));
	COLOR = vec4(col, COLOR.a);
}
