shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Muratura a blocchi sfalsati (UV in unità di mondo), con fughe, smussi,
// variazione per blocco, muschio sulle facce in alto e sporco vicino al suolo.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 tint_a : source_color = vec3(0.55, 0.52, 0.48);
uniform vec3 tint_b : source_color = vec3(0.42, 0.40, 0.37);
uniform vec3 mortar : source_color = vec3(0.24, 0.22, 0.20);
uniform vec3 moss_color : source_color = vec3(0.19, 0.24, 0.10);
uniform vec2 block = vec2(0.62, 0.3);
uniform float mortar_width = 0.03;
uniform float moss = 0.35;
uniform float ground_dirt = 0.6;
uniform float irregular = 0.35;
uniform float ground_level = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV / block;
	float row = floor(uv.y);
	uv.x += hash12(vec2(row, 3.1)) * irregular + mod(row, 2.0) * 0.5;
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float edge = min(min(f.x, 1.0 - f.x) * block.x, min(f.y, 1.0 - f.y) * block.y);
	float h = hash12(cell + row * 7.0);
	vec3 c = mix(tint_a, tint_b, h);
	float grain = fbm(UV * 4.0 + cell);
	c *= 0.82 + 0.34 * grain;
	c *= mix(0.78, 1.0, smoothstep(mortar_width, mortar_width * 3.5, edge));
	float m = 1.0 - smoothstep(mortar_width * 0.45, mortar_width, edge);
	c = mix(c, mortar, m);
	float up = clamp(wnrm.y, 0.0, 1.0);
	float moss_mask = smoothstep(0.5, 0.78, fbm3(wpos.xz * 0.7 + wpos.y * 0.9)) * moss * (0.35 + up * 0.9);
	c = mix(c, moss_color, clamp(moss_mask, 0.0, 0.85));
	c *= mix(1.0 - ground_dirt * 0.45, 1.0, smoothstep(0.0, 0.9, wpos.y - ground_level));
	vec3 tint = srgb_to_linear(COLOR.rgb);
	ALBEDO = c * tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.35;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.5;
}
