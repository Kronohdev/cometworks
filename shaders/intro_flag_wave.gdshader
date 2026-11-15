shader_type canvas_item;
// The Brazilian flag on the Moon in the intro. The pole is on the texture's right edge.
// `reveal` unrolls the cloth from the pole outwards (0 = furled, 1 = open); the ripple runs
// from the pole to the free edge, growing with the distance from the pole, with the cloth
// bunching a little in the troughs and light / shade following the folds.

uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float amplitude : hint_range(0.0, 0.1) = 0.0;
uniform float frequency = 7.0;
uniform float speed = 5.0;

void fragment() {
	float free_end = 1.0 - UV.x;                         // 0 at the pole, 1 at the free edge
	float phase = free_end * frequency - TIME * speed;
	float k = amplitude * smoothstep(0.0, 0.35, free_end) * (0.6 + 0.4 * free_end);
	float wave = sin(phase) + 0.35 * sin(phase * 2.3 + 1.7);
	vec2 uv = UV + vec2(cos(phase) * k * 0.35, wave * k);
	vec4 c = texture(TEXTURE, uv);
	if (uv.y < 0.0 || uv.y > 1.0 || uv.x < 0.0 || uv.x > 1.0) { c.a = 0.0; }
	// unroll: hide what is still furled, with a soft rolled edge
	float edge = reveal * 1.02;
	c.a *= 1.0 - smoothstep(edge - 0.04, edge, free_end);
	float slope = cos(phase) + 0.8 * cos(phase * 2.3 + 1.7);
	c.rgb *= 1.0 + slope * k * 3.2;
	COLOR = c;
}
