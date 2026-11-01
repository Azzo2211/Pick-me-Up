shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Personaggi: stoffa, pelle e metalli con ombre a due toni (vedi toon.gdshaderinc).
#include "res://scripts/hub3d/shaders/toon.gdshaderinc"

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	AO = toon_ambient;
	AO_LIGHT_AFFECT = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = ALBEDO * rim * toon_rim;
}
