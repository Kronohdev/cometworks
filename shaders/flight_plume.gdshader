shader_type spatial;
// Rocket exhaust plume on an open cone (scenes/flight/engine_plume.tscn). Additive and
// unshaded, so glow picks it up. Per-engine values are instance uniforms (no material
// copies): throttle, expansion (0 = sea level, 1 = vacuum) and the propellant colours.
//   sea level: narrow, long, bright core with Mach diamonds
//   vacuum:    the plume balloons out (vertex widening) and turns faint and diffuse
// The cone mesh is 1 m tall and centred: along = 0 at the nozzle (top), 1 at the tail.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

instance uniform float throttle = 1.0;
instance uniform float expansion = 0.0;
instance uniform vec4 core_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
instance uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
instance uniform float seed = 0.0;
uniform float intensity = 2.2;
uniform float diamonds = 1.0;
uniform float is_core = 0.0;

varying float along;
varying vec3 vnormal;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void vertex() {
	along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
	// widen towards the tail as the ambient pressure drops (under-expanded jet)
	float t = along;
	float widen = 1.0 + t * (0.15 + expansion * 2.6) + t * t * expansion * 1.6;
	float flick = 1.0 + 0.05 * sin(TIME * 47.0 + seed * 13.0 + t * 9.0);
	VERTEX.xz *= widen * flick;
	vnormal = NORMAL;
}

void fragment() {
	float t = clamp(along, 0.0, 1.0);
	// soft edges: fade where the surface is seen edge-on
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(facing, 1.6);
	// brightness along the plume: hot at the nozzle, fading towards the tail
	float fall = pow(1.0 - t, mix(1.1, 2.6, expansion));
	float flick = 0.85 + 0.15 * noise1(TIME * 31.0 + seed * 7.0 + t * 6.0);
	// Mach diamonds (only in thick air)
	float md = pow(0.5 + 0.5 * cos(t * 38.0 - 0.6), 6.0) * (1.0 - expansion) * diamonds * smoothstep(0.02, 0.1, t) * (1.0 - t);
	vec3 col = mix(core_color.rgb, edge_color.rgb, smoothstep(0.0, 0.55, t + (1.0 - soft) * 0.4));
	col = mix(col, core_color.rgb * 1.6, is_core);
	float a = soft * fall * flick * (1.0 - expansion * 0.55);
	a += md * 0.9 * soft;
	// a bright throat right at the nozzle
	a += smoothstep(0.08, 0.0, t) * 1.5 * soft;
	ALBEDO = col * a * intensity * clamp(throttle, 0.0, 1.0);
}
