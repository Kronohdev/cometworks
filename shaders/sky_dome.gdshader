shader_type spatial;
// Daytime sky for the launch site, drawn on a large inward-facing sphere (the hangar
// scene's Environment uses a plain colour background, so the sky lives in the level).
// Gradient zenith -> horizon haze, sun disk + halo matching the Sun light direction,
// and soft procedural cumulus/cirrus bands. Fog is disabled here: the horizon colour is
// the same as the Environment depth-fog colour, so distant terrain melts into it.
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;

uniform vec4 zenith_color : source_color = vec4(0.24, 0.49, 0.79, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.80, 0.88, 0.94, 1.0);
uniform vec4 ground_color : source_color = vec4(0.70, 0.77, 0.80, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.945, 0.863, 1.0);
uniform vec3 sun_dir = vec3(-0.22, 0.41, -0.89);
uniform float sun_size = 0.9995;
uniform float sun_energy = 10.0;
uniform float halo_energy = 0.7;
uniform float horizon_sharpness = 3.2;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.72, 0.78, 0.86, 1.0);
uniform float cloud_cover = 0.42;
uniform float cloud_scale = 1.4;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 dir = normalize(wpos - CAMERA_POSITION_WORLD);
	float h = dir.y;
	vec3 sky;
	if (h >= 0.0) {
		float t = pow(1.0 - h, horizon_sharpness);
		sky = mix(zenith_color.rgb, horizon_color.rgb, t);
	} else {
		sky = mix(horizon_color.rgb, ground_color.rgb, smoothstep(0.0, 0.12, -h));
	}
	vec3 sd = normalize(sun_dir);
	float mu = dot(dir, sd);
	// clouds on a virtual plane above the camera
	if (h > 0.015) {
		vec2 cp = dir.xz / (h + 0.06) * cloud_scale;
		float n = fbm(cp + vec2(3.0, 1.0));
		float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.22, n);
		float wisps = smoothstep(0.55, 0.85, fbm(cp * vec2(0.35, 2.5) + 11.0)) * 0.35;
		float c = clamp(cover + wisps * (1.0 - cover), 0.0, 1.0);
		float lit = clamp(0.55 + 0.45 * (fbm(cp + sd.xz * 0.15 + 3.0) - n) * 4.0 + 0.25 * max(mu, 0.0), 0.0, 1.0);
		vec3 cc = mix(cloud_shadow.rgb, cloud_color.rgb, lit);
		float fade = smoothstep(0.015, 0.18, h);
		sky = mix(sky, cc, c * fade * 0.92);
	}
	// sun: disk + halo (the disk is HDR so glow picks it up)
	float halo = pow(max(mu, 0.0), 180.0) * 1.2 + pow(max(mu, 0.0), 12.0) * 0.18;
	sky += sun_color.rgb * halo * halo_energy;
	float disk = smoothstep(sun_size, sun_size + 0.0002, mu);
	sky = mix(sky, sun_color.rgb * sun_energy, disk);
	ALBEDO = sky;
}
