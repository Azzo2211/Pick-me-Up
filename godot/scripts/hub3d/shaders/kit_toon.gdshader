shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Corpi del kit (tools/character_kit): un'unica mesh vestita. La seconda UV dice di
// che "posto" della tavolozza è ogni faccia (pelle, stoffa, metallo...) e quanto è
// in ombra fissa; il colore di ogni posto lo dà l'eroe (palette, alfa = lucentezza).
// Luce a due toni come gli altri personaggi (vedi toon.gdshaderinc), con:
// - luce del cielo dall'alto (spalle e testa più chiare, gambe più scure) per dare volume;
// - metalli "cromati" come nelle armature disegnate: riflesso del cielo in alto, linea
//   scura dell'orizzonte, terra calda in basso e un filo bianco netto. Niente riflesso
//   della luce vera: sui pettorali piatti diventa una macchia bianca;
// - ombra tinta per materiale: calda sulla pelle, fredda sul metallo.
uniform float toon_shade : hint_range(0.0, 1.0) = 0.3;
uniform float toon_lit : hint_range(0.0, 2.0) = 0.6;
uniform float toon_ambient : hint_range(0.0, 1.0) = 0.72;
uniform vec3 toon_shadow_tint : source_color = vec3(0.80, 0.74, 0.92);
uniform vec3 skin_shadow_tint : source_color = vec3(0.98, 0.74, 0.74);
uniform vec3 metal_shadow_tint : source_color = vec3(0.66, 0.72, 0.86);
uniform float toon_rim : hint_range(0.0, 1.0) = 0.16;
uniform float sky_form : hint_range(0.0, 1.0) = 0.32;
uniform float metal_contrast : hint_range(0.0, 1.5) = 1.0;

uniform vec4 palette[16] : source_color;

varying vec3 slot_color;
varying float slot_shine;
varying float slot_kind; // 0 stoffa/cuoio, 1 pelle, 2 metallo
varying float neck_shadow;

void vertex() {
	int s = clamp(int(UV2.x + 0.5), 0, 15);
	slot_color = palette[s].rgb * UV2.y;
	slot_shine = palette[s].a;
	slot_kind = s == 0 ? 1.0 : (palette[s].a >= 0.4 ? 2.0 : 0.0);
	// ombra del mento sul collo (davanti, sotto la testa): stacca la testa dal corpo
	neck_shadow = s == 0 ? smoothstep(1.38, 1.46, VERTEX.y) * (1.0 - step(1.53, VERTEX.y)) : 0.0;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// cielo dall'alto: le superfici rivolte in su prendono più luce ambiente
	float sky = mix(1.0 - sky_form, 1.0 + sky_form * 0.35, smoothstep(-0.7, 0.8, wn.y));
	vec3 col = slot_color;
	float metal = step(1.5, slot_kind);
	if (metal > 0.5) {
		vec3 r = reflect(-VIEW, NORMAL);
		vec3 rw = normalize((INV_VIEW_MATRIX * vec4(r, 0.0)).xyz);
		float e = rw.y;
		float env = mix(0.55, 1.06, smoothstep(-0.5, 0.45, e));          // terra → cielo
		env -= 0.30 * (1.0 - smoothstep(0.0, 0.07, abs(e + 0.06)));       // linea dell'orizzonte
		float glint = smoothstep(0.62, 0.7, e) * (1.0 - smoothstep(0.86, 0.95, e));
		env = mix(1.0, env, metal_contrast);
		col = col * env + vec3(glint * 0.34 * slot_shine * metal_contrast);
		// il bordo del pezzo resta scuro come un tratto d'inchiostro morbido
		float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		col *= 1.0 - edge * 0.35;
	}
	col *= mix(vec3(1.0), vec3(0.66, 0.52, 0.56), neck_shadow);
	ALBEDO = col * sky;
	ROUGHNESS = 1.0;
	AO = toon_ambient;
	AO_LIGHT_AFFECT = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = ALBEDO * rim * (toon_rim + (1.0 - metal) * slot_shine * 0.25);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float shadow = LIGHT_IS_DIRECTIONAL ? smoothstep(0.25, 0.55, ATTENUATION) : 1.0;
	float falloff = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	float band = smoothstep(0.0, 0.07, ndl) * shadow;
	vec3 tint = slot_kind > 1.5 ? metal_shadow_tint : (slot_kind > 0.5 ? skin_shadow_tint : toon_shadow_tint);
	vec3 tone = mix(tint * toon_shade, vec3(1.0), band);
	DIFFUSE_LIGHT += LIGHT_COLOR * tone * falloff * toon_lit / PI;
}
