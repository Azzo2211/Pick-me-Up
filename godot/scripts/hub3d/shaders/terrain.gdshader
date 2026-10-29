shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Terreno dell'isola: erba, sterrato, selciato e roccia delle scogliere.
// Maschere nei colori dei vertici: R sterrato, G selciato, B roccia, A occlusione.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 grass_dark : source_color = vec3(0.115, 0.165, 0.065);
uniform vec3 grass_light : source_color = vec3(0.27, 0.33, 0.12);
uniform vec3 grass_dry : source_color = vec3(0.43, 0.39, 0.19);
uniform vec3 dirt_color : source_color = vec3(0.30, 0.225, 0.155);
uniform vec3 dirt_light : source_color = vec3(0.46, 0.37, 0.26);
uniform vec3 cobble_a : source_color = vec3(0.50, 0.47, 0.43);
uniform vec3 cobble_b : source_color = vec3(0.35, 0.335, 0.32);
uniform vec3 gap_color : source_color = vec3(0.13, 0.115, 0.10);
uniform vec3 rock_a : source_color = vec3(0.44, 0.38, 0.32);
uniform vec3 rock_b : source_color = vec3(0.24, 0.21, 0.20);
uniform vec3 moss_color : source_color = vec3(0.17, 0.22, 0.09);
uniform float cobble_scale = 2.4;
uniform float flower_amount = 0.35;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float fw = length(fwidth(p));
	float n1 = fbm(p * 0.16);
	float n2 = fbm(p * 0.85 + 3.0);
	float n3 = mix(0.5, vnoise(p * 5.5), aa_keep(5.5, fw));
	vec3 grass = mix(grass_dark, grass_light, smoothstep(0.28, 0.78, n1));
	grass = mix(grass, grass_dry, smoothstep(0.6, 0.85, n2) * 0.55);
	grass *= 0.8 + 0.34 * n3;
	float bloom = smoothstep(0.86, 0.9, vnoise(p * 7.0 + 11.0)) * smoothstep(0.55, 0.7, n2) * flower_amount * aa_keep(7.0, fw);
	grass = mix(grass, mix(vec3(0.55, 0.48, 0.62), vec3(0.75, 0.66, 0.38), hash12(floor(p * 7.0))), bloom);

	vec3 dirt = mix(dirt_color, dirt_light, n2) * (0.84 + 0.26 * mix(0.5, vnoise(p * 9.0), aa_keep(9.0, fw)));
	float pebble = smoothstep(0.8, 0.84, vnoise(p * 15.0)) * aa_keep(15.0, fw);
	dirt = mix(dirt, dirt_light * 1.12, pebble * 0.55);
	float rut = smoothstep(0.55, 0.9, fbm3(p * 2.5));
	dirt *= 1.0 - rut * 0.12;

	vec4 v = voronoi(p * cobble_scale);
	float stone_id = hash12(v.zw);
	vec3 cobble = mix(cobble_a, cobble_b, stone_id) * (0.86 + 0.24 * mix(0.5, vnoise(p * 11.0), aa_keep(11.0, fw)));
	cobble *= mix(0.72, 1.0, smoothstep(0.02, 0.16, v.y));
	float gap_w = fw * cobble_scale;
	cobble = mix(mix(cobble, gap_color, 0.35), mix(gap_color, cobble, smoothstep(0.025 - gap_w, 0.06 + gap_w, v.y)), aa_keep(cobble_scale * 6.0, fw));
	cobble = mix(cobble, moss_color, smoothstep(0.06, 0.0, v.y) * smoothstep(0.5, 0.8, n2) * 0.6);

	float strata = sin(wpos.y * 2.7 + fbm(vec2(wpos.x + wpos.z, wpos.y) * 0.6) * 5.0) * 0.5 + 0.5;
	vec3 rock = mix(rock_b, rock_a, strata) * (0.75 + 0.4 * fbm(vec2(wpos.x * 1.3 + wpos.z * 0.7, wpos.y * 2.1)));

	float edge_noise = (fbm3(p * 1.5) - 0.5) * 0.55;
	float dirt_mask = smoothstep(0.38, 0.62, COLOR.r + edge_noise);
	float pave_mask = smoothstep(0.42, 0.58, COLOR.g + edge_noise * 0.5);
	float steep = smoothstep(0.78, 0.5, wnrm.y);
	float rock_mask = clamp(COLOR.b + steep, 0.0, 1.0);
	vec3 col = mix(grass, dirt, dirt_mask);
	col = mix(col, cobble, pave_mask);
	vec3 cliff = mix(rock, moss_color * 1.2, smoothstep(0.62, 0.8, fbm3(vec2(wpos.x + wpos.z, wpos.y * 0.6) * 0.9)) * 0.55);
	col = mix(col, cliff, rock_mask);
	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.82, pave_mask);
	SPECULAR = 0.3;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.35;
}
