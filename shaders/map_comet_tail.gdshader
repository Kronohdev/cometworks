shader_type spatial;
// The comet's tails on the solar-system map (scenes/flight/flight_map.tscn > Bodies/MaeGelo).
// The mesh is a QuadMesh of size (1, 1) with center_offset (0.5, 0, 0): local +X runs from the
// nucleus (0) to the tip (1). FlightMap sets the node's X axis to the tail (away from the Sun,
// its real length) and its Y scale to the width; the ribbon turns about its own axis to face
// the camera and is never thinner than min_px. Additive: a straight blue ion tail and a curved,
// creamy dust tail are two copies with different colours.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 head_color : source_color = vec3(0.86, 0.97, 1.0);
uniform vec3 tail_color : source_color = vec3(0.45, 0.75, 1.0);
uniform vec3 tip_color : source_color = vec3(0.56, 0.49, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.4;
// half-width at the nucleus and at the tip, as a fraction of the node's Y scale
uniform float width_start : hint_range(0.0, 1.0) = 0.05;
uniform float width_end : hint_range(0.0, 1.0) = 0.45;
// sideways bend of the tip (dust tails curve back along the orbit), in half-widths
uniform float bend : hint_range(-1.0, 1.0) = 0.0;
uniform float streaks : hint_range(0.0, 1.0) = 0.5;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.05;
uniform float fade_power : hint_range(0.2, 6.0) = 1.3;
// the ribbon's full width on screen is at least this many pixels
uniform float min_px : hint_range(0.0, 40.0) = 6.0;
// 0..1: the whole tail (the comet only grows one near the Sun; FlightMap sets it)
instance uniform float activity = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 axis = MODEL_MATRIX[0].xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float hgt = length(MODEL_MATRIX[1].xyz);
	vec3 p_axis = origin + axis * VERTEX.x;
	vec3 to_cam = CAMERA_POSITION_WORLD - p_axis;
	vec3 side = cross(normalize(axis), to_cam);
	float sl = length(side);
	side = sl > 1e-5 ? side / sl : normalize(MODEL_MATRIX[1].xyz);
	// never thinner than min_px on screen
	vec4 vp = VIEW_MATRIX * vec4(p_axis, 1.0);
	float px_world = -vp.z * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	hgt = max(hgt, min_px * px_world);
	vec3 wp = p_axis + side * VERTEX.y * hgt;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	float s = UV.x;
	float y = (0.5 - UV.y) * 2.0;
	float w = mix(width_start, width_end, pow(s, 0.8));
	float yc = y - bend * s * s;
	float prof = exp(-(yc * yc) / max(w * w, 1e-5) * 2.2);
	float fade = pow(clamp(1.0 - s, 0.0, 1.0), fade_power);
	float n = vnoise(vec2(yc / max(w, 1e-3) * 3.0, s * 3.0 - TIME * flow_speed)) * 0.65
			+ vnoise(vec2(yc / max(w, 1e-3) * 9.0, s * 7.0 - TIME * flow_speed * 2.0)) * 0.35;
	float st = mix(1.0, 0.35 + 1.3 * n, streaks);
	vec3 c = mix(head_color, mix(tail_color, tip_color, smoothstep(0.3, 1.0, s)), smoothstep(0.0, 0.12, s));
	ALBEDO = c * prof * fade * st * intensity * activity;
}
