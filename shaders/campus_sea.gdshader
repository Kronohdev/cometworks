shader_type spatial;
render_mode cull_disabled;
// The sea around the campus plateau (scenes/tycoon/campus.tscn: Terrain/Sea). Gentle animated
// swell through the normal only (the plane stays flat, so it costs nothing in vertices), a
// colour ramp from deep water to a teal shelf near the island, glinting sky reflections, and
// foam lines that roll in towards the beach. The shore is either the distance map of the
// island (`shore_map`: metres to the nearest land, written by tools/build_campus_island.gd,
// covering `shore_rect` = x, z, width, depth in world XZ) or, without a map, a rounded
// rectangle in world XZ (`shore_center`, `shore_half`).
// Near the land the water steps through soft toon bands: deep -> mid -> shallow teal -> a
// pale lagoon edge, with a wet-sand glow right at the beach.

uniform vec3 deep : source_color = vec3(0.016, 0.040, 0.085);
uniform vec3 shallow : source_color = vec3(0.050, 0.170, 0.200);
uniform vec3 foam_color : source_color = vec3(0.86, 0.92, 1.0);
uniform vec2 shore_center = vec2(6.0, 2.0);
uniform vec2 shore_half = vec2(90.0, 67.0);
uniform float shore_round = 3.0;
uniform bool use_shore_map = false;
uniform sampler2D shore_map : filter_linear, repeat_disable, hint_default_white;
uniform vec4 shore_rect = vec4(-170.0, -150.0, 360.0, 310.0);
// metres a full texel value stands for
uniform float shore_range = 48.0;
uniform vec3 mid : source_color = vec3(0.030, 0.090, 0.150);
uniform vec3 lagoon : source_color = vec3(0.180, 0.420, 0.420);
// toon bands of the colour ramp (metres from the shore where each band ends)
uniform float lagoon_width : hint_range(0.0, 20.0) = 3.5;
uniform float band_softness : hint_range(0.05, 4.0) = 0.8;
// width of the lighter shelf around the island (m)
uniform float shelf : hint_range(1.0, 80.0) = 22.0;
uniform float wave_scale : hint_range(0.01, 1.0) = 0.12;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.6;
// foam: how far out the rolling lines go, their spacing and speed
uniform float foam_reach : hint_range(0.5, 30.0) = 7.0;
uniform float foam_spacing : hint_range(0.5, 10.0) = 2.6;
uniform float foam_speed : hint_range(0.0, 4.0) = 0.45;
uniform float foam_strength : hint_range(0.0, 2.0) = 0.9;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.07;

varying vec3 wpos;

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

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float height(vec2 p, float t) {
	float h = sin(p.x * 0.9 + t * 1.1) * 0.5 + sin(p.y * 1.3 - t * 0.8 + p.x * 0.4) * 0.35;
	h += vnoise(p * 1.7 + vec2(t * 0.6, -t * 0.4)) * 0.8 + vnoise(p * 4.1 - vec2(t * 0.9, t * 0.3)) * 0.3;
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * wave_speed;
	float dist;
	if (use_shore_map) {
		vec2 uv = (p - shore_rect.xy) / shore_rect.zw;
		dist = texture(shore_map, uv).r * shore_range;
		// beyond the map: keep counting outward from its edge
		vec2 out_d = max(max(shore_rect.xy - p, p - (shore_rect.xy + shore_rect.zw)), vec2(0.0));
		dist += length(out_d);
	} else {
		dist = sd_round_box(p - shore_center, shore_half, shore_round);
	}
	// swell normal from the height field (finite differences)
	vec2 q = p * wave_scale * 4.0;
	float e = 0.15;
	float h0 = height(q, t);
	float hx = height(q + vec2(e, 0.0), t);
	float hz = height(q + vec2(0.0, e), t);
	float far = smoothstep(250.0, 600.0, length(wpos - CAMERA_POSITION_WORLD));
	vec3 nw = normalize(vec3((h0 - hx) * wave_strength * (1.0 - far * 0.8), e * 2.0, (h0 - hz) * wave_strength * (1.0 - far * 0.8)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 col;
	if (use_shore_map) {
		// soft-edged toon bands, the edges wobbling a little with the swell
		float d = dist + (vnoise(p * 0.15 + vec2(t * 0.05, 0.0)) - 0.5) * 1.6;
		col = deep;
		col = mix(col, mid, 1.0 - smoothstep(shelf - band_softness, shelf + band_softness, d));
		col = mix(col, shallow, 1.0 - smoothstep(shelf * 0.38 - band_softness, shelf * 0.38 + band_softness, d));
		col = mix(col, lagoon, 1.0 - smoothstep(lagoon_width - band_softness * 0.6, lagoon_width + band_softness * 0.6, d));
	} else {
		float near = 1.0 - smoothstep(0.0, shelf, dist);
		col = mix(deep, shallow, near * near);
	}
	// rolling foam: soft bands that travel to the shore, torn into patches by slow noise
	float foam = 0.0;
	if (dist < foam_reach + 2.0) {
		float warp = vnoise(p * 0.07 + vec2(0.0, t * 0.03)) * 2.0;
		float ph = (dist + warp) / foam_spacing + t * foam_speed * 2.0;
		float band = fract(ph);
		float line = exp(-pow((band - 0.5) * 7.0, 2.0));
		float patches = smoothstep(0.3, 0.65, vnoise(p * 0.11 + vec2(t * 0.05, -t * 0.04)));
		float froth = 0.55 + 0.45 * vnoise(p * 2.3 + vec2(t * 0.3, 0.0));
		float fade = 1.0 - smoothstep(0.0, foam_reach, dist);
		foam = line * patches * froth * fade * fade;
		// the wet, frothy edge right at the sand
		float edge = 1.0 - smoothstep(0.0, 0.8 + vnoise(p * 0.6 + vec2(t * 0.2)) * 1.4, dist);
		foam = max(foam, edge * (0.6 + 0.4 * froth));
	}
	foam *= foam_strength;
	ALBEDO = mix(col, foam_color, clamp(foam, 0.0, 1.0));
	ROUGHNESS = mix(roughness_value, 0.6, clamp(foam, 0.0, 1.0));
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
