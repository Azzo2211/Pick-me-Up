shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

// Vortice del portale: spirale animata con nucleo luminoso.
uniform vec4 color_a : source_color = vec4(0.32, 0.72, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.62, 0.42, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float speed = 1.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float t = TIME * speed;
	float spiral = sin(a * 4.0 + r * 11.0 - t * 3.2) * 0.5 + 0.5;
	float spiral2 = sin(-a * 3.0 + r * 7.0 - t * 2.1) * 0.5 + 0.5;
	vec3 col = mix(color_a.rgb, color_b.rgb, spiral * 0.75 + spiral2 * 0.25);
	col += vec3(0.9, 0.97, 1.0) * pow(max(0.0, 1.0 - r), 2.5) * 0.9;
	col += vec3(1.0) * smoothstep(0.85, 0.98, r) * 0.35;
	ALBEDO = col * intensity;
	ALPHA = (1.0 - smoothstep(0.96, 1.0, r)) * clamp(0.75 + 0.25 * spiral, 0.0, 1.0);
}
