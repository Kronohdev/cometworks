shader_type spatial;
// Camera-facing corona around the Sun: a soft radial glow with slowly drifting
// streamers. Additive, so it never hides what is behind it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 color_inner : source_color = vec3(1.0, 0.78, 0.42);
uniform vec3 color_outer : source_color = vec3(1.0, 0.38, 0.12);
// Sun radius as a fraction of the quad half-size
uniform float sun_ratio : hint_range(0.01, 1.0) = 0.22;
uniform float intensity : hint_range(0.0, 8.0) = 1.4;
uniform float falloff : hint_range(0.5, 20.0) = 4.5;
uniform float streamers : hint_range(0.0, 1.0) = 0.35;
// dimmer when the camera is close (the disc already fills the view)
uniform vec2 near_fade = vec2(60.0, 380.0);
uniform float near_intensity : hint_range(0.0, 1.0) = 0.45;

void vertex() {
	// billboard: keep the node origin, face the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float x = max(r - sun_ratio, 0.0) / (1.0 - sun_ratio);
	float a = atan(p.y, p.x);
	float rays = 0.5 + 0.5 * sin(a * 7.0 + TIME * 0.05) * sin(a * 11.0 - TIME * 0.031 + 1.7);
	rays = mix(1.0, 0.55 + 0.9 * rays * rays, streamers);
	float glow = exp(-x * falloff) * 0.85 + exp(-x * falloff * 3.5) * 0.9;
	glow *= mix(1.0, rays, smoothstep(0.0, 0.25, x));
	glow *= 1.0 - smoothstep(0.75, 1.0, r);
	vec3 col = mix(color_inner, color_outer, smoothstep(0.0, 0.6, x));
	float cam_d = length(CAMERA_POSITION_WORLD - NODE_POSITION_WORLD);
	float k = mix(near_intensity, 1.0, smoothstep(near_fade.x, near_fade.y, cam_d));
	ALBEDO = col * glow * intensity * k;
}
