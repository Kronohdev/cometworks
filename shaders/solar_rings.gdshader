shader_type spatial;
// Saturn's voxel rings: vertex-colored, lit from both sides (the Sun light grazes the
// ring plane, so plain Lambert would leave them almost black), with a little forward
// scattering glow when back-lit and an ambient floor.
render_mode cull_disabled, specular_disabled;

uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.06;
uniform float two_sided_wrap : hint_range(0.0, 1.0) = 0.55;

varying vec3 local_p;

void vertex() {
	local_p = VERTEX;
}

void fragment() {
	ALBEDO = COLOR.rgb * brightness;
	ROUGHNESS = 1.0;
	EMISSION = COLOR.rgb * ambient_floor;
	// treat the ring as a flat sheet: normal always toward the viewer's side
	vec3 up = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = dot(up, VIEW) >= 0.0 ? up : -up;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapd = mix(max(ndl, 0.0), abs(ndl) * 0.85 + 0.15, two_sided_wrap);
	DIFFUSE_LIGHT += wrapd * ATTENUATION * LIGHT_COLOR / PI;
}
