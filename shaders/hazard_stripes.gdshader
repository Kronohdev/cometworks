shader_type spatial;
// Yellow/graphite safety stripes in world space (door jambs, pad markings, crane ends).
// With ring_mode the stripes are drawn only inside an annulus around the origin
// (floor marking around the launch pad); outside it the surface is transparent.
// Colours: palette HAZARD / INK (docs/art/palette.md).

uniform vec4 color_a : source_color = vec4(0.949, 0.718, 0.02, 1.0);
uniform vec4 color_b : source_color = vec4(0.137, 0.153, 0.18, 1.0);
uniform float stripe_width = 0.6;
uniform bool ring_mode = false;
uniform float ring_inner = 10.5;
uniform float ring_outer = 12.0;
uniform float ring_segments = 18.0;
uniform float glow = 0.0;
uniform float roughness = 0.55;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s;
	if (ring_mode) {
		float ang = atan(wpos.z, wpos.x);
		float r = length(wpos.xz);
		// slanted chevrons around the ring
		float t = ang * ring_segments / 6.2831853 + (r - ring_inner) * 0.5;
		float w = fwidth(t);
		s = smoothstep(0.5 - w, 0.5 + w, fract(t)) * (1.0 - smoothstep(1.0 - w, 1.0, fract(t)));
		float inside = step(ring_inner, r) * step(r, ring_outer);
		if (inside < 0.5) {
			discard;
		}
	} else {
		float t = (wpos.x + wpos.y + wpos.z) / (stripe_width * 2.0);
		float w = fwidth(t);
		s = smoothstep(0.5 - w, 0.5 + w, fract(t)) * (1.0 - smoothstep(1.0 - w, 1.0, fract(t)));
	}
	ALBEDO = mix(color_b.rgb, color_a.rgb, s);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	EMISSION = color_a.rgb * s * glow;
}
