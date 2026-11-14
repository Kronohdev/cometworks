shader_type spatial;
// Voxel planet surface: albedo from the baked vertex colors (linear, with voxel AO),
// lit by the Sun's OmniLight. The voxel face normal is blended with the smooth sphere
// normal, and the light is masked by the SMOOTH terminator: voxel faces near the
// day/night line that happen to face the Sun would otherwise light up as a comb of
// bright stripes on the night side. Optional ocean glint for blue-dominant voxels.
render_mode cull_back;

uniform float normal_blend : hint_range(0.0, 1.0) = 0.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.92;
// diffuse wrap: softens the terminator a little (0 = plain Lambert)
uniform float wrap : hint_range(0.0, 1.0) = 0.15;
// width of the smooth terminator mask (dot(sphere normal, light) range)
uniform vec2 terminator = vec2(-0.08, 0.28);
// faint self-illumination so night sides are not pure black (the map must stay readable)
uniform float night_floor : hint_range(0.0, 0.2) = 0.02;
// how much brighter a voxel face may get than the smooth sphere shading
uniform float face_contrast : hint_range(0.0, 1.0) = 0.22;
uniform float ocean_glint : hint_range(0.0, 2.0) = 0.0;
uniform float glint_power : hint_range(4.0, 200.0) = 48.0;

varying vec3 sphere_n;
varying float ocean;
varying vec3 smooth_n;

void vertex() {
	sphere_n = (MODELVIEW_MATRIX * vec4(VERTEX, 0.0)).xyz;
}

void fragment() {
	vec3 sn = normalize(sphere_n);
	smooth_n = sn;
	NORMAL = normalize(mix(NORMAL, sn, normal_blend));
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness;
	EMISSION = COLOR.rgb * night_floor;
	ocean = smoothstep(0.04, 0.12, COLOR.b - max(COLOR.r, COLOR.g) * 1.1);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sdl = dot(smooth_n, LIGHT);
	float d = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// voxel faces may vary around the smooth shading but never glow far above it
	d = min(d, max(sdl, 0.0) + face_contrast);
	float term = smoothstep(terminator.x, terminator.y, sdl);
	DIFFUSE_LIGHT += d * term * ATTENUATION * LIGHT_COLOR / PI;
	if (ocean_glint > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float sp = pow(max(dot(smooth_n, h), 0.0), glint_power) * ocean;
		SPECULAR_LIGHT += sp * ocean_glint * term * ATTENUATION * LIGHT_COLOR;
	}
}
