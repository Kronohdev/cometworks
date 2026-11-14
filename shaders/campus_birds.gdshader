shader_type spatial;
render_mode cull_disabled;
// A flock of small birds gliding over the campus (scenes/tycoon/campus_life.tscn: Birds).
// Every bird is a MultiMesh instance of a tiny "V" mesh (two wing quads meeting at the body,
// wing tips at |x| = 1); this shader flies it on its own loop around the instance origin and
// flaps the wings, so the flock costs no CPU. Per-instance variety comes from INSTANCE_ID.

uniform vec3 color : source_color = vec3(0.10, 0.11, 0.16);
// loop radius (m) and the spread of radii in the flock
uniform float radius = 26.0;
uniform float radius_spread = 10.0;
uniform float speed = 0.16;
uniform float height_wobble = 3.0;
uniform float flap_speed = 9.0;
uniform float flap_amount = 0.55;
// a few seconds of gliding between bursts of flapping
uniform float glide = 0.6;
uniform float bird_scale = 0.45;

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float r = radius + (h11(id + 1.3) - 0.5) * radius_spread;
	float dir = h11(id + 7.1) > 0.15 ? 1.0 : -1.0;
	float a = TIME * speed * dir * (0.85 + 0.3 * h11(id + 2.9)) + h11(id + 5.7) * TAU;
	// an oval loop with a slow vertical wave
	vec3 c = vec3(cos(a) * r, sin(a * 2.0 + id) * height_wobble, sin(a) * r * 0.7);
	vec3 fwd = normalize(vec3(-sin(a) * r, cos(a * 2.0 + id) * height_wobble * 2.0 * 0.0, cos(a) * r * 0.7) * dir);
	vec3 right = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, fwd);
	// wings flap in bursts
	float burst = smoothstep(glide, glide + 0.2, 0.5 + 0.5 * sin(TIME * 0.7 + id * 3.1));
	float flap = sin(TIME * flap_speed * (0.9 + 0.2 * h11(id + 9.0)) + id) * flap_amount * burst + 0.15;
	vec3 v = VERTEX;
	v.y += abs(v.x) * flap;
	v *= bird_scale * (0.8 + 0.4 * h11(id + 4.4));
	vec3 world = c + right * v.x + up * v.y - fwd * v.z;
	VERTEX = world;
	NORMAL = up;
}

void fragment() {
	ALBEDO = color;
	ROUGHNESS = 0.9;
}
