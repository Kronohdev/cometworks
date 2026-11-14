// Cometworks toon lighting ("Aurora de observatório", cel version). Include it in a spatial
// shader to replace the built-in diffuse / specular with a storybook light:
//   * stepped diffuse: cw_toon_bands bands with a soft edge (cw_toon_band_soft), the band
//     thresholds between cw_toon_band_low and cw_toon_band_high
//   * hue-shifted shadows: the shadow side of every directional light (sun, moon) is filled
//     with cw_shadow_tint (cool violet by day, warm at dusk, blue at night: the campus day
//     cycle drives it) and every band is tinted by the ramp texture cw_toon_ramp
//   * a crisp specular blob for glossy surfaces (ROUGHNESS below ~0.45 and toon_specular > 0)
//   * a rim of sky / aurora colour (cw_rim_color, cw_rim_strength) on the edges facing away
//     from the camera: add cw_toon_rim(NORMAL, VIEW, ALBEDO, VERTEX, INV_VIEW_MATRIX) to EMISSION in
//     fragment()
//   * lamps (omni / spot) light in soft pools: their falloff is posterised gently
//   * shadows: ATTENUATION (shadow maps and distance) goes into the banding, so cast shadows
//     have crisp edges; emission and ambient light are left to the engine
// cw_toon = 0 switches every material back to a plain Lambert + GGX look ("Clássico" in the
// options, src/core/cw_look.gd), so one shader serves both styles.
//
// The globals live in project.godot (Project Settings > Shader Globals): one place tunes the
// whole game. Per-material tunables are the toon_* uniforms below (inspector group "Toon").
//
// Usage:
//   #include "res://shaders/include/cw_toon.gdshaderinc"
//   ...fragment(): EMISSION += cw_toon_rim(NORMAL, VIEW, ALBEDO, VERTEX, INV_VIEW_MATRIX);
// Define CW_TOON_NO_LIGHT before the include to get the helpers without the light() function,
// CW_TOON_RIM_DEFAULT to change the default of toon_rim. Locals and parameters here are
// prefixed _cw_ so they never collide with the including shader's uniforms.

global uniform float cw_toon;
global uniform int cw_toon_bands;
global uniform float cw_toon_band_soft;
global uniform float cw_toon_band_low;
global uniform float cw_toon_band_high;
global uniform sampler2D cw_toon_ramp : source_color, filter_linear, repeat_disable;
global uniform vec4 cw_shadow_tint : source_color;
global uniform float cw_shadow_fill;
global uniform vec4 cw_rim_color : source_color;
global uniform float cw_rim_strength;
global uniform float cw_toon_light_scale;

group_uniforms Toon;
// shifts the band thresholds: > 0 lights more of the surface, < 0 darkens it
uniform float toon_band_bias : hint_range(-0.5, 0.5) = 0.0;
// fraction of the shadow-side fill this material takes (0 = plain dark shadows)
uniform float toon_shadow_fill : hint_range(0.0, 2.0) = 1.0;
// crisp highlight on glossy (ROUGHNESS < ~0.45) or metallic fragments; 0 = none
uniform float toon_specular : hint_range(0.0, 4.0) = 0.0;
// rim multiplier (0 = no rim on this material; a shader may #define CW_TOON_RIM_DEFAULT)
#ifndef CW_TOON_RIM_DEFAULT
#define CW_TOON_RIM_DEFAULT 1.0
#endif
uniform float toon_rim : hint_range(0.0, 3.0) = CW_TOON_RIM_DEFAULT;
// rim fades out beyond this distance (m) so far terrain stays calm
uniform float toon_rim_distance : hint_range(1.0, 400.0) = 60.0;
// band count of this material (0 = the global cw_toon_bands) and band-edge softness multiplier
uniform int toon_bands : hint_range(0, 6) = 0;
uniform float toon_softness : hint_range(0.0, 8.0) = 1.0;
// 0..1: wraps the diffuse round the terminator (soft, felt-like surfaces)
uniform float toon_wrap : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

float cw_luma(vec3 _cw_c) {
	return dot(_cw_c, vec3(0.2126, 0.7152, 0.0722));
}

// Stepped light level for x in 0..1: cw_toon_bands levels (0 .. 1) with soft edges.
float cw_toon_band(float _cw_x) {
	int _cw_n = clamp(toon_bands > 0 ? toon_bands : cw_toon_bands, 1, 6);
	if (_cw_n <= 1) {
		return _cw_x;
	}
	float _cw_w = max(cw_toon_band_soft * toon_softness, 1e-4);
	float _cw_steps = float(_cw_n - 1);
	float _cw_level = 0.0;
	for (int _cw_k = 0; _cw_k < 5; _cw_k++) {
		if (_cw_k >= _cw_n - 1) {
			break;
		}
		float _cw_t = _cw_n > 2 ? float(_cw_k) / (_cw_steps - 1.0) : 0.0;
		float _cw_edge = mix(cw_toon_band_low, cw_toon_band_high, _cw_t);
		_cw_level += smoothstep(_cw_edge - _cw_w, _cw_edge + _cw_w, _cw_x);
	}
	return _cw_level / _cw_steps;
}

// Colour multiplier of a band level: the ramp's hue shift, the shadow end filled with the
// tint (scaled by fill), the lit end white.
vec3 cw_toon_shade(float _cw_level, float _cw_fill) {
	vec3 _cw_ramp = texture(cw_toon_ramp, vec2(clamp(_cw_level, 0.01, 0.99), 0.5)).rgb;
	vec3 _cw_shadow = cw_shadow_tint.rgb * cw_shadow_fill * _cw_fill;
	return mix(_cw_shadow, vec3(1.0), _cw_level) * _cw_ramp;
}

// Sky / aurora rim for EMISSION: soft-edged band on the faces turned from the camera,
// tinted a little by the surface colour so it reads as light, not paint. Faces turned up
// (ground, roofs, table tops) get none: grazing views of the ground would wash out.
vec3 cw_toon_rim(vec3 _cw_n, vec3 _cw_v, vec3 _cw_albedo, vec3 _cw_vertex, mat4 _cw_inv_view) {
	float _cw_edge = 1.0 - clamp(dot(_cw_n, _cw_v), 0.0, 1.0);
	float _cw_r = smoothstep(0.7, 0.92, _cw_edge);
	float _cw_up = (_cw_inv_view * vec4(_cw_n, 0.0)).y;
	_cw_r *= 1.0 - smoothstep(0.35, 0.75, _cw_up);
	float _cw_fade = 1.0 - smoothstep(toon_rim_distance * 0.6, toon_rim_distance, length(_cw_vertex));
	vec3 _cw_col = cw_rim_color.rgb * mix(vec3(1.0), _cw_albedo * 2.0, 0.35);
	return _cw_col * _cw_r * cw_rim_strength * toon_rim * _cw_fade * cw_toon;
}

#ifndef CW_TOON_NO_LIGHT
void light() {
	float _cw_ndl_raw = dot(NORMAL, LIGHT);
	float _cw_ndl = clamp(_cw_ndl_raw, 0.0, 1.0);
	vec3 _cw_h = normalize(LIGHT + VIEW);
	float _cw_ndh = clamp(dot(NORMAL, _cw_h), 0.0, 1.0);

	// foliage translucency (BACKLIGHT) in both styles
	DIFFUSE_LIGHT += BACKLIGHT * LIGHT_COLOR / PI * clamp(-_cw_ndl_raw, 0.0, 1.0) * ATTENUATION;

	// cw_toon is a global: the branch is uniform, only one style is paid for
	if (cw_toon > 0.5) {
		float _cw_wrapped = clamp((_cw_ndl_raw + toon_wrap) / (1.0 + toon_wrap), 0.0, 1.0);
		float _cw_band = cw_toon_band(clamp(_cw_wrapped + toon_band_bias, 0.0, 1.0));
		if (LIGHT_IS_DIRECTIONAL) {
			// facing is banded; the shadow map is firmed up (not banded: its filtered penumbra
			// would turn into speckles), so cast shadows get a clean, slightly soft edge
			float _cw_lit = _cw_band * smoothstep(0.2, 0.8, ATTENUATION);
			// the shadow fill takes the light's brightness, not its hue (cool shadows under a warm sun)
			vec3 _cw_col = mix(vec3(cw_luma(LIGHT_COLOR)), LIGHT_COLOR, _cw_lit);
			DIFFUSE_LIGHT += _cw_col / PI * cw_toon_shade(_cw_lit, toon_shadow_fill) * cw_toon_light_scale;
			// crisp highlight on glossy (low roughness) or metal surfaces
			float _cw_gloss = max(1.0 - smoothstep(0.3, 0.5, ROUGHNESS), METALLIC);
			if (toon_specular > 0.0 && _cw_gloss > 0.0) {
				float _cw_sp = pow(_cw_ndh, mix(24.0, 160.0, _cw_gloss));
				float _cw_blob = smoothstep(0.45, 0.55, _cw_sp) * _cw_lit;
				SPECULAR_LIGHT += LIGHT_COLOR / PI * _cw_blob * toon_specular * _cw_gloss * mix(vec3(1.0), ALBEDO, METALLIC);
			}
		} else {
			// lamps: soft pools - the falloff steps gently, the facing is banded
			float _cw_pool = smoothstep(0.0, 0.18, ATTENUATION) * 0.4 + smoothstep(0.25, 0.6, ATTENUATION) * 0.6;
			_cw_pool = mix(ATTENUATION, _cw_pool, 0.35);
			DIFFUSE_LIGHT += LIGHT_COLOR / PI * _cw_pool * mix(0.15, 1.0, _cw_band) * cw_toon_light_scale;
		}
	} else {
		// classic: Lambert + GGX (close to the engine's default look)
		float _cw_ndv = clamp(dot(NORMAL, VIEW), 1e-4, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * _cw_ndl * ATTENUATION / PI;
		float _cw_a = max(ROUGHNESS * ROUGHNESS, 0.002);
		float _cw_a2 = _cw_a * _cw_a;
		float _cw_d = _cw_ndh * _cw_ndh * (_cw_a2 - 1.0) + 1.0;
		float _cw_D = _cw_a2 / (PI * _cw_d * _cw_d);
		float _cw_k = _cw_a * 0.5;
		float _cw_vis = 0.25 / ((_cw_ndl * (1.0 - _cw_k) + _cw_k) * (_cw_ndv * (1.0 - _cw_k) + _cw_k));
		vec3 _cw_f0 = mix(vec3(0.08 * SPECULAR_AMOUNT), ALBEDO, METALLIC);
		vec3 _cw_fres = _cw_f0 + (1.0 - _cw_f0) * pow(1.0 - clamp(dot(LIGHT, _cw_h), 0.0, 1.0), 5.0);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * _cw_ndl * _cw_D * _cw_vis * _cw_fres;
	}
}
#endif
