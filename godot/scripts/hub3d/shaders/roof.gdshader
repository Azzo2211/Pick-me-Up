shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Tetto a lastre (ardesia, coppi, scandole o paglia). UV: U lungo il colmo,
// V lungo la falda verso la gronda. "style": 0 ardesia, 1 scandole, 2 paglia.
// Ogni lastra ha spessore e inclinazione propria (rilievo per pixel).
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 tile_a : source_color = vec3(0.24, 0.26, 0.30);
uniform vec3 tile_b : source_color = vec3(0.17, 0.18, 0.21);
uniform vec3 moss_color : source_color = vec3(0.22, 0.25, 0.12);
uniform vec2 tile = vec2(0.24, 0.16);
uniform int style = 0;
uniform float moss = 0.25;
uniform float relief = 1.0;

void fragment() {
	vec2 uv = UV;
	float fw = length(fwidth(uv));
	vec3 c;
	float height = 0.0;
	if (style == 2) {
		float strands = fbm(vec2(uv.x * 26.0, uv.y * 2.0));
		float rows = fract(uv.y / 0.22);
		float course = floor(uv.y / 0.22);
		c = mix(tile_b, tile_a, mix(0.5, strands, aa_keep(26.0, fw)));
		// ogni corso di paglia fa ombra su quello sotto; chiazze scurite dalla pioggia
		c *= mix(0.42, 1.08, smoothstep(0.0, 0.45, rows));
		c *= 0.9 + 0.12 * hash12(vec2(course, floor(uv.x * 1.5)));
		c *= mix(1.0, 0.72, smoothstep(0.5, 0.8, fbm3(uv * 0.9 + 9.0)));
		height = rows * 0.05 + mix(0.0, strands * 0.012, aa_keep(26.0, fw));
	} else {
		float row = floor(uv.y / tile.y);
		vec2 t = vec2(uv.x / tile.x + mod(row, 2.0) * 0.5 + hash12(vec2(row, 2.0)) * 0.2, uv.y / tile.y);
		vec2 cell = floor(t);
		vec2 f = fract(t);
		float h = hash12(cell);
		c = mix(tile_a, tile_b, h);
		if (style == 1) c *= 0.85 + 0.3 * fbm(vec2(t.x * 4.0, t.y * 0.8) + cell);
		else c *= 0.9 + 0.18 * mix(0.5, vnoise(uv * 20.0), aa_keep(20.0, fw));
		// ombra della fila sopra, fessure verticali, bordo inferiore chiaro
		c *= mix(0.42, 1.0, smoothstep(0.0, 0.25, f.y));
		float side = min(f.x, 1.0 - f.x);
		c *= mix(0.55, 1.0, smoothstep(0.0, 0.07, side));
		c *= 1.0 + 0.12 * smoothstep(0.82, 0.98, f.y);
		// ogni lastra è più spessa verso la gronda e leggermente storta
		float th = tile.y * (style == 1 ? 0.16 : 0.12);
		height = f.y * th + (h - 0.5) * th * 0.35 * (f.x - 0.5) - (1.0 - smoothstep(0.0, 0.06, side)) * th * 0.5;
		if (style == 1) height += (fbm(vec2(t.x * 6.0, t.y * 1.2) + cell) - 0.5) * th * 0.25;
	}
	float m = smoothstep(0.58, 0.82, fbm3(uv * 0.7)) * moss;
	c = mix(c, moss_color, m);
	NORMAL = bump_normal(NORMAL, VERTEX, height, aa_keep(1.0 / max(tile.y, 0.05), fw) * relief);
	vec3 tint = srgb_to_linear(COLOR.rgb);
	ALBEDO = c * tint;
	ROUGHNESS = style == 0 ? 0.55 : 0.9;
	SPECULAR = style == 0 ? 0.5 : 0.25;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.5;
}
