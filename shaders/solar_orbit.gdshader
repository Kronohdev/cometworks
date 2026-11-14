shader_type spatial;
// Orbit line drawn on a flat 2x2 PlaneMesh (scaled to the orbit radius in the scene).
// The ring is computed per pixel with screen-space derivatives, so it stays a crisp,
// anti-aliased line of constant pixel width at any distance. The line is brightest at
// the body's current position (head_angle, set per instance by SolarBody) and fades
// along the trail behind it, KSP / map-view style.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

instance uniform vec4 line_color : source_color = vec4(0.45, 0.7, 1.0, 1.0);
instance uniform float head_angle = 0.0;
uniform float width_px : hint_range(0.5, 6.0) = 1.4;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.16;
uniform float trail_alpha : hint_range(0.0, 2.0) = 0.95;
uniform float trail_power : hint_range(0.5, 12.0) = 3.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float fw = max(fwidth(r), 1e-6);
	float d = abs(r - 1.0) / fw;  // distance to the ring in pixels
	float line = 1.0 - smoothstep(width_px * 0.5, width_px * 0.5 + 1.0, d);
	// angle in the plane: the body sits at (cos a, -sin a) in (x, z) for rotation a about +Y
	float a = atan(-p.y, p.x);
	float behind = fract((head_angle - a) / 6.28318530718);
	float trail = pow(1.0 - behind, trail_power);
	// grazing views: derivatives explode, fade to avoid a smeared band
	float graze = clamp(1.0 - fw * 18.0, 0.0, 1.0);
	float alpha = line * (base_alpha + trail_alpha * trail) * graze;
	ALBEDO = line_color.rgb * alpha * line_color.a;
}
