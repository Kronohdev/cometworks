shader_type spatial;
// Twinkling four-point stars round Mãe-Gelo (comet_mae_gelo.tscn > Glints) and the soft dust
// flecks of her jets and tails (Sparks, JetA/JetB). For GPUParticles3D draw passes: a QuadMesh
// of size (1, 1); each particle's colour (COLOR, from the process material's ramp) tints it and
// its alpha fades it. `star` = 1 draws a cross-shaped twinkle, 0 a round soft dot. Additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0);
uniform float intensity : hint_range(0.0, 16.0) = 2.0;
uniform float star : hint_range(0.0, 1.0) = 1.0;
// how thin the star's arms are
uniform float sharpness : hint_range(1.0, 40.0) = 14.0;
uniform float twinkle_speed : hint_range(0.0, 20.0) = 5.0;

varying float v_seed;

void vertex() {
	// billboard that keeps the particle's scale
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = mv * mat4(vec4(sc, 0, 0, 0), vec4(0, sc, 0, 0), vec4(0, 0, sc, 0), vec4(0, 0, 0, 1));
	v_seed = fract(MODEL_MATRIX[3].x * 13.17 + MODEL_MATRIX[3].y * 7.31 + MODEL_MATRIX[3].z * 3.77);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float dot_ = exp(-r * r * 6.0);
	float arms = exp(-abs(p.x) * sharpness) * exp(-abs(p.y) * 2.2) + exp(-abs(p.y) * sharpness) * exp(-abs(p.x) * 2.2);
	float tw = 0.55 + 0.45 * sin(TIME * twinkle_speed + v_seed * 40.0);
	float v = mix(dot_, (arms * 0.8 + exp(-r * r * 18.0)) * tw, star);
	v *= clamp(1.0 - r, 0.0, 1.0);
	ALBEDO = tint * COLOR.rgb * v * COLOR.a * intensity;
}
