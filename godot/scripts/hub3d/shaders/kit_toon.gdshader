shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Corpi del kit (tools/character_kit): un'unica mesh vestita. La seconda UV dice di
// che "posto" della tavolozza è ogni faccia (pelle, stoffa, metallo...) e quanto è
// in ombra fissa; il colore di ogni posto lo dà l'eroe (palette, alfa = lucentezza).
// Luce a due toni come gli altri personaggi (vedi toon.gdshaderinc). Niente riflesso
// della luce: sui pettorali piatti diventa una macchia bianca; i metalli hanno solo la
// striscia chiara disegnata in fragment().
uniform float toon_shade : hint_range(0.0, 1.0) = 0.3;
uniform float toon_lit : hint_range(0.0, 2.0) = 0.6;
uniform float toon_ambient : hint_range(0.0, 1.0) = 0.72;
uniform vec3 toon_shadow_tint : source_color = vec3(0.80, 0.74, 0.92);
uniform float toon_rim : hint_range(0.0, 1.0) = 0.16;

uniform vec4 palette[16] : source_color;

varying vec3 slot_color;
varying float slot_shine;

void vertex() {
	int s = clamp(int(UV2.x + 0.5), 0, 15);
	slot_color = palette[s].rgb * UV2.y;
	slot_shine = palette[s].a;
}

void fragment() {
	ALBEDO = slot_color;
	ROUGHNESS = 1.0;
	AO = toon_ambient;
	AO_LIGHT_AFFECT = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// metalli: una striscia chiara verticale, come nelle armature disegnate
	float stripe = smoothstep(0.22, 0.3, NORMAL.x) * (1.0 - smoothstep(0.42, 0.52, NORMAL.x)) * smoothstep(-0.4, 0.1, NORMAL.y);
	EMISSION = ALBEDO * (rim * (toon_rim + slot_shine * 0.25) + stripe * step(0.4, slot_shine) * slot_shine * 0.55);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float shadow = LIGHT_IS_DIRECTIONAL ? smoothstep(0.25, 0.55, ATTENUATION) : 1.0;
	float falloff = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	float band = smoothstep(0.0, 0.07, ndl) * shadow;
	vec3 tone = mix(toon_shadow_tint * toon_shade, vec3(1.0), band);
	DIFFUSE_LIGHT += LIGHT_COLOR * tone * falloff * toon_lit / PI;
}
