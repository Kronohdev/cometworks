shader_type spatial;
// One of Mãe-Gelo's tails (scenes/menu/props/comet_mae_gelo.tscn > DustTail / IonTail). The mesh
// is a QuadMesh of size (1, 1) with center_offset (0.5, 0, 0): local +X runs from the head (0)
// to the tip (1), away from the Sun. The node's X scale is the length, its Y scale the width,
// and the ribbon turns round its own axis to face the camera (it never shows its edge).
//   dust tail   curved (bend), wide, creamy gold turning amber, fanned by fine synchrone rays
//               from the head and brighter along its leading (outer) edge
//   ion tail    straight, narrow, electric blue, made of fast streamers with slow kinks
// `bands` posterises the light into soft storybook steps (0 = smooth). Additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 head_color : source_color = vec3(1.0, 0.98, 0.9);
uniform vec3 near_color : source_color = vec3(1.0, 0.9, 0.6);
uniform vec3 mid_color : source_color = vec3(1.0, 0.76, 0.38);
uniform vec3 far_color : source_color = vec3(0.95, 0.5, 0.32);
uniform float intensity : hint_range(0.0, 8.0) = 1.0;
// half-width at the head and at the tip, as a fraction of the node's Y scale
uniform float width_start : hint_range(0.0, 1.0) = 0.05;
uniform float width_end : hint_range(0.0, 1.0) = 0.45;
// sideways bend of the tip (dust tails curve), in half-widths
uniform float bend : hint_range(-1.0, 1.0) = 0.0;
// synchrone rays fanning from the head (dust) and how many
uniform float rays : hint_range(0.0, 1.0) = 0.0;
uniform float ray_count : hint_range(1.0, 40.0) = 11.0;
// fine streamers along the tail (ion) and their flow
uniform float streaks : hint_range(0.0, 1.0) = 0.5;
uniform float streak_scale : hint_range(0.5, 20.0) = 4.0;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.05;
// slow sideways waves (the solar wind tugging the ion tail)
uniform float kinks : hint_range(0.0, 0.5) = 0.0;
// brighter outer edge of the curve (dust tails pile up on their leading side)
uniform float edge_bright : hint_range(0.0, 2.0) = 0.0;
uniform float fade_power : hint_range(0.2, 6.0) = 1.4;
// how quickly the colour moves from near to far
uniform float gradient_scale : hint_range(0.1, 2.0) = 1.0;
uniform float bands : hint_range(0.0, 10.0) = 0.0;

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
	// keep the curve on the node's own +Y side whichever way the ribbon turned
	if (dot(side, MODEL_MATRIX[1].xyz) < 0.0) {
		side = -side;
	}
	vec3 wp = p_axis + side * VERTEX.y * hgt;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

vec3 grad(float s) {
	s = clamp(s / gradient_scale, 0.0, 1.0);
	return s < 0.5 ? mix(near_color, mid_color, s * 2.0) : mix(mid_color, far_color, s * 2.0 - 1.0);
}

float posterise(float v) {
	if (bands <= 0.0) {
		return v;
	}
	float x = v * bands;
	return (floor(x) + smoothstep(0.3, 0.7, fract(x))) / bands;
}

void fragment() {
	float s = UV.x;
	float y = (0.5 - UV.y) * 2.0;
	float w = mix(width_start, width_end, pow(s, 0.8));
	float yc = y - bend * s * s;
	yc -= kinks * sin(s * 9.0 - TIME * 0.7) * s * w * 2.0;
	float across = yc / max(w, 1e-4);
	float prof = exp(-across * across * 2.0);
	// the leading edge (the outer side of the curve) is brighter in a dust tail
	if (edge_bright > 0.0) {
		float lead = -sign(bend) * across;
		prof *= 1.0 + edge_bright * smoothstep(-0.2, 0.9, lead) * smoothstep(1.6, 0.6, abs(across));
	}
	float fade = pow(clamp(1.0 - s, 0.0, 1.0), fade_power) * smoothstep(0.0, 0.04, s + 0.01);
	float detail = 1.0;
	if (streaks > 0.0) {
		float n = vnoise(vec2(across * streak_scale, s * 3.0 - TIME * flow_speed)) * 0.6
				+ vnoise(vec2(across * streak_scale * 2.7, s * 8.0 - TIME * flow_speed * 1.7)) * 0.4;
		detail *= mix(1.0, 0.3 + 1.4 * n, streaks * smoothstep(0.02, 0.2, s));
	}
	if (rays > 0.0) {
		// straight lines from the head at different angles: synchrones
		float ang = yc / max(s + 0.03, 1e-3);
		float r = 0.5 + 0.5 * sin(ang * ray_count + vnoise(vec2(ang * 3.0, 1.7)) * 3.0);
		detail *= mix(1.0, 0.45 + 0.9 * r, rays * smoothstep(0.05, 0.35, s));
	}
	float v = posterise(clamp(prof * fade * detail, 0.0, 1.4));
	vec3 c = mix(head_color, grad(s), smoothstep(0.0, 0.12, s));
	ALBEDO = c * v * intensity;
}
