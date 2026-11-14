shader_type spatial;
// Engine shrouds and joint collars between stacked parts. Object-space panels that
// match the voxel parts: horizontal bands every band_height meters, longitudinal
// seams around the circumference, slight per-panel tint, an optional accent stripe.
// Colours: palette STRUCTURE / GUNMETAL / ACCENT (docs/art/palette.md).

uniform vec4 body_color : source_color = vec4(0.875, 0.89, 0.906, 1.0);
uniform vec4 seam_color : source_color = vec4(0.235, 0.267, 0.314, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.961, 0.604, 0.212, 1.0);
uniform float band_height = 0.5;
uniform float seams_around = 16.0;
uniform float seam_width = 0.035;
uniform float stripe_from = -1.0; // object-space Y range of the accent stripe (disabled if from > to)
uniform float stripe_to = -2.0;
uniform float metallic_amount = 0.25;

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float ang = atan(opos.z, opos.x) / 6.2831853 + 0.5;
	float r = max(length(opos.xz), 0.001);
	float u = ang * seams_around;
	float v = opos.y / band_height;
	vec2 id = floor(vec2(u, v));
	vec2 f = fract(vec2(u, v));
	float seam_u = min(f.x, 1.0 - f.x) * 6.2831853 * r / seams_around;
	float seam_v = min(f.y, 1.0 - f.y) * band_height;
	float seam = 1.0 - smoothstep(0.0, seam_width, min(seam_u, seam_v));
	vec3 col = body_color.rgb * (1.0 + (hash(id) - 0.5) * 0.05);
	if (stripe_from <= stripe_to && opos.y >= stripe_from && opos.y <= stripe_to) {
		col = stripe_color.rgb;
	}
	ALBEDO = mix(col, seam_color.rgb, seam * 0.85);
	METALLIC = metallic_amount;
	ROUGHNESS = 0.5 + seam * 0.3;
}
