shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Intonaco consumato: macchie, colature verticali, base più scura e superficie
// irregolare (rilievo per pixel).
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.78, 0.71, 0.60);
uniform vec3 stain_color : source_color = vec3(0.52, 0.45, 0.36);
uniform float stains = 0.5;
uniform float relief = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fw = length(fwidth(UV));
	float big = fbm(UV * 0.9 + wpos.xz * 0.05);
	float streak = fbm3(vec2(UV.x * 6.0, UV.y * 0.6));
	float fine = mix(0.5, vnoise(UV * 18.0), aa_keep(18.0, fw));
	vec3 c = mix(base_color, stain_color, smoothstep(0.45, 0.85, big) * stains);
	c *= 0.9 + 0.12 * fine;
	c = mix(c, stain_color * 0.8, smoothstep(0.62, 0.9, streak) * 0.25 * stains);
	// intonaco scrostato: chiazze più basse con il mattone sotto
	float flake = smoothstep(0.7, 0.74, fbm3(UV * 2.2 + 7.0));
	c = mix(c, vec3(0.42, 0.28, 0.2) * (0.8 + 0.3 * fine), flake * 0.85);
	float height = (big - 0.5) * 0.006 + (fine - 0.5) * 0.003 - flake * 0.006;
	NORMAL = bump_normal(NORMAL, VERTEX, height, relief);
	vec3 tint = srgb_to_linear(COLOR.rgb);
	ALBEDO = c * tint;
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.5;
}
