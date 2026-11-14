shader_type spatial;
// Plain-colour prop in the Cometworks toon light (shaders/include/cw_toon.gdshaderinc): the
// cartoon replacement of a flat StandardMaterial3D (albedo colour, roughness, metallic, optional
// vertex colour and emission). Used by the menu shots, the campus props, the launch stage,
// the cutscene sets and the leader hats (tools/convert_toon_materials.py converts scenes).

#include "res://shaders/include/cw_toon.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
// multiply the albedo by the mesh's vertex colour
uniform bool use_vertex_color = false;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	EMISSION = emission.rgb * emission_energy + cw_toon_rim(NORMAL, VIEW, c, VERTEX, INV_VIEW_MATRIX);
}
