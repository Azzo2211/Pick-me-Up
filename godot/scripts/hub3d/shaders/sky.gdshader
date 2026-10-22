shader_type sky;

// Cielo del crepuscolo: zenit indaco, orizzonte caldo verso il sole,
// stelle che compaiono in alto e banchi di nubi accesi dal tramonto.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.06, 0.06, 0.15);
uniform vec3 upper : source_color = vec3(0.20, 0.15, 0.32);
uniform vec3 horizon : source_color = vec3(0.86, 0.48, 0.32);
uniform vec3 horizon_far : source_color = vec3(0.42, 0.30, 0.42);
uniform vec3 below : source_color = vec3(0.10, 0.08, 0.14);
uniform vec3 sun_color : source_color = vec3(1.0, 0.62, 0.32);
uniform vec3 cloud_color : source_color = vec3(0.55, 0.36, 0.40);
uniform float stars = 1.0;
uniform float aurora = 0.0;
uniform float sun_size = 0.9994;

void sky() {
	vec3 d = EYEDIR;
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(0.6, 0.15, -0.8));
	float toward_sun = clamp(dot(normalize(vec2(d.x, d.z) + 1e-5), normalize(vec2(sun_dir.x, sun_dir.z) + 1e-5)) * 0.5 + 0.5, 0.0, 1.0);
	float h = d.y;
	vec3 hor = mix(horizon_far, horizon, pow(toward_sun, 2.2));
	vec3 col = mix(hor, upper, smoothstep(0.0, 0.32, h));
	col = mix(col, zenith, smoothstep(0.25, 0.9, h));
	col = mix(col, below, smoothstep(0.0, -0.35, h));
	// alone del sole
	float s = max(dot(d, sun_dir), 0.0);
	col += sun_color * (pow(s, 8.0) * 0.35 + pow(s, 64.0) * 0.6);
	col += sun_color * smoothstep(sun_size, sun_size + 0.0004, s) * 6.0;
	// nubi stratificate vicino all'orizzonte
	if (h > -0.05) {
		vec2 cp = d.xz / (h + 0.18) * 1.6 + vec2(TIME * 0.004, 0.0);
		float c = smoothstep(0.5, 0.82, fbm(cp * vec2(0.6, 1.8)));
		float band = smoothstep(0.42, 0.04, h) * smoothstep(-0.05, 0.03, h);
		vec3 lit = mix(cloud_color * 0.6, sun_color * 0.9 + cloud_color * 0.3, pow(toward_sun, 3.0));
		col = mix(col, lit, c * band * 0.8);
	}
	// stelle
	if (stars > 0.0 && h > 0.05) {
		vec2 sp = vec2(atan(d.x, d.z) * 90.0, asin(clamp(h, -1.0, 1.0)) * 90.0);
		vec2 cell = floor(sp);
		float r = hash12(cell);
		vec2 off = hash22(cell) - 0.5;
		float star = smoothstep(0.06, 0.0, length(fract(sp) - 0.5 - off * 0.6)) * step(0.985, r);
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
		col += vec3(0.85, 0.88, 1.0) * star * twinkle * smoothstep(0.08, 0.5, h) * stars * (1.0 - pow(toward_sun, 4.0) * 0.8);
	}
	// aurora (base di livello massimo)
	if (aurora > 0.0 && h > 0.1) {
		float a = sin(atan(d.x, d.z) * 3.0 + fbm(d.xz * 3.0 + TIME * 0.03) * 4.0) * 0.5 + 0.5;
		float curtain = smoothstep(0.15, 0.35, h) * smoothstep(0.75, 0.4, h) * smoothstep(0.55, 1.0, a);
		col += mix(vec3(0.2, 0.8, 0.9), vec3(0.6, 0.35, 1.0), a) * curtain * 0.35 * aurora;
	}
	COLOR = col;
}
