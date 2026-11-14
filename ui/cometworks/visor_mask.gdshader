shader_type canvas_item;
// Round visor (GDD 22.4 "Retrato 3D do Cometinho num visor redondo"): keeps a disc of the
// texture (a portrait SubViewport) with a soft 1 px edge, the rest transparent.

uniform float edge = 0.006;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, vec2(0.5));
	c.a *= 1.0 - smoothstep(0.5 - edge, 0.5, d);
	COLOR = c;
}
