shader_type spatial;
// The Sun's voxel surface: unshaded HDR emission from the baked vertex colors, with
// limb darkening from the smooth sphere normal and a slow shimmer. Values above 1.0
// feed the WorldEnvironment glow (bloom). The energy eases from energy_near (close-up:
// granulation and sunspots stay readable) to energy_far (map view: a blazing star).
render_mode unshaded, cull_back, fog_disabled;

uniform float energy_near : hint_range(0.0, 16.0) = 1.05;
uniform float energy_far : hint_range(0.0, 16.0) = 3.0;
uniform vec2 energy_distance = vec2(70.0, 420.0);
uniform float limb_darkening : hint_range(0.0, 1.0) = 0.5;
uniform vec3 limb_tint : source_color = vec3(1.0, 0.45, 0.18);
uniform float shimmer : hint_range(0.0, 0.3) = 0.07;

varying vec3 sphere_n;
varying vec3 local_p;

void vertex() {
	sphere_n = (MODELVIEW_MATRIX * vec4(VERTEX, 0.0)).xyz;
	local_p = VERTEX;
}

void fragment() {
	float cam_d = length(CAMERA_POSITION_WORLD - NODE_POSITION_WORLD);
	float energy = mix(energy_near, energy_far, smoothstep(energy_distance.x, energy_distance.y, cam_d));
	float mu = clamp(dot(normalize(sphere_n), VIEW), 0.0, 1.0);
	float ld = mix(1.0 - limb_darkening, 1.0, pow(mu, 0.55));
	vec3 tint = mix(limb_tint, vec3(1.0), pow(mu, 0.4));
	float s = 1.0 + shimmer * sin(TIME * 0.9 + dot(local_p, vec3(9.1, 7.3, 8.7)))
			* sin(TIME * 0.37 + dot(local_p, vec3(-5.2, 11.4, 3.3)));
	ALBEDO = COLOR.rgb * tint * ld * s * energy;
}
