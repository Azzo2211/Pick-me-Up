shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Roccia naturale: grana, venature, licheni e muschio sulle facce in alto,
// rilievo per pixel. COLOR.rgb tinge la roccia, COLOR.a è l'occlusione.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 rock_a : source_color = vec3(0.47, 0.44, 0.41);
uniform vec3 rock_b : source_color = vec3(0.30, 0.29, 0.28);
uniform vec3 moss_color : source_color = vec3(0.24, 0.31, 0.12);
uniform vec3 lichen : source_color = vec3(0.62, 0.6, 0.42);
uniform float moss = 0.6;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = safe_normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = wpos * 1.6;
	float fw = length(fwidth(wpos));
	float big = fbm(p.xz * 0.7 + p.y * 0.9);
	float mid = fbm(vec2(p.x + p.z * 0.6, p.y) * 2.3 + 4.0);
	float fine = mix(0.5, vnoise(p.xz * 9.0 + p.y * 7.0), aa_keep(14.0, fw));
	float crack = smoothstep(0.03, 0.0, abs(mid - 0.5)) * aa_keep(6.0, fw);
	vec3 c = mix(rock_b, rock_a, smoothstep(0.25, 0.75, big));
	c *= 0.82 + 0.3 * fine;
	c *= 1.0 - crack * 0.45;
	float up = clamp(wnrm.y, 0.0, 1.0);
	float moss_mask = smoothstep(0.45, 0.8, up + (big - 0.5) * 0.6) * moss;
	c = mix(c, moss_color * (0.8 + 0.4 * fine), moss_mask);
	float lv = vnoise(p.xz * 3.0 + p.y);
	float lw = fwidth(lv);
	c = mix(c, lichen, smoothstep(0.78 - lw, 0.82 + lw, lv) * (1.0 - moss_mask) * 0.4);
	float height = big * 0.05 + mid * 0.02 + (fine - 0.5) * 0.006 - crack * 0.01;
	NORMAL = bump_normal(NORMAL, VERTEX, height, 1.0);
	ALBEDO = c * srgb_to_linear(COLOR.rgb);
	ROUGHNESS = mix(0.86, 0.95, moss_mask);
	SPECULAR = 0.3;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.6;
}
