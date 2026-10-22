shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

// Bordo luminoso per evidenziare un edificio (overlay sul materiale).
uniform vec3 glow_color : source_color = vec3(1.0, 0.82, 0.5);
uniform float intensity = 0.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	ALBEDO = glow_color * (rim * 0.9 + 0.07) * intensity;
}
