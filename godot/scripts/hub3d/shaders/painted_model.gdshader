shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Modelli 3D dell'utente con il colore dipinto nella texture (la Guardia, il Guerriero:
// assets/characters/user/): la luce e le ombre sono già nel disegno, quindi qui la luce
// vera conta poco. Banda morbida (niente gradino netto come nel toon: sul disegno
// farebbe macchie) e poca luce ambiente (quella azzurra del cielo sbiadiva il disegno), così il modello
// resta uguale al foglio.
// Entrambe le facce: le mesh ricavate dalle immagini non hanno un dentro e un fuori.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float lit : hint_range(0.0, 2.0) = 0.34;
uniform float shade : hint_range(0.0, 1.0) = 0.72;
uniform float ambient : hint_range(0.0, 1.0) = 0.24;
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.82, 0.94);
uniform float rim : hint_range(0.0, 1.0) = 0.08;
// la luce azzurra del cielo e il tonemap sbiadiscono i colori: un filo di saturazione in più
uniform float saturation : hint_range(0.0, 2.0) = 1.3;
// mezzitoni un po' più scuri: l'armatura dipinta resta d'acciaio e non diventa bianca
uniform float contrast : hint_range(0.5, 2.0) = 1.15;

// Il modello è un bassorilievo (spesso solo come il disegno): le braccia abbassate
// finiscono dentro il mantello. Il verde del colore dei punti dice di quanto (misurato
// da tools/character_kit/import_user_model.py, in unità di arm_front) e qui il braccio
// si avvicina alla telecamera lungo il raggio di vista: stessa posizione sullo
// schermo, ma davanti al mantello. Solo guardando il personaggio da davanti: da
// dietro il mantello lo copre.
uniform float arm_front : hint_range(0.0, 0.5) = 0.3;
// Capelli dipinti (alfa sotto 1 nella texture, vedi tools/character_kit/sheet_to_model.py)
// tinti col colore di capelli dell'eroe, tenendo luci e ombre del disegno.
uniform float hair_recolor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 hair_color : source_color = vec3(0.23, 0.16, 0.12);
uniform float hair_ref = 0.19; // luminanza media dei capelli dipinti (come li legge il renderer Compatibility)

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float pull = COLOR.g * arm_front;
	if (pull > 0.0001) {
		vec3 fwd = normalize(mat3(MODELVIEW_MATRIX) * vec3(0.0, 0.0, 1.0));
		float facing = dot(fwd, normalize(-view.xyz));
		float units = length(mat3(MODELVIEW_MATRIX) * vec3(1.0, 0.0, 0.0));
		view.xyz -= normalize(view.xyz) * pull * units * smoothstep(-0.05, 0.35, facing);
	}
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 col = tex.rgb;
	float hair = clamp((1.0 - tex.a) / 0.784, 0.0, 1.0) * hair_recolor;
	if (hair > 0.0) {
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, clamp(hair_color * (lum / hair_ref), 0.0, 1.0), hair);
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	ALBEDO = pow(clamp(mix(vec3(l), col, saturation), 0.0, 1.0), vec3(contrast));
	ROUGHNESS = 1.0;
	AO = ambient;
	AO_LIGHT_AFFECT = 0.0;
	float r = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	EMISSION = ALBEDO * r * rim;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float shadow = LIGHT_IS_DIRECTIONAL ? smoothstep(0.2, 0.6, ATTENUATION) : 1.0;
	float falloff = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	float band = smoothstep(-0.15, 0.35, ndl) * shadow;
	vec3 tone = mix(shadow_tint * shade, vec3(1.0), band);
	DIFFUSE_LIGHT += LIGHT_COLOR * tone * falloff * lit / PI;
}
