shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Volto anime disegnato sulla testa base del kit: occhi grandi con iride a
// sfumatura, riflessi e ciglia, sopracciglia, naso accennato e bocca. Le UV sono
// coordinate frontali della testa (0 = altezza degli occhi, 1 = 10 cm), la seconda
// UV (y) vale 1 sul davanti e 0 sui lati e dietro.
// I tre volti del foglio (bello, comune, rude) cambiano solo questi parametri.
#include "res://scripts/hub3d/shaders/toon.gdshaderinc"

uniform vec3 iris_color : source_color = vec3(0.35, 0.55, 0.85);
uniform vec3 brow_color : source_color = vec3(0.22, 0.16, 0.12);
uniform vec3 line_color : source_color = vec3(0.17, 0.09, 0.08);
// occhio: mezza larghezza e mezza altezza dell'apertura, raggio dell'iride (tutto in
// unità del volto). Gli uomini del foglio hanno occhi stretti e taglienti, l'iride
// tagliata dalla palpebra; le donne occhi più aperti e ciglia lunghe.
uniform float eye_w = 0.17;
uniform float eye_h = 0.085;
uniform float iris_r = 0.085;
uniform float eye_x = 0.38;
uniform float eye_y = 0.0;
uniform float eye_tilt = 0.12;
uniform float lid_th = 0.02;
uniform float lash = 1.0;
uniform float lash_flick = 0.0;
uniform float lower_lash = 0.5;
uniform float crease = 0.35;
uniform float brow_thick = 0.022;
uniform float brow_gap = 0.06;
uniform float brow_tilt = 0.0;
uniform float brow_arch = 0.02;
uniform float mouth_y = -0.6;
uniform float mouth_w = 0.09;
uniform float mouth_curve = 0.0;
uniform float lips = 0.0;
uniform float blush = 0.0;
uniform float age_lines = 0.0;
uniform float stubble = 0.0;
uniform vec3 stubble_color : source_color = vec3(0.2, 0.15, 0.1);
uniform float scar = 0.0;
uniform float freckles = 0.0;
uniform float closed = 0.0;

uniform vec3 skin_color : source_color = vec3(0.96, 0.83, 0.72);

varying vec2 fp;
varying float front;

void vertex() {
	fp = UV;
	front = UV2.y;
	// ombre morbide come negli anime: la normale si piega verso quella di una sfera
	vec3 ball = normalize(VERTEX - vec3(0.0, 0.15, -0.02));
	NORMAL = normalize(mix(NORMAL, ball, 0.65));
}

float cover(float d, float px) {
	return 1.0 - smoothstep(-px, px, d);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Palpebre dell'occhio (q in unità del volto, x verso l'angolo esterno): altezza del
// bordo alto e di quello basso alla x data. L'angolo interno sta un po' più in basso
// di quello esterno (eye_tilt), il bordo alto è più dritto di quello basso.
float lid_up(float t) {
	float c = clamp(t, -1.0, 1.0);
	return eye_h * ((1.0 - c * c) * (1.0 + 0.18 * c) * 0.92 + 0.08) + eye_tilt * eye_h * c * 0.5 - eye_h * 0.08 * (1.0 - c);
}

float lid_low(float t) {
	float c = clamp(t, -1.0, 1.0);
	return -eye_h * 0.72 * pow(max(1.0 - c * c, 0.0), 0.75) + eye_tilt * eye_h * c * 0.5 - eye_h * 0.08 * (1.0 - c);
}

// Un occhio: restituisce colore premoltiplicato (rgb) e copertura (a).
vec4 eye(vec2 p, float side, float px) {
	vec2 q = p - vec2(side * eye_x, eye_y);
	q.x *= side; // +x verso l'angolo esterno
	float t = q.x / eye_w;
	float yu = lid_up(t);
	float yl = lid_low(t);
	if (closed > 0.5) {
		float y = mix(yl, yu, 0.25);
		float d = max(abs(q.y - y) - lid_th * 0.45, (abs(t) - 1.05) * eye_w);
		float a = cover(d, px);
		return vec4(line_color * a, a);
	}
	// apertura dell'occhio
	float inside = max(max(q.y - yu, yl - q.y), (abs(t) - 1.0) * eye_w * 0.5);
	float white = cover(inside, px);
	float lid_shade = smoothstep(yu - eye_h * 0.7, yu, q.y);
	vec3 col = mix(vec3(0.97, 0.96, 0.98), vec3(0.74, 0.72, 0.84), lid_shade);
	// iride rotonda, tagliata dalle palpebre: scura in alto, chiara in basso
	vec2 ic = vec2(-0.06 * eye_w, (yu + yl) * 0.5 + eye_h * 0.12);
	vec2 d_i = q - ic;
	float id = length(d_i) / iris_r;
	float iris = cover((id - 1.0) * iris_r, px);
	float tv = d_i.y / iris_r;
	vec3 ic_col = mix(iris_color * 1.3 + vec3(0.05), iris_color * 0.38, smoothstep(-0.75, 0.55, tv));
	ic_col = mix(ic_col, iris_color * 0.22, smoothstep(0.8, 0.97, id));
	col = mix(col, ic_col, iris);
	float pupil = cover((length(d_i / vec2(0.36, 0.5)) / iris_r - 1.0) * iris_r * 0.4, px);
	col = mix(col, iris_color * 0.12, pupil * 0.9);
	// ombra della palpebra sull'iride
	col = mix(col, col * 0.62, smoothstep(yu - eye_h * 0.55, yu, q.y) * iris);
	// riflessi
	float h1 = cover(length(d_i - vec2(-0.32, 0.28) * iris_r) - iris_r * 0.24, px);
	float h2 = cover(length(d_i - vec2(0.34, -0.42) * iris_r) - iris_r * 0.11, px);
	col = mix(col, vec3(1.0), max(h1, h2 * 0.8));
	vec4 o = vec4(col * white, white);
	// palpebra superiore: tratto spesso sul bordo alto, più spesso e allungato verso
	// l'esterno; con lash_flick la punta si piega all'insù (ciglia femminili)
	float te = clamp(t, -1.0, 1.22);
	float th = lid_th * lash * (0.55 + 0.75 * smoothstep(-0.6, 1.0, t));
	float yline = lid_up(te) + (t > 1.0 ? (t - 1.0) * eye_h * (lash_flick * 1.6 - 0.5) : 0.0);
	float lash_d = max(max(yline - th * 0.25 - q.y, q.y - yline - th), max(-1.0 - t, t - 1.22) * eye_w);
	float lash_a = cover(lash_d, px);
	// palpebra inferiore: tratto sottile solo verso l'esterno
	float low_d = max(abs(q.y - yl) - lid_th * 0.22, max(0.05 - t, t - 1.0) * eye_w);
	float low_a = cover(low_d, px) * lower_lash * smoothstep(0.05, 0.5, t);
	// piega della palpebra sopra l'occhio
	float yc = lid_up(clamp(t * 0.95, -1.0, 1.0)) + eye_h * 0.38 + lid_th;
	float crease_d = max(abs(q.y - yc) - lid_th * 0.16, max(-0.45 - t, t - 0.95) * eye_w);
	float crease_a = cover(crease_d, px) * crease;
	vec3 lash_col = line_color;
	float la = max(lash_a, low_a);
	o.rgb = mix(o.rgb, lash_col * la, la);
	o.a = max(o.a, la);
	o.rgb = mix(o.rgb, lash_col * crease_a * 0.8, crease_a * (1.0 - o.a));
	o.a = max(o.a, crease_a * 0.8);
	return o;
}

// Sopracciglio: tratto dritto e affusolato verso l'esterno; brow_tilt alza la coda
// (sguardo deciso) o l'abbassa, brow_arch lo incurva.
float brow(vec2 p, float side, float px) {
	vec2 q = p - vec2(side * eye_x, eye_y + eye_h + brow_gap);
	q.x *= side;
	float bw = eye_w * 1.18;
	float x = clamp((q.x + eye_w * 0.08) / bw, -1.0, 1.0);
	float y = brow_arch * (1.0 - x * x) + brow_tilt * 0.05 * x - 0.012 * (1.0 - x) * (1.0 - x) * 0.25;
	float th = brow_thick * (1.0 - 0.55 * smoothstep(-0.4, 1.0, x));
	float d = abs(q.y - y) - th;
	d = max(d, abs(q.x + eye_w * 0.08) - bw);
	return cover(d, px);
}

void fragment() {
	vec3 skin = skin_color;
	vec3 col = skin;
	float px = max(fwidth(fp.x), fwidth(fp.y)) * 0.9;
	float f = smoothstep(0.25, 0.55, front);
	float feature = 0.0;
	// ombra portata dei capelli sulla fronte e sulle tempie, come nel cel shading
	float hair_sh = smoothstep(0.34, 0.5, fp.y + 0.12 * abs(fp.x)) * smoothstep(0.1, 0.4, front + 0.2);
	col = mix(col, col * vec3(0.84, 0.74, 0.76), hair_sh * 0.6);
	if (f > 0.0) {
		// rossore sulle guance
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			float bl = 1.0 - smoothstep(0.0, 1.0, length((fp - vec2(s * 0.42, -0.36)) / vec2(0.14, 0.065)));
			col = mix(col, vec3(0.96, 0.52, 0.52), bl * blush * 0.45 * f);
		}
		// barba appena fatta: ombra leggera su mascella e labbro, come negli anime
		if (stubble > 0.0) {
			float jaw = 1.0 - smoothstep(-0.56, -0.4, fp.y);
			float lip = (1.0 - smoothstep(0.0, 1.0, length((fp - vec2(0.0, mouth_y + 0.07)) / vec2(0.16, 0.035))));
			float region = max(jaw * (1.0 - smoothstep(0.55, 0.75, abs(fp.x))), lip);
			col = mix(col, mix(skin, stubble_color, 0.55), region * stubble * 0.38 * f);
		}
		// lentiggini sul naso e sulle guance
		if (freckles > 0.0) {
			vec2 cell = floor(fp * 34.0);
			vec2 jit = vec2(hash(cell), hash(cell + 7.1));
			float dot_d = length(fract(fp * 34.0) - jit) - 0.12;
			float zone = 1.0 - smoothstep(0.0, 1.0, length((fp - vec2(0.0, -0.28)) / vec2(0.55, 0.12)));
			col = mix(col, skin * 0.72, step(dot_d, 0.0) * step(0.55, hash(cell + 3.3)) * zone * freckles * f);
		}
		// naso come nel foglio: un tratto leggero lungo il lato del naso e la punta
		float bridge = cover(seg(fp, vec2(0.045, -0.1), vec2(0.06, -0.33)) - 0.004, px);
		float tip = cover(seg(fp, vec2(0.065, -0.34), vec2(0.015, -0.385)) - 0.0065, px);
		col = mix(col, skin * 0.74, bridge * 0.45 * f);
		col = mix(col, mix(skin * 0.62, line_color, 0.3), tip * 0.85 * f);
		// rughe dell'età
		if (age_lines > 0.0) {
			for (int i = 0; i < 2; i++) {
				float s = i == 0 ? -1.0 : 1.0;
				float under = cover(abs(length((fp - vec2(s * eye_x, eye_y - 0.02)) / vec2(eye_w * 1.05, eye_h * 1.35)) - 1.0) * 0.1 - 0.004, px) * step(fp.y, eye_y - eye_h * 0.9);
				float fold = cover(seg(fp, vec2(s * 0.15, -0.42), vec2(s * 0.21, -0.6)) - 0.005, px);
				col = mix(col, skin * 0.68, (under * 0.6 + fold * 0.7) * age_lines * f);
			}
		}
		// cicatrice sulla guancia
		if (scar > 0.0) {
			float sc = cover(seg(fp, vec2(0.2, 0.06), vec2(0.5, -0.34)) - 0.009, px);
			col = mix(col, mix(skin * 0.7, vec3(0.75, 0.42, 0.42), 0.4), sc * scar * f);
		}
		// bocca: un tratto corto, più marcato al centro, e l'ombra del labbro di sotto
		float mx = clamp(fp.x / mouth_w, -1.0, 1.0);
		float my = mouth_y + mouth_curve * (mx * mx);
		float md = abs(fp.y - my) - 0.0075 * (1.0 - 0.5 * mx * mx);
		md = max(md, abs(fp.x) - mouth_w);
		float mouth = cover(md, px);
		col = mix(col, mix(line_color, skin * 0.55, 0.3), mouth * f);
		float lip_sh = cover(seg(fp, vec2(-mouth_w * 0.4, mouth_y - 0.075), vec2(mouth_w * 0.4, mouth_y - 0.075)) - 0.004, px);
		col = mix(col, skin * 0.8, lip_sh * 0.55 * f);
		if (lips > 0.0) {
			float lip = 1.0 - smoothstep(0.0, 1.0, length((fp - vec2(0.0, mouth_y - 0.03)) / vec2(mouth_w * 0.8, 0.028)));
			col = mix(col, vec3(0.86, 0.48, 0.48), lip * lips * 0.4 * f);
		}
		// sopracciglia e occhi
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			float b = brow(fp, s, px);
			col = mix(col, brow_color, b * f);
			vec4 e = eye(fp, s, px);
			col = mix(col, e.rgb / max(e.a, 0.0001), e.a * f);
			feature = max(feature, e.a * f);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	AO = toon_ambient;
	AO_LIGHT_AFFECT = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// gli occhi restano luminosi anche dal lato in ombra
	EMISSION = ALBEDO * (rim * toon_rim + feature * 0.28);
}
