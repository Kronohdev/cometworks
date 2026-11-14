shader_type spatial;
// Cometling skin: voxel vertex colours (AO baked) + per-creature tints chosen by the
// vertex-colour alpha written by tools/creature_gen.py:
//   a = 0 fixed colour, 1/3 body tint, 2/3 spot tint, 1 glow tint (also emissive).
// The tints are INSTANCE uniforms, so every Cometling shares this one material.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform vec4 body_tint : source_color = vec4(0.75, 0.9, 1.0, 1.0);
instance uniform vec4 spot_tint : source_color = vec4(1.0, 0.8, 0.33, 1.0);
instance uniform vec4 glow_tint : source_color = vec4(0.96, 0.6, 0.21, 1.0);
instance uniform float glow_energy = 1.6;
// 0..1: lifts the whole creature a bit (surprise flash, selection in the crew panel)
instance uniform float highlight = 0.0;

uniform float rim_strength : hint_range(0.0, 1.0) = 0.28;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	float m = round(COLOR.a * 3.0);
	vec3 base = COLOR.rgb;
	vec3 tint = vec3(1.0);
	tint = mix(tint, body_tint.rgb, step(0.5, m) * step(m, 1.5));
	tint = mix(tint, spot_tint.rgb, step(1.5, m) * step(m, 2.5));
	float g = step(2.5, m);
	tint = mix(tint, glow_tint.rgb, g);
	vec3 c = base * tint;
	ALBEDO = c;
	ROUGHNESS = mix(roughness, 0.3, g);
	SPECULAR = 0.35;
	// soft "velvet" rim keeps the silhouettes readable on the bright hangar floor
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = c * (rim * rim_strength + highlight * 0.35) + glow_tint.rgb * glow_energy * g;
}
