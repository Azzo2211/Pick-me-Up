shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled, shadows_disabled;

// Contorno dei pezzi del kit: come outline.gdshader, ma il colore del tratto viene
// dalla tavolozza dell'eroe (seconda UV) oppure da un colore fisso (capelli, volto).
uniform float width_px = 1.4;
uniform float max_width = 0.012;
uniform vec3 line_color : source_color = vec3(0.10, 0.06, 0.07);
uniform float tint = 0.35;
uniform bool use_palette = true;
uniform vec4 palette[16] : source_color;
uniform vec3 base_color = vec3(0.5);

varying vec3 base;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
	float len = length(dir);
	if (len > 0.0001) dir /= len;
	vec4 far_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * max_width, 1.0);
	float cap = length(far_clip.xy / far_clip.w - clip.xy / clip.w);
	float off = min(width_px * 2.0 / VIEWPORT_SIZE.y, cap);
	clip.xy += dir * off * clip.w;
	POSITION = clip;
	base = use_palette ? palette[clamp(int(UV2.x + 0.5), 0, 15)].rgb : base_color;
}

void fragment() {
	ALBEDO = mix(line_color, base * 0.32, tint);
}
