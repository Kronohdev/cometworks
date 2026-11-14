shader_type spatial;
// Comet tail ribbon for the main-menu shots (scenes/menu/props/comet_mae_gelo.tscn). The
// mesh is a QuadMesh with size (1, 1) and center_offset (0.5, 0, 0): local +X runs from the
// head (0) to the tip (1). The node's X scale is the tail length, its Y scale the width; the
// ribbon spins around its own axis to face the camera. Additive, aurora gradient
// (teal -> violet -> orange) with soft striations that flow away from the head.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 head_color : source_color = vec3(0.8, 0.96, 1.0);
uniform vec3 color_a : source_color = vec3(0.247, 0.878, 0.773);
uniform vec3 color_b : source_color = vec3(0.557, 0.486, 1.0);
uniform vec3 color_c : source_color = vec3(1.0, 0.541, 0.239);
uniform float intensity : hint_range(0.0, 8.0) = 1.2;
// half-width at the head and at the tip, as a fraction of the node's Y scale
uniform float width_start : hint_range(0.0, 1.0) = 0.04;
uniform float width_end : hint_range(0.0, 1.0) = 0.4;
// sideways bend of the tip (dust tails curve), in half-widths
uniform float bend : hint_range(-1.0, 1.0) = 0.0;
uniform float streaks : hint_range(0.0, 1.0) = 0.6;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.04;
uniform float fade_power : hint_range(0.2, 6.0) = 1.4;
// where along the tail the colour reaches teal / the gradient end
uniform float gradient_scale : hint_range(0.1, 2.0) = 1.0;

varying float v_len;

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
	vec3 wp = p_axis + side * VERTEX.y * hgt;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	v_len = length(axis);
}

vec3 grad(float s) {
	s = clamp(s / gradient_scale, 0.0, 1.0);
	return s < 0.5 ? mix(color_a, color_b, s * 2.0) : mix(color_b, color_c, s * 2.0 - 1.0);
}

void fragment() {
	float s = UV.x;
	float y = (0.5 - UV.y) * 2.0;
	float w = mix(width_start, width_end, pow(s, 0.85));
	float yc = y - bend * s * s;
	float prof = exp(-(yc * yc) / max(w * w, 1e-5) * 2.2);
	float fade = pow(clamp(1.0 - s, 0.0, 1.0), fade_power);
	float n = vnoise(vec2(yc / max(w, 1e-3) * 3.0, s * 3.0 - TIME * flow_speed))
			* 0.65 + vnoise(vec2(yc / max(w, 1e-3) * 9.0, s * 7.0 - TIME * flow_speed * 2.0)) * 0.35;
	float st = mix(1.0, 0.35 + 1.3 * n, streaks);
	vec3 c = mix(head_color, grad(s), smoothstep(0.0, 0.14, s));
	ALBEDO = c * prof * fade * st * intensity;
}
