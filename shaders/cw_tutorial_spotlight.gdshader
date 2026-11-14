shader_type canvas_item;
// Soft spotlight of the tutorials (scenes/tycoon/ui/tutorial/tutorial.tscn, Spotlight): dims the
// screen around a rounded rectangle (the UI node Halleyzinho is talking about) and leaves it
// clear, with a soft edge. TycoonTutorial sets hole (x, y, w, h in the rect's own pixels),
// rect_size and strength (0 = no dimming, for the fades).

uniform vec4 hole = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform float radius = 14.0;
uniform float softness = 18.0;
uniform vec4 dim_color : source_color = vec4(0.106, 0.094, 0.271, 0.5);
uniform float strength : hint_range(0.0, 1.0) = 1.0;

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * rect_size;
	float a = dim_color.a;
	if (hole.z > 0.0 && hole.w > 0.0) {
		vec2 c = hole.xy + hole.zw * 0.5;
		float d = rounded_box(px - c, hole.zw * 0.5, radius);
		a *= smoothstep(0.0, softness, d);
	}
	COLOR = vec4(dim_color.rgb, a * strength);
}
