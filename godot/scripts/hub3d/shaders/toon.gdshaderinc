// Ombreggiatura anime a due toni per i personaggi: lato in luce e lato in ombra
// separati da un bordo netto, ombra tinta di freddo, riflesso sui metalli e
// un filo di luce sul contorno. Il colore viene dai vertici: il renderer
// Compatibility illumina in spazio sRGB, come i materiali standard dei personaggi.

uniform float toon_shade : hint_range(0.0, 1.0) = 0.3;
// i personaggi a due toni sono più chiari dei materiali normali: si abbassa la luce piena
uniform float toon_lit : hint_range(0.0, 2.0) = 0.6;
// quanta luce ambiente arriva (il resto lo fa la luce del sole a due toni)
uniform float toon_ambient : hint_range(0.0, 1.0) = 0.72;
uniform vec3 toon_shadow_tint : source_color = vec3(0.80, 0.74, 0.92);
uniform float toon_spec : hint_range(0.0, 2.0) = 0.0;
uniform float toon_rim : hint_range(0.0, 1.0) = 0.16;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// sole: l'ombra portata entra nel taglio netto; torce e lanterne sfumano con la distanza
	float shadow = LIGHT_IS_DIRECTIONAL ? smoothstep(0.25, 0.55, ATTENUATION) : 1.0;
	float falloff = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	float band = smoothstep(0.0, 0.07, ndl) * shadow;
	vec3 tone = mix(toon_shadow_tint * toon_shade, vec3(1.0), band);
	DIFFUSE_LIGHT += LIGHT_COLOR * tone * falloff * toon_lit / PI;
	if (toon_spec > 0.0) {
		float h = dot(NORMAL, normalize(LIGHT + VIEW));
		SPECULAR_LIGHT += LIGHT_COLOR * smoothstep(0.965, 0.985, h) * band * falloff * toon_spec / PI;
	}
}
