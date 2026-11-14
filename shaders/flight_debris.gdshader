shader_type spatial;
// Voxel fragment of a destroyed vessel (scenes/flight/debris_chunk.tscn). Colour per
// instance (no material copies) plus a scorched, glowing look that cools down.
instance uniform vec4 tint : source_color = vec4(0.87, 0.89, 0.91, 1.0);
uniform float scorch = 0.45;

varying vec3 lpos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float n = hash(floor(lpos * 4.0 + 7.0));
	vec3 c = tint.rgb * (0.85 + 0.25 * n);
	c = mix(c, vec3(0.08, 0.07, 0.06), scorch * smoothstep(0.3, 0.9, n));
	ALBEDO = c;
	ROUGHNESS = 0.8;
	EMISSION = vec3(1.0, 0.4, 0.1) * step(0.93, n) * 0.6;
}
