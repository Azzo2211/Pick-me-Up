shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

// Acqua stilizzata: strisce chiare che scorrono lungo UV.y.
uniform vec4 base_color : source_color = vec4(0.33, 0.70, 0.95, 1.0);
uniform vec4 foam_color : source_color = vec4(0.88, 0.97, 1.0, 1.0);
uniform float speed = 1.0;
uniform float stripes = 6.0;
uniform float alpha = 0.9;

void fragment() {
	float wave = sin((UV.y * stripes - TIME * speed) * 6.2831 + sin(UV.x * 9.0) * 0.8) * 0.5 + 0.5;
	float foam = smoothstep(0.78, 1.0, wave);
	ALBEDO = mix(base_color.rgb, foam_color.rgb, foam * 0.7);
	ALPHA = alpha;
}
