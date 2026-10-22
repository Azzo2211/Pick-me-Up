shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

// Banchi di nebbia sotto e attorno all'isola: rumore che scorre lentamente.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 color_low : source_color = vec3(0.30, 0.22, 0.34);
uniform vec3 color_high : source_color = vec3(0.78, 0.52, 0.48);
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
	float shape = smoothstep(0.35, 0.75, n);
	vec2 uv = UV * 2.0 - 1.0;
	float fade = smoothstep(1.0, 1.0 - edge_fade, length(uv));
	ALBEDO = mix(color_low, color_high, smoothstep(0.4, 0.9, n));
	ALPHA = shape * fade * density;
}
