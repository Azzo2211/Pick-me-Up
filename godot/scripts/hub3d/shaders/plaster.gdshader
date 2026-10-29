shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Intonaco consumato: macchie, colature verticali e base più scura.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.78, 0.71, 0.60);
uniform vec3 stain_color : source_color = vec3(0.52, 0.45, 0.36);
uniform float stains = 0.5;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float big = fbm(UV * 0.9 + wpos.xz * 0.05);
	float streak = fbm3(vec2(UV.x * 6.0, UV.y * 0.6));
	vec3 c = mix(base_color, stain_color, smoothstep(0.45, 0.85, big) * stains);
	c *= 0.9 + 0.12 * mix(0.5, vnoise(UV * 18.0), aa_keep(18.0, length(fwidth(UV))));
	c = mix(c, stain_color * 0.8, smoothstep(0.62, 0.9, streak) * 0.25 * stains);
	vec3 tint = srgb_to_linear(COLOR.rgb);
	ALBEDO = c * tint;
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.5;
}
