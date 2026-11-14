shader_type spatial;
// Thin atmosphere halo on a sphere shell slightly larger than the planet. Bright at the
// limb, fading to zero at the shell's own silhouette, and only on the side facing the
// Sun (the Sun sits at the world origin of the solar-system scene).
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform vec3 atmo_color : source_color = vec3(0.42, 0.7, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.6;
uniform float power : hint_range(0.5, 8.0) = 2.4;
uniform float edge_softness : hint_range(1.0, 32.0) = 7.0;
uniform vec3 sun_position = vec3(0.0);

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float f = 1.0 - clamp(dot(world_n, v), 0.0, 1.0);
	float rim = pow(f, power) * (1.0 - pow(f, edge_softness));
	vec3 l = normalize(sun_position - world_pos);
	float lit = smoothstep(-0.3, 0.55, dot(world_n, l));
	// forward scattering: a little extra glow when looking toward the Sun through the limb
	float fwd = pow(clamp(dot(-v, l), 0.0, 1.0), 6.0) * 0.8;
	ALBEDO = atmo_color * rim * (lit + fwd * f) * intensity;
}
