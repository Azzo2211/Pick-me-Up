shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled, shadows_disabled;

// Contorno dei modelli dipinti dell'utente (vedi painted_model.gdshader): come
// outline.gdshader, ma spinto un po' indietro lungo il raggio di vista. Le mesh
// ricavate dalle immagini hanno pezzi sottili uno sopra l'altro (tabarro sulle gambe):
// senza la spinta le loro linee interne spuntavano come graffi scuri camminando.
// Il bordo contro lo sfondo resta.
uniform float width_px = 1.3;
uniform float max_width = 0.012;
uniform vec3 line_color : source_color = vec3(0.11, 0.08, 0.09);
uniform float push = 0.06;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float units = length(mat3(MODELVIEW_MATRIX) * vec3(1.0, 0.0, 0.0));
	view.xyz += normalize(view.xyz) * push * units;
	vec4 clip = PROJECTION_MATRIX * view;
	vec3 n = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
	float len = length(dir);
	if (len > 0.0001) dir /= len;
	// tetto in unità del modello: i personaggi lontani non diventano macchie scure
	vec4 far_clip = PROJECTION_MATRIX * (view + vec4(n * max_width * units, 0.0));
	float cap = length(far_clip.xy / far_clip.w - clip.xy / clip.w);
	float off = min(width_px * 2.0 / VIEWPORT_SIZE.y, cap);
	clip.xy += dir * off * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = line_color;
}
