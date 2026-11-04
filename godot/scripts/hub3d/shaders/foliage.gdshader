shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

// Fogliame: colore dai vertici, variazione di tinta nel mondo, vento leggero.
// Con "leaf_tex" diventa un ciuffo di foglie ritagliato (alpha scissor).
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_texture = false;
uniform float sway = 0.035;
uniform vec3 dry_tint : source_color = vec3(0.62, 0.52, 0.22);
uniform float variation = 0.2;
uniform float brightness = 1.0;

varying vec3 wpos;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float t = TIME * 1.1 + world.x * 0.35 + world.z * 0.27;
	VERTEX.x += sin(t) * sway * h;
	VERTEX.z += cos(t * 0.83) * sway * h * 0.6;
	wpos = world;
}

void fragment() {
	vec3 c = srgb_to_linear(COLOR.rgb) * brightness;
	float n = vnoise(wpos.xz * 0.22 + vec2(wpos.y * 0.1));
	c = mix(c, srgb_to_linear(dry_tint) * (0.6 + 0.4 * length(c)), smoothstep(0.58, 0.9, n) * variation);
	if (use_texture) {
		vec4 t = texture(leaf_tex, UV);
		c *= t.rgb;
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = 0.45;
		// bordi delle foglie sfumati con l'MSAA (alpha to coverage): niente puntini che sfarfallano
		ALPHA_ANTIALIASING_EDGE = 0.35;
		ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_tex, 0));
	} else {
		c *= 0.86 + 0.28 * vnoise(wpos.xz * 4.0 + vec2(wpos.y * 3.0));
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.75;
}
