shader_type spatial;
// Campus roads and plaza (scenes/tycoon/campus.tscn: Roads/*). src/tycoon/campus.gd sets `era`
// (1..5) so the paths grow with the agency:
//   1 packed dirt with tyre ruts and pebbles      2 fresh gravel-asphalt
//   3 asphalt with a dashed centre line           4 dark asphalt, edge lines
//   5 launch-base concrete slabs with hazard edges
// The plaza (`plaza = true`) goes from trodden earth to paving tiles with a star inlay.
// Roads are box meshes: set the instance parameter `along_z` on roads that run along Z.

uniform int era : hint_range(1, 5) = 1;
uniform bool plaza = false;
instance uniform bool along_z = false;
// half the width of the road (m), for ruts and edge lines
instance uniform float half_width = 2.5;
uniform vec3 dirt : source_color = vec3(0.430, 0.360, 0.270);
uniform vec3 dirt_dark : source_color = vec3(0.345, 0.285, 0.210);
uniform vec3 gravel : source_color = vec3(0.235, 0.245, 0.270);
uniform vec3 asphalt : source_color = vec3(0.150, 0.160, 0.185);
uniform vec3 asphalt_night : source_color = vec3(0.115, 0.125, 0.150);
uniform vec3 concrete : source_color = vec3(0.330, 0.345, 0.370);
uniform vec3 paint : source_color = vec3(0.900, 0.880, 0.780);
uniform vec3 hazard : source_color = vec3(1.0, 0.541, 0.239);
uniform vec3 star_inlay : source_color = vec3(0.247, 0.878, 0.773);
uniform float star_glow : hint_range(0.0, 4.0) = 0.6;

varying vec3 wpos;
varying vec3 mpos;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mpos = VERTEX;
}

float star_shape(vec2 p, float r) {
	// four-pointed star (the Cometlings' antenna bulb)
	vec2 a = abs(p);
	return step(a.x * a.y * 9.0 + (a.x + a.y) * 0.35, r * 0.5);
}

void fragment() {
	vec2 w = wpos.xz;
	float along = along_z ? mpos.z : mpos.x;
	float across = along_z ? mpos.x : mpos.z;
	vec2 cell = floor(w / 0.25);
	float grain = hash12(cell);
	float n = vnoise(w * 0.4);
	vec3 col;
	float rough = 0.95;
	vec3 emit = vec3(0.0);
	if (plaza) {
		vec2 p = mpos.xz;
		if (era <= 1) {
			col = mix(dirt, dirt_dark, smoothstep(0.3, 0.8, n)) * (0.92 + grain * 0.16);
			// a trodden ring around the monument
			float r = length(p);
			col *= 1.0 - 0.12 * smoothstep(1.4, 2.2, r) * (1.0 - smoothstep(2.8, 3.8, r));
		} else {
			vec3 base = era >= 5 ? concrete : mix(gravel, concrete, 0.35);
			vec2 t = fract(p / 1.0);
			vec2 ti = floor(p / 1.0);
			float seam = 1.0 - (step(0.04, t.x) * step(0.04, t.y));
			col = base * (0.9 + hash12(ti + 3.0) * 0.18) * (1.0 - seam * 0.35);
			float r = length(p);
			// a ring and the star inlay around the monument (era 3+)
			if (era >= 3) {
				float ring = smoothstep(0.06, 0.0, abs(r - 3.2));
				col = mix(col, star_inlay * 0.6, ring);
				float s = star_shape(p, 2.6);
				col = mix(col, star_inlay * 0.5, s * (1.0 - step(r, 1.0)));
				emit = star_inlay * star_glow * (ring * 0.6 + s * 0.25) * float(era >= 4);
			}
		}
	} else if (era <= 1) {
		col = mix(dirt, dirt_dark, smoothstep(0.35, 0.75, n));
		// two tyre ruts and a grassy hump between them
		float rut = exp(-pow((abs(across) - 1.05) / 0.32, 2.0));
		col = mix(col, dirt_dark * 0.85, rut * 0.75);
		col *= 1.0 - 0.06 * smoothstep(0.4, 0.0, abs(across));
		col *= 0.9 + grain * 0.2;
		// a few pebbles
		col = mix(col, dirt_dark * 0.7, step(0.985, hash12(floor(w / 0.1))) * 0.8);
	} else if (era == 2) {
		col = gravel * (0.85 + grain * 0.3) * (0.92 + n * 0.16);
		rough = 0.9;
	} else {
		vec3 base = era == 3 ? asphalt : asphalt_night;
		if (era >= 5) {
			base = concrete * 0.8;
		}
		col = base * (0.94 + grain * 0.12) * (0.95 + n * 0.1);
		// patched / darker tyre tracks
		col *= 1.0 - 0.07 * exp(-pow((abs(across) - 1.1) / 0.45, 2.0));
		rough = 0.82;
		if (era >= 5) {
			// slab seams every 4 m along, one seam down the middle
			float s1 = step(abs(fract(along / 4.0 + 0.5) - 0.5) * 4.0, 0.04);
			float s2 = step(abs(across), 0.03);
			col *= 1.0 - (max(s1, s2)) * 0.35;
			// hazard-striped edges
			float edge = step(half_width - 0.35, abs(across)) * step(abs(across), half_width - 0.1);
			float stripe = step(0.5, fract((along + across) * 0.8));
			col = mix(col, mix(hazard, asphalt_night, stripe), edge);
		} else {
			// dashed centre line
			float dash = step(abs(across), 0.07) * step(0.5, fract(along / 3.0));
			col = mix(col, paint, dash * (era == 3 ? 0.8 : 0.9));
			if (era >= 4) {
				float edge_line = step(abs(abs(across) - (half_width - 0.3)), 0.06);
				col = mix(col, paint * 0.9, edge_line);
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	EMISSION = emit;
}
