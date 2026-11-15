shader_type spatial;
// The Conferência dos Cometinhos' ground (scenes/tycoon/conference/conference_fair.tscn: Ground,
// Plaza). World-space like the campus ground (shaders/campus_terrain.gdshader), so the meshes
// need no UVs, and pixelated in voxel-sized cells like the campus props:
//   paving = true   the fair's plaza: cream stone flags in running bond with grout seams, a
//                   brick promenade (an ellipse round the plaza) and brick walkways from the
//                   gate to the exhibit and from the exhibit to the three stands, each with a
//                   pale stone border; a rosette of navy and mint tiles with a glowing ring
//                   and four star rays round the exhibit
//   paving = false  the field round it: the campus grass (lush / dry / clover patches, cell
//                   jitter), a worn earth fringe hugging the plaza's edge and a trodden track
//                   running out of the gate
// Positions are in the fair's local metres (the fair sits at the world origin; `origin` shifts
// it otherwise). Lighting: the Cometworks toon light (shaders/include/cw_toon.gdshaderinc).
#define CW_TOON_RIM_DEFAULT 0.0
#include "res://shaders/include/cw_toon.gdshaderinc"

uniform bool paving = true;
uniform vec2 origin = vec2(0.0);
// the plaza's half size (x, z) and where the exhibit stands
uniform vec2 plaza_half = vec2(28.0, 22.0);
uniform vec2 exhibit = vec2(0.0, -5.0);
uniform vec2 stand_a = vec2(-17.0, -11.0);
uniform vec2 stand_b = vec2(0.0, -16.5);
uniform vec2 stand_c = vec2(17.0, -11.0);
uniform vec2 gate = vec2(0.0, 20.5);
// the promenade: centre, radii, half width
uniform vec2 ring_centre = vec2(0.0, -1.5);
uniform vec2 ring_radii = vec2(20.0, 14.0);
uniform float walk_half = 1.25;

group_uniforms stone;
uniform vec3 stone_a : source_color = vec3(0.930, 0.850, 0.700);
uniform vec3 stone_b : source_color = vec3(0.860, 0.770, 0.630);
uniform vec3 grout : source_color = vec3(0.640, 0.560, 0.470);
uniform vec3 brick_a : source_color = vec3(0.830, 0.560, 0.420);
uniform vec3 brick_b : source_color = vec3(0.740, 0.470, 0.360);
uniform vec3 border : source_color = vec3(0.950, 0.900, 0.800);
uniform vec3 rosette_dark : source_color = vec3(0.169, 0.165, 0.361);
uniform vec3 rosette_mid : source_color = vec3(0.300, 0.290, 0.560);
uniform vec3 star_inlay : source_color = vec3(0.435, 0.878, 0.745);
uniform float star_glow : hint_range(0.0, 4.0) = 0.7;
uniform float tile_size = 1.2;
// the seams' half width, in tile fractions
uniform float seam_width = 0.022;
// one brick of the walkways (m)
uniform vec2 brick = vec2(0.6, 0.3);

group_uniforms grass;
uniform vec3 grass_a : source_color = vec3(0.235, 0.380, 0.255);
uniform vec3 grass_b : source_color = vec3(0.300, 0.450, 0.270);
uniform vec3 grass_dry : source_color = vec3(0.470, 0.470, 0.290);
uniform vec3 clover : source_color = vec3(0.180, 0.330, 0.240);
uniform vec3 earth : source_color = vec3(0.420, 0.335, 0.250);
uniform float fringe : hint_range(0.0, 6.0) = 2.2;

uniform float cell_size : hint_range(0.05, 1.0) = 0.25;
uniform float jitter : hint_range(0.0, 0.5) = 0.07;

varying vec3 wpos;
varying vec3 wnrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return length(p - a - ab * t);
}

// distance outside the plaza rectangle (negative inside)
float rect_dist(vec2 p) {
	vec2 d = abs(p) - plaza_half;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// the walkways' distance field: 0 on a walkway's centre line
float walk_dist(vec2 p) {
	float d = seg_dist(p, vec2(gate.x, plaza_half.y), exhibit);
	vec2 to_a = normalize(stand_a - exhibit);
	vec2 to_b = normalize(stand_b - exhibit);
	vec2 to_c = normalize(stand_c - exhibit);
	d = min(d, seg_dist(p, exhibit, stand_a - to_a * 1.4));
	d = min(d, seg_dist(p, exhibit, stand_b - to_b * 1.4));
	d = min(d, seg_dist(p, exhibit, stand_c - to_c * 1.4));
	// the elliptical promenade (approximate distance, fine at these radii)
	vec2 q = (p - ring_centre) / ring_radii;
	float k = length(q);
	float ring = abs(k - 1.0) * min(ring_radii.x, ring_radii.y);
	return min(d, ring);
}

vec3 paving_color(vec2 p, out vec3 emit) {
	emit = vec3(0.0);
	vec2 cell = floor(p / cell_size);
	vec2 c = (cell + 0.5) * cell_size;           // voxel-pixel centre
	float grain = hash12(cell + 5.0);
	float wear = fbm(c * 0.12 + 9.0);
	// stone flags in running bond; the seams are drawn at full resolution (thin, soft) while
	// the flags' colour keeps the voxel-pixel grain
	float row = floor(p.y / tile_size);
	vec2 tp = vec2(p.x / tile_size + 0.5 * mod(row, 2.0), p.y / tile_size);
	vec2 ti = floor(tp);
	vec2 tf = fract(tp);
	vec2 aa = fwidth(tp) * 1.2;
	vec2 sd = min(tf, 1.0 - tf);
	float seam = 1.0 - smoothstep(seam_width, seam_width + aa.x, sd.x) * smoothstep(seam_width, seam_width + aa.y, sd.y);
	float th = hash12(ti + 3.0);
	vec3 col = mix(stone_a, stone_b, th);
	col = mix(col, stone_b * 0.88, step(0.93, hash12(ti + 41.0)));   // the odd darker flag
	col = mix(col, grout, seam * 0.7);
	// walkways: brick stretcher bond with a pale stone border
	float wd = walk_dist(c);
	if (wd < walk_half + 0.3) {
		if (wd < walk_half) {
			float brow = floor(p.y / brick.y);
			vec2 bp = vec2(p.x / brick.x + 0.5 * mod(brow, 2.0), p.y / brick.y);
			vec2 bi = floor(bp);
			vec2 bf = fract(bp);
			vec2 baa = fwidth(bp) * 1.2;
			vec2 bd = min(bf, 1.0 - bf) * brick;
			float bseam = 1.0 - smoothstep(0.025, 0.025 + baa.x * brick.x, bd.x) * smoothstep(0.025, 0.025 + baa.y * brick.y, bd.y);
			col = mix(brick_a, brick_b, hash12(bi + 7.0));
			col = mix(col, grout, bseam * 0.55);
		} else {
			col = border * (0.94 + hash12(floor(c / 0.5)) * 0.08);
		}
	}
	// the exhibit's rosette
	vec2 e = c - exhibit;
	float r = length(e);
	if (r < 5.4) {
		float ang = atan(e.y, e.x);
		float ringi = floor(r / 0.9);
		float segs = 6.0 + ringi * 6.0;
		float si = floor((ang / 6.2831853 + 0.5) * segs);
		vec3 rc = mod(si + ringi, 2.0) < 1.0 ? rosette_dark : rosette_mid;
		rc *= 0.92 + hash12(vec2(si, ringi)) * 0.12;
		float rseam = step(fract(r / 0.9), 0.08);
		rc *= 1.0 - rseam * 0.3;
		// four star rays toward the corners of the compass
		vec2 a = abs(e);
		float ray = step(a.x * a.y * 1.6 + (a.x + a.y) * 0.18, 1.0) * step(1.9, r);
		rc = mix(rc, star_inlay * 0.75, ray);
		float edge = smoothstep(0.16, 0.0, abs(r - 5.1));
		rc = mix(rc, star_inlay, edge);
		col = mix(col, rc, step(r, 5.25));
		emit = star_inlay * star_glow * (edge * 0.8 + ray * 0.2);
	}
	col *= 0.93 + wear * 0.14;
	col *= 1.0 + (grain - 0.5) * jitter * 2.0;
	// a soft trodden darkening along the plaza's very edge
	col *= 1.0 - 0.08 * smoothstep(-1.5, 0.0, rect_dist(c));
	return col;
}

vec3 grass_color(vec2 p) {
	vec2 cell = floor(p / cell_size);
	vec2 c = (cell + 0.5) * cell_size;
	float big = fbm(c * 0.035);
	float mid = fbm(c * 0.16 + 4.0);
	float fine = vnoise(c * 0.9);
	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.7, big));
	col = mix(col, clover, smoothstep(0.62, 0.78, mid) * 0.7);
	col = mix(col, grass_dry, smoothstep(0.55, 0.85, big * 0.6 + fine * 0.4) * 0.35);
	// worn earth hugging the plaza, ragged
	float rd = rect_dist(c);
	float ragged = fringe * (0.45 + 0.9 * fbm(c * 0.5 + 2.0));
	float worn = 1.0 - smoothstep(ragged * 0.4, ragged, rd);
	// the track out of the gate
	float track = abs(c.x - gate.x) - (2.0 + vnoise(c * 0.6) * 0.8);
	worn = max(worn, (1.0 - smoothstep(-0.4, 0.4, track)) * step(0.0, c.y - plaza_half.y)
			* (1.0 - smoothstep(14.0, 26.0, c.y - plaza_half.y)));
	vec3 dirt = earth * (0.9 + fine * 0.2);
	col = mix(col, dirt, worn * 0.9);
	col *= 1.0 + (hash12(cell + 17.0) - 0.5) * jitter * 2.0;
	return col;
}

void fragment() {
	vec2 p = wpos.xz - origin;
	vec3 col;
	vec3 emit = vec3(0.0);
	if (paving) {
		col = paving_color(p, emit);
		if (normalize(wnrm).y < 0.5) {
			col = grout;   // the slab's thin edge
			emit = vec3(0.0);
		}
	} else {
		col = grass_color(p);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.3;
	EMISSION = emit + cw_toon_rim(NORMAL, VIEW, ALBEDO, VERTEX, INV_VIEW_MATRIX);
}
