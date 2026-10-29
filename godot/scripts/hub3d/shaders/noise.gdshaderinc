// Rumore procedurale e utilità condivise dagli shader del mondo.

// Normalizzazione che non produce NaN su vettori nulli.
vec3 safe_normalize(vec3 v) {
	float l = length(v);
	return l > 1e-8 ? v / l : vec3(0.0, 1.0, 0.0);
}

// Antialias del rumore: quanto tenere un dettaglio di frequenza `freq` quando
// un pixel copre `fw` unità (fwidth delle coordinate). I dettagli più fini di
// un pixel sfumano verso il loro valore medio invece di sfarfallare/sgranare.
float aa_keep(float freq, float fw) {
	return 1.0 - smoothstep(0.25, 0.8, freq * fw);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(5.3, 11.7);
		a *= 0.5;
	}
	return v / 0.875;
}

// Voronoi: x = distanza dal centro, y = distanza dal bordo della cella, zw = id cella.
vec4 voronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g) * 0.85 + 0.075;
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; }
		}
	}
	float edge = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash22(n + g) * 0.85 + 0.075;
			vec2 r = g + o - f;
			vec2 dr = r - mr;
			if (dot(dr, dr) > 0.00001) edge = min(edge, dot(0.5 * (mr + r), normalize(dr)));
		}
	}
	return vec4(sqrt(md), edge, n + mg);
}

vec3 srgb_to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(64.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// Rilievo per pixel: inclina la normale (spazio vista) seguendo il gradiente in
// screen space di un'altezza h espressa in unità di mondo. strength 1 = pendenze
// reali; i dettagli troppo fini per lo schermo vanno attenuati prima (aa_keep).
// Derivate "fini" (per pixel) dove esistono: con quelle grossolane il rilievo
// cambia a blocchi di 2x2 pixel e i bordi netti diventano a scalini.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define DFDX dFdx
#define DFDY dFdy
#else
#define DFDX dFdxFine
#define DFDY dFdyFine
#endif

vec3 bump_normal(vec3 n, vec3 view_pos, float h, float strength) {
	vec3 dpdx = DFDX(view_pos);
	vec3 dpdy = DFDY(view_pos);
	float dhdx = DFDX(h);
	float dhdy = DFDY(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	vec3 g = abs(det) * n - strength * grad;
	float len = length(g);
	// pixel degeneri (triangolo visto di taglio): niente NaN, si tiene la normale
	return (len > 1e-12 && abs(det) > 1e-14) ? g / len : n;
}
