shader_type spatial;
// Map lines (orbits, predicted trajectories, SOI rings) with a constant width in pixels,
// whatever the zoom: each polyline point is duplicated into a strip (CUSTOM0.w = side
// -1 / +1) and pushed sideways in screen space along the mitred normal of its two
// neighbours (CUSTOM0.xyz = previous point, CUSTOM1.xyz = next point, CUSTOM1.w = arc
// length for dashes). Anti-aliased edges in the fragment, optional dashes, a soft gap
// around a point (hides a coarse polyline where a finer one is drawn) and the depth test
// against the planets. One draw call per line; the mesh is rebuilt only when the
// trajectory changes (src/flight/flight_map.gd).
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

instance uniform vec4 line_color : source_color = vec4(1.0);
instance uniform float line_width = 2.0;
// dash period in mesh units (0 = solid)
instance uniform float dash = 0.0;
// xyz = world point, w = radius (0 = off)
instance uniform vec4 gap = vec4(0.0);

varying float v_side;
varying float v_arc;
varying vec3 v_world;
varying float v_alpha;

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 vprev = MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	vec4 vnext = MODELVIEW_MATRIX * vec4(CUSTOM1.xyz, 1.0);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_side = CUSTOM0.w;
	v_arc = CUSTOM1.w;
	v_alpha = COLOR.a;
	float near_z = -0.0001 * length(vp.xyz);
	bool p_ok = vprev.z < near_z;
	bool n_ok = vnext.z < near_z;
	vec4 c = PROJECTION_MATRIX * vp;
	if (vp.z >= near_z) {
		// behind the camera: collapse (the adjacent quads vanish)
		POSITION = vec4(0.0, 0.0, 2.0, 1.0);
	} else {
		vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
		vec2 sc = c.xy / c.w * aspect;
		vec4 cp = PROJECTION_MATRIX * vprev;
		vec4 cn = PROJECTION_MATRIX * vnext;
		vec2 sp = p_ok ? cp.xy / cp.w * aspect : sc;
		vec2 sn = n_ok ? cn.xy / cn.w * aspect : sc;
		vec2 d1 = sc - sp;
		vec2 d2 = sn - sc;
		float l1 = length(d1);
		float l2 = length(d2);
		d1 = l1 > 1e-9 ? d1 / l1 : (l2 > 1e-9 ? d2 / l2 : vec2(1.0, 0.0));
		d2 = l2 > 1e-9 ? d2 / l2 : d1;
		vec2 t = d1 + d2;
		t = length(t) > 1e-6 ? normalize(t) : d1;
		vec2 nrm = vec2(-t.y, t.x);
		float miter = 1.0 / max(dot(nrm, vec2(-d1.y, d1.x)), 0.6);
		float half_px = line_width * 0.5 + 1.0;
		vec2 off = nrm * (CUSTOM0.w * half_px * miter * 2.0 / VIEWPORT_SIZE.y);
		off.x /= aspect.x;
		c.xy += off * c.w;
		POSITION = c;
	}
}

void fragment() {
	float half_px = line_width * 0.5 + 1.0;
	float d = abs(v_side) * half_px;
	float a = clamp(line_width * 0.5 + 0.5 - d, 0.0, 1.0);
	if (dash > 0.0) {
		float ph = fract(v_arc / dash);
		float aa = fwidth(v_arc / dash) * 1.5 + 1e-4;
		a *= smoothstep(0.0, aa, ph) * (1.0 - smoothstep(0.55 - aa, 0.55, ph));
	}
	if (gap.w > 0.0) {
		a *= smoothstep(gap.w * 0.75, gap.w, distance(v_world, gap.xyz));
	}
	// a little more saturation: the map's ACES tonemap washes thin bright lines out
	vec3 c = line_color.rgb * COLOR.rgb;
	c = max(mix(vec3(dot(c, vec3(0.3, 0.5, 0.2))), c, 1.3), vec3(0.0)) * 0.88;
	ALBEDO = c;
	ALPHA = line_color.a * a * v_alpha;
}
