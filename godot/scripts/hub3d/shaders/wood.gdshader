shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Legno: venature allungate e assi. "planks" > 0 disegna tavole lungo U.
// Rilievo per pixel: fessure tra le assi e venatura in leggero rilievo.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.33, 0.22, 0.14);
uniform vec3 dark_color : source_color = vec3(0.19, 0.12, 0.08);
uniform float planks = 0.0;
uniform float relief = 1.0;

void fragment() {
	vec2 uv = UV;
	float fw = length(fwidth(uv));
	float plank_id = planks > 0.0 ? floor(uv.y / planks) : 0.0;
	float grain = fbm(vec2(uv.x * 1.2 + plank_id * 3.7, uv.y * 14.0 + plank_id));
	float rings = mix(0.5, sin((uv.y * 30.0 + grain * 6.0)) * 0.5 + 0.5, aa_keep(30.0 / 6.28, fw));
	vec3 c = mix(dark_color, base_color, 0.55 + 0.45 * grain);
	c *= 0.9 + 0.12 * rings;
	c *= 0.88 + 0.2 * hash12(vec2(plank_id, 1.7));
	float height = (grain - 0.5) * 0.004 + (rings - 0.5) * 0.0015;
	if (planks > 0.0) {
		float f = fract(uv.y / planks);
		float seam = smoothstep(0.0, 0.07, f) * smoothstep(1.0, 0.93, f);
		c *= mix(0.5, 1.0, seam);
		height += seam * 0.008 * aa_keep(1.0 / planks, fw);
	}
	NORMAL = bump_normal(NORMAL, VERTEX, height, relief);
	vec3 tint = srgb_to_linear(COLOR.rgb);
	ALBEDO = c * tint;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.5;
}
