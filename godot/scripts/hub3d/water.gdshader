shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

// Acqua al crepuscolo: riflesso del cielo con increspature che scorrono.
uniform vec4 base_color : source_color = vec4(0.10, 0.13, 0.20, 1.0);
uniform vec4 sky_color : source_color = vec4(0.62, 0.40, 0.42, 1.0);
uniform vec4 foam_color : source_color = vec4(0.85, 0.80, 0.85, 1.0);
uniform float speed = 1.0;
uniform float stripes = 6.0;
uniform float alpha = 0.9;

void fragment() {
	float wave = sin((UV.y * stripes - TIME * speed) * 6.2831 + sin(UV.x * 9.0 + TIME) * 0.8) * 0.5 + 0.5;
	float ripple = sin(UV.x * 40.0 + UV.y * 25.0 + TIME * 2.0) * 0.5 + 0.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(base_color.rgb, sky_color.rgb, 0.35 + 0.5 * fres + ripple * 0.08);
	col = mix(col, foam_color.rgb, smoothstep(0.82, 1.0, wave) * 0.45);
	ALBEDO = col;
	ALPHA = alpha;
}
