shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The lighthouse beams (scenes/tycoon/campus_lighthouse.tscn: BeamPivot/Beam*): a soft cone of
// light added over the scene, brightest along its axis and near the lamp, fading out with
// distance. The day cycle fades the beams in at night (group campus_night_glow).

uniform vec4 color : source_color = vec4(1.0, 0.86, 0.58, 1.0);
uniform float strength : hint_range(0.0, 4.0) = 0.5;
// how fast the beam fades along its length (higher = shorter)
uniform float falloff : hint_range(0.2, 6.0) = 2.2;

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);    // 0 at the narrow end (the lamp)
	float axis = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float fade = pow(1.0 - along, falloff);
	ALBEDO = color.rgb * strength * axis * fade;
}
