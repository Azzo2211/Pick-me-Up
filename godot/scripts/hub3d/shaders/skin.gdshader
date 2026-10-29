shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Pelle dei personaggi: colore dai vertici, ombre calde (luce sotto la pelle),
// riflesso morbido e bordo illuminato che stacca la figura dallo sfondo.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 warm : source_color = vec3(0.85, 0.32, 0.22);

void fragment() {
	vec3 c = srgb_to_linear(COLOR.rgb);
	ALBEDO = c;
	ROUGHNESS = 0.52;
	SPECULAR = 0.32;
	BACKLIGHT = c * warm * 0.55;
	RIM = 0.35;
	RIM_TINT = 0.55;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.3;
}
