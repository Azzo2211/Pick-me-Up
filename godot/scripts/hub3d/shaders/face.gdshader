shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Volto anime disegnato sulla testa base: occhi grandi con iride a sfumatura,
// riflessi e ciglia, sopracciglia, naso accennato e bocca. Le UV sono le
// coordinate frontali della sfera unitaria della testa (x a destra, y in alto),
// l'alfa del colore dei vertici vale 1 sul davanti e 0 sul retro.
// I tre volti del foglio (bello, comune, rude) cambiano solo questi parametri.
#include "res://scripts/hub3d/shaders/toon.gdshaderinc"

uniform vec3 iris_color : source_color = vec3(0.35, 0.55, 0.85);
uniform vec3 brow_color : source_color = vec3(0.22, 0.16, 0.12);
uniform vec3 line_color : source_color = vec3(0.17, 0.09, 0.08);
uniform float eye_w = 0.15;
uniform float eye_h = 0.16;
uniform float eye_x = 0.36;
uniform float eye_y = -0.10;
uniform float eye_tilt = 0.0;
uniform float lash = 1.0;
uniform float lash_flick = 0.0;
uniform float lower_lash = 0.5;
uniform float crease = 0.35;
uniform float brow_thick = 0.022;
uniform float brow_gap = 0.09;
uniform float brow_tilt = 0.0;
uniform float brow_arch = 0.03;
uniform float mouth_y = -0.62;
uniform float mouth_w = 0.09;
uniform float mouth_curve = 0.015;
uniform float lips = 0.0;
uniform float blush = 0.0;
uniform float age_lines = 0.0;
uniform float stubble = 0.0;
uniform vec3 stubble_color : source_color = vec3(0.2, 0.15, 0.1);
uniform float scar = 0.0;
uniform float freckles = 0.0;
uniform float closed = 0.0;

varying vec2 fp;
varying float front;

void vertex() {
	fp = UV;
	front = COLOR.a;
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

// Un occhio: restituisce colore premoltiplicato (rgb) e copertura (a).
vec4 eye(vec2 p, float side, float px) {
	vec2 q = p - vec2(side * eye_x, eye_y);
	q.x *= side; // +x verso l'angolo esterno
	q.y -= eye_tilt * q.x;
	vec2 e = q / vec2(eye_w, eye_h);
	float scale = min(eye_w, eye_h);
	float r = length(e);
	vec4 o = vec4(0.0);
	if (closed > 0.5) {
		float y = -0.15 - 0.25 * e.x * e.x;
		float d = abs(e.y - y) * scale - 0.006;
		d = max(d, (abs(e.x) - 1.0) * scale);
		float a = cover(d, px);
		return vec4(line_color * a, a);
	}
	// bianco dell'occhio, con l'ombra della palpebra in alto
	float white = cover((r - 1.0) * scale, px);
	vec3 col = mix(vec3(0.98, 0.97, 0.99), vec3(0.80, 0.80, 0.90), smoothstep(0.1, 0.75, e.y));
	// iride alta e grande, scura in alto e chiara in basso, con bordo scuro
	vec2 ic = vec2(-0.04, -0.04);
	vec2 ir = vec2(0.62, 0.84);
	float id = length((e - ic) / ir);
	float iris = cover((id - 1.0) * scale * 0.62, px);
	float t = (e.y - ic.y) / ir.y;
	vec3 ic_col = mix(iris_color * 1.28 + vec3(0.06), iris_color * 0.42, smoothstep(-0.7, 0.75, t));
	ic_col = mix(ic_col, iris_color * 0.3, smoothstep(0.78, 0.98, id));
	col = mix(col, ic_col, iris);
	float pupil = cover((length((e - ic - vec2(0.0, 0.05)) / vec2(0.27, 0.4)) - 1.0) * scale * 0.3, px);
	col = mix(col, iris_color * 0.16, pupil);
	// riflessi
	float h1 = cover((length(e - ic - vec2(-0.24, 0.32)) - 0.2) * scale, px);
	float h2 = cover((length(e - ic - vec2(0.26, -0.4)) - 0.09) * scale, px);
	col = mix(col, vec3(1.0), max(h1, h2 * 0.85));
	o = vec4(col * white, white);
	// ciglia superiori: tratto spesso sul bordo alto, più spesso verso l'esterno
	float th = (0.13 + 0.09 * max(e.x, 0.0)) * lash;
	float upper = smoothstep(-0.25, 0.05, e.y + 0.25 * e.x);
	float lash_d = (abs(r - 1.0 - th * 0.15) - th * 0.5) * scale;
	float lash_a = cover(lash_d, px) * upper;
	// codina all'angolo esterno
	if (lash_flick > 0.0) {
		float fd = seg(e, vec2(0.82, 0.38), vec2(1.18 + 0.15 * lash_flick, 0.62)) * scale - 0.006 * lash_flick;
		lash_a = max(lash_a, cover(fd, px));
	}
	// ciglia inferiori: tratto sottile verso l'esterno
	float lower = (1.0 - smoothstep(-0.35, 0.0, e.y)) * smoothstep(-0.4, 0.2, e.x);
	float low_a = cover((abs(r - 1.0) - 0.035) * scale, px) * lower * lower_lash;
	// piega della palpebra sopra l'occhio
	vec2 ce = (e - vec2(0.05, 0.18)) / vec2(1.05, 1.0);
	float crease_a = cover((abs(length(ce) - 1.12) - 0.025) * scale, px) * smoothstep(0.55, 0.85, e.y) * step(-0.5, e.x) * step(e.x, 0.95) * crease;
	vec3 lash_col = line_color;
	o.rgb = mix(o.rgb, lash_col * max(lash_a, low_a), max(lash_a, low_a));
	o.a = max(o.a, max(lash_a, low_a));
	o.rgb = mix(o.rgb, lash_col * crease_a, crease_a * (1.0 - o.a));
	o.a = max(o.a, crease_a);
	return o;
}

float brow(vec2 p, float side, float px) {
	vec2 q = p - vec2(side * eye_x, eye_y + eye_h + brow_gap);
	q.x *= side;
	float bw = eye_w * 1.2;
	float x = clamp(q.x / bw, -1.0, 1.0);
	float y = brow_arch * (1.0 - x * x) + brow_tilt * x * 0.06;
	float th = brow_thick * (1.05 - 0.45 * (x * 0.5 + 0.5));
	float d = abs(q.y - y) - th;
	d = max(d, abs(q.x) - bw);
	return cover(d, px);
}

void fragment() {
	vec3 skin = COLOR.rgb;
	vec3 col = skin;
	float px = max(fwidth(fp.x), fwidth(fp.y)) * 0.9;
	float f = smoothstep(0.25, 0.55, front);
	float feature = 0.0;
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
		// naso: solo un'ombra breve
		float nose = cover(seg(fp, vec2(0.0, -0.3), vec2(0.035, -0.39)) - 0.007, px);
		col = mix(col, skin * 0.72, nose * 0.8 * f);
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
		// bocca: piccola linea curva, un po' più marcata al centro
		float mx = clamp(fp.x / mouth_w, -1.0, 1.0);
		float my = mouth_y + mouth_curve * (mx * mx) * 1.0;
		float md = abs(fp.y - my) - 0.0085 * (1.0 - 0.45 * mx * mx);
		md = max(md, abs(fp.x) - mouth_w);
		float mouth = cover(md, px);
		col = mix(col, mix(line_color, skin * 0.55, 0.35), mouth * f);
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
