shader_type sky;
// The whole sky of the flight scene: the Earth itself (analytic sphere, voxel texture),
// its atmosphere (single scattering, Rayleigh + Mie), clouds, the Sun, the Moon and a
// starfield. Rendering the planet here keeps it exact at any altitude: the CPU passes the
// camera altitude in double precision (cam_alt) and every intersection is written in a
// form that does not subtract huge numbers (c = h * (2R + h) instead of |C|² - R²).
//
// Frames: EYEDIR is in the render frame (= the planet-centred inertial frame, translated
// by the floating origin). up_dir = radial up at the camera. planet_to_tex rotates render
// directions into the texture frame of earth_albedo (lat/lon like tools/planet_gen.py).
// Near the launch site the ground uses the launch-site scene's own coastline and colours
// (shaders/outside_ground.gdshader) so the local scene and the planet join without a seam.
//
// Cost (integrated GPU): the single-scattering march (scatter_steps samples, each with two
// Chapman sun columns) runs in Godot's half-resolution sky pass (in-scattered light is
// smooth); the Milky Way / nebula fBm runs in the quarter-resolution pass; the full-
// resolution pass only does what has sharp edges: the voxel ground, clouds, Sun, Moon and
// stars, with the view transmittance from closed-form Chapman columns. The radiance
// cubemap pass keeps the old all-in-one path (5 samples).
render_mode use_half_res_pass, use_quarter_res_pass;

uniform float planet_radius = 6371000.0;
uniform float atmo_height = 100000.0;
uniform float cam_alt = 10.0;
uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_dir = vec3(0.3, 0.5, -0.8);
uniform vec3 moon_dir = vec3(-0.4, 0.6, 0.7);
uniform float moon_radius = 0.016;
uniform mat3 planet_to_tex = mat3(1.0);
uniform sampler2D earth_albedo : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D earth_clouds : filter_nearest_mipmap, repeat_enable;
uniform sampler2D moon_albedo : source_color, filter_nearest_mipmap, repeat_enable;
// camera position relative to the launch-site scene origin (render frame, metres)
uniform vec3 cam_site = vec3(0.0, 10.0, 0.0);
uniform float site_blend_start = 5000.0;
uniform float site_blend_end = 14000.0;
uniform vec2 coast_origin = vec2(350.0, -200.0);
uniform vec2 coast_normal = vec2(0.89443, -0.44721);
uniform vec2 coast_dir = vec2(-0.44721, -0.89443);
uniform vec4 grass_color : source_color = vec4(0.46, 0.64, 0.33, 1.0);
uniform vec4 sand_color : source_color = vec4(0.86, 0.80, 0.64, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.27, 0.62, 0.78, 1.0);
uniform vec4 deep_color : source_color = vec4(0.07, 0.25, 0.52, 1.0);
// look
// sun irradiance; the ground uses sun_intensity / PI * cos (Lambert), the same scale as
// the scene's DirectionalLight (energy ~ sun_intensity / PI), so both grounds match
uniform float sun_intensity = 9.0;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.96, 0.9);
uniform float exposure = 1.0;
uniform float star_brightness = 2.4;
uniform float milky_way = 0.6;
uniform float cloud_height = 7000.0;
uniform float cloud_opacity = 0.9;
// voxel sub-cells per cloud texel (finer blocks along the cloud edges)
uniform float cloud_subcells = 4.0;
uniform float ocean_roughness = 0.05;
uniform float glint = 0.06;
uniform float city_lights = 1.0;
uniform vec3 galactic_pole = vec3(0.38, 0.86, -0.34);
uniform vec3 rayleigh = vec3(5.8e-6, 13.5e-6, 33.1e-6);
uniform float mie = 1.3e-5;
uniform float h_rayleigh = 8500.0;
uniform float h_mie = 1000.0;
uniform float mie_g = 0.78;
// 0 = normal; 1 = map view (stars only)
uniform float map_mode = 0.0;
// samples of the in-scattering march (FlightSky sets it from GraphicsQuality)
uniform int scatter_steps = 9;


// ------------------------------------------------------------ noise / stars (as solar_sky)
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

vec3 star_color(float t) {
	vec3 c = mix(vec3(1.0, 0.62, 0.38), vec3(1.0, 0.9, 0.75), smoothstep(0.0, 0.3, t));
	c = mix(c, vec3(0.95, 0.97, 1.0), smoothstep(0.3, 0.6, t));
	return mix(c, vec3(0.62, 0.75, 1.0), smoothstep(0.65, 1.0, t));
}

vec3 star_layer(vec3 dir, float scale, float keep, float size, float boost) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = p - cell;
	float h = hash13(cell + 0.5);
	if (h < keep) {
		return vec3(0.0);
	}
	vec3 sp = 0.3 + 0.4 * hash33(cell * 1.31 + 7.0);
	float d = length(f - sp);
	float b = pow((h - keep) / (1.0 - keep), 2.2);
	float core = smoothstep(size, 0.0, d);
	float halo = exp(-d / size * 2.2) * 0.25 * b;
	return star_color(hash13(cell + 3.7)) * (core * core + halo) * b * boost;
}

// the smooth part of the background (quarter-resolution pass)
vec3 galaxy(vec3 dir) {
	vec3 col = vec3(0.0015, 0.002, 0.005);
	vec3 gp = normalize(galactic_pole);
	float g = dot(dir, gp);
	float band = exp(-g * g / 0.035);
	float wide = exp(-g * g / 0.16);
	float n1 = fbm3(dir * 3.0 + 4.0);
	float n2 = fbm3(dir * 9.0 + 1.3);
	float dust = smoothstep(0.42, 0.68, fbm3(dir * 6.0 + 11.0)) * exp(-g * g / 0.008);
	float mw = (band * (0.55 + 0.9 * n1 * n2) + wide * 0.25 * n1) * (1.0 - 0.75 * dust);
	col += mix(vec3(0.16, 0.17, 0.27), vec3(0.34, 0.29, 0.25), n2) * mw * milky_way * 0.2;
	float neb = smoothstep(0.55, 0.85, fbm3(dir * 2.2 + 21.0));
	col += vec3(0.2, 0.06, 0.26) * neb * 0.04;
	return col;
}

// the sharp part: three star layers (full resolution)
vec3 stars(vec3 dir) {
	float g = dot(dir, normalize(galactic_pole));
	float dens = exp(-g * g / 0.035) * 0.04;
	vec3 s = star_layer(dir, 70.0, 0.965 - dens, 0.16, 1.6);
	s += star_layer(dir, 150.0, 0.95 - dens, 0.2, 0.9);
	s += star_layer(dir, 320.0, 0.9 - dens * 2.0, 0.26, 0.45);
	return s * star_brightness;
}

vec3 space_background(vec3 dir) {
	return galaxy(dir) + stars(dir);
}

// ------------------------------------------------------------ atmosphere
float phase_r(float c) {
	return 3.0 / (16.0 * PI) * (1.0 + c * c);
}

float phase_m(float c) {
	float g = mie_g;
	float g2 = g * g;
	return 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + c * c)) / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g * c, 1.5));
}

// Chapman grazing-incidence approximation (Schüler): relative air mass towards a
// direction with cosine `mu` from the zenith at radius r (x = r / H).
float chapman(float x, float mu) {
	float c = sqrt(x * PI * 0.5);
	return c / ((c - 1.0) * max(mu, 0.0) + 1.0);
}

// Optical depth (Rayleigh, Mie) from a point at altitude h (radius r) towards the Sun,
// and a soft planet shadow factor.
vec3 sun_depth(float h, float r, float mu_s) {
	float R = planet_radius;
	float horizon = -sqrt(max(1.0 - (R / r) * (R / r), 0.0));
	float shadow = smoothstep(horizon - 0.012, horizon + 0.004, mu_s);
	float mu = max(mu_s, 0.0);
	float dr = exp(-h / h_rayleigh) * h_rayleigh * chapman(r / h_rayleigh, mu);
	float dm = exp(-h / h_mie) * h_mie * chapman(r / h_mie, mu);
	// below the horizon the sun ray grazes: add the extra air it crosses
	float graze = 1.0 + 6.0 * smoothstep(0.0, -0.2, mu_s);
	return vec3(dr * graze, dm * graze, shadow);
}

vec3 extinction(vec2 od) {
	return exp(-(rayleigh * od.x + mie * 1.1 * od.y));
}

// air column (Rayleigh, Mie) from altitude hh / radius rr to space, zenith cosine m >= 0
vec2 column_up(float hh, float rr, float m) {
	return vec2(exp(-hh / h_rayleigh) * h_rayleigh * chapman(rr / h_rayleigh, m),
			exp(-hh / h_mie) * h_mie * chapman(rr / h_mie, m));
}

// optical depth along the view ray (closed form): to the ground point, or through the
// whole atmosphere (rays looking down past the limb cross the tangent point twice)
vec2 view_depth(float h, float r0, float mu, bool ground, float mu_g) {
	if (ground) {
		return max(column_up(0.0, planet_radius, -mu_g) - column_up(h, r0, -mu), vec2(0.0));
	}
	if (mu >= 0.0) {
		return column_up(h, r0, mu);
	}
	float rt = r0 * sqrt(max(1.0 - mu * mu, 0.0));
	float ht = max(rt - planet_radius, 0.0);
	return max(2.0 * column_up(ht, rt, 0.0) - column_up(h, r0, -mu), vec2(0.0));
}

// ------------------------------------------------------------ ground
float site_coast(vec2 p) {
	float t = dot(p, coast_dir);
	return dot(p - coast_origin, coast_normal) + 40.0 * sin(t * 0.004) + 25.0 * sin(t * 0.011 + 1.3);
}

vec2 tex_uv(vec3 n_render) {
	vec3 n = planet_to_tex * n_render;
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.z, n.x);
	return vec2(lon / (2.0 * PI) + 0.5, 0.5 - lat / PI);
}

// returns rgb albedo, a = 1 for water (specular)
vec4 ground_albedo(vec3 n_render, vec3 site_p, float dist, out float relief, out float lights) {
	vec2 uv = tex_uv(n_render);
	vec2 tsize = vec2(textureSize(earth_albedo, 0));
	vec4 t = texture(earth_albedo, uv);
	relief = t.a;
	vec2 cell = floor(uv * tsize);
	vec2 f = fract(uv * tsize);
	float water = step(t.a, 0.004);
	vec3 col = t.rgb;
	// voxel look: per-column jitter, raised columns lighter, a soft AO line between columns
	float jit = hash12(cell);
	col *= 0.95 + 0.1 * jit;
	col *= mix(1.0, 0.92 + 0.16 * t.a, 1.0 - water);
	vec2 px = fwidth(uv * tsize);
	float edge = max(abs(f.x - 0.5), abs(f.y - 0.5));
	float ao_vis = 1.0 - smoothstep(0.08, 0.35, max(px.x, px.y));
	col *= 1.0 - 0.08 * smoothstep(0.4, 0.5, edge) * ao_vis * (1.0 - water * 0.6);
	// finer voxel patchwork inside each column when seen from low altitude (fields, woods)
	float fine_vis = smoothstep(0.6, 0.05, max(px.x, px.y));
	if (fine_vis > 0.0) {
		vec2 c8 = floor(uv * tsize * 8.0);
		vec2 c32 = floor(uv * tsize * 32.0);
		float v8 = hash12(c8 + 17.0);
		float v32 = hash12(c32 + 3.0);
		vec3 tint = mix(vec3(0.86, 0.95, 0.82), vec3(1.08, 1.04, 0.92), v8);
		vec3 fine = col * tint * (0.94 + 0.12 * v32);
		col = mix(col, fine, fine_vis * (1.0 - water));
		col = mix(col, col * (0.97 + 0.06 * v32), fine_vis * water);
	}
	lights = (1.0 - water) * step(0.87, hash12(cell * 1.37 + 5.1)) * (0.5 + 0.5 * hash12(cell + 9.0));
	// launch-site neighbourhood: the scene's own coast and colours
	float d = length(site_p.xz);
	float w = 1.0 - smoothstep(site_blend_start, site_blend_end, d);
	if (w > 0.0) {
		float s = site_coast(site_p.xz);
		vec2 sc = floor(site_p.xz / 6.0);
		vec3 grass = grass_color.rgb * (0.94 + 0.12 * hash12(sc));
		vec3 c = grass;
		float sw = 0.0;
		c = mix(c, sand_color.rgb, smoothstep(-45.0, -39.0, s));
		if (s > 0.0) {
			c = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 160.0, s));
			sw = 1.0;
		}
		col = mix(col, c, w);
		water = mix(water, sw, w);
		lights *= 1.0 - w;
	}
	return vec4(col, water);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	if (map_mode > 0.5) {
		COLOR = AT_CUBEMAP_PASS ? vec3(0.002, 0.003, 0.006) : space_background(dir);
	} else if (AT_QUARTER_RES_PASS) {
		COLOR = galaxy(dir);
		ALPHA = 1.0;
	} else {
	float R = planet_radius;
	float h = max(cam_alt, 0.5);
	float r0 = R + h;
	vec3 up = normalize(up_dir);
	vec3 sun = normalize(sun_dir);
	float mu = dot(dir, up);
	float b = r0 * mu;
	// ground: t² + 2bt + c = 0 with c = |C|² - R² = h (2R + h)
	float cg = h * (2.0 * R + h);
	float disc_g = b * b - cg;
	bool ground = disc_g > 0.0 && b < 0.0;
	float t_ground = ground ? cg / (-b + sqrt(disc_g)) : 0.0;
	// atmosphere shell
	float ha = atmo_height;
	float ca = (h - ha) * (2.0 * R + h + ha);
	float disc_a = b * b - ca;
	vec3 inscatter = vec3(0.0);
	vec3 trans = vec3(1.0);
	float cos_sun = dot(dir, sun);
	bool march = AT_CUBEMAP_PASS || AT_HALF_RES_PASS;
	if (disc_a > 0.0 && march) {
		float sq = sqrt(disc_a);
		float t0 = h > ha ? max(-b - sq, 0.0) : 0.0;
		float t1 = ground ? t_ground : -b + sq;
		if (t1 > t0) {
			int steps = AT_CUBEMAP_PASS ? 5 : max(scatter_steps, 3);
			// sample densely near the camera (exponential air)
			vec2 od = vec2(0.0);
			vec3 sum_r = vec3(0.0);
			vec3 sum_m = vec3(0.0);
			float prev_t = t0;
			for (int i = 0; i < steps; i++) {
				float k = (float(i) + 0.5) / float(steps);
				float tt = t0 + (t1 - t0) * k * k;
				float tn = t0 + (t1 - t0) * pow((float(i) + 1.0) / float(steps), 2.0);
				float tp = t0 + (t1 - t0) * pow(float(i) / float(steps), 2.0);
				float ds = tn - tp;
				// sample height without cancellation: r² - R² = c + 2bt + t²
				float rr2 = cg + 2.0 * b * tt + tt * tt;
				float rs = sqrt(R * R + rr2);
				float hs = max(rr2 / (rs + R), 0.0);
				vec3 pn = (up * r0 + dir * tt) / rs;
				float dr = exp(-hs / h_rayleigh) * ds;
				float dm = exp(-hs / h_mie) * ds;
				vec2 od_mid = od + vec2(dr, dm) * 0.5;
				od += vec2(dr, dm);
				vec3 sd = sun_depth(hs, rs, dot(pn, sun));
				vec3 tr = extinction(od_mid + sd.xy) * sd.z;
				sum_r += tr * dr;
				sum_m += tr * dm;
			}
			trans = extinction(od);
			inscatter = sun_intensity * sun_tint * (rayleigh * phase_r(cos_sun) * sum_r + mie * phase_m(cos_sun) * sum_m);
		}
	}
	if (AT_HALF_RES_PASS) {
		COLOR = inscatter;
		ALPHA = 1.0;
	} else {
	if (!AT_CUBEMAP_PASS) {
		inscatter = disc_a > 0.0 ? HALF_RES_COLOR.rgb : vec3(0.0);
		float mu_g = 0.0;
		if (ground) {
			mu_g = dot(normalize(up * r0 + dir * t_ground), dir);
		}
		trans = disc_a > 0.0 ? extinction(view_depth(h, r0, mu, ground, mu_g)) : vec3(1.0);
	}
	vec3 col;
	if (ground) {
		vec3 p = up * r0 + dir * t_ground;
		vec3 n = normalize(p);
		vec3 site_p = cam_site + dir * t_ground;
		float relief;
		float lights;
		vec4 alb = ground_albedo(n, site_p, t_ground, relief, lights);
		float mu_s = dot(n, sun);
		vec3 sd = sun_depth(0.0, R, mu_s);
		vec3 sun_tr = extinction(sd.xy) * sd.z;
		float lambert = max(mu_s, 0.0);
		// cloud shadow
		float shade = 1.0;
		if (!AT_CUBEMAP_PASS) {
			vec3 cp = normalize(n + sun * (cloud_height / R) / max(mu_s, 0.2));
			shade = 1.0 - texture(earth_clouds, tex_uv(cp)).r * 0.45 * smoothstep(1500.0, 30000.0, h);
		}
		vec3 sky_amb = vec3(0.35, 0.5, 0.85) * 0.09 * smoothstep(-0.25, 0.3, mu_s);
		float irr = sun_intensity / PI;
		col = alb.rgb * irr * (sun_tint * sun_tr * lambert * shade + sky_amb);
		// sun glint on water (GGX lobe, Schlick Fresnel)
		vec3 hv = normalize(sun - dir);
		float nh = max(dot(n, hv), 0.0);
		float a2 = ocean_roughness * ocean_roughness;
		float dd = nh * nh * (a2 - 1.0) + 1.0;
		float ggx = a2 / (PI * dd * dd);
		float fres = 0.02 + 0.98 * pow(1.0 - max(dot(-dir, hv), 0.0), 5.0);
		col += alb.a * ggx * fres * glint * sun_tr * shade * sun_intensity * step(0.0, mu_s);
		// night side: city lights
		float night = smoothstep(0.02, -0.12, mu_s);
		col += lights * night * city_lights * vec3(1.0, 0.72, 0.38) * 0.35 * smoothstep(20000.0, 120000.0, h);
		col = col * trans + inscatter;
	} else {
		vec3 bg = vec3(0.0);
		if (!AT_CUBEMAP_PASS) {
			// stars drown in a bright sky (and are not computed at all in daylight)
			float sky_l = dot(inscatter, vec3(0.3, 0.5, 0.2));
			float star_k = exp(-sky_l * 18.0);
			if (star_k > 0.004) {
				bg = (QUARTER_RES_COLOR.rgb + stars(dir)) * star_k;
			}
			// moon (voxel texture, lit by the sun)
			vec3 md = normalize(moon_dir);
			float cm = dot(dir, md);
			float cr = cos(moon_radius);
			if (cm > cr) {
				vec3 mx = normalize(cross(md, abs(md.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
				vec3 my = cross(mx, md);
				vec2 q = vec2(dot(dir, mx), dot(dir, my)) / sin(moon_radius);
				float z = sqrt(max(1.0 - dot(q, q), 0.0));
				vec3 mn = normalize(mx * q.x + my * q.y - md * z);
				vec2 muv = vec2(atan(dot(mn, my), dot(mn, mx)) / (2.0 * PI) + 0.5, 0.5 - asin(clamp(dot(mn, md), -1.0, 1.0)) / PI);
				vec3 malb = texture(moon_albedo, muv).rgb;
				float ml = max(dot(mn, sun), 0.0);
				float edge = smoothstep(1.0, 0.96, length(q));
				bg = mix(bg, malb * (ml * 2.2 + 0.015), edge);
			}
			// sun disk, corona and glare
			float sd = smoothstep(0.99996, 0.99999, cos_sun);
			bg += sun_tint * (sd * 60.0 + pow(max(cos_sun, 0.0), 4000.0) * 6.0 + pow(max(cos_sun, 0.0), 300.0) * 0.6
				+ pow(max(cos_sun, 0.0), 24.0) * 0.06 * (1.0 - smoothstep(0.0, 0.3, dot(inscatter, vec3(0.33)))));
		}
		col = bg * trans + inscatter;
	}
	// clouds over the ground, seen from above the deck
	if (ground && !AT_CUBEMAP_PASS && h > cloud_height) {
		float hc = cloud_height;
		float cc = (h - hc) * (2.0 * R + h + hc);
		float dc = b * b - cc;
		if (dc > 0.0) {
			float tc = cc / (-b + sqrt(dc));
			vec3 pc = normalize(up * r0 + dir * tc);
			vec2 cuv = tex_uv(pc);
			vec2 csz = vec2(textureSize(earth_clouds, 0));
			// smooth cover from the bilinear neighbours, cut into finer voxel blocks
			vec2 g = cuv * csz - 0.5;
			vec2 gi = floor(g);
			vec2 gf = fract(g);
			float c00 = texture(earth_clouds, (gi + vec2(0.5, 0.5)) / csz).r;
			float c10 = texture(earth_clouds, (gi + vec2(1.5, 0.5)) / csz).r;
			float c01 = texture(earth_clouds, (gi + vec2(0.5, 1.5)) / csz).r;
			float c11 = texture(earth_clouds, (gi + vec2(1.5, 1.5)) / csz).r;
			vec2 sub = floor(cuv * csz * cloud_subcells);
			vec2 sf = (sub + 0.5) / cloud_subcells - gi - 0.5;
			sf = clamp(sf, 0.0, 1.0);
			float cover = mix(mix(c00, c10, sf.x), mix(c01, c11, sf.x), sf.y);
			// break the decks up: value noise over the sub-cells (blocky, voxel-like holes)
			vec2 nq = sub * 0.23;
			vec2 ni = floor(nq);
			vec2 nf = fract(nq);
			nf = nf * nf * (3.0 - 2.0 * nf);
			float vn = mix(mix(hash12(ni), hash12(ni + vec2(1, 0)), nf.x), mix(hash12(ni + vec2(0, 1)), hash12(ni + vec2(1, 1)), nf.x), nf.y);
			float thr = 0.3 + 0.25 * hash12(sub) + 0.45 * smoothstep(0.35, 0.75, vn);
			float m = step(thr, cover) * (0.72 + 0.28 * smoothstep(0.3, 0.9, cover - thr + 0.5));
			float thick = 0.78 + 0.22 * hash12(sub * 1.7 + 3.0) - 0.12 * vn;
			float mu_c = dot(pc, sun);
			vec3 sdc = sun_depth(hc, R + hc, mu_c);
			vec3 ctr = extinction(sdc.xy) * sdc.z;
			vec3 ccol = vec3(thick) * (sun_intensity / PI * 0.8 * sun_tint * ctr * (0.2 + 0.8 * max(mu_c, 0.0)) + 0.01);
			float fade = smoothstep(cloud_height, cloud_height * 3.0, h) * cloud_opacity;
			col = mix(col, ccol * trans + inscatter * 0.6, m * fade);
		}
	}
	COLOR = col * exposure;
	}
	}
}
