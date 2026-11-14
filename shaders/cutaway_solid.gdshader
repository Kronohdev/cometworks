shader_type spatial;
// Plain painted / metal surface for structure attached to the walls and ceiling of the
// assembly building (columns, girders, catwalks, roof trusses). Like the inward-facing
// wall quads, it disappears when the camera is outside the building on that side, so a
// zoomed-out camera sees a clean cutaway instead of a cage of columns.
// Only the main (perspective) view is cut: orthographic shadow passes (the sun) and
// cameras inside the building (spot shadows, reflection probe) still see everything.

uniform vec4 albedo : source_color = vec4(0.64, 0.68, 0.72, 1.0);
uniform float metallic = 0.55;
uniform float roughness = 0.38;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform vec3 half_size = vec3(60.0, 120.0, 60.0); // x / z: half width, y: ceiling height
uniform float margin = 4.8;                       // wall-attached band that gets cut

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = CAMERA_POSITION_WORLD;
	bool perspective = PROJECTION_MATRIX[3][3] < 0.5;
	if (perspective) {
		bool cut = (c.x > half_size.x && wpos.x > half_size.x - margin)
				|| (c.x < -half_size.x && wpos.x < -half_size.x + margin)
				|| (c.z > half_size.z && wpos.z > half_size.z - margin)
				|| (c.z < -half_size.z && wpos.z < -half_size.z + margin)
				|| (c.y > half_size.y && wpos.y > half_size.y - margin * 2.0);
		if (cut) {
			discard;
		}
	}
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = emission_color.rgb * emission_energy;
}
