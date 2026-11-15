shader_type spatial;
// Mãe-Gelo's icy nucleus (scenes/menu/props/comet_mae_gelo.tscn > Nucleus): voxel lobes in the
// Cometworks toon light (shaders/include/cw_toon.gdshaderinc). Snow-white ice with soft blue
// shade, dusty lilac crust patches in object space (so they stay put while she turns), frost
// glints that wink as the view moves and a cool rim. The sunlit side (local -X of the comet:
// the tail points +X) glows a touch warmer, where the jets come out.

#include "res://shaders/include/cw_toon.gdshaderinc"

uniform vec3 ice_color : source_color = vec3(0.93, 0.98, 1.0);
uniform vec3 shade_color : source_color = vec3(0.62, 0.80, 0.98);
uniform vec3 crust_color : source_color = vec3(0.50, 0.47, 0.66);
// how much of the surface the dusty crust covers, and the size of its patches (object units)
uniform float crust_amount : hint_range(0.0, 1.0) = 0.38;
uniform float crust_scale : hint_range(0.1, 20.0) = 2.6;
// the patches follow the voxels: one colour per voxel of this size (object units, 0 = smooth)
uniform float voxel_size : hint_range(0.0, 1.0) = 0.1;
// frost glints: how many cells sparkle and how bright
uniform float glint_density : hint_range(0.0, 1.0) = 0.12;
uniform float glint_strength : hint_range(0.0, 8.0) = 2.4;
uniform float glint_scale : hint_range(1.0, 60.0) = 14.0;
// the sunlit side's warm glow (towards local -X of the comet root)
uniform vec3 sun_glow : source_color = vec3(1.0, 0.86, 0.62);
uniform float sun_glow_strength : hint_range(0.0, 4.0) = 0.25;
// a faint inner light so she reads on a black sky
uniform vec3 inner_glow : source_color = vec3(0.55, 0.85, 1.0);
uniform float inner_glow_strength : hint_range(0.0, 4.0) = 0.22;
// how much of the voxel mesh's own vertex colour (its baked shading) shows
uniform float vertex_color_mix : hint_range(0.0, 1.0) = 0.35;
// her own storybook light from the Sun side (local -X of the comet), on top of the scene's:
// two soft toon steps, so the ice reads bright and icy in any shot
uniform float self_light : hint_range(0.0, 2.0) = 0.75;
uniform float self_shadow : hint_range(0.0, 1.0) = 0.42;
uniform vec3 shadow_tint : source_color = vec3(0.5, 0.58, 0.95);
uniform float rim_strength : hint_range(0.0, 4.0) = 1.1;
uniform vec3 rim_color : source_color = vec3(0.62, 0.95, 1.0);

varying vec3 v_obj;
varying vec3 v_obj_n;

float h13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float n3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h13(i), h13(i + vec3(1, 0, 0)), f.x), mix(h13(i + vec3(0, 1, 0)), h13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(h13(i + vec3(0, 0, 1)), h13(i + vec3(1, 0, 1)), f.x), mix(h13(i + vec3(0, 1, 1)), h13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	v_obj = VERTEX;
	v_obj_n = NORMAL;
}

void fragment() {
	// crust patches: two octaves, hard-ish edge (toon), in the lobe's own space
	vec3 q = v_obj;
	if (voxel_size > 0.0) {
		q = (floor((v_obj - v_obj_n * voxel_size * 0.5) / voxel_size) + 0.5) * voxel_size;
	}
	float c = n3(q * crust_scale) * 0.65 + n3(q * crust_scale * 2.7 + 7.1) * 0.35;
	float crust = smoothstep(1.0 - crust_amount - 0.04, 1.0 - crust_amount + 0.04, c);
	// the ice is bluer in the hollows (normals that face down / away) and whiter on top
	float up = clamp(v_obj_n.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 ice = mix(shade_color, ice_color, smoothstep(0.15, 0.85, up));
	vec3 col = mix(ice, crust_color, crust * 0.85);
	col *= mix(vec3(1.0), COLOR.rgb, vertex_color_mix);
	ALBEDO = col * (1.0 - self_light * 0.5);
	ROUGHNESS = mix(0.55, 0.95, crust);
	SPECULAR = 0.35;
	// frost glints: a few voxel-sized cells that wink as the eye moves
	vec3 cell = floor(v_obj * glint_scale);
	float h = h13(cell + 3.7);
	float g = 0.0;
	vec3 fc = fract(v_obj * glint_scale) - 0.5;
	float pin = smoothstep(0.32, 0.05, length(fc));
	if (h > 1.0 - glint_density && crust < 0.5) {
		vec3 wv = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
		float tw = sin(dot(wv, vec3(31.0, 17.0, 23.0)) * 6.0 + h * 60.0 + TIME * (1.0 + 3.0 * h));
		g = pow(max(tw, 0.0), 12.0) * glint_strength * pin;
	}
	// sunward warmth: the comet root's -X axis in view space
	vec3 sun_v = normalize((VIEW_MATRIX * vec4(-MODEL_MATRIX[0].xyz, 0.0)).xyz);
	float sunward = clamp(dot(NORMAL, sun_v), 0.0, 1.0);
	float lam = dot(NORMAL, sun_v) * 0.5 + 0.5;
	float step_ = smoothstep(0.42, 0.48, lam) * 0.6 + smoothstep(0.7, 0.76, lam) * 0.4;
	vec3 self_lit = col * mix(shadow_tint * self_shadow, vec3(1.0), step_) * self_light;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = self_lit + cw_toon_rim(NORMAL, VIEW, col, VERTEX, INV_VIEW_MATRIX)
			+ inner_glow * inner_glow_strength * (1.0 - crust * 0.6)
			+ sun_glow * sun_glow_strength * smoothstep(0.35, 0.8, sunward)
			+ rim_color * rim * rim_strength
			+ vec3(0.85, 0.97, 1.0) * g;
}
