shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

// Banchi di nebbia sotto e attorno all'isola: rumore che scorre lentamente.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 color_low : source_color = vec3(0.30, 0.22, 0.34);
uniform vec3 color_high : source_color = vec3(0.78, 0.52, 0.48);
// luce del sole sui banchi: si accendono dalla parte da cui arriva (direzione sul piano, verso il sole)
uniform vec3 color_glow : source_color = vec3(1.0, 0.69, 0.44);
uniform vec2 sun_xz = vec2(-0.47, 0.88);
uniform float glow = 0.7;
uniform float density = 0.75;
uniform float scale = 0.035;
uniform float speed = 0.012;
uniform float edge_fade = 0.42;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * scale + vec2(TIME * speed, TIME * speed * 0.4);
	float n = fbm(p) * 0.7 + fbm(p * 2.7 - vec2(TIME * speed * 1.7, 0.0)) * 0.3;
	float shape = smoothstep(0.3, 0.72, n);
	vec2 uv = UV * 2.0 - 1.0;
	float fade = smoothstep(1.0, 1.0 - edge_fade, length(uv));
	vec3 col = mix(color_low, color_high, smoothstep(0.4, 0.9, n));
	// i banchi più gonfi prendono la luce calda sul lato del sole: il mare di nubi ha profondità
	float toward = clamp(dot(normalize(wpos.xz + vec2(0.001)), normalize(sun_xz)) * 0.5 + 0.5, 0.0, 1.0);
	float crest = smoothstep(0.55, 0.95, n);
	col = mix(col, color_glow, glow * crest * (0.25 + 0.75 * toward * toward));
	ALBEDO = col;
	ALPHA = shape * fade * density;
}
