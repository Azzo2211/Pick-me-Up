shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Capelli: ciocche con fili lungo la lunghezza (V), riflesso lucido a banda e
// radici più scure. Colore dai vertici.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

void fragment() {
	vec3 c = srgb_to_linear(COLOR.rgb);
	vec2 uv = UV;
	float fw = length(fwidth(uv));
	float strands = mix(0.5, vnoise(vec2(uv.x * 180.0, uv.y * 6.0)), aa_keep(180.0, fw));
	float clumps = vnoise(vec2(uv.x * 40.0, uv.y * 2.0));
	c *= 0.72 + 0.4 * strands * (0.7 + 0.3 * clumps);
	// banda lucida (riflesso tipico dei capelli disegnati)
	float sheen = pow(clamp(dot(normalize(NORMAL + VIEW), vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 0.0, 1.0), 6.0);
	c += srgb_to_linear(COLOR.rgb) * sheen * 0.5 * strands;
	NORMAL = bump_normal(NORMAL, VERTEX, (strands - 0.5) * 0.0015, 1.0);
	ALBEDO = c;
	ROUGHNESS = 0.42;
	SPECULAR = 0.5;
	RIM = 0.3;
	RIM_TINT = 0.7;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.4;
}
