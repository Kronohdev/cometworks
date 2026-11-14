shader_type spatial;
// Navball sphere (scenes/flight/flight_hud.tscn, inside a SubViewport). The texture is
// equirectangular in the local horizon frame: sphere +Y = zenith, -Z = north, +X = east;
// u = 1 - heading / 360 so the labels read correctly on the outside of the ball.
// Unshaded with a soft spherical falloff and a glossy highlight.
render_mode unshaded, cull_back;

uniform sampler2D navball_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float rim_dark = 0.55;

varying vec3 local_n;

void vertex() {
	local_n = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(local_n);
	float heading = atan(n.x, -n.z);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	vec2 uv = vec2(1.0 - heading / (2.0 * PI), 0.5 - lat / PI);
	vec3 c = texture(navball_tex, uv).rgb;
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	c *= mix(1.0 - rim_dark, 1.0, pow(facing, 0.6));
	// soft key light from the upper left
	vec3 l = normalize(vec3(-0.45, 0.55, 0.7));
	float spec = pow(max(dot(reflect(-l, normalize(NORMAL)), normalize(VIEW)), 0.0), 24.0);
	c += vec3(0.18) * spec;
	ALBEDO = c;
}
