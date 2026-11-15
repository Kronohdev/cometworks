shader_type spatial;
render_mode world_vertex_coords;
// Voxel clouds drifting around the campus island (scenes/tycoon/campus_island.tscn:
// SkyLife/Clouds*). Each cloud is a MultiMesh instance; this shader slides it along +x and
// wraps it around inside [wrap_min, wrap_max], so the sky keeps moving at no CPU cost.
// Lit by the Cometworks toon light: peach at golden hour, blue under the moon.

#define CW_TOON_RIM_DEFAULT 0.6
#include "res://shaders/include/cw_toon.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.97, 0.97, 1.0, 1.0);
// the underside is a little darker and cooler
uniform vec4 belly : source_color = vec4(0.78, 0.82, 0.92, 1.0);
uniform float drift_speed = 1.6;
uniform float wrap_min = -650.0;
uniform float wrap_max = 650.0;
// a soft glow so clouds never turn into black holes at night
uniform float self_light : hint_range(0.0, 1.0) = 0.12;

varying float lift;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float span = wrap_max - wrap_min;
	float x = mod(origin.x - wrap_min + TIME * drift_speed, span) + wrap_min;
	VERTEX.x += x - origin.x;
	lift = clamp((VERTEX.y - origin.y) / 3.0, 0.0, 1.0);
}

void fragment() {
	vec3 c = mix(belly.rgb, albedo.rgb, smoothstep(0.0, 0.6, lift));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = c * self_light + cw_toon_rim(NORMAL, VIEW, c, VERTEX, INV_VIEW_MATRIX);
}
