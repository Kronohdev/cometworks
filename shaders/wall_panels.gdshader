shader_type spatial;
// Wall / ceiling cladding for the assembly building, procedural (no textures): panel
// seams, rivet rows, per-panel tint variation, a painted dado band along the floor with
// a thin safety stripe, and optional glowing window/light strips every N panel rows.
// Works in world space, so any quad size keeps the same panel scale.
// Colours follow the MARGIN palette (docs/art/palette.md).

uniform vec4 base_color : source_color = vec4(0.875, 0.89, 0.906, 1.0);
uniform vec4 seam_color : source_color = vec4(0.62, 0.65, 0.69, 1.0);
uniform vec4 strip_color : source_color = vec4(0.75, 0.914, 1.0, 1.0);
uniform vec2 panel_size = vec2(4.0, 6.0);
uniform float seam_width = 0.06;
uniform int strip_every = 4;
uniform float strip_glow = 1.6;
uniform float strip_height = 0.9;
uniform float strip_min_height = 0.0; // walls: no strips below this height
uniform float grime_height = 14.0;
uniform float grime_amount = 0.12;
uniform float metallic_amount = 0.1;
uniform float roughness_base = 0.6;
uniform bool use_xz = false; // ceilings: map world X/Z instead of the wall plane
// painted dado (lower band) + safety stripe on top of it
uniform float dado_height = 0.0;
uniform vec4 dado_color : source_color = vec4(0.235, 0.267, 0.314, 1.0);
uniform vec4 band_color : source_color = vec4(0.949, 0.718, 0.02, 1.0);
uniform float band_width = 0.35;

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv;
	if (use_xz) {
		uv = wpos.xz;
	} else {
		uv = abs(wnormal.x) > 0.5 ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
	}
	vec2 cell = uv / panel_size;
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	vec2 seam_uv = min(f, 1.0 - f) * panel_size;
	float aa = max(fwidth(uv.x), fwidth(uv.y));
	float seam = 1.0 - smoothstep(0.0, seam_width + aa, min(seam_uv.x, seam_uv.y));
	vec2 rv = fract(uv / 0.5);
	float rivet_line = step(seam_uv.y, 0.18) * step(0.12, seam_uv.y);
	float rivet = rivet_line * (1.0 - smoothstep(0.08, 0.14, length(rv - 0.5)));
	float tint = (hash(id) - 0.5) * 0.05;
	float grime = use_xz ? 0.0 : (1.0 - smoothstep(0.0, grime_height, wpos.y)) * grime_amount;
	vec3 col = base_color.rgb * (1.0 + tint) * (1.0 - grime);
	col = mix(col, seam_color.rgb, seam);
	col -= vec3(rivet * 0.05);
	float rough = roughness_base + seam * 0.25;
	if (!use_xz && dado_height > 0.0) {
		float dado = 1.0 - step(dado_height, wpos.y);
		float band = step(dado_height, wpos.y) * (1.0 - step(dado_height + band_width, wpos.y));
		col = mix(col, dado_color.rgb * (1.0 + tint), dado);
		col = mix(col, band_color.rgb, band);
		rough = mix(rough, 0.5, dado);
	}
	ALBEDO = col;
	METALLIC = metallic_amount;
	ROUGHNESS = rough;
	float strip = 0.0;
	if (strip_every > 0 && int(mod(id.y, float(strip_every))) == 0 && (use_xz || wpos.y > strip_min_height)) {
		strip = 1.0 - smoothstep(strip_height * 0.5, strip_height * 0.5 + 0.08, abs(f.y - 0.5) * panel_size.y);
		// strips are made of separate window lights, interrupted at the vertical seams
		strip *= smoothstep(0.25, 0.45, seam_uv.x);
	}
	ALBEDO = mix(ALBEDO, strip_color.rgb * 0.6, strip);
	EMISSION = strip_color.rgb * strip * strip_glow;
}
