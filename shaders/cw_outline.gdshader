shader_type spatial;
// Cometworks ink outlines: a screen-space post-process drawn by a full-screen quad parented to a
// camera (scenes/fx/cw_outline.tscn). Reads the depth and normal buffers of the opaque pass:
//   depth   the Laplacian of the raw depth (which is affine in 1/z, so flat surfaces give zero
//           at any angle) finds silhouettes and big steps; only the near side is inked, so
//           lines hug the object instead of haloing onto what is behind it
//   normal  a turn of the normal between two flat faces finds creases (building corners, roof
//           edges); faces smaller than crease_min_size (voxel stair steps) are skipped and the
//           creases fade out sooner with distance, so voxel shapes don't turn into hatching;
//           round voxel shapes opt out of creases by a roughness below crease_min_roughness
// The ink is the local colour darkened and pulled towards cw_outline_color (a deep indigo),
// so lines read as coloured ink, not black. Lines fade with distance (fade_start..fade_end) and
// are never drawn on the sky. Only the camera that owns the quad draws it (every other camera
// gets a degenerate triangle), so several cameras can carry one each.
// Global tunables (project.godot shader_globals): cw_outline_color, cw_outline_strength.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;

global uniform vec4 cw_outline_color : source_color;
global uniform float cw_outline_strength;

group_uniforms Lines;
// sample offset in pixels of the internal render (1 = thinnest line)
uniform float line_width : hint_range(0.5, 3.0) = 1.5;
// ignore 1-pixel depth holes (voxel face cracks seen by MSAA samples): no ink speckles
uniform bool despeckle = true;
// relative depth Laplacian that starts a line, and where it is full strength
uniform float depth_threshold : hint_range(0.001, 0.5) = 0.07;
uniform float depth_full : hint_range(0.001, 1.0) = 0.2;
// normal turn (1 - cos) that starts a crease line, and where it is full strength
uniform float normal_threshold : hint_range(0.0, 2.0) = 0.55;
uniform float normal_full : hint_range(0.0, 2.0) = 0.9;
// depth thresholds are scaled by far_threshold_scale between far_start and far_end (m)
uniform float far_threshold_scale : hint_range(0.05, 1.0) = 0.35;
uniform float far_start : hint_range(0.0, 500.0) = 25.0;
uniform float far_end : hint_range(0.0, 1000.0) = 100.0;
// smallest flat face (m) on each side of a crease for it to get a line (voxel steps are smaller)
uniform float crease_min_size : hint_range(0.0, 1.0) = 0.06;
// materials with a lower roughness get no crease lines (see the note in fragment())
uniform float crease_min_roughness : hint_range(0.0, 1.0) = 0.7;
// crease lines fade out between these distances (m)
uniform float normal_fade_start : hint_range(0.0, 500.0) = 40.0;
uniform float normal_fade_end : hint_range(0.0, 500.0) = 140.0;
// crease lines are weaker than silhouettes
uniform float normal_weight : hint_range(0.0, 1.0) = 0.7;
group_uniforms Ink;
// how much of the local colour stays in the ink (0 = flat cw_outline_color)
uniform float local_colour : hint_range(0.0, 1.0) = 0.35;
// darkening of the local colour
uniform float darken : hint_range(0.0, 1.0) = 0.25;
group_uniforms Fade;
// all lines fade out between these distances (m), like the fog
uniform float fade_start : hint_range(0.0, 1000.0) = 150.0;
uniform float fade_end : hint_range(0.0, 2000.0) = 400.0;
// strength of this camera's lines (times cw_outline_strength)
uniform float strength : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

void vertex() {
	// owner check: the quad sits at its camera's origin
	if (distance(NODE_POSITION_WORLD, CAMERA_POSITION_WORLD) > 0.01) {
		POSITION = vec4(4.0, 4.0, 4.0, 1.0);
	} else {
		POSITION = vec4(VERTEX.xy, 1.0, 1.0);   // QuadMesh 2 x 2: covers clip space
	}
}

float linear_depth(vec2 uv, float raw, mat4 inv_proj) {
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

// roughness as the material wrote it (Godot 4.6 hands the buffer's roughness back decoded)
float buffer_roughness(vec2 uv) {
	return texture(normal_tex, uv).w;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float dc = texture(depth_tex, uv).r;
	if (dc <= 1e-7) {
		discard;   // sky
	}
	vec2 px = line_width / VIEWPORT_SIZE;
	float dl = texture(depth_tex, uv - vec2(px.x, 0.0)).r;
	float dr = texture(depth_tex, uv + vec2(px.x, 0.0)).r;
	float dd = texture(depth_tex, uv - vec2(0.0, px.y)).r;
	float du = texture(depth_tex, uv + vec2(0.0, px.y)).r;
	// lone far pixels (the hairline cracks between voxel faces that MSAA samples see through)
	// are not silhouettes: each tap takes the nearer of itself and the pixel past it, so a
	// 1-pixel hole is filled while a real edge (background on both) still draws its line
	if (despeckle) {
		vec2 px2 = 2.0 / VIEWPORT_SIZE;
		dl = max(dl, texture(depth_tex, uv - vec2(px.x + px2.x, 0.0)).r);
		dr = max(dr, texture(depth_tex, uv + vec2(px.x + px2.x, 0.0)).r);
		dd = max(dd, texture(depth_tex, uv - vec2(0.0, px.y + px2.y)).r);
		du = max(du, texture(depth_tex, uv + vec2(0.0, px.y + px2.y)).r);
	}
	// reverse Z: larger raw depth = nearer. Negative Laplacian = this pixel stands in front.
	float lap_x = (dl + dr - 2.0 * dc) / dc;
	float lap_y = (dd + du - 2.0 * dc) / dc;
	float near_step = max(max(-lap_x, -lap_y), 0.0);
	float z = linear_depth(uv, dc, INV_PROJECTION_MATRIX);
	// far away the steps between things are relatively smaller (a roof 10 m over the lawn seen
	// from 110 m): the threshold eases off with distance
	float d_scale = mix(1.0, far_threshold_scale, smoothstep(far_start, far_end, z));
	float e_depth = smoothstep(depth_threshold * d_scale, depth_full * d_scale, near_step);
	// creases: a turn of the normal between the two sides of this pixel, where each side is
	// flat for at least crease_min_size (m) - so big faces meeting get a line, and the 1-voxel
	// stair steps of round voxel shapes (Cometlings, trees) don't
	float e_normal = 0.0;
	// cheap material mask: surfaces smoother than crease_min_roughness (Cometlings 0.62,
	// foliage 0.68) get silhouettes only, so their round voxel terraces don't draw contours
	if (normal_weight > 0.0 && z < normal_fade_end && buffer_roughness(uv) >= crease_min_roughness) {
		float m_per_px = z * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		float reach = clamp(crease_min_size / m_per_px, 2.0, 16.0);
		vec2 rx = vec2(px.x * reach / line_width, 0.0);
		vec2 ry = vec2(0.0, px.y * reach / line_width);
		vec2 ox = vec2(px.x, 0.0);
		vec2 oy = vec2(0.0, px.y);
		vec3 a = view_normal(uv - ox);
		vec3 b = view_normal(uv + ox);
		float flat_x = smoothstep(0.9, 0.99, dot(a, view_normal(uv - rx))) * smoothstep(0.9, 0.99, dot(b, view_normal(uv + rx)));
		float turn_x = (1.0 - dot(a, b)) * flat_x * step(1e-7, min(dl, dr));
		vec3 c = view_normal(uv - oy);
		vec3 d = view_normal(uv + oy);
		float flat_y = smoothstep(0.9, 0.99, dot(c, view_normal(uv - ry))) * smoothstep(0.9, 0.99, dot(d, view_normal(uv + ry)));
		float turn_y = (1.0 - dot(c, d)) * flat_y * step(1e-7, min(dd, du));
		e_normal = smoothstep(normal_threshold, normal_full, max(turn_x, turn_y)) * normal_weight;
		e_normal *= 1.0 - smoothstep(normal_fade_start, normal_fade_end, z);
	}

	float edge = max(e_depth, e_normal);
	edge *= 1.0 - smoothstep(fade_start, fade_end, z);
	edge *= cw_outline_strength * strength;
	if (edge <= 0.002) {
		discard;
	}
	vec3 local = texture(screen_tex, uv).rgb;
	vec3 ink = mix(cw_outline_color.rgb, local * darken, local_colour);
	ALBEDO = ink;
	ALPHA = clamp(edge, 0.0, 1.0);
}
