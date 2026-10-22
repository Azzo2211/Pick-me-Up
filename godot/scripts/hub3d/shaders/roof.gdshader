shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

// Tetto a lastre (ardesia, coppi, scandole o paglia). UV: U lungo il colmo,
// V lungo la falda. "style": 0 ardesia, 1 scandole di legno, 2 paglia.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 tile_a : source_color = vec3(0.24, 0.26, 0.30);
uniform vec3 tile_b : source_color = vec3(0.17, 0.18, 0.21);
uniform vec3 moss_color : source_color = vec3(0.22, 0.25, 0.12);
uniform vec2 tile = vec2(0.24, 0.16);
uniform int style = 0;
uniform float moss = 0.25;

void fragment() {
	vec2 uv = UV;
	vec3 c;
	if (style == 2) {
		float strands = fbm(vec2(uv.x * 26.0, uv.y * 2.0));
		float rows = fract(uv.y / 0.22);
		c = mix(tile_b, tile_a, strands);
		c *= mix(0.62, 1.0, smoothstep(0.0, 0.35, rows));
		c *= 0.85 + 0.25 * vnoise(uv * 3.0);
	} else {
		float row = floor(uv.y / tile.y);
		vec2 t = vec2(uv.x / tile.x + mod(row, 2.0) * 0.5 + hash12(vec2(row, 2.0)) * 0.2, uv.y / tile.y);
		vec2 cell = floor(t);
		vec2 f = fract(t);
		float h = hash12(cell);
		c = mix(tile_a, tile_b, h);
		if (style == 1) c *= 0.85 + 0.3 * fbm(vec2(t.x * 4.0, t.y * 0.8) + cell);
		else c *= 0.9 + 0.18 * vnoise(uv * 20.0);
		// ombra del bordo inferiore di ogni fila e fessure verticali
		c *= mix(0.45, 1.0, smoothstep(0.0, 0.22, f.y));
		c *= mix(0.6, 1.0, smoothstep(0.0, 0.06, min(f.x, 1.0 - f.x)));
		c *= 1.0 - 0.18 * smoothstep(0.85, 1.0, f.y);
	}
	float m = smoothstep(0.58, 0.82, fbm3(uv * 0.7)) * moss;
	c = mix(c, moss_color, m);
	vec3 tint = srgb_to_linear(COLOR.rgb);
	ALBEDO = c * tint;
	ROUGHNESS = style == 0 ? 0.62 : 0.92;
	SPECULAR = style == 0 ? 0.5 : 0.25;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.5;
}
