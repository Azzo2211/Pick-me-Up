// Fogliame: colore dai vertici (alfa = occlusione), variazione di tinta nel
// mondo, vento leggero e luce che filtra tra le foglie. Le normali arrivano dai
// vertici e sono "da chioma" (puntano fuori dal centro dell'albero): così la
// chioma si illumina come un volume morbido, come in un'illustrazione.
// Con CUTOUT definito le facce sono carte con texture ritagliata (alpha scissor).
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

#ifdef CUTOUT
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
#endif
uniform float sway = 0.035;
uniform vec3 dry_tint : source_color = vec3(0.62, 0.52, 0.22);
uniform float variation = 0.2;
uniform float brightness = 1.0;
uniform float translucency = 0.45;

varying vec3 wpos;
varying vec3 vnrm;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float t = TIME * 1.1 + world.x * 0.35 + world.z * 0.27;
	VERTEX.x += sin(t) * sway * h;
	VERTEX.z += cos(t * 0.83) * sway * h * 0.6;
	wpos = world;
	vnrm = safe_normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = srgb_to_linear(COLOR.rgb) * brightness;
	float n = vnoise(wpos.xz * 0.22 + vec2(wpos.y * 0.1));
	c = mix(c, srgb_to_linear(dry_tint) * (0.6 + 0.4 * length(c)), smoothstep(0.58, 0.9, n) * variation);
#ifdef CUTOUT
	vec4 t = texture(leaf_tex, UV);
	c *= mix(0.55, 1.15, t.r);
	// nei mipmap lontani l'alfa si assottiglia: lo compensiamo col livello di dettaglio
	vec2 tex_px = UV * vec2(textureSize(leaf_tex, 0));
	float lod = max(0.0, 0.5 * log2(max(dot(dFdx(tex_px), dFdx(tex_px)), dot(dFdy(tex_px), dFdy(tex_px)))));
	ALPHA = clamp(t.a * (1.0 + lod * 0.28), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// bordi delle foglie sfumati con l'MSAA (alpha to coverage)
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_tex, 0));
#else
	float fw = length(fwidth(wpos));
	c *= 0.86 + 0.28 * mix(0.5, vnoise(wpos.xz * 4.0 + vec2(wpos.y * 3.0)), aa_keep(4.0, fw));
#endif
	// normale della chioma, uguale sui due lati della carta
	NORMAL = length(vnrm) > 1e-5 ? normalize(vnrm) : NORMAL;
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = c * translucency;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.85;
}
