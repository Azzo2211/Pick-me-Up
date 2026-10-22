shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

// Varco del Portale: un vuoto scuro al centro, energia viola e azzurra
// che ruota verso il bordo, scintille e un anello di luce.
uniform vec4 color_a : source_color = vec4(0.30, 0.55, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.62, 0.30, 1.0, 1.0);
uniform vec4 void_color : source_color = vec4(0.02, 0.01, 0.05, 1.0);
uniform float intensity = 1.0;
uniform float speed = 1.0;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv.y *= 1.0;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float t = TIME * speed;
	float swirl = sin(a * 5.0 + log(r + 0.05) * 9.0 - t * 2.4) * 0.5 + 0.5;
	float swirl2 = sin(-a * 3.0 + r * 12.0 - t * 1.7) * 0.5 + 0.5;
	vec3 energy = mix(color_a.rgb, color_b.rgb, swirl * 0.7 + swirl2 * 0.3);
	float rim_band = smoothstep(0.25, 0.92, r);
	vec3 col = mix(void_color.rgb, energy * (0.4 + 1.6 * swirl), rim_band);
	// scintille che cadono verso il centro
	vec2 sp = vec2(a * 6.0, log(r + 0.02) * 8.0 + t * 2.0);
	float spark = step(0.97, h21(floor(sp * 3.0))) * smoothstep(0.3, 0.0, length(fract(sp * 3.0) - 0.5));
	col += vec3(0.85, 0.8, 1.0) * spark * rim_band * 1.5;
	col += vec3(0.75, 0.85, 1.0) * smoothstep(0.86, 0.97, r) * smoothstep(1.0, 0.97, r) * 2.0;
	ALBEDO = col * intensity;
	ALPHA = 1.0 - smoothstep(0.975, 1.0, r);
}
