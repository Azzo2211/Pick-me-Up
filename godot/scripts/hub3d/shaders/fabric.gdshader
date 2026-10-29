shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Stoffa e cuoio dei personaggi: pieghe lungo la caduta del tessuto, trama
// fine (solo da vicino), lucentezza radente. "leather" > 0 = cuoio.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform float leather = 0.0;

void fragment() {
	vec3 c = srgb_to_linear(COLOR.rgb);
	vec2 uv = UV;
	float fw = length(fwidth(uv));
	float folds = fbm(vec2(uv.x * 9.0, uv.y * 1.6));
	float wear = fbm3(uv * 4.0 + 3.0);
	float weave = mix(0.5, (sin(uv.x * 900.0) * sin(uv.y * 900.0)) * 0.5 + 0.5, 1.0 - smoothstep(0.05, 0.2, 143.0 * fw));
	float grain = mix(0.5, vnoise(uv * 140.0), aa_keep(140.0, fw));
	c *= mix(0.86 + 0.24 * folds, 0.9 + 0.2 * grain, leather);
	c *= mix(1.0, 0.92 + 0.12 * weave, (1.0 - leather) * 0.6);
	// bordi consumati più chiari, pieghe profonde più scure
	c = mix(c, c * 1.25, smoothstep(0.62, 0.85, wear) * 0.35);
	float height = mix(folds * 0.006 + (weave - 0.5) * 0.0008, (grain - 0.5) * 0.0012 + wear * 0.002, leather);
	NORMAL = bump_normal(NORMAL, VERTEX, height, 1.0);
	ALBEDO = c;
	ROUGHNESS = mix(0.9, 0.55, leather);
	SPECULAR = mix(0.22, 0.42, leather);
	RIM = mix(0.25, 0.1, leather);
	RIM_TINT = 0.6;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.4;
}
