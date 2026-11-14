shader_type sky;
// Planetary sky: zenith/horizon gradient (black for airless bodies), sun disk
// and glow, procedural stars, and an optional big body (Earth seen from the
// Moon, Jupiter from Europa, Saturn from Titan) lit by the sun.
// All parameters are written by PlanetSurface from the PlanetSurfaceProfile.

uniform vec3 zenith_color : source_color = vec3(0.2, 0.42, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.82, 0.95);
uniform vec3 ground_color : source_color = vec3(0.25, 0.26, 0.24);
uniform float gradient_power = 0.5;
uniform float star_intensity = 0.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);
uniform float sun_size_deg = 0.53;
uniform vec3 glow_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float glow_strength = 0.6;
uniform float sun_disk_energy = 30.0;
uniform bool body_enabled = false;
uniform vec3 body_dir = vec3(0.0, 0.5, 0.86);
uniform float body_size_deg = 2.0;
uniform vec3 body_color_a : source_color = vec3(0.25, 0.45, 0.85);
uniform vec3 body_color_b : source_color = vec3(0.95, 0.95, 0.95);
uniform float body_bands = 0.0;
uniform float body_energy = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 stars(vec3 d) {
	// cube-face grid so stars do not stretch at the poles
	vec3 a = abs(d);
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) { uv = d.yz / a.x; face = d.x > 0.0 ? 0.0 : 1.0; }
	else if (a.y >= a.z) { uv = d.xz / a.y; face = d.y > 0.0 ? 2.0 : 3.0; }
	else { uv = d.xy / a.z; face = d.z > 0.0 ? 4.0 : 5.0; }
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 220.0 : 520.0;
		vec2 g = uv * scale + face * 1013.0 + float(layer) * 71.0;
		vec2 cell = floor(g);
		float h = hash12(cell);
		float thr = layer == 0 ? 0.985 : 0.975;
		if (h > thr) {
			vec2 c = vec2(hash12(cell + 3.1), hash12(cell + 7.7)) * 0.6 + 0.2;
			float dist = length(fract(g) - c);
			float b = pow((h - thr) / (1.0 - thr), 2.0) * (layer == 0 ? 2.5 : 0.9);
			float tint = hash12(cell + 11.0);
			vec3 sc = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.7), tint);
			col += sc * b * smoothstep(0.32, 0.0, dist);
		}
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), gradient_power));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));

	vec3 sd = LIGHT0_DIRECTION;
	float cs = dot(d, sd);
	float ang = acos(clamp(cs, -1.0, 1.0));
	float sun_r = radians(sun_size_deg) * 0.5;
	// glow (wide + tight lobes), dimmed below the horizon
	float g = glow_strength * (0.25 * pow(max(cs, 0.0), 6.0) + 0.75 * pow(max(cs, 0.0), 180.0));
	col += glow_color * g * smoothstep(-0.15, 0.05, h);

	if (star_intensity > 0.0 && !AT_CUBEMAP_PASS) {
		float vis = smoothstep(-0.02, 0.15, h) * (1.0 - smoothstep(0.995, 0.9999, cs));
		col += stars(d) * star_intensity * vis;
	}

	if (body_enabled) {
		vec3 bd = normalize(body_dir);
		float br = radians(body_size_deg) * 0.5;
		float bang = acos(clamp(dot(d, bd), -1.0, 1.0));
		if (bang < br * 1.02) {
			// local frame of the disk
			vec3 bx = normalize(cross(vec3(0.0, 1.0, 0.0), bd));
			vec3 by = cross(bd, bx);
			vec2 p = vec2(dot(d, bx), dot(d, by)) / sin(br);
			float r2 = dot(p, p);
			if (r2 < 1.0) {
				vec3 n = normalize(p.x * bx + p.y * by - sqrt(1.0 - r2) * bd);
				float lit = clamp(dot(n, sd) * 1.1 + 0.08, 0.0, 1.0);
				vec3 surf;
				if (body_bands > 0.0) {
					float lat = p.y + 0.06 * (vnoise(p * 6.0) - 0.5);
					float band = 0.5 + 0.5 * sin(lat * body_bands * 3.14159 + 0.8 * vnoise(vec2(lat * 9.0, p.x * 3.0)));
					surf = mix(body_color_a, body_color_b, band);
				} else {
					float cl = smoothstep(0.5, 0.75, vnoise(p * 5.0 + 3.0) * 0.6 + vnoise(p * 13.0) * 0.4);
					float land = smoothstep(0.55, 0.6, vnoise(p * 3.0 + 17.0));
					surf = mix(body_color_a, vec3(0.32, 0.42, 0.22), land * 0.7);
					surf = mix(surf, body_color_b, cl);
				}
				float limb = smoothstep(1.0, 0.85, r2);
				vec3 bc = surf * lit * body_energy;
				float edge = smoothstep(1.0, 0.96, r2);
				col = mix(col, bc + glow_color * 0.0, edge * (0.6 + 0.4 * limb));
			}
		}
	}

	float disk = smoothstep(sun_r * 1.15, sun_r * 0.85, ang);
	col += sun_color * disk * sun_disk_energy * smoothstep(-0.02, 0.01, h);
	COLOR = col;
}
